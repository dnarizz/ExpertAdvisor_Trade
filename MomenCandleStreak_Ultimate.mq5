//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate_V2.1.mq5                       |
//| Base: v1.6 (Multi Symbol/TF, Layering System & Consecutive Limit)  |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "7.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Cakupan Symbol & Timeframe ==="
input string SymbolList          = "USTEC";
input string TimeframeList       = "H1";

input group "=== Strategi & Layering ==="
input int    StreakCount         = 2;
input double RetracePercent      = 0.50; // Retrace x% dari candle kedua (50% = 0.50)
input int    MaxConsecutiveTrades= 3;    // BATASAN: Maksimal 3x trade berurutan pada tren tanpa henti

input group "=== Lot (Dynamic Nonaktif Default) ==="
input bool   UseStaticLot        = true; // Static Lot aktif secara default
input double StaticLotSize       = 0.01;
input double RiskPercentPerTrade = 1.0;  // Kode tetap ada, diaktifkan jika UseStaticLot = false

input group "=== Target TP & SL ==="
input double SL_BufferPoints     = 0;    // 0 = Tepat di harga Open candle lompatan pertama
input double RiskRewardRatio     = 1.0;  // Digunakan untuk TP Layer 1 (1:1 RR)

input group "=== Trailing Stop (Nonaktif Default) ==="
input bool   UseTrailingStop     = false;// Trailing SL sementara dinonaktifkan
input double TrailStepPercent    = 10.0; // Tetap ada di kode untuk kebutuhan mendatang

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = true;
input double MaxSpreadPoints     = 500;
input bool   OnePositionPerSymbol= false;
input int    MaxTotalOpenPositions = 10;
input int    MagicNumber         = 777007;

//================== STRUCT & GLOBAL ==================
struct SymTFState
  {
   string           symbol;
   ENUM_TIMEFRAMES  tf;
   datetime         lastBarTime;
   int              consecutiveTrades; // Menghitung akumulasi trade berurutan
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
      if(!SymbolSelect(sym, true)) continue;

      for(int t=0; t<nTf; t++)
        {
         string tfStr = tfs[t];
         StringTrimLeft(tfStr); StringTrimRight(tfStr);
         ENUM_TIMEFRAMES tf = StringToTimeframe(tfStr);
         if(tf == PERIOD_CURRENT) continue;

         g_states[idx].symbol = sym;
         g_states[idx].tf = tf;
         g_states[idx].lastBarTime = 0;
         g_states[idx].consecutiveTrades = 0;
         idx++;
        }
     }

   ArrayResize(g_states, idx);
   Print("EA v7 Layering Aktif | Layer 1 (Market 1:1) + Layer 2 (Limit Retrace ", RetracePercent*100, "%) | Max Sekuensial: ", MaxConsecutiveTrades);
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
   // Trailing SL tetap ada di kode tetapi nonaktif secara default
   if(UseTrailingStop) ManageTrailingStop();

   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0; i<ArraySize(g_states); i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime currentBarTime = iTime(sym, tf, 0);
      if(currentBarTime == g_states[i].lastBarTime) continue;
      g_states[i].lastBarTime = currentBarTime;

      // Hapus pending order Layer 2 yang belum ter-fill dari candle sebelumnya
      DeleteStalePendingOrders(sym);

      if(UseSpreadFilter && IsSpreadHigh(sym)) continue;
      if(OnePositionPerSymbol && PositionSelect(sym)) continue;

      int signal = EvaluateStreak(sym, tf);
      
      // Jika tren/streak terputus, reset hitungan sekuensial
      if(signal == 0)
        {
         g_states[i].consecutiveTrades = 0;
         continue;
        }

      // BATASAN: Jika sudah mencapai batas maksimal trade berurutan, lewati sinyal ini
      if(g_states[i].consecutiveTrades >= MaxConsecutiveTrades)
        {
         Print(sym, " - Mencapai batas maks ", MaxConsecutiveTrades, " trade sekuensial. Skip sinyal.");
         continue;
        }

      // Eksekusi Layer 1 & Pasang Pending Order Layer 2
      if(signal == 1)  ExecuteLayeredTrade(sym, tf, ORDER_TYPE_BUY, currentBarTime);
      if(signal == -1) ExecuteLayeredTrade(sym, tf, ORDER_TYPE_SELL, currentBarTime);

      g_states[i].consecutiveTrades++; // Tambah hitungan sekuensial
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
//| Eksekusi Layer 1 (Market Order) & Layer 2 (Pending Limit Order)  |
//+------------------------------------------------------------------+
void ExecuteLayeredTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type, datetime barTime)
  {
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);

   // Index Candle:
   // Candle 1 = Candle lompatan kedua (konfirmasi/terakhir closed)
   // Candle 2 = Candle lompatan pertama (candle awal streak jika StreakCount=2)
   int firstCandleIdx = StreakCount; 

   double h1 = iHigh(sym, tf, 1);
   double l1 = iLow(sym, tf, 1);
   double range1 = h1 - l1;
   if(range1 <= 0) return;

   // SL diambil dari harga Open candle lompatan pertama (Candle 2)
   // Catatan: Pada candle bearish (SELL), harga Open berada di ATAS (top body)
   double slLevel = iOpen(sym, tf, firstCandleIdx);

   // --- 1. EKSEKUSI LAYER 1 (Market Order Instant di Open Candle 0) ---
   double entryL1 = (type == ORDER_TYPE_BUY) ? ask : bid;
   double slL1    = (type == ORDER_TYPE_BUY) ? (slLevel - SL_BufferPoints*point) : (slLevel + SL_BufferPoints*point);
   double R1      = (type == ORDER_TYPE_BUY) ? (entryL1 - slL1) : (slL1 - entryL1);

   if(R1 > 0)
     {
      double tpL1  = (type == ORDER_TYPE_BUY) ? (entryL1 + R1 * RiskRewardRatio) : (entryL1 - R1 * RiskRewardRatio);
      double lotL1 = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, R1/point);

      if(type == ORDER_TYPE_BUY)
         trade.Buy(lotL1, sym, entryL1, slL1, tpL1, "S7_L1|" + DoubleToString(R1, _Digits));
      else
         trade.Sell(lotL1, sym, entryL1, slL1, tpL1, "S7_L1|" + DoubleToString(R1, _Digits));
     }

   // --- 2. EKSEKUSI LAYER 2 (Pending Limit Order Retrace x% Candle 2) ---
   double limitPriceL2, tpL2, slL2, R2;

   if(type == ORDER_TYPE_BUY)
     {
      limitPriceL2 = h1 - RetracePercent * range1;
      slL2         = slLevel - SL_BufferPoints*point;
      tpL2         = h1; // TP Layer 2 = High candle lompatan kedua
      R2           = limitPriceL2 - slL2;

      if(R2 > 0 && limitPriceL2 < ask) // Validasi agar tidak ditolak server MT5
        {
         double lotL2 = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, R2/point);
         datetime expr = barTime + PeriodSeconds(tf);
         trade.BuyLimit(lotL2, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2|" + DoubleToString(R2, _Digits));
        }
     }
   else // ORDER_TYPE_SELL
     {
      limitPriceL2 = l1 + RetracePercent * range1;
      slL2         = slLevel + SL_BufferPoints*point;
      tpL2         = l1; // TP Layer 2 = Low candle lompatan kedua
      R2           = slL2 - limitPriceL2;

      if(R2 > 0 && limitPriceL2 > bid) // Validasi agar tidak ditolak server MT5
        {
         double lotL2 = UseStaticLot ? StaticLotSize : CalculateDynamicLot(sym, R2/point);
         datetime expr = barTime + PeriodSeconds(tf);
         trade.SellLimit(lotL2, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2|" + DoubleToString(R2, _Digits));
        }
     }
  }

//+------------------------------------------------------------------+
//| Trailing Stop Kontinu (Tetap disimpan, nonaktif jika UseTrailingStop=false)
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

      double profitR = (type == POSITION_TYPE_BUY) ? ((bid - entry) / R) : ((entry - ask) / R);
      double stepsPassed = MathFloor(profitR / stepFraction);
      if(stepsPassed < 1) continue;

      double lockedR = -1.0 + stepsPassed * stepFraction;

      if(type == POSITION_TYPE_BUY)
        {
         double newSL = entry + lockedR * R;
         if(newSL > currentSL) trade.PositionModify(ticket, newSL, currentTP);
        }
      else
        {
         double newSL = entry - lockedR * R;
         if(currentSL == 0 || newSL < currentSL) trade.PositionModify(ticket, newSL, currentTP);
        }
     }
  }
//+------------------------------------------------------------------+
