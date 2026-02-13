//+------------------------------------------------------------------+
//|                                         Quebra_Broker Expert.mq5 |
//|                                               Guilherme Ferreira |
//|                                  guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.6"
#property description "Modo de uso:"
#property description "Quando houver setas verdes, crie ordem de COMPRA para a PROXIMA vela."
#property description "A expiracao da ordem e para a mesma vela. Se necessario, faca ate 02 martingales."
#property description "Quando houver setas vermelhas, crie ordem de VENDA para a PROXIMA vela."
#property description "A expiracao da ordem e para a mesma vela. Se necessario, faca ate 02 martingales."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots 5

//--- plot MA
#property indicator_label1 "MA"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrGray
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

//--- plot Compra
#property indicator_label2 "Compra"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrLime
#property indicator_style2 STYLE_SOLID
#property indicator_width2 3

//--- plot Venda
#property indicator_label3 "Venda"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 clrRed
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

//--- plot Envelope Superior
#property indicator_label4 "EnvelopeSup"
#property indicator_type4 DRAW_LINE
#property indicator_color4 clrDarkGray
#property indicator_style4 STYLE_DOT
#property indicator_width4 1

//--- plot Envelope Inferior
#property indicator_label5 "EnvelopeInf"
#property indicator_type5 DRAW_LINE
#property indicator_color5 clrDarkGray
#property indicator_style5 STYLE_DOT
#property indicator_width5 1

//--- indicator buffers
double MA_Buffer[];
double Compra_Buffer[];
double Venda_Buffer[];
double EnvelopeSup_Buffer[];
double EnvelopeInf_Buffer[];

//--- parametros
input int MA_Periodo = 14;          // Periodo MA
input double EnvelopeDesvio = 0.15; // Desvio do envelope em porcentagem
int SHIFT = 0;

int OnInit()
{
  SetIndexBuffer(0, MA_Buffer, INDICATOR_DATA);
  SetIndexBuffer(1, Compra_Buffer, INDICATOR_DATA);
  SetIndexBuffer(2, Venda_Buffer, INDICATOR_DATA);
  SetIndexBuffer(3, EnvelopeSup_Buffer, INDICATOR_DATA);
  SetIndexBuffer(4, EnvelopeInf_Buffer, INDICATOR_DATA);

  PlotIndexSetInteger(1, PLOT_ARROW, 225);
  PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 25);
  PlotIndexSetInteger(2, PLOT_ARROW, 226);
  PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, -25);

  long handle = ChartID();

  if (handle > 0)
  {
    //--- Define o encaixe da borda direita do grafico
    ChartSetInteger(handle, CHART_SHIFT, true);
    //--- Exibe como candles
    ChartSetInteger(handle, CHART_MODE, CHART_CANDLES);
  }

  return (INIT_SUCCEEDED);
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
  // --- Media Movel Simples
  CopyBuffer(iMA(_Symbol, _Period, MA_Periodo, SHIFT, MODE_SMA, PRICE_CLOSE), 0, 0, rates_total, MA_Buffer);
  CopyBuffer(iEnvelopes(_Symbol, _Period, MA_Periodo, SHIFT, MODE_SMA, PRICE_CLOSE, EnvelopeDesvio), 0, 0, rates_total, EnvelopeSup_Buffer);
  CopyBuffer(iEnvelopes(_Symbol, _Period, MA_Periodo, SHIFT, MODE_SMA, PRICE_CLOSE, EnvelopeDesvio), 1, 0, rates_total, EnvelopeInf_Buffer);

  for (int i = MathMax(2, prev_calculated - 1); i < rates_total; i++)
  {
    bool sinalVenda = close[i - 1] > EnvelopeSup_Buffer[i - 1] && close[i - 0] < EnvelopeSup_Buffer[i - 0] && high[i - 2] > high[i - 1];
    bool sinalCompra = close[i - 1] < EnvelopeInf_Buffer[i - 1] && close[i - 0] > EnvelopeInf_Buffer[i - 0] && low[i - 2] < low[i - 1];

    Compra_Buffer[i] = sinalCompra ? low[i] : 0;
    Venda_Buffer[i] = sinalVenda ? high[i] : 0;
  }

  Comment("--- QB --- " + TimeCurrent());

  return (rates_total);
}
//+------------------------------------------------------------------+
