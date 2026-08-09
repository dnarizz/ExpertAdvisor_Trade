//+------------------------------------------------------------------+
//|                                Model_D1_1_RetraceTracker.mq5     |
//|                                Copyright 2026, AI Collaborator   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.10"
#property description "Model D1.1: Single Layer Static Retrace x% & Hit Rate Tracker"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input group "=== Parameter Strategi Retrace ==="
input int      InpStreakCount      = 2;      // Jumlah Candle Streak Konsekutif
input double   InpRetracePercent   = 30.0;   // Retrace Static (x%) dari Range Streak
input int      InpLimitExpireBars  = 3;      // Masa Berlaku Pending Order (dalam Bar)

input group "=== Risk & Trade Management ==="
input double   InpLotSize          = 0.03;   // Ukuran Lot (Single Layer)
input double   InpRiskRewardRatio  = 2.5;    // Risk Reward Ratio (TP = SL * RRR)
input int      InpSLBufferPoints   = 0;      // Buffer Stop Loss (Point)
input ulong    InpMagicNumber      = 777011; // Magic Number EA

//--- Global Variables & Statistics
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
   
   EventSetTimer(1); // Timer untuk update dashboard
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
   // Cek Pembentukan Bar Baru
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return; // Jalankan logika hanya saat bar baru buka
   
   // Rule Single Layer: Jika sudah ada posisi aktif atau pending order aktif, lewati
   if(HasActivePositionOrPending()) return;

   // Cek Sinyal Streak (+1: Bullish Streak, -1: Bearish Streak, 0: Tidak Ada)
   int streakDirection = CheckStreakSignal();
   
   if(streakDirection != 0)
   {
      g_lastBarTime = currentBarTime; // Kunci bar ini
      g_totalSetups++;                // Catat Setup Streak Baru

      // Hitung High & Low dari keseluruhan Candle Streak
      double streakHigh = GetStreakHigh(InpStreakCount);
      double streakLow  = GetStreakLow(InpStreakCount);
      double streakRange = streakHigh - streakLow;

      if(streakRange <= 0) return;

      double limitPrice = 0;
      double slPrice    = 0;
      double tpPrice    = 0;
      ENUM_ORDER_TYPE orderType;

      if(streakDirection == 1) // Bullish Streak -> Pasang BUY LIMIT saat retrace turun x%
      {
         orderType  = ORDER_TYPE_BUY_LIMIT;
         limitPrice = streakHigh - (streakRange * (InpRetracePercent / 100.0));
         slPrice    = streakLow - (InpSLBufferPoints * _Point);
         
         double riskDistance = limitPrice - slPrice;
         if(riskDistance <= 0) return;
         tpPrice    = limitPrice + (riskDistance * InpRiskRewardRatio);
      }
      else // Bearish Streak -> Pasang SELL LIMIT saat retrace naik x%
      {
         orderType  = ORDER_TYPE_SELL_LIMIT;
         limitPrice = streakLow + (streakRange * (InpRetracePercent / 100.0));
         slPrice    = streakHigh + (InpSLBufferPoints * _Point);
         
         double riskDistance = slPrice - limitPrice;
         if(riskDistance <= 0) return;
         tpPrice    = limitPrice - (riskDistance * InpRiskRewardRatio);
      }

      // Normalisasi Harga Presisi
      limitPrice = NormalizeDouble(limitPrice, _Digits);
      slPrice    = NormalizeDouble(slPrice, _Digits);
      tpPrice    = NormalizeDouble(tpPrice, _Digits);

      // Waktu Kedaluwarsa Pending Order
      datetime expirationTime = currentBarTime + (InpLimitExpireBars * PeriodSeconds(_Period));
      
      // Kirim Single Layer Pending Order
      if(trade.OrderOpen(_Symbol, orderType, InpLotSize, limitPrice, limitPrice, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expirationTime, "Model D1.1"))
      {
         PrintFormat("Model D1.1: Pending %s dipasang di %.5f (Retrace %.1f%%)", 
                     EnumToString(orderType), limitPrice, InpRetracePercent);
      }
   }
}

//+------------------------------------------------------------------+
//| Deteksi Eksekusi Pending Order (Retrace Hit)                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   // Jika pending order berhasil terisi (Deal terpicu dari pending order)
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagicNumber)
      {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
         {
            g_retraceHits++; // Tambahkan hit pencapaian retrace x%
            UpdateDashboard();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Evaluasi Kriteria Custom Strategy Tester (MT5 Optimization)      |
//+------------------------------------------------------------------+
double OnTester()
{
   if(g_totalSetups == 0) return 0.0;
   double hitRate = ((double)g_retraceHits / (double)g_totalSetups) * 100.0;
   return hitRate; // Mengembalikan persentase harga retrace ke x%
}

//+------------------------------------------------------------------+
//| Helper: Cek Kerentanan Streak (Consecutive Candles)              |
//+------------------------------------------------------------------+
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

   if(bullish) return 1;   // Sinyal Bullish
   if(bearish) return -1;  // Sinyal Bearish
   return 0;
}

//+------------------------------------------------------------------+
//| Helper: Cek Posisi atau Pending Order Aktif                      |
//+------------------------------------------------------------------+
bool HasActivePositionOrPending()
{
   // Cek Posisi Aktif
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
   }

   // Cek Pending Order Aktif
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

//+------------------------------------------------------------------+
//| Helper: Cari High Tertinggi dalam Rentang Streak                 |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Helper: Cari Low Terendah dalam Rentang Streak                  |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Helper: Tampilan UI Dashboard                                    |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double hitRate = (g_totalSetups > 0) ? ((double)g_retraceHits / (double)g_totalSetups) * 100.0 : 0.0;
   
   string text = "=========================================\n";
   text += "     MODEL D1.1 - RETRACE TRACKER PANEL   \n";
   text += "=========================================\n";
   text += StringFormat("Target Retrace (x%%)   : %.1f%%\n", InpRetracePercent);
   text += StringFormat("Total Streak Setup     : %d\n", g_totalSetups);
   text += StringFormat("Retrace Tersentuh (Hits): %d\n", g_retraceHits);
   text += StringFormat("Rasio Keberhasilan (Hit Rate) : %.2f%%\n", hitRate);
   text += "=========================================\n";

   Comment(text);
}
