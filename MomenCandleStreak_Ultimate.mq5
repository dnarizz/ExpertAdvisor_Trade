//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate_v1.6.mq5                   |
//| Base: v1.3 (multi symbol/timeframe, multiple posisi per symbol)    |
//|                                                                    |
//| PERUBAHAN v1.6:                                                     |
//| 1. Entry TIDAK market langsung -- EA memasang PENDING LIMIT ORDER|
//|    menunggu harga retrace 65% ke dalam range candle SEBELUMNYA   |
//|    (candle index 1, candle terakhir yang closed dari streak).    |
//|    BUY  -> limit price = High(1) - RetracePercent*(High-Low)     |
//|    SELL -> limit price = Low(1)  + RetracePercent*(High-Low)     |
//|    Order kadaluarsa otomatis di akhir candle berjalan jika tidak |
//|    ter-fill (ORDER_TIME_SPECIFIED, expiration = open candle 0).  |
//| 2. RiskRewardRatio tetap input -- ubah manual (1.0, 1.5, dst)    |
//|    tanpa recompile, tidak di-hardcode.                           |
//| 3. SL punya 2 MODE, dipilih via UseTrailingStop:                 |
//|    - true  -> trailing kontinu (step X% dari R, seperti v6)      |
//|    - false -> SL FIXED, tidak pernah dipindah sama sekali        |
//|      (murni fixed RR sesuai RiskRewardRatio, tanpa BEP/trailing) |
//|                                                                    |
//| CATATAN WAJIB: belum divalidasi backtest historis riil.          |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "7.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Cakupan Symbol & Timeframe ==="
input string SymbolList          = "US100,EURUSD,XAUUSD";
input string TimeframeList       = "H4,H1";

input group "=== Strategi ==="
input int    StreakCount         = 3;
input double RetracePercent      = 0.65;  // 65% retracement ke dalam candle sebelumnya

input group "=== Lot ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.01;
input double RiskPercentPerTrade = 1.0;   // dipakai jika UseStaticLot = false

input group "=== SL & TP ==="
input double SL_BufferPoints     = 200;
input double RiskRewardRatio     = 1.5;   // BISA DIUBAH MANUAL (mis. 1.0 utk RR 1:1), tanpa recompile

input group "=== Mode SL: Trailing vs Fixed ==="
input bool   UseTrailingStop     = false; // true = trailing kontinu aktif; false = SL FIXED, tidak pernah pindah
input double TrailStepPercent    = 10.0;  // dipakai HANYA jika UseTrailingStop = true

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadPoints     = 500;
input bool   OnePositionPerSymbol = false;
input int    MaxTotalOpenPositions = 10;
input int    MagicNumber          = 777007;

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
   Print("EA v7 aktif untuk ", idx, " kombinasi symbol/timeframe. RR=1:", RiskRewardRatio,
         " | Retrace=", RetracePercent*100, "% | TrailingMode=", UseTrailingStop);
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
   if(UseTrailingStop) ManageTrailingStop();

   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0; i<ArraySize(g_states); i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime currentBarTime = iTime(sym, tf, 0);
      if(currentBarTime == g_states[i].lastBarTime) continue;
      g_states[i].lastBarTime = currentBarTime;

      // Hapus pending order lama milik EA ini untuk symbol ini yang belum ter-fill
      // (candle sebelumnya sudah closed, order retracement lama sudah tidak relevan)
      DeleteStalePendingOrders(sym);

      if(UseSpreadFilter && IsSpreadHigh(sym)) continue;
      if(OnePositionPerSymbol && PositionSelect(sym)) continue;

      int signal = EvaluateStreak(sym, tf);
      if(signal == 1)  PlacePendingOrder(sym, tf, ORDER_TYPE_BUY_LIMIT, currentBarTime);
      if(signal == -1) PlacePendingOrder(sym, tf, ORDER_TYPE_SELL_LIMIT, currentBarTime);
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
void DeleteStalePendingOrders(string sym)
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;

      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT)
         trade.OrderDelete(ticket);
     }
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
//| Pasang pending limit order menunggu retracement 65% ke candle    |
//| sebelumnya (index 1). SL dari high/low candle PERTAMA streak.    |
//+------------------------------------------------------------------+
void PlacePendingOrder(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE otype, datetime barTime)
  {
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);

   double h1 = iHigh(sym, tf, 1);   // candle sebelumnya (terakhir closed dari streak)
   double l1 = iLow(sym, tf, 1);
   double range1 = h1 - l1;
   if(range1 <= 0) return;

   int firstCandleIdx = StreakCount; // candle tertua dari streak, acuan SL
   double sl, tp, limitPrice, R;

   if(otype == ORDER_TYPE_BUY_LIMIT)
     {
      limitPrice = h1 - RetracePercent * range1;
      sl = iLow(sym, tf, firstCandleIdx) - SL_BufferPoints*point;
      R = limitPrice - sl;
      tp = limitPrice + R * RiskRewardRatio;
     }
   else
     {
      limitPrice = l1 + RetracePercent * range1;
      sl = iHigh(sym, tf, firstCandleIdx) + SL_BufferPoints*point;
      R = sl - limitPrice;
      tp = limitPrice - R * RiskRewardRatio;
     }

   if(R <= 0) { Print("SL invalid untuk ", sym, ", skip pending order."); return; }

   double slPoints = R/point;
   double lot = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, slPoints);
   double minLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   lot = MathMax(minLot, MathMin(maxLot, lot));

   // Expiration: order kadaluarsa saat candle berjalan ini berakhir
   datetime expiration = barTime + PeriodSeconds(tf);
   string cmt = "S3v7|" + DoubleToString(R, _Digits);

   if(otype == ORDER_TYPE_BUY_LIMIT)
      trade.BuyLimit(lot, limitPrice, sym, sl, tp, ORDER_TIME_SPECIFIED, expiration, cmt);
   else
      trade.SellLimit(lot, limitPrice, sym, sl, tp, ORDER_TIME_SPECIFIED, expiration, cmt);
  }

//+------------------------------------------------------------------+
//| Trailing Stop Kontinu (HANYA aktif jika UseTrailingStop = true) |
//| Step X% dari R, jarak trailing konstan = 1R.                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double stepFraction = TrailStepPercent / 100.0;

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
      if(stepsPassed < 1) continue;

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
   // Jika UseTrailingStop = false, fungsi ini tidak pernah dipanggil dari OnTick,
   // sehingga SL yang di-set saat PlacePendingOrder() akan TETAP, tidak pernah berubah.
  }
//+------------------------------------------------------------------+
