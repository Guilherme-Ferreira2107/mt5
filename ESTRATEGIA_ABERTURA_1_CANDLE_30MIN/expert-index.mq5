//+------------------------------------------------------------------+
//|                                   abertura-1-candle-30min.mq5    |
//|  Porte da estrategia Pine "Abertura 16h - 1o Candle 30min".      |
//|  Um unico trade por dia, disparado no fechamento do candle de    |
//|  referencia (horario configuravel). TP/SL sao percentuais da     |
//|  altura (high-low) desse candle. Inclui risco por operacao.      |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link ""
#property version "1.00"
#property description "Abertura 16h - 1 Candle 30min: entrada unica diaria no candle de referencia, TP/SL como % da altura do candle."

//============================== ENUMS ===============================

enum ENUM_RISK_MODE
{
   RISK_FIXED_MONEY,    // Risco fixo em dinheiro por operacao
   RISK_PERCENT_BALANCE // Risco percentual do saldo por operacao
};

//============================== INPUTS ===============================

input long InpMagicNumber = 20260710; // Magic Number
input int InpSlippagePoints = 30;     // Slippage maximo (pontos)

input string Inp_Sep1 = "--- Candle de referencia ---"; // ---
input int InpSessionHour = 16;                          // Hora do candle de referencia
input int InpSessionMinute = 0;                         // Minuto do candle de referencia
input double InpTakeProfitPercent = 1050.0;             // Take Profit (% da altura do candle)
input double InpStopLossPercent = 150.0;                // Stop Loss (% da altura do candle)

input string Inp_Sep2 = "--- Spread ---"; // ---
input double InpMaxSpreadPoints = 100.0;  // Spread maximo permitido (pontos)

input string Inp_Sep3 = "--- Risco por operacao ---";    // ---
input ENUM_RISK_MODE InpRiskMode = RISK_PERCENT_BALANCE; // Risk Mode
input double InpRiskPercent = 0.5;                       // Risk Percent (% do saldo)
input double InpFixedRiskMoney = 50.0;                   // Fixed Risk Money

input string Inp_Sep4 = "--- Filtro de tendencia (media movel) ---"; // ---
input bool InpUseMAFilter = false;                                   // Ativar filtro de tendencia por media movel
input int InpMAPeriod = 50;                                          // Periodo da media movel
input ENUM_MA_METHOD InpMAMethod = MODE_SMA;                         // Metodo da media movel
input ENUM_APPLIED_PRICE InpMAAppliedPrice = PRICE_CLOSE;            // Preco aplicado da media movel

input string Inp_Sep4b = "--- Protecao de lucro (giveback) ---"; // ---
input bool InpUseProfitGiveback = false;                         // Ativar fechamento por retracao do lucro
input double InpGivebackPercent = 50.0;                          // % do movimento favoravel que, se devolvido, fecha a posicao

input string Inp_Sep4c = "--- Fechamento por horario (dia seguinte) ---"; // ---
input bool InpUseTimeExit = false;                                       // Ativar fechamento forcado no dia seguinte a entrada
input int InpExitHour = 23;                                              // Hora do fechamento forcado (dia seguinte)
input int InpExitMinute = 0;                                             // Minuto do fechamento forcado (dia seguinte)

//============================== GLOBALS ===============================

// estado do dia corrente
datetime g_currentDay = 0;
double g_dayProfit = 0.0;
int g_dayTradesCount = 0;

// estatisticas agregadas de todo o teste/sessao
int g_totalTradesOpened = 0;
int g_totalTradesClosed = 0;
int g_totalWins = 0;
int g_totalLosses = 0;
double g_grossProfit = 0.0;
double g_grossLoss = 0.0;
double g_totalProfit = 0.0;

int g_totalDaysTraded = 0;
int g_positiveDays = 0;
int g_negativeDays = 0;
double g_sumPositiveDaily = 0.0;
double g_sumNegativeDaily = 0.0;
double g_maxDailyProfit = 0.0;
double g_maxDailyLoss = 0.0;

int g_currentConsecNegativeDays = 0;
int g_maxConsecNegativeDays = 0;

double g_equityPeak = 0.0;
double g_maxDrawdown = 0.0;

int g_maHandle = INVALID_HANDLE;

// rastreio da posicao atual para a protecao de lucro (giveback)
ulong g_gbTicket = 0;
double g_gbEntryPrice = 0.0;
double g_gbPeakPrice = 0.0;
long g_gbPosType = -1;

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
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
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
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (tick_value <= 0.0 || tick_size <= 0.0 || point <= 0.0 || sl_points <= 0.0)
      return 0.0;

   double sl_price_distance = sl_points * point;
   double loss_per_lot = (sl_price_distance / tick_size) * tick_value;
   if (loss_per_lot <= 0.0)
      return 0.0;

   return NormalizeLot(risk_money_out / loss_per_lot);
}

//============================== SINAL ===============================

// Verdadeiro quando o candle que acabou de fechar comecou exatamente no
// horario configurado (equivalente a "hour == sessionHour and minute ==
// sessionMinute" do Pine). Como esse horario ocorre uma unica vez por dia,
// isso ja garante no maximo um sinal por dia.
bool IsTriggerCandle(const datetime candle_open_time)
{
   MqlDateTime dt;
   TimeToStruct(candle_open_time, dt);
   return (dt.hour == InpSessionHour && dt.min == InpSessionMinute);
}

//============================== POSICOES ===============================

ulong FindOpenPositionTicket()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return ticket;
   }
   return 0;
}

bool HasOpenPosition()
{
   return FindOpenPositionTicket() != 0;
}

//============================== FECHAMENTO A MERCADO ===============================

// Fecha uma posicao a mercado por iniciativa da propria EA (giveback ou
// horario de corte). SL/TP normais continuam sendo geridos pelo broker; isso
// so entra em acao quando um dos gatilhos abaixo dispara antes deles.
void CloseMarketPosition(const ulong ticket, const long pos_type, const string reason)
{
   if (!PositionSelectByTicket(ticket))
      return;

   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double volume = PositionGetDouble(POSITION_VOLUME);

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = _Symbol;
   req.volume = volume;
   req.deviation = InpSlippagePoints;
   req.magic = InpMagicNumber;
   req.type_filling = GetFillingType();

   if (pos_type == POSITION_TYPE_BUY)
   {
      req.type = ORDER_TYPE_SELL;
      req.price = tick.bid;
   }
   else
   {
      req.type = ORDER_TYPE_BUY;
      req.price = tick.ask;
   }

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
      PrintFormat("[EXIT-FAIL] ticket=%I64u motivo=%s retcode=%d", ticket, reason, res.retcode);
}

//============================== PROTECAO DE LUCRO (GIVEBACK) ===============================

// A cada tick (independente de nova barra), acompanha o preco mais favoravel
// atingido desde a entrada e fecha a posicao se o preco devolver
// InpGivebackPercent do movimento favoravel. So atua enquanto a posicao ainda
// esta no lado positivo (preco de gatilho sempre fica entre entrada e pico),
// entao nunca antecipa um stop de perda -- so protege lucro ja formado.
void ManageProfitGiveback()
{
   if (!InpUseProfitGiveback)
      return;

   ulong ticket = FindOpenPositionTicket();
   if (ticket == 0)
   {
      g_gbTicket = 0;
      return;
   }

   if (!PositionSelectByTicket(ticket))
      return;

   if (ticket != g_gbTicket)
   {
      g_gbTicket = ticket;
      g_gbEntryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_gbPeakPrice = g_gbEntryPrice;
      g_gbPosType = PositionGetInteger(POSITION_TYPE);
   }

   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   if (g_gbPosType == POSITION_TYPE_BUY)
   {
      if (tick.bid > g_gbPeakPrice)
         g_gbPeakPrice = tick.bid;

      double favorable = g_gbPeakPrice - g_gbEntryPrice;
      if (favorable <= 0.0)
         return;

      double triggerPrice = g_gbPeakPrice - favorable * (InpGivebackPercent / 100.0);
      if (tick.bid <= triggerPrice)
         CloseMarketPosition(g_gbTicket, g_gbPosType, "PROFIT_GIVEBACK");
   }
   else
   {
      if (tick.ask < g_gbPeakPrice)
         g_gbPeakPrice = tick.ask;

      double favorable = g_gbEntryPrice - g_gbPeakPrice;
      if (favorable <= 0.0)
         return;

      double triggerPrice = g_gbPeakPrice + favorable * (InpGivebackPercent / 100.0);
      if (tick.ask >= triggerPrice)
         CloseMarketPosition(g_gbTicket, g_gbPosType, "PROFIT_GIVEBACK");
   }
}

//============================== FECHAMENTO POR HORARIO ===============================

// Encerra a posicao aberta no InpExitHour:InpExitMinute do dia seguinte ao da
// entrada (nao no mesmo dia) -- como a estrategia so entra uma vez por dia,
// isso da margem para o trade trabalhar durante o resto do dia da entrada e
// so aplica o corte na sessao seguinte. Independente de lucro ou prejuizo.
// Roda a cada tick para nao depender do fechamento de candle.
void ManageTimeExit()
{
   if (!InpUseTimeExit)
      return;

   ulong ticket = FindOpenPositionTicket();
   if (ticket == 0)
      return;

   if (!PositionSelectByTicket(ticket))
      return;

   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   MqlDateTime openDt;
   TimeToStruct(openTime, openDt);
   openDt.hour = 0;
   openDt.min = 0;
   openDt.sec = 0;
   datetime openDay = StructToTime(openDt);

   MqlDateTime nowDt;
   TimeToStruct(TimeCurrent(), nowDt);
   int nowMinutes = nowDt.hour * 60 + nowDt.min;

   MqlDateTime nowDayDt = nowDt;
   nowDayDt.hour = 0;
   nowDayDt.min = 0;
   nowDayDt.sec = 0;
   datetime nowDay = StructToTime(nowDayDt);

   if (nowDay <= openDay)
      return; // ainda no dia da entrada -- so aplica o corte a partir do dia seguinte

   int exitMinutes = InpExitHour * 60 + InpExitMinute;
   if (nowMinutes < exitMinutes)
      return;

   long pos_type = PositionGetInteger(POSITION_TYPE);
   CloseMarketPosition(ticket, pos_type, "TIME_EXIT");
}

//============================== ENTRADAS ===============================

// ref_close / range vem do candle de referencia (rates[1]): range = high-low,
// ref_close = close do candle. TP/SL sao percentuais desse range, igual ao
// Pine (tpPerc=50%, slPerc=25% por padrao).
void OpenBuy(const double ref_close, const double range)
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl_price = NormalizeDouble(ref_close - range * InpStopLossPercent / 100.0, _Digits);
   double tp_price = NormalizeDouble(ref_close + range * InpTakeProfitPercent / 100.0, _Digits);

   double sl_distance = tick.ask - sl_price;
   if (sl_distance <= 0.0 || tp_price <= tick.ask)
   {
      Print("[ENTRY-FAIL] BUY: SL/TP invalidos em relacao ao preco atual");
      return;
   }

   double risk_money = 0.0;
   double lot = CalculateLotSize(sl_distance / point, risk_money);
   if (lot <= 0.0)
   {
      Print("[ENTRY-FAIL] BUY: lote invalido");
      return;
   }

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = ORDER_TYPE_BUY;
   req.price = tick.ask;
   req.sl = sl_price;
   req.tp = tp_price;
   req.deviation = InpSlippagePoints;
   req.magic = InpMagicNumber;
   req.type_filling = GetFillingType();
   req.comment = "ABERTURA_BUY";

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[ENTRY-FAIL] BUY retcode=%d", res.retcode);
      return;
   }

   g_dayTradesCount++;
   g_totalTradesOpened++;
}

void OpenSell(const double ref_close, const double range)
{
   MqlTick tick;
   if (!SymbolInfoTick(_Symbol, tick))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl_price = NormalizeDouble(ref_close + range * InpStopLossPercent / 100.0, _Digits);
   double tp_price = NormalizeDouble(ref_close - range * InpTakeProfitPercent / 100.0, _Digits);

   double sl_distance = sl_price - tick.bid;
   if (sl_distance <= 0.0 || tp_price >= tick.bid)
   {
      Print("[ENTRY-FAIL] SELL: SL/TP invalidos em relacao ao preco atual");
      return;
   }

   double risk_money = 0.0;
   double lot = CalculateLotSize(sl_distance / point, risk_money);
   if (lot <= 0.0)
   {
      Print("[ENTRY-FAIL] SELL: lote invalido");
      return;
   }

   MqlTradeRequest req;
   MqlTradeResult res;
   ZeroMemory(req);
   ZeroMemory(res);
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lot;
   req.type = ORDER_TYPE_SELL;
   req.price = tick.bid;
   req.sl = sl_price;
   req.tp = tp_price;
   req.deviation = InpSlippagePoints;
   req.magic = InpMagicNumber;
   req.type_filling = GetFillingType();
   req.comment = "ABERTURA_SELL";

   if (!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
   {
      PrintFormat("[ENTRY-FAIL] SELL retcode=%d", res.retcode);
      return;
   }

   g_dayTradesCount++;
   g_totalTradesOpened++;
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
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime today = StructToTime(dt);

   if (today == g_currentDay)
      return;

   if (g_currentDay != 0)
      FinalizeDayStats(g_dayProfit, g_dayTradesCount);

   g_currentDay = today;
   g_dayProfit = 0.0;
   g_dayTradesCount = 0;
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

//============================== RELATORIO ===============================

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
   if (InpSessionHour < 0 || InpSessionHour > 23 || InpSessionMinute < 0 || InpSessionMinute > 59)
   {
      Alert("Horario do candle de referencia invalido.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpUseMAFilter && InpMAPeriod <= 0)
   {
      Alert("InpMAPeriod deve ser maior que zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpUseProfitGiveback && (InpGivebackPercent <= 0.0 || InpGivebackPercent >= 100.0))
   {
      Alert("InpGivebackPercent deve estar entre 0 e 100 (exclusive).");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpExitHour < 0 || InpExitHour > 23 || InpExitMinute < 0 || InpExitMinute > 59)
   {
      Alert("Horario de fechamento forcado invalido.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_maHandle = INVALID_HANDLE;
   if (InpUseMAFilter)
   {
      g_maHandle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, InpMAMethod, InpMAAppliedPrice);
      if (g_maHandle == INVALID_HANDLE)
      {
         Print("ERRO: falha ao criar handle da media movel. GetLastError=", GetLastError());
         return INIT_FAILED;
      }
   }

   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   g_currentDay = 0;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFinalReport();

   if (g_maHandle != INVALID_HANDLE)
      IndicatorRelease(g_maHandle);
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

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   g_dayProfit += profit;
   g_totalProfit += profit;
   g_totalTradesClosed++;

   if (profit > 0.0)
   {
      g_totalWins++;
      g_grossProfit += profit;
   }
   else if (profit < 0.0)
   {
      g_totalLosses++;
      g_grossLoss += (-profit);
   }
}

void OnTick()
{
   RolloverDayIfNeeded();
   UpdateDrawdown();
   ManageProfitGiveback();
   ManageTimeExit();

   if (!IsNewBar())
      return;

   int minBars = 3;
   if (InpUseMAFilter)
      minBars = MathMax(minBars, InpMAPeriod + 2);
   if (Bars(_Symbol, _Period) < minBars)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if (CopyRates(_Symbol, _Period, 0, 2, rates) < 2)
      return;

   // rates[1] e o candle que acabou de fechar (o candle 0 e o novo, em formacao).
   if (!IsTriggerCandle(rates[1].time))
      return;

   if (HasOpenPosition())
      return;

   if (!SpreadOk())
      return;

   double range = rates[1].high - rates[1].low;
   if (range <= 0.0)
      return;

   bool is_bull = rates[1].close > rates[1].open;

   bool allowBuy = true;
   bool allowSell = true;
   if (InpUseMAFilter)
   {
      double maBuf[1];
      if (CopyBuffer(g_maHandle, 0, 1, 1, maBuf) <= 0)
      {
         Print("ERRO: CopyBuffer da media movel falhou. GetLastError=", GetLastError());
         return;
      }
      double maValue = maBuf[0];
      allowBuy = rates[1].close > maValue;
      allowSell = rates[1].close < maValue;
   }

   if (is_bull && allowBuy)
      OpenBuy(rates[1].close, range);
   else if (!is_bull && allowSell)
      OpenSell(rates[1].close, range);
}
//+------------------------------------------------------------------+
