//+------------------------------------------------------------------+
//|                                   EstrategiaDojiPavioSuperior.mq5 |
//|  Porta de Inferior.pinescript (Doji - Pavio Superior/Inferior)   |
//|  para MT5, com gestao de risco por operacao e gestao de risco    |
//|  diaria (meta, stop, maximo de trades, sequencia de perdas,      |
//|  janela horaria). Arquitetura identica a zig-zag_rsi_adx_quant.  |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      ""
#property version   "1.00"
#property description "EA de Doji com pavio superior/inferior maior, stop estrutural (extremo do candle de sinal) e alvo = altura do doji x multiplicador."

//============================== ENUMS ===============================

enum ENUM_RISK_MODE
  {
   RISK_FIXED_MONEY,      // Risco fixo em dinheiro por operacao
   RISK_PERCENT_BALANCE   // Risco percentual do saldo por operacao
  };

enum ENUM_DAILY_LIMIT_MODE
  {
   LIMIT_R_MULTIPLE,    // Expresso em multiplos de R
   LIMIT_FIXED_MONEY    // Expresso em valor fixo de dinheiro
  };

//============================== INPUTS ===============================

input long   InpMagicNumber       = 20260715;  // Magic Number
input int    InpSlippagePoints    = 30;        // Slippage maximo (pontos)

input string Inp_Sep1              = "--- Sinal Doji ---"; // ---
input double InpDojiBodyPercent    = 20.0;     // Corpo maximo do Doji (% do range total)
input double InpTargetMultiplier   = 10.0;     // Multiplicador do alvo (x altura do Doji)
input bool   InpUseFixedStopTarget = false;    // Usar Stop Loss e Alvo fixos (em vez do stop estrutural)
input double InpFixedStopPoints    = 20.0;     // Stop Loss fixo (pontos), se InpUseFixedStopTarget
input double InpFixedTargetPoints  = 100.0;    // Alvo fixo (pontos), se InpUseFixedStopTarget

input string Inp_Sep2             = "--- Spread ---"; // ---
input double InpMaxSpreadPoints   = 30.0;      // Spread maximo permitido (pontos)

input string Inp_Sep3             = "--- Risco por operacao ---"; // ---
input ENUM_RISK_MODE InpRiskMode  = RISK_PERCENT_BALANCE; // Risk Mode
input double InpRiskPercent       = 0.5;       // Risk Percent (% do saldo)
input double InpFixedRiskMoney    = 50.0;      // Fixed Risk Money
input bool   InpUseMaxDurationExit = false;    // Usar saida por tempo maximo
input int    InpMaxTradeDurationMinutes = 60;  // Max Trade Duration (minutos)
input bool   InpUseOppositeSignalExit = false; // Usar saida por sinal contrario

input string Inp_Sep4             = "--- Gerenciamento diario ---"; // ---
input ENUM_DAILY_LIMIT_MODE InpDailyTargetMode = LIMIT_R_MULTIPLE; // Daily Target Mode
input double InpDailyTargetRMultiple = 1.0;    // Daily Profit Target (em R)
input double InpDailyTargetMoney  = 100.0;     // Daily Profit Target (dinheiro)
input bool   InpCloseOpenOnDailyTarget = false;// Fechar posicoes abertas ao bater meta

input ENUM_DAILY_LIMIT_MODE InpDailyLossMode = LIMIT_R_MULTIPLE; // Daily Loss Mode
input double InpDailyLossRMultiple = 2.0;      // Daily Loss Limit (em R)
input double InpDailyLossMoney    = 200.0;     // Daily Loss Limit (dinheiro)
input bool   InpCloseOpenOnDailyLoss = true;   // Fechar posicoes abertas ao bater stop diario

input int    InpMaxTradesPerDay   = 5;         // Max Trades Per Day (0 = ilimitado)
input int    InpMaxConsecLossesPerDay = 3;     // Max Consecutive Losses Per Day (0 = desliga)

input string Inp_Sep5              = "--- Sessoes de horario ---"; // ---
input bool   UsarSessao1           = true;      // Operar Sessao 1
input string Sessao1Inicio         = "00:00";   // Hora inicial Sessao 1
input string Sessao1Fim            = "03:00";   // Hora final Sessao 1
input bool   UsarSessao2           = true;      // Operar Sessao 2
input string Sessao2Inicio         = "08:00";   // Hora inicial Sessao 2
input string Sessao2Fim            = "11:00";   // Hora final Sessao 2
input bool   UsarSessao3           = true;      // Operar Sessao 3
input string Sessao3Inicio         = "14:00";   // Hora inicial Sessao 3
input string Sessao3Fim            = "17:00";   // Hora final Sessao 3
input int    MaxCandlesInicioSessao = 0;        // 0 desliga, >0 limita aos primeiros candles da sessao

input string Inp_Sep6             = "--- Log / Export ---"; // ---
input bool   InpExportCSV         = true;      // Exportar trades para CSV
input bool   InpVerboseLog        = true;      // Log detalhado no Experts

//============================== GLOBALS ===============================

// estado do dia corrente
datetime g_currentDay        = 0;
double   g_dayStartBalance   = 0.0;
double   g_dailyR            = 0.0;
double   g_dayProfit         = 0.0;
int      g_dayTradesCount    = 0;
int      g_dayConsecLosses   = 0;
bool     g_dailyTargetReached = false;
bool     g_dailyLossReached   = false;

int      g_lastSignal        = 0;     // 1 = buy, -1 = sell, 0 = none (calculado em cada nova barra)
double   g_lastStopPrice      = 0.0;   // low (buy) / high (sell) do candle de sinal
double   g_lastRangePoints    = 0.0;   // altura do doji em pontos, para o alvo
string   g_lastCloseReason   = "";    // motivo de fechamento manual a ser consumido pelo OnTradeTransaction

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

int      g_maxConsecLossesEver     = 0;
int      g_currentConsecNegativeDays = 0;
int      g_maxConsecNegativeDays   = 0;

double   g_equityPeak   = 0.0;
double   g_maxDrawdown  = 0.0;

int      g_csvHandle = INVALID_HANDLE;

//============================== UTILITARIOS ===============================

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

bool ParseTimeToMinutes(const string time_text, int &minutes_total)
{
   datetime parsed = StringToTime("2000.01.01 " + time_text);
   if (parsed == 0)
      return false;

   MqlDateTime time_struct;
   TimeToStruct(parsed, time_struct);
   minutes_total = time_struct.hour * 60 + time_struct.min;
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

bool IsSessionActive(const bool enabled,
                     const string start_text,
                     const string end_text,
                     const int now_minutes,
                     bool &inside_window,
                     int &elapsed_candles)
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
   if (IsSessionActive(UsarSessao1, Sessao1Inicio, Sessao1Fim, now_minutes, inside_window, elapsed_candles))
      return true;
   if (IsSessionActive(UsarSessao2, Sessao2Inicio, Sessao2Fim, now_minutes, inside_window, elapsed_candles))
      return true;
   if (IsSessionActive(UsarSessao3, Sessao3Inicio, Sessao3Fim, now_minutes, inside_window, elapsed_candles))
      return true;

   return false;
}

bool SpreadOk()
{
   double spread_points = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread_points <= InpMaxSpreadPoints);
}

ENUM_ORDER_TYPE_FILLING GetFillingType()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((filling & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;
   if ((filling & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
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
   if (lot < min_lot)
      lot = min_lot;
   if (lot > max_lot)
      lot = max_lot;
   return NormalizeDouble(lot, 2);
}

// sl_points e sempre a distancia REAL do stop (estrutural ou fixo), nunca
// um valor fixo desatualizado -- ver OpenBuy/OpenSell.
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

double GetDailyTargetMoney()
{
   return (InpDailyTargetMode == LIMIT_R_MULTIPLE) ? (InpDailyTargetRMultiple * g_dailyR) : InpDailyTargetMoney;
}

double GetDailyLossMoney()
{
   return (InpDailyLossMode == LIMIT_R_MULTIPLE) ? (InpDailyLossRMultiple * g_dailyR) : InpDailyLossMoney;
}

//============================== SINAL ===============================
// Portado de Inferior.pinescript: Doji = corpo <= range * InpDojiBodyPercent%.
// Pavio superior maior => compra, stop = minima do candle de sinal.
// Pavio inferior maior => venda, stop = maxima do candle de sinal.
// Alvo = altura do doji (range) x InpTargetMultiplier, a partir da entrada.
int GetSignal(double &out_stop_price, double &out_range_points)
{
   out_stop_price = 0.0;
   out_range_points = 0.0;

   double o1 = iOpen(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1);
   double l1 = iLow(_Symbol, _Period, 1);
   double c1 = iClose(_Symbol, _Period, 1);

   double totalRange = h1 - l1;
   if (totalRange <= 0.0)
      return 0;

   double bodySize = MathAbs(c1 - o1);
   bool isDoji = bodySize <= totalRange * (InpDojiBodyPercent / 100.0);
   if (!isDoji)
      return 0;

   double upperWick = h1 - MathMax(c1, o1);
   double lowerWick = MathMin(c1, o1) - l1;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (upperWick > lowerWick)
   {
      out_stop_price = l1;
      out_range_points = totalRange / point;
      return 1;
   }
   if (lowerWick > upperWick)
   {
      out_stop_price = h1;
      out_range_points = totalRange / point;
      return -1;
   }
   return 0;
}

//============================== POSICOES ===============================

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

void ClosePositionByTicket(const ulong ticket, const string reason)
{
   if (!PositionSelectByTicket(ticket))
      return;

   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   long type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action      = TRADE_ACTION_DEAL;
   req.position    = ticket;
   req.symbol      = _Symbol;
   req.volume      = volume;
   req.deviation   = InpSlippagePoints;
   req.magic       = InpMagicNumber;
   req.type_filling = GetFillingType();

   if (type == POSITION_TYPE_BUY)
   {
      req.type  = ORDER_TYPE_SELL;
      req.price = tick.bid;
   }
   else
   {
      req.type  = ORDER_TYPE_BUY;
      req.price = tick.ask;
   }

   g_lastCloseReason = reason;
   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      g_lastCloseReason = "";
      PrintFormat("[EXIT-FAIL] ticket=%I64u motivo=%s retcode=%d", ticket, reason, res.retcode);
   }
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
      ClosePositionByTicket(ticket, reason);
   }
}

void ManageOpenPosition(const bool check_opposite_signal)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      if (InpUseMaxDurationExit)
      {
         int minutesOpen = (int)((TimeCurrent() - openTime) / 60);
         if (minutesOpen >= InpMaxTradeDurationMinutes)
         {
            ClosePositionByTicket(ticket, "MAX_TRADE_DURATION");
            continue;
         }
      }

      if (check_opposite_signal && InpUseOppositeSignalExit)
      {
         if (posType == POSITION_TYPE_BUY && g_lastSignal == -1)
         {
            ClosePositionByTicket(ticket, "OPPOSITE_SIGNAL");
            continue;
         }
         if (posType == POSITION_TYPE_SELL && g_lastSignal == 1)
         {
            ClosePositionByTicket(ticket, "OPPOSITE_SIGNAL");
            continue;
         }
      }
   }
}

//============================== ENTRADAS ===============================

bool CanOpenNewTrade(string &reason)
{
   if (g_dailyLossReached)   { reason = "DAILY_LOSS_LIMIT_REACHED"; return false; }
   if (g_dailyTargetReached) { reason = "DAILY_TARGET_REACHED";     return false; }
   if (InpMaxTradesPerDay > 0 && g_dayTradesCount >= InpMaxTradesPerDay)
      { reason = "MAX_TRADES_PER_DAY_REACHED"; return false; }
   if (InpMaxConsecLossesPerDay > 0 && g_dayConsecLosses >= InpMaxConsecLossesPerDay)
      { reason = "MAX_CONSEC_LOSSES_REACHED"; return false; }
   if (!IsWithinTradingWindow())
      { reason = "OUTSIDE_TRADING_WINDOW"; return false; }
   if (!SpreadOk())
      { reason = "SPREAD_TOO_HIGH"; return false; }
   return true;
}

void OpenBuy(const double stop_price, const double range_points)
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double sl_points, tp_points;
   if (InpUseFixedStopTarget)
   {
      sl_points = InpFixedStopPoints;
      tp_points = InpFixedTargetPoints;
   }
   else
   {
      sl_points = (tick.ask - stop_price) / point;
      tp_points = range_points * InpTargetMultiplier;
   }

   if (sl_points <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] BUY: distancia de stop invalida (sl_points=", sl_points, ")");
      return;
   }

   double risk_money = 0.0;
   double lot = CalculateLotSize(sl_points, risk_money);
   if (lot <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] BUY: lote invalido");
      return;
   }

   double sl = NormalizeDouble(tick.ask - sl_points * point, _Digits);
   double tp = NormalizeDouble(tick.ask + tp_points * point, _Digits);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.type         = ORDER_TYPE_BUY;
   req.price        = tick.ask;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = InpSlippagePoints;
   req.magic        = InpMagicNumber;
   req.type_filling = GetFillingType();
   req.comment      = "DOJI_BUY";

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[ENTRY-FAIL] BUY retcode=%d", res.retcode);
      return;
   }

   g_dayTradesCount++;
   g_totalTradesOpened++;
   if (InpVerboseLog)
      PrintFormat("[ENTRY] DOJI_BUY lot=%.2f sl=%.5f tp=%.5f risco=%.2f", lot, sl, tp, risk_money);
}

void OpenSell(const double stop_price, const double range_points)
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double sl_points, tp_points;
   if (InpUseFixedStopTarget)
   {
      sl_points = InpFixedStopPoints;
      tp_points = InpFixedTargetPoints;
   }
   else
   {
      sl_points = (stop_price - tick.bid) / point;
      tp_points = range_points * InpTargetMultiplier;
   }

   if (sl_points <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] SELL: distancia de stop invalida (sl_points=", sl_points, ")");
      return;
   }

   double risk_money = 0.0;
   double lot = CalculateLotSize(sl_points, risk_money);
   if (lot <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] SELL: lote invalido");
      return;
   }

   double sl = NormalizeDouble(tick.bid + sl_points * point, _Digits);
   double tp = NormalizeDouble(tick.bid - tp_points * point, _Digits);

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.type         = ORDER_TYPE_SELL;
   req.price        = tick.bid;
   req.sl           = sl;
   req.tp           = tp;
   req.deviation    = InpSlippagePoints;
   req.magic        = InpMagicNumber;
   req.type_filling = GetFillingType();
   req.comment      = "DOJI_SELL";

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[ENTRY-FAIL] SELL retcode=%d", res.retcode);
      return;
   }

   g_dayTradesCount++;
   g_totalTradesOpened++;
   if (InpVerboseLog)
      PrintFormat("[ENTRY] DOJI_SELL lot=%.2f sl=%.5f tp=%.5f risco=%.2f", lot, sl, tp, risk_money);
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

   if (day_profit > g_maxDailyProfit)
      g_maxDailyProfit = day_profit;
   if (day_profit < g_maxDailyLoss)
      g_maxDailyLoss = day_profit;
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
   g_dailyR            = CalcRiskMoney(g_dayStartBalance);
   g_dayProfit         = 0.0;
   g_dayTradesCount     = 0;
   g_dayConsecLosses    = 0;
   g_dailyTargetReached = false;
   g_dailyLossReached   = false;

   if (InpVerboseLog)
      PrintFormat("[DAY] Novo dia %s | R diario=%.2f", TimeToString(g_currentDay, TIME_DATE), g_dailyR);
}

void CheckDailyLimitsAfterClose()
{
   double target = GetDailyTargetMoney();
   double loss_limit = GetDailyLossMoney();

   if (!g_dailyTargetReached && target > 0.0 && g_dayProfit >= target)
   {
      g_dailyTargetReached = true;
      Print("[DAILY] DAILY_TARGET_REACHED dayProfit=", DoubleToString(g_dayProfit, 2));
      if (InpCloseOpenOnDailyTarget)
         CloseAllPositions("DAILY_TARGET_REACHED");
   }

   if (!g_dailyLossReached && loss_limit > 0.0 && g_dayProfit <= -loss_limit)
   {
      g_dailyLossReached = true;
      Print("[DAILY] DAILY_LOSS_LIMIT_REACHED dayProfit=", DoubleToString(g_dayProfit, 2));
      if (InpCloseOpenOnDailyLoss)
         CloseAllPositions("DAILY_LOSS_LIMIT_REACHED");
   }
}

//============================== DRAWDOWN ===============================

void UpdateDrawdown()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if (eq > g_equityPeak)
      g_equityPeak = eq;

   double dd = g_equityPeak - eq;
   if (dd > g_maxDrawdown)
      g_maxDrawdown = dd;
}

//============================== CSV / RELATORIO ===============================

void OpenCSV()
{
   if (!InpExportCSV)
      return;

   string filename = "DojiPavio_" + _Symbol + "_" + IntegerToString((int)InpMagicNumber) + ".csv";
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
   int parsed_minutes = 0;
   bool horarios_validos = true;
   if (UsarSessao1)
      horarios_validos = horarios_validos && ParseTimeToMinutes(Sessao1Inicio, parsed_minutes) && ParseTimeToMinutes(Sessao1Fim, parsed_minutes);
   if (UsarSessao2)
      horarios_validos = horarios_validos && ParseTimeToMinutes(Sessao2Inicio, parsed_minutes) && ParseTimeToMinutes(Sessao2Fim, parsed_minutes);
   if (UsarSessao3)
      horarios_validos = horarios_validos && ParseTimeToMinutes(Sessao3Inicio, parsed_minutes) && ParseTimeToMinutes(Sessao3Fim, parsed_minutes);

   if (!horarios_validos)
   {
      Alert("Horario invalido. Use HH:MM para as sessoes configuradas.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_equityPeak  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_currentDay  = 0;
   g_csvHandle   = INVALID_HANDLE;
   OpenCSV();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
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
      PrintFormat("[EXIT] %s ticket=%I64u profit=%.2f motivo=%s dayProfit=%.2f", _Symbol, trans.deal, profit, exit_reason, g_dayProfit);

   ExportTradeRow(TimeCurrent(), profit, exit_reason);

   CheckDailyLimitsAfterClose();
}

void OnTick()
{
   RolloverDayIfNeeded();
   UpdateDrawdown();

   bool is_new_bar = IsNewBar();
   if (is_new_bar)
      g_lastSignal = GetSignal(g_lastStopPrice, g_lastRangePoints);

   ManageOpenPosition(is_new_bar);

   if (!is_new_bar)
      return;

   if (HasOpenPosition())
      return;

   string block_reason = "";
   if (!CanOpenNewTrade(block_reason))
   {
      if (InpVerboseLog && block_reason != "")
         PrintFormat("[BLOCKED] motivo=%s", block_reason);
      return;
   }

   if (g_lastSignal == 1)
      OpenBuy(g_lastStopPrice, g_lastRangePoints);
   else if (g_lastSignal == -1)
      OpenSell(g_lastStopPrice, g_lastRangePoints);
}
//+------------------------------------------------------------------+
