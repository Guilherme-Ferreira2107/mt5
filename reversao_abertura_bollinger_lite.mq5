//+------------------------------------------------------------------+
//| reversao_abertura_bollinger_lite.mq5                              |
//| EA lite de reversao pelas Bandas de Bollinger, variante por dois  |
//| fechamentos. Compra quando o candle penultimo fecha abaixo da    |
//| banda inferior e o candle anterior fecha de volta acima dela;    |
//| vende no espelho com a banda superior. Sem stop de protecao      |
//| separado: a saida (com ganho ou prejuizo) acontece quando o      |
//| preco atinge a banda oposta ou a media, recalculadas a cada      |
//| novo candle - exceto se UseFixedStopTarget ligar SL/TP fixos.    |
//| Duas travas de seguranca adicionais: MaxLossPercent fecha a      |
//| mercado se a perda flutuante atingir X% do saldo (checado a      |
//| cada tick); OppositeCandlesToExit fecha se N candles fechados    |
//| seguidos forem contra a direcao do trade (checado a cada candle).|
//| UseADXFilter so libera entrada com ADX estritamente abaixo de    |
//| ADXThreshold - mean reversion tende a falhar com tendencia forte.|
//| Com uma posicao aberta, o mesmo ADXThreshold tambem fecha a      |
//| mercado se o ADX subir a esse nivel ou acima dele (tendencia     |
//| fortalecendo depois da entrada), sem excecao de enfraquecimento. |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Teste primeiro em conta demo.         |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input int BandsPeriod = 20;                 // Periodo das Bandas de Bollinger
input double BandsDeviation = 2.0;          // Desvios-padrao das bandas
input ENUM_APPLIED_PRICE BandsPrice = PRICE_CLOSE;
input bool UseMiddleBandTarget = true;      // saida na media da banda; false usa a banda oposta
input int OppositeCandlesToExit = 4;        // fecha a posicao ao contar N candles fechados seguidos contra o trade (0 desativa)

input double RiskPercent = 1.0;              // % do saldo usado para dimensionar o lote
input double MaxLossPercent = 1.0;           // trava de seguranca: fecha a posicao se a perda flutuante atingir X% do saldo
input bool AutoTrade = false;                // precisa ligar explicitamente
input ulong MagicNumber = 20260721;
input bool DebugLog = true;

input bool UseMAFilter = false;              // compra acima da MA e venda abaixo da MA
input int MAPeriod = 50;
input ENUM_MA_METHOD MAMethod = MODE_SMA;

input bool UseADXFilter = true;              // so libera entrada com ADX fraco ou enfraquecendo
input int ADXPeriod = 14;
input double ADXThreshold = 25.0;            // ADX abaixo disso ja libera, mesmo sem estar enfraquecendo

input bool UseFixedStopTarget = false;       // liga SL/TP fixos em pontos; desliga a saida dinamica
input double FixedStopPoints = 100.0;
input double FixedTargetPoints = 150.0;

input bool UseTradingWindow = false;
input string TradingWindowStart = "16:00";  // hora do servidor
input string TradingWindowEnd = "19:00";

CTrade trade;
int maHandle = INVALID_HANDLE;
int bandsHandle = INVALID_HANDLE;
int adxHandle = INVALID_HANDLE;
int oppositeStreak = 0;

bool ParseTimeToMinutes(const string time_text, int &minutes_total)
{
   datetime parsed = StringToTime("2000.01.01 " + time_text);
   if (parsed == 0)
      return false;

   MqlDateTime ts;
   TimeToStruct(parsed, ts);
   minutes_total = ts.hour * 60 + ts.min;
   return true;
}

bool IsWithinTradingWindow()
{
   if (!UseTradingWindow)
      return true;

   int startMinutes, endMinutes;
   if (!ParseTimeToMinutes(TradingWindowStart, startMinutes) ||
       !ParseTimeToMinutes(TradingWindowEnd, endMinutes))
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int nowMinutes = now.hour * 60 + now.min;

   if (startMinutes <= endMinutes)
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
   return nowMinutes >= startMinutes || nowMinutes <= endMinutes;
}

double LotsForRisk(const double stopDistance)
{
   if (stopDistance <= 0.0 || RiskPercent <= 0.0)
      return 0.0;

   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;

   double lots = riskAmount / (stopDistance / tickSize * tickValue);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0.0)
      step = 0.01;

   int decimals = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   lots = NormalizeDouble(MathFloor(lots / step) * step, decimals);
   if (lots > maxLot)
      lots = NormalizeDouble(MathFloor(maxLot / step) * step, decimals);
   return lots < minLot ? 0.0 : lots;
}

bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;
      return true;
   }
   return false;
}

// Fecha a posicao se o ADX subir acima de ADXThreshold enquanto o trade esta aberto:
// tendencia fortalecendo depois da entrada e cenario ruim pra reversao a media. So
// atua se UseADXFilter estiver ligado. Roda uma vez por candle novo.
void ManageADXExit()
{
   if (!UseADXFilter)
      return;

   double adxBuf[1];
   if (CopyBuffer(adxHandle, MAIN_LINE, 1, 1, adxBuf) <= 0)
   {
      Print("ERRO: CopyBuffer do ADX (saida) falhou. GetLastError=", GetLastError());
      return;
   }
   double adx1 = adxBuf[0];
   if (adx1 < ADXThreshold)
      return;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      if (DebugLog)
         Print("SAIDA POR ADX: ticket=", ticket, " adx1=", adx1, " limite=", ADXThreshold);
      if (!trade.PositionClose(ticket))
         Print("ERRO ao fechar posicao pelo ADX: retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());

      break; // no maximo 1 posicao por simbolo/magic neste EA
   }
}

// So monitora quando a saida e dinamica; com UseFixedStopTarget=true a corretora
// ja controla SL/TP e esta funcao nao mexe na posicao.
void ManageDynamicExit(const double middleBand1, const double upperBand1, const double lowerBand1)
{
   if (UseFixedStopTarget)
      return;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool shouldClose = false;
      double level = 0.0;
      if (posType == POSITION_TYPE_BUY)
      {
         level = UseMiddleBandTarget ? middleBand1 : upperBand1;
         shouldClose = bid >= level;
      }
      else if (posType == POSITION_TYPE_SELL)
      {
         level = UseMiddleBandTarget ? middleBand1 : lowerBand1;
         shouldClose = ask <= level;
      }

      if (DebugLog)
         Print("SAIDA DINAMICA CHECK: ticket=", ticket,
               " tipo=", EnumToString((ENUM_POSITION_TYPE)posType),
               " nivel=", level, " bid=", bid, " ask=", ask,
               " fecha=", shouldClose);

      if (shouldClose && !trade.PositionClose(ticket))
         Print("ERRO ao fechar posicao: retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());

      break; // no maximo 1 posicao por simbolo/magic neste EA
   }
}

// Conta candles fechados seguidos contra a direcao da posicao (bearish pra uma
// compra, bullish pra uma venda); fecha a mercado ao atingir OppositeCandlesToExit.
// Qualquer candle que nao seja contra o trade (incluindo doji, close==open) zera
// a contagem. Roda uma vez por candle novo, junto com ManageDynamicExit.
void ManageOppositeStreakExit()
{
   if (OppositeCandlesToExit <= 0)
      return;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      bool isOpposite = (posType == POSITION_TYPE_BUY && close1 < open1) ||
                        (posType == POSITION_TYPE_SELL && close1 > open1);

      oppositeStreak = isOpposite ? oppositeStreak + 1 : 0;

      if (DebugLog)
         Print("STREAK OPOSTO: ticket=", ticket, " tipo=", EnumToString((ENUM_POSITION_TYPE)posType),
               " open1=", open1, " close1=", close1, " isOpposite=", isOpposite,
               " streak=", oppositeStreak, "/", OppositeCandlesToExit);

      if (oppositeStreak >= OppositeCandlesToExit)
      {
         if (DebugLog)
            Print("SAIDA POR SEQUENCIA OPOSTA: ticket=", ticket, " streak=", oppositeStreak);
         if (!trade.PositionClose(ticket))
            Print("ERRO ao fechar posicao pela sequencia oposta: retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription());
         oppositeStreak = 0;
      }

      break; // no maximo 1 posicao por simbolo/magic neste EA
   }
}

// Trava de seguranca por %saldo: roda em TODO tick (nao so a cada candle novo),
// pra reagir rapido. Fecha a posicao se a perda flutuante (profit+swap) atingir
// MaxLossPercent do saldo, independente do modo de saida (dinamica ou fixa).
bool CheckHardStopLoss()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;

      double floatingResult = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double maxLossAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (MaxLossPercent / 100.0);

      if (floatingResult <= -maxLossAmount)
      {
         if (DebugLog)
            Print("TRAVA DE SEGURANCA: ticket=", ticket, " perda flutuante=", floatingResult,
                  " limite=-", maxLossAmount, " (", MaxLossPercent, "% do saldo)");
         if (!trade.PositionClose(ticket))
            Print("ERRO ao fechar posicao pela trava de seguranca: retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription());
         return true;
      }
      break; // no maximo 1 posicao por simbolo/magic neste EA
   }
   return false;
}

int OnInit()
{
   if (BandsPeriod <= 1 || BandsDeviation <= 0.0 || RiskPercent <= 0.0 ||
       MaxLossPercent <= 0.0 || OppositeCandlesToExit < 0 ||
       (UseMAFilter && MAPeriod <= 0) ||
       (UseADXFilter && (ADXPeriod <= 0 || ADXThreshold < 0.0)) ||
       (UseFixedStopTarget && (FixedStopPoints <= 0.0 || FixedTargetPoints <= 0.0)))
   {
      Alert("Parametros numericos invalidos.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (UseTradingWindow)
   {
      int dummyMinutes;
      if (!ParseTimeToMinutes(TradingWindowStart, dummyMinutes) ||
          !ParseTimeToMinutes(TradingWindowEnd, dummyMinutes))
      {
         Alert("Horario invalido. Use HH:MM em TradingWindowStart/End.");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   if (UseMAFilter)
   {
      maHandle = iMA(_Symbol, PERIOD_CURRENT, MAPeriod, 0, MAMethod, PRICE_CLOSE);
      if (maHandle == INVALID_HANDLE)
      {
         Print("ERRO: falha ao criar handle da media. GetLastError=", GetLastError());
         return INIT_FAILED;
      }
   }

   bandsHandle = iBands(_Symbol, PERIOD_CURRENT, BandsPeriod, 0,
                        BandsDeviation, BandsPrice);
   if (bandsHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handle das Bandas de Bollinger. GetLastError=", GetLastError());
      return INIT_FAILED;
   }

   if (UseADXFilter)
   {
      adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADXPeriod);
      if (adxHandle == INVALID_HANDLE)
      {
         Print("ERRO: falha ao criar handle do ADX. GetLastError=", GetLastError());
         return INIT_FAILED;
      }
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA nao enviara ordens.");
   if (!UseFixedStopTarget)
      Print("AVISO: saida dinamica ativa - a posicao abre sem SL. A EA fecha a mercado ao atingir a banda/media.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
   if (bandsHandle != INVALID_HANDLE)
      IndicatorRelease(bandsHandle);
   if (adxHandle != INVALID_HANDLE)
      IndicatorRelease(adxHandle);
}

void OnTick()
{
   if (!AutoTrade)
      return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return;

   if (HasOpenPosition() && CheckHardStopLoss())
      return;

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   int minBars = BandsPeriod + 3;
   if (UseMAFilter)
      minBars = (int)MathMax(minBars, MAPeriod + 3);
   if (UseADXFilter)
      minBars = (int)MathMax(minBars, ADXPeriod + 3);
   if (Bars(_Symbol, PERIOD_CURRENT) < minBars)
   {
      Print("AVISO: barras insuficientes (minimo=", minBars, ").");
      return;
   }

   // baseBuf[0]/upperBuf[0]/lowerBuf[0] = candle anterior (shift 1)
   // baseBuf[1]/upperBuf[1]/lowerBuf[1] = candle penultimo (shift 2)
   double baseBuf[2], upperBuf[2], lowerBuf[2];
   if (CopyBuffer(bandsHandle, 0, 1, 2, baseBuf) <= 0 ||
       CopyBuffer(bandsHandle, 1, 1, 2, upperBuf) <= 0 ||
       CopyBuffer(bandsHandle, 2, 1, 2, lowerBuf) <= 0)
   {
      Print("ERRO: CopyBuffer das bandas falhou. GetLastError=", GetLastError());
      return;
   }
   double middleBand1 = baseBuf[0];
   double upperBand1 = upperBuf[0];
   double lowerBand1 = lowerBuf[0];
   double upperBand2 = upperBuf[1];
   double lowerBand2 = lowerBuf[1];

   // Posicao aberta: so gerencia a saida dinamica (se aplicavel) e nao avalia entrada nova.
   if (HasOpenPosition())
   {
      ManageADXExit();
      ManageOppositeStreakExit();
      ManageDynamicExit(middleBand1, upperBand1, lowerBand1);
      return;
   }

   if (!IsWithinTradingWindow())
      return;

   double maValue = 0.0;
   bool allowBuy = true;
   bool allowSell = true;
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   if (UseMAFilter)
   {
      double maBuf[1];
      if (CopyBuffer(maHandle, 0, 1, 1, maBuf) <= 0)
      {
         Print("ERRO: CopyBuffer da media falhou. GetLastError=", GetLastError());
         return;
      }
      maValue = maBuf[0];
      allowBuy = close1 > maValue;
      allowSell = close1 < maValue;
   }

   double adx1 = 0.0, adx2 = 0.0;
   bool allowByADX = true;
   if (UseADXFilter)
   {
      double adxBuf[2];
      if (CopyBuffer(adxHandle, MAIN_LINE, 1, 2, adxBuf) <= 0)
      {
         Print("ERRO: CopyBuffer do ADX falhou. GetLastError=", GetLastError());
         return;
      }
      adx1 = adxBuf[0];
      adx2 = adxBuf[1];
      // Entrada exige ADX estritamente abaixo do limite; a excecao "ou enfraquecendo"
      // vale so pra decidir fechar um trade ja aberto (ver ManageADXExit).
      allowByADX = adx1 < ADXThreshold;
   }

   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);

   bool buySignal = close2 < lowerBand2 && close1 > lowerBand1;
   bool sellSignal = close2 > upperBand2 && close1 < upperBand1;

   if (DebugLog)
      Print("BB dois fechamentos barra=", TimeToString(currentBarTime),
            " close2=", close2, " close1=", close1,
            " lowerBand2=", lowerBand2, " upperBand2=", upperBand2,
            " lower1=", lowerBand1, " middle1=", middleBand1, " upper1=", upperBand1,
            " buySignal=", buySignal, " sellSignal=", sellSignal,
            " ma=", maValue, " allowBuy=", allowBuy, " allowSell=", allowSell,
            " adx1=", adx1, " adx2=", adx2, " allowByADX=", allowByADX);

   if (!buySignal && !sellSignal)
      return;
   if ((buySignal && !allowBuy) || (sellSignal && !allowSell))
      return;
   if (UseADXFilter && !allowByADX)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double entry = buySignal ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (point <= 0.0 || entry <= 0.0)
      return;

   double stopDistance;
   double stop = 0.0;    // 0.0 = sem SL enviado (saida dinamica cuida disso)
   double target = 0.0;  // 0.0 = sem TP enviado (saida dinamica cuida disso)

   if (UseFixedStopTarget)
   {
      stopDistance = FixedStopPoints * point;
      stop = buySignal ? entry - stopDistance : entry + stopDistance;
      target = buySignal ? entry + FixedTargetPoints * point
                         : entry - FixedTargetPoints * point;
      stop = NormalizeDouble(stop, digits);
      target = NormalizeDouble(target, digits);

      bool validPrices = buySignal ? (stop < entry && target > entry)
                                   : (stop > entry && target < entry);
      if (!validPrices)
      {
         if (DebugLog)
            Print("SINAL IGNORADO: stop/alvo invalidos. entry=", entry,
                  " stop=", stop, " target=", target);
         return;
      }
   }
   else
   {
      // Sem SL real: usa a distancia ate a banda rompida so como regua de risco pro lote.
      stopDistance = buySignal ? (entry - lowerBand1) : (upperBand1 - entry);
   }

   if (stopDistance <= 0.0)
   {
      if (DebugLog)
         Print("SINAL IGNORADO: distancia de risco invalida. stopDistance=", stopDistance);
      return;
   }

   double lots = LotsForRisk(stopDistance);
   if (lots <= 0.0)
   {
      Print("AVISO: lote calculado <= 0. stopDistance=", stopDistance);
      return;
   }

   bool sent = buySignal
               ? trade.Buy(lots, _Symbol, 0.0, stop, target, "reversao_abertura_bollinger_lite")
               : trade.Sell(lots, _Symbol, 0.0, stop, target, "reversao_abertura_bollinger_lite");
   if (!sent)
      Print("ERRO ao enviar ordem: retcode=", trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription());
   else
   {
      oppositeStreak = 0; // nao herdar sequencia de um trade anterior
      if (DebugLog)
         Print(buySignal ? "COMPRA ENVIADA" : "VENDA ENVIADA",
               " lots=", lots, " entry=", entry, " stop=", stop,
               " target=", target, " risco%=", RiskPercent);
   }
}
