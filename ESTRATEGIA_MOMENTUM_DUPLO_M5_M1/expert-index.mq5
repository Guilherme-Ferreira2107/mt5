//+------------------------------------------------------------------+
//| expert-index.mq5                                                  |
//| EA: Momentum Duplo -- vies do timeframe de referencia (iMomentum) |
//| define a direcao, gatilho do timeframe alvo (iMomentum mais       |
//| rapido) cronometra a entrada num pullback A FAVOR dessa direcao.  |
//| Nao e reversao pura (perigosa no timeframe alvo, onde ruido/      |
//| spread dominam mais) nem continuacao pura (perseguir a forca      |
//| local vira comprar o topo) -- e um hibrido dos dois.               |
//| Especificacao completa: ESTRATEGIA_MOMENTUM_DUPLO_M5_M1.md        |
//| (mesma pasta).                                                     |
//|                                                                    |
//| Arquitetura "lite" (baseada em rsi_extremo_lite.mq5, na raiz do   |
//| repo): sem CSV, sem governanca diaria, sem OnTradeTransaction --  |
//| so o essencial para operar EURUSD nas janelas de maior            |
//| volatilidade do dia. O bloco de sessoes (Londres+NY, Asia         |
//| disponivel mas desligada por padrao) foi copiado de               |
//| ESTRATEGIA_ROMPIMENTO_LT_RETRACAO/expert-index.mq5 -- e o unico   |
//| jeito de cobrir 2 janelas nao contiguas (rsi_extremo_lite.mq5 so  |
//| tem 1 janela).                                                    |
//|                                                                    |
//| Simbolo alvo: EURUSD. Timeframes parametrizaveis via               |
//| InpTargetTimeframe (gatilho/entrada, default M1) e                |
//| InpBiasTimeframe (referencia/vies, default M5) -- ambos            |
//| independentes do periodo do grafico onde a EA esta anexada. O     |
//| OnInit exige que InpBiasTimeframe seja estritamente maior que     |
//| InpTargetTimeframe (senao a logica "vies maior + gatilho menor"   |
//| perde sentido).                                                    |
//|                                                                    |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Revise o codigo e teste em conta demo |
//| / Strategy Tester antes de usar em conta real.                    |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      ""
#property version   "1.00"
#property strict
#include <Trade/Trade.mqh>

//============================== INPUTS ===============================

input ulong  InpMagicNumber       = 20260803;  // Magic Number
input int    InpSlippagePoints    = 20;        // Slippage maximo (pontos)
input bool   AutoTrade            = false;     // precisa ligar explicitamente
input bool   DebugLog             = true;      // imprime diagnostico a cada candle fechado

input string Inp_Sep1                  = "--- Momentum Vies (timeframe maior) ---"; // ---
input ENUM_TIMEFRAMES InpBiasTimeframe = PERIOD_M5; // Timeframe do vies
input int    InpMomentumBiasPeriod     = 14;        // Periodo do iMomentum de vies

input string Inp_Sep2                    = "--- Momentum Gatilho (timeframe alvo) ---"; // ---
input ENUM_TIMEFRAMES InpTargetTimeframe = PERIOD_M1; // Timeframe alvo (entrada) -- precisa ser MENOR que InpBiasTimeframe
input int    InpMomentumTriggerPeriod    = 6;    // Periodo do iMomentum de gatilho
input double InpMinPullbackDistance      = 0.05; // Distancia minima de 100 antes do cruzamento contar como pullback (calibrar -- ver .md)

input string Inp_Sep3                  = "--- Sessoes (horario do servidor) ---"; // ---
input bool   UsarAsia       = false;     // Operar sessao asiatica
input string AsiaInicio     = "00:00";   // Hora inicial Asia
input string AsiaFim        = "03:00";   // Hora final Asia
input bool   UsarLondres    = true;      // Operar sessao Londres
input string LondresInicio  = "08:00";   // Hora inicial Londres
input string LondresFim     = "11:00";   // Hora final Londres
input bool   UsarNovaYork   = true;      // Operar sessao Nova York
input string NovaYorkInicio = "13:00";   // Hora inicial Nova York
input string NovaYorkFim    = "16:00";   // Hora final Nova York
input int    MaxCandlesInicioSessao = 0; // 0 desliga, >0 limita aos primeiros candles da sessao

input string Inp_Sep4                  = "--- Stop / Alvo ---"; // ---
input bool   InpUseFixedStopTarget = false; // usar stop/alvo fixos (em pontos) em vez do estrutural
input int    InpStructuralLookback = 10;    // candles do timeframe alvo p/ minima/maxima recente (stop estrutural)
input double InpRiskRewardRatio    = 1.5;   // usado quando o stop e estrutural
input double InpFixedStopPoints    = 150.0; // Stop fixo (pontos), se InpUseFixedStopTarget
input double InpFixedTargetPoints  = 300.0; // Alvo fixo (pontos), se InpUseFixedStopTarget

input string Inp_Sep5                  = "--- Risco ---"; // ---
input double InpRiskPercent = 1.0; // % do saldo arriscado por trade

input string Inp_Sep6                  = "--- Spread ---"; // ---
input double InpMaxSpreadPoints = 20.0; // Spread maximo permitido (pontos, calibrar por corretora)

input string Inp_Sep7                  = "--- Saida ---"; // ---
input bool InpCloseOnOppositeBias = true; // fecha a posicao se o vies do M5 inverter
input bool InpCloseAtSessionEnd   = true; // fecha a posicao ao sair da janela de sessao (inclui o intervalo Londres->NY)

//============================== GLOBALS ===============================

CTrade trade;

int g_momBiasHandle    = INVALID_HANDLE;
int g_momTriggerHandle = INVALID_HANDLE;

//============================== SESSAO / HORARIO ===============================
// Copiado de ESTRATEGIA_ROMPIMENTO_LT_RETRACAO/expert-index.mq5 --
// suporta ate 3 janelas nao contiguas (aqui usamos Londres+NY, Asia
// fica disponivel mas desligada por padrao).

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

   int period_seconds = PeriodSeconds(InpTargetTimeframe);
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

//============================== RISCO / POSICAO ===============================
// Adaptado de rsi_extremo_lite.mq5 (Highest/Lowest/LotsForRisk/HasOpenPosition).

double Highest(int shift, int count)
{
   int idx = iHighest(_Symbol, InpTargetTimeframe, MODE_HIGH, count, shift);
   return idx >= 0 ? iHigh(_Symbol, InpTargetTimeframe, idx) : 0.0;
}

double Lowest(int shift, int count)
{
   int idx = iLowest(_Symbol, InpTargetTimeframe, MODE_LOW, count, shift);
   return idx >= 0 ? iLow(_Symbol, InpTargetTimeframe, idx) : 0.0;
}

double LotsForRisk(double stopDistance)
{
   if (stopDistance <= 0) return 0.0;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0) return 0.0;
   double lots = riskAmount / (stopDistance / tickSize * tickValue);

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0) step = 0.01;

   int decimals = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   lots = NormalizeDouble(MathFloor(lots / step) * step, decimals);

   if (lots > maxLot) lots = NormalizeDouble(MathFloor(maxLot / step) * step, decimals);
   return lots < minLot ? 0.0 : lots;
}

bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
      return true;
   }
   return false;
}

bool SpreadOk()
{
   double spread_points = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread_points <= InpMaxSpreadPoints);
}

//============================== MOMENTUM (VIES + GATILHO) ===============================

// Vies: ultimo valor fechado do iMomentum no timeframe maior. > 100 =
// alta, < 100 = baixa (Larry Williams: preco atual / preco N periodos
// atras * 100).
bool GetBias(double &biasValue)
{
   double buf[1];
   if (CopyBuffer(g_momBiasHandle, 0, 1, 1, buf) <= 0)
      return false;
   biasValue = buf[0];
   return true;
}

// Gatilho: 2 ultimas barras fechadas do iMomentum no timeframe alvo,
// para detectar o cruzamento de volta por 100 (fim do pullback).
bool GetTrigger(double &prev, double &last)
{
   double buf[2];
   ArraySetAsSeries(buf, true);
   if (CopyBuffer(g_momTriggerHandle, 0, 1, 2, buf) <= 0)
      return false;
   last = buf[0]; // ultima barra fechada
   prev = buf[1]; // barra anterior a essa
   return true;
}

//============================== GESTAO DE POSICAO ABERTA ===============================

void ManageOpenPosition()
{
   if (!InpCloseOnOppositeBias && !InpCloseAtSessionEnd)
      return;

   double bias = 0.0;
   bool haveBias = InpCloseOnOppositeBias && GetBias(bias);
   bool sessionEnded = InpCloseAtSessionEnd && !IsWithinTradingWindow();

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      string reason = "";

      if (sessionEnded)
         reason = "SESSION_END";
      else if (haveBias)
      {
         if (posType == POSITION_TYPE_BUY && bias < 100.0)
            reason = "BIAS_FLIP";
         else if (posType == POSITION_TYPE_SELL && bias > 100.0)
            reason = "BIAS_FLIP";
      }

      if (reason == "")
         continue;

      if (!trade.PositionClose(ticket))
         PrintFormat("[EXIT-FAIL] ticket=%I64u motivo=%s retcode=%d", ticket, reason, trade.ResultRetcode());
      else if (DebugLog)
         PrintFormat("[EXIT] ticket=%I64u motivo=%s", ticket, reason);
   }
}

//============================== EVENTOS MT5 ===============================

int OnInit()
{
   if (_Symbol != "EURUSD" && DebugLog)
      PrintFormat("AVISO: esta EA foi desenhada para EURUSD; simbolo atual=%s -- revise spread/stop antes de usar em outro par.", _Symbol);

   if (PeriodSeconds(InpBiasTimeframe) <= PeriodSeconds(InpTargetTimeframe))
   {
      Alert("InpBiasTimeframe precisa ser um timeframe MAIOR que InpTargetTimeframe -- senao a logica de vies maior + gatilho menor nao faz sentido.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_momBiasHandle = iMomentum(_Symbol, InpBiasTimeframe, InpMomentumBiasPeriod, PRICE_CLOSE);
   if (g_momBiasHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handle do momentum de vies. GetLastError=", GetLastError());
      return INIT_FAILED;
   }

   g_momTriggerHandle = iMomentum(_Symbol, InpTargetTimeframe, InpMomentumTriggerPeriod, PRICE_CLOSE);
   if (g_momTriggerHandle == INVALID_HANDLE)
   {
      Print("ERRO: falha ao criar handle do momentum de gatilho. GetLastError=", GetLastError());
      return INIT_FAILED;
   }

   int dummyMinutes;
   bool horariosValidos = true;
   if (UsarAsia)     horariosValidos = horariosValidos && ParseTimeToMinutes(AsiaInicio, dummyMinutes) && ParseTimeToMinutes(AsiaFim, dummyMinutes);
   if (UsarLondres)  horariosValidos = horariosValidos && ParseTimeToMinutes(LondresInicio, dummyMinutes) && ParseTimeToMinutes(LondresFim, dummyMinutes);
   if (UsarNovaYork) horariosValidos = horariosValidos && ParseTimeToMinutes(NovaYorkInicio, dummyMinutes) && ParseTimeToMinutes(NovaYorkFim, dummyMinutes);
   if (!horariosValidos)
   {
      Alert("Horario invalido nas sessoes. Use o formato HH:MM.");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippagePoints);

   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA nao vai enviar ordens ate voce ligar este input.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_momBiasHandle != INVALID_HANDLE)    IndicatorRelease(g_momBiasHandle);
   if (g_momTriggerHandle != INVALID_HANDLE) IndicatorRelease(g_momTriggerHandle);
}

void OnTick()
{
   if (!AutoTrade) return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) return;

   if (HasOpenPosition())
   {
      ManageOpenPosition();
      return; // nao abre e fecha no mesmo tick
   }

   if (!IsWithinTradingWindow())
      return;

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpTargetTimeframe, 0);
   if (currentBarTime == lastBarTime)
      return; // so avalia uma vez por candle do timeframe alvo fechado
   lastBarTime = currentBarTime;

   int minBarsTarget = MathMax(InpMomentumTriggerPeriod, InpStructuralLookback) + 3;
   if (Bars(_Symbol, InpTargetTimeframe) < minBarsTarget)
   {
      if (DebugLog) Print("AVISO: barras do timeframe alvo insuficientes (minimo=", minBarsTarget, ")");
      return;
   }
   if (Bars(_Symbol, InpBiasTimeframe) < InpMomentumBiasPeriod + 3)
   {
      if (DebugLog) Print("AVISO: barras do timeframe de vies insuficientes");
      return;
   }

   if (!SpreadOk())
   {
      if (DebugLog) Print("AVISO: spread acima do limite, sem entrada nesse candle");
      return;
   }

   double bias;
   if (!GetBias(bias))
   {
      Print("ERRO: CopyBuffer do momentum de vies falhou. GetLastError=", GetLastError());
      return;
   }

   double prevTrig, lastTrig;
   if (!GetTrigger(prevTrig, lastTrig))
   {
      Print("ERRO: CopyBuffer do momentum de gatilho falhou. GetLastError=", GetLastError());
      return;
   }

   bool biasBullish = bias > 100.0;
   bool biasBearish = bias < 100.0;

   // Compra: vies de alta no timeframe de referencia + timeframe alvo
   // saiu de um pullback (ficou <= 100 - distancia minima) e acabou de
   // cruzar de volta acima de 100 -- entra a favor da tendencia maior,
   // cronometrado pelo fim do recuo no timeframe alvo.
   bool buySignal  = biasBullish && (prevTrig <= 100.0 - InpMinPullbackDistance) && (lastTrig > 100.0);
   // Venda: espelho para vies de baixa.
   bool sellSignal = biasBearish && (prevTrig >= 100.0 + InpMinPullbackDistance) && (lastTrig < 100.0);

   if (DebugLog)
      PrintFormat("BARRA %s bias=%.5f prevTrig=%.5f lastTrig=%.5f buy=%s sell=%s",
                  TimeToString(currentBarTime), bias, prevTrig, lastTrig,
                  (buySignal ? "true" : "false"), (sellSignal ? "true" : "false"));

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if (buySignal)
   {
      double entry  = iClose(_Symbol, InpTargetTimeframe, 1);
      double stop   = InpUseFixedStopTarget ? entry - InpFixedStopPoints * point : Lowest(1, InpStructuralLookback);
      double target = InpUseFixedStopTarget ? entry + InpFixedTargetPoints * point
                                             : entry + (entry - stop) * InpRiskRewardRatio;
      double lots = LotsForRisk(entry - stop);
      if (lots <= 0.0)
      {
         if (DebugLog) Print("AVISO: lots calculado <= 0 no BUY (entry=", entry, " stop=", stop, "), ordem nao enviada.");
      }
      else if (!trade.Buy(lots, _Symbol, 0.0, stop, target))
         Print("ERRO ao enviar BUY: retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
   }
   else if (sellSignal)
   {
      double entry  = iClose(_Symbol, InpTargetTimeframe, 1);
      double stop   = InpUseFixedStopTarget ? entry + InpFixedStopPoints * point : Highest(1, InpStructuralLookback);
      double target = InpUseFixedStopTarget ? entry - InpFixedTargetPoints * point
                                             : entry - (stop - entry) * InpRiskRewardRatio;
      double lots = LotsForRisk(stop - entry);
      if (lots <= 0.0)
      {
         if (DebugLog) Print("AVISO: lots calculado <= 0 no SELL (entry=", entry, " stop=", stop, "), ordem nao enviada.");
      }
      else if (!trade.Sell(lots, _Symbol, 0.0, stop, target))
         Print("ERRO ao enviar SELL: retcode=", trade.ResultRetcode(), " desc=", trade.ResultRetcodeDescription());
   }
}
//+------------------------------------------------------------------+
