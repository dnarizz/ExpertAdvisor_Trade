//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate_V2.4.mq5                    |
//| Base: v2.3 + Max SL Capping Mechanism                           |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "3.10"
// v3.1: base v2.5_Fixed. Tambah:
// - UseStaticSL: SL fixed manual, bypass Open-candle+cap
// - Weekend close: tutup semua posisi+pending Jumat jam X (server time)
// - Session filter: Asian/London/US toggle terpisah
// - Day filter: Senin-Jumat toggle terpisah (Sabtu/Minggu selalu off)
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Cakupan Symbol & Timeframe ==="
input string SymbolList          = "XAUUSD";
input string TimeframeList       = "H1";

input group "=== Strategi & Layering ==="
input int    StreakCount         = 2;
input double RetracePercent      = 0; // Retrace x% dari candle kedua (50% = 0.50)
input int    MaxConsecutiveTrades= 4;    // Batas maksimal trade berurutan

input group "=== Lot Management ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.05; // Otomatis disesuaikan ke min/step lot broker
input double RiskPercentPerTrade = 1.0;  // Digunakan jika UseStaticLot = false

input group "=== Target TP & SL ==="
input double SL_BufferPoints     = 0;    // Buffer SL tambahan dalam point
input double MaxSLPoints         = 1000; // BATAS MAKSIMAL SL (0 = Tanpa Batas / Mengikuti Open Candle)
input double RiskRewardRatio     = 1.0;  // TP Layer 1 (1:1 RR)

input group "=== Trailing Stop ==="
input bool   UseTrailingStop     = false;
input double TrailStepPercent    = 10.0;

input group "=== SL Static (Override) ==="
input bool   UseStaticSL         = true; // true = pakai StaticSLPoints, bypass logic Open-candle & cap
input double StaticSLPoints      = 25000;  // jarak SL fixed dalam point, dipakai kalau UseStaticSL=true

input group "=== Weekend Close ==="
input bool   UseWeekendClose     = true;
input int    WeekendCloseHour    = 22;    // jam Jumat (server time) mulai tutup semua posisi
input bool   BlockNewTradeAfterWeekendClose = true; // cegah entry baru setelah jam ini di hari Jumat

input group "=== Session Filter (semua ON = tanpa filter jam) ==="
input bool   UseSessionFilter    = false; // master switch, kalau false semua session dianggap terbuka
input bool   EnableAsianSession  = true;
input int    AsianStartHour      = 1;
input int    AsianEndHour        = 9;
input bool   EnableLondonSession = true;
input int    LondonStartHour     = 9;
input int    LondonEndHour       = 17;
input bool   EnableUSSession     = true;
input int    USStartHour         = 14;
input int    USEndHour           = 22;

input group "=== Day Filter ==="
input bool   TradeMonday         = true;
input bool   TradeTuesday        = true;
input bool   TradeWednesday      = true;
input bool   TradeThursday       = true;
input bool   TradeFriday         = true;

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = false;
input double MaxSpreadPoints     = 500;
input bool   OnePositionPerSymbol= false;
input int    MaxTotalOpenPositions = 3;
input int    MagicNumber         = 777007;

//================== STRUCT & GLOBAL ==================
struct SymTFState
  {
   string          symbol;
   ENUM_TIMEFRAMES tf;
   datetime        lastBarTime;
   int             consecutiveTrades;
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
         bool validTf;
         ENUM_TIMEFRAMES tf = StringToTimeframe(tfStr, validTf);
         if(!validTf)
           {
            Print("WARNING: Timeframe '", tfStr, "' tidak dikenali, dilewati (BUKAN fallback diam-diam).");
            continue;
           }

         g_states[idx].symbol = sym;
         g_states[idx].tf = tf;
         g_states[idx].lastBarTime = 0;
         g_states[idx].consecutiveTrades = 0;
         idx++;
        }
     }

   ArrayResize(g_states, idx);
   trade.SetExpertMagicNumber(MagicNumber);
   Print("EA v7.60 Max SL Cap Initialized. Max SL: ", MaxSLPoints, " points.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringToTimeframe(string s, bool &valid)
  {
   valid = true;
   if(s=="M1")  return PERIOD_M1;
   if(s=="M5")  return PERIOD_M5;
   if(s=="M15") return PERIOD_M15;
   if(s=="M30") return PERIOD_M30;
   if(s=="H1")  return PERIOD_H1;
   if(s=="H4")  return PERIOD_H4;
   if(s=="D1")  return PERIOD_D1;
   if(s=="W1")  return PERIOD_W1;
   if(s=="MN1") return PERIOD_MN1;
   valid = false;
   return PERIOD_CURRENT;
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(UseTrailingStop) ManageTrailingStop();
   if(UseWeekendClose) CheckWeekendClose();
   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0; i<ArraySize(g_states); i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime currentBarTime = iTime(sym, tf, 0);
      if(currentBarTime <= 0 || currentBarTime == g_states[i].lastBarTime) continue;

      g_states[i].lastBarTime = currentBarTime;

      DeleteStalePendingOrders(sym);

      if(UseSpreadFilter && IsSpreadHigh(sym)) continue;
      if(OnePositionPerSymbol && PositionSelect(sym)) continue;
      if(!IsDayAllowed()) continue;
      if(UseSessionFilter && !IsSessionAllowed()) continue;
      if(UseWeekendClose && BlockNewTradeAfterWeekendClose && IsPastWeekendCloseHour()) continue;

      int signal = EvaluateStreak(sym, tf);
      
      if(signal == 0)
        {
         g_states[i].consecutiveTrades = 0;
         continue;
        }

      if(g_states[i].consecutiveTrades >= MaxConsecutiveTrades)
        {
         Print(sym, " - Batas maks ", MaxConsecutiveTrades, " trade sekuensial tercapai. Skip.");
         continue;
        }

      bool executed = false;
      if(signal == 1)  executed = ExecuteLayeredTrade(sym, tf, ORDER_TYPE_BUY, currentBarTime);
      if(signal == -1) executed = ExecuteLayeredTrade(sym, tf, ORDER_TYPE_SELL, currentBarTime);

      if(executed)
        {
         g_states[i].consecutiveTrades++;
         Print(sym, " Trade Berhasil. Consecutive Count: ", g_states[i].consecutiveTrades);
        }
     }
  }

//+------------------------------------------------------------------+
int EvaluateStreak(string sym, ENUM_TIMEFRAMES tf)
  {
   if(iBars(sym, tf) < StreakCount + 1) return 0;

   bool allGreen = true, allRed = true;
   for(int i=1; i<=StreakCount; i++)
     {
      double o = iOpen(sym, tf, i);
      double c = iClose(sym, tf, i);
      if(o <= 0 || c <= 0) return 0;
      
      if(c <= o) allGreen = false;
      if(c >= o) allRed = false;
     }
   if(allGreen) return 1;
   if(allRed)   return -1;
   return 0;
  }

//+------------------------------------------------------------------+
double NormalizeLot(string sym, double targetLot)
  {
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   if(stepLot > 0)
      targetLot = MathFloor(targetLot / stepLot) * stepLot;

   if(targetLot < minLot) targetLot = minLot;
   if(targetLot > maxLot) targetLot = maxLot;

   return NormalizeDouble(targetLot, 2);
  }

//+------------------------------------------------------------------+
double CalculateDynamicLot(string sym, double slPoints)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercentPerTrade/100.0);
   double tickValue  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(sym, SYMBOL_POINT);
   
   if(tickValue<=0 || tickSize<=0 || point<=0 || slPoints<=0) 
      return NormalizeLot(sym, StaticLotSize);

   double valuePerPoint = tickValue * (point/tickSize);
   double rawLot        = riskAmount / (slPoints * valuePerPoint);

   return NormalizeLot(sym, rawLot);
  }

//+------------------------------------------------------------------+
bool IsSpreadHigh(string sym)
  {
   double spreadPoints = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   return (spreadPoints > MaxSpreadPoints);
  }

//+------------------------------------------------------------------+
bool IsDayAllowed()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
     {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false; // Sabtu/Minggu selalu off (market XAUUSD tutup weekend)
     }
  }

//+------------------------------------------------------------------+
bool InHourRange(int h, int startH, int endH)
  {
   if(startH <= endH) return (h >= startH && h < endH);
   return (h >= startH || h < endH); // wrap tengah malam
  }

bool IsSessionAllowed()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   bool allowed = false;
   if(EnableAsianSession  && InHourRange(h, AsianStartHour, AsianEndHour))   allowed = true;
   if(EnableLondonSession && InHourRange(h, LondonStartHour, LondonEndHour)) allowed = true;
   if(EnableUSSession     && InHourRange(h, USStartHour, USEndHour))        allowed = true;
   return allowed;
  }

//+------------------------------------------------------------------+
bool IsPastWeekendCloseHour()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= WeekendCloseHour); // Jumat >= jam X
  }

void CheckWeekendClose()
  {
   if(!IsPastWeekendCloseHour()) return;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      trade.PositionClose(ticket);
     }
   // pending order lompatan juga dihapus, tak ada gunanya nunggu weekend
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      trade.OrderDelete(ticket);
     }
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
void SetAutoFillingType(string sym)
  {
   uint filling = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| Eksekusi Trade dengan Logika Capping Max SL                      |
//+------------------------------------------------------------------+
bool ExecuteLayeredTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type, datetime barTime)
  {
   SetAutoFillingType(sym);

   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask       = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(sym, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(point <= 0 || ask <= 0 || bid <= 0) return false;

   int firstCandleIdx = StreakCount; 

   double h1 = iHigh(sym, tf, 1);
   double l1 = iLow(sym, tf, 1);
   double range1 = h1 - l1;
   if(range1 <= 0) return false;

   // SL ideal awal dari Open candle lompatan pertama
   double slLevel = iOpen(sym, tf, firstCandleIdx);
   bool anyExecuted = false;

   // --- 1. EKSEKUSI LAYER 1 (Market Order Instant) ---
   double entryL1 = (type == ORDER_TYPE_BUY) ? ask : bid;
   double slL1;

   if(UseStaticSL)
     {
      // Bypass total logic Open-candle & MaxSLPoints cap. Murni fixed point dari entry.
      slL1 = (type == ORDER_TYPE_BUY) ? (entryL1 - StaticSLPoints*point) : (entryL1 + StaticSLPoints*point);
     }
   else
     {
      double rawSL = (type == ORDER_TYPE_BUY) ? (slLevel - SL_BufferPoints*point) 
                                                : (slLevel + SL_BufferPoints*point);
      slL1 = rawSL;

      // PERHITUNGAN BATAS MAKSIMAL SL (MaxSLPoints)
      if(type == ORDER_TYPE_BUY)
        {
         double rawDistPoints = (entryL1 - rawSL) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints)
           {
            slL1 = entryL1 - (MaxSLPoints * point);
            Print(sym, " - SL terlalu jauh (", rawDistPoints, " pt). Dicap ke MaxSLPoints: ", MaxSLPoints);
           }
        }
      else // SELL
        {
         double rawDistPoints = (rawSL - entryL1) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints)
           {
            slL1 = entryL1 + (MaxSLPoints * point);
            Print(sym, " - SL terlalu jauh (", rawDistPoints, " pt). Dicap ke MaxSLPoints: ", MaxSLPoints);
           }
        }
     }

   double R1 = (type == ORDER_TYPE_BUY) ? (entryL1 - slL1) : (slL1 - entryL1);

   if(R1 > 0)
     {
      double tpL1  = (type == ORDER_TYPE_BUY) ? (entryL1 + R1 * RiskRewardRatio) 
                                              : (entryL1 - R1 * RiskRewardRatio);
      double lotL1 = UseStaticLot ? NormalizeLot(sym, StaticLotSize) : CalculateDynamicLot(sym, R1/point);

      bool resL1 = (type == ORDER_TYPE_BUY) ? 
                   trade.Buy(lotL1, sym, entryL1, slL1, tpL1, "S7_L1|"+DoubleToString(R1,_Digits)) : 
                   trade.Sell(lotL1, sym, entryL1, slL1, tpL1, "S7_L1|"+DoubleToString(R1,_Digits));

      if(resL1) anyExecuted = true;
      else Print("Error Layer 1 [", sym, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }

   // --- 2. EKSEKUSI LAYER 2 (Pending Limit Order Menggunakan SL yang Sudah Dicap) ---
   double limitPriceL2, tpL2, slL2, R2;

   if(type == ORDER_TYPE_BUY)
     {
      limitPriceL2 = h1 - RetracePercent * range1;
      slL2         = slL1; // Menggunakan SL yang sudah dicap dari Layer 1
      tpL2         = h1;
      R2           = limitPriceL2 - slL2;

      if(R2 > 0 && limitPriceL2 <= (ask - stopLevel)) 
        {
         double lotL2  = UseStaticLot ? NormalizeLot(sym, StaticLotSize) : CalculateDynamicLot(sym, R2/point);
         datetime expr = barTime + PeriodSeconds(tf);
         
         if(trade.BuyLimit(lotL2, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2|"+DoubleToString(R2,_Digits)))
            anyExecuted = true;
        }
     }
   else // SELL
     {
      limitPriceL2 = l1 + RetracePercent * range1;
      slL2         = slL1; // Menggunakan SL yang sudah dicap dari Layer 1
      tpL2         = l1;
      R2           = slL2 - limitPriceL2;

      if(R2 > 0 && limitPriceL2 >= (bid + stopLevel)) 
        {
         double lotL2  = UseStaticLot ? NormalizeLot(sym, StaticLotSize) : CalculateDynamicLot(sym, R2/point);
         datetime expr = barTime + PeriodSeconds(tf);
         
         if(trade.SellLimit(lotL2, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2|"+DoubleToString(R2,_Digits)))
            anyExecuted = true;
        }
     }

   return anyExecuted;
  }

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

      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long type        = PositionGetInteger(POSITION_TYPE);

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

      double profitR     = (type == POSITION_TYPE_BUY) ? ((bid - entry) / R) : ((entry - ask) / R);
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
