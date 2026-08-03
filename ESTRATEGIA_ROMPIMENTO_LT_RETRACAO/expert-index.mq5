//+------------------------------------------------------------------+
//| expert-index.mq5                                                  |
//| EA: Rompimento de Estrutura (LT via ZigZag) + Entrada na Retracao |
//| de 50% do movimento que causou o rompimento.                     |
//| Especificacao completa: ESTRATEGIA_ROMPIMENTO_LT_RETRACAO.md      |
//| (mesma pasta).                                                    |
//|                                                                    |
//| Maquina de estados por simbolo/timeframe (uma posicao/pendente    |
//| por vez, controlada por magic+simbolo):                          |
//|   SETUP_IDLE            -> procura rompimento confirmado (candle  |
//|                            fecha alem do ultimo topo/fundo do     |
//|                            ZigZag + margem de 0.2xATR).           |
//|   SETUP_WAIT_MOVE_END    -> aguarda o ZigZag confirmar um novo    |
//|                            pivo na direcao do rompimento (fim do  |
//|                            movimento / alvo).                    |
//|   SETUP_PENDING_ARMED    -> ordem pendente (Buy/Sell Limit) ativa |
//|                            no nivel de retracao, com SL na origem |
//|                            do movimento e TP no fim do movimento. |
//|                                                                    |
//| Testado inicialmente para EURUSD, timeframe H1 -- mas o codigo eh |
//| generico (usa _Symbol/_Period do grafico onde o EA for anexado).  |
//|                                                                    |
//| ATENCAO: este EA envia ordens REAIS quando anexado ao grafico.    |
//| Revise o codigo e teste em conta demo / Strategy Tester antes de  |
//| usar em conta real.                                                |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      ""
#property version   "1.00"
#property strict
#include <Trade/Trade.mqh>

//============================== ENUMS ===============================

enum ENUM_RISK_MODE
  {
   RISK_FIXED_MONEY,      // Risco fixo em dinheiro por operacao
   RISK_PERCENT_BALANCE   // Risco percentual do saldo por operacao
  };

enum ENUM_SETUP_STATE
  {
   SETUP_IDLE,           // procurando rompimento de estrutura
   SETUP_WAIT_MOVE_END,  // rompimento confirmado, aguardando fim do movimento
   SETUP_PENDING_ARMED   // pendente enviada, aguardando preenchimento/invalidacao/expiracao
  };

//============================== STRUCT ===============================

struct PivotPoint
  {
   double   value;
   datetime time;
   bool     isHigh;
  };

//============================== INPUTS ===============================

input long   InpMagicNumber       = 20260729;  // Magic Number
input int    InpSlippagePoints    = 30;        // Slippage maximo (pontos)

input string Inp_Sep1              = "--- Estrutura (ZigZag) ---"; // ---
input int    InpZigZagDepth        = 12;       // Depth do ZigZag
input int    InpZigZagDeviation    = 5;        // Deviation do ZigZag
input int    InpZigZagBackstep     = 3;        // Backstep do ZigZag
input int    InpZigZagLookbackBars = 300;      // Barras usadas para ler a estrutura

input string Inp_Sep2              = "--- Tolerancia de rompimento ---"; // ---
input int    InpATRPeriod              = 14;   // Periodo do ATR
input double InpATRToleranceMultiplier = 0.2;  // Margem minima de rompimento (multiplos de ATR)

input string Inp_Sep3              = "--- Entrada / geometria do movimento ---"; // ---
input double InpRetracementPercent = 0.5;      // Percentual de retracao para a entrada (0.5 = 50%, 0.236 = 23.6%...)
input double InpStopLossPercent    = 0.0;      // Percentual do movimento para o stop (0.0 = origem do movimento)
input double InpTakeProfitPercent  = 1.0;      // Percentual do movimento para o alvo (1.0 = fim do movimento, 1.618 = extensao)
input int    InpMaxCandlesSetup    = 20;        // Candles apos o rompimento para expirar o setup (0 = desliga)

input string Inp_Sep4              = "--- Risco por operacao ---"; // ---
input ENUM_RISK_MODE InpRiskMode  = RISK_PERCENT_BALANCE; // Risk Mode
input double InpRiskPercent      = 1.0;        // Risk Percent (% do saldo)
input double InpFixedRiskMoney   = 50.0;       // Fixed Risk Money

input string Inp_Sep5              = "--- Spread ---"; // ---
input double InpMaxSpreadPoints  = 30.0;       // Spread maximo permitido (pontos)

input string Inp_Sep6              = "--- Gerenciamento diario ---"; // ---
input double InpDailyTargetPercent      = 6.0;  // Meta diaria (% do saldo do inicio do dia)
input bool   InpCloseOpenOnDailyTarget  = false; // Fechar posicoes abertas ao bater meta
input double InpDailyLossPercent        = 3.0;  // Stop diario (% do saldo do inicio do dia)
input bool   InpCloseOpenOnDailyLoss    = true; // Fechar posicoes abertas ao bater stop diario
input int    InpMaxTradesPerDay         = 3;    // Max Trades Per Day (0 = ilimitado)
input int    InpMaxConsecLossesPerDay   = 0;    // Max Consecutive Losses Per Day (0 = desliga)

input string Inp_Sep7              = "--- Horario operacional (sessoes) ---"; // ---
input bool   UsarAsia       = true;      // Operar sessao asiatica
input string AsiaInicio     = "00:00";   // Hora inicial Asia
input string AsiaFim        = "03:00";   // Hora final Asia
input bool   UsarLondres    = true;      // Operar sessao Londres
input string LondresInicio  = "08:00";   // Hora inicial Londres
input string LondresFim     = "11:00";   // Hora final Londres
input bool   UsarNovaYork   = true;      // Operar sessao Nova York
input string NovaYorkInicio = "14:00";   // Hora inicial Nova York
input string NovaYorkFim    = "17:00";   // Hora final Nova York
input int    MaxCandlesInicioSessao = 0; // 0 desliga, >0 limita aos primeiros candles da sessao

input string Inp_Sep8              = "--- Log / Export ---"; // ---
input bool   InpExportCSV  = true;   // Exportar trades para CSV
input bool   InpVerboseLog = true;   // Log detalhado no Experts

input string Inp_Sep9              = "--- Visualizacao ---"; // ---
input bool   InpShowChartObjects = true; // desenha a LT rompida e o fibo do movimento no grafico

//============================== GLOBALS ===============================

CTrade trade;

int g_zigzagHandle = INVALID_HANDLE;
int g_atrHandle    = INVALID_HANDLE;

ENUM_SETUP_STATE g_state = SETUP_IDLE;
int      g_direction        = 0;   // 1 = compra (LTB rompida p/ cima), -1 = venda (LTA rompida p/ baixo)
double   g_moveStart         = 0.0; // origem do movimento (stop)
datetime g_moveStartTime     = 0;
double   g_moveEnd           = 0.0; // fim do movimento (alvo), definido apos confirmacao
datetime g_moveEndTime       = 0;
double   g_breakLevel        = 0.0; // nivel do topo/fundo estrutural rompido (diagnostico)
datetime g_breakoutBarTime   = 0;   // vela que confirmou o rompimento (base p/ expiracao)
ulong    g_pendingTicket     = 0;   // ticket da pendente ativa (0 = nenhuma)

// estado do dia corrente
datetime g_currentDay        = 0;
double   g_dayStartBalance   = 0.0;
double   g_dailyTargetMoney  = 0.0;
double   g_dailyLossMoney    = 0.0;
double   g_dayProfit         = 0.0;
int      g_dayTradesCount    = 0;
int      g_dayConsecLosses   = 0;
bool     g_dailyTargetReached = false;
bool     g_dailyLossReached   = false;

string   g_lastCloseReason   = ""; // motivo de fechamento manual a ser consumido pelo OnTradeTransaction

// estatisticas agregadas de todo o teste/sessao
int      g_totalTradesOpened = 0;
int      g_totalTradesClosed = 0;
int      g_totalWins         = 0;
int      g_totalLosses       = 0;
double   g_grossProfit       = 0.0;
double   g_grossLoss         = 0.0;
double   g_totalProfit       = 0.0;

int      g_totalDaysTraded   = 0;
int      g_positiveDays      = 0;
int      g_negativeDays      = 0;
double   g_sumPositiveDaily  = 0.0;
double   g_sumNegativeDaily  = 0.0;
double   g_maxDailyProfit    = 0.0;
double   g_maxDailyLoss      = 0.0;

int      g_maxConsecLossesEver       = 0;
int      g_currentConsecNegativeDays = 0;
int      g_maxConsecNegativeDays     = 0;

double   g_equityPeak  = 0.0;
double   g_maxDrawdown = 0.0;

int      g_csvHandle = INVALID_HANDLE;

//============================== SESSAO / HORARIO ===============================

bool ParseTimeToMinutes(const string time_text, int &minutes_total)
{
   datetime parsed = StringToTime("2000.01.01 " + time_text);
   if (parsed == 0)
      return false;

   MqlDateTime ts;
   TimeToStruct(parsed, ts);
   minutes_total = ts.hour * 60 + ts.min;
   return true;
}

bool IsWithinMinutesRange(const int now_minutes, const int start_minutes, const int end_minutes)
{
   if (start_minutes == end_minutes)
      return true;
   if (start_minutes < end_minutes)
      return (now_minutes >= start_minutes && now_minutes <= end_minutes);
   return (now_minutes >= start_minutes || now_minutes <= end_minutes);
}

int GetSessionElapsedCandles(const int now_minutes, const int start_minutes)
{
   int minutes_since_start = now_minutes - start_minutes;
   if (minutes_since_start < 0)
      minutes_since_start += 24 * 60;

   int period_seconds = PeriodSeconds(_Period);
   if (period_seconds <= 0)
      return 0;

   int period_minutes = MathMax(1, period_seconds / 60);
   return (minutes_since_start / period_minutes) + 1;
}

bool IsSessionActive(const bool enabled, const string start_text, const string end_text,
                     const int now_minutes, bool &inside_window, int &elapsed_candles)
{
   inside_window = false;
   elapsed_candles = 0;

   if (!enabled)
      return false;

   int start_minutes = 0;
   int end_minutes = 0;
   if (!ParseTimeToMinutes(start_text, start_minutes) || !ParseTimeToMinutes(end_text, end_minutes))
      return false;

   inside_window = IsWithinMinutesRange(now_minutes, start_minutes, end_minutes);
   if (!inside_window)
      return false;

   elapsed_candles = GetSessionElapsedCandles(now_minutes, start_minutes);
   if (MaxCandlesInicioSessao > 0 && elapsed_candles > MaxCandlesInicioSessao)
      return false;

   return true;
}

bool IsWithinTradingWindow()
{
   MqlDateTime now_struct;
   TimeToStruct(TimeCurrent(), now_struct);
   int now_minutes = now_struct.hour * 60 + now_struct.min;

   bool inside_window = false;
   int elapsed_candles = 0;
   if (IsSessionActive(UsarAsia, AsiaInicio, AsiaFim, now_minutes, inside_window, elapsed_candles))
      return true;
   if (IsSessionActive(UsarLondres, LondresInicio, LondresFim, now_minutes, inside_window, elapsed_candles))
      return true;
   if (IsSessionActive(UsarNovaYork, NovaYorkInicio, NovaYorkFim, now_minutes, inside_window, elapsed_candles))
      return true;

   return false;
}

//============================== RISCO / LOTE ===============================

bool SpreadOk()
{
   double spread_points = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread_points <= InpMaxSpreadPoints);
}

double CalcRiskMoney(const double balance_ref)
{
   if (InpRiskMode == RISK_FIXED_MONEY)
      return InpFixedRiskMoney;
   return balance_ref * InpRiskPercent / 100.0;
}

double NormalizeLot(double lot)
{
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (lot_step <= 0.0)
      lot_step = 0.01;

   lot = MathFloor(lot / lot_step) * lot_step;
   if (lot < min_lot) lot = min_lot;
   if (lot > max_lot) lot = max_lot;
   return NormalizeDouble(lot, 2);
}

// sl_points: distancia do stop em pontos (derivada da geometria do movimento).
double CalculateLotSize(const double sl_points, double &risk_money_out)
{
   risk_money_out = CalcRiskMoney(AccountInfoDouble(ACCOUNT_BALANCE));

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (tick_value <= 0.0 || tick_size <= 0.0 || point <= 0.0 || sl_points <= 0.0)
      return 0.0;

   double sl_price_distance = sl_points * point;
   double loss_per_lot = (sl_price_distance / tick_size) * tick_value;
   if (loss_per_lot <= 0.0)
      return 0.0;

   return NormalizeLot(risk_money_out / loss_per_lot);
}

//============================== ESTRUTURA (ZIGZAG) ===============================

// Le os buffers do indicador ZigZag e retorna, em ordem cronologica (mais antigo
// primeiro), todos os pivos confirmados -- o ultimo pivo visual nunca e tratado
// como confirmado, pois ainda pode repintar.
int CollectConfirmedPivots(PivotPoint &pivots[])
{
   int bars_to_copy = MathMin(Bars(_Symbol, _Period), InpZigZagLookbackBars);
   if (bars_to_copy < 10)
      return 0;

   double zz[], hi[], lo[];
   datetime tm[];
   ArraySetAsSeries(zz, true);
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(tm, true);

   if (CopyBuffer(g_zigzagHandle, 0, 0, bars_to_copy, zz) <= 0) return 0;
   if (CopyBuffer(g_zigzagHandle, 1, 0, bars_to_copy, hi) <= 0) return 0;
   if (CopyBuffer(g_zigzagHandle, 2, 0, bars_to_copy, lo) <= 0) return 0;
   if (CopyTime(_Symbol, _Period, 0, bars_to_copy, tm) <= 0) return 0;

   ArrayResize(pivots, bars_to_copy);
   int count = 0;
   for (int i = bars_to_copy - 1; i >= 0; i--)
   {
      double zzv = zz[i];
      if (zzv == 0.0 || zzv == EMPTY_VALUE)
         continue;

      bool isHighPivot = (hi[i] != 0.0 && hi[i] != EMPTY_VALUE && MathAbs(zzv - hi[i]) <= _Point * 2.0);
      bool isLowPivot  = (lo[i] != 0.0 && lo[i] != EMPTY_VALUE && MathAbs(zzv - lo[i]) <= _Point * 2.0);
      if (!isHighPivot && !isLowPivot)
         continue;

      pivots[count].value  = zzv;
      pivots[count].time   = tm[i];
      pivots[count].isHigh = isHighPivot;
      count++;
   }

   // O ultimo pivo visual do ZigZag ainda pode repintar -- nao e tratado como confirmado.
   if (count > 0)
      count--;

   ArrayResize(pivots, count);
   return count;
}

bool GetLastPivotOfType(const PivotPoint &pivots[], const int count, const bool wantHigh,
                        double &value, datetime &time)
{
   for (int i = count - 1; i >= 0; i--)
   {
      if (pivots[i].isHigh == wantHigh)
      {
         value = pivots[i].value;
         time = pivots[i].time;
         return true;
      }
   }
   return false;
}

bool GetLastTwoPivotsOfType(const PivotPoint &pivots[], const int count, const bool wantHigh,
                            double &v1, datetime &t1, double &v2, datetime &t2)
{
   int found = 0;
   for (int i = count - 1; i >= 0 && found < 2; i--)
   {
      if (pivots[i].isHigh == wantHigh)
      {
         if (found == 0) { v1 = pivots[i].value; t1 = pivots[i].time; }
         else            { v2 = pivots[i].value; t2 = pivots[i].time; }
         found++;
      }
   }
   return (found == 2);
}

//============================== POSICOES / SETUP ===============================

bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }
   return false;
}

// Cancela a pendente ativa (se houver) e volta a maquina de estados para IDLE.
void CancelSetup(const string reason)
{
   if (g_pendingTicket != 0)
   {
      if (OrderSelect(g_pendingTicket))
      {
         if (!trade.OrderDelete(g_pendingTicket) && InpVerboseLog)
            PrintFormat("[CANCEL-FAIL] ticket=%I64u retcode=%d", g_pendingTicket, trade.ResultRetcode());
      }
      g_pendingTicket = 0;
   }

   if (InpVerboseLog)
      PrintFormat("[SETUP-CANCEL] motivo=%s direcao=%d moveStart=%.5f moveEnd=%.5f",
                  reason, g_direction, g_moveStart, g_moveEnd);

   g_state         = SETUP_IDLE;
   g_direction     = 0;
   g_moveStart     = 0.0;
   g_moveStartTime = 0;
   g_moveEnd       = 0.0;
   g_moveEndTime   = 0;
   g_breakLevel    = 0.0;
   g_breakoutBarTime = 0;
}

// Chamada a cada tick: detecta se a pendente foi preenchida (virou posicao) ou
// se sumiu por conta externa (ex.: expiracao no lado da corretora).
void ManageActiveSetup()
{
   if (g_pendingTicket == 0)
      return;

   if (HasOpenPosition())
   {
      if (InpVerboseLog)
         PrintFormat("[FILL] pendente preenchida ticket=%I64u", g_pendingTicket);
      g_pendingTicket = 0;
      g_dayTradesCount++;
      g_totalTradesOpened++;
      g_state = SETUP_IDLE;
      return;
   }

   if (!OrderSelect(g_pendingTicket))
   {
      if (InpVerboseLog)
         PrintFormat("[PENDING] ordem %I64u nao encontrada (cancelada/expirada externamente)", g_pendingTicket);
      g_pendingTicket = 0;
      g_state = SETUP_IDLE;
   }
}

bool CheckExpired()
{
   if (InpMaxCandlesSetup <= 0)
      return false;
   int barsElapsed = iBarShift(_Symbol, _Period, g_breakoutBarTime, false);
   if (barsElapsed < 0)
      return false;
   return (barsElapsed >= InpMaxCandlesSetup);
}

//============================== VISUALIZACAO ===============================
// Objetos de grafico opcionais (InpShowChartObjects) so para acompanhar
// visualmente o setup atual -- nao influenciam nenhuma decisao do EA.

void ClearChartObjects()
{
   ObjectDelete(0, "RLTR_LT");
   ObjectDelete(0, "RLTR_FIBO");
}

// Linha de tendencia entre os 2 pivos confirmados que definiram a estrutura
// rompida (o mesmo par usado em SearchForBreakout).
void DrawStructureLine(const double v1, const datetime t1, const double v2, const datetime t2)
{
   if (!InpShowChartObjects)
      return;

   string name = "RLTR_LT";
   ObjectDelete(0, name);
   if (!ObjectCreate(0, name, OBJ_TREND, 0, t1, v1, t2, v2))
      return;

   ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

// Monta, em ordem crescente e sem duplicatas, os niveis percentuais
// realmente usados pelo EA (0%, stop, entrada, 100%, alvo) para desenhar no
// Fibo -- assim o objeto no grafico mostra exatamente o que o EA calculou,
// nao uma tabela generica de razoes de Fibonacci.
void BuildFiboLevels(double &levels[])
{
   double raw[5] = { 0.0, InpStopLossPercent, InpRetracementPercent, 1.0, InpTakeProfitPercent };
   ArraySort(raw);

   ArrayResize(levels, 0);
   for (int i = 0; i < 5; i++)
   {
      bool dup = false;
      for (int j = 0; j < ArraySize(levels); j++)
         if (MathAbs(levels[j] - raw[i]) < 0.0001) { dup = true; break; }
      if (!dup)
      {
         int n = ArraySize(levels);
         ArrayResize(levels, n + 1);
         levels[n] = raw[i];
      }
   }
}

// Fibo do movimento (0% = g_moveStart, 100% = g_moveEnd), com os niveis de
// stop/entrada/alvo configurados marcados e rotulados.
void DrawMovementFibo()
{
   if (!InpShowChartObjects)
      return;

   string name = "RLTR_FIBO";
   ObjectDelete(0, name);
   if (!ObjectCreate(0, name, OBJ_FIBO, 0, g_moveStartTime, g_moveStart, g_moveEndTime, g_moveEnd))
      return;

   double levels[];
   BuildFiboLevels(levels);

   ObjectSetInteger(0, name, OBJPROP_LEVELS, ArraySize(levels));
   for (int i = 0; i < ArraySize(levels); i++)
   {
      ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, i, levels[i]);
      ObjectSetString(0, name, OBJPROP_LEVELTEXT, i, DoubleToString(levels[i] * 100.0, 1) + "%");
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

// Fase SETUP_IDLE: procura fechamento de candle alem do ultimo topo/fundo
// confirmado do ZigZag, com margem minima de InpATRToleranceMultiplier*ATR.
void SearchForBreakout()
{
   PivotPoint pivots[];
   int count = CollectConfirmedPivots(pivots);
   if (count < 2)
      return;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if (CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) <= 0)
      return;
   double atr = atrBuf[0];
   double margin = InpATRToleranceMultiplier * atr;

   double closeBar1 = iClose(_Symbol, _Period, 1);

   double lastHigh, prevHigh; datetime lastHighTime, prevHighTime;
   bool haveDescHighs = GetLastTwoPivotsOfType(pivots, count, true, lastHigh, lastHighTime, prevHigh, prevHighTime)
                        && lastHigh < prevHigh;

   if (haveDescHighs && closeBar1 > lastHigh + margin)
   {
      double moveStartV; datetime moveStartT;
      if (!GetLastPivotOfType(pivots, count, false, moveStartV, moveStartT))
         return; // precisa de ao menos um fundo confirmado como origem do movimento

      g_direction       = 1;
      g_moveStart       = moveStartV;
      g_moveStartTime   = moveStartT;
      g_breakLevel      = lastHigh;
      g_breakoutBarTime = iTime(_Symbol, _Period, 1);
      g_state           = SETUP_WAIT_MOVE_END;

      ClearChartObjects();
      DrawStructureLine(prevHigh, prevHighTime, lastHigh, lastHighTime);

      if (InpVerboseLog)
         PrintFormat("[BREAKOUT] COMPRA (LTB rompida p/ cima) nivel=%.5f moveStart=%.5f atr=%.5f",
                     lastHigh, g_moveStart, atr);
      return;
   }

   double lastLow, prevLow; datetime lastLowTime, prevLowTime;
   bool haveAscLows = GetLastTwoPivotsOfType(pivots, count, false, lastLow, lastLowTime, prevLow, prevLowTime)
                      && lastLow > prevLow;

   if (haveAscLows && closeBar1 < lastLow - margin)
   {
      double moveStartV; datetime moveStartT;
      if (!GetLastPivotOfType(pivots, count, true, moveStartV, moveStartT))
         return; // precisa de ao menos um topo confirmado como origem do movimento

      g_direction       = -1;
      g_moveStart       = moveStartV;
      g_moveStartTime   = moveStartT;
      g_breakLevel      = lastLow;
      g_breakoutBarTime = iTime(_Symbol, _Period, 1);
      g_state           = SETUP_WAIT_MOVE_END;

      ClearChartObjects();
      DrawStructureLine(prevLow, prevLowTime, lastLow, lastLowTime);

      if (InpVerboseLog)
         PrintFormat("[BREAKOUT] VENDA (LTA rompida p/ baixo) nivel=%.5f moveStart=%.5f atr=%.5f",
                     lastLow, g_moveStart, atr);
      return;
   }
}

// Fase SETUP_WAIT_MOVE_END: aguarda o ZigZag confirmar um novo pivo na direcao
// do rompimento (topo, se compra; fundo, se venda) apos a vela de rompimento.
void HandleWaitMoveEnd()
{
   if (CheckExpired())
   {
      CancelSetup("SETUP_EXPIRED_WAIT_MOVE_END");
      return;
   }

   PivotPoint pivots[];
   int count = CollectConfirmedPivots(pivots);
   if (count < 1)
      return;

   bool wantHigh = (g_direction == 1);
   double v; datetime t;
   if (!GetLastPivotOfType(pivots, count, wantHigh, v, t))
      return;
   if (t <= g_breakoutBarTime)
      return; // ainda nao ha pivo novo formado apos o rompimento

   g_moveEnd     = v;
   g_moveEndTime = t;

   DrawMovementFibo();

   if (InpVerboseLog)
      PrintFormat("[MOVE-END] direcao=%d moveEnd=%.5f moveEndTime=%s", g_direction, v, TimeToString(t));

   SendPendingOrder();
}

// Preco correspondente a um percentual do movimento (0.0 = origem/g_moveStart,
// 1.0 = fim do movimento/g_moveEnd). Aceita valores fora de [0,1] para permitir
// stop alem da origem ou alvo em extensao (ex.: 1.618).
double PriceAtLevel(const double percent)
{
   double range = MathAbs(g_moveEnd - g_moveStart);
   if (g_direction == 1)
      return g_moveStart + range * percent;
   return g_moveStart - range * percent;
}

// Envia a ordem pendente (Buy/Sell Limit) no nivel de retracao, com SL e TP
// tambem calculados como percentual do movimento (InpStopLossPercent /
// InpTakeProfitPercent). A invalidacao em HandlePendingArmed continua usando
// g_moveStart/g_moveEnd diretamente (0%/100% estruturais), nao estes niveis
// configuraveis -- ver nota no cabecalho de HandlePendingArmed.
void SendPendingOrder()
{
   double range = MathAbs(g_moveEnd - g_moveStart);
   if (range <= 0.0)
   {
      CancelSetup("INVALID_RANGE");
      return;
   }

   double entry = PriceAtLevel(InpRetracementPercent);
   double sl    = PriceAtLevel(InpStopLossPercent);
   double tp    = PriceAtLevel(InpTakeProfitPercent);

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl, _Digits);
   tp    = NormalizeDouble(tp, _Digits);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPoints = MathAbs(entry - sl) / point;

   double riskMoney = 0.0;
   double lot = CalculateLotSize(slPoints, riskMoney);
   if (lot <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] lote invalido, cancelando setup");
      CancelSetup("INVALID_LOT");
      return;
   }

   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   bool ok = false;
   if (g_direction == 1)
   {
      if (entry >= tick.ask)
      {
         if (InpVerboseLog) Print("[ENTRY-SKIP] preco ja passou do nivel de entrada (compra)");
         CancelSetup("ENTRY_ALREADY_PASSED");
         return;
      }
      ok = trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ROMPIMENTO_LT_RETRACAO");
   }
   else
   {
      if (entry <= tick.bid)
      {
         if (InpVerboseLog) Print("[ENTRY-SKIP] preco ja passou do nivel de entrada (venda)");
         CancelSetup("ENTRY_ALREADY_PASSED");
         return;
      }
      ok = trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ROMPIMENTO_LT_RETRACAO");
   }

   if (!ok)
   {
      PrintFormat("[ENTRY-FAIL] pendente nao enviada retcode=%d desc=%s",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      CancelSetup("ORDER_SEND_FAILED");
      return;
   }

   g_pendingTicket = trade.ResultOrder();
   g_state = SETUP_PENDING_ARMED;

   if (InpVerboseLog)
      PrintFormat("[PENDING] %s lot=%.2f entry=%.5f sl=%.5f tp=%.5f risco=%.2f",
                  (g_direction == 1 ? "BUY_LIMIT" : "SELL_LIMIT"), lot, entry, sl, tp, riskMoney);
}

// Fase SETUP_PENDING_ARMED: cancela a pendente se o preco romper o inicio do
// movimento (falso rompimento) ou retornar ao/alem do fim do movimento sem
// ter preenchido a entrada (retracao rasa demais -- ver secao 4 do .md).
// Propositalmente usa g_moveStart/g_moveEnd (0%/100% estruturais, os pivos
// confirmados de verdade) em vez de InpStopLossPercent/InpTakeProfitPercent:
// a invalidacao mede se a TESE do setup falhou (preco varreu toda a estrutura
// sem preencher a entrada), nao onde o usuario escolheu arriscar/realizar.
void HandlePendingArmed()
{
   if (CheckExpired())
   {
      CancelSetup("SETUP_EXPIRED_PENDING");
      return;
   }

   double closeBar1 = iClose(_Symbol, _Period, 1);

   if (g_direction == 1)
   {
      if (closeBar1 < g_moveStart) { CancelSetup("INVALIDATED_PAST_ORIGIN"); return; }
      if (closeBar1 > g_moveEnd)   { CancelSetup("INVALIDATED_RETURNED_TO_TARGET"); return; }
   }
   else
   {
      if (closeBar1 > g_moveStart) { CancelSetup("INVALIDATED_PAST_ORIGIN"); return; }
      if (closeBar1 < g_moveEnd)   { CancelSetup("INVALIDATED_RETURNED_TO_TARGET"); return; }
   }
}

bool CanOpenNewTrade(string &reason)
{
   if (g_dailyLossReached)   { reason = "DAILY_LOSS_LIMIT_REACHED"; return false; }
   if (g_dailyTargetReached) { reason = "DAILY_TARGET_REACHED";     return false; }
   if (InpMaxTradesPerDay > 0 && g_dayTradesCount >= InpMaxTradesPerDay)
      { reason = "MAX_TRADES_PER_DAY_REACHED"; return false; }
   if (InpMaxConsecLossesPerDay > 0 && g_dayConsecLosses >= InpMaxConsecLossesPerDay)
      { reason = "MAX_CONSEC_LOSSES_REACHED"; return false; }
   if (!SpreadOk())
      { reason = "SPREAD_TOO_HIGH"; return false; }
   return true;
}

void CloseAllPositions(const string reason)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      g_lastCloseReason = reason;
      if (!trade.PositionClose(ticket))
      {
         g_lastCloseReason = "";
         PrintFormat("[EXIT-FAIL] ticket=%I64u motivo=%s retcode=%d", ticket, reason, trade.ResultRetcode());
      }
   }
}

//============================== GESTAO DIARIA ===============================

void FinalizeDayStats(const double day_profit, const int day_trades)
{
   if (day_trades <= 0)
      return;

   g_totalDaysTraded++;

   if (day_profit > 0.0)
   {
      g_positiveDays++;
      g_sumPositiveDaily += day_profit;
      g_currentConsecNegativeDays = 0;
   }
   else if (day_profit < 0.0)
   {
      g_negativeDays++;
      g_sumNegativeDaily += day_profit;
      g_currentConsecNegativeDays++;
      if (g_currentConsecNegativeDays > g_maxConsecNegativeDays)
         g_maxConsecNegativeDays = g_currentConsecNegativeDays;
   }
   else
   {
      g_currentConsecNegativeDays = 0;
   }

   if (day_profit > g_maxDailyProfit) g_maxDailyProfit = day_profit;
   if (day_profit < g_maxDailyLoss)   g_maxDailyLoss = day_profit;
}

void RolloverDayIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);

   if (today == g_currentDay)
      return;

   if (g_currentDay != 0)
      FinalizeDayStats(g_dayProfit, g_dayTradesCount);

   g_currentDay        = today;
   g_dayStartBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyTargetMoney  = g_dayStartBalance * InpDailyTargetPercent / 100.0;
   g_dailyLossMoney    = g_dayStartBalance * InpDailyLossPercent / 100.0;
   g_dayProfit         = 0.0;
   g_dayTradesCount    = 0;
   g_dayConsecLosses   = 0;
   g_dailyTargetReached = false;
   g_dailyLossReached   = false;

   if (InpVerboseLog)
      PrintFormat("[DAY] Novo dia %s | meta=%.2f stop=%.2f",
                  TimeToString(g_currentDay, TIME_DATE), g_dailyTargetMoney, g_dailyLossMoney);
}

void CheckDailyLimitsAfterClose()
{
   if (!g_dailyTargetReached && g_dailyTargetMoney > 0.0 && g_dayProfit >= g_dailyTargetMoney)
   {
      g_dailyTargetReached = true;
      Print("[DAILY] DAILY_TARGET_REACHED dayProfit=", DoubleToString(g_dayProfit, 2));
      if (InpCloseOpenOnDailyTarget) CloseAllPositions("DAILY_TARGET_REACHED");
      if (g_pendingTicket != 0) CancelSetup("DAILY_TARGET_REACHED");
   }

   if (!g_dailyLossReached && g_dailyLossMoney > 0.0 && g_dayProfit <= -g_dailyLossMoney)
   {
      g_dailyLossReached = true;
      Print("[DAILY] DAILY_LOSS_LIMIT_REACHED dayProfit=", DoubleToString(g_dayProfit, 2));
      if (InpCloseOpenOnDailyLoss) CloseAllPositions("DAILY_LOSS_LIMIT_REACHED");
      if (g_pendingTicket != 0) CancelSetup("DAILY_LOSS_LIMIT_REACHED");
   }
}

void UpdateDrawdown()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if (eq > g_equityPeak)
      g_equityPeak = eq;

   double dd = g_equityPeak - eq;
   if (dd > g_maxDrawdown)
      g_maxDrawdown = dd;
}

bool IsNewBar()
{
   static datetime last_time = 0;
   datetime t[1];
   if (CopyTime(_Symbol, _Period, 0, 1, t) <= 0)
      return false;

   if (t[0] != last_time)
   {
      last_time = t[0];
      return true;
   }
   return false;
}

//============================== CSV / RELATORIO ===============================

void OpenCSV()
{
   if (!InpExportCSV)
      return;

   string filename = "ROMPIMENTO_LT_RETRACAO_" + _Symbol + "_" + IntegerToString((int)InpMagicNumber) + ".csv";
   g_csvHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if (g_csvHandle != INVALID_HANDLE)
      FileWrite(g_csvHandle, "datetime", "profit", "exit_reason", "day_profit", "day_trades");
   else if (InpVerboseLog)
      PrintFormat("[CSV] Falha ao abrir arquivo %s erro=%d", filename, GetLastError());
}

void ExportTradeRow(const datetime t, const double profit, const string reason)
{
   if (g_csvHandle == INVALID_HANDLE)
      return;

   FileWrite(g_csvHandle, TimeToString(t, TIME_DATE | TIME_SECONDS), DoubleToString(profit, 2), reason,
             DoubleToString(g_dayProfit, 2), IntegerToString(g_dayTradesCount));
   FileFlush(g_csvHandle);
}

void PrintFinalReport()
{
   FinalizeDayStats(g_dayProfit, g_dayTradesCount);

   double avg_positive = (g_positiveDays > 0) ? g_sumPositiveDaily / g_positiveDays : 0.0;
   double avg_negative = (g_negativeDays > 0) ? g_sumNegativeDaily / g_negativeDays : 0.0;
   double profit_factor = (g_grossLoss > 0.0) ? g_grossProfit / g_grossLoss : 0.0;
   double expectancy_trade = (g_totalTradesClosed > 0) ? g_totalProfit / g_totalTradesClosed : 0.0;
   double expectancy_day = (g_totalDaysTraded > 0) ? g_totalProfit / g_totalDaysTraded : 0.0;

   Print("================ RELATORIO FINAL ================");
   PrintFormat("Total de trades (abertos):           %d", g_totalTradesOpened);
   PrintFormat("Total de trades (fechados):          %d", g_totalTradesClosed);
   PrintFormat("Dias operados:                       %d", g_totalDaysTraded);
   PrintFormat("Dias positivos:                      %d", g_positiveDays);
   PrintFormat("Dias negativos:                      %d", g_negativeDays);
   PrintFormat("Lucro medio diario (dias positivos): %.2f", avg_positive);
   PrintFormat("Perda media diaria (dias negativos): %.2f", avg_negative);
   PrintFormat("Maior lucro diario:                  %.2f", g_maxDailyProfit);
   PrintFormat("Maior perda diaria:                  %.2f", g_maxDailyLoss);
   PrintFormat("Sequencia maxima de perdas (trades): %d", g_maxConsecLossesEver);
   PrintFormat("Sequencia maxima de dias negativos:  %d", g_maxConsecNegativeDays);
   PrintFormat("Profit Factor:                       %.2f", profit_factor);
   PrintFormat("Drawdown maximo (equity):            %.2f", g_maxDrawdown);
   PrintFormat("Expectativa por trade:               %.2f", expectancy_trade);
   PrintFormat("Expectativa por dia:                 %.2f", expectancy_day);
   Print("===================================================");
}

//============================== EVENTOS MT5 ===============================

int OnInit()
{
   g_zigzagHandle = iCustom(_Symbol, _Period, "Examples\\ZigZag", InpZigZagDepth, InpZigZagDeviation, InpZigZagBackstep);
   g_atrHandle    = iATR(_Symbol, _Period, InpATRPeriod);

   if (g_zigzagHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      Alert("Falha ao criar handles de indicadores - erro: ", GetLastError());
      return INIT_FAILED;
   }

   // Anexa no grafico o MESMO handle que o EA usa para calcular a estrutura,
   // assim o que aparece na tela sempre bate com Depth/Deviation/Backstep
   // realmente configurados (evita testar um ajuste manualmente enquanto o
   // EA roda com outro, como aconteceu antes).
   if (InpShowChartObjects)
      ChartIndicatorAdd(0, 0, g_zigzagHandle);

   if (InpStopLossPercent >= InpRetracementPercent)
   {
      Alert("InpStopLossPercent deve ser menor que InpRetracementPercent (stop tem que ficar antes da entrada).");
      return INIT_PARAMETERS_INCORRECT;
   }
   if (InpTakeProfitPercent <= InpRetracementPercent)
   {
      Alert("InpTakeProfitPercent deve ser maior que InpRetracementPercent (alvo tem que ficar depois da entrada).");
      return INIT_PARAMETERS_INCORRECT;
   }

   int parsedMinutes = 0;
   bool horariosValidos = true;
   if (UsarAsia)     horariosValidos = horariosValidos && ParseTimeToMinutes(AsiaInicio, parsedMinutes) && ParseTimeToMinutes(AsiaFim, parsedMinutes);
   if (UsarLondres)  horariosValidos = horariosValidos && ParseTimeToMinutes(LondresInicio, parsedMinutes) && ParseTimeToMinutes(LondresFim, parsedMinutes);
   if (UsarNovaYork) horariosValidos = horariosValidos && ParseTimeToMinutes(NovaYorkInicio, parsedMinutes) && ParseTimeToMinutes(NovaYorkFim, parsedMinutes);
   if (!horariosValidos)
   {
      Alert("Horario invalido. Use HH:MM para as sessoes configuradas.");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_state = SETUP_IDLE;
   g_pendingTicket = 0;
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   g_currentDay = 0;
   g_csvHandle = INVALID_HANDLE;
   OpenCSV();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_zigzagHandle != INVALID_HANDLE) IndicatorRelease(g_zigzagHandle);
   if (g_atrHandle != INVALID_HANDLE)    IndicatorRelease(g_atrHandle);

   PrintFinalReport();

   if (g_csvHandle != INVALID_HANDLE)
      FileClose(g_csvHandle);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &res)
{
   if (trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if (!HistoryDealSelect(trans.deal))
      return;

   long deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   if (deal_magic != InpMagicNumber || deal_symbol != _Symbol)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if (entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   long deal_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string exit_reason = g_lastCloseReason;
   if (exit_reason == "")
   {
      if (deal_reason == DEAL_REASON_SL)
         exit_reason = "STOP_LOSS";
      else if (deal_reason == DEAL_REASON_TP)
         exit_reason = "TAKE_PROFIT";
      else
         exit_reason = "UNKNOWN";
   }
   g_lastCloseReason = "";

   g_dayProfit += profit;
   g_totalProfit += profit;
   g_totalTradesClosed++;

   if (profit > 0.0)
   {
      g_totalWins++;
      g_grossProfit += profit;
      g_dayConsecLosses = 0;
   }
   else if (profit < 0.0)
   {
      g_totalLosses++;
      g_grossLoss += (-profit);
      g_dayConsecLosses++;
      if (g_dayConsecLosses > g_maxConsecLossesEver)
         g_maxConsecLossesEver = g_dayConsecLosses;
   }

   if (InpVerboseLog)
      PrintFormat("[EXIT] %s ticket=%I64u profit=%.2f motivo=%s dayProfit=%.2f",
                  _Symbol, trans.deal, profit, exit_reason, g_dayProfit);

   ExportTradeRow(TimeCurrent(), profit, exit_reason);

   CheckDailyLimitsAfterClose();
}

void OnTick()
{
   RolloverDayIfNeeded();
   UpdateDrawdown();

   ManageActiveSetup();

   if (!IsNewBar())
      return;

   if (Bars(_Symbol, _Period) < InpZigZagLookbackBars)
      return;

   switch (g_state)
   {
      case SETUP_IDLE:
      {
         if (HasOpenPosition())
            break;

         string blockReason = "";
         if (!CanOpenNewTrade(blockReason))
         {
            if (InpVerboseLog && blockReason != "")
               PrintFormat("[BLOCKED] motivo=%s", blockReason);
            break;
         }
         if (!IsWithinTradingWindow())
            break;

         SearchForBreakout();
         break;
      }
      case SETUP_WAIT_MOVE_END:
         HandleWaitMoveEnd();
         break;
      case SETUP_PENDING_ARMED:
         HandlePendingArmed();
         break;
   }
}
//+------------------------------------------------------------------+
