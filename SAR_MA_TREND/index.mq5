//+------------------------------------------------------------------+
//|                                                  My_First_EA.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"
//--- input parameters

int EA_Magic = 12345;

// Alvos
input int StopLoss = 100;   // SL
input int TakeProfit = 300; // TK

// Lote
input double Lot = 0.1; // Lote

// Médias Móveis
input bool apenasCruzamento = false;
int MA_Periodo_Rapido = 20;
input int MA_Periodo_Medio = 50;
input int MA_Periodo_Lento = 100;
double Desvio = 4;
int Deslocamento = 0;
ENUM_APPLIED_PRICE Preco = PRICE_CLOSE;

// RSI
int RSI_Periodo = 3;
int RSI_MAX = 90;
int RSI_MIN = 10;

// Horário
bool habilitaHorario = false;
int horaInicio = 9;
int horaFim = 11;

double ultimoResultado = 0.0;
bool ultimoTradeLucro = false;

double p_close;
int STP, TKP;
int handle, handleRSI, handleFastMA, handleSlowMA;

double superior[], inferior[], rsi_buffer[], fastMA[], slowMA[];

int OnInit()
{
    handle = iBands(_Symbol, _Period, 20, Deslocamento, Desvio, Preco);
    handleRSI = iRSI(_Symbol, _Period, RSI_Periodo, PRICE_CLOSE);
    handleFastMA = iMA(_Symbol, _Period, MA_Periodo_Medio, 0, MODE_EMA, PRICE_CLOSE);
    handleSlowMA = iMA(_Symbol, _Period, MA_Periodo_Lento, 0, MODE_EMA, PRICE_CLOSE);

    datetime agoraBrasilia = TimeGMT();
    MqlDateTime partesBrasilia;
    TimeToStruct(agoraBrasilia, partesBrasilia);

    bool horarioPermitido = (partesBrasilia.hour >= horaInicio && partesBrasilia.hour < horaFim);

    if (handle < 0 || handleRSI < 0 || handleFastMA < 0 || handleSlowMA < 0)
    {
        Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
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
    IndicatorRelease(handle);
    IndicatorRelease(handleRSI);
    IndicatorRelease(handleFastMA);
    IndicatorRelease(handleSlowMA);
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

    if (IsNewBar == false)
        return;

    //--- Do we have enough bars to work with
    int Mybars = Bars(_Symbol, _Period);
    if (Mybars < 60) // if total bars is less than 60 bars
    {
        Alert("We have less than 60 bars, EA will now exit!!");
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
    ArraySetAsSeries(superior, true);
    ArraySetAsSeries(inferior, true);
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(fastMA, true);
    ArraySetAsSeries(slowMA, true);

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
        return;
    }

    if (CopyRates(_Symbol, _Period, 0, 3, mrate) < 0)
    {
        Alert("Error copying rates/history data - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (CopyBuffer(handle, 1, 0, 2, superior) < 0 || CopyBuffer(handle, 2, 0, 2, inferior) < 0)
    {
        Alert("Error copying ADX indicator Buffers - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (CopyBuffer(handleRSI, 0, 0, 2, rsi_buffer) < 0)
    {
        Alert("Error copying ADX indicator Buffers - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (CopyBuffer(handleFastMA, 0, 0, 3, fastMA) < 0 || CopyBuffer(handleSlowMA, 0, 0, 3, slowMA) < 0)
    {
        Alert("Erro ao copiar valores das MAs: ", GetLastError());
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

    p_close = mrate[1].close;

    double min_anterior = iLow(_Symbol, _Period, 0);

    bool CrossUp = (fastMA[1] < slowMA[1] && fastMA[0] > slowMA[0]); // Cruzamento p/ cima
    bool Buy_Condition_1 = (min_anterior <= inferior[0]);
    bool Buy_Condition_2 = (rsi_buffer[1] >= RSI_MAX && rsi_buffer[0] <= RSI_MAX);

    bool apenasCruzaMedia = apenasCruzamento ? CrossUp : Buy_Condition_1 || Buy_Condition_2;

    //--- Putting all together
    // if (Buy_Condition_2 || Buy_Condition_1) {
    if (apenasCruzaMedia)
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
    /*
        2. Check for a Short/Sell Setup : MA-8 decreasing downwards,
        previous price close below it, ADX > 22, -DI > +DI
    */
    //--- Declare bool type variables to hold our Sell Conditions
    double max_anterior = iHigh(_Symbol, _Period, 0);

    bool CrossDown = (fastMA[1] > slowMA[1] && fastMA[0] < slowMA[0]); // Cruzamento p/ baixo
    bool Sell_Condition_1 = (max_anterior >= superior[0]);
    bool Sell_Condition_2 = (rsi_buffer[1] <= 50 && rsi_buffer[0] >= 50);

    bool apenasCruzaMediaVenda = apenasCruzamento ? CrossDown : (Sell_Condition_1 || Sell_Condition_2);

    //--- Putting all together
    // if (Sell_Condition_2 || Sell_Condition_1) {
    if (apenasCruzaMediaVenda)
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