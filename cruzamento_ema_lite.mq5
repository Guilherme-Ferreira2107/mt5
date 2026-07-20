//+------------------------------------------------------------------+
//| cruzamento_ema_lite.mq5                                          |
//| EA lite: cruzamento de EMA rapida/lenta. Compra quando a EMA     |
//| rapida cruza para cima da EMA lenta no candle recem-fechado;     |
//| vende quando cruza para baixo. Pensado para M5, com muitos       |
//| gatilhos por dia. Stop especifico do sinal = minima/maxima do    |
//| proprio candle do cruzamento (ou fixo em pontos).                 |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Revise o codigo e teste em conta demo |
//| antes de usar em conta real.                                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input int    EMAFastPeriod  = 5;     // Periodo da EMA rapida
input int    EMASlowPeriod  = 20;    // Periodo da EMA lenta
input bool   UseMAFilter    = false; // ativar/desativar filtro extra de tendencia pela media movel
input int    MAPeriod       = 50;    // Periodo da media movel de filtro de tendencia
input ENUM_MA_METHOD MAMethod = MODE_SMA; // Metodo da media movel
input double RiskRewardRatio = 1.50;
input double RiskPercent    = 1.0;   // % do saldo arriscado por trade
input bool   UseFixedStopTarget = false; // usar stop/alvo fixos (em pontos) em vez do estrutural
input double FixedStopPoints    = 200.0; // Stop fixo (pontos), se UseFixedStopTarget
input double FixedTargetPoints  = 300.0; // Alvo fixo (pontos), se UseFixedStopTarget
input bool   UseTradingWindow   = false; // restringir novas entradas a uma janela de horario
input string TradingWindowStart = "09:00"; // Inicio da janela (HH:MM, hora do servidor)
input string TradingWindowEnd   = "17:00"; // Fim da janela (HH:MM, hora do servidor)
input bool   AutoTrade      = false; // precisa ligar explicitamente
input ulong  MagicNumber    = 20260716;
input bool   DebugLog       = true;  // imprime diagnostico a cada candle fechado

CTrade trade;
int emaFastHandle;
int emaSlowHandle;
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
   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (emaFastHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handle da EMA rapida. GetLastError=", GetLastError());
      return INIT_FAILED;
   }

   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (emaSlowHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handle da EMA lenta. GetLastError=", GetLastError());
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
   if (emaFastHandle != INVALID_HANDLE)
      IndicatorRelease(emaFastHandle);
   if (emaSlowHandle != INVALID_HANDLE)
      IndicatorRelease(emaSlowHandle);
   if (maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

double LotsForRisk(double stopDistance)
{
   if (stopDistance <= 0)
      return 0.0;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0)
      return 0.0;
   double lots = riskAmount / (stopDistance / tickSize * tickValue);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0)
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

void OnTick()
{
   if (!AutoTrade)
      return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return; // negociacao desabilitada no simbolo
   if (HasOpenPosition())
      return; // uma posicao por vez neste simbolo/EA
   if (!IsWithinTradingWindow())
      return; // fora da janela de horario configurada

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime)
      return; // so avalia uma vez por candle fechado
   lastBarTime = currentBarTime;

   int minBars = EMASlowPeriod + 3;
   if (UseMAFilter)
      minBars = MathMax(minBars, MAPeriod + 2);
   if (Bars(_Symbol, PERIOD_CURRENT) < minBars)
   {
      Print("AVISO: barras insuficientes (minimo=", minBars, ")");
      return;
   }

   double fastBuf[2], slowBuf[2];
   if (CopyBuffer(emaFastHandle, 0, 1, 2, fastBuf) <= 0)
   {
      Print("ERRO: CopyBuffer da EMA rapida falhou. GetLastError=", GetLastError());
      return;
   }
   if (CopyBuffer(emaSlowHandle, 0, 1, 2, slowBuf) <= 0)
   {
      Print("ERRO: CopyBuffer da EMA lenta falhou. GetLastError=", GetLastError());
      return;
   }
   double fast1 = fastBuf[0]; // EMA rapida no ultimo candle fechado
   double fast2 = fastBuf[1]; // EMA rapida no candle anterior
   double slow1 = slowBuf[0]; // EMA lenta no ultimo candle fechado
   double slow2 = slowBuf[1]; // EMA lenta no candle anterior

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

   bool crossUp   = fast2 <= slow2 && fast1 > slow1;   // EMA rapida cruzou para cima da lenta
   bool crossDown = fast2 >= slow2 && fast1 < slow1;   // EMA rapida cruzou para baixo da lenta

   if (DebugLog)
      Print("BARRA ", TimeToString(currentBarTime), " fast1=", fast1, " slow1=", slow1,
            " fast2=", fast2, " slow2=", slow2, " crossUp=", crossUp, " crossDown=", crossDown,
            " maValue=", maValue, " allowBuy=", allowBuy, " allowSell=", allowSell);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1  = iLow(_Symbol, PERIOD_CURRENT, 1);

   if (crossUp && allowBuy)
   {
      // EMA rapida cruzou para cima => compra, stop = minima do candle do cruzamento (ou fixo)
      double entry = iClose(_Symbol, PERIOD_CURRENT, 1);
      double stop = UseFixedStopTarget ? entry - FixedStopPoints * point : low1;
      double target = UseFixedStopTarget ? entry + FixedTargetPoints * point
                                          : entry + (entry - stop) * RiskRewardRatio;
      double lots = LotsForRisk(entry - stop);
      if (lots <= 0)
         Print("AVISO: lots calculado <= 0 no BUY (entry=", entry, " stop=", stop, "), ordem nao enviada.");
      else if (!trade.Buy(lots, _Symbol, 0.0, stop, target))
         Print("ERRO ao enviar BUY: retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());
   }
   else if (crossDown && allowSell)
   {
      // EMA rapida cruzou para baixo => venda, stop = maxima do candle do cruzamento (ou fixo)
      double entry = iClose(_Symbol, PERIOD_CURRENT, 1);
      double stop = UseFixedStopTarget ? entry + FixedStopPoints * point : high1;
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
