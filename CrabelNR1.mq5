//+------------------------------------------------------------------+
//|                                                   CrabelNR1.mq5 |
//|                        Toby Crabel Narrow Range 1 Strategy       |
//|                                      Runs on D1 (Daily) chart    |
//+------------------------------------------------------------------+
#property copyright "Toby Crabel NR1 Strategy"
#property version   "1.00"
#property strict

// Input Parameters
input group "=== Strategy Parameters ==="
input int      inp_LookbackPeriod = 20;        // Lookback Period (days)
input int      inp_StretchLength = 10;         // Stretch Length for Noise calculation
input double   inp_StretchMultiple = 2.0;      // Stretch Multiple
input int      inp_ATRLength = 20;             // ATR Length
input double   inp_ATRStopMultiple = 6.0;      // ATR Stop Multiple

input group "=== Exit Parameters ==="
input int      inp_TimeExitDays = 5;           // Time Exit (days, 0=disabled)
input double   inp_TargetMultiple = 3.0;       // Target Exit Multiple (0=disabled)
input bool     inp_UseStretchExit = true;      // Use Stretch Exit (opposite side)

input group "=== Risk Management ==="
input double   inp_RiskPercent = 1.0;          // Risk per Trade (%)
input int      inp_MagicNumber = 20241102;     // Magic Number
input string   inp_TradeComment = "CrabelNR1"; // Trade Comment

// Global variables
int      g_atrHandle = INVALID_HANDLE;
double   g_atrBuffer[];
datetime g_lastBarTime = 0;
bool     g_newBar = false;
datetime g_entryTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Check if chart is Daily
   if(_Period != PERIOD_D1)
   {
      Alert("ERROR: This EA must run on D1 (Daily) chart!");
      return(INIT_FAILED);
   }

   // Initialize ATR indicator
   g_atrHandle = iATR(_Symbol, PERIOD_D1, inp_ATRLength);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR indicator");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(g_atrBuffer, true);

   Print("Toby Crabel NR1 EA initialized on ", _Symbol, " D1");
   Print("Lookback: ", inp_LookbackPeriod, " | Stretch: ", inp_StretchLength, "x", inp_StretchMultiple);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   CheckNewBar();

   if(!g_newBar)
      return;

   // Update ATR values
   if(CopyBuffer(g_atrHandle, 0, 0, 3, g_atrBuffer) < 3)
      return;

   // Check and manage existing positions
   ManageOpenPositions();

   // Check if we can open new trade
   if(PositionsTotal() > 0)
      return;

   // Check for Narrow Range pattern
   if(IsNarrowRange())
   {
      double stretch = CalculateStretch();
      if(stretch > 0)
      {
         PlacePendingOrders(stretch);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for new bar                                                  |
//+------------------------------------------------------------------+
void CheckNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_D1, 0);

   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      g_newBar = true;
   }
   else
   {
      g_newBar = false;
   }
}

//+------------------------------------------------------------------+
//| Check if current pattern is Narrow Range (NR1)                    |
//+------------------------------------------------------------------+
bool IsNarrowRange()
{
   // Need at least lookback + 2 bars
   if(Bars(_Symbol, PERIOD_D1) < inp_LookbackPeriod + 2)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, PERIOD_D1, 0, inp_LookbackPeriod + 2, rates) < inp_LookbackPeriod + 2)
      return false;

   // Calculate 2-bar range for bars 0 and 1 (current forming bar and previous)
   double currentHigh = MathMax(rates[0].high, rates[1].high);
   double currentLow = MathMin(rates[0].low, rates[1].low);
   double currentRange = currentHigh - currentLow;

   // Compare with all 2-bar ranges in lookback period
   bool isNarrowest = true;

   for(int i = 2; i < inp_LookbackPeriod + 1; i++)
   {
      double high2bar = MathMax(rates[i].high, rates[i+1].high);
      double low2bar = MathMin(rates[i].low, rates[i+1].low);
      double range2bar = high2bar - low2bar;

      if(range2bar <= currentRange)
      {
         isNarrowest = false;
         break;
      }
   }

   if(isNarrowest)
   {
      Print("Narrow Range detected! 2-bar range: ", DoubleToString(currentRange/_Point, 1), " points");
   }

   return isNarrowest;
}

//+------------------------------------------------------------------+
//| Calculate Stretch (Average Noise)                                 |
//+------------------------------------------------------------------+
double CalculateStretch()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, PERIOD_D1, 1, inp_StretchLength, rates) < inp_StretchLength)
      return 0;

   double noiseSum = 0;

   // Calculate average noise (High - Low) over stretch period
   for(int i = 0; i < inp_StretchLength; i++)
   {
      double noise = rates[i].high - rates[i].low;
      noiseSum += noise;
   }

   double avgNoise = noiseSum / inp_StretchLength;
   double stretch = avgNoise * inp_StretchMultiple;

   return stretch;
}

//+------------------------------------------------------------------+
//| Place pending orders for breakout                                 |
//+------------------------------------------------------------------+
void PlacePendingOrders(double stretch)
{
   double currentOpen = iOpen(_Symbol, PERIOD_D1, 0);
   double atr = g_atrBuffer[0];

   if(currentOpen <= 0 || atr <= 0)
      return;

   // Calculate entry levels
   double buyStopPrice = currentOpen + stretch;
   double sellStopPrice = currentOpen - stretch;

   // Calculate position size based on ATR stop
   double stopDistance = atr * inp_ATRStopMultiple;
   double lotSize = CalculateLotSize(stopDistance);

   if(lotSize <= 0)
      return;

   // Calculate stop loss levels
   double buyStopLoss = buyStopPrice - stopDistance;
   double sellStopLoss = sellStopPrice + stopDistance;

   // Calculate take profit levels (if enabled)
   double buyTP = 0;
   double sellTP = 0;

   if(inp_TargetMultiple > 0)
   {
      buyTP = buyStopPrice + (stopDistance * inp_TargetMultiple);
      sellTP = sellStopPrice - (stopDistance * inp_TargetMultiple);
   }

   // Place Buy Stop order
   if(PlaceOrder(ORDER_TYPE_BUY_STOP, buyStopPrice, buyStopLoss, buyTP, lotSize))
   {
      Print("Buy Stop placed at ", DoubleToString(buyStopPrice, _Digits),
            " | SL: ", DoubleToString(buyStopLoss, _Digits),
            " | Stretch: ", DoubleToString(stretch/_Point, 1), " points");
   }

   // Place Sell Stop order
   if(PlaceOrder(ORDER_TYPE_SELL_STOP, sellStopPrice, sellStopLoss, sellTP, lotSize))
   {
      Print("Sell Stop placed at ", DoubleToString(sellStopPrice, _Digits),
            " | SL: ", DoubleToString(sellStopLoss, _Digits),
            " | Stretch: ", DoubleToString(stretch/_Point, 1), " points");
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopDistance)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (inp_RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue == 0 || tickSize == 0 || stopDistance == 0)
      return 0;

   double lotSize = riskAmount / (stopDistance * tickValue / tickSize);

   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

   return lotSize;
}

//+------------------------------------------------------------------+
//| Place order                                                        |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp, double lots)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_PENDING;
   request.symbol = _Symbol;
   request.volume = lots;
   request.type = orderType;
   request.price = NormalizeDouble(price, _Digits);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = tp > 0 ? NormalizeDouble(tp, _Digits) : 0;
   request.deviation = 10;
   request.magic = inp_MagicNumber;
   request.comment = inp_TradeComment;
   request.type_filling = ORDER_FILLING_FOK;

   // Try different filling modes
   if(!OrderSend(request, result))
   {
      request.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(request, result))
      {
         request.type_filling = ORDER_FILLING_RETURN;
         OrderSend(request, result);
      }
   }

   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      return true;
   }
   else
   {
      Print("Order failed: ", result.retcode, " - ", result.comment);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber)
         continue;

      // Store entry time when position opens
      if(g_entryTime == 0)
      {
         g_entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      }

      // Check time exit
      if(inp_TimeExitDays > 0)
      {
         datetime currentTime = TimeCurrent();
         int daysPassed = (int)((currentTime - g_entryTime) / 86400);

         if(daysPassed >= inp_TimeExitDays)
         {
            ClosePosition(ticket, "Time Exit");
            continue;
         }
      }

      // Stretch exit (opposite side stop) is handled by initial SL
      // Additional exit logic can be added here
   }

   // Delete opposite pending order when one is triggered
   if(PositionsTotal() > 0)
   {
      DeletePendingOrders();
   }

   // Reset entry time when no positions
   if(PositionsTotal() == 0)
   {
      g_entryTime = 0;
   }
}

//+------------------------------------------------------------------+
//| Delete pending orders                                              |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0)
         continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber)
         continue;

      MqlTradeRequest request = {};
      MqlTradeResult result = {};

      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;

      OrderSend(request, result);
   }
}

//+------------------------------------------------------------------+
//| Close position                                                     |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket, string reason)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = _Symbol;
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.deviation = 10;
   request.magic = inp_MagicNumber;
   request.comment = reason;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      request.type = ORDER_TYPE_SELL;
   else
      request.type = ORDER_TYPE_BUY;

   request.price = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                   SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   request.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(request, result))
   {
      request.type_filling = ORDER_FILLING_IOC;
      if(!OrderSend(request, result))
      {
         request.type_filling = ORDER_FILLING_RETURN;
         OrderSend(request, result);
      }
   }

   if(result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Position closed: ", reason);
   }
}
//+------------------------------------------------------------------+
