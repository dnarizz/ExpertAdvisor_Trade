//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate_V1.1.mq5                |
//| Versi 1.1: SL otomatis di high/low candle PERTAMA dari streak,     |
//| TP unlimited, trailing stop step-wise berbasis kelipatan R.      |
//|                                                                    |
//| LOGIKA TRAILING (wajib dipahami sebelum live):                   |
//|   R = jarak awal entry ke SL awal                                 |
//|   Floating profit >= 2R -> SL pindah ke Breakeven (0R)           |
//|   Floating profit >= 3R -> SL pindah ke 1R                        |
//|   Floating profit >= 4R -> SL pindah ke 2R, dst (step = N-2)      |
//|   SL HANYA bergerak searah profit, tidak pernah mundur.           |
//|                                                                    |
//| CATATAN WAJIB:                                                    |
//| - Belum divalidasi backtest historis riil.                       |
//| - "TP unlimited" berarti profit hanya dibatasi oleh kapan harga  |
//|   berbalik menyentuh trailing SL -- bukan tanpa risiko, hanya    |
//|   tanpa batas atas.                                               |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "2.00"
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

input group "=== SL Otomatis & Trailing ==="
input double SL_BufferPoints     = 0;     // buffer tambahan di bawah/atas candle pertama, 0 = tepat di high/low
input double TrailStartRR        = 2.0;   // mulai trailing (pindah ke BEP) saat profit = X * R
input double TrailStepRR         = 1.0;   // tiap kenaikan profit sebesar ini (dalam R), SL maju 1 step (mundur TrailStartRR)

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadPoints     = 300;
input bool   UseSessionFilter    = true;
input int    AvoidStartHour      = 23;
input int    AvoidEndHour        = 1;
input bool   OnePositionPerSymbol = true;
input int    MaxTotalOpenPositions = 5;
input int    MagicNumber          = 777001;

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
   Print("EA v2 aktif untuk ", idx, " kombinasi symbol/timeframe.");
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
   // Trailing dievaluasi TIAP TICK (bukan hanya candle baru) agar responsif
   ManageTrailingStop();

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
//| Entry: SL = high/low candle PERTAMA dari streak (index tertua)  |
//| Komentar posisi menyimpan R (jarak SL awal) untuk trailing.     |
//+------------------------------------------------------------------+
void ExecuteTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type)
  {
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);

   int firstCandleIdx = StreakCount; // candle tertua dalam streak
   double sl, entry, R;

   if(type == ORDER_TYPE_BUY)
     {
      entry = ask;
      sl = iLow(sym, tf, firstCandleIdx) - SL_BufferPoints*point;
      R = entry - sl;
     }
   else
     {
      entry = bid;
      sl = iHigh(sym, tf, firstCandleIdx) + SL_BufferPoints*point;
      R = sl - entry;
     }

   if(R <= 0) { Print("SL invalid untuk ", sym, ", skip trade."); return; }

   double slPoints = R/point;
   double lot = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, slPoints);
   double minLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   lot = MathMax(minLot, MathMin(maxLot, lot));

   // Simpan R di comment untuk dipakai fungsi trailing (TP=0, unlimited)
   string cmt = "S3v2|" + DoubleToString(R, _Digits);

   if(type == ORDER_TYPE_BUY)
      trade.Buy(lot, sym, entry, sl, 0, cmt);
   else
      trade.Sell(lot, sym, entry, sl, 0, cmt);
  }

//+------------------------------------------------------------------+
//| Trailing Stop Step-wise berbasis kelipatan R                    |
//| profit >= 2R -> SL di BEP (0R)                                    |
//| profit >= 3R -> SL di 1R, profit >= 4R -> SL di 2R, dst           |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      string cmt = PositionGetString(POSITION_COMMENT);

      // Parse R dari comment "S3v2|<R>"
      int sep = StringFind(cmt, "|");
      if(sep < 0) continue;
      double R = StringToDouble(StringSubstr(cmt, sep+1));
      if(R <= 0) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      long type = PositionGetInteger(POSITION_TYPE);

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

      double profitR;
      if(type == POSITION_TYPE_BUY)
         profitR = (bid - entry) / R;
      else
         profitR = (entry - ask) / R;

      if(profitR < TrailStartRR) continue; // belum capai ambang trailing pertama (2R)

      // step level: berapa kali TrailStepRR sudah terlampaui SETELAH TrailStartRR
      double stepsPassed = MathFloor((profitR - TrailStartRR) / TrailStepRR);
      double lockedR = stepsPassed * TrailStepRR; // 0 = BEP, 1 = 1R, 2 = 2R, dst

      double newSL;
      if(type == POSITION_TYPE_BUY)
        {
         newSL = entry + lockedR * R;
         if(newSL > currentSL) // hanya maju, tidak pernah mundur
            trade.PositionModify(ticket, newSL, 0);
        }
      else
        {
         newSL = entry - lockedR * R;
         if(currentSL == 0 || newSL < currentSL)
            trade.PositionModify(ticket, newSL, 0);
        }
     }
  }
//+------------------------------------------------------------------+
