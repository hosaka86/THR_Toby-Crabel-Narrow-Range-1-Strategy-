//+------------------------------------------------------------------+
//|                                                   CrabelNR1.mq5 |
//|                        Toby Crabel Narrow Range 1 Strategy       |
//|                                      Runs on any timeframe       |
//+------------------------------------------------------------------+
#property copyright "Toby Crabel NR1 Strategy"
#property version   "2.00"
#property strict

// Input Parameters
input group "=== Strategy Parameters ==="
input int      inp_LookbackPeriod = 20;        // Lookback Period (days)
input int      inp_StretchLength = 10;         // Stretch Length for Noise calculation
input double   inp_StretchMultiple = 2.0;      // Stretch Multiple

input group "=== Exit Parameters ==="
input int      inp_TimeExitDays = 5;           // Time Exit (days, 0=disabled)
input double   inp_TargetMultiple = 3.0;       // Target Exit Multiple (0=disabled)

input group "=== Risk Management ==="
input double   inp_RiskPercent = 1.0;          // Risk per Trade (%)
input int      inp_MagicNumber = 20241102;     // Magic Number
input string   inp_TradeComment = "CrabelNR1"; // Trade Comment

// Global variables
datetime g_lastBarTime = 0;
bool     g_newBar = false;
datetime g_entryTime = 0;
ulong    g_buyStopTicket = 0;
ulong    g_sellStopTicket = 0;
double   g_initialStretch = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Toby Crabel NR1 EA v2.0 initialized on ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print("Lookback: ", inp_LookbackPeriod, " | Stretch: ", inp_StretchLength, "x", inp_StretchMultiple);
   Print("LOGIC: First triggered order = Entry, Second order = Protective Stop");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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

   // Manage existing positions and orders
   ManagePositionsAndOrders();

   // Check if we already have pending orders or open position
   if(CountOwnPositions() > 0 || CountOwnPendingOrders() > 0)
      return;

   // Check for Narrow Range pattern
   if(IsNarrowRange())
   {
      double stretch = CalculateStretch();
      if(stretch > 0)
      {
         PlaceBracketOrders(stretch);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for new bar                                                  |
//+------------------------------------------------------------------+
void CheckNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

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
//| Manage positions and pending orders                               |
//+------------------------------------------------------------------+
void ManagePositionsAndOrders()
{
   // Check if we have an open position
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;

      // Store entry time
      if(g_entryTime == 0)
         g_entryTime = (datetime)PositionGetInteger(POSITION_TIME);

      // Check time exit
      if(inp_TimeExitDays > 0)
      {
         datetime currentTime = TimeCurrent();
         int daysPassed = (int)((currentTime - g_entryTime) / 86400);

         if(daysPassed >= inp_TimeExitDays)
         {
            ClosePosition(ticket, "Time Exit");
            DeleteAllOwnPendingOrders();
            ResetGlobals();
            continue;
         }
      }

      // Check target exit
      if(inp_TargetMultiple > 0 && g_initialStretch > 0)
      {
         double positionProfit = PositionGetDouble(POSITION_PROFIT);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ?
                               SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                               SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         double priceMove = MathAbs(currentPrice - openPrice);
         double targetDistance = g_initialStretch * inp_TargetMultiple;

         if(priceMove >= targetDistance)
         {
            ClosePosition(ticket, "Target Exit");
            DeleteAllOwnPendingOrders();
            ResetGlobals();
            continue;
         }
      }
   }

   // Reset globals if no position
   if(CountOwnPositions() == 0)
   {
      g_entryTime = 0;
   }

   // Check if one pending order was triggered (position opened)
   // Then the other pending order becomes the protective stop
   if(CountOwnPositions() > 0)
   {
      // We have a position now, check which order was triggered
      CheckAndConvertPendingToStop();
   }
}

//+------------------------------------------------------------------+
//| Check which pending order was triggered and convert other to SL  |
//+------------------------------------------------------------------+
void CheckAndConvertPendingToStop()
{
   // Check if we still have pending orders
   if(CountOwnPendingOrders() == 0)
      return;

   // Get the position type
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong posTicket = PositionGetTicket(i);
      if(posTicket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Delete opposite pending orders - they will be replaced by proper SL
      // The SL is already set on the position from the initial bracket order
      DeleteAllOwnPendingOrders();
      break;
   }
}

//+------------------------------------------------------------------+
//| Count own positions                                               |
//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count own pending orders                                          |
//+------------------------------------------------------------------+
int CountOwnPendingOrders()
{
   int count = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if current pattern is Narrow Range (NR1)                    |
//+------------------------------------------------------------------+
bool IsNarrowRange()
{
   if(Bars(_Symbol, PERIOD_CURRENT) < inp_LookbackPeriod + 2)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, inp_LookbackPeriod + 2, rates) < inp_LookbackPeriod + 2)
      return false;

   // Calculate 2-bar range for the completed bars (1 and 2, not including current forming bar 0)
   double currentHigh = MathMax(rates[1].high, rates[2].high);
   double currentLow = MathMin(rates[1].low, rates[2].low);
   double currentRange = currentHigh - currentLow;

   // Compare with all previous 2-bar ranges in lookback period
   bool isNarrowest = true;

   for(int i = 2; i < inp_LookbackPeriod; i++)
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

   if(CopyRates(_Symbol, PERIOD_CURRENT, 1, inp_StretchLength, rates) < inp_StretchLength)
      return 0;

   double noiseSum = 0;

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
//| Place bracket orders (Buy Stop and Sell Stop)                     |
//| The first triggered = Entry, the second = Protective Stop         |
//+------------------------------------------------------------------+
void PlaceBracketOrders(double stretch)
{
   double currentOpen = iOpen(_Symbol, PERIOD_CURRENT, 0);

   if(currentOpen <= 0)
      return;

   // Calculate entry levels
   double buyStopPrice = currentOpen + stretch;
   double sellStopPrice = currentOpen - stretch;

   // Calculate position size based on stretch distance (= initial risk)
   double lotSize = CalculateLotSize(stretch);

   if(lotSize <= 0)
      return;

   // Store stretch for later use
   g_initialStretch = stretch;

   // Place bracket orders
   // Buy Stop with SL at Sell Stop level, Sell Stop with SL at Buy Stop level
   // This implements: "The first stop that is traded is the position. The other stop is the protective stop."

   double buyTP = 0;
   double sellTP = 0;

   if(inp_TargetMultiple > 0)
   {
      buyTP = buyStopPrice + (stretch * inp_TargetMultiple);
      sellTP = sellStopPrice - (stretch * inp_TargetMultiple);
   }

   // Place Buy Stop with SL at Sell Stop price
   g_buyStopTicket = PlaceOrder(ORDER_TYPE_BUY_STOP, buyStopPrice, sellStopPrice, buyTP, lotSize);

   if(g_buyStopTicket > 0)
   {
      Print("Buy Stop placed at ", DoubleToString(buyStopPrice, _Digits),
            " | Protective Stop: ", DoubleToString(sellStopPrice, _Digits),
            " | Stretch: ", DoubleToString(stretch/_Point, 1), " points");
   }

   // Place Sell Stop with SL at Buy Stop price
   g_sellStopTicket = PlaceOrder(ORDER_TYPE_SELL_STOP, sellStopPrice, buyStopPrice, sellTP, lotSize);

   if(g_sellStopTicket > 0)
   {
      Print("Sell Stop placed at ", DoubleToString(sellStopPrice, _Digits),
            " | Protective Stop: ", DoubleToString(buyStopPrice, _Digits),
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
ulong PlaceOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp, double lots)
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
   request.type_filling = ORDER_FILLING_RETURN;

   if(!OrderSend(request, result))
   {
      request.type_filling = ORDER_FILLING_FOK;
      if(!OrderSend(request, result))
      {
         request.type_filling = ORDER_FILLING_IOC;
         OrderSend(request, result);
      }
   }

   if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
   {
      return result.order;
   }
   else
   {
      Print("Order failed: ", result.retcode, " - ", result.comment);
      return 0;
   }
}

//+------------------------------------------------------------------+
//| Delete all own pending orders                                     |
//+------------------------------------------------------------------+
void DeleteAllOwnPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;

      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber) continue;

      MqlTradeRequest request = {};
      MqlTradeResult result = {};

      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;

      OrderSend(request, result);
   }

   g_buyStopTicket = 0;
   g_sellStopTicket = 0;
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

   request.type_filling = ORDER_FILLING_RETURN;

   if(!OrderSend(request, result))
   {
      request.type_filling = ORDER_FILLING_FOK;
      if(!OrderSend(request, result))
      {
         request.type_filling = ORDER_FILLING_IOC;
         OrderSend(request, result);
      }
   }

   if(result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Position closed: ", reason);
   }
}

//+------------------------------------------------------------------+
//| Reset global variables                                            |
//+------------------------------------------------------------------+
void ResetGlobals()
{
   g_entryTime = 0;
   g_buyStopTicket = 0;
   g_sellStopTicket = 0;
   g_initialStretch = 0;
}
//+------------------------------------------------------------------+
