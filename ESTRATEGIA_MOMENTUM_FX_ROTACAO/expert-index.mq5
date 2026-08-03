//+------------------------------------------------------------------+
//| expert-index.mq5                                                  |
//| EA: Momentum cross-sectional em cesta de FX, rotacao trimestral.  |
//| Adaptado de quantpedia.com/strategies/momentum-in-mutual-fund-    |
//| returns (momentum-in-mutual-fund-returns.py). Especificacao       |
//| completa: ESTRATEGIA_MOMENTUM_FX_ROTACAO.md (mesma pasta).        |
//|                                                                    |
//| Diferente das outras EAs deste repo: NAO e sinal tecnico em 1     |
//| simbolo. E rotacao de carteira -- ranqueia uma cesta de pares FX  |
//| pelo retorno dos ultimos N dias uteis, compra (e opcionalmente    |
//| vende) os extremos do ranking em pesos iguais, e rebalanceia a    |
//| cada N meses. Pode manter varias posicoes abertas ao mesmo tempo, |
//| uma por simbolo selecionado. Sem stop estrutural, sem sessao de   |
//| horario, sem governanca diaria -- ver secoes 6/7 do .md para o    |
//| motivo de cada omissao e o que foi usado no lugar (kill-switch de |
//| drawdown de portfolio).                                           |
//|                                                                    |
//| Anexar em grafico D1 (o simbolo do grafico serve so de "relogio"  |
//| para detectar nova barra diaria -- nao precisa estar na cesta).   |
//| Requer o modo "Todos os ticks (baseado em ticks reais)" no        |
//| Strategy Tester para operar multiplos simbolos corretamente.      |
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

//============================== STRUCT ===============================

struct SymbolPerf
  {
   string   symbol;
   double   momentum;
  };

//============================== INPUTS ===============================

input long   InpMagicNumber       = 20260803;  // Magic Number
input int    InpSlippagePoints    = 30;        // Slippage maximo (pontos)

input string Inp_Sep1                  = "--- Universo (cesta de FX) ---"; // ---
input string InpUniverse                = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,NZDUSD,EURGBP,EURJPY,EURCHF,EURCAD,EURAUD,EURNZD,GBPJPY,GBPCHF,GBPCAD,GBPAUD,GBPNZD,AUDJPY,AUDCHF,AUDCAD,AUDNZD,NZDJPY,CADJPY,CHFJPY,CADCHF,NZDCHF,NZDCAD"; // Cesta de pares (separados por virgula)
input int    InpMinUniverseReady        = 10;   // Minimo de simbolos com historico OK para rebalancear

input string Inp_Sep2                  = "--- Momentum / Ranking ---"; // ---
input int    InpMomentumTradingDays     = 126;  // Janela de momentum (dias uteis, 126 = ~6 meses)
input int    InpRebalanceMonths         = 3;    // Frequencia de rebalanceamento (meses)
input double InpTopPercent              = 20.0; // % superior do ranking (carteira comprada)
input bool   InpAllowShort              = false;// Vender tambem o % inferior (long-short)
input double InpBottomPercent           = 20.0; // % inferior do ranking (carteira vendida, se InpAllowShort)

input string Inp_Sep3                  = "--- Exposicao / Sizing ---"; // ---
input double InpGrossExposurePercent    = 100.0; // Exposicao bruta total (% do saldo, dividida entre posicoes)
input double InpMaxSymbolWeightPercent  = 20.0;  // Teto de peso por simbolo
input double InpHardStopPercent         = 0.0;   // Stop de seguranca por posicao (% do preco, 0 = desliga)

input string Inp_Sep4                  = "--- Spread ---"; // ---
input double InpMaxSpreadPoints  = 50.0;       // Spread maximo permitido por simbolo (pontos, calibrar por par)

input string Inp_Sep5                  = "--- Governanca de portfolio ---"; // ---
input double InpMaxDrawdownPercent      = 20.0; // Drawdown maximo de equity do pico (% , 0 = desliga)
input bool   InpFlattenOnMaxDrawdown    = true; // Zera posicoes e pausa rebalanceamentos ao atingir o limite

input string Inp_Sep6                  = "--- Log / Export ---"; // ---
input bool   InpExportCSV  = true;   // Exportar trades/rebalanceamentos para CSV
input bool   InpVerboseLog = true;   // Log detalhado no Experts

//============================== GLOBALS ===============================

CTrade trade;

string   g_universe[];
datetime g_nextRebalanceTime = 0;
int      g_rebalanceCount    = 0;

bool     g_killSwitchActive  = false;
double   g_equityPeak        = 0.0;
double   g_maxDrawdown       = 0.0;

string   g_lastCloseReason   = ""; // motivo de fechamento manual a ser consumido pelo OnTradeTransaction

int      g_totalTradesOpened = 0;
int      g_totalTradesClosed = 0;
int      g_totalWins         = 0;
int      g_totalLosses       = 0;
double   g_grossProfit       = 0.0;
double   g_grossLoss         = 0.0;
double   g_totalProfit       = 0.0;

int      g_csvHandle           = INVALID_HANDLE;
int      g_csvRebalanceHandle  = INVALID_HANDLE;

//============================== UNIVERSO ===============================

// Faz o parsing do csv de simbolos, valida cada um via SymbolSelect (ignora
// os que o broker nao oferece) e devolve a lista efetivamente utilizavel.
int ParseUniverse(const string csv, string &out[])
{
   ArrayResize(out, 0);

   string parts[];
   int n = StringSplit(csv, ',', parts);

   for (int i = 0; i < n; i++)
   {
      string sym = parts[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if (sym == "")
         continue;

      if (!SymbolSelect(sym, true))
      {
         if (InpVerboseLog)
            PrintFormat("[UNIVERSE] simbolo indisponivel no broker, ignorado: %s", sym);
         continue;
      }

      int m = ArraySize(out);
      ArrayResize(out, m + 1);
      out[m] = sym;
   }

   return ArraySize(out);
}

//============================== MOMENTUM ===============================

// Retorno dos ultimos 'trading_days' dias uteis em D1: (preco_agora -
// preco_entao) / preco_entao. Usa shift 1 (ultima barra fechada) como
// "agora" para nao depender da barra do dia corrente ainda em formacao.
bool GetMomentum(const string symbol, const int trading_days, double &momentum)
{
   int bars = iBars(symbol, PERIOD_D1);
   if (bars < trading_days + 2)
      return false;

   double price_now  = iClose(symbol, PERIOD_D1, 1);
   double price_then = iClose(symbol, PERIOD_D1, 1 + trading_days);
   if (price_now <= 0.0 || price_then <= 0.0)
      return false;

   momentum = (price_now - price_then) / price_then;
   return true;
}

int BuildPerformanceList(SymbolPerf &list[])
{
   ArrayResize(list, 0);

   for (int i = 0; i < ArraySize(g_universe); i++)
   {
      string sym = g_universe[i];
      double mom;
      if (!GetMomentum(sym, InpMomentumTradingDays, mom))
         continue;

      int n = ArraySize(list);
      ArrayResize(list, n + 1);
      list[n].symbol   = sym;
      list[n].momentum = mom;
   }

   return ArraySize(list);
}

// Selection sort decrescente por momentum -- universo pequeno (dezenas de
// simbolos), O(n^2) e suficiente e mantem o codigo simples.
void SortPerfDesc(SymbolPerf &list[])
{
   int n = ArraySize(list);
   for (int i = 0; i < n - 1; i++)
   {
      int best = i;
      for (int j = i + 1; j < n; j++)
         if (list[j].momentum > list[best].momentum)
            best = j;
      if (best != i)
      {
         SymbolPerf tmp = list[i];
         list[i] = list[best];
         list[best] = tmp;
      }
   }
}

//============================== SIZING ===============================

double NormalizeLotForSymbol(const string symbol, double lot)
{
   double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if (lot_step <= 0.0)
      lot_step = 0.01;

   lot = MathFloor(lot / lot_step) * lot_step;
   if (lot < min_lot) lot = min_lot;
   if (lot > max_lot) lot = max_lot;
   return NormalizeDouble(lot, 2);
}

// notional_por_lote ~= (preco / tick_size) * tick_value -- tick_value do
// MT5 ja embute a conversao de moeda de cotacao para moeda da conta, entao
// a formula vale para qualquer par sem precisar converter moedas na mao
// (ver limitacoes na secao 4 do .md).
double CalcLotForWeight(const string symbol, const double weight_percent)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double notional_target = balance * weight_percent / 100.0;

   double price      = SymbolInfoDouble(symbol, SYMBOL_BID);
   double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if (price <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   double notional_per_lot = (price / tick_size) * tick_value;
   if (notional_per_lot <= 0.0)
      return 0.0;

   return NormalizeLotForSymbol(symbol, notional_target / notional_per_lot);
}

bool SpreadOkFor(const string symbol)
{
   double spread_points = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   return (spread_points <= InpMaxSpreadPoints);
}

//============================== POSICOES ===============================

bool SymbolInList(const string symbol, const string &list[])
{
   for (int i = 0; i < ArraySize(list); i++)
      if (list[i] == symbol)
         return true;
   return false;
}

// direction: 1 = comprado, -1 = vendido. Retorna false se nao ha posicao
// nossa (magic) aberta nesse simbolo.
bool GetOpenPositionForSymbol(const string symbol, int &direction)
{
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      return true;
   }
   return false;
}

// Fecha toda posicao nossa cujo (simbolo, direcao) nao esteja mais na
// lista-alvo do rebalanceamento atual -- cobre tanto "saiu do ranking"
// quanto "inverteu de direcao" (era comprado, virou candidato a venda).
void CloseUntargeted(const string &longList[], const string &shortList[])
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      int direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;

      bool keep = (direction == 1) ? SymbolInList(symbol, longList) : SymbolInList(symbol, shortList);
      if (keep)
         continue;

      g_lastCloseReason = "REBALANCE_ROTATED_OUT";
      trade.SetTypeFillingBySymbol(symbol);
      if (!trade.PositionClose(ticket))
      {
         g_lastCloseReason = "";
         PrintFormat("[EXIT-FAIL] %s ticket=%I64u retcode=%d", symbol, ticket, trade.ResultRetcode());
      }
   }
}

bool OpenMarketPosition(const string symbol, const int direction, const double weight_percent)
{
   if (!SpreadOkFor(symbol))
   {
      if (InpVerboseLog)
         PrintFormat("[SKIP] %s spread acima do limite, nao abriu", symbol);
      return false;
   }

   double lot = CalcLotForWeight(symbol, weight_percent);
   if (lot <= 0.0)
   {
      if (InpVerboseLog)
         PrintFormat("[SKIP] %s lote invalido (peso=%.2f%%)", symbol, weight_percent);
      return false;
   }

   MqlTick tick;
   if (!SymbolInfoTick(symbol, tick))
      return false;

   trade.SetTypeFillingBySymbol(symbol);

   double sl = 0.0;
   if (InpHardStopPercent > 0.0)
   {
      double price = (direction == 1) ? tick.ask : tick.bid;
      double dist  = price * InpHardStopPercent / 100.0;
      sl = (direction == 1) ? price - dist : price + dist;
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }

   bool ok = (direction == 1)
             ? trade.Buy(lot, symbol, 0.0, sl, 0.0, "MOMENTUM_FX")
             : trade.Sell(lot, symbol, 0.0, sl, 0.0, "MOMENTUM_FX");

   if (!ok)
   {
      PrintFormat("[ENTRY-FAIL] %s retcode=%d desc=%s", symbol, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
   }

   g_totalTradesOpened++;
   if (InpVerboseLog)
      PrintFormat("[ENTRY] %s %s lot=%.2f peso=%.2f%%", symbol, (direction == 1 ? "BUY" : "SELL"), lot, weight_percent);
   return true;
}

// Abre posicao para os simbolos da lista que ainda nao tem posicao nossa
// (os que tinham posicao na direcao errada ja foram fechados em
// CloseUntargeted antes desta funcao ser chamada).
void OpenTargeted(const string &list[], const int direction, const double weight_percent)
{
   for (int i = 0; i < ArraySize(list); i++)
   {
      string symbol = list[i];
      int existingDir;
      if (GetOpenPositionForSymbol(symbol, existingDir))
         continue;
      OpenMarketPosition(symbol, direction, weight_percent);
   }
}

void CloseAllPositions(const string reason)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      g_lastCloseReason = reason;
      trade.SetTypeFillingBySymbol(symbol);
      if (!trade.PositionClose(ticket))
      {
         g_lastCloseReason = "";
         PrintFormat("[EXIT-FAIL] %s ticket=%I64u motivo=%s retcode=%d", symbol, ticket, reason, trade.ResultRetcode());
      }
   }
}

//============================== REBALANCEAMENTO ===============================

datetime AddMonths(const datetime base, const int months)
{
   MqlDateTime dt;
   TimeToStruct(base, dt);

   int total_months = (dt.mon - 1) + months;
   dt.year += total_months / 12;
   dt.mon   = (total_months % 12) + 1;
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;

   return StructToTime(dt);
}

string ArrayToPipeList(const string &list[])
{
   string s = "";
   for (int i = 0; i < ArraySize(list); i++)
   {
      if (i > 0) s += "|";
      s += list[i];
   }
   return s;
}

void ExportRebalanceRow(const string &longList[], const string &shortList[], const int n_ready)
{
   if (g_csvRebalanceHandle == INVALID_HANDLE)
      return;

   FileWrite(g_csvRebalanceHandle, TimeToString(TimeCurrent(), TIME_DATE), n_ready,
             ArrayToPipeList(longList), ArrayToPipeList(shortList));
   FileFlush(g_csvRebalanceHandle);
}

void DoRebalance()
{
   SymbolPerf perf[];
   int n = BuildPerformanceList(perf);
   if (n < InpMinUniverseReady)
   {
      if (InpVerboseLog)
         PrintFormat("[REBALANCE-SKIP] apenas %d/%d simbolos com historico suficiente (minimo %d)",
                     n, ArraySize(g_universe), InpMinUniverseReady);
      return;
   }

   SortPerfDesc(perf);

   int topCount = (int)MathMax(1.0, MathRound(n * InpTopPercent / 100.0));
   int bottomCount = 0;
   if (InpAllowShort)
      bottomCount = (int)MathMax(1.0, MathRound(n * InpBottomPercent / 100.0));

   if (topCount + bottomCount > n)
   {
      if (InpVerboseLog)
         Print("[REBALANCE-WARN] InpTopPercent + InpBottomPercent excede o universo pronto, ajustando bottomCount");
      bottomCount = MathMax(0, n - topCount);
   }

   string longList[];
   ArrayResize(longList, topCount);
   for (int i = 0; i < topCount; i++)
      longList[i] = perf[i].symbol;

   string shortList[];
   ArrayResize(shortList, bottomCount);
   for (int i = 0; i < bottomCount; i++)
      shortList[i] = perf[n - 1 - i].symbol;

   int totalSlots = topCount + bottomCount;
   double weight = MathMin(InpGrossExposurePercent / totalSlots, InpMaxSymbolWeightPercent);

   CloseUntargeted(longList, shortList);
   OpenTargeted(longList, 1, weight);
   if (bottomCount > 0)
      OpenTargeted(shortList, -1, weight);

   g_rebalanceCount++;

   if (InpVerboseLog)
   {
      PrintFormat("[REBALANCE #%d] universo_pronto=%d topN=%d bottomN=%d peso=%.2f%%",
                  g_rebalanceCount, n, topCount, bottomCount, weight);

      string longStr = "";
      for (int i = 0; i < topCount; i++)
         longStr += StringFormat("%s(%.2f%%) ", longList[i], perf[i].momentum * 100.0);
      Print("[REBALANCE] LONG: ", longStr);

      if (bottomCount > 0)
      {
         string shortStr = "";
         for (int i = 0; i < bottomCount; i++)
            shortStr += StringFormat("%s(%.2f%%) ", shortList[i], perf[n - 1 - i].momentum * 100.0);
         Print("[REBALANCE] SHORT: ", shortStr);
      }
   }

   ExportRebalanceRow(longList, shortList, n);
}

//============================== GOVERNANCA DE PORTFOLIO ===============================

void UpdateEquityDrawdown()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if (eq > g_equityPeak)
      g_equityPeak = eq;

   double dd = g_equityPeak - eq;
   if (dd > g_maxDrawdown)
      g_maxDrawdown = dd;
}

void CheckMaxDrawdownKillSwitch()
{
   if (g_killSwitchActive || InpMaxDrawdownPercent <= 0.0 || g_equityPeak <= 0.0)
      return;

   double ddPercent = (g_equityPeak - AccountInfoDouble(ACCOUNT_EQUITY)) / g_equityPeak * 100.0;
   if (ddPercent < InpMaxDrawdownPercent)
      return;

   g_killSwitchActive = true;
   PrintFormat("[KILL-SWITCH] drawdown %.2f%% >= limite %.2f%% -- pausando novos rebalanceamentos",
               ddPercent, InpMaxDrawdownPercent);

   if (InpFlattenOnMaxDrawdown)
      CloseAllPositions("MAX_DRAWDOWN_KILL");
}

//============================== RELOGIO (NOVA BARRA D1) ===============================

bool IsNewAnchorBar()
{
   static datetime last_time = 0;
   datetime t[1];
   if (CopyTime(_Symbol, PERIOD_D1, 0, 1, t) <= 0)
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

   string filename = "MOMENTUM_FX_" + IntegerToString((int)InpMagicNumber) + ".csv";
   g_csvHandle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if (g_csvHandle != INVALID_HANDLE)
      FileWrite(g_csvHandle, "datetime", "symbol", "profit", "exit_reason");
   else if (InpVerboseLog)
      PrintFormat("[CSV] Falha ao abrir arquivo %s erro=%d", filename, GetLastError());

   string filenameReb = "MOMENTUM_FX_REBALANCES_" + IntegerToString((int)InpMagicNumber) + ".csv";
   g_csvRebalanceHandle = FileOpen(filenameReb, FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if (g_csvRebalanceHandle != INVALID_HANDLE)
      FileWrite(g_csvRebalanceHandle, "datetime", "n_ready", "long_list", "short_list");
   else if (InpVerboseLog)
      PrintFormat("[CSV] Falha ao abrir arquivo %s erro=%d", filenameReb, GetLastError());
}

void ExportTradeRow(const datetime t, const string symbol, const double profit, const string reason)
{
   if (g_csvHandle == INVALID_HANDLE)
      return;

   FileWrite(g_csvHandle, TimeToString(t, TIME_DATE | TIME_SECONDS), symbol, DoubleToString(profit, 2), reason);
   FileFlush(g_csvHandle);
}

void PrintFinalReport()
{
   double profit_factor = (g_grossLoss > 0.0) ? g_grossProfit / g_grossLoss : 0.0;
   double expectancy = (g_totalTradesClosed > 0) ? g_totalProfit / g_totalTradesClosed : 0.0;

   Print("================ RELATORIO FINAL ================");
   PrintFormat("Rebalanceamentos executados:  %d", g_rebalanceCount);
   PrintFormat("Trades abertos:                %d", g_totalTradesOpened);
   PrintFormat("Trades fechados:                %d", g_totalTradesClosed);
   PrintFormat("Trades vencedores:              %d", g_totalWins);
   PrintFormat("Trades perdedores:              %d", g_totalLosses);
   PrintFormat("Profit Factor:                  %.2f", profit_factor);
   PrintFormat("Lucro total:                    %.2f", g_totalProfit);
   PrintFormat("Drawdown maximo (equity):       %.2f", g_maxDrawdown);
   PrintFormat("Expectativa por trade:          %.2f", expectancy);
   PrintFormat("Kill-switch acionado:           %s", (g_killSwitchActive ? "SIM" : "NAO"));
   Print("===================================================");
}

//============================== EVENTOS MT5 ===============================

int OnInit()
{
   int n = ParseUniverse(InpUniverse, g_universe);
   if (n < InpMinUniverseReady)
   {
      Alert("Universo com poucos simbolos validos no broker: ", n, " (minimo ", InpMinUniverseReady, ")");
      return INIT_FAILED;
   }

   if (InpAllowShort && InpTopPercent + InpBottomPercent > 100.0)
   {
      Alert("InpTopPercent + InpBottomPercent nao pode exceder 100%.");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   g_equityPeak        = AccountInfoDouble(ACCOUNT_EQUITY);
   g_maxDrawdown        = 0.0;
   g_killSwitchActive   = false;
   g_nextRebalanceTime  = 0; // forca rebalanceamento na primeira barra nova
   g_rebalanceCount     = 0;

   g_csvHandle          = INVALID_HANDLE;
   g_csvRebalanceHandle = INVALID_HANDLE;
   OpenCSV();

   PrintFormat("[INIT] universo=%d simbolos validos, momentum=%d dias uteis, rebalance a cada %d meses",
               n, InpMomentumTradingDays, InpRebalanceMonths);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFinalReport();

   if (g_csvHandle != INVALID_HANDLE)
      FileClose(g_csvHandle);
   if (g_csvRebalanceHandle != INVALID_HANDLE)
      FileClose(g_csvRebalanceHandle);
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &res)
{
   if (trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if (!HistoryDealSelect(trans.deal))
      return;

   long deal_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if (deal_magic != InpMagicNumber)
      return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if (entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                  + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   long deal_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   string exit_reason = g_lastCloseReason;
   if (exit_reason == "")
      exit_reason = (deal_reason == DEAL_REASON_SL) ? "HARD_STOP" : "UNKNOWN";
   g_lastCloseReason = "";

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

   if (InpVerboseLog)
      PrintFormat("[EXIT] %s ticket=%I64u profit=%.2f motivo=%s", symbol, trans.deal, profit, exit_reason);

   ExportTradeRow(TimeCurrent(), symbol, profit, exit_reason);
}

void OnTick()
{
   UpdateEquityDrawdown();
   CheckMaxDrawdownKillSwitch();

   if (g_killSwitchActive)
      return;

   if (!IsNewAnchorBar())
      return;

   if (TimeCurrent() < g_nextRebalanceTime)
      return;

   DoRebalance();
   g_nextRebalanceTime = AddMonths(TimeCurrent(), InpRebalanceMonths);
}
//+------------------------------------------------------------------+
