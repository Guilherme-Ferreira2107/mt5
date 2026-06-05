//+------------------------------------------------------------------+
//|                                                  My_First_EA.mq5 |
//|                        Copyright 2010, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2010, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.10"

int EA_Magic = 12345;

// Risk and targets
input int StopLoss = 100;
input int TakeProfit = 300;
input bool usarTakeProfitFixo = false;
input double AlvoRR = 4.0;
input int StopBuffer = 20;

// Position sizing
input double Lot = 0.1;

// Trend and pullback
input bool apenasCruzamento = false;
input int MA_Periodo_Rapido = 20;
input int MA_Periodo_Medio = 50;
input int MA_Periodo_Lento = 100;
input int DistanciaMaxMedia = 120;
input double Desvio = 4;
input int Deslocamento = 0;
input ENUM_APPLIED_PRICE Preco = PRICE_CLOSE;

// RSI
input int RSI_Periodo = 3;
input int RSI_MAX = 90;
input int RSI_MIN = 10;
input int RSI_Compra_Retomada = 40;
input int RSI_Venda_Retomada = 60;

// Session filter
input bool habilitaHorario = false;
input int horaInicio = 9;
input int horaFim = 11;

// Trade management
input bool usarTrailingStop = true;

double ultimoResultado = 0.0;
bool ultimoTradeLucro = false;

double p_close;
int STP, TKP;
int handleBands, handleRSI, handleFastMA, handleSlowMA;

double superior[], inferior[], rsi_buffer[], fastMA[], slowMA[];

bool HorarioPermitido()
{
    if (!habilitaHorario)
        return true;

    MqlDateTime partesServidor;
    TimeToStruct(TimeCurrent(), partesServidor);
    return (partesServidor.hour >= horaInicio && partesServidor.hour < horaFim);
}

double LimitarStopCompra(double precoEntrada, double stopBase)
{
    double stopMinimo = precoEntrada - STP * _Point;
    return NormalizeDouble(MathMax(stopBase, stopMinimo), _Digits);
}

double LimitarStopVenda(double precoEntrada, double stopBase)
{
    double stopMaximo = precoEntrada + STP * _Point;
    return NormalizeDouble(MathMin(stopBase, stopMaximo), _Digits);
}

double CalcularTakeCompra(double precoEntrada, double stopLoss)
{
    if (usarTakeProfitFixo)
        return NormalizeDouble(precoEntrada + TKP * _Point, _Digits);

    double risco = precoEntrada - stopLoss;
    return NormalizeDouble(precoEntrada + (risco * AlvoRR), _Digits);
}

double CalcularTakeVenda(double precoEntrada, double stopLoss)
{
    if (usarTakeProfitFixo)
        return NormalizeDouble(precoEntrada - TKP * _Point, _Digits);

    double risco = stopLoss - precoEntrada;
    return NormalizeDouble(precoEntrada - (risco * AlvoRR), _Digits);
}

void GerenciarTrailingStop()
{
    if (!usarTrailingStop || !PositionSelect(_Symbol))
        return;

    long tipo = PositionGetInteger(POSITION_TYPE);
    double slAtual = PositionGetDouble(POSITION_SL);
    double tpAtual = PositionGetDouble(POSITION_TP);
    double novoSL = slAtual;

    if (tipo == POSITION_TYPE_BUY)
    {
        novoSL = NormalizeDouble(iLow(_Symbol, _Period, 1) - StopBuffer * _Point, _Digits);
        if (novoSL <= slAtual)
            return;
    }
    else if (tipo == POSITION_TYPE_SELL)
    {
        novoSL = NormalizeDouble(iHigh(_Symbol, _Period, 1) + StopBuffer * _Point, _Digits);
        if (slAtual != 0.0 && novoSL >= slAtual)
            return;
    }
    else
    {
        return;
    }

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_SLTP;
    request.symbol = _Symbol;
    request.magic = EA_Magic;
    request.sl = novoSL;
    request.tp = tpAtual;

    if (!OrderSend(request, result))
        Print("Falha ao atualizar trailing stop. Erro: ", GetLastError());
}

int OnInit()
{
    handleBands = iBands(_Symbol, _Period, 20, Deslocamento, Desvio, Preco);
    handleRSI = iRSI(_Symbol, _Period, RSI_Periodo, PRICE_CLOSE);
    handleFastMA = iMA(_Symbol, _Period, MA_Periodo_Medio, 0, MODE_EMA, PRICE_CLOSE);
    handleSlowMA = iMA(_Symbol, _Period, MA_Periodo_Lento, 0, MODE_EMA, PRICE_CLOSE);

    if (handleBands < 0 || handleRSI < 0 || handleFastMA < 0 || handleSlowMA < 0)
    {
        Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
        return (-1);
    }

    STP = StopLoss;
    TKP = TakeProfit;

    if (_Digits == 5 || _Digits == 3)
    {
        STP *= 10;
        TKP *= 10;
    }

    return (0);
}

void OnDeinit(const int reason)
{
    IndicatorRelease(handleBands);
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
            Old_Time = New_Time[0];
        }
    }
    else
    {
        Alert("Error in copying historical times data, error =", GetLastError());
        ResetLastError();
        return;
    }

    if (!IsNewBar || !HorarioPermitido())
        return;

    MqlTick latest_price;
    MqlTradeRequest mrequest;
    MqlTradeResult mresult;
    MqlRates mrate[];
    ZeroMemory(mrequest);
    ZeroMemory(mresult);

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

    if (CopyBuffer(handleBands, 1, 0, 3, superior) < 0 || CopyBuffer(handleBands, 2, 0, 3, inferior) < 0)
    {
        Alert("Error copying Bollinger Buffers - error:", GetLastError(), "!!");
        ResetLastError();
        return;
    }

    if (CopyBuffer(handleRSI, 0, 0, 3, rsi_buffer) < 0)
    {
        Alert("Error copying RSI Buffers - error:", GetLastError(), "!!");
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

    if (PositionSelect(_Symbol))
    {
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            Buy_opened = true;
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            Sell_opened = true;
    }

    if (Buy_opened || Sell_opened)
    {
        GerenciarTrailingStop();
        return;
    }

    p_close = mrate[1].close;

    double min_anterior = iLow(_Symbol, _Period, 1);
    double max_anterior = iHigh(_Symbol, _Period, 1);
    double fechamentoAnterior = mrate[1].close;

    bool tendenciaAlta = (fastMA[1] > slowMA[1] && fastMA[0] > slowMA[0] && fastMA[0] > fastMA[1] && slowMA[0] >= slowMA[1]);
    bool tendenciaBaixa = (fastMA[1] < slowMA[1] && fastMA[0] < slowMA[0] && fastMA[0] < fastMA[1] && slowMA[0] <= slowMA[1]);

    bool pullbackCompra = (min_anterior <= fastMA[1] || min_anterior <= inferior[1]);
    bool pullbackVenda = (max_anterior >= fastMA[1] || max_anterior >= superior[1]);

    bool retomadaRSICompra = (rsi_buffer[1] <= RSI_Compra_Retomada && rsi_buffer[0] > rsi_buffer[1]);
    bool retomadaRSIVenda = (rsi_buffer[1] >= RSI_Venda_Retomada && rsi_buffer[0] < rsi_buffer[1]);

    bool pertoMediaCompra = (MathAbs(fechamentoAnterior - fastMA[1]) <= DistanciaMaxMedia * _Point);
    bool pertoMediaVenda = (MathAbs(fechamentoAnterior - fastMA[1]) <= DistanciaMaxMedia * _Point);

    bool CrossUp = (fastMA[1] < slowMA[1] && fastMA[0] > slowMA[0]);
    bool CrossDown = (fastMA[1] > slowMA[1] && fastMA[0] < slowMA[0]);

    bool Buy_Condition_Trend = (tendenciaAlta && pullbackCompra && retomadaRSICompra && pertoMediaCompra);
    bool Sell_Condition_Trend = (tendenciaBaixa && pullbackVenda && retomadaRSIVenda && pertoMediaVenda);

    bool Buy_Condition_Fallback = (rsi_buffer[1] >= RSI_MAX && rsi_buffer[0] <= RSI_MAX);
    bool Sell_Condition_Fallback = (rsi_buffer[1] <= 50 && rsi_buffer[0] >= 50);

    bool sinalCompra = apenasCruzamento ? CrossUp : (Buy_Condition_Trend || (tendenciaAlta && Buy_Condition_Fallback));
    bool sinalVenda = apenasCruzamento ? CrossDown : (Sell_Condition_Trend || (tendenciaBaixa && Sell_Condition_Fallback));

    if (sinalCompra)
    {
        double precoCompra = NormalizeDouble(latest_price.ask, _Digits);
        double stopCompra = LimitarStopCompra(precoCompra, min_anterior - StopBuffer * _Point);
        double takeCompra = CalcularTakeCompra(precoCompra, stopCompra);

        ZeroMemory(mrequest);
        ZeroMemory(mresult);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = precoCompra;
        mrequest.sl = stopCompra;
        mrequest.tp = takeCompra;
        mrequest.symbol = _Symbol;
        mrequest.volume = Lot;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_BUY;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = 100;

        bool enviadoCompra = OrderSend(mrequest, mresult);
        if (enviadoCompra && (mresult.retcode == 10009 || mresult.retcode == 10008))
            Alert("A Buy order has been successfully placed with Ticket#:", mresult.order, "!!");
        else
        {
            Alert("The Buy order request could not be completed -error:", GetLastError());
            ResetLastError();
        }
        return;
    }

    if (sinalVenda)
    {
        double precoVenda = NormalizeDouble(latest_price.bid, _Digits);
        double stopVenda = LimitarStopVenda(precoVenda, max_anterior + StopBuffer * _Point);
        double takeVenda = CalcularTakeVenda(precoVenda, stopVenda);

        ZeroMemory(mrequest);
        ZeroMemory(mresult);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = precoVenda;
        mrequest.sl = stopVenda;
        mrequest.tp = takeVenda;
        mrequest.symbol = _Symbol;
        mrequest.volume = Lot;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_SELL;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = 100;

        bool enviadoVenda = OrderSend(mrequest, mresult);
        if (enviadoVenda && (mresult.retcode == 10009 || mresult.retcode == 10008))
            Alert("A Sell order has been successfully placed with Ticket#:", mresult.order, "!!");
        else
        {
            Alert("The Sell order request could not be completed -error:", GetLastError());
            ResetLastError();
        }
    }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD)
        return;
    if (trans.symbol != _Symbol)
        return;

    datetime from = TimeCurrent() - 2 * 86400;
    datetime to = TimeCurrent();

    if (!HistorySelect(from, to))
    {
        Print("Erro ao selecionar historico: ", GetLastError());
        return;
    }

    int totalDeals = HistoryDealsTotal();
    if (totalDeals <= 0)
    {
        Print("Nenhum deal no historico.");
        return;
    }

    ulong last_deal = HistoryDealGetTicket(totalDeals - 1);
    if (HistoryDealGetInteger(last_deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
        return;

    double profit = HistoryDealGetDouble(last_deal, DEAL_PROFIT);
    double commission = HistoryDealGetDouble(last_deal, DEAL_COMMISSION);
    double swap = HistoryDealGetDouble(last_deal, DEAL_SWAP);

    ultimoResultado = profit + commission + swap;
    ultimoTradeLucro = (ultimoResultado >= 0.0);

    PrintFormat("[GUILHERME] Ultimo trade fechado: %.2f (%s)",
                ultimoResultado,
                ultimoTradeLucro ? "lucro" : "prejuizo");
}

//+------------------------------------------------------------------+
