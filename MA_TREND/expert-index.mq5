//+------------------------------------------------------------------+
//|                                                  My_First_EA.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"
//--- input parameters
input int EA_Magic = 12345; // Magic number para identificar ordens deste EA
input int StopLoss = 100;   // Stop loss em pontos
input int TakeProfit = 300; // Take profit em pontos
input double Lot = 0.1;     // Lote base
input int MA_Periodo = 200; // Periodo da media movel principal

double ultimoResultado = 0.0;
bool ultimoTradeLucro = false;

int STP, TKP;
int handleMA;
double maBuffer[];

int OnInit()
{
    handleMA = iMA(_Symbol, _Period, MA_Periodo, 0, MODE_EMA, PRICE_CLOSE);

    if (handleMA < 0)
    {
        Alert("Error creating MA handle - error: ", GetLastError(), "!!");
        return (-1);
    }

    //--- Let us handle currency pairs with 5 or 3 digit prices instead of 4
    STP = StopLoss;
    TKP = TakeProfit;

    if (_Digits == 5 || _Digits == 3)
    {
        STP = STP * 10;
        TKP = TKP * 10;
    }
    return (0);
}

void OnDeinit(const int reason)
{
    IndicatorRelease(handleMA);
}

void OnTick()
{
    if (Bars(_Symbol, _Period) < MA_Periodo + 5)
    {
        Alert("Bars insuficientes para a MA de ", MA_Periodo, ", EA vai sair!");
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

    if (IsNewBar == false)
        return;

    //--- Define some MQL5 Structures we will use for our trade
    MqlTick latest_price;
    MqlTradeRequest mrequest;
    MqlTradeResult mresult;
    MqlRates mrate[];
    ZeroMemory(mrequest);

    ArraySetAsSeries(mrate, true);
    ArraySetAsSeries(maBuffer, true);

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
        return;
    }

    if (CopyRates(_Symbol, _Period, 0, 5, mrate) < 5)
    {
        Alert("Error copying rates/history data - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (CopyBuffer(handleMA, 0, 0, 5, maBuffer) < 0)
    {
        Alert("Erro ao copiar valores da MA: ", GetLastError());
        ResetLastError();
        return;
    }

    bool Buy_opened = false;
    bool Sell_opened = false;

    if (PositionSelect(_Symbol) == true)
    {
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            Buy_opened = true;
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            Sell_opened = true;
        }
    }

    bool priceAboveMA = mrate[1].close > maBuffer[1];
    bool priceBelowMA = mrate[1].close < maBuffer[1];

    bool buyPattern = (mrate[4].close < mrate[4].open) && (mrate[3].close < mrate[3].open) &&
                      (mrate[2].close < mrate[2].open) && (mrate[1].close > mrate[1].open);

    bool sellPattern = (mrate[4].close > mrate[4].open) && (mrate[3].close > mrate[3].open) &&
                       (mrate[2].close > mrate[2].open) && (mrate[1].close < mrate[1].open);

    if (priceAboveMA && buyPattern && !Buy_opened && !Sell_opened)
    {
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = NormalizeDouble(latest_price.ask, _Digits);
        mrequest.sl = NormalizeDouble(latest_price.ask - STP * _Point, _Digits);
        mrequest.tp = NormalizeDouble(latest_price.ask + TKP * _Point, _Digits);
        mrequest.symbol = _Symbol;
        mrequest.volume = ultimoTradeLucro ? Lot : Lot * 3;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_BUY;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = 100;

        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
        {
            Alert("Buy enviado (ticket: ", mresult.order, ")");
        }
        else
        {
            Alert("Falha ao enviar Buy - erro:", GetLastError());
            ResetLastError();
            return;
        }
    }

    if (priceBelowMA && sellPattern && !Buy_opened && !Sell_opened)
    {
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = NormalizeDouble(latest_price.bid, _Digits);
        mrequest.sl = NormalizeDouble(latest_price.bid + STP * _Point, _Digits);
        mrequest.tp = NormalizeDouble(latest_price.bid - TKP * _Point, _Digits);
        mrequest.symbol = _Symbol;
        mrequest.volume = ultimoTradeLucro ? Lot : Lot * 3;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_SELL;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = 100;

        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
        {
            Alert("Sell enviado (ticket: ", mresult.order, ")");
        }
        else
        {
            Alert("Falha ao enviar Sell - erro:", GetLastError());
            ResetLastError();
            return;
        }
    }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD) // só novos deals
        return;
    if (trans.symbol != _Symbol) // só este símbolo
        return;

    // Seleciona o histórico recente (últimos 2 dias, pode ajustar se quiser)
    datetime from = TimeCurrent() - 2 * 86400;
    datetime to = TimeCurrent();

    if (!HistorySelect(from, to))
    {
        Print("Erro ao selecionar histórico: ", GetLastError());
        return;
    }

    int totalDeals = HistoryDealsTotal();
    if (totalDeals <= 0)
    {
        Print("Nenhum deal no histórico.");
        return;
    }

    // Pega o último deal fechado
    ulong last_deal = HistoryDealGetTicket(totalDeals - 1);

    // Verifica se é saída de posição (fechamento)
    if (HistoryDealGetInteger(last_deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
        return;

    double profit = HistoryDealGetDouble(last_deal, DEAL_PROFIT);
    double commission = HistoryDealGetDouble(last_deal, DEAL_COMMISSION);
    double swap = HistoryDealGetDouble(last_deal, DEAL_SWAP);

    ultimoResultado = profit + commission + swap;
    ultimoTradeLucro = (ultimoResultado >= 0.0);

    PrintFormat("[G U I L H E R M E:] Último trade fechado: %.2f (%s)",
                ultimoResultado,
                ultimoTradeLucro ? "lucro" : "prejuízo");
}

//+------------------------------------------------------------------+
