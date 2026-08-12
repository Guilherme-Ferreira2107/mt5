//+------------------------------------------------------------------+
//| DriftPullback_Indicador.mq5                                       |
//| Indicador visual da estrategia Drift Pullback (VWAP + pullback).  |
//| Funciona em qualquer simbolo/timeframe anexado ao grafico -       |
//| MNQ, NQ, WDO, etc. Replica a logica de sinal do EA                |
//| MNQ_DriftPullback.mq5 e marca no grafico os pontos de entrada     |
//| (compra/venda) dos ultimos N candles.                             |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "VWAP sessao"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Entrada Compra"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

#property indicator_label3  "Entrada Venda"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2

input group "Exibicao"
input int    InpBarsToShow            = 500;   // Quantos candles recentes recebem sinal
input bool   InpShowVWAP              = true;
input bool   InpShowInfoPanel         = true;

input group "Timeframe e sessao"
// Somado ao horario do servidor para obter o horario da estrategia (mesma regra do EA).
input int    InpStrategyTimeOffsetMinutes = 0;
input int    InpSessionStartHHMM      = 1530;
input int    InpEntryStartHHMM        = 1530;
input int    InpLastEntryHHMM         = 2030;

input group "Filtros direcionais"
input int    InpVWAPSlopeBars         = 9;    // numero de candles do timeframe do grafico
input int    InpReturnBars            = 36;   // numero de candles do timeframe do grafico
input double InpMinimumReturnPct      = 0.10;
input bool   InpUseEMAFilter          = false;
input int    InpFastEMAPeriod         = 20;
input int    InpSlowEMAPeriod         = 50;

input group "Gatilho"
input bool   InpRequireFirstOppositeCandle = true;
input bool   InpRequireWholeCandleSide     = false;
input double InpMaxDistanceFromVWAPPoints  = 0.0; // 0 desliga
input double InpMinBodyPoints              = 0.0; // 0 desliga
input double InpMaxBodyPoints              = 0.0; // 0 desliga

input group "Risco e limites diarios"
// Usados apenas para SIMULAR o estado do EA (1 posicao por vez, limites diarios).
// Mantenha iguais aos valores do robo para o indicador nao sugerir entradas que o EA nao tomaria.
input double InpLongStopPoints        = 40.0;
input double InpLongTargetPoints      = 40.0;
input double InpShortStopPoints       = 45.0;
input double InpShortTargetPoints     = 50.0;
input int    InpMaxTradesPerDay       = 4;
input int    InpMaxLossesPerDay       = 2;
input int    InpForceCloseHHMM        = 2055;

input group "Alertas"
input bool   InpAlertPopup            = true;
input bool   InpAlertPush             = false;
input bool   InpAlertLog              = true;

double BufferVWAP[];
double BufferBuy[];
double BufferSell[];

double g_cumPV[];
double g_cumVol[];

int g_fastEMAHandle = INVALID_HANDLE;
int g_slowEMAHandle = INVALID_HANDLE;
datetime g_lastAlertBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpVWAPSlopeBars < 1 || InpReturnBars < 1 || InpBarsToShow < 1)
   {
      Print("ERRO: InpVWAPSlopeBars, InpReturnBars e InpBarsToShow devem ser maiores que zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, BufferVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufferBuy, INDICATOR_DATA);
   SetIndexBuffer(2, BufferSell, INDICATOR_DATA);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(1, PLOT_ARROW, 233); // seta para cima
   PlotIndexSetInteger(2, PLOT_ARROW, 234); // seta para baixo

   if(!InpShowVWAP)
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);

   if(InpUseEMAFilter)
   {
      g_fastEMAHandle = iMA(_Symbol, PERIOD_CURRENT, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_slowEMAHandle = iMA(_Symbol, PERIOD_CURRENT, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_fastEMAHandle == INVALID_HANDLE || g_slowEMAHandle == INVALID_HANDLE)
      {
         Print("ERRO: nao foi possivel criar as medias EMA. GetLastError=", GetLastError());
         return INIT_FAILED;
      }
   }

   IndicatorSetString(INDICATOR_SHORTNAME, _Symbol + " DriftPullback Sinais");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fastEMAHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastEMAHandle);
   if(g_slowEMAHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowEMAHandle);
   Comment("");
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
datetime SessionStartForBar(const datetime server_time)
{
   MqlDateTime dt;
   TimeToStruct(ToStrategyTime(server_time), dt);
   dt.hour = InpSessionStartHHMM / 100;
   dt.min  = InpSessionStartHHMM % 100;
   dt.sec  = 0;
   return StructToTime(dt) - InpStrategyTimeOffsetMinutes * 60;
}

//+------------------------------------------------------------------+
void RecalcVWAP(const int start, const int rates_total,
                 const datetime &time[], const double &high[],
                 const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[])
{
   for(int i = start; i < rates_total; i++)
   {
      double cumPV  = (i > 0) ? g_cumPV[i - 1]  : 0.0;
      double cumVol = (i > 0) ? g_cumVol[i - 1] : 0.0;

      bool new_day = (i == 0) || (StrategyDateKey(time[i]) != StrategyDateKey(time[i - 1]));
      if(new_day)
      {
         cumPV  = 0.0;
         cumVol = 0.0;
      }

      datetime session_start = SessionStartForBar(time[i]);
      if(time[i] < session_start)
      {
         g_cumPV[i]  = cumPV;
         g_cumVol[i] = cumVol;
         BufferVWAP[i] = EMPTY_VALUE;
         continue;
      }

      long vol = volume[i] > 0 ? volume[i] : tick_volume[i];
      double typical = (high[i] + low[i] + close[i]) / 3.0;
      cumPV  += typical * (double)vol;
      cumVol += (double)vol;

      g_cumPV[i]  = cumPV;
      g_cumVol[i] = cumVol;
      BufferVWAP[i] = cumVol > 0.0 ? cumPV / cumVol : EMPTY_VALUE;
   }
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                 const int prev_calculated,
                 const datetime &time[],
                 const double &open[],
                 const double &high[],
                 const double &low[],
                 const double &close[],
                 const long &tick_volume[],
                 const long &volume[],
                 const int &spread[])
{
   int warmup = MathMax(InpSlowEMAPeriod, MathMax(InpReturnBars, InpVWAPSlopeBars)) + 2;
   if(rates_total <= warmup)
      return rates_total;

   bool first_run = (prev_calculated <= 0 || ArraySize(g_cumPV) != rates_total);
   if(ArraySize(g_cumPV) != rates_total)
      ArrayResize(g_cumPV, rates_total);
   if(ArraySize(g_cumVol) != rates_total)
      ArrayResize(g_cumVol, rates_total);

   if(first_run)
   {
      ArrayInitialize(BufferVWAP, EMPTY_VALUE);
      ArrayInitialize(BufferBuy, EMPTY_VALUE);
      ArrayInitialize(BufferSell, EMPTY_VALUE);
   }

   int vwap_start = first_run ? 0 : MathMax(0, prev_calculated - 1);
   RecalcVWAP(vwap_start, rates_total, time, high, low, close, tick_volume, volume);

   // A simulacao de posicao/limites diarios e sequencial (depende do que aconteceu nos
   // candles anteriores), entao a janela de sinal e sempre recalculada do zero a cada chamada.
   int signal_start = MathMax(warmup, rates_total - InpBarsToShow);

   double fastEma[];
   double slowEma[];
   if(InpUseEMAFilter)
   {
      int count = MathMin(rates_total, (rates_total - signal_start) + 5);
      ArraySetAsSeries(fastEma, true);
      ArraySetAsSeries(slowEma, true);
      if(CopyBuffer(g_fastEMAHandle, 0, 0, count, fastEma) <= 0 ||
         CopyBuffer(g_slowEMAHandle, 0, 0, count, slowEma) <= 0)
         return rates_total;
   }

   string panel = "";

   // Estado simulado da posicao, para reproduzir o HasOurPosition()/limites diarios do EA
   // e nao marcar sinais que o robo nunca teria tomado.
   bool   in_position      = false;
   int    position_dir     = 0;     // 1 = comprado, -1 = vendido
   double position_stop    = 0.0;
   double position_target  = 0.0;
   int    current_day      = -1;
   int    trades_today     = 0;
   int    losses_today     = 0;

   for(int i = signal_start; i < rates_total; i++)
   {
      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      int day_key = StrategyDateKey(time[i]);
      if(day_key != current_day)
      {
         current_day  = day_key;
         trades_today = 0;
         losses_today = 0;
      }

      bool was_open_at_start = in_position;

      // 1) Verifica se a posicao simulada fecha neste candle (stop, alvo ou zeragem por horario).
      if(in_position)
      {
         bool hit_stop = false;
         bool hit_target = false;
         if(position_dir == 1)
         {
            hit_stop   = low[i]  <= position_stop;
            hit_target = high[i] >= position_target;
         }
         else
         {
            hit_stop   = high[i] >= position_stop;
            hit_target = low[i]  <= position_target;
         }

         bool force_close = HHMM(time[i]) >= InpForceCloseHHMM;

         if(hit_stop || hit_target || force_close)
         {
            bool is_loss = hit_stop || force_close;
            if(hit_target)
               is_loss = false;
            if(is_loss)
               losses_today++;
            in_position = false;
         }
      }

      // 2) So avalia um novo gatilho se a posicao ja estava zerada antes deste candle
      //    (mesma regra do EA: nunca abre e fecha no mesmo candle avaliado).
      if(was_open_at_start)
         continue;
      if(trades_today >= InpMaxTradesPerDay || losses_today >= InpMaxLossesPerDay)
         continue;

      int s1 = i;
      int s2 = i - 1;
      int slope_ref = i - InpVWAPSlopeBars;
      int return_ref = i - InpReturnBars;
      if(s2 < 0 || slope_ref < 0 || return_ref < 0)
         continue;

      double vwap1 = BufferVWAP[s1];
      double vwap2 = BufferVWAP[s2];
      double vwap_slope_ref = BufferVWAP[slope_ref];
      if(vwap1 == EMPTY_VALUE || vwap1 <= 0.0 ||
         vwap2 == EMPTY_VALUE || vwap2 <= 0.0 ||
         vwap_slope_ref == EMPTY_VALUE || vwap_slope_ref <= 0.0)
         continue;

      double close1 = close[s1];
      double open1  = open[s1];
      double high1  = high[s1];
      double low1   = low[s1];
      double close2 = close[s2];
      double open2  = open[s2];
      double close_return_ref = close[return_ref];
      if(close_return_ref <= 0.0)
         continue;

      double return_pct = (close1 / close_return_ref - 1.0) * 100.0;
      bool vwap_rising  = vwap1 > vwap_slope_ref;
      bool vwap_falling = vwap1 < vwap_slope_ref;

      bool ema_long = true;
      bool ema_short = true;
      if(InpUseEMAFilter)
      {
         int shift = rates_total - 1 - s1;
         if(shift < 0 || shift >= ArraySize(fastEma) || shift >= ArraySize(slowEma))
            continue;
         double fast_ema = fastEma[shift];
         double slow_ema = slowEma[shift];
         ema_long  = close1 > fast_ema && fast_ema > slow_ema;
         ema_short = close1 < fast_ema && fast_ema < slow_ema;
      }

      bool regime_long  = close1 > vwap1 && vwap_rising  && return_pct >=  InpMinimumReturnPct && ema_long;
      bool regime_short = close1 < vwap1 && vwap_falling && return_pct <= -InpMinimumReturnPct && ema_short;

      double distance = MathAbs(close1 - vwap1);
      double previous_distance = MathAbs(close2 - vwap2);
      double body = MathAbs(close1 - open1);

      bool distance_ok = InpMaxDistanceFromVWAPPoints <= 0.0 || distance <= InpMaxDistanceFromVWAPPoints;
      bool body_ok = (InpMinBodyPoints <= 0.0 || body >= InpMinBodyPoints) &&
                     (InpMaxBodyPoints <= 0.0 || body <= InpMaxBodyPoints);
      bool first_red   = !InpRequireFirstOppositeCandle || close2 >= open2;
      bool first_green = !InpRequireFirstOppositeCandle || close2 <= open2;
      bool whole_above = !InpRequireWholeCandleSide || low1 > vwap1;
      bool whole_below = !InpRequireWholeCandleSide || high1 < vwap1;

      bool long_trigger = regime_long && close1 < open1 && first_red && whole_above &&
                           distance < previous_distance && distance_ok && body_ok;
      bool short_trigger = regime_short && close1 > open1 && first_green && whole_below &&
                            distance < previous_distance && distance_ok && body_ok;

      int strategy_hhmm = HHMM(time[s1]);
      bool within_entry_window = strategy_hhmm >= InpEntryStartHHMM && strategy_hhmm <= InpLastEntryHHMM;
      long_trigger  = long_trigger  && within_entry_window;
      short_trigger = short_trigger && within_entry_window;

      if(!long_trigger && !short_trigger)
         continue;

      double offset = MathMax((high1 - low1) * 0.3, 5 * _Point);

      // Abre a posicao simulada com o mesmo stop/alvo do EA, para bloquear novos
      // sinais ate ela fechar (igual ao HasOurPosition()).
      if(long_trigger)
      {
         BufferBuy[i] = low1 - offset;
         in_position     = true;
         position_dir    = 1;
         position_stop   = close1 - InpLongStopPoints;
         position_target = close1 + InpLongTargetPoints;
         trades_today++;
         panel = StringFormat("COMPRA em %s | preco=%s | VWAP=%s",
                               TimeToString(time[i], TIME_DATE | TIME_MINUTES),
                               DoubleToString(close1, _Digits),
                               DoubleToString(vwap1, _Digits));
      }
      else if(short_trigger)
      {
         BufferSell[i] = high1 + offset;
         in_position     = true;
         position_dir    = -1;
         position_stop   = close1 + InpShortStopPoints;
         position_target = close1 - InpShortTargetPoints;
         trades_today++;
         panel = StringFormat("VENDA em %s | preco=%s | VWAP=%s",
                               TimeToString(time[i], TIME_DATE | TIME_MINUTES),
                               DoubleToString(close1, _Digits),
                               DoubleToString(vwap1, _Digits));
      }
   }

   // Alerta apenas para o ultimo candle fechado (evita repeticao a cada tick).
   int closed_bar = rates_total - 2;
   if(closed_bar >= signal_start && closed_bar >= 0 && time[closed_bar] != g_lastAlertBarTime)
   {
      bool has_signal = (BufferBuy[closed_bar] != EMPTY_VALUE) || (BufferSell[closed_bar] != EMPTY_VALUE);
      if(has_signal)
      {
         string side = (BufferBuy[closed_bar] != EMPTY_VALUE) ? "COMPRA" : "VENDA";
         string msg = StringFormat("%s Drift Pullback: sinal de %s em %s a %s",
                                    _Symbol, side,
                                    TimeToString(time[closed_bar], TIME_DATE | TIME_MINUTES),
                                    DoubleToString(close[closed_bar], _Digits));
         if(InpAlertLog)
            Print(msg);
         if(InpAlertPopup)
            Alert(msg);
         if(InpAlertPush)
            SendNotification(msg);
         g_lastAlertBarTime = time[closed_bar];
      }
   }

   if(InpShowInfoPanel)
   {
      int last = rates_total - 1;
      string status = StringFormat("%s Drift Pullback | VWAP=%s | %s",
                                    _Symbol,
                                    BufferVWAP[last] != EMPTY_VALUE ? DoubleToString(BufferVWAP[last], _Digits) : "n/d",
                                    panel != "" ? panel : "sem sinal recente na janela exibida");
      Comment(status);
   }
   else
   {
      Comment("");
   }

   return rates_total;
}
