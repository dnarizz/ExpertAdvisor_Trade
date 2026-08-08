//+------------------------------------------------------------------+
//| US100_H4_PriceAction_EA.mq5                                      |
//| Rule A: Wick Rejection at Swing High/Low                         |
//| Rule B: Engulfing After Climax Move                               |
//| Rule C: Double Top/Bottom with Wick Rejection                    |
//|                                                                    |
//| CATATAN WAJIB DIBACA SEBELUM LIVE:                                |
//| - Kode ini BELUM divalidasi backtest historis riil.               |
//| - Parameter (multiplier, lookback, RR ratio) adalah default       |
//|   logis, BUKAN hasil optimasi statistik. Jalankan Strategy        |
//|   Tester di data Exness sebelum live, dan sesuaikan parameter.    |
//| - RiskPercentPerTrade & DailyMaxLossPercent sudah dikonfirmasi    |
//|   user pada level agresif (target 20%/hari, drawdown tanpa        |
//|   batas efektif). Ini BUKAN rekomendasi risk management,          |
//|   murni implementasi sesuai instruksi eksplisit.                  |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT: GENERAL ==================
input group "=== Rule Toggle ==="
input bool   UseRuleA          = true;   // Wick Rejection at Swing High/Low
input bool   UseRuleB          = true;   // Engulfing After Climax
input bool   UseRuleC          = true;   // Double Top/Bottom Rejection
input bool   RequireConfluence = false;  // true = butuh minimal 2 rule sepakat arah yang sama pada candle yang sama

input group "=== Risk & Money Management ==="
input double RiskPercentPerTrade = 4.0;     // % risk dari Daily Base Equity per trade
input double DailyTargetPercent  = 20.0;    // stop trading hari ini jika profit >= ini
input double DailyMaxLossPercent = 100.0;   // stop trading hari ini jika loss >= ini (100 = efektif tanpa batas)
input bool   ManualDBEOverride   = true;    // true = pakai ManualDBEValue, false = pakai equity real saat reset harian
input double ManualDBEValue      = 400000;  // Daily Base Equity manual (update sendiri per hari jika perlu)
input double RiskRewardRatio     = 2.0;     // TP = SL x ratio ini

input group "=== Filter: Spread & Sesi ==="
input bool   UseSpreadFilter   = true;
input double MaxSpreadPoints   = 300;    // maksimum spread (dalam point) untuk entry, sesuaikan dgn US100 Exness
input bool   UseSessionFilter  = true;
input int    AvoidStartHour    = 23;     // mulai hindari trading (server time), cover jelang market close/rollover
input int    AvoidEndHour      = 1;      // selesai hindari trading (server time)

input group "=== Rule A: Wick Rejection ==="
input int    SwingLookback_A   = 20;     // jumlah candle H4 utk cari swing high/low
input double ProximityPercent_A= 0.15;   // toleransi jarak ke swing level (%)
input double WickBodyRatio_A   = 2.0;    // wick minimal = X * body

input group "=== Rule B: Engulfing After Climax ==="
input int    ATR_Period_B      = 10;
input double ClimaxATRMulti_B  = 1.5;    // range candle klimaks minimal = X * ATR
input int    TrendConfirmCandles_B = 3;  // jumlah candle searah tren sebelum klimaks

input group "=== Rule C: Double Top/Bottom ==="
input int    FractalLookback_C = 5;      // fractal 5-candle utk deteksi swing
input int    MinCandleGap_C    = 5;      // jarak minimum antar swing1 & swing2
input double DoubleTolerance_C = 0.3;    // toleransi selisih harga swing1 vs swing2 (%)

//================== GLOBAL VARS ==================
double g_DailyBaseEquity;
datetime g_LastTradingDay = 0;
datetime g_LastBarTime    = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_DailyBaseEquity = ManualDBEOverride ? ManualDBEValue : AccountInfoDouble(ACCOUNT_EQUITY);
   g_LastTradingDay  = TimeCurrent();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // ---- Reset Daily Base Equity di hari trading baru ----
   MqlDateTime dtNow, dtLast;
   TimeToStruct(TimeCurrent(), dtNow);
   TimeToStruct(g_LastTradingDay, dtLast);
   if(dtNow.day != dtLast.day || dtNow.mon != dtLast.mon || dtNow.year != dtLast.year)
     {
      g_DailyBaseEquity = ManualDBEOverride ? ManualDBEValue : AccountInfoDouble(ACCOUNT_EQUITY);
      g_LastTradingDay  = TimeCurrent();
      Print("=== DAILY RESET === Base Equity baru: ", g_DailyBaseEquity);
     }

   // ---- Hanya proses saat candle H4 baru terbentuk ----
   datetime currentBarTime = iTime(_Symbol, PERIOD_H4, 0);
   if(currentBarTime == g_LastBarTime) return;
   g_LastBarTime = currentBarTime;

   // ---- Circuit breaker harian ----
   if(!CanTradeToday())
     {
      Print("Circuit breaker aktif: target/loss harian tercapai. Trading dihentikan sampai reset besok.");
      return;
     }

   // ---- Filter sesi (hindari jam market tutup/rollover, spread tinggi) ----
   if(UseSessionFilter && IsAvoidSession())
     {
      Print("Skip: dalam sesi avoid (jelang market close/rollover).");
      return;
     }

   // ---- Filter spread tinggi ----
   if(UseSpreadFilter && IsSpreadHigh())
     {
      Print("Skip: spread saat ini di atas ambang batas.");
      return;
     }

   // ---- Sudah ada posisi terbuka? (opsional: cegah overlap, bisa dihapus jika mau layering) ----
   if(PositionSelect(_Symbol))
     {
      return; // hanya 1 posisi aktif per waktu; hapus blok ini jika ingin multi-posisi/layering
     }

   // ---- Evaluasi ketiga rule pada candle H4 index 1 (candle yang baru saja closed) ----
   int sigA = UseRuleA ? EvaluateRuleA() : 0;   // 1 = buy, -1 = sell, 0 = none
   int sigB = UseRuleB ? EvaluateRuleB() : 0;
   int sigC = UseRuleC ? EvaluateRuleC() : 0;

   int finalSignal = 0;

   if(RequireConfluence)
     {
      int buyVotes  = (sigA==1?1:0) + (sigB==1?1:0) + (sigC==1?1:0);
      int sellVotes = (sigA==-1?1:0) + (sigB==-1?1:0) + (sigC==-1?1:0);
      if(buyVotes  >= 2) finalSignal = 1;
      if(sellVotes >= 2) finalSignal = -1;
     }
   else
     {
      // prioritas: sinyal pertama yang muncul dieksekusi (A > B > C)
      if(sigA != 0)      finalSignal = sigA;
      else if(sigB != 0) finalSignal = sigB;
      else if(sigC != 0) finalSignal = sigC;
     }

   if(finalSignal == 1)  ExecuteTrade(ORDER_TYPE_BUY);
   if(finalSignal == -1) ExecuteTrade(ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
//| Circuit breaker: cek apakah masih boleh trading hari ini         |
//+------------------------------------------------------------------+
bool CanTradeToday()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double pnlPercent = (equity - g_DailyBaseEquity) / g_DailyBaseEquity * 100.0;

   if(pnlPercent >= DailyTargetPercent)  return false; // target tercapai
   if(pnlPercent <= -DailyMaxLossPercent) return false; // max loss tercapai
   return true;
  }

//+------------------------------------------------------------------+
//| Filter sesi: hindari jam market close/rollover                  |
//+------------------------------------------------------------------+
bool IsAvoidSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;

   if(AvoidStartHour <= AvoidEndHour)
      return (h >= AvoidStartHour && h < AvoidEndHour);
   else // wrap around midnight, e.g. 23 -> 1
      return (h >= AvoidStartHour || h < AvoidEndHour);
  }

//+------------------------------------------------------------------+
//| Filter spread tinggi                                             |
//+------------------------------------------------------------------+
bool IsSpreadHigh()
  {
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPoints > MaxSpreadPoints);
  }

//+------------------------------------------------------------------+
//| RULE A: Wick Rejection at Swing High/Low                        |
//| return 1 = buy signal, -1 = sell signal, 0 = none                |
//+------------------------------------------------------------------+
int EvaluateRuleA()
  {
   int idx = 1; // candle H4 yang baru closed
   double o = iOpen(_Symbol, PERIOD_H4, idx);
   double c = iClose(_Symbol, PERIOD_H4, idx);
   double h = iHigh(_Symbol, PERIOD_H4, idx);
   double l = iLow(_Symbol, PERIOD_H4, idx);

   double body = MathAbs(c - o);
   double upperWick = h - MathMax(o,c);
   double lowerWick = MathMin(o,c) - l;
   if(body < _Point) body = _Point; // hindari div by zero pada doji

   double swingHigh = FindSwingHigh(SwingLookback_A, idx+1);
   double swingLow  = FindSwingLow(SwingLookback_A, idx+1);

   double tolHigh = swingHigh * (ProximityPercent_A/100.0);
   double tolLow  = swingLow  * (ProximityPercent_A/100.0);

   // SELL: upper wick panjang + dekat swing high + close di 1/3 bawah range
   if(upperWick >= WickBodyRatio_A * body &&
      h >= swingHigh - tolHigh &&
      c <= l + 0.33*(h-l))
      return -1;

   // BUY: lower wick panjang + dekat swing low + close di 1/3 atas range
   if(lowerWick >= WickBodyRatio_A * body &&
      l <= swingLow + tolLow &&
      c >= l + 0.67*(h-l))
      return 1;

   return 0;
  }

//+------------------------------------------------------------------+
//| RULE B: Engulfing After Climax Move                              |
//+------------------------------------------------------------------+
int EvaluateRuleB()
  {
   int idx = 1;
   double atr = iATR_Value(ATR_Period_B, idx+1);
   if(atr <= 0) return 0;

   double rangePrev = iHigh(_Symbol,PERIOD_H4,idx+1) - iLow(_Symbol,PERIOD_H4,idx+1);
   bool isClimax = (rangePrev >= ClimaxATRMulti_B * atr);
   if(!isClimax) return 0;

   // cek trend confirm candles sebelum candle klimaks
   bool downTrendBefore = true, upTrendBefore = true;
   for(int i=idx+2; i<idx+2+TrendConfirmCandles_B; i++)
     {
      if(iClose(_Symbol,PERIOD_H4,i) <= iClose(_Symbol,PERIOD_H4,i+1)) downTrendBefore = false;
      if(iClose(_Symbol,PERIOD_H4,i) >= iClose(_Symbol,PERIOD_H4,i+1)) upTrendBefore = false;
     }

   double oPrev = iOpen(_Symbol,PERIOD_H4,idx+1);
   double cPrev = iClose(_Symbol,PERIOD_H4,idx+1);
   double oCur  = iOpen(_Symbol,PERIOD_H4,idx);
   double cCur  = iClose(_Symbol,PERIOD_H4,idx);

   // bullish engulfing setelah downtrend klimaks
   if(downTrendBefore && cPrev < oPrev && cCur > oCur &&
      oCur <= cPrev && cCur >= oPrev)
      return 1;

   // bearish engulfing setelah uptrend klimaks
   if(upTrendBefore && cPrev > oPrev && cCur < oCur &&
      oCur >= cPrev && cCur <= oPrev)
      return -1;

   return 0;
  }

//+------------------------------------------------------------------+
//| RULE C: Double Top/Bottom with Wick Rejection                   |
//+------------------------------------------------------------------+
int EvaluateRuleC()
  {
   int idx = 1;
   double swing1H=0, swing2H=0; int swing1Idx=-1, swing2Idx=-1;
   double swing1L=0, swing2L=0;

   // cari 2 fractal high terakhir
   int found=0;
   for(int i=idx+FractalLookback_C/2; i<idx+80 && found<2; i++)
     {
      if(IsFractalHigh(i))
        {
         if(found==0){ swing1H=iHigh(_Symbol,PERIOD_H4,i); swing1Idx=i; found++; }
         else { swing2H=iHigh(_Symbol,PERIOD_H4,i); swing2Idx=i; found++; }
        }
     }
   if(found==2 && MathAbs(swing1Idx-swing2Idx) >= MinCandleGap_C)
     {
      double diffPct = MathAbs(swing1H-swing2H)/swing1H*100.0;
      if(diffPct <= DoubleTolerance_C)
        {
         // cek wick rejection di swing terbaru (swing1, index lebih kecil = lebih baru)
         double h=iHigh(_Symbol,PERIOD_H4,swing1Idx), o=iOpen(_Symbol,PERIOD_H4,swing1Idx);
         double c=iClose(_Symbol,PERIOD_H4,swing1Idx), l=iLow(_Symbol,PERIOD_H4,swing1Idx);
         double body=MathAbs(c-o); if(body<_Point) body=_Point;
         double upperWick=h-MathMax(o,c);
         if(upperWick >= WickBodyRatio_A*body) return -1; // double top -> sell
        }
     }

   found=0;
   for(int i=idx+FractalLookback_C/2; i<idx+80 && found<2; i++)
     {
      if(IsFractalLow(i))
        {
         if(found==0){ swing1L=iLow(_Symbol,PERIOD_H4,i); swing1Idx=i; found++; }
         else { swing2L=iLow(_Symbol,PERIOD_H4,i); swing2Idx=i; found++; }
        }
     }
   if(found==2 && MathAbs(swing1Idx-swing2Idx) >= MinCandleGap_C)
     {
      double diffPct = MathAbs(swing1L-swing2L)/swing1L*100.0;
      if(diffPct <= DoubleTolerance_C)
        {
         double h=iHigh(_Symbol,PERIOD_H4,swing1Idx), o=iOpen(_Symbol,PERIOD_H4,swing1Idx);
         double c=iClose(_Symbol,PERIOD_H4,swing1Idx), l=iLow(_Symbol,PERIOD_H4,swing1Idx);
         double body=MathAbs(c-o); if(body<_Point) body=_Point;
         double lowerWick=MathMin(o,c)-l;
         if(lowerWick >= WickBodyRatio_A*body) return 1; // double bottom -> buy
        }
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Helper: Fractal detection                                        |
//+------------------------------------------------------------------+
bool IsFractalHigh(int i)
  {
   double h = iHigh(_Symbol,PERIOD_H4,i);
   return (h > iHigh(_Symbol,PERIOD_H4,i-1) && h > iHigh(_Symbol,PERIOD_H4,i-2) &&
           h > iHigh(_Symbol,PERIOD_H4,i+1) && h > iHigh(_Symbol,PERIOD_H4,i+2));
  }
bool IsFractalLow(int i)
  {
   double l = iLow(_Symbol,PERIOD_H4,i);
   return (l < iLow(_Symbol,PERIOD_H4,i-1) && l < iLow(_Symbol,PERIOD_H4,i-2) &&
           l < iLow(_Symbol,PERIOD_H4,i+1) && l < iLow(_Symbol,PERIOD_H4,i+2));
  }

//+------------------------------------------------------------------+
//| Helper: Swing High/Low sederhana (MAX/MIN dalam lookback)       |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookback, int startIdx)
  {
   double h = iHigh(_Symbol,PERIOD_H4,startIdx);
   for(int i=startIdx; i<startIdx+lookback; i++)
      if(iHigh(_Symbol,PERIOD_H4,i) > h) h = iHigh(_Symbol,PERIOD_H4,i);
   return h;
  }
double FindSwingLow(int lookback, int startIdx)
  {
   double l = iLow(_Symbol,PERIOD_H4,startIdx);
   for(int i=startIdx; i<startIdx+lookback; i++)
      if(iLow(_Symbol,PERIOD_H4,i) < l) l = iLow(_Symbol,PERIOD_H4,i);
   return l;
  }

//+------------------------------------------------------------------+
//| Helper: ATR value via handle-free calculation (manual)          |
//+------------------------------------------------------------------+
double iATR_Value(int period, int shift)
  {
   int handle = iATR(_Symbol, PERIOD_H4, period);
   if(handle == INVALID_HANDLE) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0) return 0;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| Position Sizing berbasis Daily Base Equity (fixed, bukan        |
//| dynamic equity) sesuai instruksi eksplisit user                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPoints)
  {
   double riskAmount = g_DailyBaseEquity * (RiskPercentPerTrade/100.0);
   double tickValue   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickValue<=0 || tickSize<=0 || point<=0) return 0.01;

   double valuePerPoint = tickValue * (point/tickSize);
   double lot = riskAmount / (slPoints * valuePerPoint);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot/lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   return lot;
  }

//+------------------------------------------------------------------+
//| Eksekusi Trade                                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
  {
   int idx = 1;
   double h = iHigh(_Symbol,PERIOD_H4,idx);
   double l = iLow(_Symbol,PERIOD_H4,idx);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp, entry, slPoints;

   if(type == ORDER_TYPE_BUY)
     {
      entry = ask;
      sl = l - 5*point;               // SL di bawah low candle sinyal, buffer 5 point
      slPoints = (entry - sl)/point;
      tp = entry + (entry-sl)*RiskRewardRatio;
     }
   else
     {
      entry = bid;
      sl = h + 5*point;               // SL di atas high candle sinyal, buffer 5 point
      slPoints = (sl - entry)/point;
      tp = entry - (sl-entry)*RiskRewardRatio;
     }

   if(slPoints <= 0) { Print("SL invalid, skip trade."); return; }

   double lot = CalculateLotSize(slPoints);
   if(lot <= 0) { Print("Lot size invalid, skip trade."); return; }

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, _Symbol, entry, sl, tp, "RuleEA_Buy");
   else
      trade.Sell(lot, _Symbol, entry, sl, tp, "RuleEA_Sell");
  }
//+------------------------------------------------------------------+
