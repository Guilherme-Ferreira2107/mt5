//+------------------------------------------------------------------+
//|                                                  ZigZag_RSI_ADX.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"

int EA_Magic = 12345; // EA Magic Number
input double Lot = 1; // Lots to Trade

double p_close; // Variable to store the close value of a bar
int zigzag_handle;
int rsi_handle;

input int InpDepth = 12;               // Depth do ZigZag
input int InpDeviation = 5;            // Deviation do ZigZag
input int InpBackstep = 3;             // Backstep do ZigZag
input int MaxTopos = 3;                // Quantidade de topos visiveis
input int MaxFundos = 3;               // Quantidade de fundos visiveis
input int ArrowOffsetPoints = 50;      // Distancia visual da seta em pontos
input int RSI_Period = 2;              // Periodo do RSI
input int RSI_Buy_Level = 10;          // Nivel do RSI para compra
input int RSI_Sell_Level = 90;         // Nivel do RSI para venda
input int StopLookbackBars = 3;        // Barras para calcular o stop estrutural
input double RiskRewardRatio = 2.0;    // Multiplicador do alvo sobre o risco
input int SlippagePoints = 100;        // Desvio maximo
input int ZigZagLookbackBars = 300;    // Barras usadas para ler a estrutura
input bool UsarAsia = true;            // Operar sessao asiatica
input string AsiaInicio = "00:00";     // Hora inicial Asia
input string AsiaFim = "03:00";        // Hora final Asia
input bool UsarLondres = true;         // Operar sessao Londres
input string LondresInicio = "08:00";  // Hora inicial Londres
input string LondresFim = "11:00";     // Hora final Londres
input bool UsarNovaYork = true;        // Operar sessao Nova York
input string NovaYorkInicio = "14:00"; // Hora inicial Nova York
input string NovaYorkFim = "17:00";    // Hora final Nova York
input int MaxCandlesInicioSessao = 0;  // 0 desliga, >0 limita aos primeiros candles da sessao

bool ParseTimeToMinutes(const string time_text, int &minutes_total)
{
    datetime parsed = StringToTime("2000.01.01 " + time_text);
    if (parsed == 0)
        return false;

    MqlDateTime time_struct;
    TimeToStruct(parsed, time_struct);
    minutes_total = time_struct.hour * 60 + time_struct.min;
    return true;
}

bool IsWithinMinutesRange(const int now_minutes, const int start_minutes, const int end_minutes)
{
    if (start_minutes == end_minutes)
        return true;

    if (start_minutes < end_minutes)
        return (now_minutes >= start_minutes && now_minutes <= end_minutes);

    return (now_minutes >= start_minutes || now_minutes <= end_minutes);
}

int GetSessionElapsedCandles(const int now_minutes, const int start_minutes)
{
    int minutes_since_start = now_minutes - start_minutes;
    if (minutes_since_start < 0)
        minutes_since_start += 24 * 60;

    int period_seconds = PeriodSeconds(_Period);
    if (period_seconds <= 0)
        return 0;

    int period_minutes = MathMax(1, period_seconds / 60);
    return (minutes_since_start / period_minutes) + 1;
}

bool IsSessionActive(const bool enabled,
                     const string start_text,
                     const string end_text,
                     const int now_minutes,
                     bool &inside_window,
                     int &elapsed_candles)
{
    inside_window = false;
    elapsed_candles = 0;

    if (!enabled)
        return false;

    int start_minutes = 0;
    int end_minutes = 0;
    if (!ParseTimeToMinutes(start_text, start_minutes) || !ParseTimeToMinutes(end_text, end_minutes))
        return false;

    inside_window = IsWithinMinutesRange(now_minutes, start_minutes, end_minutes);
    if (!inside_window)
        return false;

    elapsed_candles = GetSessionElapsedCandles(now_minutes, start_minutes);
    if (MaxCandlesInicioSessao > 0 && elapsed_candles > MaxCandlesInicioSessao)
        return false;

    return true;
}

bool IsWithinTradingWindow()
{
    MqlDateTime now_struct;
    TimeToStruct(TimeCurrent(), now_struct);
    int now_minutes = now_struct.hour * 60 + now_struct.min;

    bool inside_window = false;
    int elapsed_candles = 0;
    if (IsSessionActive(UsarAsia, AsiaInicio, AsiaFim, now_minutes, inside_window, elapsed_candles))
        return true;
    if (IsSessionActive(UsarLondres, LondresInicio, LondresFim, now_minutes, inside_window, elapsed_candles))
        return true;
    if (IsSessionActive(UsarNovaYork, NovaYorkInicio, NovaYorkFim, now_minutes, inside_window, elapsed_candles))
        return true;

    return false;
}

bool GetConfirmedAscendingLows(double &last_low, double &previous_low)
{
    last_low = EMPTY_VALUE;
    previous_low = EMPTY_VALUE;

    int bars_to_copy = MathMin(Bars(_Symbol, _Period), ZigZagLookbackBars);
    if (bars_to_copy < 10)
        return false;

    double zigzag_buffer[];
    double high_buffer[];
    double low_buffer[];

    ArraySetAsSeries(zigzag_buffer, true);
    ArraySetAsSeries(high_buffer, true);
    ArraySetAsSeries(low_buffer, true);

    if (CopyBuffer(zigzag_handle, 0, 0, bars_to_copy, zigzag_buffer) <= 0)
        return false;
    if (CopyBuffer(zigzag_handle, 1, 0, bars_to_copy, high_buffer) <= 0)
        return false;
    if (CopyBuffer(zigzag_handle, 2, 0, bars_to_copy, low_buffer) <= 0)
        return false;

    double pivot_values[];
    bool pivot_is_high[];
    ArrayResize(pivot_values, bars_to_copy);
    ArrayResize(pivot_is_high, bars_to_copy);
    int pivot_count = 0;

    for (int i = bars_to_copy - 1; i >= 0; i--)
    {
        double zz = zigzag_buffer[i];
        double zz_high = high_buffer[i];
        double zz_low = low_buffer[i];

        if (zz == 0.0 || zz == EMPTY_VALUE)
            continue;

        bool is_high_pivot = (zz_high != 0.0 && zz_high != EMPTY_VALUE && MathAbs(zz - zz_high) <= _Point * 2.0);
        bool is_low_pivot = (zz_low != 0.0 && zz_low != EMPTY_VALUE && MathAbs(zz - zz_low) <= _Point * 2.0);

        if (!is_high_pivot && !is_low_pivot)
            continue;

        pivot_values[pivot_count] = zz;
        pivot_is_high[pivot_count] = is_high_pivot;
        pivot_count++;
    }

    if (pivot_count < 3)
        return false;

    double confirmed_lows[];
    ArrayResize(confirmed_lows, pivot_count);
    int confirmed_low_count = 0;

    // O ultimo pivot visual do ZigZag nao e tratado como confirmado.
    for (int p = 0; p < pivot_count - 1; p++)
    {
        if (!pivot_is_high[p])
        {
            confirmed_lows[confirmed_low_count] = pivot_values[p];
            confirmed_low_count++;
        }
    }

    if (confirmed_low_count < 2)
        return false;

    last_low = confirmed_lows[confirmed_low_count - 1];
    previous_low = confirmed_lows[confirmed_low_count - 2];
    return (last_low > previous_low);
}

bool GetConfirmedDescendingHighs(double &last_high, double &previous_high)
{
    last_high = EMPTY_VALUE;
    previous_high = EMPTY_VALUE;

    int bars_to_copy = MathMin(Bars(_Symbol, _Period), ZigZagLookbackBars);
    if (bars_to_copy < 10)
        return false;

    double zigzag_buffer[];
    double high_buffer[];
    double low_buffer[];

    ArraySetAsSeries(zigzag_buffer, true);
    ArraySetAsSeries(high_buffer, true);
    ArraySetAsSeries(low_buffer, true);

    if (CopyBuffer(zigzag_handle, 0, 0, bars_to_copy, zigzag_buffer) <= 0)
        return false;
    if (CopyBuffer(zigzag_handle, 1, 0, bars_to_copy, high_buffer) <= 0)
        return false;
    if (CopyBuffer(zigzag_handle, 2, 0, bars_to_copy, low_buffer) <= 0)
        return false;

    double pivot_values[];
    bool pivot_is_high[];
    ArrayResize(pivot_values, bars_to_copy);
    ArrayResize(pivot_is_high, bars_to_copy);
    int pivot_count = 0;

    for (int i = bars_to_copy - 1; i >= 0; i--)
    {
        double zz = zigzag_buffer[i];
        double zz_high = high_buffer[i];
        double zz_low = low_buffer[i];

        if (zz == 0.0 || zz == EMPTY_VALUE)
            continue;

        bool is_high_pivot = (zz_high != 0.0 && zz_high != EMPTY_VALUE && MathAbs(zz - zz_high) <= _Point * 2.0);
        bool is_low_pivot = (zz_low != 0.0 && zz_low != EMPTY_VALUE && MathAbs(zz - zz_low) <= _Point * 2.0);

        if (!is_high_pivot && !is_low_pivot)
            continue;

        pivot_values[pivot_count] = zz;
        pivot_is_high[pivot_count] = is_high_pivot;
        pivot_count++;
    }

    if (pivot_count < 3)
        return false;

    double confirmed_highs[];
    ArrayResize(confirmed_highs, pivot_count);
    int confirmed_high_count = 0;

    // O ultimo pivot visual do ZigZag nao e tratado como confirmado.
    for (int p = 0; p < pivot_count - 1; p++)
    {
        if (pivot_is_high[p])
        {
            confirmed_highs[confirmed_high_count] = pivot_values[p];
            confirmed_high_count++;
        }
    }

    if (confirmed_high_count < 2)
        return false;

    last_high = confirmed_highs[confirmed_high_count - 1];
    previous_high = confirmed_highs[confirmed_high_count - 2];
    return (last_high < previous_high);
}

int OnInit()
{
    zigzag_handle = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
    rsi_handle = iRSI(_Symbol, _Period, RSI_Period, PRICE_CLOSE);

    if (zigzag_handle < 0 || rsi_handle < 0)
    {
        Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
        return (-1);
    }

    int parsed_minutes = 0;
    bool horarios_validos = true;
    if (UsarAsia)
        horarios_validos = horarios_validos && ParseTimeToMinutes(AsiaInicio, parsed_minutes) && ParseTimeToMinutes(AsiaFim, parsed_minutes);
    if (UsarLondres)
        horarios_validos = horarios_validos && ParseTimeToMinutes(LondresInicio, parsed_minutes) && ParseTimeToMinutes(LondresFim, parsed_minutes);
    if (UsarNovaYork)
        horarios_validos = horarios_validos && ParseTimeToMinutes(NovaYorkInicio, parsed_minutes) && ParseTimeToMinutes(NovaYorkFim, parsed_minutes);

    if (!horarios_validos)
    {
        Alert("Horario invalido. Use HH:MM para as sessoes configuradas.");
        return (-1);
    }

    return (0);
}

void OnDeinit(const int reason)
{
    IndicatorRelease(zigzag_handle);
    IndicatorRelease(rsi_handle);
}

void OnTick()
{
    if (Bars(_Symbol, _Period) < 60)
    {
        Alert("We have less than 60 bars, EA will now exit!!");
        return;
    }

    static datetime Old_Time;
    datetime New_Time[1];
    bool IsNewBar = false;

    int copied = CopyTime(_Symbol, _Period, 0, 1, New_Time);
    if (copied > 0)
    {
        if (Old_Time != New_Time[0])
        {
            IsNewBar = true;
            if (MQL5InfoInteger(MQL5_DEBUGGING))
                Print("We have new bar here ", New_Time[0], " old time was ", Old_Time);
            Old_Time = New_Time[0];
        }
    }
    else
    {
        Alert("Error in copying historical times data, error =", GetLastError());
        ResetLastError();
        return;
    }

    if (!IsNewBar)
        return;

    if (!IsWithinTradingWindow())
        return;

    MqlTick latest_price;
    MqlTradeRequest mrequest;
    MqlTradeResult mresult;
    MqlRates mrate[];
    double rsi_buffer[];
    ZeroMemory(mrequest);

    ArraySetAsSeries(mrate, true);
    ArraySetAsSeries(rsi_buffer, true);

    int copiedRsi = CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer);
    if (copiedRsi < 3)
    {
        Alert("Error copying RSI buffer - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
        return;
    }

    int rates_to_copy = MathMax(StopLookbackBars + 1, 3);
    if (CopyRates(_Symbol, _Period, 0, rates_to_copy, mrate) < rates_to_copy)
    {
        Alert("Error copying rates/history data - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    bool buy_opened = false;
    bool sell_opened = false;
    if (PositionSelect(_Symbol) == true)
    {
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            buy_opened = true;
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            sell_opened = true;
    }

    if (buy_opened || sell_opened)
        return;

    MqlDateTime now_struct;
    TimeToStruct(TimeCurrent(), now_struct);
    int now_minutes = now_struct.hour * 60 + now_struct.min;
    bool asia_ativa = false;
    bool londres_ativa = false;
    bool novayork_ativa = false;
    int candles_asia = 0;
    int candles_londres = 0;
    int candles_novayork = 0;
    asia_ativa = IsSessionActive(UsarAsia, AsiaInicio, AsiaFim, now_minutes, asia_ativa, candles_asia);
    londres_ativa = IsSessionActive(UsarLondres, LondresInicio, LondresFim, now_minutes, londres_ativa, candles_londres);
    novayork_ativa = IsSessionActive(UsarNovaYork, NovaYorkInicio, NovaYorkFim, now_minutes, novayork_ativa, candles_novayork);

    string sessao_ativa = "Fora";
    int candles_sessao = 0;
    if (asia_ativa)
    {
        sessao_ativa = "Asia";
        candles_sessao = candles_asia;
    }
    else if (londres_ativa)
    {
        sessao_ativa = "Londres";
        candles_sessao = candles_londres;
    }
    else if (novayork_ativa)
    {
        sessao_ativa = "NovaYork";
        candles_sessao = candles_novayork;
    }

    double trigger_candle_close = mrate[1].close;
    p_close = trigger_candle_close;

    double last_confirmed_low = EMPTY_VALUE;
    double previous_confirmed_low = EMPTY_VALUE;
    double last_confirmed_high = EMPTY_VALUE;
    double previous_confirmed_high = EMPTY_VALUE;
    bool ascending_lows = GetConfirmedAscendingLows(last_confirmed_low, previous_confirmed_low);
    bool descending_highs = GetConfirmedDescendingHighs(last_confirmed_high, previous_confirmed_high);
    bool rsi_buy_trigger = (rsi_buffer[2] <= RSI_Buy_Level && rsi_buffer[1] > RSI_Buy_Level);
    bool rsi_sell_trigger = (rsi_buffer[2] >= RSI_Sell_Level && rsi_buffer[1] < RSI_Sell_Level);
    bool price_above_last_confirmed_low = (last_confirmed_low != EMPTY_VALUE && trigger_candle_close > last_confirmed_low);
    bool price_below_last_confirmed_high = (last_confirmed_high != EMPTY_VALUE && trigger_candle_close < last_confirmed_high);
    bool buy_condition = ascending_lows && rsi_buy_trigger && price_above_last_confirmed_low;
    bool sell_condition = descending_highs && rsi_sell_trigger && price_below_last_confirmed_high;

    int stop_bars = MathMax(1, StopLookbackBars);
    double highest_recent_high = mrate[1].high;
    double lowest_recent_low = mrate[1].low;
    int available_bars = ArraySize(mrate);
    int bars_for_stop = MathMin(stop_bars, available_bars - 1);
    for (int i = 1; i <= bars_for_stop; i++)
    {
        if (mrate[i].high > highest_recent_high)
            highest_recent_high = mrate[i].high;
        if (mrate[i].low < lowest_recent_low)
            lowest_recent_low = mrate[i].low;
    }

    if (buy_condition)
    {
        double buy_sl = NormalizeDouble(lowest_recent_low, _Digits);
        double buy_risk = latest_price.ask - buy_sl;
        if (buy_risk <= 0.0)
            return;

        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = NormalizeDouble(latest_price.ask, _Digits);
        mrequest.sl = buy_sl;
        mrequest.tp = NormalizeDouble(latest_price.ask + (buy_risk * RiskRewardRatio), _Digits);
        mrequest.symbol = _Symbol;
        mrequest.volume = Lot;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_BUY;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = SlippagePoints;

        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
        {
            Alert("A Buy order has been successfully placed with Ticket#:", mresult.order, "!!");
        }
        else
        {
            Alert("The Buy order request could not be completed -error:", GetLastError());
            ResetLastError();
        }
        return;
    }

    if (!sell_condition)
        return;

    double sell_sl = NormalizeDouble(highest_recent_high, _Digits);
    double sell_risk = sell_sl - latest_price.bid;
    if (sell_risk <= 0.0)
        return;

    ZeroMemory(mrequest);
    mrequest.action = TRADE_ACTION_DEAL;
    mrequest.price = NormalizeDouble(latest_price.bid, _Digits);
    mrequest.sl = sell_sl;
    mrequest.tp = NormalizeDouble(latest_price.bid - (sell_risk * RiskRewardRatio), _Digits);
    mrequest.symbol = _Symbol;
    mrequest.volume = Lot;
    mrequest.magic = EA_Magic;
    mrequest.type = ORDER_TYPE_SELL;
    mrequest.type_filling = ORDER_FILLING_IOC;
    mrequest.deviation = SlippagePoints;

    OrderSend(mrequest, mresult);
    if (mresult.retcode == 10009 || mresult.retcode == 10008)
    {
        Alert("A Sell order has been successfully placed with Ticket#:", mresult.order, "!!");
    }
    else
    {
        Alert("The Sell order request could not be completed -error:", GetLastError());
        ResetLastError();
    }
}
//+------------------------------------------------------------------+
