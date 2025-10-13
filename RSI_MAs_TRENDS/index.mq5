//+------------------------------------------------------------------+
//|                                         Quebra_Broker Expert.mq5 |
//|                                               Guilherme Ferreira |
//|                                  guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.6"
#property description "Modo de uso:"
#property description "Quando houver setas verde, crie ordem de COMPRA para a PRÓXIMA vela."
#property description "A expiração da ordem é para a mesma vela. Se necessário, faça até 02 martingales."
#property description "Quando houver setas vermelhas, crie ordem de VENDA para a PRÓXIMA vela."
#property description "A expiração da ordem é para a mesma vela. Se necessário, faça até 02 martingales."
#property indicator_chart_window
#property indicator_buffers 12
#property indicator_plots 12

//--- plot MA1
#property indicator_label1 ""
#property indicator_type1 DRAW_NONE
#property indicator_color1 clrGray
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2
//--- plot MA2
#property indicator_label2 ""
#property indicator_type2 DRAW_NONE
#property indicator_color2 clrDarkTurquoise
#property indicator_style2 STYLE_SOLID
#property indicator_width2 1
//--- plot MA3
#property indicator_label3 ""
#property indicator_type3 DRAW_NONE
#property indicator_color3 clrGold
#property indicator_style3 STYLE_SOLID
#property indicator_width3 1

//--- plot Compra
#property indicator_label4 "Compra"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 clrGreen
#property indicator_style4 STYLE_SOLID
#property indicator_width4 3
//--- plot Venda
#property indicator_label5 "Venda"
#property indicator_type5 DRAW_ARROW
#property indicator_color5 clrRed
#property indicator_style5 STYLE_SOLID
#property indicator_width5 3

////--- plot SAR
#property indicator_label6 ""
#property indicator_type6 DRAW_NONE
#property indicator_color6 clrBlue
#property indicator_style6 STYLE_SOLID
#property indicator_width6 1

//--- plotar ADX
#property indicator_label7 ""
#property indicator_type7 DRAW_NONE
#property indicator_color7 clrNONE
#property indicator_style7 STYLE_SOLID
#property indicator_width7 0
//--- plotar DI_plus
#property indicator_label8 ""
#property indicator_type8 DRAW_NONE
#property indicator_color8 clrNONE
#property indicator_style8 STYLE_SOLID
#property indicator_width8 0
//--- plotar DI_minus
#property indicator_label9 ""
#property indicator_type9 DRAW_NONE
#property indicator_color9 clrNONE
#property indicator_style9 STYLE_SOLID
#property indicator_width9 0

//--- plot RSI
#property indicator_label10 ""
#property indicator_type10 DRAW_NONE
#property indicator_style10 STYLE_SOLID
#property indicator_width10 1

//--- indicator buffers
double MA1_Buffer[];
double MA2_Buffer[];
double MA3_Buffer[];
double SAR_Buffer[];
double ADX_Buffer[];
double DI_plus_Buffer[];
double DI_minus_Buffer[];
double RSI_Buffer[];

double Compra_Buffer[];
double Venda_Buffer[];

//--- parametros
input int MA1_Periodo = 20; // Período MA
input int MA2_Periodo = 40; // Período MA2
input int MA3_Periodo = 80; // Período MA3
int SHIFT = 0;
double SAR_step = 0.05;     // SAR
double SAR_maximum = 0.2;   // SAR MAX
INPUT int ADX_Periodo = 30; // Período ADX
input int ADX_Min = 25;     // ADX Mínimo
int DI_plus_Periodo = 0;
int DI_minus_Periodo = 0;
input int RSI_Periodo = 3; // Período RSI
input int RSI_MAX = 94;    // RSI Máximo
input int RSI_MIN = 6;     // RSI Mínimo
int contagem = 0;
input bool VerificaAlerta = false;
input bool Habilita_ADX = false;

int OnInit()
{
  SetIndexBuffer(0, MA1_Buffer, INDICATOR_DATA);
  SetIndexBuffer(1, MA2_Buffer, INDICATOR_DATA);
  SetIndexBuffer(2, MA3_Buffer, INDICATOR_DATA);

  SetIndexBuffer(3, Compra_Buffer, INDICATOR_DATA);
  SetIndexBuffer(4, Venda_Buffer, INDICATOR_DATA);

  SetIndexBuffer(5, SAR_Buffer, INDICATOR_DATA);

  SetIndexBuffer(6, ADX_Buffer, INDICATOR_DATA);
  SetIndexBuffer(7, DI_plus_Buffer, INDICATOR_DATA);
  SetIndexBuffer(8, DI_minus_Buffer, INDICATOR_DATA);

  SetIndexBuffer(9, RSI_Buffer, INDICATOR_DATA);

  PlotIndexSetInteger(3, PLOT_ARROW, 225);
  PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 25);
  PlotIndexSetInteger(4, PLOT_ARROW, 226);
  PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, -25);

  long handle = ChartID();

  if (handle > 0)
  {
    //--- Define o encaixe da borda direita do gráfico
    ChartSetInteger(handle, CHART_SHIFT, true);
    //--- Exibe como candles
    ChartSetInteger(handle, CHART_MODE, CHART_CANDLES);
  }

  //---
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

  // MEDIAS MOVEIS
  CopyBuffer(iMA(_Symbol, _Period, MA1_Periodo, SHIFT, MODE_SMA, PRICE_CLOSE), 0, 0, rates_total, MA1_Buffer);
  CopyBuffer(iMA(_Symbol, _Period, MA2_Periodo, SHIFT, MODE_SMA, PRICE_CLOSE), 0, 0, rates_total, MA2_Buffer);
  CopyBuffer(iMA(_Symbol, _Period, MA3_Periodo, SHIFT, MODE_SMA, PRICE_CLOSE), 0, 0, rates_total, MA3_Buffer);

  // SAR PARABOLICO
  CopyBuffer(iSAR(_Symbol, _Period, SAR_step, SAR_maximum), 0, 0, rates_total, SAR_Buffer);

  // ADX
  CopyBuffer(iADX(_Symbol, _Period, ADX_Periodo), 0, 0, rates_total, ADX_Buffer);

  // RSI
  CopyBuffer(iRSI(_Symbol, _Period, RSI_Periodo, PRICE_CLOSE), 0, 0, rates_total, RSI_Buffer);

  for (int i = MathMax(5, prev_calculated - 1); i < rates_total; i++)
  {
    bool adxMin = Habilita_ADX ? ADX_Buffer[i] >= ADX_Min && : true;

    bool ma1Menorma2 = MA1_Buffer[i] < MA2_Buffer[i];
    bool ma1Menorma3 = MA1_Buffer[i] < MA3_Buffer[i];
    bool ma2Menorma3 = MA2_Buffer[i] < MA3_Buffer[i];

    bool ma1Maiorma2 = MA1_Buffer[i] > MA2_Buffer[i];
    bool ma1Maiorma3 = MA1_Buffer[i] > MA3_Buffer[i];
    bool ma2Maiorma3 = MA2_Buffer[i] > MA3_Buffer[i];

    // Condição de ordem decrescente MA1 < MA2 < MA3
    bool mediasOrdenadasDecrescente = ma1Menorma2 && ma1Menorma3 && ma2Menorma3;

    // Condição de ordem crescente MA1 > MA2 > MA3
    bool mediasOrdenadasCrescente = ma1Maiorma2 && ma1Maiorma3 && ma2Maiorma3;

    bool rsiSinalVenda = RSI_Buffer[i - 1] > RSI_MAX && RSI_Buffer[i] < RSI_MAX;
    bool rsiSinalCompra = RSI_Buffer[i - 1] < RSI_MIN && RSI_Buffer[i] > RSI_MIN;

    // Preço abre e fecha abaixo da MA1, com MA1 < MA2 < MA3
    bool sinalCompra = adxMin && mediasOrdenadasCrescente && rsiSinalCompra;

    bool sinalVenda = adxMin && mediasOrdenadasDecrescente && rsiSinalVenda;

    // ***** PULLBACK DAS MEDIAS ***** //
    Compra_Buffer[i] = sinalCompra ? low[i] : 0;
    Venda_Buffer[i] = sinalVenda ? high[i] : 0;
  }

  Comment("--- QB --- " + TimeCurrent());

  return (rates_total);
}
//+------------------------------------------------------------------+
