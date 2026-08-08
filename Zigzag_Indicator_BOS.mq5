//+------------------------------------------------------------------+
//| US100_ZigZag_BOS_EA.mq5                                          |
//| Strategi: ZigZag Break-of-Structure Trend Continuation           |
//|                                                                    |
//| CATATAN WAJIB:                                                    |
//| - Lot size STATIC (edit manual di input LotSize di bawah).       |
//| - Belum divalidasi backtest historis riil. Jalankan Strategy     |
//|   Tester dengan data Exness sebelum live.                        |
//| - "Optimal" tidak bisa diklaim tanpa data hasil backtest.        |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Lot & Risk ==="
input double LotSize          = 0.01;   // STATIC — ubah manual di sini sesuai kebutuhan
input double RiskRewardRatio  = 2.0;    // TP = jarak SL x ratio ini
input double SL_BufferPoints  = 50;     // buffer tambahan di belakang pivot untuk SL

input group "=== ZigZag Parameters ==="
input int    ZZ_Depth         = 10;     // sesuai permintaan
input int    ZZ_Deviation     = 2;      // sesuai permintaan
input int    ZZ_Backstep      = 3;      // default standar indikator ZigZag

input group "=== Filter Tambahan (opsional, bisa dimatikan) ==="
input bool   UseSpreadFilter  = true;
input double MaxSpreadPoints  = 300;
input bool   UseSessionFilter = true;
input int    AvoidStartHour   = 23;     // server time, hindari jelang market close/rollover
input int    AvoidEndHour     = 1;
input bool   OnePositionOnly  = true;   // true = tidak buka posisi baru jika masih ada posisi aktif

//================== GLOBAL ==================
int      g_zzHandle;
datetime g_lastBarTime = 0;
datetime g_lastPivotTime = 0; // hindari entry ganda pada pivot yang sama

//+------------------------------------------------------------------+
int OnInit()
  {
   g_zzHandle = iCustom(_Symbol, PERIOD_H4, "Examples\\ZigZag", ZZ_Depth, ZZ_Deviation, ZZ_Backstep);
   if(g_zzHandle == INVALID_HANDLE)
     {
      Print("ERROR: Gagal load indikator ZigZag. Pastikan 'Examples\\ZigZag' tersedia di terminal Anda.");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(g_zzHandle != INVALID_HANDLE) IndicatorRelease(g_zzHandle);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime currentBarTime = iTime(_Symbol, PERIOD_H4, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   if(UseSessionFilter && IsAvoidSession()) return;
   if(UseSpreadFilter && IsSpreadHigh())    return;
   if(OnePositionOnly && PositionSelect(_Symbol)) return;

   int signal = EvaluateZigZagBOS();
   if(signal == 1)  ExecuteTrade(ORDER_TYPE_BUY);
   if(signal == -1) ExecuteTrade(ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
//| Ambil N pivot ZigZag terkonfirmasi terakhir (index bar & harga) |
//| pivots[0] = pivot TERBARU, pivots[N-1] = pivot TERLAMA           |
//+------------------------------------------------------------------+
bool GetLastPivots(int count, int &pivotBarIdx[], double &pivotPrice[])
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   int lookback = 300; // scan 300 candle ke belakang untuk cari pivot
   if(CopyBuffer(g_zzHandle, 0, 1, lookback, buf) <= 0) return false; // mulai dari idx 1 (skip candle berjalan)
   ArraySetAsSeries(buf, true);

   int found = 0;
   ArrayResize(pivotBarIdx, count);
   ArrayResize(pivotPrice, count);

   for(int i=0; i<lookback && found<count; i++)
     {
      if(buf[i] != 0.0 && buf[i] != EMPTY_VALUE)
        {
         pivotBarIdx[found] = i+1; // +1 karena CopyBuffer mulai dari shift 1
         pivotPrice[found]  = buf[i];
         found++;
        }
     }
   return (found == count);
  }

//+------------------------------------------------------------------+
//| Logika utama: Break of Structure via ZigZag                     |
//| return 1 = buy, -1 = sell, 0 = none                              |
//+------------------------------------------------------------------+
int EvaluateZigZagBOS()
  {
   int pivotBarIdx[];
   double pivotPrice[];

   if(!GetLastPivots(4, pivotBarIdx, pivotPrice)) return 0; // data pivot belum cukup

   // pivot[0]=terbaru ... pivot[3]=terlama
   // Cek apakah pivot terbaru sudah pernah diproses (hindari entry ganda)
   datetime pivotTime = iTime(_Symbol, PERIOD_H4, pivotBarIdx[0]);
   if(pivotTime == g_lastPivotTime) return 0;

   double p0 = pivotPrice[0]; // terbaru
   double p1 = pivotPrice[1];
   double p2 = pivotPrice[2];
   double p3 = pivotPrice[3]; // terlama

   // Tentukan apakah p0 adalah pivot LOW atau HIGH dengan membandingkan ke p1
   bool p0IsLow = (p0 < p1);

   // Struktur UPTREND: pivot low naik (p0 low > p2 low) DAN pivot high naik (p1 high > p3 high)
   // p0=low, p1=high, p2=low, p3=high (alternating dari terbaru ke terlama)
   if(p0IsLow)
     {
      double low_new = p0, low_old = p2;
      double high_new = p1, high_old = p3;

      // Higher-low DAN higher-high -> uptrend intact -> BUY di konfirmasi higher-low
      if(low_new > low_old && high_new > high_old)
        {
         g_lastPivotTime = pivotTime;
         return 1;
        }

      // Lower-low DAN lower-high -> downtrend intact, p0 low ini adalah continuation -> tidak entry buy
      // (opsional: bisa jadi entry SELL breakout jika low_new < low_old signifikan, tapi disederhanakan skip)
     }
   else // p0 adalah pivot HIGH
     {
      double high_new = p0, high_old = p2;
      double low_new  = p1, low_old  = p3;

      // Lower-high DAN lower-low -> downtrend intact -> SELL di konfirmasi lower-high
      if(high_new < high_old && low_new < low_old)
        {
         g_lastPivotTime = pivotTime;
         return -1;
        }
     }

   g_lastPivotTime = pivotTime; // tandai sudah diproses meski tidak entry, agar tidak dievaluasi ulang
   return 0;
  }

//+------------------------------------------------------------------+
bool IsAvoidSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(AvoidStartHour <= AvoidEndHour)
      return (h >= AvoidStartHour && h < AvoidEndHour);
   else
      return (h >= AvoidStartHour || h < AvoidEndHour);
  }

bool IsSpreadHigh()
  {
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPoints > MaxSpreadPoints);
  }

//+------------------------------------------------------------------+
//| Eksekusi Trade dengan Lot Static                                 |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
  {
   int pivotBarIdx[];
   double pivotPrice[];
   if(!GetLastPivots(2, pivotBarIdx, pivotPrice)) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp, entry;

   if(type == ORDER_TYPE_BUY)
     {
      entry = ask;
      sl = pivotPrice[0] - SL_BufferPoints*point; // di bawah pivot low terbaru
      tp = entry + (entry - sl) * RiskRewardRatio;
     }
   else
     {
      entry = bid;
      sl = pivotPrice[0] + SL_BufferPoints*point; // di atas pivot high terbaru
      tp = entry - (sl - entry) * RiskRewardRatio;
     }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot = MathMax(minLot, MathMin(maxLot, LotSize));

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, _Symbol, entry, sl, tp, "ZigZagBOS_Buy");
   else
      trade.Sell(lot, _Symbol, entry, sl, tp, "ZigZagBOS_Sell");
  }
//+------------------------------------------------------------------+
