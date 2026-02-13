//+------------------------------------------------------------------+
//|                                                  My_First_EA.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"
//--- input parameters

input int EA_Magic = 12345;          // Magic number para identificar ordens deste EA

// Alvos
input int StopLoss = 100;            // Stop loss em pontos
input int TakeProfit = 300;          // Take profit em pontos

// Lote
input double Lot = 0.1;              // Lote base

// Regras do indicador (Envelopes + MA)
input int MA_Periodo = 14;           // Periodo da media do envelope
input double EnvelopeDesvio = 0.15;  // Desvio do envelope em porcentagem

// Horario
input bool habilitaHorario = false;  // Ativa filtro de horario
input int horaInicio = 9;            // Hora inicial (0-23)
input int horaFim = 11;              // Hora final (0-23, exclusivo)

double ultimoResultado = 0.0;
bool ultimoTradeLucro = false;

int STP, TKP;
int envelopeHandle;
double envelopeSup[], envelopeInf[];

int OnInit()
{
    envelopeHandle = iEnvelopes(_Symbol, _Period, MA_Periodo, 0, MODE_SMA, PRICE_CLOSE, EnvelopeDesvio);

    if (envelopeHandle < 0)
    {
        Alert("Error creating Envelopes handle - error: ", GetLastError(), "!!");
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
    IndicatorRelease(envelopeHandle);
}

void OnTick()
{
    if (Bars(_Symbol, _Period) < 5)
    {
        Alert("We have less than 5 bars, EA will now exit!!");
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

    if (habilitaHorario)
    {
        MqlDateTime partesBrasilia;
        TimeToStruct(TimeCurrent(), partesBrasilia);
        if (partesBrasilia.hour < horaInicio || partesBrasilia.hour >= horaFim)
            return;
    }

    //--- Do we have enough bars to work with
    int Mybars = Bars(_Symbol, _Period);
    if (Mybars < 5) // precisamos de pelo menos 4 candles fechados
    {
        Alert("We have less than 5 bars, EA will now exit!!");
        return;
    }

    //--- Define some MQL5 Structures we will use for our trade
    MqlTick latest_price;
    MqlTradeRequest mrequest;
    MqlTradeResult mresult;
    MqlRates mrate[];
    ZeroMemory(mrequest);

    // the rates arrays
    ArraySetAsSeries(mrate, true);
    ArraySetAsSeries(envelopeSup, true);
    ArraySetAsSeries(envelopeInf, true);

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
        return;
    }

    if (CopyRates(_Symbol, _Period, 0, 4, mrate) < 0)
    {
        Alert("Error copying rates/history data - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (CopyBuffer(envelopeHandle, 0, 0, 4, envelopeSup) < 0 || CopyBuffer(envelopeHandle, 1, 0, 4, envelopeInf) < 0)
    {
        Alert("Erro ao copiar valores do indicador Envelopes: ", GetLastError());
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

    bool buySignal = (mrate[2].close < envelopeInf[2] && mrate[1].close > envelopeInf[1] && mrate[3].low < mrate[2].low);
    bool sellSignal = (mrate[2].close > envelopeSup[2] && mrate[1].close < envelopeSup[1] && mrate[3].high > mrate[2].high);

    // entrada de compra segue a seta verde (seta aparece e operamos na proxima vela)
    if (buySignal && !sellSignal)
    {
        // any opened Buy position?
        if (Buy_opened || Sell_opened)
        {
            Alert("We already have a Buy Position!!!");
            return; // Don't open a new Buy Position
        }
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;                                     // immediate order execution
        mrequest.price = NormalizeDouble(latest_price.ask, _Digits);             // latest ask price
        mrequest.sl = NormalizeDouble(latest_price.ask - STP * _Point, _Digits); // Stop Loss
        mrequest.tp = NormalizeDouble(latest_price.ask + TKP * _Point, _Digits); // Take Profit
        mrequest.symbol = _Symbol;                                               // currency pair
        mrequest.volume = ultimoTradeLucro ? Lot : Lot * 3;                      // number of lots to trade
        // mrequest.volume = Lot;
        mrequest.magic = EA_Magic;                 // Order Magic Number
        mrequest.type = ORDER_TYPE_BUY;            // Buy Order
        mrequest.type_filling = ORDER_FILLING_IOC; // Order execution type
        mrequest.deviation = 100;                  // Deviation from current price
        //--- send order
        OrderSend(mrequest, mresult);
        // get the result code
        if (mresult.retcode == 10009 || mresult.retcode == 10008) // Request is completed or order placed
        {
            Alert("A Buy order has been successfully placed with Ticket#:", mresult.order, "!!");
        }
        else
        {
            Alert("The Buy order request could not be completed -error:", GetLastError());
            ResetLastError();
            return;
        }
    }

    // entrada de venda segue a seta vermelha
    if (sellSignal && !buySignal)
    {
        if (Buy_opened || Sell_opened)
        {
            Alert("We already have a Sell position!!!");
            return;
        }
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;                                     // immediate order execution
        mrequest.price = NormalizeDouble(latest_price.bid, _Digits);             // latest Bid price
        mrequest.sl = NormalizeDouble(latest_price.bid + STP * _Point, _Digits); // Stop Loss
        mrequest.tp = NormalizeDouble(latest_price.bid - TKP * _Point, _Digits); // Take Profit
        mrequest.symbol = _Symbol;                                               // currency pair
        mrequest.volume = ultimoTradeLucro ? Lot : Lot * 3;                      // number of lots to trade
        // mrequest.volume = Lot;
        mrequest.magic = EA_Magic;                 // Order Magic Number
        mrequest.type = ORDER_TYPE_SELL;           // Sell Order
        mrequest.type_filling = ORDER_FILLING_IOC; // Order execution type
        mrequest.deviation = 100;                  // Deviation from current price
        //--- send order
        OrderSend(mrequest, mresult);
        // get the result code
        if (mresult.retcode == 10009 || mresult.retcode == 10008) // Request is completed or order placed
        {
            Alert("A Sell order has been successfully placed with Ticket#:", mresult.order, "!!");
        }
        else
        {
            Alert("The Sell order request could not be completed -error:", GetLastError());
            ResetLastError();
            return;
        }
    }
    return;
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
