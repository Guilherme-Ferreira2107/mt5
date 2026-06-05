//+------------------------------------------------------------------+
//|                                                  BREAK_CHANNELS   |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.00"

int EA_Magic = 12345;

input double Lot = 1.0;           // Lotes
input int InpDepth = 12;          // ZigZag Depth
input int InpDeviation = 5;       // ZigZag Deviation
input int InpBackstep = 3;        // ZigZag Backstep
input int EMA_Periodo = 9;        // Periodo da EMA
input int StopLossPoints = 300;   // Stop em pontos
input int TakeProfitPoints = 600; // Alvo em pontos

int zigzag_handle = INVALID_HANDLE;
int ema_handle = INVALID_HANDLE;

double ZigZag_Buffer[];
double ZigZagHighBuffer[];
double ZigZagLowBuffer[];
double EmaBuffer[];

bool FundosAscendentes = false;
bool ToposDescendentes = false;
double UltimoTopo = EMPTY_VALUE;
double PenultimoTopo = EMPTY_VALUE;
double UltimoFundo = EMPTY_VALUE;
double PenultimoFundo = EMPTY_VALUE;

int OnInit()
{
    zigzag_handle = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
    if (zigzag_handle == INVALID_HANDLE)
    {
        Alert("Erro ao criar handle do ZigZag: ", GetLastError());
        return INIT_FAILED;
    }

    ema_handle = iMA(_Symbol, _Period, EMA_Periodo, 0, MODE_EMA, PRICE_CLOSE);
    if (ema_handle == INVALID_HANDLE)
    {
        Alert("Erro ao criar handle da EMA: ", GetLastError());
        return INIT_FAILED;
    }

    ArraySetAsSeries(ZigZag_Buffer, true);
    ArraySetAsSeries(ZigZagHighBuffer, true);
    ArraySetAsSeries(ZigZagLowBuffer, true);
    ArraySetAsSeries(EmaBuffer, true);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if (ema_handle != INVALID_HANDLE)
        IndicatorRelease(ema_handle);
    if (zigzag_handle != INVALID_HANDLE)
        IndicatorRelease(zigzag_handle);
}

bool IsNewBar()
{
    static datetime old_time = 0;
    datetime new_time[1];

    if (CopyTime(_Symbol, _Period, 0, 1, new_time) <= 0)
        return false;

    if (old_time != new_time[0])
    {
        old_time = new_time[0];
        return true;
    }

    return false;
}

void UpdateConfirmedPivots(const double &high[], const double &low[], const int rates_total)
{
    int pivot_indices[];
    double pivot_values[];
    bool pivot_is_high[];
    ArrayResize(pivot_indices, rates_total);
    ArrayResize(pivot_values, rates_total);
    ArrayResize(pivot_is_high, rates_total);

    int pivot_count = 0;

    for (int i = rates_total - 1; i >= 0; i--)
    {
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
            pivot_indices[pivot_count] = i;
            pivot_values[pivot_count] = zz;
            pivot_is_high[pivot_count] = false;
            pivot_count++;
        }
        else if (is_high_pivot)
        {
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

    if (pivot_count <= 1)
        return;

    int confirmed_high_count = 0;
    int confirmed_low_count = 0;
    double confirmed_high_values[];
    double confirmed_low_values[];
    ArrayResize(confirmed_high_values, pivot_count);
    ArrayResize(confirmed_low_values, pivot_count);

    for (int p = 0; p < pivot_count - 1; p++)
    {
        if (pivot_is_high[p])
            confirmed_high_values[confirmed_high_count++] = pivot_values[p];
        else
            confirmed_low_values[confirmed_low_count++] = pivot_values[p];
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
}

void OnTick()
{
    if (Bars(_Symbol, _Period) < 60)
        return;

    if (!IsNewBar())
        return;

    MqlTick latest_price;
    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Erro ao obter cotacao: ", GetLastError());
        return;
    }

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, _Period, 0, 200, rates) <= 0)
    {
        Alert("Erro ao copiar rates: ", GetLastError());
        return;
    }

    int rates_total = ArraySize(rates);
    if (rates_total < 10)
        return;

    double high[];
    double low[];
    double close[];
    ArrayResize(high, rates_total);
    ArrayResize(low, rates_total);
    ArrayResize(close, rates_total);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);

    for (int i = 0; i < rates_total; i++)
    {
        high[i] = rates[i].high;
        low[i] = rates[i].low;
        close[i] = rates[i].close;
    }

    if (CopyBuffer(zigzag_handle, 0, 0, rates_total, ZigZag_Buffer) <= 0)
        return;
    if (CopyBuffer(zigzag_handle, 1, 0, rates_total, ZigZagHighBuffer) <= 0)
        return;
    if (CopyBuffer(zigzag_handle, 2, 0, rates_total, ZigZagLowBuffer) <= 0)
        return;
    if (CopyBuffer(ema_handle, 0, 0, rates_total, EmaBuffer) <= 0)
        return;

    UpdateConfirmedPivots(high, low, rates_total);

    bool sinal_venda = false;
    bool sinal_compra = false;

    if (rates_total > 3)
    {
        sinal_venda = (ToposDescendentes &&
                       close[2] > EmaBuffer[2] &&
                       close[1] < EmaBuffer[1]);

        sinal_compra = (FundosAscendentes &&
                        close[3] < EmaBuffer[3] &&
                        close[2] > EmaBuffer[2]);
    }

    bool buy_opened = false;
    bool sell_opened = false;
    if (PositionSelect(_Symbol))
    {
        long position_type = PositionGetInteger(POSITION_TYPE);
        buy_opened = (position_type == POSITION_TYPE_BUY);
        sell_opened = (position_type == POSITION_TYPE_SELL);
    }

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    if (sinal_compra && !buy_opened && !sell_opened)
    {
        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        request.volume = Lot;
        request.magic = EA_Magic;
        request.type = ORDER_TYPE_BUY;
        request.price = NormalizeDouble(latest_price.ask, _Digits);
        request.sl = NormalizeDouble(latest_price.ask - StopLossPoints * _Point, _Digits);
        request.tp = NormalizeDouble(latest_price.ask + TakeProfitPoints * _Point, _Digits);
        request.deviation = 100;
        request.type_filling = ORDER_FILLING_IOC;

        OrderSend(request, result);
    }

    if (sinal_venda && !sell_opened && !buy_opened)
    {
        ZeroMemory(request);
        ZeroMemory(result);
        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        request.volume = Lot;
        request.magic = EA_Magic;
        request.type = ORDER_TYPE_SELL;
        request.price = NormalizeDouble(latest_price.bid, _Digits);
        request.sl = NormalizeDouble(latest_price.bid + StopLossPoints * _Point, _Digits);
        request.tp = NormalizeDouble(latest_price.bid - TakeProfitPoints * _Point, _Digits);
        request.deviation = 100;
        request.type_filling = ORDER_FILLING_IOC;

        OrderSend(request, result);
    }
}
//+------------------------------------------------------------------+
