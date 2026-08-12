//+------------------------------------------------------------------+
//| expert-index.mq5                                                  |
//| EA: CTA Trend-Following -- diferenca entre EWMAs, normalizada     |
//| pelo desvio-padrao do proprio sinal e limitada por clip.          |
//| Port do Pine Script v6 fornecido em logs.txt.                     |
//| Especificacao: ESTRATEGIA_CTA_TREND_FOLLOWING.md.                 |
//|                                                                    |
//| Calcula apenas com candles fechados. Por padrao usa D1, pois tau  |
//| foi definido em dias no modelo original. Mantem uma unica posicao |
//| por simbolo/magic e a inverte quando o sinal troca de polaridade. |
//|                                                                    |
//| ATENCAO: AutoTrade=false por padrao. Teste no Strategy Tester e   |
//| em conta demo antes de habilitar ordens reais.                     |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//============================== INPUTS ===============================

input ulong  InpMagicNumber       = 20260804; // Magic Number
input int    InpSlippagePoints    = 30;       // Slippage maximo (pontos)
input bool   AutoTrade            = false;    // Precisa ligar explicitamente
input bool   InpVerboseLog        = true;     // Diagnostico a cada nova barra

input string Inp_Sep1             = "--- Modelo CTA ---"; // ---
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_D1; // Timeframe do modelo (D1 = tau em dias)
input int    InpTau               = 5;        // Horizonte rapido (tau)
input int    InpSlowMultiplier    = 4;        // Periodo lento = tau * multiplicador
input int    InpNormMultiplier    = 16;       // Normalizacao = tau * multiplicador
input double InpClipValue         = 2.0;      // Limite do sinal (+/- desvios-padrao)
input double InpSignalDeadZone    = 0.0;      // |sinal| abaixo disto fica neutro

input string Inp_Sep2             = "--- Posicao / Risco ---"; // ---
input bool   InpUseVolatilitySizing = true;  // Dimensionar lote por EWMA do movimento absoluto
input double InpDailyRiskPercent    = 0.50;  // Risco monetario para 1 EWMA-vol com sinal no clip
input double InpFixedLot             = 0.10;  // Lote quando sizing por volatilidade esta desligado
input double InpMaxLot               = 10.0;  // Teto adicional de lote (0 = somente limite do broker)

input string Inp_Sep3             = "--- Execucao ---"; // ---
input double InpMaxSpreadPoints   = 0.0;      // Spread maximo (0 = desliga filtro)
input bool   InpCloseOnNeutral    = false;    // Fecha se sinal entrar na zona neutra

//============================== GLOBALS ===============================

CTrade trade;

int      g_fastHandle = INVALID_HANDLE;
int      g_slowHandle = INVALID_HANDLE;
datetime g_lastSignalBar = 0;

//============================== UTILITARIOS ===============================

int VolumeDigits(const double step)
{
   if (step >= 1.0)
      return 0;

   int digits = 0;
   double scaled = step;
   while (digits < 8 && MathAbs(scaled - MathRound(scaled)) > 1e-8)
   {
      scaled *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeLots(double lots)
{
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0.0 || min_lot <= 0.0 || max_lot <= 0.0)
      return 0.0;

   if (InpMaxLot > 0.0)
      max_lot = MathMin(max_lot, InpMaxLot);

   lots = MathMin(lots, max_lot);
   lots = MathFloor((lots + 1e-12) / step) * step;
   if (lots < min_lot)
      return 0.0;

   return NormalizeDouble(lots, VolumeDigits(step));
}

bool SpreadOk()
{
   if (InpMaxSpreadPoints <= 0.0)
      return true;
   return ((double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints);
}

// direction: +1 compra, -1 venda, 0 sem posicao desta EA.
int GetOwnPositionDirection()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   }
   return 0;
}

bool HasForeignPositionOnSymbol()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         return true;
   }
   return false;
}

bool CloseOwnPositions(const string reason)
{
   bool all_ok = true;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      if (!trade.PositionClose(ticket))
      {
         all_ok = false;
         PrintFormat("[EXIT-FAIL] ticket=%I64u motivo=%s retcode=%u desc=%s",
                     ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      }
      else if (InpVerboseLog)
         PrintFormat("[EXIT] ticket=%I64u motivo=%s", ticket, reason);
   }
   return all_ok;
}

//============================== MODELO CTA ===============================

// CopyBuffer start_pos=1 equivale ao close[1] do Pine: a barra corrente
// nunca participa. O desvio-padrao usa a populacao (divisor N), igual ao
// comportamento padrao de ta.stdev(..., biased=true).
bool CalculateSignal(double &signal, double &raw, double &std_dev,
                     double &fast_now, double &slow_now)
{
   int norm_period = InpTau * InpNormMultiplier;

   double fast[];
   double slow[];
   ArrayResize(fast, norm_period);
   ArrayResize(slow, norm_period);
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if (CopyBuffer(g_fastHandle, 0, 1, norm_period, fast) != norm_period ||
       CopyBuffer(g_slowHandle, 0, 1, norm_period, slow) != norm_period)
      return false;

   fast_now = fast[0];
   slow_now = slow[0];

   double mean = 0.0;
   for (int i = 0; i < norm_period; i++)
      mean += fast[i] - slow[i];
   mean /= norm_period;

   double variance = 0.0;
   for (int i = 0; i < norm_period; i++)
   {
      double delta = (fast[i] - slow[i]) - mean;
      variance += delta * delta;
   }
   variance /= norm_period;
   std_dev = MathSqrt(MathMax(variance, 0.0));

   double s_tilde = fast_now - slow_now;
   raw = (std_dev > 0.0) ? s_tilde / std_dev : 0.0;
   signal = MathMax(-InpClipValue, MathMin(InpClipValue, raw));
   if (MathAbs(signal) < InpSignalDeadZone)
      signal = 0.0;

   return true;
}

// EWMA de abs(close[1]-close[2]) com alpha=2/(periodo+1).
// A serie e reconstruida em ordem cronologica e sem barra corrente.
bool CalculateAssetVolatility(double &volatility)
{
   int norm_period = InpTau * InpNormMultiplier;
   int warmup = MathMax(norm_period * 5, norm_period + 2);

   double closes[];
   ArrayResize(closes, warmup + 1);
   ArraySetAsSeries(closes, true);
   int copied = CopyClose(_Symbol, InpSignalTimeframe, 1, warmup + 1, closes);
   if (copied < norm_period + 2)
      return false;

   double alpha = 2.0 / (norm_period + 1.0);
   int oldest_return_index = copied - 2;
   volatility = MathAbs(closes[oldest_return_index] - closes[oldest_return_index + 1]);

   for (int i = oldest_return_index - 1; i >= 0; i--)
   {
      double absolute_return = MathAbs(closes[i] - closes[i + 1]);
      volatility = alpha * absolute_return + (1.0 - alpha) * volatility;
   }
   return true;
}

double CalculateLots(const double signal, const double volatility)
{
   if (!InpUseVolatilitySizing)
      return NormalizeLots(InpFixedLot);
   if (volatility <= 0.0 || InpClipValue <= 0.0)
      return 0.0;

   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if (tick_size <= 0.0 || tick_value <= 0.0)
      return 0.0;

   double risk_budget = AccountInfoDouble(ACCOUNT_EQUITY) * InpDailyRiskPercent / 100.0;
   double loss_per_lot_at_one_vol = (volatility / tick_size) * tick_value;
   double signal_fraction = MathMin(1.0, MathAbs(signal) / InpClipValue);
   if (loss_per_lot_at_one_vol <= 0.0)
      return 0.0;

   return NormalizeLots((risk_budget * signal_fraction) / loss_per_lot_at_one_vol);
}

//============================== EXECUCAO ===============================

void ProcessClosedBar()
{
   double signal, raw, std_dev, fast, slow;
   if (!CalculateSignal(signal, raw, std_dev, fast, slow))
   {
      if (InpVerboseLog)
         PrintFormat("[WAIT] indicadores ainda sem historico suficiente, erro=%d", GetLastError());
      return;
   }

   double volatility = 0.0;
   if (!CalculateAssetVolatility(volatility))
   {
      if (InpVerboseLog)
         Print("[WAIT] historico insuficiente para EWMA de volatilidade");
      return;
   }

   int wanted_direction = (signal > 0.0) ? 1 : ((signal < 0.0) ? -1 : 0);
   int current_direction = GetOwnPositionDirection();

   if (InpVerboseLog)
      PrintFormat("[CTA] barra=%s fast=%.8f slow=%.8f std=%.8f raw=%.4f signal=%.4f vol=%.8f atual=%d alvo=%d",
                  TimeToString(iTime(_Symbol, InpSignalTimeframe, 1)),
                  fast, slow, std_dev, raw, signal, volatility,
                  current_direction, wanted_direction);

   if (wanted_direction == 0)
   {
      if (InpCloseOnNeutral && current_direction != 0)
         CloseOwnPositions("SIGNAL_NEUTRAL");
      return;
   }

   if (current_direction == wanted_direction)
      return;

   if (current_direction != 0 && !CloseOwnPositions("SIGNAL_FLIP"))
      return;

   // Em conta netting, uma ordem desta EA se fundiria com uma posicao manual
   // ou de outra EA no mesmo simbolo. Bloqueamos esse caso.
   if (HasForeignPositionOnSymbol())
   {
      Print("[BLOCKED] existe posicao de outro magic no simbolo");
      return;
   }

   if (!SpreadOk())
   {
      if (InpVerboseLog)
         Print("[BLOCKED] spread acima do limite");
      return;
   }

   double lots = CalculateLots(signal, volatility);
   if (lots <= 0.0)
   {
      Print("[BLOCKED] lote calculado abaixo do minimo ou dados de tick invalidos");
      return;
   }

   bool ok = (wanted_direction > 0)
             ? trade.Buy(lots, _Symbol, 0.0, 0.0, 0.0, "CTA_TREND")
             : trade.Sell(lots, _Symbol, 0.0, 0.0, 0.0, "CTA_TREND");

   if (!ok)
      PrintFormat("[ENTRY-FAIL] direcao=%d lote=%.*f retcode=%u desc=%s",
                  wanted_direction, VolumeDigits(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)),
                  lots, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   else if (InpVerboseLog)
      PrintFormat("[ENTRY] %s lote=%.*f signal=%.4f",
                  (wanted_direction > 0 ? "BUY" : "SELL"),
                  VolumeDigits(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)), lots, signal);
}

//============================== EVENTOS MT5 ===============================

int OnInit()
{
   if (InpTau < 1 || InpSlowMultiplier < 2 || InpNormMultiplier < 4 ||
       InpClipValue < 0.5 || InpSignalDeadZone < 0.0 ||
       InpSignalDeadZone >= InpClipValue || InpDailyRiskPercent < 0.0 ||
       InpFixedLot <= 0.0 || InpMaxLot < 0.0)
   {
      Alert("Parametros invalidos. Revise tau, multiplicadores, clip, zona neutra, risco e lotes.");
      return INIT_PARAMETERS_INCORRECT;
   }

   int slow_period = InpTau * InpSlowMultiplier;
   int norm_period = InpTau * InpNormMultiplier;
   if (slow_period <= InpTau || norm_period <= 1)
      return INIT_PARAMETERS_INCORRECT;

   g_fastHandle = iMA(_Symbol, InpSignalTimeframe, InpTau, 0, MODE_EMA, PRICE_CLOSE);
   g_slowHandle = iMA(_Symbol, InpSignalTimeframe, slow_period, 0, MODE_EMA, PRICE_CLOSE);
   if (g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE)
   {
      PrintFormat("ERRO: falha ao criar handles EMA, GetLastError=%d", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA calcula, mas nao envia ordens.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_fastHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastHandle);
   if (g_slowHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowHandle);
}

void OnTick()
{
   datetime bar_time = iTime(_Symbol, InpSignalTimeframe, 0);
   if (bar_time <= 0 || bar_time == g_lastSignalBar)
      return;
   g_lastSignalBar = bar_time;

   if (!AutoTrade)
      return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return;

   int required_bars = InpTau * InpNormMultiplier + InpTau * InpSlowMultiplier + 10;
   if (Bars(_Symbol, InpSignalTimeframe) < required_bars)
   {
      if (InpVerboseLog)
         PrintFormat("[WAIT] barras insuficientes: atual=%d minimo=%d",
                     Bars(_Symbol, InpSignalTimeframe), required_bars);
      return;
   }

   ProcessClosedBar();
}
//+------------------------------------------------------------------+
