//+------------------------------------------------------------------+
//| PriceActionSimples.mq5                                            |
//| Gerado a partir da estrategia 'price_action_simples' (Python).    |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Revise o codigo e teste em conta demo |
//| antes de usar em conta real.                                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input int    Lookback        = 10;        // candles p/ minima/maxima recente
input double StopBufferPct   = 0.0500;  // % de folga alem do extremo
input double RiskRewardRatio = 2.00;
input double RiskPercent     = 1.0;                  // % do saldo arriscado por trade
input bool   AutoTrade       = false;                // precisa ligar explicitamente
input ulong  MagicNumber     = 20260709;
input bool   DebugLog        = true;                 // imprime diagnostico a cada candle fechado

CTrade trade;
int fastMAHandle, slowMAHandle;

int OnInit()
{
   fastMAHandle = iMA(_Symbol, PERIOD_CURRENT, 5, 0, MODE_SMA, PRICE_CLOSE);
   slowMAHandle = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
   if (fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handles de indicador. fastMAHandle=", fastMAHandle,
            " slowMAHandle=", slowMAHandle, " GetLastError=", GetLastError());
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA nao vai enviar ordens ate voce ligar este input.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fastMAHandle);
   IndicatorRelease(slowMAHandle);
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

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime) return; // so avalia uma vez por candle fechado
   lastBarTime = currentBarTime;

   if (Bars(_Symbol, PERIOD_CURRENT) < Lookback + 2)
   {
      Print("AVISO: barras insuficientes para Lookback=", Lookback);
      return;
   }

   double fastBuf[1], slowBuf[1];
   if (CopyBuffer(fastMAHandle, 0, 1, 1, fastBuf) <= 0)
   {
      Print("ERRO: CopyBuffer fastMA falhou. GetLastError=", GetLastError());
      return;
   }
   if (CopyBuffer(slowMAHandle, 0, 1, 1, slowBuf) <= 0)
   {
      Print("ERRO: CopyBuffer slowMA falhou. GetLastError=", GetLastError());
      return;
   }
   double fastMA = fastBuf[0];
   double slowMA = slowBuf[0];

   bool trendUp   = fastMA > slowMA * 1.0015;
   bool trendDown = fastMA < slowMA * 0.9985;

   double recentHigh = Highest(1, Lookback);
   double recentLow  = Lowest(1, Lookback);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double open1  = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double stopBufferFraction = StopBufferPct / 100.0;

   if (DebugLog)
      Print("BARRA ", TimeToString(currentBarTime), " fastMA=", fastMA, " slowMA=", slowMA,
            " trendUp=", trendUp, " trendDown=", trendDown,
            " close1=", close1, " open1=", open1, " low1=", low1, " high1=", high1,
            " recentHigh=", recentHigh, " recentLow=", recentLow);

   if (!trendUp && !trendDown) return; // lateral, sem setup (mesma regra do MarketAgent)

   if (trendUp)
   {
      bool breakout = close1 > recentHigh;
      bool pullback = (low1 <= recentLow * (1 + stopBufferFraction * 4)) && (close1 > open1);
      if (DebugLog)
         Print("  trendUp: breakout=", breakout, " pullback=", pullback);
      if (breakout || pullback)
      {
         double entry = close1;
         double stop = recentLow * (1 - stopBufferFraction);
         double target = entry + (entry - stop) * RiskRewardRatio;
         double lots = LotsForRisk(entry - stop);
         if (lots <= 0)
            Print("AVISO: lots calculado <= 0 no BUY (entry=", entry, " stop=", stop, "), ordem nao enviada.");
         else if (!trade.Buy(lots, _Symbol, 0.0, stop, target))
            Print("ERRO ao enviar BUY: retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription());
      }
   }
   else if (trendDown)
   {
      bool breakout = close1 < recentLow;
      bool pullback = (high1 >= recentHigh * (1 - stopBufferFraction * 4)) && (close1 < open1);
      if (DebugLog)
         Print("  trendDown: breakout=", breakout, " pullback=", pullback);
      if (breakout || pullback)
      {
         double entry = close1;
         double stop = recentHigh * (1 + stopBufferFraction);
         double target = entry - (stop - entry) * RiskRewardRatio;
         double lots = LotsForRisk(stop - entry);
         if (lots <= 0)
            Print("AVISO: lots calculado <= 0 no SELL (entry=", entry, " stop=", stop, "), ordem nao enviada.");
         else if (!trade.Sell(lots, _Symbol, 0.0, stop, target))
            Print("ERRO ao enviar SELL: retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription());
      }
   }
}