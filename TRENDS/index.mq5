//+------------------------------------------------------------------+
//|                                          PriceAction_Trend_Entry |
//|                                      Autor: Guilherme Ferreira   |
//|                             Email: guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.0"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots 2

//--- Seta de Compra
#property indicator_label1 "Compra"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLime
#property indicator_width1 2
#property indicator_style1 STYLE_SOLID

//--- Seta de Venda
#property indicator_label2 "Venda"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrRed
#property indicator_width2 2
#property indicator_style2 STYLE_SOLID

//--- Buffers
double BuyBuffer[];
double SellBuffer[];

//--- Inputs
input int EMA_Fast = 50;
input int EMA_Slow = 200;
input double ArrowShift = 25.0;

//--- Handles
int handleEMAfast, handleEMAslow;

int OnInit()
{
    SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);

    PlotIndexSetInteger(0, PLOT_ARROW, 233); // Up arrow
    PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, ArrowShift);
    PlotIndexSetInteger(1, PLOT_ARROW, 234); // Down arrow
    PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, -ArrowShift);

    handleEMAfast = iMA(_Symbol, _Period, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
    handleEMAslow = iMA(_Symbol, _Period, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

    if (handleEMAfast < 0 || handleEMAslow < 0)
    {
        Print("Erro ao criar indicadores: ", GetLastError());
        return (INIT_FAILED);
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
    if (rates_total < EMA_Slow + 2)
        return 0;

    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);

    CopyBuffer(handleEMAfast, 0, 0, rates_total, emaFast);
    CopyBuffer(handleEMAslow, 0, 0, rates_total, emaSlow);

    int start;
    if (prev_calculated == 0)
        start = rates_total - 2;
    else
        start = rates_total - prev_calculated;

    if (start > rates_total - 2)
        start = rates_total - 2;

    if (start < EMA_Slow)
        start = EMA_Slow;

    for (int i = start; i >= 0; --i)
    {
        BuyBuffer[i] = 0;
        SellBuffer[i] = 0;

        bool crossUp = (emaFast[i] > emaSlow[i] && emaFast[i + 1] <= emaSlow[i + 1]);
        bool crossDown = (emaFast[i] < emaSlow[i] && emaFast[i + 1] >= emaSlow[i + 1]);

        // Compra quando a EMA rapida cruza acima da EMA lenta
        if (crossUp)
            BuyBuffer[i] = low[i] - (ArrowShift * _Point);

        // Venda quando a EMA rapida cruza abaixo da EMA lenta
        if (crossDown)
            SellBuffer[i] = high[i] + (ArrowShift * _Point);
    }

    Comment("--- QB --- ",
            DoubleToString(emaFast[0], _Digits),
            " ---- ",
            DoubleToString(emaSlow[0], _Digits));

    return (rates_total);
}


