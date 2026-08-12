//+------------------------------------------------------------------+
//| MNQ_DriftPullback.mq5                                            |
//| Primeira implementacao da estrategia NQ/MNQ Drift Pullback.      |
//| Teste em Strategy Tester e conta demo antes de qualquer uso real.|
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include <Trade/Trade.mqh>

input group "Execucao" input bool InpAutoTrade = false;
input ulong InpMagicNumber = 2026080701;
input double InpVolume = 1.0;
input int InpMaxSlippageTicks = 1;
input bool InpDebugLog = true;

input group "Timeframe e sessao" input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
// Somado ao horario do servidor para obter o horario da estrategia.
// Ex.: servidor 14:30 e Nova York 09:30 => usar -300 minutos.
input int InpStrategyTimeOffsetMinutes = 0;
input int InpSessionStartHHMM = 1030;
input int InpEntryStartHHMM = 1030;
input int InpLastEntryHHMM = 1530;
input int InpForceCloseHHMM = 1555;

input group "Filtros direcionais" input int InpVWAPSlopeBars = 3; // 15 min no M5
input int InpReturnBars = 12;                                     // 60 min no M5
input double InpMinimumReturnPct = 0.10;
input bool InpUseEMAFilter = false;
input int InpFastEMAPeriod = 20;
input int InpSlowEMAPeriod = 50;

input group "Gatilho" input bool InpRequireFirstOppositeCandle = true;
input bool InpRequireWholeCandleSide = false;
input double InpMaxDistanceFromVWAPPoints = 0.0; // 0 desliga
input double InpMinBodyPoints = 0.0;             // 0 desliga
input double InpMaxBodyPoints = 0.0;             // 0 desliga

input group "Risco e limites diarios" input double InpLongStopPoints = 40.0;
input double InpLongTargetPoints = 20.0;
input double InpShortStopPoints = 40.0;
input double InpShortTargetPoints = 25.0;
input int InpMaxTradesPerDay = 4;
input int InpMaxLossesPerDay = 2;

CTrade trade;
int g_fastEMAHandle = INVALID_HANDLE;
int g_slowEMAHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
double NormalizePriceToTick(const double price)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tick_size <= 0.0)
      tick_size = _Point;
   return NormalizeDouble(MathRound(price / tick_size) * tick_size, _Digits);
}

//+------------------------------------------------------------------+
double NormalizeVolume(const double requested)
{
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (step <= 0.0)
      step = min_volume;
   if (step <= 0.0)
      return 0.0;

   double volume = MathMax(min_volume, MathMin(max_volume, requested));
   volume = MathFloor(volume / step + 1e-9) * step;
   return NormalizeDouble(volume, 8);
}

//+------------------------------------------------------------------+
datetime ToStrategyTime(const datetime server_time)
{
   return server_time + InpStrategyTimeOffsetMinutes * 60;
}

//+------------------------------------------------------------------+
int HHMM(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(ToStrategyTime(server_time), dt);
   return dt.hour * 100 + dt.min;
}

//+------------------------------------------------------------------+
int StrategyDateKey(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(ToStrategyTime(server_time), dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
}

//+------------------------------------------------------------------+
datetime StrategyDayStartServer(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(ToStrategyTime(server_time), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt) - InpStrategyTimeOffsetMinutes * 60;
}

//+------------------------------------------------------------------+
datetime SessionStartServer(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(ToStrategyTime(server_time), dt);
   dt.hour = InpSessionStartHHMM / 100;
   dt.min = InpSessionStartHHMM % 100;
   dt.sec = 0;
   return StructToTime(dt) - InpStrategyTimeOffsetMinutes * 60;
}

//+------------------------------------------------------------------+
bool HasOurPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CloseOurPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if ((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if (!trade.PositionClose(ticket))
         Print("ERRO ao zerar posicao: ticket=", ticket,
               " retcode=", trade.ResultRetcode(),
               " descricao=", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
void GetDailyStats(const datetime now_server, int &trades_count, int &losses_count)
{
   trades_count = 0;
   losses_count = 0;

   datetime from = StrategyDayStartServer(now_server);
   if (!HistorySelect(from, now_server))
      return;

   int total = HistoryDealsTotal();
   for (int i = 0; i < total; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if (deal == 0)
         continue;
      if (HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      if ((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
         continue;

      ENUM_DEAL_ENTRY entry =
          (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      ENUM_DEAL_TYPE type =
          (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);

      if (entry == DEAL_ENTRY_IN &&
          (type == DEAL_TYPE_BUY || type == DEAL_TYPE_SELL))
      {
         trades_count++;
      }
      else if (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         double result =
             HistoryDealGetDouble(deal, DEAL_PROFIT) +
             HistoryDealGetDouble(deal, DEAL_SWAP) +
             HistoryDealGetDouble(deal, DEAL_COMMISSION) +
             HistoryDealGetDouble(deal, DEAL_FEE);
         if (result < 0.0)
            losses_count++;
      }
   }
}

//+------------------------------------------------------------------+
double SessionVWAP(const int shift)
{
   datetime bar_time = iTime(_Symbol, InpTimeframe, shift);
   if (bar_time <= 0)
      return 0.0;

   datetime session_start = SessionStartServer(bar_time);
   if (bar_time < session_start)
      return 0.0;

   int oldest_shift = iBarShift(_Symbol, InpTimeframe, session_start, false);
   if (oldest_shift < shift)
      return 0.0;

   double price_volume = 0.0;
   double volume_sum = 0.0;

   for (int i = oldest_shift; i >= shift; --i)
   {
      double high = iHigh(_Symbol, InpTimeframe, i);
      double low = iLow(_Symbol, InpTimeframe, i);
      double close = iClose(_Symbol, InpTimeframe, i);
      long volume = iRealVolume(_Symbol, InpTimeframe, i);
      if (volume <= 0)
         volume = iVolume(_Symbol, InpTimeframe, i);
      if (volume <= 0)
         continue;

      double typical = (high + low + close) / 3.0;
      price_volume += typical * (double)volume;
      volume_sum += (double)volume;
   }

   return volume_sum > 0.0 ? price_volume / volume_sum : 0.0;
}

//+------------------------------------------------------------------+
bool ReadEMA(const int handle, const int shift, double &value)
{
   double buffer[1];
   if (CopyBuffer(handle, 0, shift, 1, buffer) != 1)
      return false;
   value = buffer[0];
   return true;
}

//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if (InpVWAPSlopeBars < 1 || InpReturnBars < 1)
   {
      Print("ERRO: janelas de filtro devem ser maiores que zero.");
      return false;
   }
   if (InpVolume <= 0.0 ||
       InpLongStopPoints <= 0.0 || InpLongTargetPoints <= 0.0 ||
       InpShortStopPoints <= 0.0 || InpShortTargetPoints <= 0.0)
   {
      Print("ERRO: volume, stops e alvos devem ser positivos.");
      return false;
   }
   if (InpEntryStartHHMM > InpLastEntryHHMM)
   {
      Print("ERRO: horario inicial maior que horario final de entrada.");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   if (!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_fastEMAHandle =
       iMA(_Symbol, InpTimeframe, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slowEMAHandle =
       iMA(_Symbol, InpTimeframe, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if (g_fastEMAHandle == INVALID_HANDLE ||
       g_slowEMAHandle == INVALID_HANDLE)
   {
      Print("ERRO: nao foi possivel criar as medias. GetLastError=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);

   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   int deviation_points = 0;
   if (_Point > 0.0 && tick_size > 0.0)
      deviation_points =
          (int)MathCeil(InpMaxSlippageTicks * tick_size / _Point);
   trade.SetDeviationInPoints(deviation_points);

   Print("MNQ DriftPullback iniciado em ", _Symbol,
         ". TickSize=", tick_size,
         " TickValue=", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
         " VolumeMin=", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
         " VolumeStep=", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
         " OffsetHorarioMin=", InpStrategyTimeOffsetMinutes);

   if (!InpAutoTrade)
      Print("AVISO: InpAutoTrade=false; nenhuma ordem sera enviada.");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_fastEMAHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastEMAHandle);
   if (g_slowEMAHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowEMAHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now_server = TimeCurrent();
   int strategy_hhmm = HHMM(now_server);

   // Zeragem por horario ocorre em todo tick, nao apenas em nova barra.
   if (strategy_hhmm >= InpForceCloseHHMM)
   {
      if (HasOurPosition())
         CloseOurPositions();
      return;
   }

   datetime current_bar = iTime(_Symbol, InpTimeframe, 0);
   if (current_bar <= 0 || current_bar == g_lastBarTime)
      return;
   g_lastBarTime = current_bar;

   int required_bars =
       MathMax(InpSlowEMAPeriod,
               MathMax(InpReturnBars, InpVWAPSlopeBars)) +
       5;
   if (Bars(_Symbol, InpTimeframe) < required_bars)
      return;

   if (HasOurPosition())
      return;
   if (strategy_hhmm < InpEntryStartHHMM ||
       strategy_hhmm > InpLastEntryHHMM)
      return;

   int trades_today = 0;
   int losses_today = 0;
   GetDailyStats(now_server, trades_today, losses_today);
   if (trades_today >= InpMaxTradesPerDay ||
       losses_today >= InpMaxLossesPerDay)
      return;

   const int s1 = 1;
   const int s2 = 2;
   double vwap1 = SessionVWAP(s1);
   double vwap2 = SessionVWAP(s2);
   double vwap_slope_ref = SessionVWAP(s1 + InpVWAPSlopeBars);
   if (vwap1 <= 0.0 || vwap2 <= 0.0 || vwap_slope_ref <= 0.0)
      return;

   double close1 = iClose(_Symbol, InpTimeframe, s1);
   double open1 = iOpen(_Symbol, InpTimeframe, s1);
   double high1 = iHigh(_Symbol, InpTimeframe, s1);
   double low1 = iLow(_Symbol, InpTimeframe, s1);
   double close2 = iClose(_Symbol, InpTimeframe, s2);
   double open2 = iOpen(_Symbol, InpTimeframe, s2);
   double close_return_ref =
       iClose(_Symbol, InpTimeframe, s1 + InpReturnBars);
   if (close_return_ref <= 0.0)
      return;

   double return_pct =
       (close1 / close_return_ref - 1.0) * 100.0;
   bool vwap_rising = vwap1 > vwap_slope_ref;
   bool vwap_falling = vwap1 < vwap_slope_ref;

   bool ema_long = true;
   bool ema_short = true;
   if (InpUseEMAFilter)
   {
      double fast_ema = 0.0;
      double slow_ema = 0.0;
      if (!ReadEMA(g_fastEMAHandle, s1, fast_ema) ||
          !ReadEMA(g_slowEMAHandle, s1, slow_ema))
         return;
      ema_long = close1 > fast_ema && fast_ema > slow_ema;
      ema_short = close1 < fast_ema && fast_ema < slow_ema;
   }

   bool regime_long =
       close1 > vwap1 &&
       vwap_rising &&
       return_pct >= InpMinimumReturnPct &&
       ema_long;
   bool regime_short =
       close1 < vwap1 &&
       vwap_falling &&
       return_pct <= -InpMinimumReturnPct &&
       ema_short;

   double distance = MathAbs(close1 - vwap1);
   double previous_distance = MathAbs(close2 - vwap2);
   double body = MathAbs(close1 - open1);

   bool distance_ok =
       InpMaxDistanceFromVWAPPoints <= 0.0 ||
       distance <= InpMaxDistanceFromVWAPPoints;
   bool body_ok =
       (InpMinBodyPoints <= 0.0 || body >= InpMinBodyPoints) &&
       (InpMaxBodyPoints <= 0.0 || body <= InpMaxBodyPoints);
   bool first_red =
       !InpRequireFirstOppositeCandle || close2 >= open2;
   bool first_green =
       !InpRequireFirstOppositeCandle || close2 <= open2;
   bool whole_above =
       !InpRequireWholeCandleSide || low1 > vwap1;
   bool whole_below =
       !InpRequireWholeCandleSide || high1 < vwap1;

   bool long_trigger =
       regime_long &&
       close1 < open1 &&
       first_red &&
       whole_above &&
       distance < previous_distance &&
       distance_ok &&
       body_ok;
   bool short_trigger =
       regime_short &&
       close1 > open1 &&
       first_green &&
       whole_below &&
       distance < previous_distance &&
       distance_ok &&
       body_ok;

   if (InpDebugLog)
      Print("BAR ", TimeToString(current_bar),
            " StrategyHHMM=", strategy_hhmm,
            " VWAP=", DoubleToString(vwap1, _Digits),
            " ReturnPct=", DoubleToString(return_pct, 3),
            " LongRegime=", regime_long,
            " ShortRegime=", regime_short,
            " LongTrigger=", long_trigger,
            " ShortTrigger=", short_trigger,
            " TradesToday=", trades_today,
            " LossesToday=", losses_today);

   if (!InpAutoTrade || (!long_trigger && !short_trigger))
      return;

   double volume = NormalizeVolume(InpVolume);
   if (volume <= 0.0)
   {
      Print("ERRO: volume invalido para o simbolo ", _Symbol);
      return;
   }

   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   if (long_trigger)
   {
      double sl = NormalizePriceToTick(tick.ask - InpLongStopPoints);
      double tp = NormalizePriceToTick(tick.ask + InpLongTargetPoints);
      if (!trade.Buy(volume, _Symbol, 0.0, sl, tp, "MNQ Drift Long"))
         Print("ERRO BUY: ", trade.ResultRetcode(), " ",
               trade.ResultRetcodeDescription());
   }
   else if (short_trigger)
   {
      double sl = NormalizePriceToTick(tick.bid + InpShortStopPoints);
      double tp = NormalizePriceToTick(tick.bid - InpShortTargetPoints);
      if (!trade.Sell(volume, _Symbol, 0.0, sl, tp, "MNQ Drift Short"))
         Print("ERRO SELL: ", trade.ResultRetcode(), " ",
               trade.ResultRetcodeDescription());
   }
}
