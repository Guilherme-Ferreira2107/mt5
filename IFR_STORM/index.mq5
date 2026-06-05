//+------------------------------------------------------------------+
//|                                                   IFR_STORM.mq5 |
//|          Stormer: IFR2 + ADX + MMS20 (Stop) + MMS200 (Tendência)|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link ""
#property version "1.02"

//--- parâmetros de entrada
input int IFR_Periodo = 3;     // Período do IFR
input int IFR_Compra = 6;      // IFR Compra (Sobrevenda)
input int IFR_Venda = 94;      // IFR Venda (Sobrecompra)
input int MMS_Periodo = 200;   // Período da Média de Stop (MMS20)
input int Trend_Periodo = 200; // Período da Média de Tendência (MMS200)
input int ADX_Periodo = 14;    // Período do ADX
input int ADX_Max = 36;        // ADX Máximo para Entrar
input double Lot = 0.1;        // Volume (Lotes)

int EA_Magic = 98765;

//--- handles dos indicadores
int handleRSI, handleMMS20, handleMMS200, handleADX;

//--- buffers dos indicadores
double rsi_buf[], mms20_buf[], mms200_buf[], adx_buf[];

//--- alvos gerenciados manualmente (sem mrequest.tp para evitar reabertura automática)
double g_tp_long = 0;
double g_tp_short = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    handleRSI = iRSI(_Symbol, _Period, IFR_Periodo, PRICE_CLOSE);
    handleMMS20 = iMA(_Symbol, _Period, MMS_Periodo, 0, MODE_SMA, PRICE_CLOSE);
    handleMMS200 = iMA(_Symbol, _Period, Trend_Periodo, 0, MODE_SMA, PRICE_CLOSE);
    handleADX = iADX(_Symbol, _Period, ADX_Periodo);

    if (handleRSI < 0 || handleMMS20 < 0 || handleMMS200 < 0 || handleADX < 0)
    {
        Alert("Erro ao criar handles dos indicadores - erro: ", GetLastError());
        return INIT_FAILED;
    }
    g_tp_long = 0;
    g_tp_short = 0;
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    IndicatorRelease(handleRSI);
    IndicatorRelease(handleMMS20);
    IndicatorRelease(handleMMS200);
    IndicatorRelease(handleADX);
}

//+------------------------------------------------------------------+
// Verifica se existe posição aberta DESTE EA (filtra pelo magic number)
// Preenche tipo e ticket da posição encontrada
//+------------------------------------------------------------------+
bool PosicaoAberta(ENUM_POSITION_TYPE &tipo, ulong &ticket_out)
{
    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == EA_Magic)
        {
            tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ticket_out = ticket;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
// Fecha a posição do EA pelo ticket correto
//+------------------------------------------------------------------+
void ClosePosition(bool isBuy, const MqlTick &tick, string comment)
{
    ENUM_POSITION_TYPE tipo;
    ulong ticket = 0;
    if (!PosicaoAberta(tipo, ticket))
        return;

    MqlTradeRequest mrequest;
    MqlTradeResult mresult;
    ZeroMemory(mrequest);
    mrequest.action = TRADE_ACTION_DEAL;
    mrequest.symbol = _Symbol;
    mrequest.volume = PositionGetDouble(POSITION_VOLUME);
    mrequest.magic = EA_Magic;
    mrequest.type_filling = ORDER_FILLING_IOC;
    mrequest.deviation = 100;
    mrequest.comment = comment;
    mrequest.position = ticket;
    if (isBuy)
    {
        mrequest.type = ORDER_TYPE_SELL;
        mrequest.price = NormalizeDouble(tick.bid, _Digits);
    }
    else
    {
        mrequest.type = ORDER_TYPE_BUY;
        mrequest.price = NormalizeDouble(tick.ask, _Digits);
    }
    OrderSend(mrequest, mresult);
    if (mresult.retcode != 10009 && mresult.retcode != 10008)
    {
        Alert("Erro ao fechar posição - retcode:", mresult.retcode, " erro:", GetLastError());
        ResetLastError();
    }
}

//+------------------------------------------------------------------+
void OnTick()
{
    if (Bars(_Symbol, _Period) < 210)
        return;

    // Detecção de novo candle
    static datetime Old_Time;
    datetime New_Time[1];
    if (CopyTime(_Symbol, _Period, 0, 1, New_Time) <= 0)
    {
        Alert("Erro ao copiar tempo - erro:", GetLastError());
        ResetLastError();
        return;
    }
    if (Old_Time == New_Time[0])
        return;
    Old_Time = New_Time[0];

    // Dados de mercado e indicadores
    MqlTick latest_price;
    MqlRates mrate[];

    ArraySetAsSeries(mrate, true);
    ArraySetAsSeries(rsi_buf, true);
    ArraySetAsSeries(mms20_buf, true);
    ArraySetAsSeries(mms200_buf, true);
    ArraySetAsSeries(adx_buf, true);

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Erro ao obter preço - erro:", GetLastError());
        return;
    }
    if (CopyRates(_Symbol, _Period, 0, 3, mrate) < 3)
    {
        Alert("Erro ao copiar rates - erro:", GetLastError());
        return;
    }
    if (CopyBuffer(handleRSI, 0, 0, 3, rsi_buf) < 3 ||
        CopyBuffer(handleMMS20, 0, 0, 3, mms20_buf) < 3 ||
        CopyBuffer(handleMMS200, 0, 0, 3, mms200_buf) < 3 ||
        CopyBuffer(handleADX, 0, 0, 3, adx_buf) < 3)
    {
        Alert("Erro ao copiar buffers dos indicadores - erro:", GetLastError());
        return;
    }

    // Estado das posições abertas (filtrando pelo magic number)
    ENUM_POSITION_TYPE posType;
    ulong pos_ticket = 0;
    bool tem_posicao = PosicaoAberta(posType, pos_ticket);
    bool Buy_opened = tem_posicao && (posType == POSITION_TYPE_BUY);
    bool Sell_opened = tem_posicao && (posType == POSITION_TYPE_SELL);

    // Valores dos indicadores
    // Índice [1] = último candle fechado  = "close"    no Pine
    // Índice [2] = dois candles atrás     = "close[1]" no Pine
    double rsi_anterior = rsi_buf[2];
    double rsi_atual = rsi_buf[1];
    double mms20_atual = mms20_buf[1];
    double mms200_atual = mms200_buf[1];
    double adx_atual = adx_buf[1];
    double close_atual = mrate[1].close;
    double close_ant = mrate[2].close;
    double mms20_ant = mms20_buf[2];

    // Proteção: aguardar warm-up dos indicadores (EMPTY_VALUE ou zero = não calculado)
    if (mms200_atual == EMPTY_VALUE || mms200_atual <= 0 ||
        mms20_atual == EMPTY_VALUE || mms20_atual <= 0 ||
        rsi_atual == EMPTY_VALUE ||
        adx_atual == EMPTY_VALUE)
        return;

    // ---- GERENCIAMENTO DE SAÍDA ----
    // Stop: fechar quando close cruza a MMS20
    // TP:   fechar quando close atinge o alvo calculado na entrada
    if (Buy_opened)
    {
        bool stop_long = (close_atual < mms20_atual);
        bool tp_long = (g_tp_long > 0 && close_atual >= g_tp_long);
        if (stop_long || tp_long)
        {
            ClosePosition(true, latest_price, stop_long ? "Stop MMS20 Long" : "Alvo Long");
            g_tp_long = 0;
        }
        return;
    }

    if (Sell_opened)
    {
        bool stop_short = (close_atual > mms20_atual);
        bool tp_short = (g_tp_short > 0 && close_atual <= g_tp_short);
        if (stop_short || tp_short)
        {
            ClosePosition(false, latest_price, stop_short ? "Stop MMS20 Short" : "Alvo Short");
            g_tp_short = 0;
        }
        return;
    }

    // ---- CONDIÇÕES DE ENTRADA ----
    // media_abaixo: candle anterior fechou ACIMA da MMS20 → média como suporte (para compra)
    // media_acima:  candle anterior fechou ABAIXO da MMS20 → média como resistência (para venda)
    bool media_abaixo = (close_ant > mms20_ant);
    bool media_acima = (close_ant < mms20_ant);

    // Compra:  preço ACIMA da MMS200 + IFR sobrevenda + ADX fraco + alinhamento MMS20
    // Venda:   preço ABAIXO da MMS200 + IFR sobrecompra + ADX fraco + alinhamento MMS20
    bool BuySignal = (close_atual > mms200_atual) &&
                     (rsi_anterior < (double)IFR_Compra) &&
                     (rsi_atual > (double)IFR_Compra) &&
                     (adx_atual < (double)ADX_Max) &&
                     media_abaixo;

    bool SellSignal = (close_atual < mms200_atual) &&
                      (rsi_atual > (double)IFR_Venda) &&
                      (adx_atual < (double)ADX_Max) &&
                      media_acima;

    double MenorMinimaDasTresUltimasVelas = MathMin(mrate[1].low, MathMin(mrate[2].low, mrate[3].low));
    double MaiorMaximaDasTresUltimasVelas = MathMax(mrate[1].high, MathMin(mrate[2].high, mrate[3].high));

    // ---- ABERTURA DE COMPRA ----
    if (BuySignal)
    {
        // Alvo = máxima dos 2 últimos candles fechados (ta.highest(high, 2) no Pine)
        double tp = MathMax(mrate[1].high, mrate[2].high);

        MqlTradeRequest mrequest;
        MqlTradeResult mresult;
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = NormalizeDouble(latest_price.ask, _Digits);
        mrequest.sl = 0;
        mrequest.tp = 0;
        mrequest.symbol = _Symbol;
        mrequest.volume = Lot;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_BUY;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = 100;
        mrequest.comment = "IFR Storm Compra";
        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
        {
            g_tp_long = tp;
            Alert("Compra realizada! Ticket#:", mresult.order, " | TP: ", tp);
        }
        else
        {
            Alert("Erro na ordem de Compra - retcode:", mresult.retcode, " erro:", GetLastError());
            ResetLastError();
        }
    }

    // ---- ABERTURA DE VENDA ----
    else if (SellSignal)
    {
        // Alvo = mínima dos 2 últimos candles fechados (ta.lowest(low, 2) no Pine)
        double tp = MathMin(mrate[1].low, mrate[2].low);

        MqlTradeRequest mrequest;
        MqlTradeResult mresult;
        ZeroMemory(mrequest);
        mrequest.action = TRADE_ACTION_DEAL;
        mrequest.price = NormalizeDouble(latest_price.bid, _Digits);
        mrequest.sl = 0;
        mrequest.tp = 0;
        mrequest.symbol = _Symbol;
        mrequest.volume = Lot;
        mrequest.magic = EA_Magic;
        mrequest.type = ORDER_TYPE_SELL;
        mrequest.type_filling = ORDER_FILLING_IOC;
        mrequest.deviation = 100;
        mrequest.comment = "IFR Storm Venda";
        OrderSend(mrequest, mresult);
        if (mresult.retcode == 10009 || mresult.retcode == 10008)
        {
            g_tp_short = tp;
            Alert("Venda realizada! Ticket#:", mresult.order, " | TP: ", tp);
        }
        else
        {
            Alert("Erro na ordem de Venda - retcode:", mresult.retcode, " erro:", GetLastError());
            ResetLastError();
        }
    }
}
//+------------------------------------------------------------------+
