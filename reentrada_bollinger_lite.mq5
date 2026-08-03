//+------------------------------------------------------------------+
//| reentrada_bollinger_lite.mq5                                     |
//| EA lite de reversao pelas Bandas de Bollinger. Depois que o      |
//| preco rompe uma banda, negocia o primeiro candle que fecha de    |
//| volta dentro das bandas: compra apos romper a inferior e vende   |
//| apos romper a superior. Por padrao, o stop fica no extremo do    |
//| movimento fora da banda e o alvo na linha media. O lote limita   |
//| a perda planejada no stop ao RiskPercent do saldo.               |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Teste primeiro em conta demo.         |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input int BandsPeriod = 20;                 // Periodo das Bandas de Bollinger
input double BandsDeviation = 2.0;          // Desvios-padrao das bandas
input ENUM_APPLIED_PRICE BandsPrice = PRICE_CLOSE;
input bool UseMiddleBandTarget = true;      // alvo na media da banda; false usa RiskRewardRatio

input double RiskRewardRatio = 1.5;         // alvo por risco quando UseMiddleBandTarget=false
input double RiskPercent = 1.0;              // % do saldo perdido se o stop for executado
input bool AutoTrade = false;                // precisa ligar explicitamente
input ulong MagicNumber = 20260720;
input bool DebugLog = true;

input bool UseMAFilter = false;              // compra acima da MA e venda abaixo da MA
input int MAPeriod = 50;
input ENUM_MA_METHOD MAMethod = MODE_SMA;

input bool UseFixedStopTarget = false;       // substitui stop estrutural e alvo da media/RR
input double FixedStopPoints = 100.0;
input double FixedTargetPoints = 150.0;

input bool UseTradingWindow = false;
input string TradingWindowStart = "16:00";  // hora do servidor
input string TradingWindowEnd = "19:00";

CTrade trade;
int maHandle = INVALID_HANDLE;
int bandsHandle = INVALID_HANDLE;

bool lowerBreakActive = false;
bool upperBreakActive = false;
double lowerBreakExtreme = 0.0;
double upperBreakExtreme = 0.0;

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

double Highest(const int shift, const int count)
{
   int index = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, count, shift);
   return index < 0 ? 0.0 : iHigh(_Symbol, PERIOD_CURRENT, index);
}

double Lowest(const int shift, const int count)
{
   int index = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, count, shift);
   return index < 0 ? 0.0 : iLow(_Symbol, PERIOD_CURRENT, index);
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

int OnInit()
{
   if (BandsPeriod <= 1 || BandsDeviation <= 0.0 || RiskPercent <= 0.0 ||
       RiskRewardRatio <= 0.0 || (UseMAFilter && MAPeriod <= 0) ||
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

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA nao enviara ordens.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
   if (bandsHandle != INVALID_HANDLE)
      IndicatorRelease(bandsHandle);
}

void OnTick()
{
   if (!AutoTrade)
      return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return;
   if (HasOpenPosition())
      return;
   if (!IsWithinTradingWindow())
      return;

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   int minBars = BandsPeriod + 2;
   if (UseMAFilter)
      minBars = (int)MathMax(minBars, MAPeriod + 2);
   if (Bars(_Symbol, PERIOD_CURRENT) < minBars)
   {
      Print("AVISO: barras insuficientes (minimo=", minBars, ").");
      return;
   }

   double baseBuf[1], upperBuf[1], lowerBuf[1];
   if (CopyBuffer(bandsHandle, 0, 1, 1, baseBuf) <= 0 ||
       CopyBuffer(bandsHandle, 1, 1, 1, upperBuf) <= 0 ||
       CopyBuffer(bandsHandle, 2, 1, 1, lowerBuf) <= 0)
   {
      Print("ERRO: CopyBuffer das bandas falhou. GetLastError=", GetLastError());
      return;
   }

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

   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double middleBand1 = baseBuf[0];
   double upperBand1 = upperBuf[0];
   double lowerBand1 = lowerBuf[0];
   bool brokeLower = low1 < lowerBand1;
   bool brokeUpper = high1 > upperBand1;
   bool closedInside = close1 > lowerBand1 && close1 < upperBand1;

   // Um candle que rompe as duas bandas e ambiguo; descarta os dois setups.
   if (brokeLower && brokeUpper)
   {
      lowerBreakActive = false;
      upperBreakActive = false;
      if (DebugLog)
         Print("SINAL DESCARTADO: candle rompeu as duas bandas.");
      return;
   }

   if (brokeLower)
   {
      if (!lowerBreakActive)
         lowerBreakExtreme = low1;
      else
         lowerBreakExtreme = MathMin(lowerBreakExtreme, low1);
      lowerBreakActive = true;
      upperBreakActive = false;
   }
   else if (lowerBreakActive)
      lowerBreakExtreme = MathMin(lowerBreakExtreme, low1);

   if (brokeUpper)
   {
      if (!upperBreakActive)
         upperBreakExtreme = high1;
      else
         upperBreakExtreme = MathMax(upperBreakExtreme, high1);
      upperBreakActive = true;
      lowerBreakActive = false;
   }
   else if (upperBreakActive)
      upperBreakExtreme = MathMax(upperBreakExtreme, high1);

   bool buySignal = lowerBreakActive && closedInside;
   bool sellSignal = upperBreakActive && closedInside;

   if (DebugLog)
      Print("BB barra=", TimeToString(iTime(_Symbol, PERIOD_CURRENT, 1)),
            " close=", close1, " lower=", lowerBand1, " middle=", middleBand1,
            " upper=", upperBand1, " lowerActive=", lowerBreakActive,
            " upperActive=", upperBreakActive, " buySignal=", buySignal,
            " sellSignal=", sellSignal, " ma=", maValue,
            " allowBuy=", allowBuy, " allowSell=", allowSell);

   if (!buySignal && !sellSignal)
      return;

   // O primeiro fechamento de retorno consome o setup, mesmo se outro filtro bloquear.
   double structuralStop = buySignal ? lowerBreakExtreme : upperBreakExtreme;
   lowerBreakActive = false;
   upperBreakActive = false;

   if ((buySignal && !allowBuy) || (sellSignal && !allowSell))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double entry = buySignal ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (point <= 0.0 || entry <= 0.0)
      return;

   double stop = structuralStop;
   double stopDistance = buySignal ? entry - stop : stop - entry;
   double target = middleBand1;

   if (UseFixedStopTarget)
   {
      stopDistance = FixedStopPoints * point;
      stop = buySignal ? entry - stopDistance : entry + stopDistance;
      target = buySignal ? entry + FixedTargetPoints * point
                         : entry - FixedTargetPoints * point;
   }
   else if (!UseMiddleBandTarget)
   {
      target = buySignal ? entry + stopDistance * RiskRewardRatio
                         : entry - stopDistance * RiskRewardRatio;
   }

   stop = NormalizeDouble(stop, digits);
   target = NormalizeDouble(target, digits);
   stopDistance = MathAbs(entry - stop);

   bool validPrices = buySignal ? (stop < entry && target > entry)
                                : (stop > entry && target < entry);
   if (!validPrices)
   {
      if (DebugLog)
         Print("SINAL IGNORADO: stop/alvo invalidos. entry=", entry,
               " stop=", stop, " target=", target);
      return;
   }

   double lots = LotsForRisk(stopDistance);
   if (lots <= 0.0)
   {
      Print("AVISO: lote calculado <= 0. stopDistance=", stopDistance);
      return;
   }

   bool sent = buySignal
               ? trade.Buy(lots, _Symbol, 0.0, stop, target, "reentrada_bollinger_lite")
               : trade.Sell(lots, _Symbol, 0.0, stop, target, "reentrada_bollinger_lite");
   if (!sent)
      Print("ERRO ao enviar ordem: retcode=", trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription());
   else if (DebugLog)
      Print(buySignal ? "COMPRA ENVIADA" : "VENDA ENVIADA",
            " lots=", lots, " entry=", entry, " stop=", stop,
            " target=", target, " risco%=", RiskPercent);
}
