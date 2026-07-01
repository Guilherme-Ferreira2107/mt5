//+------------------------------------------------------------------+
//| risk-governance.mqh                                               |
//| Modulo padrao de gestao de risco por operacao + governanca diaria |
//| + relatorio final. Extraido de zig-zag_rsi_adx_quant.mq5.          |
//| Sempre incluir em EAs novos, independente do sinal de entrada.     |
//+------------------------------------------------------------------+
#property strict

enum ENUM_RISK_MODE   { RISK_FIXED_MONEY, RISK_PERCENT_BALANCE };
enum ENUM_RR_MODE     { RR_1_TO_1, RR_1_TO_0_75, RR_1_TO_0_5, RR_CUSTOM };
enum ENUM_DAILY_LIMIT_MODE { LIMIT_R_MULTIPLE, LIMIT_FIXED_MONEY };

// ---- inputs a copiar (renomeie prefixo se quiser) ----
// input long   InpMagicNumber;
// input int    InpSlippagePoints    = 30;
// input ENUM_RISK_MODE InpRiskMode  = RISK_PERCENT_BALANCE;
// input double InpRiskPercent       = 0.5;
// input double InpFixedRiskMoney    = 50.0;
// input double InpStopLossPoints;                 // ou derive do stop estrutural
// input bool   InpUseFixedTPPoints  = false;
// input double InpTakeProfitPoints  = 150;
// input ENUM_RR_MODE InpRRMode      = RR_1_TO_1;
// input double InpCustomRR          = 1.0;
// input bool   InpUseMaxDurationExit = false;
// input int    InpMaxTradeDurationMinutes = 60;
// input bool   InpUseOppositeSignalExit = false;
// input ENUM_DAILY_LIMIT_MODE InpDailyTargetMode = LIMIT_R_MULTIPLE;
// input double InpDailyTargetRMultiple = 1.0;
// input double InpDailyTargetMoney  = 100.0;
// input bool   InpCloseOpenOnDailyTarget = false;
// input ENUM_DAILY_LIMIT_MODE InpDailyLossMode = LIMIT_R_MULTIPLE;
// input double InpDailyLossRMultiple = 2.0;
// input double InpDailyLossMoney    = 200.0;
// input bool   InpCloseOpenOnDailyLoss = true;
// input int    InpMaxTradesPerDay   = 5;    // 0 = ilimitado
// input int    InpMaxConsecLossesPerDay = 3; // 0 = desliga
// input bool   InpExportCSV = true;
// input bool   InpVerboseLog = true;

// ---- globais a copiar ----
// datetime g_currentDay; double g_dayStartBalance; double g_dailyR;
// double g_dayProfit; int g_dayTradesCount; int g_dayConsecLosses;
// bool g_dailyTargetReached; bool g_dailyLossReached;
// int g_lastSignal; string g_lastCloseReason;
// estatisticas agregadas: g_totalTradesOpened/Closed, g_totalWins/Losses,
// g_grossProfit/Loss, g_totalProfit, g_totalDaysTraded, g_positiveDays,
// g_negativeDays, g_sumPositiveDaily/NegativeDaily, g_maxDailyProfit/Loss,
// g_maxConsecLossesEver, g_currentConsecNegativeDays, g_maxConsecNegativeDays,
// g_equityPeak, g_maxDrawdown, int g_csvHandle;

// -------------------- filling / sizing --------------------

ENUM_ORDER_TYPE_FILLING GetFillingType()
{
   // NUNCA hardcode ORDER_FILLING_IOC -- corretoras variam. Detecte.
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if ((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if ((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

double GetRRMultiplier(const ENUM_RR_MODE mode, const double custom_rr)
{
   switch (mode)
   {
      case RR_1_TO_1:    return 1.0;
      case RR_1_TO_0_75: return 0.75;
      case RR_1_TO_0_5:  return 0.5;
      case RR_CUSTOM:    return custom_rr;
   }
   return 1.0;
}

double CalcRiskMoney(const ENUM_RISK_MODE mode, const double fixed_money,
                      const double risk_percent, const double balance_ref)
{
   if (mode == RISK_FIXED_MONEY)
      return fixed_money;
   return balance_ref * risk_percent / 100.0;
}

double NormalizeLot(double lot)
{
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (lot_step <= 0.0) lot_step = 0.01;

   lot = MathFloor(lot / lot_step) * lot_step;
   if (lot < min_lot) lot = min_lot;
   if (lot > max_lot) lot = max_lot;
   return NormalizeDouble(lot, 2);
}

// sl_points: distancia do stop em pontos (fixa OU derivada do stop
// estrutural convertida para pontos). Retorna lote normalizado, 0.0 se
// invalido.
double CalculateLotSize(const double sl_points, const ENUM_RISK_MODE risk_mode,
                         const double fixed_money, const double risk_percent,
                         double &risk_money_out)
{
   risk_money_out = CalcRiskMoney(risk_mode, fixed_money, risk_percent, AccountInfoDouble(ACCOUNT_BALANCE));

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

// -------------------- governanca diaria --------------------
// Chame RolloverDayIfNeeded() no inicio de todo OnTick, antes de checar
// sinais. Chame CheckDailyLimitsAfterClose() dentro de OnTradeTransaction
// apos registrar o profit do trade fechado.

// void RolloverDayIfNeeded()
// {
//    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
//    dt.hour = 0; dt.min = 0; dt.sec = 0;
//    datetime today = StructToTime(dt);
//    if (today == g_currentDay) return;
//    if (g_currentDay != 0) FinalizeDayStats(g_dayProfit, g_dayTradesCount);
//    g_currentDay = today;
//    g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
//    g_dailyR = CalcRiskMoney(InpRiskMode, InpFixedRiskMoney, InpRiskPercent, g_dayStartBalance);
//    g_dayProfit = 0.0; g_dayTradesCount = 0; g_dayConsecLosses = 0;
//    g_dailyTargetReached = false; g_dailyLossReached = false;
// }
//
// bool CanOpenNewTrade(string &reason)
// {
//    if (g_dailyLossReached)   { reason = "DAILY_LOSS_LIMIT_REACHED"; return false; }
//    if (g_dailyTargetReached) { reason = "DAILY_TARGET_REACHED";     return false; }
//    if (InpMaxTradesPerDay > 0 && g_dayTradesCount >= InpMaxTradesPerDay)
//       { reason = "MAX_TRADES_PER_DAY_REACHED"; return false; }
//    if (InpMaxConsecLossesPerDay > 0 && g_dayConsecLosses >= InpMaxConsecLossesPerDay)
//       { reason = "MAX_CONSEC_LOSSES_REACHED"; return false; }
//    if (!SpreadOk()) { reason = "SPREAD_TOO_HIGH"; return false; }
//    return true;
// }

// -------------------- relatorio --------------------
// Em OnDeinit chame PrintFinalReport() (ele mesmo chama FinalizeDayStats
// para fechar o ultimo dia). Metricas: dias operados, dias +/-, lucro/perda
// media diaria, maior lucro/perda diaria, sequencia max de perdas
// (trades e dias), profit factor, drawdown de equity, expectativa por
// trade e por dia. Ver PrintFinalReport() em zig-zag_rsi_adx_quant.mq5
// linhas 600-627 para a implementacao completa -- copie tal qual.

// -------------------- CSV --------------------
// OpenCSV() no OnInit (arquivo "<EA>_<Symbol>_<Magic>.csv", separador ';'),
// ExportTradeRow() apos cada fechamento, FileClose() no OnDeinit. Ver
// zig-zag_rsi_adx_quant.mq5 linhas 577-598 para a implementacao completa.
