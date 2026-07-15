//+------------------------------------------------------------------+
//|                                   RANGE_BOLLINGER/expert-index.mq5|
//|  EA de reversao em mercado lateral: gatilho nos extremos das      |
//|  Bollinger Bands + zona de suporte/resistencia recente,           |
//|  confirmado por filtro duplo obrigatorio de "mercado parado"      |
//|  (ADX baixo + largura de banda ou ATR baixos). Stop fixo em       |
//|  pontos alem da banda/suporte oposto (sem pivos de tendencia).    |
//|  Gestao de risco por operacao + governanca diaria + CSV/relatorio |
//|  seguem o padrao de zig-zag_rsi_adx_quant.mq5.                    |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      ""
#property version   "1.00"
#property description "EA de reversao em range: Bollinger Bands + S/R + filtro duplo ADX/BandWidth-ATR, com gestao de risco diaria."

//============================== ENUMS ===============================

enum ENUM_RISK_MODE
  {
   RISK_FIXED_MONEY,      // Risco fixo em dinheiro por operacao
   RISK_PERCENT_BALANCE   // Risco percentual do saldo por operacao
  };

enum ENUM_RR_MODE
  {
   RR_1_TO_1,      // Alvo = 1R (1:1)
   RR_1_TO_0_75,   // Alvo = 0.75R (1:0.75)
   RR_1_TO_0_5,    // Alvo = 0.5R (1:0.5)
   RR_CUSTOM       // Alvo = InpCustomRR * R
  };

enum ENUM_DAILY_LIMIT_MODE
  {
   LIMIT_R_MULTIPLE,    // Expresso em multiplos de R
   LIMIT_FIXED_MONEY    // Expresso em valor fixo de dinheiro
  };

enum ENUM_VOLATILITY_FILTER
  {
   VOL_FILTER_BANDWIDTH,  // Usar largura das Bollinger Bands (%)
   VOL_FILTER_ATR         // Usar ATR em pontos
  };

//============================== INPUTS ===============================

input long   InpMagicNumber       = 20260701;  // Magic Number
input int    InpSlippagePoints    = 30;        // Slippage maximo (pontos)

input string Inp_Sep1             = "--- Bollinger Bands ---"; // ---
input int    InpBBPeriod          = 20;        // BB Period
input int    InpBBShift           = 0;         // BB Shift
input double InpBBDeviation       = 2.0;       // BB Deviation
input ENUM_APPLIED_PRICE InpBBAppliedPrice = PRICE_CLOSE; // BB Applied Price

input string Inp_Sep2             = "--- Zona de Suporte/Resistencia ---"; // ---
input int    InpSRLookbackBars    = 20;        // Barras para achar suporte/resistencia recente
input int    InpSRZoneTolerancePoints = 150;   // Tolerancia (pontos) para considerar preco "na zona"

input string Inp_Sep3             = "--- Filtro Duplo: Mercado Parado ---"; // ---
input int    InpADXPeriod         = 14;        // ADX Period
input double InpADXMaxLevel       = 20.0;      // ADX maximo para considerar mercado lateral
input ENUM_VOLATILITY_FILTER InpVolatilityFilterMode = VOL_FILTER_BANDWIDTH; // Modo do filtro de volatilidade
input double InpMaxBandWidthPercent = 3.0;     // Largura maxima da banda (% da media) para considerar squeeze
input int    InpATRPeriod         = 14;        // ATR Period (usado se modo = ATR)
input double InpMaxATRPoints      = 300.0;     // ATR maximo em pontos (usado se modo = ATR)

input string Inp_Sep4             = "--- Spread ---"; // ---
input double InpMaxSpreadPoints   = 30.0;      // Spread maximo permitido (pontos)

input string Inp_Sep5             = "--- Stop / Alvo ---"; // ---
input int    InpStopBufferPoints  = 50;        // Buffer (pontos) alem da banda/suporte oposto para o stop
input bool   InpUseFixedTPPoints  = false;     // Usar Take Profit Points fixo (em vez de RR)
input double InpTakeProfitPoints  = 150;       // Take Profit Points (se fixo)
input ENUM_RR_MODE InpRRMode      = RR_1_TO_1; // RR Mode
input double InpCustomRR          = 1.0;       // RR customizado (multiplo de R)
input bool   InpUseMaxDurationExit = false;    // Usar saida por tempo maximo
input int    InpMaxTradeDurationMinutes = 60;  // Max Trade Duration (minutos)
input bool   InpUseOppositeSignalExit = false; // Usar saida por sinal contrario

input string Inp_Sep6             = "--- Risco por operacao ---"; // ---
input ENUM_RISK_MODE InpRiskMode  = RISK_PERCENT_BALANCE; // Risk Mode
input double InpRiskPercent       = 0.5;       // Risk Percent (% do saldo)
input double InpFixedRiskMoney    = 50.0;      // Fixed Risk Money

input string Inp_Sep7             = "--- Gerenciamento diario ---"; // ---
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

input string Inp_Sep8             = "--- Sessao (padrao: Asia, ajustavel sem recompilar) ---"; // ---
input bool   InpUsarFiltroSessao  = true;      // Usar filtro de sessao
input string InpSessaoInicio      = "00:00";   // Hora inicial (horario do servidor/broker)
input string InpSessaoFim         = "08:00";   // Hora final (horario do servidor/broker)

input string Inp_Sep9             = "--- Log / Export ---"; // ---
input bool   InpExportCSV         = true;      // Exportar trades para CSV
input bool   InpVerboseLog        = true;      // Log detalhado no Experts

//============================== GLOBALS ===============================

int      g_bbHandle  = INVALID_HANDLE;
int      g_adxHandle = INVALID_HANDLE;
int      g_atrHandle = INVALID_HANDLE;

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

int      g_maxConsecLossesEver      = 0;
int      g_currentConsecNegativeDays = 0;
int      g_maxConsecNegativeDays    = 0;

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

bool IsWithinTradingWindow()
{
   if (!InpUsarFiltroSessao)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int now_minutes = dt.hour * 60 + dt.min;

   int start_minutes = 0;
   int end_minutes = 0;
   if (!ParseTimeToMinutes(InpSessaoInicio, start_minutes) || !ParseTimeToMinutes(InpSessaoFim, end_minutes))
      return false;

   return IsWithinMinutesRange(now_minutes, start_minutes, end_minutes);
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

// Evita mandar ordem para um simbolo que a corretora marcou como
// closeonly/disabled/longonly/shortonly naquele momento (ex.: janela de
// rollover diario do XAUUSD) -- corta o retcode 10044 antes de tentar.
bool SymbolAllowsNewOrder(const bool is_buy, string &reason)
{
   long trade_mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

   if (trade_mode == SYMBOL_TRADE_MODE_DISABLED)
      { reason = "SYMBOL_TRADE_DISABLED"; return false; }
   if (trade_mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      { reason = "SYMBOL_CLOSE_ONLY"; return false; }
   if (is_buy && trade_mode == SYMBOL_TRADE_MODE_SHORTONLY)
      { reason = "SYMBOL_SHORT_ONLY"; return false; }
   if (!is_buy && trade_mode == SYMBOL_TRADE_MODE_LONGONLY)
      { reason = "SYMBOL_LONG_ONLY"; return false; }

   return true;
}

double GetRRMultiplier()
{
   switch (InpRRMode)
   {
      case RR_1_TO_1:    return 1.0;
      case RR_1_TO_0_75: return 0.75;
      case RR_1_TO_0_5:  return 0.5;
      case RR_CUSTOM:    return InpCustomRR;
   }
   return 1.0;
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

//============================== SINAL: RANGE (BB + S/R + ADX/Volatilidade) ==============================

// Le Bollinger Bands, ADX, ATR (se aplicavel) e as barras necessarias para achar
// a zona de suporte/resistencia recente. So retorna sinal quando o filtro duplo
// de "mercado parado" (ADX baixo E banda/ATR estreitos) estiver satisfeito.
bool ComputeRangeSignal(int &signal_out, double &sl_price_out)
{
   signal_out = 0;
   sl_price_out = 0.0;

   int bars_needed = MathMax(InpSRLookbackBars + 3, 5);

   double bb_upper[], bb_middle[], bb_lower[], adx_buf[], atr_buf[];
   MqlRates rates[];

   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(adx_buf, true);
   ArraySetAsSeries(atr_buf, true);
   ArraySetAsSeries(rates, true);

   if (CopyBuffer(g_bbHandle, 1, 0, 3, bb_upper) < 3)
      return false;
   if (CopyBuffer(g_bbHandle, 0, 0, 3, bb_middle) < 3)
      return false;
   if (CopyBuffer(g_bbHandle, 2, 0, 3, bb_lower) < 3)
      return false;
   if (CopyBuffer(g_adxHandle, 0, 0, 2, adx_buf) < 2)
      return false;
   if (InpVolatilityFilterMode == VOL_FILTER_ATR && CopyBuffer(g_atrHandle, 0, 0, 2, atr_buf) < 2)
      return false;
   if (CopyRates(_Symbol, _Period, 0, bars_needed, rates) < bars_needed)
      return false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tolerance_price   = InpSRZoneTolerancePoints * point;
   double stop_buffer_price = InpStopBufferPoints * point;

   // zona de suporte/resistencia: extremos das barras anteriores ao gatilho
   // (indices 3..window_end), nao inclui as duas barras usadas no gatilho.
   double recent_low  = rates[2].low;
   double recent_high = rates[2].high;
   int window_end = MathMin(2 + InpSRLookbackBars, ArraySize(rates) - 1);
   for (int i = 3; i <= window_end; i++)
   {
      if (rates[i].low < recent_low)   recent_low  = rates[i].low;
      if (rates[i].high > recent_high) recent_high = rates[i].high;
   }

   bool adx_allows_entry = (adx_buf[1] <= InpADXMaxLevel);

   bool volatility_allows_entry;
   if (InpVolatilityFilterMode == VOL_FILTER_BANDWIDTH)
   {
      double bandwidth_pct = (bb_middle[1] != 0.0) ? (bb_upper[1] - bb_lower[1]) / bb_middle[1] * 100.0 : 0.0;
      volatility_allows_entry = (bandwidth_pct <= InpMaxBandWidthPercent);
   }
   else
   {
      double atr_points = atr_buf[1] / point;
      volatility_allows_entry = (atr_points <= InpMaxATRPoints);
   }

   // Filtro duplo obrigatorio: so considera "mercado parado" com as DUAS
   // condicoes verdadeiras ao mesmo tempo.
   if (!(adx_allows_entry && volatility_allows_entry))
      return false;

   bool buy_trigger  = (rates[2].close < bb_lower[2]) && (rates[1].close > bb_lower[1]);
   bool sell_trigger = (rates[2].close > bb_upper[2]) && (rates[1].close < bb_upper[1]);

   bool price_near_support    = (rates[2].low  <= recent_low  + tolerance_price);
   bool price_near_resistance = (rates[2].high >= recent_high - tolerance_price);

   if (buy_trigger && price_near_support)
   {
      signal_out = 1;
      sl_price_out = NormalizeDouble(MathMin(recent_low, bb_lower[1]) - stop_buffer_price, _Digits);
      return true;
   }

   if (sell_trigger && price_near_resistance)
   {
      signal_out = -1;
      sl_price_out = NormalizeDouble(MathMax(recent_high, bb_upper[1]) + stop_buffer_price, _Digits);
      return true;
   }

   return false;
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

   req.action       = TRADE_ACTION_DEAL;
   req.position     = ticket;
   req.symbol       = _Symbol;
   req.volume       = volume;
   req.deviation    = InpSlippagePoints;
   req.magic        = InpMagicNumber;
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

void OpenBuy(const double sl_price)
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double risk_price_distance = tick.ask - sl_price;
   if (risk_price_distance <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] BUY: stop invalido (acima do preco)");
      return;
   }

   double sl_points = risk_price_distance / point;
   double tp_points = InpUseFixedTPPoints ? InpTakeProfitPoints : (sl_points * GetRRMultiplier());

   double risk_money = 0.0;
   double lot = CalculateLotSize(sl_points, risk_money);
   if (lot <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] BUY: lote invalido");
      return;
   }

   double sl = NormalizeDouble(sl_price, _Digits);
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
   req.comment      = "BB_RANGE_BUY";

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[ENTRY-FAIL] BUY retcode=%d", res.retcode);
      return;
   }

   g_dayTradesCount++;
   g_totalTradesOpened++;
   if (InpVerboseLog)
      PrintFormat("[ENTRY] BB_RANGE_BUY lot=%.2f sl=%.5f tp=%.5f risco=%.2f", lot, sl, tp, risk_money);
}

void OpenSell(const double sl_price)
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double risk_price_distance = sl_price - tick.bid;
   if (risk_price_distance <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] SELL: stop invalido (abaixo do preco)");
      return;
   }

   double sl_points = risk_price_distance / point;
   double tp_points = InpUseFixedTPPoints ? InpTakeProfitPoints : (sl_points * GetRRMultiplier());

   double risk_money = 0.0;
   double lot = CalculateLotSize(sl_points, risk_money);
   if (lot <= 0.0)
   {
      if (InpVerboseLog) Print("[ENTRY-FAIL] SELL: lote invalido");
      return;
   }

   double sl = NormalizeDouble(sl_price, _Digits);
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
   req.comment      = "BB_RANGE_SELL";

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[ENTRY-FAIL] SELL retcode=%d", res.retcode);
      return;
   }

   g_dayTradesCount++;
   g_totalTradesOpened++;
   if (InpVerboseLog)
      PrintFormat("[ENTRY] BB_RANGE_SELL lot=%.2f sl=%.5f tp=%.5f risco=%.2f", lot, sl, tp, risk_money);
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

   string filename = "RANGE_BOLLINGER_" + _Symbol + "_" + IntegerToString((int)InpMagicNumber) + ".csv";
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
   g_bbHandle = iBands(_Symbol, _Period, InpBBPeriod, InpBBShift, InpBBDeviation, InpBBAppliedPrice);
   g_adxHandle = iADX(_Symbol, _Period, InpADXPeriod);

   if (g_bbHandle == INVALID_HANDLE || g_adxHandle == INVALID_HANDLE)
   {
      Alert("Falha ao criar handles de indicadores (BB/ADX) - erro: ", GetLastError());
      return INIT_FAILED;
   }

   if (InpVolatilityFilterMode == VOL_FILTER_ATR)
   {
      g_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
      if (g_atrHandle == INVALID_HANDLE)
      {
         Alert("Falha ao criar handle do ATR - erro: ", GetLastError());
         return INIT_FAILED;
      }
   }

   if (InpUsarFiltroSessao)
   {
      int parsed_minutes = 0;
      if (!ParseTimeToMinutes(InpSessaoInicio, parsed_minutes) || !ParseTimeToMinutes(InpSessaoFim, parsed_minutes))
      {
         Alert("Horario de sessao invalido. Use HH:MM.");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   g_equityPeak  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_currentDay  = 0;
   g_csvHandle   = INVALID_HANDLE;
   OpenCSV();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_bbHandle != INVALID_HANDLE)
      IndicatorRelease(g_bbHandle);
   if (g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
   if (g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

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
   double signal_sl_price = 0.0;

   if (is_new_bar)
   {
      int signal = 0;
      double sl_price = 0.0;
      if (ComputeRangeSignal(signal, sl_price))
      {
         g_lastSignal = signal;
         signal_sl_price = sl_price;
      }
      else
      {
         g_lastSignal = 0;
      }
   }

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

   if (g_lastSignal == 1 || g_lastSignal == -1)
   {
      bool is_buy = (g_lastSignal == 1);
      string symbol_block_reason = "";
      if (!SymbolAllowsNewOrder(is_buy, symbol_block_reason))
      {
         if (InpVerboseLog)
            PrintFormat("[BLOCKED] motivo=%s", symbol_block_reason);
         return;
      }

      if (is_buy)
         OpenBuy(signal_sl_price);
      else
         OpenSell(signal_sl_price);
   }
}
//+------------------------------------------------------------------+
