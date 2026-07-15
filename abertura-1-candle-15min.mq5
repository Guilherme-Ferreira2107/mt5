//+------------------------------------------------------------------+
//|                                    Abertura_1_Candle_15min.mq5    |
//|              Migrado do Pine Script "Abertura 10h - 1o Candle"   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link "http://www.mql5.com"
#property version "1.00"

int EA_Magic = 20260713; // EA Magic Number
input double Lot = 1;    // Lots to Trade

input int SessionHour = 10;         // Hora do candle de referencia
input int SessionMinute = 0;        // Minuto do candle de referencia
input double TakeProfitPerc = 50.0; // Take Profit (% da altura do candle)
input double StopLossPerc = 25.0;   // Stop Loss (% da altura do candle)
input int SlippagePoints = 100;     // Desvio maximo

input bool OperarDomingo = false; // Operar no domingo
input bool OperarSegunda = true;  // Operar na segunda-feira
input bool OperarTerca = true;    // Operar na terca-feira
input bool OperarQuarta = true;   // Operar na quarta-feira
input bool OperarQuinta = true;   // Operar na quinta-feira
input bool OperarSexta = true;    // Operar na sexta-feira
input bool OperarSabado = false;  // Operar no sabado

bool trade_taken_today = false;
int last_trade_day = -1;

void ResetDailyControlIfNewDay()
{
   MqlDateTime now_struct;
   TimeToStruct(TimeCurrent(), now_struct);

   int today_key = now_struct.year * 1000 + now_struct.day_of_year;
   if (today_key != last_trade_day)
   {
      last_trade_day = today_key;
      trade_taken_today = false;
   }
}

bool IsSessionCandle(const datetime candle_time)
{
   MqlDateTime candle_struct;
   TimeToStruct(candle_time, candle_struct);
   return (candle_struct.hour == SessionHour && candle_struct.min == SessionMinute);
}

bool IsWeekdayAllowed(const datetime candle_time)
{
   MqlDateTime candle_struct;
   TimeToStruct(candle_time, candle_struct);

   switch (candle_struct.day_of_week)
   {
   case 0:
      return OperarDomingo;
   case 1:
      return OperarSegunda;
   case 2:
      return OperarTerca;
   case 3:
      return OperarQuarta;
   case 4:
      return OperarQuinta;
   case 5:
      return OperarSexta;
   case 6:
      return OperarSabado;
   default:
      return false;
   }
}

// Alguns simbolos/corretoras nao aceitam ORDER_FILLING_IOC; escolhe o modo
// realmente suportado pelo simbolo para evitar rejeicao da ordem de abertura.
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   int filling_flags = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if ((filling_flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if ((filling_flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

int OnInit()
{
   if (SessionHour < 0 || SessionHour > 23 || SessionMinute < 0 || SessionMinute > 59)
   {
      Alert("Horario invalido para o candle de referencia.");
      return (-1);
   }

   ENUM_SYMBOL_TRADE_MODE trade_mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if (trade_mode != SYMBOL_TRADE_MODE_FULL)
   {
      Alert("Atencao: ", _Symbol, " nao esta com trade mode FULL (modo atual restringe aberturas). Verifique a especificacao do simbolo.");
   }

   last_trade_day = -1;
   trade_taken_today = false;

   return (0);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   if (Bars(_Symbol, _Period) < 3)
   {
      Alert("We have less than 3 bars, EA will now exit!!");
      return;
   }

   static datetime Old_Time;
   datetime New_Time[1];
   bool IsNewBar = false;

   int copied = CopyTime(_Symbol, _Period, 0, 1, New_Time);
   if (copied > 0)
   {
      if (Old_Time != New_Time[0])
      {
         IsNewBar = true;
         if (MQL5InfoInteger(MQL5_DEBUGGING))
            Print("We have new bar here ", New_Time[0], " old time was ", Old_Time);
         Old_Time = New_Time[0];
      }
   }
   else
   {
      Alert("Error in copying historical times data, error =", GetLastError());
      ResetLastError();
      return;
   }

   if (!IsNewBar)
      return;

   ResetDailyControlIfNewDay();

   if (trade_taken_today)
      return;

   MqlRates mrate[];
   ArraySetAsSeries(mrate, true);

   if (CopyRates(_Symbol, _Period, 0, 2, mrate) < 2)
   {
      Alert("Error copying rates/history data - error:", GetLastError(), "!!");
      ResetLastError();
      return;
   }

   // mrate[1] e o ultimo candle fechado, correspondente ao "barstate.isconfirmed" do Pine.
   if (!IsSessionCandle(mrate[1].time))
      return;

   if (!IsWeekdayAllowed(mrate[1].time))
      return;

   bool buy_opened = false;
   bool sell_opened = false;
   if (PositionSelect(_Symbol) == true)
   {
      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         buy_opened = true;
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         sell_opened = true;
   }

   if (buy_opened || sell_opened)
      return;

   trade_taken_today = true;

   double range_candle = mrate[1].high - mrate[1].low;
   if (range_candle <= 0.0)
      return;

   bool is_bull = (mrate[1].close > mrate[1].open);

   MqlTick latest_price;
   if (!SymbolInfoTick(_Symbol, latest_price))
   {
      Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
      return;
   }

   MqlTradeRequest mrequest;
   MqlTradeResult mresult;
   ZeroMemory(mrequest);

   if (is_bull)
   {
      double tp = NormalizeDouble(mrate[1].close + range_candle * (TakeProfitPerc / 100.0), _Digits);
      double sl = NormalizeDouble(mrate[1].close - range_candle * (StopLossPerc / 100.0), _Digits);

      mrequest.action = TRADE_ACTION_DEAL;
      mrequest.price = NormalizeDouble(latest_price.ask, _Digits);
      mrequest.sl = sl;
      mrequest.tp = tp;
      mrequest.symbol = _Symbol;
      mrequest.volume = Lot;
      mrequest.magic = EA_Magic;
      mrequest.type = ORDER_TYPE_BUY;
      mrequest.type_filling = GetFillingMode();
      mrequest.deviation = SlippagePoints;

      OrderSend(mrequest, mresult);
      if (mresult.retcode == 10009 || mresult.retcode == 10008)
      {
         Alert("A Buy order has been successfully placed with Ticket#:", mresult.order, "!!");
      }
      else
      {
         Alert("The Buy order request could not be completed -error:", GetLastError());
         ResetLastError();
      }
      return;
   }

   double sell_tp = NormalizeDouble(mrate[1].close - range_candle * (TakeProfitPerc / 100.0), _Digits);
   double sell_sl = NormalizeDouble(mrate[1].close + range_candle * (StopLossPerc / 100.0), _Digits);

   mrequest.action = TRADE_ACTION_DEAL;
   mrequest.price = NormalizeDouble(latest_price.bid, _Digits);
   mrequest.sl = sell_sl;
   mrequest.tp = sell_tp;
   mrequest.symbol = _Symbol;
   mrequest.volume = Lot;
   mrequest.magic = EA_Magic;
   mrequest.type = ORDER_TYPE_SELL;
   mrequest.type_filling = GetFillingMode();
   mrequest.deviation = SlippagePoints;

   OrderSend(mrequest, mresult);
   if (mresult.retcode == 10009 || mresult.retcode == 10008)
   {
      Alert("A Sell order has been successfully placed with Ticket#:", mresult.order, "!!");
   }
   else
   {
      Alert("The Sell order request could not be completed -error:", GetLastError());
      ResetLastError();
   }
}
//+------------------------------------------------------------------+
