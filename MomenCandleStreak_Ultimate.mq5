#property copyright "Custom EA - Educational/Experimental Use"
#property version   "6.00"
// v1.5: base dari v1.4, breakeven sekali-jalan DIGANTI trailing stop kontinu:
// tiap floating profit bertambah 10% dari R, SL ikut naik 10% dari R.
// Jarak trailing tetap = 1R (lebar SL awal), SL hanya maju, tidak pernah mundur.
// Pada profit = 100% R (1:1), SL otomatis di breakeven -- konsisten dgn v5.
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Cakupan Symbol & Timeframe ==="
input string SymbolList          = "USTEC";
input string TimeframeList       = "H1";

input group "=== Strategi ==="
input int    StreakCount         = 2;

input group "=== Lot ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.01;
input double RiskPercentPerTrade = 1.0;   // dipakai jika UseStaticLot = false

input group "=== SL Otomatis & TP Fixed RR ==="
input double SL_BufferPoints     = 200;   // buffer tambahan di bawah/atas candle pertama (diubah sesuai permintaan)
input double RiskRewardRatio     = 1.5;   // TP = R x ratio ini. Bisa diubah manual (1.5 / 2.0 / dst) tanpa recompile
input double TrailStepPercent    = 10.0;  // tiap kelipatan X% dari R profit bertambah, SL naik X% dari R juga

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadPoints     = 500;   // diubah dari 300 ke 500 sesuai permintaan
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
   ManageTrailingStop(); // trailing kontinu tiap tick, step 10% dari R

   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0; i<ArraySize(g_states); i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime currentBarTime = iTime(sym, tf, 0);
      if(currentBarTime == g_states[i].lastBarTime) continue;
      g_states[i].lastBarTime = currentBarTime;

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

   string cmt = "S3v6|" + DoubleToString(R, _Digits); // simpan R untuk logika trailing

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, sym, entry, sl, tp, cmt);
   else
      trade.Sell(lot, sym, entry, sl, tp, cmt);
  }

//+------------------------------------------------------------------+
//| Trailing Stop Kontinu: tiap profit bertambah X% dari R, SL ikut  |
//| naik X% dari R. Jarak trailing konstan = 1R (lebar SL awal).     |
//| SL hanya bergerak maju (searah profit), tidak pernah mundur.     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double stepFraction = TrailStepPercent / 100.0; // 10% -> 0.10

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      string cmt = PositionGetString(POSITION_COMMENT);

      int sep = StringFind(cmt, "|");
      if(sep < 0) continue;
      double R = StringToDouble(StringSubstr(cmt, sep+1));
      if(R <= 0) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

      double profitR;
      if(type == POSITION_TYPE_BUY)
         profitR = (bid - entry) / R;
      else
         profitR = (entry - ask) / R;

      double stepsPassed = MathFloor(profitR / stepFraction);
      if(stepsPassed < 1) continue; // belum capai step pertama (10% R)

      // lockedR: jarak trailing tetap 1R di belakang harga saat ini,
      // diperbarui tiap kelipatan stepFraction. Pada profitR=1.0 (100% R),
      // lockedR = 0 -> SL persis di breakeven.
      double lockedR = -1.0 + stepsPassed * stepFraction;

      double newSL;
      if(type == POSITION_TYPE_BUY)
        {
         newSL = entry + lockedR * R;
         if(newSL > currentSL)
            trade.PositionModify(ticket, newSL, currentTP);
        }
      else
        {
         newSL = entry - lockedR * R;
         if(currentSL == 0 || newSL < currentSL)
            trade.PositionModify(ticket, newSL, currentTP);
        }
     }
  }
//+------------------------------------------------------------------+
