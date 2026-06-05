//+------------------------------------------------------------------+
//|                          laryy.mq5                               |
//|                         Guilherme Santos                         |
//|       SEPA VCP Robot — conversão de PineScript para MQ5          |
//+------------------------------------------------------------------+
#property copyright "Guilherme Santos"
#property version   "1.00"

#include <Trade\Trade.mqh>

enum ENUM_TRADE_DIR
{
    DIR_BOTH  = 0, // Ambos
    DIR_LONG  = 1, // Apenas Long
    DIR_SHORT = 2  // Apenas Short
};

// ── Trend Template ────────────────────────────────────────────
input group              "Trend Template"
input int    MA50Len       = 50;  // MA 50
input int    MA150Len      = 150; // MA 150
input int    MA200Len      = 200; // MA 200
input int    MA200SlopeLen = 20;  // MA 200 slope (candles)
input int    TTMinScore    = 6;   // Score mínimo (0-6)

// ── VCP ───────────────────────────────────────────────────────
input group              "VCP"
input int    VCPSwingLen  = 5;   // Swing lookback
input int    VCPContracts = 3;   // Contrações mínimas (2-4)
input int    VCPAtrLen    = 14;  // ATR período
input int    VCPAtrSmooth = 5;   // ATR suavização
input int    VCPVolLen    = 20;  // Volume médio (períodos)
input double VCPVolThresh = 0.8; // Volume seco (% média)

// ── Breakout ──────────────────────────────────────────────────
input group              "Breakout"
input double BrkVolMult  = 1.4; // Volume mínimo (x média)
input double BrkBodyMult = 0.3; // Corpo mínimo (x ATR)

// ── Stop e Alvo ───────────────────────────────────────────────
input group              "Stop e Alvo"
input double RRRatio  = 2.5; // Risco/Retorno (R)
input double SLOffset = 0.1; // Stop offset (%)

// ── Gestão de Capital ─────────────────────────────────────────
input group              "Gestão de Capital"
input double RiskPct      = 1.0; // Risco por trade (%)
input int    MaxPositions = 1;   // Máximo de posições abertas

// ── Sessão ────────────────────────────────────────────────────
input group              "Sessão"
input bool UseSession  = true;  // Filtrar por sessão
input int  LondonStart = 7;     // Londres início (hora UTC)
input int  LondonEnd   = 16;    // Londres fim (hora UTC)
input int  NYStart     = 12;    // Nova York início (hora UTC)
input int  NYEnd       = 21;    // Nova York fim (hora UTC)
input bool CloseEOD    = false; // Fechar posições fora da sessão

// ── Operações ─────────────────────────────────────────────────
input group              "Operações"
input ENUM_TRADE_DIR TradeDir = DIR_BOTH; // Direção

input int MagicNumber = 77777; // Magic Number

//─────────────────────────────────────────────────────────────
CTrade trade;

int handleMA50, handleMA150, handleMA200, handleATR;

// Histórico de swing highs/lows — índice 0 = mais recente (espelho do PineScript)
double shArr[4];
double slArr[4];

datetime lastBarTime    = 0;
datetime lastPivotHTime = 0; // evita push duplo no mesmo pivot
datetime lastPivotLTime = 0;

//─────────────────────────────────────────────────────────────
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(100);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    handleMA50  = iMA(_Symbol, _Period, MA50Len,  0, MODE_EMA, PRICE_CLOSE);
    handleMA150 = iMA(_Symbol, _Period, MA150Len, 0, MODE_EMA, PRICE_CLOSE);
    handleMA200 = iMA(_Symbol, _Period, MA200Len, 0, MODE_EMA, PRICE_CLOSE);
    handleATR   = iATR(_Symbol, _Period, VCPAtrLen);

    if (handleMA50 < 0 || handleMA150 < 0 || handleMA200 < 0 || handleATR < 0)
    {
        Alert("Erro ao criar handles dos indicadores: ", GetLastError());
        return INIT_FAILED;
    }

    ArrayInitialize(shArr, EMPTY_VALUE);
    ArrayInitialize(slArr, EMPTY_VALUE);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    IndicatorRelease(handleMA50);
    IndicatorRelease(handleMA150);
    IndicatorRelease(handleMA200);
    IndicatorRelease(handleATR);
}

//─────────────────────────────────────────────────────────────
bool InSession()
{
    if (!UseSession) return true;
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int h = dt.hour;
    return (h >= LondonStart && h < LondonEnd) || (h >= NYStart && h < NYEnd);
}

int CountPositions()
{
    int n = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if (PositionSelectByTicket(t) &&
            PositionGetString(POSITION_SYMBOL)       == _Symbol &&
            (long)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            n++;
    }
    return n;
}

void CloseAllPositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong t = PositionGetTicket(i);
        if (PositionSelectByTicket(t) &&
            PositionGetString(POSITION_SYMBOL)       == _Symbol &&
            (long)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            trade.PositionClose(t);
    }
}

// Pivot high: hi[idx] é o maior em [idx-len .. idx+len]
// Arrays em série: índice 0 = candle atual, índices maiores = candles mais antigos
bool IsPivotHigh(const double &hi[], int idx, int len)
{
    if (idx < len || idx + len >= ArraySize(hi)) return false;
    double v = hi[idx];
    if (v <= 0) return false;
    for (int j = idx - len; j <= idx + len; j++)
    {
        if (j == idx) continue;
        if (hi[j] >= v) return false;
    }
    return true;
}

bool IsPivotLow(const double &lo[], int idx, int len)
{
    if (idx < len || idx + len >= ArraySize(lo)) return false;
    double v = lo[idx];
    if (v <= 0) return false;
    for (int j = idx - len; j <= idx + len; j++)
    {
        if (j == idx) continue;
        if (lo[j] <= v) return false;
    }
    return true;
}

// array.unshift equivalente — insere na frente, descarta o último
void PushHigh(double v) { for (int i = 3; i > 0; i--) shArr[i] = shArr[i-1]; shArr[0] = v; }
void PushLow (double v) { for (int i = 3; i > 0; i--) slArr[i] = slArr[i-1]; slArr[0] = v; }

// Position sizing por risco % (mesma fórmula do PineScript)
double CalcLot(double entry, double stop)
{
    double riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPct / 100.0;
    double dist    = MathAbs(entry - stop);
    if (dist <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double tv  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double ts  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lot = riskAmt / (dist / ts * tv);

    // cap em 20% do equity — proteção contra stop muito pequeno
    double cap = AccountInfoDouble(ACCOUNT_EQUITY) * 0.20 / (entry > 0 ? entry : 1.0);
    lot = MathMin(lot, cap);
    lot = MathMax(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lot = MathFloor(lot / step) * step;
    return NormalizeDouble(lot, 2);
}

//─────────────────────────────────────────────────────────────
void OnTick()
{
    // ── Fecha fora de sessão (todo tick) ─────────────────────
    if (CloseEOD && !InSession() && CountPositions() > 0)
    {
        CloseAllPositions();
        return;
    }

    // ── Processa apenas no início de cada candle novo ─────────
    datetime bt[1];
    if (CopyTime(_Symbol, _Period, 0, 1, bt) < 1) return;
    if (bt[0] == lastBarTime) return;
    lastBarTime = bt[0];

    // ── Calcula tamanhos de cópia necessários ─────────────────
    //
    // Para detecção de pivot: precisamos de índices 0 .. (1+VCPSwingLen)+VCPSwingLen
    //   pivIdx = 1 + VCPSwingLen  (PineScript bar[vcpSwingLen] → série MQ5 [1+len])
    //   lado esquerdo mais antigo: pivIdx + VCPSwingLen
    //
    int pivIdx  = 1 + VCPSwingLen;
    int copyLen = pivIdx + VCPSwingLen + MathMax(VCPAtrSmooth, VCPVolLen) + 5;

    double hiArr[], loArr[], clArr[], opArr[];
    long   vArr[];
    ArraySetAsSeries(hiArr, true); ArraySetAsSeries(loArr, true);
    ArraySetAsSeries(clArr, true); ArraySetAsSeries(opArr, true);
    ArraySetAsSeries(vArr,  true);

    if (CopyHigh       (_Symbol, _Period, 0, copyLen, hiArr) < copyLen) return;
    if (CopyLow        (_Symbol, _Period, 0, copyLen, loArr) < copyLen) return;
    if (CopyClose      (_Symbol, _Period, 0, copyLen, clArr) < copyLen) return;
    if (CopyOpen       (_Symbol, _Period, 0, copyLen, opArr) < copyLen) return;
    if (CopyTickVolume (_Symbol, _Period, 0, copyLen, vArr)  < copyLen) return;

    int maCopyLen  = MA200SlopeLen + 5;
    int atrCopyLen = VCPAtrSmooth  + 5;
    double ma50Buf[], ma150Buf[], ma200Buf[], atrBuf[];
    ArraySetAsSeries(ma50Buf, true); ArraySetAsSeries(ma150Buf, true);
    ArraySetAsSeries(ma200Buf, true); ArraySetAsSeries(atrBuf,  true);

    if (CopyBuffer(handleMA50,  0, 0, maCopyLen,  ma50Buf)  < maCopyLen)  return;
    if (CopyBuffer(handleMA150, 0, 0, maCopyLen,  ma150Buf) < maCopyLen)  return;
    if (CopyBuffer(handleMA200, 0, 0, maCopyLen,  ma200Buf) < maCopyLen)  return;
    if (CopyBuffer(handleATR,   0, 0, atrCopyLen, atrBuf)   < atrCopyLen) return;

    // ── Detecção de pivot high/low ────────────────────────────
    //
    // Mesmo comportamento do ta.pivothigh/pivotlow do Pine:
    //   confirma o pivot em bar[vcpSwingLen] somente após vcpSwingLen candles à direita
    //   pivIdx = 1 + VCPSwingLen → corresponde ao PineScript bar[vcpSwingLen]
    //
    datetime pivTimes[];
    ArraySetAsSeries(pivTimes, true);
    if (CopyTime(_Symbol, _Period, 0, pivIdx + 2, pivTimes) >= pivIdx + 1)
    {
        datetime pt = pivTimes[pivIdx];

        if (IsPivotHigh(hiArr, pivIdx, VCPSwingLen) && pt != lastPivotHTime)
        {
            PushHigh(hiArr[pivIdx]);
            lastPivotHTime = pt;
        }
        if (IsPivotLow(loArr, pivIdx, VCPSwingLen) && pt != lastPivotLTime)
        {
            PushLow(loArr[pivIdx]);
            lastPivotLTime = pt;
        }
    }

    // ── Trend Template (SEPA / Minervini) ────────────────────
    double ma50  = ma50Buf[1];
    double ma150 = ma150Buf[1];
    double ma200 = ma200Buf[1];
    double ma200Old = (ArraySize(ma200Buf) > 1 + MA200SlopeLen)
                      ? ma200Buf[1 + MA200SlopeLen] : ma200;
    double cl = clArr[1];

    bool ma200Up = ma200 > ma200Old;
    bool ma200Dn = ma200 < ma200Old;

    int sBull = (cl > ma50  ? 1:0) + (cl  > ma150 ? 1:0) + (cl  > ma200 ? 1:0)
              + (ma50 > ma150? 1:0) + (ma150 > ma200? 1:0) + (ma200Up    ? 1:0);
    int sBear = (cl < ma50  ? 1:0) + (cl  < ma150 ? 1:0) + (cl  < ma200 ? 1:0)
              + (ma50 < ma150? 1:0) + (ma150 < ma200? 1:0) + (ma200Dn    ? 1:0);

    bool tLong  = sBull >= TTMinScore;
    bool tShort = sBear >= TTMinScore;
    bool aLong  = tLong  && (TradeDir == DIR_BOTH || TradeDir == DIR_LONG);
    bool aShort = tShort && (TradeDir == DIR_BOTH || TradeDir == DIR_SHORT);

    // ── Volume médio e ATR suavizado ─────────────────────────
    double vSum = 0; for (int k = 1; k <= VCPVolLen;    k++) vSum += (double)vArr[k];
    double aSum = 0; for (int k = 1; k <= VCPAtrSmooth; k++) aSum += atrBuf[k];
    double vSma = vSum / VCPVolLen;
    double aSma = aSum / VCPAtrSmooth;
    double aCur = atrBuf[1];

    bool vDry  = (double)vArr[1] < vSma * VCPVolThresh;
    bool aContr = aCur < aSma;

    // ── VCP — contrações de range ─────────────────────────────
    //
    // r1 = range mais recente, r4 = mais antigo
    // c2: r1 < r2 ; c3: r1 < r2 < r3 ; c4: r1 < r2 < r3 < r4
    //
    double pH = shArr[0], pL = slArr[0];

    double r1 = (shArr[0]!=EMPTY_VALUE && slArr[0]!=EMPTY_VALUE) ? MathAbs(shArr[0]-slArr[0]) : -1.0;
    double r2 = (shArr[1]!=EMPTY_VALUE && slArr[1]!=EMPTY_VALUE) ? MathAbs(shArr[1]-slArr[1]) : -1.0;
    double r3 = (shArr[2]!=EMPTY_VALUE && slArr[2]!=EMPTY_VALUE) ? MathAbs(shArr[2]-slArr[2]) : -1.0;
    double r4 = (shArr[3]!=EMPTY_VALUE && slArr[3]!=EMPTY_VALUE) ? MathAbs(shArr[3]-slArr[3]) : -1.0;

    bool c2 = r1 > 0 && r2 > 0 && r1 < r2;
    bool c3 = c2 && r3 > 0 && r2 < r3;
    bool c4 = c3 && r4 > 0 && r3 < r4;

    bool vcp    = (VCPContracts <= 2) ? c2 : (VCPContracts == 3) ? c3 : c4;
    bool vcpAct = vcp && vDry && aContr;

    // ── Breakout ─────────────────────────────────────────────
    double body = MathAbs(clArr[1] - opArr[1]);
    bool vExp   = (double)vArr[1] > vSma * BrkVolMult;
    bool bOk    = body >= aCur * BrkBodyMult;

    bool bLong  = pH != EMPTY_VALUE && clArr[1] > pH && clArr[1] > opArr[1] && vExp && bOk && vcp;
    bool bShort = pL != EMPTY_VALUE && clArr[1] < pL && clArr[1] < opArr[1] && vExp && bOk && vcp;

    // ── Stop, Alvo e Lote ────────────────────────────────────
    double sL = pL != EMPTY_VALUE ? pL * (1.0 - SLOffset / 100.0) : -1.0;
    double sS = pH != EMPTY_VALUE ? pH * (1.0 + SLOffset / 100.0) : -1.0;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double rL  = sL > 0 ? MathAbs(ask - sL) : -1.0;
    double rS  = sS > 0 ? MathAbs(bid - sS) : -1.0;
    double tpL = rL > 0 ? ask + rL * RRRatio : -1.0;
    double tpS = rS > 0 ? bid - rS * RRRatio : -1.0;

    bool inSess = InSession();
    bool canOp  = CountPositions() < MaxPositions;

    bool doL = bLong  && aLong  && inSess && canOp && sL > 0 && tpL > 0;
    bool doS = bShort && aShort && inSess && canOp && sS > 0 && tpS > 0;

    // ── Execução ─────────────────────────────────────────────
    if (doL)
    {
        double qty = CalcLot(ask, sL);
        string cmt = StringFormat("VCP BUY | SL:%.5f | TP:%.5f | RR %.1fR", sL, tpL, RRRatio);
        if (trade.Buy(qty, _Symbol, ask,
                      NormalizeDouble(sL,  _Digits),
                      NormalizeDouble(tpL, _Digits), cmt))
            PrintFormat("[VCP] Long aberto: entrada=%.5f  sl=%.5f  tp=%.5f  lote=%.2f", ask, sL, tpL, qty);
        else
            PrintFormat("[VCP] Erro ao abrir Long: %d", GetLastError());
    }
    else if (doS)
    {
        double qty = CalcLot(bid, sS);
        string cmt = StringFormat("VCP SELL | SL:%.5f | TP:%.5f | RR %.1fR", sS, tpS, RRRatio);
        if (trade.Sell(qty, _Symbol, bid,
                       NormalizeDouble(sS,  _Digits),
                       NormalizeDouble(tpS, _Digits), cmt))
            PrintFormat("[VCP] Short aberto: entrada=%.5f  sl=%.5f  tp=%.5f  lote=%.2f", bid, sS, tpS, qty);
        else
            PrintFormat("[VCP] Erro ao abrir Short: %d", GetLastError());
    }
}

//─────────────────────────────────────────────────────────────
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    if (trans.symbol != _Symbol) return;

    if (!HistorySelect(TimeCurrent() - 2 * 86400, TimeCurrent())) return;

    int n = HistoryDealsTotal();
    if (n <= 0) return;

    ulong deal = HistoryDealGetTicket(n - 1);
    if (HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

    double pnl = HistoryDealGetDouble(deal, DEAL_PROFIT)
               + HistoryDealGetDouble(deal, DEAL_COMMISSION)
               + HistoryDealGetDouble(deal, DEAL_SWAP);

    PrintFormat("[VCP] Trade fechado: %.2f (%s)", pnl, pnl >= 0.0 ? "lucro" : "prejuízo");
}
//+------------------------------------------------------------------+
