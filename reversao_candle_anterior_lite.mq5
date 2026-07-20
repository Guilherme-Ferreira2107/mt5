//+------------------------------------------------------------------+
//| reversao_candle_anterior_lite.mq5                                 |
//| EA lite: reversao do range do candle anterior. A cada candle      |
//| fechado, mantem uma ordem pendente Buy Limit na minima desse      |
//| candle, com TP na maxima do mesmo candle (cancela e reenvia a     |
//| pendente a cada novo candle, se ainda nao executada). Por padrao  |
//| nao ha stop de preco: se a posicao abrir e nao bater o alvo, e    |
//| fechada a mercado ao fechar o candle de numero CandlesToExit,     |
//| contando o candle de entrada. Com UseFixedStopTarget=true, stop e |
//| alvo passam a ser distancias fixas (pontos) a partir da entrada,  |
//| e a saida por tempo continua valendo como rede de seguranca.      |
//| ATENCAO: com AutoTrade=true e o AutoTrading do terminal ligado,   |
//| este EA envia ordens REAIS. Revise o codigo e teste em conta demo |
//| antes de usar em conta real.                                      |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input int CandlesToExit = 3;               // Candles (contando o de entrada) ate fechar a mercado se o alvo nao foi atingido
input bool UseMAFilter = false;            // ativar/desativar filtro de tendencia pela media movel
input int MAPeriod = 50;                   // Periodo da media movel de filtro de tendencia
input ENUM_MA_METHOD MAMethod = MODE_SMA;  // Metodo da media movel
input double RiskPercent = 0.1;            // % do saldo arriscado, calculado sobre a distancia minima-maxima do candle de sinal (ou sobre FixedStopPoints, se UseFixedStopTarget)
input bool UseFixedStopTarget = false;     // usar stop/alvo fixos manuais (pontos a partir da entrada) em vez do padrao (sem stop / alvo = maxima do candle)
input double FixedStopPoints = 100.0;      // Stop fixo (pontos a partir da entrada), se UseFixedStopTarget
input double FixedTargetPoints = 1500.0;   // Alvo fixo (pontos a partir da entrada), se UseFixedStopTarget
input bool UseTradingWindow = true;        // restringir novas ordens pendentes a uma janela de horario
input string TradingWindowStart = "16:00"; // Inicio da janela (HH:MM, hora do servidor)
input string TradingWindowEnd = "19:00";   // Fim da janela (HH:MM, hora do servidor)
input bool AutoTrade = false;              // precisa ligar explicitamente
input ulong MagicNumber = 20260717;
input bool DebugLog = true; // imprime diagnostico a cada candle fechado

CTrade trade;
int maHandle;
ulong pendingTicket = 0;   // ticket da Buy Limit pendente ativa (0 = nenhuma)
ulong positionTicket = 0;  // ticket da posicao aberta por este EA (0 = nenhuma)
datetime entryBarTime = 0; // hora do candle em que a posicao foi aberta

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

bool IsWithinTradingWindow()
{
   if (!UseTradingWindow)
      return true;

   int startMinutes, endMinutes;
   if (!ParseTimeToMinutes(TradingWindowStart, startMinutes) || !ParseTimeToMinutes(TradingWindowEnd, endMinutes))
      return true; // horario ja validado no OnInit, nao deveria cair aqui

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int nowMinutes = now.hour * 60 + now.min;

   if (startMinutes <= endMinutes)
      return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
   return nowMinutes >= startMinutes || nowMinutes <= endMinutes; // janela cruzando meia-noite
}

int OnInit()
{
   maHandle = INVALID_HANDLE;
   if (UseMAFilter)
   {
      maHandle = iMA(_Symbol, PERIOD_CURRENT, MAPeriod, 0, MAMethod, PRICE_CLOSE);
      if (maHandle == INVALID_HANDLE)
      {
         Print("ERRO: falha ao criar handle da media movel. GetLastError=", GetLastError());
         return INIT_FAILED;
      }
   }

   if (UseTradingWindow)
   {
      int dummyMinutes;
      if (!ParseTimeToMinutes(TradingWindowStart, dummyMinutes) || !ParseTimeToMinutes(TradingWindowEnd, dummyMinutes))
      {
         Alert("Horario invalido em TradingWindowStart/TradingWindowEnd. Use o formato HH:MM.");
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   trade.SetExpertMagicNumber(MagicNumber);
   if (!AutoTrade)
      Print("AVISO: AutoTrade=false. O EA nao vai enviar ordens ate voce ligar este input.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

double LotsForRisk(double stopDistance)
{
   if (stopDistance <= 0)
      return 0.0;
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSize <= 0)
      return 0.0;
   double lots = riskAmount / (stopDistance / tickSize * tickValue);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if (step <= 0)
      step = 0.01;

   int decimals = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   lots = NormalizeDouble(MathFloor(lots / step) * step, decimals);

   if (lots > maxLot)
      lots = NormalizeDouble(MathFloor(maxLot / step) * step, decimals);
   return lots < minLot ? 0.0 : lots;
}

ulong FindOpenPositionTicket()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;
      return ticket;
   }
   return 0;
}

void ManageOpenPosition()
{
   ulong currentTicket = FindOpenPositionTicket();

   if (currentTicket != 0 && positionTicket == 0)
   {
      // pendente foi executada nesta vela
      positionTicket = currentTicket;
      entryBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      pendingTicket = 0;
      if (DebugLog)
         Print("POSICAO ABERTA ticket=", positionTicket, " entryBarTime=", TimeToString(entryBarTime));
      return;
   }

   if (currentTicket == 0 && positionTicket != 0)
   {
      // posicao ja foi encerrada (alvo atingido ou fechamento manual)
      if (DebugLog)
         Print("POSICAO ENCERRADA ticket=", positionTicket);
      positionTicket = 0;
      entryBarTime = 0;
      return;
   }

   if (positionTicket != 0)
   {
      int barsSinceEntry = iBarShift(_Symbol, PERIOD_CURRENT, entryBarTime, false);
      if (barsSinceEntry >= CandlesToExit)
      {
         if (!trade.PositionClose(positionTicket))
            Print("ERRO ao fechar posicao por tempo: retcode=", trade.ResultRetcode(),
                  " desc=", trade.ResultRetcodeDescription());
         else
         {
            if (DebugLog)
               Print("POSICAO FECHADA POR TEMPO ticket=", positionTicket, " barsSinceEntry=", barsSinceEntry);
            positionTicket = 0;
            entryBarTime = 0;
         }
      }
   }
}

void ManagePendingOrder()
{
   if (positionTicket != 0)
      return; // ja ha posicao aberta, nao mantem pendente nova

   if (pendingTicket != 0 && OrderSelect(pendingTicket))
   {
      if (!trade.OrderDelete(pendingTicket))
         Print("ERRO ao cancelar Buy Limit antiga: retcode=", trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());
   }
   pendingTicket = 0;

   if (!IsWithinTradingWindow())
      return; // fora da janela, nao reenvia pendente

   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   if (high1 - low1 <= 0.0)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl = 0.0;
   double tp = high1;
   double riskDistance = high1 - low1;
   if (UseFixedStopTarget)
   {
      sl = low1 - FixedStopPoints * point;
      tp = low1 + FixedTargetPoints * point;
      riskDistance = FixedStopPoints * point;
   }

   double maValue = 0.0;
   bool allowBuy = true;
   if (UseMAFilter)
   {
      double maBuf[1];
      if (CopyBuffer(maHandle, 0, 1, 1, maBuf) <= 0)
      {
         Print("ERRO: CopyBuffer da media movel falhou. GetLastError=", GetLastError());
         return;
      }
      maValue = maBuf[0];
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      allowBuy = close1 > maValue;
   }

   if (DebugLog)
      Print("BARRA ", TimeToString(iTime(_Symbol, PERIOD_CURRENT, 0)),
            " low1=", low1, " high1=", high1, " sl=", sl, " tp=", tp,
            " maValue=", maValue, " allowBuy=", allowBuy);

   if (!allowBuy)
      return;

   double lots = LotsForRisk(riskDistance);
   if (lots <= 0)
   {
      Print("AVISO: lots calculado <= 0 (riskDistance=", riskDistance, "), Buy Limit nao enviada.");
      return;
   }

   if (!trade.BuyLimit(lots, low1, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "reversao_candle_anterior_lite"))
   {
      Print("ERRO ao enviar Buy Limit: retcode=", trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription());
      return;
   }
   pendingTicket = trade.ResultOrder();
}

void OnTick()
{
   if (!AutoTrade)
      return;
   if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return; // negociacao desabilitada no simbolo

   ManageOpenPosition(); // detecta fill/fechamento e aplica saida por tempo a cada tick

   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if (currentBarTime == lastBarTime)
      return; // reenvio/avaliacao da pendente so uma vez por candle fechado
   lastBarTime = currentBarTime;

   int minBars = UseMAFilter ? MAPeriod + 2 : 3;
   if (Bars(_Symbol, PERIOD_CURRENT) < minBars)
   {
      Print("AVISO: barras insuficientes (minimo=", minBars, ")");
      return;
   }

   ManagePendingOrder();
}
