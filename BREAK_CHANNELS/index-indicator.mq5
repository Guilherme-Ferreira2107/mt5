//+------------------------------------------------------------------+
//|                                         Quebra_Broker Expert.mq5 |
//|                                               Guilherme Ferreira |
//|                                  guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.40"
#property description "Modo de uso:"
#property description "Fundos ascendentes: candle do segundo fundo em amarelo."
#property description "Topos descendentes: candle do segundo topo em vermelho."
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots 4

//--- plot candles coloridos
#property indicator_label1 "Padrao"
#property indicator_type1 DRAW_COLOR_CANDLES
#property indicator_color1 clrYellow, clrRed
#property indicator_style1 STYLE_SOLID
#property indicator_width1 1

//--- plot ZigZag
#property indicator_label2 "ZigZag"
#property indicator_type2 DRAW_SECTION
#property indicator_color2 clrDodgerBlue
#property indicator_style2 STYLE_SOLID
#property indicator_width2 1

//--- plot Compra
#property indicator_label3 "Compra"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 clrGreen
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

//--- plot Venda
#property indicator_label4 "Venda"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 clrRed
#property indicator_style4 STYLE_SOLID
#property indicator_width4 3

//--- indicator buffers
double CandleOpenBuffer[];
double CandleHighBuffer[];
double CandleLowBuffer[];
double CandleCloseBuffer[];
double CandleColorBuffer[];
double ZigZag_Buffer[];
double Compra_Buffer[];
double Venda_Buffer[];
double ZigZagHighBuffer[];
double ZigZagLowBuffer[];

//--- parametros
input int InpDepth = 12;    // ZigZag Depth
input int InpDeviation = 5; // ZigZag Deviation
input int InpBackstep = 3;  // ZigZag Backstep
input bool VerificaAlerta = false;

//--- handle do indicador
int zigzag_handle = INVALID_HANDLE;

//--- ultimos pivots confirmados do ZigZag
double UltimoTopo = EMPTY_VALUE;
double PenultimoTopo = EMPTY_VALUE;
double UltimoFundo = EMPTY_VALUE;
double PenultimoFundo = EMPTY_VALUE;
bool FundosAscendentes = false;
bool ToposDescendentes = false;

int OnInit()
{
  zigzag_handle = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
  if (zigzag_handle == INVALID_HANDLE)
  {
    Print("Erro ao carregar ZigZag: ", GetLastError());
    return INIT_FAILED;
  }

  SetIndexBuffer(0, CandleOpenBuffer, INDICATOR_DATA);
  SetIndexBuffer(1, CandleHighBuffer, INDICATOR_DATA);
  SetIndexBuffer(2, CandleLowBuffer, INDICATOR_DATA);
  SetIndexBuffer(3, CandleCloseBuffer, INDICATOR_DATA);
  SetIndexBuffer(4, CandleColorBuffer, INDICATOR_COLOR_INDEX);
  SetIndexBuffer(5, ZigZag_Buffer, INDICATOR_DATA);
  SetIndexBuffer(6, Compra_Buffer, INDICATOR_DATA);
  SetIndexBuffer(7, Venda_Buffer, INDICATOR_DATA);

  ArraySetAsSeries(CandleOpenBuffer, true);
  ArraySetAsSeries(CandleHighBuffer, true);
  ArraySetAsSeries(CandleLowBuffer, true);
  ArraySetAsSeries(CandleCloseBuffer, true);
  ArraySetAsSeries(CandleColorBuffer, true);
  ArraySetAsSeries(ZigZag_Buffer, true);
  ArraySetAsSeries(Compra_Buffer, true);
  ArraySetAsSeries(Venda_Buffer, true);
  ArraySetAsSeries(ZigZagHighBuffer, true);
  ArraySetAsSeries(ZigZagLowBuffer, true);

  PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
  PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
  PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
  PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);

  PlotIndexSetInteger(2, PLOT_ARROW, 225);
  PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 25);
  PlotIndexSetInteger(3, PLOT_ARROW, 226);
  PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, -25);

  IndicatorSetString(INDICATOR_SHORTNAME, "Break Channels + ZigZag");

  long chart_id = ChartID();
  if (chart_id > 0)
  {
    ChartSetInteger(chart_id, CHART_SHIFT, true);
    ChartSetInteger(chart_id, CHART_MODE, CHART_CANDLES);
    ChartSetInteger(chart_id, CHART_FOREGROUND, false);
  }

  return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
  if (zigzag_handle != INVALID_HANDLE)
    IndicatorRelease(zigzag_handle);
}

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
  if (rates_total <= 0)
    return 0;

  if (BarsCalculated(zigzag_handle) < rates_total)
    return prev_calculated;

  if (CopyBuffer(zigzag_handle, 0, 0, rates_total, ZigZag_Buffer) <= 0)
  {
    Print("Erro ao copiar buffer do ZigZag: ", GetLastError());
    return prev_calculated;
  }
  if (CopyBuffer(zigzag_handle, 1, 0, rates_total, ZigZagHighBuffer) <= 0)
  {
    Print("Erro ao copiar buffer de topos do ZigZag: ", GetLastError());
    return prev_calculated;
  }
  if (CopyBuffer(zigzag_handle, 2, 0, rates_total, ZigZagLowBuffer) <= 0)
  {
    Print("Erro ao copiar buffer de fundos do ZigZag: ", GetLastError());
    return prev_calculated;
  }

  int pivot_indices[];
  double pivot_values[];
  bool pivot_is_high[];
  ArrayResize(pivot_indices, rates_total);
  ArrayResize(pivot_values, rates_total);
  ArrayResize(pivot_is_high, rates_total);
  int pivot_count = 0;

  for (int i = rates_total - 1; i >= 0; i--)
  {
    CandleOpenBuffer[i] = 0.0;
    CandleHighBuffer[i] = 0.0;
    CandleLowBuffer[i] = 0.0;
    CandleCloseBuffer[i] = 0.0;
    CandleColorBuffer[i] = 0.0;
    Compra_Buffer[i] = 0.0;
    Venda_Buffer[i] = 0.0;

    double zz = ZigZag_Buffer[i];
    double zzHigh = ZigZagHighBuffer[i];
    double zzLow = ZigZagLowBuffer[i];
    if (zz == 0.0 || zz == EMPTY_VALUE)
      continue;

    bool is_high_pivot = (zzHigh != 0.0 && zzHigh != EMPTY_VALUE && MathAbs(zz - zzHigh) <= _Point * 2.0);
    bool is_low_pivot = (zzLow != 0.0 && zzLow != EMPTY_VALUE && MathAbs(zz - zzLow) <= _Point * 2.0);

    if (!is_high_pivot && !is_low_pivot)
    {
      if (MathAbs(zz - high[i]) <= _Point * 2.0)
        is_high_pivot = true;
      else if (MathAbs(zz - low[i]) <= _Point * 2.0)
        is_low_pivot = true;
    }

    if (is_low_pivot)
    {
      Compra_Buffer[i] = zz;
      pivot_indices[pivot_count] = i;
      pivot_values[pivot_count] = zz;
      pivot_is_high[pivot_count] = false;
      pivot_count++;
    }
    else if (is_high_pivot)
    {
      Venda_Buffer[i] = zz;
      pivot_indices[pivot_count] = i;
      pivot_values[pivot_count] = zz;
      pivot_is_high[pivot_count] = true;
      pivot_count++;
    }
  }

  UltimoTopo = EMPTY_VALUE;
  PenultimoTopo = EMPTY_VALUE;
  UltimoFundo = EMPTY_VALUE;
  PenultimoFundo = EMPTY_VALUE;
  FundosAscendentes = false;
  ToposDescendentes = false;

  if (pivot_count > 1)
  {
    int confirmed_high_indices[];
    double confirmed_high_values[];
    int confirmed_low_indices[];
    double confirmed_low_values[];
    ArrayResize(confirmed_high_indices, pivot_count);
    ArrayResize(confirmed_high_values, pivot_count);
    ArrayResize(confirmed_low_indices, pivot_count);
    ArrayResize(confirmed_low_values, pivot_count);
    int confirmed_high_count = 0;
    int confirmed_low_count = 0;

    // Todos os pivots visuais, exceto o ultimo da sequencia, sao tratados como confirmados.
    for (int p = 0; p < pivot_count - 1; p++)
    {
      if (pivot_is_high[p])
      {
        confirmed_high_indices[confirmed_high_count] = pivot_indices[p];
        confirmed_high_values[confirmed_high_count] = pivot_values[p];
        confirmed_high_count++;
      }
      else
      {
        confirmed_low_indices[confirmed_low_count] = pivot_indices[p];
        confirmed_low_values[confirmed_low_count] = pivot_values[p];
        confirmed_low_count++;
      }
    }

    if (confirmed_high_count >= 1)
      UltimoTopo = confirmed_high_values[confirmed_high_count - 1];
    if (confirmed_high_count >= 2)
      PenultimoTopo = confirmed_high_values[confirmed_high_count - 2];

    if (confirmed_low_count >= 1)
      UltimoFundo = confirmed_low_values[confirmed_low_count - 1];
    if (confirmed_low_count >= 2)
      PenultimoFundo = confirmed_low_values[confirmed_low_count - 2];

    FundosAscendentes = (UltimoFundo != EMPTY_VALUE && PenultimoFundo != EMPTY_VALUE && UltimoFundo > PenultimoFundo);
    ToposDescendentes = (UltimoTopo != EMPTY_VALUE && PenultimoTopo != EMPTY_VALUE && UltimoTopo < PenultimoTopo);

    if (FundosAscendentes && confirmed_low_count >= 1)
    {
      int bar_index = confirmed_low_indices[confirmed_low_count - 1];
      CandleOpenBuffer[bar_index] = open[bar_index];
      CandleHighBuffer[bar_index] = high[bar_index];
      CandleLowBuffer[bar_index] = low[bar_index];
      CandleCloseBuffer[bar_index] = close[bar_index];
      CandleColorBuffer[bar_index] = 0.0; // amarelo
    }

    if (ToposDescendentes && confirmed_high_count >= 1)
    {
      int bar_index = confirmed_high_indices[confirmed_high_count - 1];
      CandleOpenBuffer[bar_index] = open[bar_index];
      CandleHighBuffer[bar_index] = high[bar_index];
      CandleLowBuffer[bar_index] = low[bar_index];
      CandleCloseBuffer[bar_index] = close[bar_index];
      CandleColorBuffer[bar_index] = 1.0; // vermelho
    }
  }

  Comment(
      "UltimoTopoConfirmado: ", (UltimoTopo == EMPTY_VALUE ? "n/a" : DoubleToString(UltimoTopo, _Digits)), "\n",
      "PenultimoTopoConfirmado: ", (PenultimoTopo == EMPTY_VALUE ? "n/a" : DoubleToString(PenultimoTopo, _Digits)), "\n",
      "UltimoFundoConfirmado: ", (UltimoFundo == EMPTY_VALUE ? "n/a" : DoubleToString(UltimoFundo, _Digits)), "\n",
      "PenultimoFundoConfirmado: ", (PenultimoFundo == EMPTY_VALUE ? "n/a" : DoubleToString(PenultimoFundo, _Digits)), "\n",
      "FundosAscendentes: ", (FundosAscendentes ? "true" : "false"), "\n",
      "ToposDescendentes: ", (ToposDescendentes ? "true" : "false"));

  return (rates_total);
}
//+------------------------------------------------------------------+
