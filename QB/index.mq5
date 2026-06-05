//+------------------------------------------------------------------+
//|                                                       QB.mq5     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"

//--- parâmetros de entrada
input double Lot           = 0.1;  // Lotes para operar
input int    RSI_Periodo   = 3;    // Período do RSI
input int    RSI_MAX       = 94;   // RSI máximo
input int    RSI_MIN       = 6;    // RSI mínimo
input double distancia_alvo = 1.5; // Multiplicador de distância (risco/retorno)

int EA_Magic = 12345;

//--- handles e buffers
int    handleRSI;
double rsi_buffer[];

//+------------------------------------------------------------------+
int OnInit()
{
    handleRSI = iRSI(_Symbol, _Period, RSI_Periodo, PRICE_CLOSE);
    if (handleRSI < 0)
    {
        Alert("Erro ao criar o handle do RSI - erro: ", GetLastError(), "!!");
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    IndicatorRelease(handleRSI);
}

void OnTick()
{
    if (Bars(_Symbol, _Period) < 60)
    {
        Alert("Ha menos de 60 barras, o EA sera encerrado!!");
        return;
    }

    // Detecção de nova barra
    static datetime Old_Time;
    datetime New_Time[1];
    int copied = CopyTime(_Symbol, _Period, 0, 1, New_Time);
    if (copied > 0)
    {
        if (Old_Time != New_Time[0])
        {
            if (MQL5InfoInteger(MQL5_DEBUGGING))
                Print("Nova barra detectada em ", New_Time[0], " | barra anterior: ", Old_Time);
            Old_Time = New_Time[0];
        }
        else
            return;
    }
    else
    {
        Alert("Erro ao copiar o historico de tempos, erro = ", GetLastError());
        ResetLastError();
        return;
    }

    //--- Estruturas MQL5
    MqlTick         latest_price;
    MqlTradeRequest mrequest;
    MqlTradeResult  mresult;
    MqlRates        mrate[];
    ZeroMemory(mrequest);

    ArraySetAsSeries(mrate,       true);
    ArraySetAsSeries(rsi_buffer,  true);

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Erro ao obter a ultima cotacao - erro: ", GetLastError(), "!!");
        return;
    }
    if (CopyRates(_Symbol, _Period, 0, 3, mrate) < 0)
    {
        Alert("Erro ao copiar os dados de precos/historico - erro: ", GetLastError(), "!!");
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleRSI, 0, 0, 3, rsi_buffer) < 0)
    {
        Alert("Erro ao copiar os buffers do RSI - erro: ", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    //--- Verificar posições abertas
    bool Buy_opened  = false;
    bool Sell_opened = false;
    if (PositionSelect(_Symbol))
    {
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            Buy_opened = true;
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            Sell_opened = true;
    }

    //--- Condição de compra: RSI cruzou de baixo para cima o RSI_MIN
    bool Buy_Signal = (rsi_buffer[2] < RSI_MIN && rsi_buffer[1] > RSI_MIN);

    if (Buy_Signal)
    {
        if (Buy_opened)
        {
            Alert("Ja existe uma posicao comprada aberta!!!");
            return;
        }
        double min0 = iLow(_Symbol, _Period, 0);
        double min1 = iLow(_Symbol, _Period, 1);
        double min2 = iLow(_Symbol, _Period, 2);
        double sl   = MathMin(min0, MathMin(min1, min2));
        double dist = latest_price.ask - sl;
        double tp   = latest_price.ask + (dist * distancia_alvo);

        ZeroMemory(mrequest);
        mrequest.action       = TRADE_ACTION_DEAL;
        mrequest.price        = NormalizeDouble(latest_price.ask, _Digits);
        mrequest.sl           = NormalizeDouble(sl, _Digits);
        mrequest.tp           = NormalizeDouble(tp, _Digits);
        mrequest.symbol       = _Symbol;
        mrequest.volume       = Lot;
        mrequest.magic        = EA_Magic;
        mrequest.type         = ORDER_TYPE_BUY;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation    = 100;
        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
            Alert("Ordem de compra enviada com sucesso. Ticket#: ", mresult.order, "!!");
        else
        {
            Alert("A solicitacao de compra nao pode ser concluida - erro: ", GetLastError());
            ResetLastError();
        }
        return;
    }

    //--- Condição de venda: RSI cruzou de cima para baixo o RSI_MAX
    bool Sell_Signal = (rsi_buffer[2] > RSI_MAX && rsi_buffer[1] < RSI_MAX);

    if (Sell_Signal)
    {
        if (Sell_opened)
        {
            Alert("Ja existe uma posicao vendida aberta!!!");
            return;
        }
        double max0 = iHigh(_Symbol, _Period, 0);
        double max1 = iHigh(_Symbol, _Period, 1);
        double max2 = iHigh(_Symbol, _Period, 2);
        double sl   = MathMax(max0, MathMax(max1, max2));
        double dist = sl - latest_price.bid;
        double tp   = latest_price.bid - (dist * distancia_alvo);

        ZeroMemory(mrequest);
        mrequest.action       = TRADE_ACTION_DEAL;
        mrequest.price        = NormalizeDouble(latest_price.bid, _Digits);
        mrequest.sl           = NormalizeDouble(sl, _Digits);
        mrequest.tp           = NormalizeDouble(tp, _Digits);
        mrequest.symbol       = _Symbol;
        mrequest.volume       = Lot;
        mrequest.magic        = EA_Magic;
        mrequest.type         = ORDER_TYPE_SELL;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation    = 100;
        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
            Alert("Ordem de venda enviada com sucesso. Ticket#: ", mresult.order, "!!");
        else
        {
            Alert("A solicitacao de venda nao pode ser concluida - erro: ", GetLastError());
            ResetLastError();
        }
    }
}
//+------------------------------------------------------------------+
