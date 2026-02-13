//+------------------------------------------------------------------+
//| MA Cross Arrows - Simples                                        |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots 2

// Plot 0: Setas de Compra
#property indicator_label1 "Buy"
#property indicator_type1 DRAW_ARROW
#property indicator_color1 clrLime
#property indicator_width1 1

// Plot 1: Setas de Venda
#property indicator_label2 "Sell"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrRed
#property indicator_width2 1

// Inputs
input int FastMAPeriod = 9;
input int SlowMAPeriod = 50;
input ENUM_MA_METHOD MaMethod = MODE_EMA;
input ENUM_APPLIED_PRICE PriceType = PRICE_CLOSE;

input int MACDFastPeriod = 12;
input int MACDSlowPeriod = 26;
input int MACDSignalPeriod = 9;

input int StochKPeriod = 14;
input int StochDPeriod = 3;
input int StochSlowing = 3;
input ENUM_MA_METHOD StochMaMethod = MODE_SMA;
input ENUM_STO_PRICE StochPriceField = STO_LOWHIGH;
input bool EnableStochLogs = false;
input int StochLogBars = 5;

// Offset da seta de venda (em pontos)
input int SellArrowOffsetPoints = 10;

// Offset da seta de compra (em pontos)
input int BuyArrowOffsetPoints = 10;

// Buffers
double buyBuf[], sellBuf[];
double maFast[], maSlow[];
double macdMain[], macdSignal[], macdHist[];
double stochK[], stochD[];

// Cruzamentos
bool CrossUpAt(int i, int rt)
{
    if (i + 1 >= rt)
        return false;
    return (maFast[i] > maSlow[i] && maFast[i + 1] <= maSlow[i + 1]);
}
bool CrossDownAt(int i, int rt)
{
    if (i + 1 >= rt)
        return false;
    return (maFast[i] < maSlow[i] && maFast[i + 1] >= maSlow[i + 1]);
}

int OnInit()
{
    SetIndexBuffer(0, buyBuf, INDICATOR_DATA);
    SetIndexBuffer(1, sellBuf, INDICATOR_DATA);

    ArraySetAsSeries(buyBuf, true);
    ArraySetAsSeries(sellBuf, true);

    PlotIndexSetInteger(0, PLOT_ARROW, 233); // ↑
    PlotIndexSetInteger(1, PLOT_ARROW, 234); // ↓
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    ArraySetAsSeries(maFast, true);
    ArraySetAsSeries(maSlow, true);
    ArraySetAsSeries(macdMain, true);
    ArraySetAsSeries(macdSignal, true);
    ArraySetAsSeries(macdHist, true);
    ArraySetAsSeries(stochK, true);
    ArraySetAsSeries(stochD, true);

    IndicatorSetString(INDICATOR_SHORTNAME, "MA Cross Arrows");
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
    static datetime lastLoggedBarTime = 0;

    if (rates_total < SlowMAPeriod + 5)
        return prev_calculated;

    if (CopyBuffer(iMA(_Symbol, PERIOD_CURRENT, FastMAPeriod, 0, MaMethod, PriceType), 0, 0, rates_total, maFast) <= 0)
        return prev_calculated;
    if (CopyBuffer(iMA(_Symbol, PERIOD_CURRENT, SlowMAPeriod, 0, MaMethod, PriceType), 0, 0, rates_total, maSlow) <= 0)
        return prev_calculated;

    int macdHandle = iMACD(_Symbol, PERIOD_CURRENT, MACDFastPeriod, MACDSlowPeriod, MACDSignalPeriod, PriceType);
    if (macdHandle == INVALID_HANDLE)
        return prev_calculated;
    if (CopyBuffer(macdHandle, 0, 0, rates_total, macdMain) <= 0)
        return prev_calculated;
    if (CopyBuffer(macdHandle, 1, 0, rates_total, macdSignal) <= 0)
        return prev_calculated;
    if (CopyBuffer(macdHandle, 2, 0, rates_total, macdHist) <= 0)
        return prev_calculated;

    int stochHandle = iStochastic(_Symbol, PERIOD_CURRENT, StochKPeriod, StochDPeriod, StochSlowing, StochMaMethod, StochPriceField);
    if (stochHandle == INVALID_HANDLE)
        return prev_calculated;
    if (CopyBuffer(stochHandle, 0, 0, rates_total, stochK) <= 0)
        return prev_calculated;
    if (CopyBuffer(stochHandle, 1, 0, rates_total, stochD) <= 0)
        return prev_calculated;

    if (EnableStochLogs && time[0] != lastLoggedBarTime)
    {
        int barsToLog = MathMin(StochLogBars, rates_total);
        for (int b = 0; b < barsToLog; b++)
        {
            PrintFormat("Stoch bar %d (%s): %%K=%.2f %%D=%.2f",
                        b,
                        TimeToString(time[b], TIME_DATE | TIME_SECONDS),
                        stochK[b],
                        stochD[b]);
        }
        lastLoggedBarTime = time[0];
    }

    int start = (prev_calculated > 0 ? prev_calculated - 1 : SlowMAPeriod + 5);
    if (start < 1)
        start = 1;
    if (start >= rates_total)
        start = rates_total - 1;

    // limpar buffers
    for (int k = start; k >= 0 && k < rates_total; k--)
    {
        buyBuf[k] = EMPTY_VALUE;
        sellBuf[k] = EMPTY_VALUE;
    }

    // gerar sinais
    for (int i = start; i >= 1; i--)
    {
        if (CrossUpAt(i, rates_total))
            buyBuf[i] = maSlow[i] - (BuyArrowOffsetPoints * _Point);

        if (CrossDownAt(i, rates_total))
            sellBuf[i] = maSlow[i] + (SellArrowOffsetPoints * _Point);
    }

    return (rates_total);
}
