//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate_V1.3.mq5                  |
//| Versi 1.3: SAMA seperti v1.2 (SL otomatis di candle pertama streak,  |
//| TP fixed RR 1:1.5), TAPI mengizinkan MULTIPLE posisi terbuka     |
//| bersamaan pada symbol yang sama (OnePositionPerSymbol = false).  |
//|                                                                    |
//| KONSEKUENSI WAJIB DIPAHAMI (bukan bug, ini efek langsung dari    |
//| menghilangkan batas 1 posisi/symbol):                             |
//| - Jika streak baru muncul beruntun (mis. candle 4,5,6 juga       |
//|   hijau setelah sinyal pertama di candle 1-3), EA akan membuka   |
//|   posisi BUY baru lagi di symbol yang sama, menumpuk eksposur.   |
//| - Total risk per symbol menjadi PERKALIAN dari jumlah posisi     |
//|   yang menumpuk -- 3 posisi menumpuk dgn risk 1% masing-masing   |
//|   = 3% risk riil pada symbol itu saat itu juga.                  |
//| - MaxTotalOpenPositions tetap jadi pengaman utama, pastikan      |
//|   nilainya sudah disesuaikan dgn toleransi margin akun Anda.     |
//|                                                                    |
//| CATATAN WAJIB: belum divalidasi backtest historis riil.          |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "4.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Cakupan Symbol & Timeframe ==="
input string SymbolList          = "US100,EURUSD,XAUUSD";
input string TimeframeList       = "H4,H1";

input group "=== Strategi ==="
input int    StreakCount         = 3;

input group "=== Lot ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.01;
input double RiskPercentPerTrade = 1.0;   // dipakai jika UseStaticLot = false

input group "=== SL Otomatis & TP Fixed RR ==="
input double SL_BufferPoints     = 0;     // buffer tambahan di bawah/atas candle pertama, 0 = tepat di high/low
input double RiskRewardRatio     = 1.5;   // TP = R x ratio ini (sesuai permintaan: 1:1.5)

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadPoints     = 300;
input bool   UseSessionFilter    = true;
input int    AvoidStartHour      = 23;
input int    AvoidEndHour        = 1;
input bool   OnePositionPerSymbol = false;  // v4: default false, izinkan multiple posisi per symbol
input int    MaxTotalOpenPositions = 10;    // dinaikkan dari default v3 (5) karena posisi bisa menumpuk per symbol
input int    MagicNumber          = 777004;

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
   string symbols[]; string tfs[];
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
         Print("WARNING: Symbol '", sym, "' tidak ditemukan, dilewati.");
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
   Print("EA v4 (multi-position) aktif untuk ", idx, " kombinasi symbol/timeframe. RR = 1:", RiskRewardRatio, " | OnePositionPerSymbol=", OnePositionPerSymbol);
   if(idx == 0) { Print("ERROR: Tidak ada kombinasi valid."); return(INIT_FAILED); }

   trade.SetExpertMagicNumber(MagicNumber);
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
      if(signal == 1)  ExecuteTrade(sym, tf, ORDER_TYPE_BUY);
      if(signal == -1) ExecuteTrade(sym, tf, ORDER_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
int EvaluateStreak(string sym, ENUM_TIMEFRAMES tf)
  {
   bool allGreen = true, allRed = true;
   for(int i=1; i<=StreakCount; i++)
     {
      double o = iOpen(sym, tf, i);
      double c = iClose(sym, tf, i);
      if(c <= o) allGreen = false;
      if(c >= o) allRed = false;
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
//| Entry: SL = high/low candle PERTAMA streak, TP = R x RiskReward |
//+------------------------------------------------------------------+
void ExecuteTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type)
  {
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   int firstCandleIdx = StreakCount;
   double sl, tp, entry, R;

   if(type == ORDER_TYPE_BUY)
     {
      entry = ask;
      sl = iLow(sym, tf, firstCandleIdx) - SL_BufferPoints*point;
      R = entry - sl;
      tp = entry + R * RiskRewardRatio;
     }
   else
     {
      entry = bid;
      sl = iHigh(sym, tf, firstCandleIdx) + SL_BufferPoints*point;
      R = sl - entry;
      tp = entry - R * RiskRewardRatio;
     }

   if(R <= 0) { Print("SL invalid untuk ", sym, ", skip trade."); return; }

   double slPoints = R/point;
   double lot = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, slPoints);
   double minLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   lot = MathMax(minLot, MathMin(maxLot, lot));

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, sym, entry, sl, tp, "S3v4_Buy_"+sym);
   else
      trade.Sell(lot, sym, entry, sl, tp, "S3v4_Sell_"+sym);
  }
//+------------------------------------------------------------------+
