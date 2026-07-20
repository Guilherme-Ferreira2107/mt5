//+------------------------------------------------------------------+
//| rsi_extremo_lite.mq5                                              |
//| EA lite: RSI de pullback filtrado por tendencia da MA. RSI <=     |
//| RSIOversold (default 30) so compra se preco > MA (uptrend). RSI   |
//| >= RSIOverbought (default 70) so vende se preco < MA (downtrend). |
//| Stop estrutural por lookback (Highest/Lowest) ou fixo em pontos.  |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Revise o codigo e teste em conta demo |
//| antes de usar em conta real.                                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input double RSIOversold    = 30.0;  // RSI <= este valor => compra (pullback dentro de tendencia de alta)
input double RSIOverbought  = 70.0;  // RSI >= este valor => venda (pullback dentro de tendencia de baixa)
input int    RSIPeriod      = 14;    // Periodo do RSI
input int    StopLookback   = 10;    // candles p/ minima/maxima recente (stop estrutural)
input bool   UseMAFilter    = true;  // ativar/desativar filtro de tendencia pela media movel
input int    MAPeriod       = 50;    // Periodo da media movel de filtro de tendencia
input ENUM_MA_METHOD MAMethod = MODE_SMA; // Metodo da media movel
input double RiskRewardRatio = 2.00;
input double RiskPercent    = 1.0;   // % do saldo arriscado por trade
input bool   UseFixedStopTarget = false; // usar stop/alvo fixos (em pontos) em vez do estrutural
input double FixedStopPoints    = 200.0; // Stop fixo (pontos), se UseFixedStopTarget
input double FixedTargetPoints  = 400.0; // Alvo fixo (pontos), se UseFixedStopTarget
input bool   UseTradingWindow   = false; // restringir novas entradas a uma janela de horario
input string TradingWindowStart = "09:00"; // Inicio da janela (HH:MM, hora do servidor)
input string TradingWindowEnd   = "17:00"; // Fim da janela (HH:MM, hora do servidor)
input bool   AutoTrade      = false; // precisa ligar explicitamente
input ulong  MagicNumber    = 20260715;
input bool   DebugLog       = true;  // imprime diagnostico a cada candle fechado

CTrade trade;
int rsiHandle;
int maHandle;

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
   if (!ParseTimeToMinutes(TradingWindowStart, startMinutes) || !ParseTimeToMinutes(TradingWindowEnd, endMinutes))
      return true; // horario ja validado no OnInit, nao deveria cair aqui

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int nowMinutes = now.hour * 60 + now.min;

   if (startMinutes <= endMinutes)
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
   return nowMinutes >= startMinutes || nowMinutes <= endMinutes; // janela cruzando meia-noite
}

int OnInit()
{
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
   if (rsiHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handle do RSI. GetLastError=", GetLastError());
      return INIT_FAILED;
   }

   maHandle = INVALID_HANDLE;
   if (UseMAFilter)
   {
      maHandle = iMA(_Symbol, PERIOD_CURRENT, MAPeriod, 0, MAMethod, PRICE_CLOSE);
      if (maHandle == INVALID_HANDLE)
      {
         Print("ERRO: falha ao criar handle da media movel. GetLastError=", GetLastError());
         return INIT_FAILED;
      }
   }

   if (UseTradingWindow)
   {
      int dummyMinutes;
      if (!ParseTimeToMinutes(TradingWindowStart, dummyMinutes) || !ParseTimeToMinutes(TradingWindowEnd, dummyMinutes))
      {
         Alert("Horario invalido em TradingWindowStart/TradingWindowEnd. Use o formato HH:MM.");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA nao vai enviar ordens ate voce ligar este input.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
   if (maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

double Highest(int shift, int count)
{
   int idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, count, shift);
   return idx >= 0 ? iHigh(_Symbol, PERIOD_CURRENT, idx) : 0.0;
}

double Lowest(int shift, int count)
{
   int idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, count, shift);
   return idx >= 0 ? iLow(_Symbol, PERIOD_CURRENT, idx) : 0.0;
}

double LotsForRisk(double stopDistance)
{
   if (stopDistance <= 0) return 0.0;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0) return 0.0;
   double lots = riskAmount / (stopDistance / tickSize * tickValue);

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0) step = 0.01;

   int decimals = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   lots = NormalizeDouble(MathFloor(lots / step) * step, decimals);

   if (lots > maxLot) lots = NormalizeDouble(MathFloor(maxLot / step) * step, decimals);
   return lots < minLot ? 0.0 : lots;
}

bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      return true;
   }
   return false;
}

void OnTick()
{
   if (!AutoTrade) return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) return; // negociacao desabilitada no simbolo
   if (HasOpenPosition()) return; // uma posicao por vez neste simbolo/EA
   if (!IsWithinTradingWindow()) return; // fora da janela de horario configurada

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime) return; // so avalia uma vez por candle fechado
   lastBarTime = currentBarTime;

   int minBars = MathMax(RSIPeriod + 2, StopLookback + 2);
   if (UseMAFilter) minBars = MathMax(minBars, MAPeriod + 2);
   if (Bars(_Symbol, PERIOD_CURRENT) < minBars)
   {
      Print("AVISO: barras insuficientes (minimo=", minBars, ")");
      return;
   }

   double rsiBuf[1];
   if (CopyBuffer(rsiHandle, 0, 1, 1, rsiBuf) <= 0)
   {
      Print("ERRO: CopyBuffer do RSI falhou. GetLastError=", GetLastError());
      return;
   }
   double rsi1 = rsiBuf[0];

   double maValue = 0.0;
   bool allowBuy  = true;
   bool allowSell = true;
   if (UseMAFilter)
   {
      double maBuf[1];
      if (CopyBuffer(maHandle, 0, 1, 1, maBuf) <= 0)
      {
         Print("ERRO: CopyBuffer da media movel falhou. GetLastError=", GetLastError());
         return;
      }
      maValue = maBuf[0];
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      allowBuy  = close1 > maValue;
      allowSell = close1 < maValue;
   }

   bool isOversold   = rsi1 <= RSIOversold;
   bool isOverbought = rsi1 >= RSIOverbought;

   if (DebugLog)
      Print("BARRA ", TimeToString(currentBarTime), " rsi1=", rsi1,
            " isOversold=", isOversold, " isOverbought=", isOverbought,
            " maValue=", maValue, " allowBuy=", allowBuy, " allowSell=", allowSell);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (isOversold && allowBuy)
   {
      // RSI em pullback de sobrevenda, preco acima da MA (uptrend) => compra a favor da tendencia
      double entry = iClose(_Symbol, PERIOD_CURRENT, 1);
      double stop = UseFixedStopTarget ? entry - FixedStopPoints * point : Lowest(1, StopLookback);
      double target = UseFixedStopTarget ? entry + FixedTargetPoints * point
                                          : entry + (entry - stop) * RiskRewardRatio;
      double lots = LotsForRisk(entry - stop);
      if (lots <= 0)
         Print("AVISO: lots calculado <= 0 no BUY (entry=", entry, " stop=", stop, "), ordem nao enviada.");
      else if (!trade.Buy(lots, _Symbol, 0.0, stop, target))
         Print("ERRO ao enviar BUY: retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());
   }
   else if (isOverbought && allowSell)
   {
      // RSI em pullback de sobrecompra, preco abaixo da MA (downtrend) => venda a favor da tendencia
      double entry = iClose(_Symbol, PERIOD_CURRENT, 1);
      double stop = UseFixedStopTarget ? entry + FixedStopPoints * point : Highest(1, StopLookback);
      double target = UseFixedStopTarget ? entry - FixedTargetPoints * point
                                          : entry - (stop - entry) * RiskRewardRatio;
      double lots = LotsForRisk(stop - entry);
      if (lots <= 0)
         Print("AVISO: lots calculado <= 0 no SELL (entry=", entry, " stop=", stop, "), ordem nao enviada.");
      else if (!trade.Sell(lots, _Symbol, 0.0, stop, target))
         Print("ERRO ao enviar SELL: retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());
   }
}
