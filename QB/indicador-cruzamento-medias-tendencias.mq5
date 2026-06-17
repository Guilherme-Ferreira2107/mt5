//+------------------------------------------------------------------+
//|                   Indicador Cruzamento Medias Tendencias.mq5     |
//|                                               Guilherme Ferreira |
//|                                  guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.0"
#property description "Mostra os pontos de entrada, alvo e stop com base na logica do robo."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 6

#property indicator_label1 "Media Curta"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDodgerBlue
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2

#property indicator_label2 "Media Deslocada"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrOrange
#property indicator_style2 STYLE_DASH
#property indicator_width2 3

#property indicator_label3 "Media Tendencia"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrWhite
#property indicator_style3 STYLE_SOLID
#property indicator_width3 3

#property indicator_label4 "Entrada Compra"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 clrYellow
#property indicator_style4 STYLE_SOLID
#property indicator_width4 4

#property indicator_label5 "Take Profit"
#property indicator_type5 DRAW_ARROW
#property indicator_color5 clrDeepSkyBlue
#property indicator_style5 STYLE_SOLID
#property indicator_width5 2

#property indicator_label6 "Stop Loss"
#property indicator_type6 DRAW_ARROW
#property indicator_color6 clrTomato
#property indicator_style6 STYLE_SOLID
#property indicator_width6 2

input group "Configuracoes de horario"
input string HoraInicio = "00:00";
input string HoraTermino = "23:59";

input group "Configuracoes de gestao"
input bool GestaoAutomatica = false;
input double StopLoss = 25.0;
input double TakeProfit = 50.0;
input double DistanciaAlvo = 1.5;

input group "Configuracoes das medias"
input int periodoMediaCurta = 10;
input int periodoMediaDeslocada = 10;
input int deslocamentoMedia = 1;
input int periodoMediaTendencia = 55;
input double DistanciaVisualSeta = 15.0;

double BufferMediaCurta[];
double BufferMediaDeslocada[];
double BufferMediaTendencia[];
double BufferEntradaCompra[];
double BufferTakeProfit[];
double BufferStopLoss[];

int handleMediaCurta = INVALID_HANDLE;
int handleMediaDeslocada = INVALID_HANDLE;
int handleMediaTendencia = INVALID_HANDLE;
double BufferMediaDeslocadaCalculo[];

bool HorarioPermitido(const datetime candle_time)
{
    string data = TimeToString(candle_time, TIME_DATE);
    datetime inicio = StringToTime(data + " " + HoraInicio);
    datetime termino = StringToTime(data + " " + HoraTermino);

    if (inicio == 0 || termino == 0 || inicio >= termino)
        return false;

    return (candle_time >= inicio && candle_time <= termino);
}

int OnInit()
{
    SetIndexBuffer(0, BufferMediaCurta, INDICATOR_DATA);
    SetIndexBuffer(1, BufferMediaDeslocada, INDICATOR_DATA);
    SetIndexBuffer(2, BufferMediaTendencia, INDICATOR_DATA);
    SetIndexBuffer(3, BufferEntradaCompra, INDICATOR_DATA);
    SetIndexBuffer(4, BufferTakeProfit, INDICATOR_DATA);
    SetIndexBuffer(5, BufferStopLoss, INDICATOR_DATA);

    ArraySetAsSeries(BufferMediaCurta, true);
    ArraySetAsSeries(BufferMediaDeslocada, true);
    ArraySetAsSeries(BufferMediaTendencia, true);
    ArraySetAsSeries(BufferEntradaCompra, true);
    ArraySetAsSeries(BufferTakeProfit, true);
    ArraySetAsSeries(BufferStopLoss, true);
    ArraySetAsSeries(BufferMediaDeslocadaCalculo, true);

    PlotIndexSetInteger(3, PLOT_ARROW, 241);
    PlotIndexSetInteger(4, PLOT_ARROW, 159);
    PlotIndexSetInteger(5, PLOT_ARROW, 159);
    PlotIndexSetInteger(1, PLOT_SHIFT, deslocamentoMedia);
    PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 0);
    PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 0);
    PlotIndexSetInteger(5, PLOT_ARROW_SHIFT, 0);

    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    IndicatorSetString(INDICATOR_SHORTNAME, "Indicador Cruzamento Medias Tendencias");

    handleMediaCurta = iMA(_Symbol, _Period, periodoMediaCurta, 0, MODE_SMA, PRICE_CLOSE);
    handleMediaDeslocada = iMA(_Symbol, _Period, periodoMediaDeslocada, 0, MODE_SMA, PRICE_CLOSE);
    handleMediaTendencia = iMA(_Symbol, _Period, periodoMediaTendencia, 0, MODE_EMA, PRICE_CLOSE);

    if (handleMediaCurta == INVALID_HANDLE ||
        handleMediaDeslocada == INVALID_HANDLE ||
        handleMediaTendencia == INVALID_HANDLE)
    {
        Print("Erro ao criar handles dos indicadores: ", GetLastError());
        return INIT_FAILED;
    }

    long chart_id = ChartID();
    if (chart_id > 0)
    {
        ChartSetInteger(chart_id, CHART_SHIFT, true);
        ChartSetInteger(chart_id, CHART_MODE, CHART_CANDLES);
    }

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if (handleMediaCurta != INVALID_HANDLE)
        IndicatorRelease(handleMediaCurta);
    if (handleMediaDeslocada != INVALID_HANDLE)
        IndicatorRelease(handleMediaDeslocada);
    if (handleMediaTendencia != INVALID_HANDLE)
        IndicatorRelease(handleMediaTendencia);
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
    if (rates_total < 12)
        return 0;

    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);

    if (CopyBuffer(handleMediaCurta, 0, 0, rates_total, BufferMediaCurta) <= 0)
        return prev_calculated;
    if (CopyBuffer(handleMediaDeslocada, 0, 0, rates_total, BufferMediaDeslocadaCalculo) <= 0)
        return prev_calculated;
    if (CopyBuffer(handleMediaTendencia, 0, 0, rates_total, BufferMediaTendencia) <= 0)
        return prev_calculated;

    for (int i = 0; i < rates_total; i++)
        BufferMediaDeslocada[i] = BufferMediaDeslocadaCalculo[i];

    int inicio = rates_total - 12;
    if (prev_calculated > 0)
        inicio = MathMin(inicio, rates_total - prev_calculated + 2);
    inicio = MathMax(inicio, 0);

    for (int i = inicio; i >= 0; i--)
    {
        BufferEntradaCompra[i] = EMPTY_VALUE;
        BufferTakeProfit[i] = EMPTY_VALUE;
        BufferStopLoss[i] = EMPTY_VALUE;

        if (i + 10 >= rates_total || i + 2 + deslocamentoMedia >= rates_total)
            continue;

        bool cruzouParaCima = (BufferMediaCurta[i + 1] > BufferMediaDeslocadaCalculo[i + 1 + deslocamentoMedia] &&
                               BufferMediaCurta[i + 2] <= BufferMediaDeslocadaCalculo[i + 2 + deslocamentoMedia]);

        bool precoAcimaTendenciaAlta = (BufferMediaCurta[i] > BufferMediaTendencia[i] &&
                                        BufferMediaDeslocadaCalculo[i + deslocamentoMedia] > BufferMediaTendencia[i]);

        if (!cruzouParaCima || !precoAcimaTendenciaAlta || !HorarioPermitido(time[i]))
            continue;

        double precoEntrada = NormalizeDouble(open[i], _Digits);
        double precoStop = 0.0;
        double precoAlvo = 0.0;

        if (GestaoAutomatica)
        {
            precoStop = NormalizeDouble(precoEntrada - StopLoss * _Point, _Digits);
            precoAlvo = NormalizeDouble(precoEntrada + TakeProfit * _Point, _Digits);
        }
        else
        {
            double somaTamanhos = 0.0;
            for (int j = 1; j <= 10; j++)
                somaTamanhos += (high[i + j] - low[i + j]);

            double alturaMediana = somaTamanhos / 10.0;
            double distanciaStop = alturaMediana * 2.0;

            precoStop = NormalizeDouble(precoEntrada - distanciaStop, _Digits);
            precoAlvo = NormalizeDouble(precoEntrada + (distanciaStop * DistanciaAlvo), _Digits);
        }

        double deslocamentoVisual = DistanciaVisualSeta * _Point;

        BufferEntradaCompra[i] = NormalizeDouble(low[i] - deslocamentoVisual, _Digits);
        BufferTakeProfit[i] = precoAlvo;
        BufferStopLoss[i] = precoStop;
    }

    return rates_total;
}
//+------------------------------------------------------------------+
