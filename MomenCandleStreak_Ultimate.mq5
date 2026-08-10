//+------------------------------------------------------------------+
//|                                       Model_D1_2_Advanced.mq5    |
//|                                Copyright 2026, AI Collaborator   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.20"
#property description "Model D1.2: Single Layer, Session/Day Filters, Static/Dynamic SL & Streak Size Limits"

#include <Trade\Trade.mqh>
CTrade trade;

//--- INPUT PARAMETERS ---

input group "=== 1. Parameter Strategi Retrace ==="
input int      InpStreakCount      = 2;      // Jumlah Candle Streak Konsekutif
input double   InpRetracePercent   = 30.0;   // Retrace Static (x%) dari Range Streak
input int      InpLimitExpireBars  = 3;      // Masa Berlaku Pending Order (Bar)

input group "=== 2. Filter Batasan Ukuran Candle 1 & 2 ==="
input bool     InpUseStreakSizeFilter = true; // Aktifkan Filter Minimal/Maksimal Ukuran Streak
input double   InpMinStreakPoints     = 300;  // Batasan Minimal Total Points (Candle 1 & 2)
input double   InpMaxStreakPoints     = 3000; // Batasan Maksimal Total Points (Candle 1 & 2)

input group "=== 3. Pengaturan Stop Loss & Take Profit ==="
input bool     InpUseStaticSL      = false;  // True = Static SL (Points), False = Dynamic SL (Streak Low/High)
input double   InpStaticSLPoints   = 500;    // Jarak Static SL (Points) - Digunakan jika UseStaticSL = true
input double   InpRiskRewardRatio  = 2.5;    // Risk Reward Ratio (TP = Jarak SL * RRR)
input int      InpSLBufferPoints   = 0;      // Buffer Tambahan untuk Dynamic SL (Points)

input group "=== 4. Filter Sesi Trading (Server Time) ==="
input bool     InpUseAsianSession  = true;   // Aktifkan Sesi Asia
input int      InpAsianStartHour   = 0;      // Asia Start Hour
input int      InpAsianEndHour     = 8;      // Asia End Hour

input bool     InpUseLondonSession = true;   // Aktifkan Sesi London
input int      InpLondonStartHour  = 9;      // London Start Hour
input int      InpLondonEndHour    = 16;     // London End Hour

input bool     InpUseUSSession     = true;   // Aktifkan Sesi US / New York
input int      InpUSStartHour      = 15;     // US Start Hour
input int      InpUSEndHour        = 23;     // US End Hour

input group "=== 5. Filter Hari Trading ==="
input bool     InpTradeMonday      = true;   // Trading Hari Senin
input bool     InpTradeTuesday     = true;   // Trading Hari Selasa
input bool     InpTradeWednesday   = true;   // Trading Hari Rabu
input bool     InpTradeThursday    = true;   // Trading Hari Kamis
input bool     InpTradeFriday      = true;   // Trading Hari Jumat

input group "=== 6. Management & ID ==="
input double   InpLotSize          = 0.03;   // Ukuran Lot (Single Layer)
input ulong    InpMagicNumber      = 777012; // Magic Number EA

//--- Global Variables
int      g_totalSetups = 0;
int      g_retraceHits = 0;
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   g_lastBarTime = 0;
   g_totalSetups = 0;
   g_retraceHits = 0;
   
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
}

//+------------------------------------------------------------------+
//| Timer function for Dashboard UI                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Cek Bar Baru
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   
   // 2. Rule Single Layer
   if(HasActivePositionOrPending()) return;

   // 3. Filter Hari & Filter Sesi
   if(!IsDayAllowed() || !IsSessionAllowed()) return;

   // 4. Cek Sinyal Streak
   int streakDirection = CheckStreakSignal();
   if(streakDirection == 0) return;

   // 5. Cek Batasan Minimal & Maksimal Total Harga/Point Candle 1 & 2
   double streakOpenToCloseDistance = MathAbs(iClose(_Symbol, _Period, 1) - iOpen(_Symbol, _Period, InpStreakCount)) / _Point;
   
   if(InpUseStreakSizeFilter)
   {
      if(streakOpenToCloseDistance < InpMinStreakPoints || streakOpenToCloseDistance > InpMaxStreakPoints)
      {
         PrintFormat("Model D1.2: Sinyal Abaikan! Total Jarak Streak (%.1f pt) di luar batas [%.0f - %.0f pt]",
                     streakOpenToCloseDistance, InpMinStreakPoints, InpMaxStreakPoints);
         return;
      }
   }

   // Berhasil Lolos Semua Filter!
   g_lastBarTime = currentBarTime;
   g_totalSetups++;

   // Hitung High & Low dari keseluruhan Streak
   double streakHigh  = GetStreakHigh(InpStreakCount);
   double streakLow   = GetStreakLow(InpStreakCount);
   double streakRange = streakHigh - streakLow;

   if(streakRange <= 0) return;

   double limitPrice = 0;
   double slPrice    = 0;
   double tpPrice    = 0;
   ENUM_ORDER_TYPE orderType;

   if(streakDirection == 1) // BULLISH STREAK
   {
      orderType  = ORDER_TYPE_BUY_LIMIT;
      limitPrice = streakHigh - (streakRange * (InpRetracePercent / 100.0));
      
      // Penentuan SL (Static vs Dynamic)
      if(InpUseStaticSL)
         slPrice = limitPrice - (InpStaticSLPoints * _Point);
      else
         slPrice = streakLow - (InpSLBufferPoints * _Point);
      
      double riskDistance = limitPrice - slPrice;
      if(riskDistance <= 0) return;
      
      tpPrice = limitPrice + (riskDistance * InpRiskRewardRatio);
   }
   else // BEARISH STREAK
   {
      orderType  = ORDER_TYPE_SELL_LIMIT;
      limitPrice = streakLow + (streakRange * (InpRetracePercent / 100.0));
      
      // Penentuan SL (Static vs Dynamic)
      if(InpUseStaticSL)
         slPrice = limitPrice + (InpStaticSLPoints * _Point);
      else
         slPrice = streakHigh + (InpSLBufferPoints * _Point);
      
      double riskDistance = slPrice - limitPrice;
      if(riskDistance <= 0) return;
      
      tpPrice = limitPrice - (riskDistance * InpRiskRewardRatio);
   }

   // Presisi Harga
   limitPrice = NormalizeDouble(limitPrice, _Digits);
   slPrice    = NormalizeDouble(slPrice, _Digits);
   tpPrice    = NormalizeDouble(tpPrice, _Digits);

   // Expiration Pending Order
   datetime expirationTime = currentBarTime + (InpLimitExpireBars * PeriodSeconds(_Period));
   
   // Kirim Pending Order
   if(trade.OrderOpen(_Symbol, orderType, InpLotSize, limitPrice, limitPrice, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expirationTime, "Model D1.2"))
   {
      PrintFormat("Model D1.2: Order %s terpasang di %.5f | SL: %.5f | TP: %.5f", 
                  EnumToString(orderType), limitPrice, slPrice, tpPrice);
   }
}

//+------------------------------------------------------------------+
//| Callback Hit Tracking                                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagicNumber)
      {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
         {
            g_retraceHits++;
            UpdateDashboard();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Custom Optimization Metric (Hit Rate %)                          |
//+------------------------------------------------------------------+
double OnTester()
{
   if(g_totalSetups == 0) return 0.0;
   return ((double)g_retraceHits / (double)g_totalSetups) * 100.0;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+

// Filter Hari
bool IsDayAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   switch(dt.day_of_week)
   {
      case 1: return InpTradeMonday;
      case 2: return InpTradeTuesday;
      case 3: return InpTradeWednesday;
      case 4: return InpTradeThursday;
      case 5: return InpTradeFriday;
      default: return false; // Sabtu / Minggu
   }
}

// Filter Sesi
bool IsSessionAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;

   bool inAsian  = InpUseAsianSession  && IsTimeInHourRange(currentHour, InpAsianStartHour, InpAsianEndHour);
   bool inLondon = InpUseLondonSession && IsTimeInHourRange(currentHour, InpLondonStartHour, InpLondonEndHour);
   bool inUS     = InpUseUSSession     && IsTimeInHourRange(currentHour, InpUSStartHour, InpUSEndHour);

   return (inAsian || inLondon || inUS);
}

// Range Jam Sesi
bool IsTimeInHourRange(int hour, int startHour, int endHour)
{
   if(startHour < endHour)
      return (hour >= startHour && hour < endHour);
   else // Sesi Lintas Tengah Malam (misal 22:00 s/d 05:00)
      return (hour >= startHour || hour < endHour);
}

// Cek Sinyal Streak
int CheckStreakSignal()
{
   bool bullish = true;
   bool bearish = true;

   for(int i = 1; i <= InpStreakCount; i++)
   {
      double closePrice = iClose(_Symbol, _Period, i);
      double openPrice  = iOpen(_Symbol, _Period, i);

      if(closePrice <= openPrice) bullish = false;
      if(closePrice >= openPrice) bearish = false;
   }

   if(bullish) return 1;
   if(bearish) return -1;
   return 0;
}

// Cek Posisi / Order Aktif
bool HasActivePositionOrPending()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i) > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            return true;
      }
   }

   return false;
}

double GetStreakHigh(int count)
{
   double maxHigh = iHigh(_Symbol, _Period, 1);
   for(int i = 2; i <= count; i++)
   {
      double h = iHigh(_Symbol, _Period, i);
      if(h > maxHigh) maxHigh = h;
   }
   return maxHigh;
}

double GetStreakLow(int count)
{
   double minLow = iLow(_Symbol, _Period, 1);
   for(int i = 2; i <= count; i++)
   {
      double l = iLow(_Symbol, _Period, i);
      if(l < minLow) minLow = l;
   }
   return minLow;
}

void UpdateDashboard()
{
   double hitRate = (g_totalSetups > 0) ? ((double)g_retraceHits / (double)g_totalSetups) * 100.0 : 0.0;
   
   string text = "=========================================\n";
   text += "     MODEL D1.2 - ADVANCED PANEL        \n";
   text += "=========================================\n";
   text += StringFormat("Target Retrace (x%%)   : %.1f%%\n", InpRetracePercent);
   text += StringFormat("Mode Stop Loss         : %s\n", InpUseStaticSL ? "STATIC" : "DYNAMIC");
   text += StringFormat("Total Streak Setup     : %d\n", g_totalSetups);
   text += StringFormat("Retrace Hits           : %d\n", g_retraceHits);
   text += StringFormat("Retrace Hit Rate       : %.2f%%\n", hitRate);
   text += "=========================================\n";

   Comment(text);
}
