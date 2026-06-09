//+------------------------------------------------------------------+
//|                                        Quebra Broker Premium.mq5 |
//|                                               Guilherme Ferreira |
//|                                  guilhermeferreira2107@gmail.com |
//+------------------------------------------------------------------+
#property copyright "Guilherme Ferreira"
#property link "guilhermeferreira2107@gmail.com"
#property version "1.0"

input group "Configurações de horário"

    input string HoraInicio = "00:00"; // Horário de Início
input string HoraTermino = "23:59";    // Horário de Término

input group "Configurações gerais"

    input bool GestaoAutomatica = false; // Gestão manual?
input double StopLoss = 25.0;            // Stop Loss
input double TakeProfit = 50.0;          // Take Profit
input double TamanhoLote = 0.1;          // Volume base (Lotes)
input double DistanciaAlvo = 1.5;        // Multiplicador de distância (risco/retorno)

input group "Configurações do indicador"

    input bool HabilitarSinaisRapidos = false;    // Ordens RSI + ADX (Setas Azuis)
input bool HabilitarSinaisLentos = false;         // Ordens BB  (Setas Roxas)
input bool HabilitarSinaisADX = true;             // Ordens ADX
input bool HabilitarSinaisApenasTendencia = true; // Apenas a Favor da Tendencia
input bool ApenasLong = false;                    // Apenas compras
input bool ApenasShort = false;                   // Apenas vendas
input bool GatilhoCrescendoADX = false;

input group "Configurações de Martingale"

    bool HabilitarMartingale = false; // Habilitar Martingale
int MaxMartingale = 3;                // Máximo de perdas consecutivas

int numeroMagico = 12345;
int periodoBandas = 20;
double desvioBandas = 3.9;
int deslocamentoBandas = 0;
ENUM_APPLIED_PRICE precoBandas = PRICE_CLOSE;

input int periodoRsi = 2;             // RSI Período
input int rsiSobrecomprado = 95;      // RSI Sobre comprado
input int rsiSobrevendido = 5;        // RSI Sobre vendido
input int rsiAltoTendencia = 90;      // RSI Sobre comprado (Tendencia)
input int rsiBaixoTendencia = 10;     // RSI Sobre vendido (Tendencia)
input int periodoMediaCurta = 10;     // Período da média aritmética principal
input int periodoMediaDeslocada = 10; // Período da média aritmética deslocada
input int deslocamentoMedia = 1;      // Deslocamento da segunda média
input int periodoMediaTendencia = 55;

int adxPeriodo = 20;
int adxNivel = 20;

double pontosStop, pontosGain;
int handleBandas, handleRsi, handleAdx, handleMediaCurta, handleMediaDeslocada, handleMediaTendencia;
double bandaSuperior[], bandaInferior[], bufferRsi[], bufferAdx[], bufferMediaCurta[], bufferMediaDeslocada[], bufferMediaTendencia[];

int nivelMartingale = 0;
ulong ultimoTicketProcessado = 0;
double loteAtual = 0;

//--- Verifica o último negócio fechado e ajusta o lote pelo Martingale
void atualizarMartingale()
{
    if (!HabilitarMartingale)
    {
        loteAtual = TamanhoLote;
        return;
    }

    HistorySelect(0, TimeCurrent());
    int total = HistoryDealsTotal();

    for (int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);

        if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
            continue;
        if ((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != numeroMagico)
            continue;
        if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

        if (ticket == ultimoTicketProcessado)
            break; // nenhum negócio novo

        double lucro = HistoryDealGetDouble(ticket, DEAL_PROFIT);

        if (lucro < 0)
            nivelMartingale = MathMin(nivelMartingale + 1, MaxMartingale);
        else
            nivelMartingale = 0;

        ultimoTicketProcessado = ticket;
        break;
    }

    loteAtual = NormalizeDouble(TamanhoLote * MathPow(2.0, nivelMartingale), 2);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
    handleBandas = iBands(_Symbol, _Period, periodoBandas, deslocamentoBandas, desvioBandas, precoBandas);
    handleRsi = iRSI(_Symbol, _Period, periodoRsi, PRICE_CLOSE);
    handleAdx = iADX(_Symbol, _Period, adxPeriodo);
    handleMediaCurta = iMA(_Symbol, _Period, periodoMediaCurta, 0, MODE_SMA, PRICE_CLOSE);
    handleMediaDeslocada = iMA(_Symbol, _Period, periodoMediaDeslocada, deslocamentoMedia, MODE_SMA, PRICE_CLOSE);
    handleMediaTendencia = iMA(_Symbol, _Period, periodoMediaTendencia, 0, MODE_EMA, PRICE_CLOSE);

    if (handleBandas < 0 || handleRsi < 0 || handleAdx < 0 || handleMediaCurta < 0 || handleMediaDeslocada < 0 || handleMediaTendencia < 0)
    {
        Alert("Erro ao criar handles dos indicadores: ", GetLastError());
        return INIT_FAILED;
    }

    pontosStop = StopLoss;
    pontosGain = TakeProfit;

    datetime tInicio = StringToTime("2000.01.01 " + HoraInicio);
    datetime tTermino = StringToTime("2000.01.01 " + HoraTermino);
    if (tInicio == 0 || tTermino == 0)
    {
        Alert("Formato de horário inválido! Use HH:MM (ex: 09:00)");
        return INIT_FAILED;
    }
    if (tInicio >= tTermino)
    {
        Alert("Horário de início deve ser anterior ao horário de término!");
        return INIT_FAILED;
    }

    if (HabilitarMartingale && MaxMartingale < 1)
    {
        Alert("MaxMartingale deve ser pelo menos 1!");
        return INIT_FAILED;
    }

    nivelMartingale = 0;
    ultimoTicketProcessado = 0;
    loteAtual = TamanhoLote;

    // long corAlta = C '0,172,80';
    // long corBaixa = C '224,71,56';
    // long corFundo = C '0,0,25';
    long corDoji = clrLightSlateGray;
    long corForeground = clrDimGray;
    long idGrafico = ChartID();

    if (idGrafico > 0)
    {
        ChartSetInteger(idGrafico, CHART_AUTOSCROLL, true);
        ChartSetInteger(idGrafico, CHART_SHIFT, true);
        ChartSetInteger(idGrafico, CHART_MODE, CHART_CANDLES);
    }

    // ChartSetInteger(0, CHART_COLOR_BACKGROUND, 0, corFundo);
    // ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, 0, corAlta);
    // ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, 0, corBaixa);
    // ChartSetInteger(0, CHART_COLOR_CHART_UP, 0, corAlta);
    // ChartSetInteger(0, CHART_COLOR_CHART_DOWN, 0, corBaixa);
    // ChartSetInteger(0, CHART_COLOR_CHART_LINE, 0, corDoji);
    // ChartSetInteger(0, CHART_COLOR_FOREGROUND, 0, corForeground);
    // ChartSetInteger(0, CHART_SHOW_PERIOD_SEP, 0, corForeground);
    // ChartSetInteger(0, CHART_COLOR_BID, 0, clrDarkOrange);
    // ChartSetInteger(0, CHART_COLOR_ASK, 0, corBaixa);
    // ChartSetInteger(0, CHART_COLOR_STOP_LEVEL, 0, corBaixa);
    // ChartSetInteger(0, CHART_COLOR_LAST, 0, clrDarkOrange);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(handleBandas);
    IndicatorRelease(handleRsi);
    IndicatorRelease(handleAdx);
    IndicatorRelease(handleMediaCurta);
    IndicatorRelease(handleMediaDeslocada);
    IndicatorRelease(handleMediaTendencia);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime agora = TimeCurrent();
    string dataHoje = TimeToString(agora, TIME_DATE);
    datetime inicioHoje = StringToTime(dataHoje + " " + HoraInicio);
    datetime terminoHoje = StringToTime(dataHoje + " " + HoraTermino);
    bool estaAtivo = (agora >= inicioHoje && agora <= terminoHoje);

    string infoMartingale = "";
    if (HabilitarMartingale)
        infoMartingale = StringFormat("\n Martingale: nível %d/%d | Lote: %.2f", nivelMartingale, MaxMartingale, loteAtual);

    Comment("--- QUEBRA BROKER PREMIUM ---",
            "\n Versão 1.0",
            "\n Horário: ", HoraInicio, " - ", HoraTermino,
            "\n Status: ", estaAtivo ? "ATIVO" : "AGUARDANDO",
            infoMartingale,
            "\n", TimeToString(agora, TIME_DATE | TIME_SECONDS));

    if (Bars(_Symbol, _Period) < 60)
    {
        Alert("Barras insuficientes para operar!");
        return;
    }

    static datetime tempoBarraAnterior;
    datetime tempoBarra[1];

    if (CopyTime(_Symbol, _Period, 0, 1, tempoBarra) <= 0)
    {
        Alert("Erro ao copiar tempo das barras: ", GetLastError());
        ResetLastError();
        return;
    }

    if (tempoBarraAnterior == tempoBarra[0])
        return;

    tempoBarraAnterior = tempoBarra[0];

    atualizarMartingale();

    if (!estaAtivo)
        return;

    MqlTick latest_price;
    MqlTradeRequest requisicao;
    MqlTradeResult resultado;
    MqlRates barras[];
    ZeroMemory(requisicao);

    ArraySetAsSeries(barras, true);
    ArraySetAsSeries(bandaSuperior, true);
    ArraySetAsSeries(bandaInferior, true);
    ArraySetAsSeries(bufferRsi, true);
    ArraySetAsSeries(bufferAdx, true);
    ArraySetAsSeries(bufferMediaCurta, true);
    ArraySetAsSeries(bufferMediaDeslocada, true);
    ArraySetAsSeries(bufferMediaTendencia, true);

    if (!SymbolInfoTick(_Symbol, latest_price))
    {
        Alert("Erro ao obter cotação: ", GetLastError());
        return;
    }

    if (CopyRates(_Symbol, _Period, 0, 4, barras) < 0)
    {
        Alert("Erro ao copiar barras: ", GetLastError());
        ResetLastError();
        return;
    }

    if (CopyBuffer(handleBandas, 1, 0, 2, bandaSuperior) < 0 || CopyBuffer(handleBandas, 2, 0, 2, bandaInferior) < 0)
    {
        Alert("Erro ao copiar buffer das Bandas: ", GetLastError());
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleRsi, 0, 0, 3, bufferRsi) < 0)
    {
        Alert("Erro ao copiar buffer do RSI: ", GetLastError());
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleAdx, 0, 0, 6, bufferAdx) < 6)
    {
        Alert("Erro ao copiar buffer do ADX: ", GetLastError());
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleMediaCurta, 0, 0, 3, bufferMediaCurta) < 3)
    {
        Alert("Erro ao copiar buffer da media curta: ", GetLastError());
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleMediaDeslocada, 0, 0, 3, bufferMediaDeslocada) < 3)
    {
        Alert("Erro ao copiar buffer da media deslocada: ", GetLastError());
        ResetLastError();
        return;
    }
    if (CopyBuffer(handleMediaTendencia, 0, 0, 3, bufferMediaTendencia) < 3)
    {
        Alert("Erro ao copiar buffer da media tendencia: ", GetLastError());
        ResetLastError();
        return;
    }

    bool temCompraAberta = false;
    bool temVendaAberta = false;

    if (PositionSelect(_Symbol))
    {
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            temCompraAberta = true;
        else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            temVendaAberta = true;
    }

    bool cruzouParaCima = (bufferMediaCurta[1] > bufferMediaDeslocada[1] &&
                           bufferMediaCurta[2] <= bufferMediaDeslocada[2]);
    bool cruzouParaBaixo = (bufferMediaCurta[1] < bufferMediaDeslocada[1] &&
                            bufferMediaCurta[2] >= bufferMediaDeslocada[2]);

    if (temCompraAberta && cruzouParaBaixo)
    {
        ZeroMemory(requisicao);

        double volumePosicao = PositionGetDouble(POSITION_VOLUME);

        requisicao.action = TRADE_ACTION_DEAL;
        requisicao.position = PositionGetInteger(POSITION_TICKET);
        requisicao.symbol = _Symbol;
        requisicao.volume = volumePosicao;
        requisicao.magic = numeroMagico;
        requisicao.type = ORDER_TYPE_SELL;
        requisicao.price = NormalizeDouble(latest_price.bid, _Digits);
        requisicao.type_filling = ORDER_FILLING_FOK;
        requisicao.deviation = 100;

        if (!OrderSend(requisicao, resultado))
        {
            Alert("Erro ao encerrar ordem de compra: ", GetLastError());
            ResetLastError();
            return;
        }

        if (resultado.retcode == 10009 || resultado.retcode == 10008)
            Alert("Ordem de compra encerrada! Ticket#: ", resultado.order);

        return;
    }

    bool adxCrescendo = (bufferAdx[1] > bufferAdx[2] &&
                         bufferAdx[2] > bufferAdx[3] &&
                         bufferAdx[3] > bufferAdx[4] &&
                         bufferAdx[4] > bufferAdx[5]);

    // ADX >= adxNivel indica mercado em tendência; abaixo disso, mercado lateral
    bool emTendencia = (bufferAdx[0] >= adxNivel) && adxCrescendo;

    bool precoAcimaTendenciaAlta = (bufferMediaCurta[0] > bufferMediaTendencia[0]) && (bufferMediaDeslocada[0] > bufferMediaTendencia[0]);

    bool condCompra1 = (!temCompraAberta && !temVendaAberta && cruzouParaCima) && precoAcimaTendenciaAlta;

    if (condCompra1)
    {
        if (ApenasShort)
        {
            Alert("Apenas posições de venda são permitidas!");
            return;
        }

        ZeroMemory(requisicao);

        double min0 = iLow(_Symbol, _Period, 0);
        double min1 = iLow(_Symbol, _Period, 1);
        double min2 = iLow(_Symbol, _Period, 2);
        double sl = MathMin(min0, MathMin(min1, min2));
        double dist = latest_price.ask - sl;
        double tp = latest_price.ask + (dist * DistanciaAlvo);

        double slManual = NormalizeDouble(latest_price.ask - pontosStop * _Point, _Digits);
        double tpManual = NormalizeDouble(latest_price.ask + pontosGain * _Point, _Digits);

        requisicao.action = TRADE_ACTION_DEAL;
        requisicao.price = NormalizeDouble(latest_price.ask, _Digits);
        // requisicao.tp = GestaoAutomatica ? tpManual : NormalizeDouble(tp, _Digits);
        // requisicao.sl = GestaoAutomatica ? slManual : NormalizeDouble(sl, _Digits);
        requisicao.symbol = _Symbol;
        requisicao.volume = loteAtual;
        requisicao.magic = numeroMagico;
        requisicao.type = ORDER_TYPE_BUY;
        requisicao.type_filling = ORDER_FILLING_FOK;
        requisicao.deviation = 100;
        if (!OrderSend(requisicao, resultado))
        {
            Alert("Erro ao enviar ordem de compra: ", GetLastError());
            ResetLastError();
            return;
        }
        if (resultado.retcode == 10009 || resultado.retcode == 10008)
            Alert("Ordem de compra enviada! Ticket#: ", resultado.order, " | Lote: ", loteAtual);
    }
}
//+------------------------------------------------------------------+
