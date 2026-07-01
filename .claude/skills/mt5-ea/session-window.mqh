//+------------------------------------------------------------------+
//| session-window.mqh                                               |
//| Filtro de janelas de horario (ate 3 sessoes, com suporte a        |
//| virada de meia-noite) + limite opcional de candles desde o inicio |
//| da sessao. Extraido de zig-zag_rsi_adx.mq5.                       |
//+------------------------------------------------------------------+
#property strict

// Copie os inputs abaixo (renomeie os labels para o nome real das suas
// sessoes) e as 5 funcoes. Chame IsWithinTradingWindow() em OnTick antes
// de avaliar qualquer sinal de entrada.

input bool   UsarSessao1   = true;      // Operar Sessao 1
input string Sessao1Inicio = "00:00";   // Hora inicial Sessao 1
input string Sessao1Fim    = "03:00";   // Hora final Sessao 1
input bool   UsarSessao2   = true;      // Operar Sessao 2
input string Sessao2Inicio = "08:00";   // Hora inicial Sessao 2
input string Sessao2Fim    = "11:00";   // Hora final Sessao 2
input bool   UsarSessao3   = true;      // Operar Sessao 3
input string Sessao3Inicio = "14:00";   // Hora inicial Sessao 3
input string Sessao3Fim    = "17:00";   // Hora final Sessao 3
input int    MaxCandlesInicioSessao = 0; // 0 desliga, >0 limita aos primeiros candles da sessao

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

// inside_window / elapsed_candles saem preenchidos mesmo quando a funcao
// retorna false (ex.: dentro da janela mas alem de MaxCandlesInicioSessao),
// util para logging/diagnostico.
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

// Valide os horarios em OnInit chamando ParseTimeToMinutes para cada sessao
// habilitada; se algum retornar false, aborte com INIT_PARAMETERS_INCORRECT.
