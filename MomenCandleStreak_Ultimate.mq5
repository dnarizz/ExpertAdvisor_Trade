//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate.mq5                                   |
//| Strategi: 3 candle H-berturut searah -> entry searah momentum   |
//| (Three White Soldiers / Three Black Crows, versi naif tanpa      |
//| filter, sesuai permintaan eksplisit user)                        |
//|                                                                    |
//| CATATAN WAJIB:                                                    |
//| - TANPA FILTER berarti sinyal akan trigger di choppy market juga |
//|   -- ini bukan bug, ini konsekuensi dari spesifikasi yang dipilih.|
//| - Belum divalidasi backtest historis riil.                       |
//| - Fixed SL/TP dalam points, tidak menyesuaikan volatilitas.       |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Cakupan Symbol & Timeframe ==="
input string SymbolList          = "US100,EURUSD,XAUUSD"; // pisahkan koma, tanpa spasi
input string TimeframeList       = "H4,H1";                // M15,M30,H1,H4,D1

input group "=== Strategi ==="
input int    StreakCount         = 3;      // jumlah candle berurutan searah yang dipersyaratkan

input group "=== Lot & Risk (Fixed SL/TP) ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.01;   // EDIT MANUAL di sini jika UseStaticLot = true
input double RiskPercentPerTrade = 1.0;    // dipakai jika UseStaticLot = false
input double SL_Points           = 300;    // fixed, dalam points (sesuaikan per instrumen manual)
input double TP_Points           = 600;    // fixed, dalam points

input group "=== Filter Umum (opsional, di luar filter sinyal candle) ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadPoints     = 300;
input bool   UseSessionFilter    = true;
input int    AvoidStartHour      = 23;
input int    AvoidEndHour        = 1;
input bool   OnePositionPerSymbol = true;
input int    MaxTotalOpenPositions = 5;

//================== STRUCT & GLOBAL ==================
struct SymTFState
  {
   string           symbol;
   ENUM_TIMEFRAMES  tf;
   datetime         lastBarTime;
  };

SymTFState g_states[];

//+------------------------------------------------------------------+
int OnInit()
  {
   string symbols[];
   string tfs[];
   int nSym = StringSplit(SymbolList, ',', symbols);
   int nTf  = StringSplit(TimeframeList, ',', tfs);

   if(nSym <= 0 || nTf <= 0)
     {
      Print("ERROR: SymbolList atau TimeframeList kosong/invalid.");
      return(INIT_FAILED);
     }

   ArrayResize(g_states, nSym * nTf);
   int idx = 0;

   for(int s=0; s<nSym; s++)
     {
      string sym = symbols[s];
      StringTrimLeft(sym); StringTrimRight(sym);

      if(!SymbolSelect(sym, true))
        {
         Print("WARNING: Symbol '", sym, "' tidak ditemukan di broker, dilewati.");
         continue;
        }

      for(int t=0; t<nTf; t++)
        {
         string tfStr = tfs[t];
         StringTrimLeft(tfStr); StringTrimRight(tfStr);
         ENUM_TIMEFRAMES tf = StringToTimeframe(tfStr);
         if(tf == PERIOD_CURRENT)
           {
            Print("WARNING: Timeframe '", tfStr, "' tidak dikenali, dilewati.");
            continue;
           }

         g_states[idx].symbol = sym;
         g_states[idx].tf = tf;
         g_states[idx].lastBarTime = 0;
         idx++;
        }
     }

   ArrayResize(g_states, idx);
   Print("EA aktif untuk ", idx, " kombinasi symbol/timeframe. Streak requirement: ", StreakCount, " candle.");

   if(idx == 0)
     {
      Print("ERROR: Tidak ada kombinasi symbol/timeframe valid. EA berhenti.");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringToTimeframe(string s)
  {
   if(s=="M1")  return PERIOD_M1;
   if(s=="M5")  return PERIOD_M5;
   if(s=="M15") return PERIOD_M15;
   if(s=="M30") return PERIOD_M30;
   if(s=="H1")  return PERIOD_H1;
   if(s=="H4")  return PERIOD_H4;
   if(s=="D1")  return PERIOD_D1;
   if(s=="W1")  return PERIOD_W1;
   return PERIOD_CURRENT;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0; i<ArraySize(g_states); i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime currentBarTime = iTime(sym, tf, 0);
      if(currentBarTime == g_states[i].lastBarTime) continue;
      g_states[i].lastBarTime = currentBarTime;

      if(UseSessionFilter && IsAvoidSession()) continue;
      if(UseSpreadFilter && IsSpreadHigh(sym)) continue;
      if(OnePositionPerSymbol && PositionSelect(sym)) continue;

      int signal = EvaluateStreak(sym, tf);
      if(signal == 1)  ExecuteTrade(sym, ORDER_TYPE_BUY);
      if(signal == -1) ExecuteTrade(sym, ORDER_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Evaluasi streak N candle berurutan searah (murni tanpa filter)  |
//| Candle index 1 = candle terakhir yang closed, dst.               |
//| return 1 = buy, -1 = sell, 0 = none                              |
//+------------------------------------------------------------------+
int EvaluateStreak(string sym, ENUM_TIMEFRAMES tf)
  {
   bool allGreen = true, allRed = true;

   for(int i=1; i<=StreakCount; i++)
     {
      double o = iOpen(sym, tf, i);
      double c = iClose(sym, tf, i);

      if(c <= o) allGreen = false; // candle ini bukan hijau (close > open)
      if(c >= o) allRed = false;   // candle ini bukan merah (close < open)
     }

   if(allGreen) return 1;
   if(allRed)   return -1;
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

bool IsSpreadHigh(string sym)
  {
   double spreadPoints = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   return (spreadPoints > MaxSpreadPoints);
  }

//+------------------------------------------------------------------+
double CalculateDynamicLot(string sym, double slPoints)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercentPerTrade/100.0);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(tickValue<=0 || tickSize<=0 || point<=0) return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);

   double valuePerPoint = tickValue * (point/tickSize);
   double lot = riskAmount / (slPoints * valuePerPoint);

   double minLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double lotStep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot/lotStep)*lotStep;
   if(lot<minLot) lot=minLot;
   if(lot>maxLot) lot=maxLot;
   return lot;
  }

//+------------------------------------------------------------------+
void ExecuteTrade(string sym, ENUM_ORDER_TYPE type)
  {
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   double sl, tp, entry;

   if(type == ORDER_TYPE_BUY)
     {
      entry = ask;
      sl = entry - SL_Points*point;
      tp = entry + TP_Points*point;
     }
   else
     {
      entry = bid;
      sl = entry + SL_Points*point;
      tp = entry - TP_Points*point;
     }

   double lot = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, SL_Points);
   double minLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   lot = MathMax(minLot, MathMin(maxLot, lot));

   trade.SetExpertMagicNumber(654321);
   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, sym, entry, sl, tp, "Streak3_Buy_"+sym);
   else
      trade.Sell(lot, sym, entry, sl, tp, "Streak3_Sell_"+sym);
  }
//+------------------------------------------------------------------+
