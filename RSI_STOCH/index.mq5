//+------------------------------------------------------------------+
//|                                                  My_First_EA.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"
//--- input parameters
input int StopLoss = 300;               // Stop Loss
input int TakeProfit = 100;             // Take Profit
input double GanhoDia = 120;            // Limite de ganho diário (R$)
input double PerdaDia = 60;             // Limite de Perda diário (R$)
int EA_Magic = 12345;                   // EA Magic Number
input double Lot = 1;                   // Lots to Trade
int Periodo = 20;                       // Período
int Deslocamento = 0;                   // Deslocar
ENUM_APPLIED_PRICE Preco = PRICE_CLOSE; // Preço Aplicado
input int RSI_Periodo = 14;             // Período RSI
input int RSI_MAX = 70;                 // RSI Máximo
input int RSI_MIN = 30;                 // RSI Mínimo
input int STO_K_Period = 14;            // Periodo %K
input int STO_D_Period = 3;             // Periodo %D
input int STO_Slowing = 3;              // Suavizacao
input double STO_Overbought = 80.0;     // Nivel de sobrecompra
input double STO_Oversold = 20.0;       // Nivel de sobrevenda
input bool EnableRSIStrategy = true;    // Ativa sinais do RSI
input bool EnableStochStrategy = true;  // Ativa sinais do Estocastico
input bool EnableMATrend = true;        // Filtro de tendencia pela media
input int MA_Period = 50;               // Periodo da media
input ENUM_MA_METHOD MA_Method = MODE_EMA;
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE;
//--- Other parameters
double p_close; // Variable to store the close value of a bar
int STP, TKP;   // To be used for Stop Loss & Take Profit values
int handleRSI, handleStoch, handleMA;
double rsi_buffer[], stoch_k[], stoch_d[], ma_buffer[];
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    handleRSI = iRSI(_Symbol, _Period, RSI_Periodo, PRICE_CLOSE);
    handleStoch = iStochastic(_Symbol, _Period, STO_K_Period, STO_D_Period, STO_Slowing, MODE_SMA, STO_LOWHIGH);
    handleMA = iMA(_Symbol, _Period, MA_Period, 0, MA_Method, MA_Price);
    //--- What if handle returns Invalid Handle
    if (handleRSI < 0 || handleStoch < 0 || handleMA < 0)
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
    IndicatorRelease(handleRSI);
    IndicatorRelease(handleStoch);
    IndicatorRelease(handleMA);
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

    // the rates arrays
    ArraySetAsSeries(mrate, true);
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(stoch_k, true);
    ArraySetAsSeries(stoch_d, true);
    ArraySetAsSeries(ma_buffer, true);

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

    if (CopyBuffer(handleStoch, 0, 0, 2, stoch_k) < 0 || CopyBuffer(handleStoch, 1, 0, 2, stoch_d) < 0)
    {
        Alert("Error copying Stochastic indicator Buffers - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleMA, 0, 0, 2, ma_buffer) < 0)
    {
        Alert("Error copying MA indicator Buffers - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleRSI, 0, 0, 2, rsi_buffer) < 0)
    {
        Alert("Error copying ADX indicator Buffers - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }
    //--- we have no errors, so continue
    //--- Do we have positions opened already?
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

    //--- Buy Conditions
    bool BuyRSI = rsi_buffer[1] < RSI_MIN && rsi_buffer[0] > RSI_MIN;
    bool Stoch_Buy_Cross = (stoch_k[1] <= stoch_d[1] && stoch_k[0] > stoch_d[0]); // %K cruza acima de %D
    bool Stoch_Back_From_Oversold = (stoch_k[1] < STO_Oversold);
    bool BuyStoch = (Stoch_Buy_Cross && Stoch_Back_From_Oversold);
    bool TrendBuy = (!EnableMATrend) || (mrate[0].close > ma_buffer[0]);
    bool BuySignal = (EnableRSIStrategy || EnableStochStrategy) && (EnableRSIStrategy ? BuyRSI : true) && (EnableStochStrategy ? BuyStoch : true) && TrendBuy;

    if (BuySignal)
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
    //--- Sell Conditions
    bool SellRSI = rsi_buffer[1] > RSI_MAX && rsi_buffer[0] < RSI_MAX;
    bool Stoch_Sell_Cross = (stoch_k[1] >= stoch_d[1] && stoch_k[0] < stoch_d[0]); // %K cruza abaixo de %D
    bool Stoch_Back_From_Overbought = (stoch_k[1] > STO_Overbought);
    bool SellStoch = (Stoch_Sell_Cross && Stoch_Back_From_Overbought);
    bool TrendSell = (!EnableMATrend) || (mrate[0].close < ma_buffer[0]);
    bool SellSignal = (EnableRSIStrategy || EnableStochStrategy) && (EnableRSIStrategy ? SellRSI : true) && (EnableStochStrategy ? SellStoch : true) && TrendSell;

    if (SellSignal)
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
