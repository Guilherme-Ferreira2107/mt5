//+------------------------------------------------------------------+
//| structural-stop.mqh                                               |
//| Duas formas de calcular stop, extraidas de zig-zag_rsi_adx.mq5.    |
//| Escolha uma por estrategia -- nao use as duas ao mesmo tempo.      |
//+------------------------------------------------------------------+
#property strict

//====================== OPCAO A: lookback simples ======================
// Stop = extremo (high/low) das ultimas N barras fechadas. Simples,
// nao precisa de indicador extra. Bom default quando a estrategia nao
// depende de estrutura de topos/fundos.
//
// input int StopLookbackBars = 3;
//
// int stop_bars = MathMax(1, StopLookbackBars);
// double highest_recent_high = mrate[1].high;
// double lowest_recent_low   = mrate[1].low;
// int bars_for_stop = MathMin(stop_bars, ArraySize(mrate) - 1);
// for (int i = 1; i <= bars_for_stop; i++)
// {
//    if (mrate[i].high > highest_recent_high) highest_recent_high = mrate[i].high;
//    if (mrate[i].low  < lowest_recent_low)    lowest_recent_low  = mrate[i].low;
// }
// // buy_sl  = lowest_recent_low; sell_sl = highest_recent_high;

//====================== OPCAO B: pivos confirmados do ZigZag ==========
// Stop/filtro de tendencia baseado em topos e fundos REAIS da estrutura
// (indicador Examples\ZigZag). Mais robusto para estrategias de swing
// que precisam confirmar "fundo ascendente" / "topo descendente" antes
// de operar. Requer:
//   int zigzag_handle = iCustom(_Symbol, _Period, "Examples\\ZigZag",
//                                InpDepth, InpDeviation, InpBackstep);
//   input int ZigZagLookbackBars = 300; // barras usadas para ler a estrutura

bool GetConfirmedAscendingLows(const int zigzag_handle, const int lookback_bars,
                                double &last_low, double &previous_low)
{
   last_low = EMPTY_VALUE;
   previous_low = EMPTY_VALUE;

   int bars_to_copy = MathMin(Bars(_Symbol, _Period), lookback_bars);
   if (bars_to_copy < 10)
      return false;

   double zigzag_buffer[], high_buffer[], low_buffer[];
   ArraySetAsSeries(zigzag_buffer, true);
   ArraySetAsSeries(high_buffer, true);
   ArraySetAsSeries(low_buffer, true);

   if (CopyBuffer(zigzag_handle, 0, 0, bars_to_copy, zigzag_buffer) <= 0) return false;
   if (CopyBuffer(zigzag_handle, 1, 0, bars_to_copy, high_buffer) <= 0) return false;
   if (CopyBuffer(zigzag_handle, 2, 0, bars_to_copy, low_buffer) <= 0) return false;

   double pivot_values[];
   bool pivot_is_high[];
   ArrayResize(pivot_values, bars_to_copy);
   ArrayResize(pivot_is_high, bars_to_copy);
   int pivot_count = 0;

   for (int i = bars_to_copy - 1; i >= 0; i--)
   {
      double zz = zigzag_buffer[i];
      if (zz == 0.0 || zz == EMPTY_VALUE) continue;

      bool is_high_pivot = (high_buffer[i] != 0.0 && high_buffer[i] != EMPTY_VALUE && MathAbs(zz - high_buffer[i]) <= _Point * 2.0);
      bool is_low_pivot  = (low_buffer[i]  != 0.0 && low_buffer[i]  != EMPTY_VALUE && MathAbs(zz - low_buffer[i])  <= _Point * 2.0);
      if (!is_high_pivot && !is_low_pivot) continue;

      pivot_values[pivot_count] = zz;
      pivot_is_high[pivot_count] = is_high_pivot;
      pivot_count++;
   }

   if (pivot_count < 3) return false;

   double confirmed_lows[];
   ArrayResize(confirmed_lows, pivot_count);
   int confirmed_low_count = 0;

   // O ultimo pivo visual do ZigZag ainda pode repintar -- nao e tratado
   // como confirmado.
   for (int p = 0; p < pivot_count - 1; p++)
   {
      if (!pivot_is_high[p])
      {
         confirmed_lows[confirmed_low_count] = pivot_values[p];
         confirmed_low_count++;
      }
   }

   if (confirmed_low_count < 2) return false;

   last_low = confirmed_lows[confirmed_low_count - 1];
   previous_low = confirmed_lows[confirmed_low_count - 2];
   return (last_low > previous_low);
}

bool GetConfirmedDescendingHighs(const int zigzag_handle, const int lookback_bars,
                                  double &last_high, double &previous_high)
{
   last_high = EMPTY_VALUE;
   previous_high = EMPTY_VALUE;

   int bars_to_copy = MathMin(Bars(_Symbol, _Period), lookback_bars);
   if (bars_to_copy < 10)
      return false;

   double zigzag_buffer[], high_buffer[], low_buffer[];
   ArraySetAsSeries(zigzag_buffer, true);
   ArraySetAsSeries(high_buffer, true);
   ArraySetAsSeries(low_buffer, true);

   if (CopyBuffer(zigzag_handle, 0, 0, bars_to_copy, zigzag_buffer) <= 0) return false;
   if (CopyBuffer(zigzag_handle, 1, 0, bars_to_copy, high_buffer) <= 0) return false;
   if (CopyBuffer(zigzag_handle, 2, 0, bars_to_copy, low_buffer) <= 0) return false;

   double pivot_values[];
   bool pivot_is_high[];
   ArrayResize(pivot_values, bars_to_copy);
   ArrayResize(pivot_is_high, bars_to_copy);
   int pivot_count = 0;

   for (int i = bars_to_copy - 1; i >= 0; i--)
   {
      double zz = zigzag_buffer[i];
      if (zz == 0.0 || zz == EMPTY_VALUE) continue;

      bool is_high_pivot = (high_buffer[i] != 0.0 && high_buffer[i] != EMPTY_VALUE && MathAbs(zz - high_buffer[i]) <= _Point * 2.0);
      bool is_low_pivot  = (low_buffer[i]  != 0.0 && low_buffer[i]  != EMPTY_VALUE && MathAbs(zz - low_buffer[i])  <= _Point * 2.0);
      if (!is_high_pivot && !is_low_pivot) continue;

      pivot_values[pivot_count] = zz;
      pivot_is_high[pivot_count] = is_high_pivot;
      pivot_count++;
   }

   if (pivot_count < 3) return false;

   double confirmed_highs[];
   ArrayResize(confirmed_highs, pivot_count);
   int confirmed_high_count = 0;

   for (int p = 0; p < pivot_count - 1; p++)
   {
      if (pivot_is_high[p])
      {
         confirmed_highs[confirmed_high_count] = pivot_values[p];
         confirmed_high_count++;
      }
   }

   if (confirmed_high_count < 2) return false;

   last_high = confirmed_highs[confirmed_high_count - 1];
   previous_high = confirmed_highs[confirmed_high_count - 2];
   return (last_high < previous_high);
}
