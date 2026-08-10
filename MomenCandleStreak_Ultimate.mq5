//+------------------------------------------------------------------+
//| MomenCandleStreak_Hybrid_V4.1.1_Ultimate.mq5                       |
//| Full EA: Combined v3.1 + vD1.3 with Refined Streak Distance      |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Combined Hybrid Strategy v4.1.1"
#property version   "3.70"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== ENUM DEFINITIONS ==================
enum ENUM_STREAK_CALC_MODE
  {
   STREAK_CALC_OPEN_CLOSE,  // Net Body: Open Candle Pertama ke Close Candle Kedua/Terakhir
   STREAK_CALC_HIGH_LOW     // High-Low Range: High tertinggi ke Low terendah seluruh streak (vD1.3)
  };

enum ENUM_SL_BASE_MODE
  {
   SL_BASE_OPEN_CANDLE,     // Open Candle: Acuan SL dari Harga Open Candle Pertama Streak (v3.1)
   SL_BASE_HIGH_LOW         // High-Low Extremum: Acuan SL dari Low Terendah (Buy) / High Tertinggi (Sell) (vD1.3)
  };

//================== INPUT PARAMETERS ==================

input group "=== 1. Cakupan Symbol & Timeframe ==="
input string SymbolList                = "XAUUSD";
input string TimeframeList             = "H1";

input group "=== 2. Layer 1 (Instant Market Order - Base v3.1) ==="
input bool   UseLayer1                 = true;   // Aktifkan Layer 1 (Market Instant)
input double RiskRewardRatio           = 1.0;    // Target TP Ratio Layer 1 (1:X RR)
input double Layer1_LotSize            = 0.03;   // Lot khusus Layer 1 (jika UseStaticLot = true)

input group "=== 3. Layer 2 (Pending Limit Retrace 40% - Base vD1.3) ==="
input bool   UseLayer2                 = true;   // Aktifkan Layer 2 (Pending Limit)
input double RetracePercent            = 40.0;   // Retrace % Layer 2 (Default 40%)
input double Layer2_RiskRewardRatio    = 2.5;    // Target TP Ratio Layer 2 (Default 1:2.5 RR)
input double Layer2_LotSize            = 0.03;   // Lot khusus Layer 2 (jika UseStaticLot = true)

input group "=== 4. Layer 3 (Pending Limit Retrace 70% - Base vD1.3) ==="
input bool   UseLayer3                 = true;   // Aktifkan Layer 3 (Pending Limit)
input double Layer3_RetracePercent     = 70.0;   // Retrace % Layer 3 (Default 70%)
input double Layer3_RiskRewardRatio    = 2.0;    // Target TP Ratio Layer 3 (Default 1:2.0 RR)
input double Layer3_LotSize            = 0.03;   // Lot khusus Layer 3 (jika UseStaticLot = true)

input group "=== 5. Parameter Strategi Streak & Expiration ==="
input int    StreakCount               = 2;      // Jumlah Candle Streak Konsekutif
input int    MaxConsecutiveTrades      = 4;      // Batas maksimal trade berurutan
input int    LimitExpireBars           = 1;      // Masa berlaku Pending Order Layer 2 & 3 (dalam Bar)

input group "=== 6. Filter Ukuran Streak (Min & Max Points) ==="
input bool                  UseStreakSizeFilter = false;                  // Aktifkan Filter Ukuran Candle Streak
input ENUM_STREAK_CALC_MODE StreakCalcMode      = STREAK_CALC_OPEN_CLOSE; // Open 1st to Close 2nd vs High-Low Range
input double                MinStreakPoints     = 20000;                   // Batas Minimal Total Points Streak
input double                MaxStreakPoints     = 30000;                  // Batas Maksimal Total Points Streak

input group "=== 7. Lot Management & Risk ==="
input bool   UseStaticLot              = true;   // true = Static Lot (per layer), false = Dynamic % Risk Balance
input double StaticLotSize             = 0.03;   // Lot Cadangan Global (Fallback)
input double RiskPercentPerTrade       = 1.0;    // % Risk Balance per layer jika UseStaticLot = false

input group "=== 8. Target Stop Loss (Dynamic vs Static SL) ==="
input bool               UseStaticSL               = false;               // true = Pakai StaticSLPoints, false = Dynamic SL
input ENUM_SL_BASE_MODE  SLBaseMode                = SL_BASE_OPEN_CANDLE; // Mode Acuan Dynamic SL
input double             StaticSLPoints            = 25000;               // Jarak SL Fixed (Points) jika UseStaticSL = true
input double             SL_BufferPoints           = 0;                   // Buffer SL tambahan dalam point
input double             MaxSLPoints               = 0;                // BATAS MAKSIMAL Dynamic SL (0 = Capped Off)

input group "=== 9. Trailing Stop ==="
input bool   UseTrailingStop           = false;
input double TrailStepPercent          = 10.0;

input group "=== 10. Weekend Close ==="
input bool   UseWeekendClose           = true;
input int    WeekendCloseHour          = 22;     // Jam Jumat (server time) mulai tutup semua posisi
input bool   BlockNewTradeAfterWeekendClose = true; // Cegah entry baru setelah jam ini di hari Jumat

input group "=== 11. Session Filter (Semua ON = Tanpa Filter Jam) ==="
input bool   UseSessionFilter          = false;  // Master switch session filter
input bool   EnableAsianSession        = true;
input int    AsianStartHour            = 1;
input int    AsianEndHour              = 7;
input bool   EnableLondonSession       = true;
input int    LondonStartHour           = 7;
input int    LondonEndHour             = 16;
input bool   EnableUSSession           = true;
input int    USStartHour               = 14;
input int    USEndHour                 = 23;

input group "=== 12. Day Filter ==="
input bool   TradeMonday               = true;
input bool   TradeTuesday              = true;
input bool   TradeWednesday            = true;
input bool   TradeThursday             = true;
input bool   TradeFriday               = true;

input group "=== 13. Filter Umum & System ==="
input bool   UseSpreadFilter           = true;
input double MaxSpreadPoints           = 500;
input bool   OnePositionPerSymbol      = false;
input int    MaxTotalOpenPositions     = 3;
input int    MagicNumber               = 777007;

//================== STRUCT & GLOBAL VARIABLES ==================
struct SymTFState
  {
   string          symbol;
   ENUM_TIMEFRAMES tf;
   datetime        lastBarTime;
   int             consecutiveTrades;
  };

SymTFState g_states[];

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
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
            Print("WARNING: Timeframe '", tfStr, "' tidak dikenali, dilewati.");
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
   Print("EA Hybrid v3.7 Initialized. Active Symbol/TF States: ", idx);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| String to Timeframe Converter                                    |
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
//| Expert Tick Function                                             |
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
//| Evaluasi Momen Streak Candle                                    |
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
//| Helper High & Low Streak Range                                  |
//+------------------------------------------------------------------+
double GetStreakHigh(string sym, ENUM_TIMEFRAMES tf, int count)
  {
   double maxH = iHigh(sym, tf, 1);
   for(int i=2; i<=count; i++)
     {
      double h = iHigh(sym, tf, i);
      if(h > maxH) maxH = h;
     }
   return maxH;
  }

double GetStreakLow(string sym, ENUM_TIMEFRAMES tf, int count)
  {
   double minL = iLow(sym, tf, 1);
   for(int i=2; i<=count; i++)
     {
      double l = iLow(sym, tf, i);
      if(l < minL) minL = l;
     }
   return minL;
  }

//+------------------------------------------------------------------+
//| Eksekusi Multi-Layer (Layer 1 Instant, Layer 2 & 3 Pending)      |
//+------------------------------------------------------------------+
bool ExecuteLayeredTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type, datetime barTime)
  {
   SetAutoFillingType(sym);

   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask       = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(sym, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(point <= 0 || ask <= 0 || bid <= 0) return false;

   double streakHigh  = GetStreakHigh(sym, tf, StreakCount);
   double streakLow   = GetStreakLow(sym, tf, StreakCount);
   double streakRange = streakHigh - streakLow;
   if(streakRange <= 0) return false;

   // --- PERHITUNGAN UKURAN STREAK UNTUK FILTER GROUP 6 ---
   double streakDist = 0;
   if(StreakCalcMode == STREAK_CALC_OPEN_CLOSE)
     {
      // Open Candle Pertama (iOpen(StreakCount)) ke Close Candle Kedua/Terakhir (iClose(1))
      streakDist = MathAbs(iClose(sym, tf, 1) - iOpen(sym, tf, StreakCount)) / point;
     }
   else
     {
      // High-Low Range Extremum (vD1.3)
      streakDist = streakRange / point;
     }

   if(UseStreakSizeFilter)
     {
      if(streakDist < MinStreakPoints || streakDist > MaxStreakPoints)
        {
         Print(sym, " - Streak Points (", streakDist, ") di luar batas [", MinStreakPoints, "-", MaxStreakPoints, "]. Skip execution.");
         return false;
        }
     }

   bool anyExecuted = false;
   double entryL1 = (type == ORDER_TYPE_BUY) ? ask : bid;

   // --- PERHITUNGAN BASE STOP LOSS (SL INDUK) ---
   double slBase = 0;

   if(UseStaticSL)
     {
      slBase = (type == ORDER_TYPE_BUY) ? (entryL1 - StaticSLPoints * point) : (entryL1 + StaticSLPoints * point);
     }
   else
     {
      double rawSLLevel = 0;
      if(SLBaseMode == SL_BASE_OPEN_CANDLE)
        {
         // Open candle pertama dari streak (iOpen(StreakCount))
         rawSLLevel = iOpen(sym, tf, StreakCount);
        }
      else
        {
         // Low Terendah (Buy) atau High Tertinggi (Sell) dari streak
         rawSLLevel = (type == ORDER_TYPE_BUY) ? streakLow : streakHigh;
        }

      double rawSL = (type == ORDER_TYPE_BUY) ? (rawSLLevel - SL_BufferPoints * point) 
                                              : (rawSLLevel + SL_BufferPoints * point);
      slBase = rawSL;

      // Capping Max SL Points
      if(type == ORDER_TYPE_BUY)
        {
         double rawDistPoints = (entryL1 - rawSL) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints)
           {
            slBase = entryL1 - (MaxSLPoints * point);
            Print(sym, " - SL terlalu jauh (", rawDistPoints, " pt). Dicap ke MaxSLPoints: ", MaxSLPoints);
           }
        }
      else // SELL
        {
         double rawDistPoints = (rawSL - entryL1) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints)
           {
            slBase = entryL1 + (MaxSLPoints * point);
            Print(sym, " - SL terlalu jauh (", rawDistPoints, " pt). Dicap ke MaxSLPoints: ", MaxSLPoints);
           }
        }
     }

   // --- 1. EKSEKUSI LAYER 1 (Market Instant Order) ---
   if(UseLayer1)
     {
      double slL1 = slBase;
      double R1 = (type == ORDER_TYPE_BUY) ? (entryL1 - slL1) : (slL1 - entryL1);

      if(R1 > 0)
        {
         double tpL1  = (type == ORDER_TYPE_BUY) ? (entryL1 + R1 * RiskRewardRatio) 
                                                 : (entryL1 - R1 * RiskRewardRatio);
         
         double lotL1 = UseStaticLot ? NormalizeLot(sym, Layer1_LotSize) 
                                     : CalculateDynamicLot(sym, R1/point, Layer1_LotSize);

         bool resL1 = (type == ORDER_TYPE_BUY) ? 
                      trade.Buy(lotL1, sym, entryL1, slL1, tpL1, "S7_L1|"+DoubleToString(R1,_Digits)) : 
                      trade.Sell(lotL1, sym, entryL1, slL1, tpL1, "S7_L1|"+DoubleToString(R1,_Digits));

         if(resL1) anyExecuted = true;
         else Print("Error Layer 1 [", sym, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
     }

   // --- 2. EKSEKUSI LAYER 2 (Pending Limit Retrace 40%) ---
   if(UseLayer2)
     {
      double limitPriceL2, tpL2, slL2, R2;

      if(type == ORDER_TYPE_BUY)
        {
         limitPriceL2 = streakHigh - (streakRange * (RetracePercent / 100.0));
         slL2         = slBase;
         R2           = limitPriceL2 - slL2;

         if(R2 > 0 && limitPriceL2 <= (ask - stopLevel)) 
           {
            tpL2 = limitPriceL2 + (R2 * Layer2_RiskRewardRatio);
            
            double lotL2 = UseStaticLot ? NormalizeLot(sym, Layer2_LotSize) 
                                        : CalculateDynamicLot(sym, R2/point, Layer2_LotSize);
            datetime expr = barTime + (LimitExpireBars * PeriodSeconds(tf));
            
            if(trade.BuyLimit(lotL2, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2|"+DoubleToString(R2,_Digits)))
               anyExecuted = true;
           }
        }
      else // SELL
        {
         limitPriceL2 = streakLow + (streakRange * (RetracePercent / 100.0));
         slL2         = slBase;
         R2           = slL2 - limitPriceL2;

         if(R2 > 0 && limitPriceL2 >= (bid + stopLevel)) 
           {
            tpL2 = limitPriceL2 - (R2 * Layer2_RiskRewardRatio);
            
            double lotL2 = UseStaticLot ? NormalizeLot(sym, Layer2_LotSize) 
                                        : CalculateDynamicLot(sym, R2/point, Layer2_LotSize);
            datetime expr = barTime + (LimitExpireBars * PeriodSeconds(tf));
            
            if(trade.SellLimit(lotL2, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2|"+DoubleToString(R2,_Digits)))
               anyExecuted = true;
           }
        }
     }

   // --- 3. EKSEKUSI LAYER 3 (Pending Limit Retrace 70%) ---
   if(UseLayer3)
     {
      double limitPriceL3, tpL3, slL3, R3;

      if(type == ORDER_TYPE_BUY)
        {
         limitPriceL3 = streakHigh - (streakRange * (Layer3_RetracePercent / 100.0));
         slL3         = slBase;
         R3           = limitPriceL3 - slL3;

         if(R3 > 0 && limitPriceL3 <= (ask - stopLevel)) 
           {
            tpL3 = limitPriceL3 + (R3 * Layer3_RiskRewardRatio);
            
            double lotL3 = UseStaticLot ? NormalizeLot(sym, Layer3_LotSize) 
                                        : CalculateDynamicLot(sym, R3/point, Layer3_LotSize);
            datetime expr = barTime + (LimitExpireBars * PeriodSeconds(tf));
            
            if(trade.BuyLimit(lotL3, limitPriceL3, sym, slL3, tpL3, ORDER_TIME_SPECIFIED, expr, "S7_L3|"+DoubleToString(R3,_Digits)))
               anyExecuted = true;
           }
        }
      else // SELL
        {
         limitPriceL3 = streakLow + (streakRange * (Layer3_RetracePercent / 100.0));
         slL3         = slBase;
         R3           = slL3 - limitPriceL3;

         if(R3 > 0 && limitPriceL3 >= (bid + stopLevel)) 
           {
            tpL3 = limitPriceL3 - (R3 * Layer3_RiskRewardRatio);
            
            double lotL3 = UseStaticLot ? NormalizeLot(sym, Layer3_LotSize) 
                                        : CalculateDynamicLot(sym, R3/point, Layer3_LotSize);
            datetime expr = barTime + (LimitExpireBars * PeriodSeconds(tf));
            
            if(trade.SellLimit(lotL3, limitPriceL3, sym, slL3, tpL3, ORDER_TIME_SPECIFIED, expr, "S7_L3|"+DoubleToString(R3,_Digits)))
               anyExecuted = true;
           }
        }
     }

   return anyExecuted;
  }

//+------------------------------------------------------------------+
//| Management Dynamic/Static Lot Normalization                     |
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

double CalculateDynamicLot(string sym, double slPoints, double fallbackLot = 0.05)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercentPerTrade / 100.0);
   double tickValue  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(sym, SYMBOL_POINT);
   
   if(tickValue <= 0 || tickSize <= 0 || point <= 0 || slPoints <= 0) 
      return NormalizeLot(sym, fallbackLot);

   double valuePerPoint = tickValue * (point / tickSize);
   double rawLot        = riskAmount / (slPoints * valuePerPoint);

   return NormalizeLot(sym, rawLot);
  }

//+------------------------------------------------------------------+
//| Trailing Stop Management                                         |
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
//| Filter Handler Functions                                         |
//+------------------------------------------------------------------+
bool IsSpreadHigh(string sym)
  {
   double spreadPoints = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   return (spreadPoints > MaxSpreadPoints);
  }

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
      default: return false; // Sabtu/Minggu OFF
     }
  }

bool InHourRange(int h, int startH, int endH)
  {
   if(startH <= endH) return (h >= startH && h < endH);
   return (h >= startH || h < endH); // Wrap midnight
  }

bool IsSessionAllowed()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   bool allowed = false;
   if(EnableAsianSession  && InHourRange(h, AsianStartHour, AsianEndHour))   allowed = true;
   if(EnableLondonSession && InHourRange(h, LondonStartHour, LondonEndHour)) allowed = true;
   if(EnableUSSession     && InHourRange(h, USStartHour, USEndHour))         allowed = true;
   return allowed;
  }

bool IsPastWeekendCloseHour()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= WeekendCloseHour);
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

   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      trade.OrderDelete(ticket);
     }
  }

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
