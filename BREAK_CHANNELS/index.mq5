//+------------------------------------------------------------------+
//|                                         BREAK_CHANNELS Trend EA  |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "2.00"

int EA_Magic = 12345;

input double Lot = 1.0;                // Lotes
input int FastEMA = 20;                // EMA curta
input int SlowEMA = 50;                // EMA longa
input double RiskReward = 1.5;         // Multiplicador do alvo
input int BufferStopPoints = 20;       // Folga do stop em pontos
input double MetaDiaria = 200.0;       // Meta diaria em moeda da conta
input double StopDiario = 150.0;       // Stop diario em moeda da conta
input int MaxTradesDia = 3;            // Maximo de trades por dia
input int MaxLossesSeguidos = 2;       // Maximo de losses seguidos
input int SlippagePoints = 100;        // Desvio maximo

int fast_ema_handle = INVALID_HANDLE;
int slow_ema_handle = INVALID_HANDLE;

double FastEmaBuffer[];
double SlowEmaBuffer[];

struct DayStats
{
    double closed_pnl;
    int trades_count;
    int consecutive_losses;
};

int OnInit()
{
    fast_ema_handle = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
    if (fast_ema_handle == INVALID_HANDLE)
    {
        Alert("Erro ao criar handle da EMA curta: ", GetLastError());
        return INIT_FAILED;
    }

    slow_ema_handle = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
    if (slow_ema_handle == INVALID_HANDLE)
    {
        Alert("Erro ao criar handle da EMA longa: ", GetLastError());
        return INIT_FAILED;
    }

    ArraySetAsSeries(FastEmaBuffer, true);
    ArraySetAsSeries(SlowEmaBuffer, true);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if (fast_ema_handle != INVALID_HANDLE)
        IndicatorRelease(fast_ema_handle);
    if (slow_ema_handle != INVALID_HANDLE)
        IndicatorRelease(slow_ema_handle);
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

datetime StartOfDay(datetime current_time)
{
    MqlDateTime dt;
    TimeToStruct(current_time, dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    return StructToTime(dt);
}

DayStats CalculateTodayStats()
{
    DayStats stats;
    stats.closed_pnl = 0.0;
    stats.trades_count = 0;
    stats.consecutive_losses = 0;

    datetime from_time = StartOfDay(TimeCurrent());
    datetime to_time = TimeCurrent();
    if (!HistorySelect(from_time, to_time))
        return stats;

    int total = HistoryDealsTotal();
    int running_losses = 0;

    for (int i = 0; i < total; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        if (deal_ticket == 0)
            continue;

        string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
        long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
        long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

        if (symbol != _Symbol || magic != EA_Magic)
            continue;

        if (entry == DEAL_ENTRY_IN)
            stats.trades_count++;

        if (entry == DEAL_ENTRY_OUT)
        {
            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(deal_ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

            stats.closed_pnl += profit;

            if (profit < 0.0)
                running_losses++;
            else
                running_losses = 0;
        }
    }

    stats.consecutive_losses = running_losses;
    return stats;
}

bool HasOpenPosition(bool &buy_opened, bool &sell_opened)
{
    buy_opened = false;
    sell_opened = false;

    if (!PositionSelect(_Symbol))
        return false;

    long magic = PositionGetInteger(POSITION_MAGIC);
    if (magic != EA_Magic)
        return false;

    long position_type = PositionGetInteger(POSITION_TYPE);
    buy_opened = (position_type == POSITION_TYPE_BUY);
    sell_opened = (position_type == POSITION_TYPE_SELL);
    return true;
}

bool SendOrder(ENUM_ORDER_TYPE order_type, double price, double sl, double tp)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = Lot;
    request.magic = EA_Magic;
    request.type = order_type;
    request.price = NormalizeDouble(price, _Digits);
    request.sl = NormalizeDouble(sl, _Digits);
    request.tp = NormalizeDouble(tp, _Digits);
    request.deviation = SlippagePoints;
    request.type_filling = ORDER_FILLING_IOC;

    if (!OrderSend(request, result))
    {
        Alert("Falha ao enviar ordem: ", GetLastError());
        return false;
    }

    if (result.retcode != 10008 && result.retcode != 10009)
    {
        Alert("Ordem rejeitada. Retcode: ", result.retcode);
        return false;
    }

    return true;
}

void OnTick()
{
    if (Bars(_Symbol, _Period) < 100)
        return;

    if (!IsNewBar())
        return;

    DayStats stats = CalculateTodayStats();
    if (stats.closed_pnl >= MetaDiaria)
        return;
    if (stats.closed_pnl <= -StopDiario)
        return;
    if (stats.trades_count >= MaxTradesDia)
        return;
    if (stats.consecutive_losses >= MaxLossesSeguidos)
        return;

    bool buy_opened = false;
    bool sell_opened = false;
    HasOpenPosition(buy_opened, sell_opened);
    if (buy_opened || sell_opened)
        return;

    MqlTick latest_price;
    if (!SymbolInfoTick(_Symbol, latest_price))
        return;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, _Period, 0, 10, rates) <= 0)
        return;

    if (CopyBuffer(fast_ema_handle, 0, 0, 10, FastEmaBuffer) <= 0)
        return;
    if (CopyBuffer(slow_ema_handle, 0, 0, 10, SlowEmaBuffer) <= 0)
        return;

    bool tendencia_alta = (FastEmaBuffer[1] > SlowEmaBuffer[1]);
    bool tendencia_baixa = (FastEmaBuffer[1] < SlowEmaBuffer[1]);

    bool sinal_compra = false;
    bool sinal_venda = false;

    // Compra na retracao: candle 2 toca/perde a EMA20 e candle 1 fecha acima dela.
    if (tendencia_alta)
    {
        bool retracao = (rates[2].low <= FastEmaBuffer[2]);
        bool retomada = (rates[1].close > FastEmaBuffer[1]);
        sinal_compra = retracao && retomada;
    }

    // Venda na retracao: candle 2 toca/supera a EMA20 e candle 1 fecha abaixo dela.
    if (tendencia_baixa)
    {
        bool retracao = (rates[2].high >= FastEmaBuffer[2]);
        bool retomada = (rates[1].close < FastEmaBuffer[1]);
        sinal_venda = retracao && retomada;
    }

    if (sinal_compra)
    {
        double sl = rates[1].low - BufferStopPoints * _Point;
        double risk = latest_price.ask - sl;
        if (risk > 0.0)
        {
            double tp = latest_price.ask + (risk * RiskReward);
            SendOrder(ORDER_TYPE_BUY, latest_price.ask, sl, tp);
        }
    }

    if (sinal_venda)
    {
        double sl = rates[1].high + BufferStopPoints * _Point;
        double risk = sl - latest_price.bid;
        if (risk > 0.0)
        {
            double tp = latest_price.bid - (risk * RiskReward);
            SendOrder(ORDER_TYPE_SELL, latest_price.bid, sl, tp);
        }
    }
}
//+------------------------------------------------------------------+
