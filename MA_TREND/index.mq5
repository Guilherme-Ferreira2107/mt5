//+------------------------------------------------------------------+
//|                                         Quebra_Broker Expert.mq5 |
//|                                               Guilherme Ferreira |
//|                                  guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.12"
#property description "Modo de uso:"
#property description "Quando houver setas verde, crie ordem de COMPRA para a PRÓXIMA vela."
#property description "Quando houver setas vermelhas, crie ordem de VENDA para a PRÓXIMA vela."
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots 3

//--- plot MA1 (única média)
#property indicator_label1 "MA"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrGold
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

//--- plot Compra
#property indicator_label2 "Compra"
#property indicator_type2 DRAW_ARROW
#property indicator_color2 clrGreen
#property indicator_style2 STYLE_SOLID
#property indicator_width2 3

//--- plot Venda
#property indicator_label3 "Venda"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 clrRed
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

//--- indicator buffers
double MA1_Buffer[];
double Compra_Buffer[];
double Venda_Buffer[];

//--- parâmetros (mantém apenas 1 média)
input int MA1_Periodo = 100; // Período MA (única)
input int SHIFT = 0;

input bool VerificaAlerta = false; // mantido (não usado no trecho atual)

//--- handle
int hMA1 = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
{
    // buffers
    SetIndexBuffer(0, MA1_Buffer, INDICATOR_DATA);
    SetIndexBuffer(1, Compra_Buffer, INDICATOR_DATA);
    SetIndexBuffer(2, Venda_Buffer, INDICATOR_DATA);

    // setas
    PlotIndexSetInteger(1, PLOT_ARROW, 225);
    PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 25);
    PlotIndexSetInteger(2, PLOT_ARROW, 226);
    PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, -25);

    long chart = ChartID();
    if (chart > 0)
    {
        ChartSetInteger(chart, CHART_SHIFT, true);
        ChartSetInteger(chart, CHART_MODE, CHART_CANDLES);
    }

    // handle da MA (único)
    hMA1 = iMA(_Symbol, _Period, MA1_Periodo, SHIFT, MODE_EMA, PRICE_CLOSE);
    if (hMA1 == INVALID_HANDLE)
        return INIT_FAILED;

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if (hMA1 != INVALID_HANDLE)
        IndicatorRelease(hMA1);
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
    if (rates_total < 100)
        return 0;

    // Copia MA1
    if (CopyBuffer(hMA1, 0, 0, rates_total, MA1_Buffer) <= 0)
        return prev_calculated;

    int start = MathMax(5, prev_calculated - 1);

    for (int i = start; i < rates_total; i++)
    {

        bool tresVermelhos = (close[i + 3] > open[i + 3]) &&
                             (close[i + 2] > open[i + 2]) &&
                             (close[i + 1] > open[i + 1]);

        bool umVerde = close[i] < open[i];

        bool tresVerdes = (close[i + 3] < open[i + 3]) &&
                          (close[i + 2] < open[i + 2]) &&
                          (close[i + 1] < open[i + 1]);

        bool umVermelho = close[i] > open[i];

        // ---------------------------
        // FILTRO DE TENDÊNCIA (apenas MA1)
        // ---------------------------
        bool pAcima1 = open[i + 1] > MA1_Buffer[i + 1] && close[i + 1] > MA1_Buffer[i + 1];
        bool pAcima2 = open[i + 2] > MA1_Buffer[i + 2] && close[i + 2] > MA1_Buffer[i + 2];
        bool pAcima3 = open[i + 3] > MA1_Buffer[i + 3] && close[i + 3] > MA1_Buffer[i + 3];
        bool pAcima4 = open[i + 4] > MA1_Buffer[i + 4] && close[i + 4] > MA1_Buffer[i + 4];
        bool pAcima5 = open[i + 5] > MA1_Buffer[i + 5] && close[i + 5] > MA1_Buffer[i + 5];
        bool pAcima6 = open[i + 6] > MA1_Buffer[i + 6] && close[i + 6] > MA1_Buffer[i + 6];
        bool pAcima7 = open[i + 7] > MA1_Buffer[i + 7] && close[i + 7] > MA1_Buffer[i + 7];
        bool pAcima8 = open[i + 8] > MA1_Buffer[i + 8] && close[i + 8] > MA1_Buffer[i + 8];
        bool pAcima9 = open[i + 9] > MA1_Buffer[i + 9] && close[i + 9] > MA1_Buffer[i + 9];
        bool pAcima10 = open[i + 10] > MA1_Buffer[i + 10] && close[i + 10] > MA1_Buffer[i + 10];

        bool pAbaixo1 = open[i + 1] < MA1_Buffer[i + 1] && close[i + 1] < MA1_Buffer[i + 1];
        bool pAbaixo2 = open[i + 2] < MA1_Buffer[i + 2] && close[i + 2] < MA1_Buffer[i + 2];
        bool pAbaixo3 = open[i + 3] < MA1_Buffer[i + 3] && close[i + 3] < MA1_Buffer[i + 3];
        bool pAbaixo4 = open[i + 4] < MA1_Buffer[i + 4] && close[i + 4] < MA1_Buffer[i + 4];
        bool pAbaixo5 = open[i + 5] < MA1_Buffer[i + 5] && close[i + 5] < MA1_Buffer[i + 5];
        bool pAbaixo6 = open[i + 6] < MA1_Buffer[i + 6] && close[i + 6] < MA1_Buffer[i + 6];
        bool pAbaixo7 = open[i + 7] < MA1_Buffer[i + 7] && close[i + 7] < MA1_Buffer[i + 7];
        bool pAbaixo8 = open[i + 8] < MA1_Buffer[i + 8] && close[i + 8] < MA1_Buffer[i + 8];
        bool pAbaixo9 = open[i + 9] < MA1_Buffer[i + 9] && close[i + 9] < MA1_Buffer[i + 9];
        bool pAbaixo10 = open[i + 10] < MA1_Buffer[i + 10] && close[i + 10] < MA1_Buffer[i + 10];

        bool ultimosDezValidosAcima = pAcima1 && pAcima2 && pAcima3 && pAcima4 && pAcima5 &&
                                      pAcima6 && pAcima7 && pAcima8 && pAcima9 && pAcima10;

        bool ultimosDezValidosAbaixo = pAbaixo1 && pAbaixo2 && pAbaixo3 && pAbaixo4 && pAbaixo5 &&
                                       pAbaixo6 && pAbaixo7 && pAbaixo8 && pAbaixo9 && pAbaixo10;

        bool filtroCompraMA = (MA1_Buffer[i] < open[i]) && ultimosDezValidosAcima;
        bool filtroVendaMA = (MA1_Buffer[i] > open[i]) && ultimosDezValidosAbaixo;

        bool sinalCompra = tresVermelhos && umVerde && filtroCompraMA;

        bool sinalVenda = tresVerdes && umVermelho && filtroVendaMA;

        Compra_Buffer[i] = sinalCompra ? low[i] : 0.0;
        Venda_Buffer[i] = sinalVenda ? high[i] : 0.0;
    }

    return rates_total;
}
//+------------------------------------------------------------------+
