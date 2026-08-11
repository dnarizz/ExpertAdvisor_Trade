//+------------------------------------------------------------------+
//| TripleLayer_Independent_EA_v1.0.mq5                              |
//| 1 sistem, 3 layer (Market/Retrace/Retrace) TOTAL INDEPENDEN.     |
//| Tiap layer: streak count, calc mode, retrace%, lot, SL, RRR,     |
//| trailing, consecutive-limit, expire bar -- SEMUA sendiri2.       |
//| Session/Day filter & System filter (spread, max pos, SL buffer,  |
//| magic) di-share satu group buat semua layer.                     |
//|                                                                    |
//| ASUMSI (nyatakan eksplisit, koreksi kalau salah):                |
//| - Single symbol/timeframe (chart aktif via _Symbol/_Period),     |
//|   BUKAN multi symbol/TF kayak versi lama.                        |
//| - Weekend-close fitur versi lama DIHAPUS (tak disebut di spek).  |
//| - Layer1 (market) TIDAK punya RetracePercent & LimitExpireBar    |
//|   (gak relevan, market entry langsung, gak ada pending expiry).  |
//| - StreakCalcMode Layer1 dipakai HANYA buat hitung SL dinamis.    |
//| - Magic number SATU dipakai bareng ketiga layer (sesuai System   |
//|   Filter group); layer dibedakan lewat prefix comment "L1/L2/L3".|

// Ini Masih ERROR perlu di Debug (hasil Claude Brave)

//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//====================================================================
enum ENUM_STREAK_CALC_MODE
  {
   STREAK_CALC_OPEN_CLOSE,  // Net Body: Open Candle Pertama ke Close Candle Kedua/Terakhir
   STREAK_CALC_HIGH_LOW     // High-Low Range: High tertinggi ke Low terendah seluruh streak
  };

//====================================================================
//======================  GROUP: SYSTEM FILTER  =====================
//====================================================================
input group "=== System Filter ==="
input bool   UseSpreadFilter       = true;
input double MaxSpreadPoints       = 500;
input int    MaxTotalOpenPositions = 10;
input double SL_BufferPoints       = 0;      // buffer tambahan dipakai SEMUA layer saat SL dinamis
input int    MagicNumber           = 777100;

//====================================================================
//====================  GROUP: SESSION & DAY FILTER  =================
//====================================================================
input group "=== Session Filter ==="
input bool   UseSessionFilter    = false;
input bool   EnableAsianSession  = true;
input int    AsianStartHour      = 0;
input int    AsianEndHour        = 8;
input bool   EnableLondonSession = true;
input int    LondonStartHour     = 8;
input int    LondonEndHour       = 16;
input bool   EnableUSSession     = true;
input int    USStartHour         = 13;
input int    USEndHour           = 22;

input group "=== Day Filter ==="
input bool   UseDayFilter        = false;
input bool   TradeMonday         = true;
input bool   TradeTuesday        = true;
input bool   TradeWednesday      = true;
input bool   TradeThursday       = true;
input bool   TradeFriday         = true;

//====================================================================
//======================  LAYER 1 (MARKET)  ==========================
//====================================================================
input group "=== [Layer 1 - Market] ==="
input bool   L1_UseLayer              = true;
input int    L1_StreakCount           = 2;
input ENUM_STREAK_CALC_MODE L1_StreakCalcMode = STREAK_CALC_OPEN_CLOSE; // dipakai HANYA utk SL dinamis
input int    L1_MaxConsecutiveTrades  = 3;
input bool   L1_UseStaticLot          = true;
input double L1_StaticLotSize         = 0.03;
input double L1_RiskPercentPerTrade   = 1.0;
input bool   L1_UseStaticSL           = false;
input double L1_StaticSLPoints        = 25000;
input bool   L1_UseStreakSizeFilter   = false; // relevan hanya kalau L1_UseStaticSL=false
input double L1_MinStreakPoints       = 5000;
input double L1_MaxStreakPoints       = 30000;
input double L1_RRR                   = 1.5;
input bool   L1_UseTrailingStop       = false;
input double L1_TrailStepPercent      = 10.0;

//====================================================================
//======================  LAYER 2 (RETRACE)  =========================
//====================================================================
input group "=== [Layer 2 - Retrace] ==="
input bool   L2_UseLayer              = true;
input int    L2_StreakCount           = 2;
input ENUM_STREAK_CALC_MODE L2_StreakCalcMode = STREAK_CALC_OPEN_CLOSE;
input double L2_RetracePercent        = 0.40;
input int    L2_MaxConsecutiveTrades  = 3;
input bool   L2_UseStaticLot          = true;
input double L2_StaticLotSize         = 0.03;
input double L2_RiskPercentPerTrade   = 1.0;
input bool   L2_UseStaticSL           = false;
input double L2_StaticSLPoints        = 25000;
input bool   L2_UseStreakSizeFilter   = false;
input double L2_MinStreakPoints       = 5000;
input double L2_MaxStreakPoints       = 30000;
input double L2_RRR                   = 2.0;
input bool   L2_UseTrailingStop       = false;
input double L2_TrailStepPercent      = 10.0;
input int    L2_LimitExpireBar        = 1;

//====================================================================
//======================  LAYER 3 (RETRACE)  =========================
//====================================================================
input group "=== [Layer 3 - Retrace] ==="
input bool   L3_UseLayer              = true;
input int    L3_StreakCount           = 2;
input ENUM_STREAK_CALC_MODE L3_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L3_RetracePercent        = 0.70;
input int    L3_MaxConsecutiveTrades  = 3;
input bool   L3_UseStaticLot          = true;
input double L3_StaticLotSize         = 0.03;
input double L3_RiskPercentPerTrade   = 1.0;
input bool   L3_UseStaticSL           = false;
input double L3_StaticSLPoints        = 25000;
input bool   L3_UseStreakSizeFilter   = false;
input double L3_MinStreakPoints       = 5000;
input double L3_MaxStreakPoints       = 30000;
input double L3_RRR                   = 2.5;
input bool   L3_UseTrailingStop       = false;
input double L3_TrailStepPercent      = 10.0;
input int    L3_LimitExpireBar        = 1;

//====================================================================
//======================  GLOBAL STATE  ==============================
//====================================================================
datetime g_lastBarTime = 0;
int      g_L1Counter = 0;
int      g_L2Counter = 0;
int      g_L3Counter = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   g_lastBarTime = 0;
   g_L1Counter = 0; g_L2Counter = 0; g_L3Counter = 0;
   Print("TripleLayer_Independent_EA siap. Symbol=", _Symbol, " Period=", EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop(); // jalan tiap tick, gate per-layer di dalam fungsi (cek UseTrailingStop masing2)

   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime <= 0 || currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   DeleteStalePendingOrders();

   if(UseSpreadFilter && IsSpreadHigh()) return;
   if(UseDayFilter && !IsDayAllowed()) return;
   if(UseSessionFilter && !IsSessionAllowed()) return;

   // --- LAYER 1: MARKET ---
   if(L1_UseLayer) ProcessLayer1(currentBarTime);

   // --- LAYER 2: RETRACE ---
   if(L2_UseLayer) ProcessLayer2(currentBarTime);

   // --- LAYER 3: RETRACE ---
   if(L3_UseLayer) ProcessLayer3(currentBarTime);
  }

//+------------------------------------------------------------------+
//| Hitung sinyal streak (independen per layer, pakai StreakCount    |
//| layer itu sendiri). return 1=bullish, -1=bearish, 0=none         |
//+------------------------------------------------------------------+
int EvaluateStreak(int streakCount)
  {
   if(iBars(_Symbol, _Period) < streakCount + 1) return 0;
   bool allGreen = true, allRed = true;
   for(int i=1; i<=streakCount; i++)
     {
      double o = iOpen(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      if(o <= 0 || c <= 0) return 0;
      if(c <= o) allGreen = false;
      if(c >= o) allRed = false;
     }
   if(allGreen) return 1;
   if(allRed)   return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Ambil top/bottom acuan sesuai StreakCalcMode.                    |
//| direction: 1=bullish streak, -1=bearish streak                   |
//+------------------------------------------------------------------+
void GetStreakBounds(int streakCount, ENUM_STREAK_CALC_MODE mode, int direction, double &top, double &bottom)
  {
   if(mode == STREAK_CALC_HIGH_LOW)
     {
      top = iHigh(_Symbol, _Period, 1);
      bottom = iLow(_Symbol, _Period, 1);
      for(int i=2; i<=streakCount; i++)
        {
         double h = iHigh(_Symbol, _Period, i);
         double l = iLow(_Symbol, _Period, i);
         if(h > top) top = h;
         if(l < bottom) bottom = l;
        }
     }
   else // STREAK_CALC_OPEN_CLOSE
     {
      double openFirst = iOpen(_Symbol, _Period, streakCount); // candle tertua streak
      double closeLast  = iClose(_Symbol, _Period, 1);          // candle terbaru streak
      if(direction == 1) { top = closeLast; bottom = openFirst; }
      else               { top = openFirst; bottom = closeLast; }
     }
  }

//+------------------------------------------------------------------+
double NormalizeLot(double targetLot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot > 0) targetLot = MathFloor(targetLot / stepLot) * stepLot;
   if(targetLot < minLot) targetLot = minLot;
   if(targetLot > maxLot) targetLot = maxLot;
   return NormalizeDouble(targetLot, 2);
  }

double CalculateDynamicLot(double riskPercent, double slPoints)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent/100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickValue<=0 || tickSize<=0 || point<=0 || slPoints<=0)
      return NormalizeLot(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   double valuePerPoint = tickValue * (point/tickSize);
   double rawLot = riskAmount / (slPoints * valuePerPoint);
   return NormalizeLot(rawLot);
  }

//+------------------------------------------------------------------+
bool IsSpreadHigh()
  {
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
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
      default: return false;
     }
  }

bool InHourRange(int h, int startH, int endH)
  {
   if(startH <= endH) return (h >= startH && h < endH);
   return (h >= startH || h < endH);
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
void DeleteStalePendingOrders()
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT)
         trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Hitung SL (static atau dinamis dari StreakCalcMode layer itu)   |
//+------------------------------------------------------------------+
double ComputeSL(int direction, double entryPrice, bool useStaticSL, double staticSLPoints,
                  int streakCount, ENUM_STREAK_CALC_MODE calcMode, double point)
  {
   if(useStaticSL)
      return (direction == 1) ? (entryPrice - staticSLPoints*point) : (entryPrice + staticSLPoints*point);

   double top, bottom;
   GetStreakBounds(streakCount, calcMode, direction, top, bottom);
   return (direction == 1) ? (bottom - SL_BufferPoints*point) : (top + SL_BufferPoints*point);
  }

//+------------------------------------------------------------------+
//| Streak size filter -- hanya berlaku kalau UseStaticSL=false     |
//+------------------------------------------------------------------+
bool PassStreakSizeFilter(bool useStaticSL, bool useFilter, double minPts, double maxPts,
                           int streakCount, ENUM_STREAK_CALC_MODE calcMode, int direction, double point)
  {
   if(useStaticSL || !useFilter) return true; // filter cuma relevan saat SL dinamis
   double top, bottom;
   GetStreakBounds(streakCount, calcMode, direction, top, bottom);
   double sizePoints = (top - bottom) / point;
   return (sizePoints >= minPts && sizePoints <= maxPts);
  }

//====================================================================
//======================  LAYER 1: MARKET  ===========================
//====================================================================
void ProcessLayer1(datetime barTime)
  {
   int signal = EvaluateStreak(L1_StreakCount);
   if(signal == 0) { g_L1Counter = 0; return; }
   if(g_L1Counter >= L1_MaxConsecutiveTrades)
     {
      Print("[L1] Batas maks ", L1_MaxConsecutiveTrades, " trade sekuensial tercapai. Skip.");
      return;
     }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(point<=0 || ask<=0 || bid<=0) return;

   if(!PassStreakSizeFilter(L1_UseStaticSL, L1_UseStreakSizeFilter, L1_MinStreakPoints, L1_MaxStreakPoints,
                             L1_StreakCount, L1_StreakCalcMode, signal, point))
     {
      Print("[L1] Skip: ukuran streak di luar batas MinStreakPoints/MaxStreakPoints.");
      return;
     }

   double entry = (signal == 1) ? ask : bid;
   double sl = ComputeSL(signal, entry, L1_UseStaticSL, L1_StaticSLPoints, L1_StreakCount, L1_StreakCalcMode, point);
   double R = (signal == 1) ? (entry - sl) : (sl - entry);
   if(R <= 0) { Print("[L1] SL invalid, skip."); return; }

   double tp = (signal == 1) ? (entry + R*L1_RRR) : (entry - R*L1_RRR);
   double lot = L1_UseStaticLot ? NormalizeLot(L1_StaticLotSize) : CalculateDynamicLot(L1_RiskPercentPerTrade, R/point);

   bool res = (signal == 1) ?
              trade.Buy(lot, _Symbol, entry, sl, tp, "L1|"+DoubleToString(R,_Digits)) :
              trade.Sell(lot, _Symbol, entry, sl, tp, "L1|"+DoubleToString(R,_Digits));

   if(res) { g_L1Counter++; Print("[L1] Trade berhasil. Counter=", g_L1Counter); }
   else Print("[L1] Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
  }

//====================================================================
//======================  LAYER 2 & 3: RETRACE  ======================
//====================================================================
void ProcessLayer2(datetime barTime) { ProcessRetraceLayer(barTime, 2); }
void ProcessLayer3(datetime barTime) { ProcessRetraceLayer(barTime, 3); }

void ProcessRetraceLayer(datetime barTime, int layerNum)
  {
   int    streakCount; ENUM_STREAK_CALC_MODE calcMode; double retracePct;
   int    maxConsec; bool useStaticLot; double staticLot, riskPct;
   bool   useStaticSL; double staticSLPts; bool useSizeFilter; double minPts, maxPts;
   double rrr; int expireBar;
   int    counterRef; // 0=n/a, dipakai sbg penanda saja (counter diakses langsung di bawah)

   if(layerNum == 2)
     {
      streakCount=L2_StreakCount; calcMode=L2_StreakCalcMode; retracePct=L2_RetracePercent;
      maxConsec=L2_MaxConsecutiveTrades; useStaticLot=L2_UseStaticLot; staticLot=L2_StaticLotSize; riskPct=L2_RiskPercentPerTrade;
      useStaticSL=L2_UseStaticSL; staticSLPts=L2_StaticSLPoints; useSizeFilter=L2_UseStreakSizeFilter;
      minPts=L2_MinStreakPoints; maxPts=L2_MaxStreakPoints; rrr=L2_RRR; expireBar=L2_LimitExpireBar;
     }
   else
     {
      streakCount=L3_StreakCount; calcMode=L3_StreakCalcMode; retracePct=L3_RetracePercent;
      maxConsec=L3_MaxConsecutiveTrades; useStaticLot=L3_UseStaticLot; staticLot=L3_StaticLotSize; riskPct=L3_RiskPercentPerTrade;
      useStaticSL=L3_UseStaticSL; staticSLPts=L3_StaticSLPoints; useSizeFilter=L3_UseStreakSizeFilter;
      minPts=L3_MinStreakPoints; maxPts=L3_MaxStreakPoints; rrr=L3_RRR; expireBar=L3_LimitExpireBar;
     }

   int signal = EvaluateStreak(streakCount);
   int &counter = (layerNum == 2) ? g_L2Counter : g_L3Counter;

   if(signal == 0) { counter = 0; return; }
   if(counter >= maxConsec)
     {
      Print("[L", layerNum, "] Batas maks ", maxConsec, " trade sekuensial tercapai. Skip.");
      return;
     }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(point<=0 || ask<=0 || bid<=0) return;

   if(!PassStreakSizeFilter(useStaticSL, useSizeFilter, minPts, maxPts, streakCount, calcMode, signal, point))
     {
      Print("[L", layerNum, "] Skip: ukuran streak di luar batas.");
      return;
     }

   double top, bottom;
   GetStreakBounds(streakCount, calcMode, signal, top, bottom);
   double range = top - bottom;
   if(range <= 0) return;

   double limitPrice, sl, tp, R;
   ENUM_ORDER_TYPE otype;

   if(signal == 1)
     {
      otype = ORDER_TYPE_BUY_LIMIT;
      limitPrice = top - retracePct * range;
      sl = useStaticSL ? (limitPrice - staticSLPts*point) : (bottom - SL_BufferPoints*point);
      R = limitPrice - sl;
      if(R <= 0 || limitPrice > (ask - stopLevel)) return;
      tp = limitPrice + R * rrr;
     }
   else
     {
      otype = ORDER_TYPE_SELL_LIMIT;
      limitPrice = bottom + retracePct * range;
      sl = useStaticSL ? (limitPrice + staticSLPts*point) : (top + SL_BufferPoints*point);
      R = sl - limitPrice;
      if(R <= 0 || limitPrice < (bid + stopLevel)) return;
      tp = limitPrice - R * rrr;
     }

   double lot = useStaticLot ? NormalizeLot(staticLot) : CalculateDynamicLot(riskPct, R/point);
   datetime expiration = barTime + expireBar * PeriodSeconds(_Period);
   string tag = "L" + IntegerToString(layerNum) + "|" + DoubleToString(R, _Digits);

   bool res = (otype == ORDER_TYPE_BUY_LIMIT) ?
              trade.BuyLimit(lot, limitPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, tag) :
              trade.SellLimit(lot, limitPrice, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, tag);

   if(res) { counter++; Print("[L", layerNum, "] Pending terpasang. Counter=", counter); }
   else Print("[L", layerNum, "] Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
  }

//====================================================================
//======================  TRAILING STOP (per layer)  =================
//====================================================================
void ManageTrailingStop()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      int sep = StringFind(cmt, "|");
      if(sep < 0) continue;

      string layerTag = StringSubstr(cmt, 0, sep);
      double R = StringToDouble(StringSubstr(cmt, sep+1));
      if(R <= 0) continue;

      bool   useTrail; double stepPct;
      if(layerTag == "L1")      { useTrail = L1_UseTrailingStop; stepPct = L1_TrailStepPercent; }
      else if(layerTag == "L2") { useTrail = L2_UseTrailingStop; stepPct = L2_TrailStepPercent; }
      else if(layerTag == "L3") { useTrail = L3_UseTrailingStop; stepPct = L3_TrailStepPercent; }
      else continue;

      if(!useTrail) continue;

      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long   type       = PositionGetInteger(POSITION_TYPE);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double stepFraction = stepPct / 100.0;
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
