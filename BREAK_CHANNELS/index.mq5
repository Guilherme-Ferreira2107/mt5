//+------------------------------------------------------------------+
//|                                                  My_First_EA.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"
//--- input parameters
int EA_Magic = 12345; // EA Magic Number
input double Lot = 1; // Lots to Trade

//--- Other parameters
double p_close; // Variable to store the close value of a bar
int zigzag_handle;

input int InpDepth = 12;          // Depth do ZigZag
input int InpDeviation = 5;       // Deviation do ZigZag
input int InpBackstep = 3;        // Backstep do ZigZag
input int MaxTopos = 3;           // Quantidade de topos visíveis
input int MaxFundos = 3;          // Quantidade de fundos visíveis
input int ArrowOffsetPoints = 50; // Distância visual da seta em pontos
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    zigzag_handle = iCustom(_Symbol, _Period, "zigzag", InpDepth, InpDeviation, InpBackstep);
    //--- What if handle returns Invalid Handle
    if (zigzag_handle < 0)
    {
        Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
        return (-1);
    }

    return (0);
}

void OnDeinit(const int reason)
{
    IndicatorRelease(zigzag_handle);
}

void OnTick()
{
    //--- Do we have enough bars to work with
    if (Bars(_Symbol, _Period) < 60) // if total bars is less than 60 bars
    {
        Alert("We have less than 60 bars, EA will now exit!!");
        return;
    }

    // We will use the static Old_Time variable to serve the bar time.
    // At each OnTick execution we will check the current bar time with the saved one.
    // If the bar time isn't equal to the saved time, it indicates that we have a new tick.
    static datetime Old_Time;
    datetime New_Time[1];
    bool IsNewBar = false;

    // copying the last bar time to the element New_Time[0]
    int copied = CopyTime(_Symbol, _Period, 0, 1, New_Time);
    if (copied > 0) // ok, the data has been copied successfully
    {
        if (Old_Time != New_Time[0]) // if old time isn't equal to new bar time
        {
            IsNewBar = true; // if it isn't a first call, the new bar has appeared
            if (MQL5InfoInteger(MQL5_DEBUGGING))
                Print("We have new bar here ", New_Time[0], " old time was ", Old_Time);
            Old_Time = New_Time[0]; // saving bar time
        }
    }
    else
    {
        Alert("Error in copying historical times data, error =", GetLastError());
        ResetLastError();
        return;
    }

    //--- EA should only check for new trade if we have a new bar
    if (IsNewBar == false)
    {
        return;
    }

    //--- Do we have enough bars to work with
    int Mybars = Bars(_Symbol, _Period);
    if (Mybars < 60) // if total bars is less than 60 bars
    {
        Alert("We have less than 60 bars, EA will now exit!!");
        return;
    }

    //--- Define some MQL5 Structures we will use for our trade
    MqlTick latest_price;     // To be used for getting recent/latest price quotes
    MqlTradeRequest mrequest; // To be used for sending our trade requests
    MqlTradeResult mresult;   // To be used to get our trade results
    MqlRates mrate[];         // To be used to store the prices, volumes and spread of each bar
    ZeroMemory(mrequest);     // Initialization of mrequest structure

    double highMap[];
    double lowMap[];

    ArraySetAsSeries(highMap, true);
    ArraySetAsSeries(lowMap, true);

    // the rates arrays
    ArraySetAsSeries(mrate, true);

    int copiedHigh = CopyBuffer(zigzag_handle, 1, 0, 10, highMap);
    int copiedLow = CopyBuffer(zigzag_handle, 2, 0, 10, lowMap);

    //--- Get the last price quote using the MQL5 MqlTick Structure
    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
        return;
    }

    //--- Get the details of the latest 3 bars
    if (CopyRates(_Symbol, _Period, 0, 3, mrate) < 0)
    {
        Alert("Error copying rates/history data - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    bool Buy_opened = false;  // variable to hold the result of Buy opened position
    bool Sell_opened = false; // variables to hold the result of Sell opened position

    if (PositionSelect(_Symbol) == true) // we have an opened position
    {
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            Buy_opened = true; // It is a Buy
        }
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            Sell_opened = true; // It is a Sell
        }
    }

    // Copy the bar close price for the previous bar prior to the current bar, that is Bar 1
    p_close = mrate[1].close; // bar 1 close price

    //--- Declare bool type variables to hold our Buy Conditions
    double min_anterior = iLow(_Symbol, _Period, 0);

    bool Buy_Condition_1 = (min_anterior <= inferior[0]);

    //--- Putting all together
    if (Buy_Condition_1)
    {
        // any opened Buy position?
        if (Buy_opened)
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
        mrequest.volume = Lot;                                                   // number of lots to trade
        mrequest.magic = EA_Magic;                                               // Order Magic Number
        mrequest.type = ORDER_TYPE_BUY;                                          // Buy Order
        mrequest.type_filling = ORDER_FILLING_IOC;                               // Order execution type
        mrequest.deviation = 100;                                                // Deviation from current price
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

    bool Sell_Condition_1 = (max_anterior >= superior[0]);

    //--- Putting all together
    if (Sell_Condition_1)
    {
        // any opened Sell position?
        if (Sell_opened)
        {
            Alert("We already have a Sell position!!!");
            return; // Don't open a new Sell Position
        }
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;                                     // immediate order execution
        mrequest.price = NormalizeDouble(latest_price.bid, _Digits);             // latest Bid price
        mrequest.sl = NormalizeDouble(latest_price.bid + STP * _Point, _Digits); // Stop Loss
        mrequest.tp = NormalizeDouble(latest_price.bid - TKP * _Point, _Digits); // Take Profit
        mrequest.symbol = _Symbol;                                               // currency pair
        mrequest.volume = Lot;                                                   // number of lots to trade
        mrequest.magic = EA_Magic;                                               // Order Magic Number
        mrequest.type = ORDER_TYPE_SELL;                                         // Sell Order
        mrequest.type_filling = ORDER_FILLING_IOC;                               // Order execution type
        mrequest.deviation = 100;                                                // Deviation from current price
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
//+------------------------------------------------------------------+