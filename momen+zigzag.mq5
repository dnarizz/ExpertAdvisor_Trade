#property copyright "Custom EA - V6.4 (ZigZag Momentum & Wave Quota)"
#property version   "6.40"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== ENUM ==================
enum ENUM_STREAK_CALC_MODE
  {
   STREAK_CALC_OPEN_CLOSE,  // Open candle pertama ke Close candle terakhir streak
   STREAK_CALC_HIGH_LOW     // High tertinggi ke Low terendah seluruh streak
  };

//================== INPUT: GROUP 1 - LAYER 1 (MARKET) ==================
input group "=== 1. Layer 1 - Market Instant ==="
input bool   L1_UseLayer             = true;
input bool   L1_ReverseMode          = false;   
input int    L1_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L1_StreakCalcMode = STREAK_CALC_OPEN_CLOSE;
input int    L1_MaxConsecutiveTrades = 7;       // Maks trade per 1 rentang gelombang ZigZag
input bool   L1_UseStaticLot         = false;
input double L1_StaticLotSize        = 0.03;
input double L1_RiskPercentPerTrade  = 1.0;
input bool   L1_UseStaticSLPoint     = false;
input double L1_StaticSLPoints       = 2500;
input bool   L1_UseStreakSizeFilter  = false;
input double L1_MinStreakPoints      = 200;
input double L1_MaxStreakPoints      = 3000;
input double L1_RRR                  = 1.0;     
input bool   L1_UseTrailingStop      = true;
input double L1_TrailStartR          = 0.8;     
input double L1_TrailDistR           = 1.0;     
input bool   L1_UseMaxHoldBars       = false;
input int    L1_MaxHoldBars          = 12;

//================== INPUT: GROUP 2 - LAYER 2 (PENDING) ==================
input group "=== 2. Layer 2 - Pending Limit ==="
input bool   L2_UseLayer             = false;
input bool   L2_ReverseMode          = false;  
input int    L2_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L2_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L2_RetracePercent       = 40.0;  
input int    L2_MaxConsecutiveTrades = 4;       // Maks trade per 1 rentang gelombang ZigZag
input bool   L2_UseStaticLot         = true;
input double L2_StaticLotSize        = 0.03;
input double L2_RiskPercentPerTrade  = 1.0;
input bool   L2_UseStaticSLPoint     = false;
input double L2_StaticSLPoints       = 2500;
input bool   L2_UseStreakSizeFilter  = false;
input double L2_MinStreakPoints      = 200;
input double L2_MaxStreakPoints      = 3000;
input double L2_RRR                  = 2.5;
input bool   L2_UseTrailingStop      = false;
input double L2_TrailStartR          = 0.8;
input double L2_TrailDistR           = 1.0;
input int    L2_LimitExpireBars      = 1;
input bool   L2_UseMaxHoldBars       = false;
input int    L2_MaxHoldBars          = 10;

//================== INPUT: GROUP 3 - LAYER 3 (PENDING) ==================
input group "=== 3. Layer 3 - Pending Limit ==="
input bool   L3_UseLayer             = false;
input bool   L3_ReverseMode          = false;
input int    L3_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L3_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L3_RetracePercent       = 70.0;
input int    L3_MaxConsecutiveTrades = 4;       // Maks trade per 1 rentang gelombang ZigZag
input bool   L3_UseStaticLot         = true;
input double L3_StaticLotSize        = 0.03;
input double L3_RiskPercentPerTrade  = 1.0;
input bool   L3_UseStaticSLPoint     = false;
input double L3_StaticSLPoints       = 2500;
input bool   L3_UseStreakSizeFilter  = false;
input double L3_MinStreakPoints      = 200;
input double L3_MaxStreakPoints      = 3000;
input double L3_RRR                  = 2.0;
input bool   L3_UseTrailingStop      = false;
input double L3_TrailStartR          = 0.8;
input double L3_TrailDistR           = 1.0;
input int    L3_LimitExpireBars      = 1;
input bool   L3_UseMaxHoldBars       = false;
input int    L3_MaxHoldBars          = 10;

//================== INPUT: GROUP 4 - WEEKEND CLOSE ==================
input group "=== 4. Weekend Close ==="
input bool UseWeekendClose                = true;
input int  WeekendCloseHour               = 20;
input bool BlockNewTradeAfterWeekendClose = true;

//================== INPUT: GROUP 5 - SESSION & DAY FILTER ==================
input group "=== 5. Session & Day Filter ==="
input bool UseSessionFilter    = false;
input bool EnableAsianSession  = true;
input int  AsianStartHour      = 0;
input int  AsianEndHour        = 7;
input bool EnableLondonSession = true;
input int  LondonStartHour     = 7;
input int  LondonEndHour       = 16;
input bool EnableUSSession     = true;
input int  USStartHour         = 14;
input int  USEndHour           = 23;

input bool UseDayFilter   = false;
input bool TradeMonday    = true;
input bool TradeTuesday   = true;
input bool TradeWednesday = true;
input bool TradeThursday  = true;
input bool TradeFriday    = true;

//================== INPUT: GROUP 6 - SYSTEM FILTER ==================
input group "=== 6. System Filter ==="
input bool   UseSpreadFilter       = true;
input double MaxSpreadPoints       = 500;
input int    MaxTotalOpenPositions = 10;
input double SL_BufferPoints       = 0;
input int    MagicNumber           = 777070;

//================== INPUT: GROUP 7 - ZIGZAG FILTER ==================
input group "=== 7. ZigZag Trend & Quota Filter ==="
input bool            UseZigZagFilter = true;           // Aktifkan Filter & Kuota ZigZag
input ENUM_TIMEFRAMES ZZ_Timeframe    = PERIOD_CURRENT; // Timeframe Indikator ZigZag
input int             ZZ_Depth        = 12;             // ZigZag Depth
input int             ZZ_Deviation    = 5;              // ZigZag Deviation
input int             ZZ_Backstep     = 3;              // ZigZag Backstep
input int             ZZ_LookbackBars = 300;            // Bar pencarian titik ZigZag

//================== STRUCT & GLOBAL ==================
struct SLayerParams
  {
   bool                  enabled;
   string                tag;
   bool                  reverse;
   int                   streakCount;
   ENUM_STREAK_CALC_MODE calcMode;
   double                retracePercent;
   int                   maxConsecutive;
   bool                  useStaticLot;
   double                staticLot;
   double                riskPercent;
   bool                  useStaticSL;
   double                staticSLPoints;
   bool                  useStreakFilter;
   double                minStreakPoints;
   double                maxStreakPoints;
   double                rrr;
   bool                  useTrailing;
   double                trailStartR;
   double                trailDistR;
   int                   limitExpireBars;
   bool                  useMaxHold;
   int                   maxHoldBars;
  };

SLayerParams g_layers[3];
int          g_consecutive[3];        // Jumlah trade yang sudah diambil pada fase saat ini
int          g_lastSignal[3];         // Dipakai jika UseZigZagFilter = false
int          g_lastZZDir[3];          // Menyimpan arah ZigZag terakhir (1 = Naik, -1 = Turun)
datetime     g_lastZZAnchorTime[3];   // Menyimpan waktu titik pangkal gelombang ZigZag
int          g_zzHandle = INVALID_HANDLE;
datetime     g_lastBarTime = 0;

const double TRAIL_MIN_STEP_R = 0.02;  // SL trailing hanya digeser jika membaik >= 0.02R

//+------------------------------------------------------------------+
//| Isi parameter satu layer                                          |
//+------------------------------------------------------------------+
void SetLayer(int idx, string tag, bool enabled, bool reverse, int streakCount, ENUM_STREAK_CALC_MODE calcMode,
              double retracePercent, int maxConsecutive, bool useStaticLot, double staticLot, double riskPercent,
              bool useStaticSL, double staticSLPoints, bool useStreakFilter, double minStreak, double maxStreak,
              double rrr, bool useTrailing, double trailStartR, double trailDistR,
              int limitExpireBars, bool useMaxHold, int maxHoldBars)
  {
   g_layers[idx].enabled         = enabled;
   g_layers[idx].tag             = tag;
   g_layers[idx].reverse         = reverse;
   g_layers[idx].streakCount     = streakCount;
   g_layers[idx].calcMode        = calcMode;
   g_layers[idx].retracePercent  = retracePercent;
   g_layers[idx].maxConsecutive  = maxConsecutive;
   g_layers[idx].useStaticLot    = useStaticLot;
   g_layers[idx].staticLot       = staticLot;
   g_layers[idx].riskPercent     = riskPercent;
   g_layers[idx].useStaticSL     = useStaticSL;
   g_layers[idx].staticSLPoints  = staticSLPoints;
   g_layers[idx].useStreakFilter = useStreakFilter && !useStaticSL;
   g_layers[idx].minStreakPoints = minStreak;
   g_layers[idx].maxStreakPoints = maxStreak;
   g_layers[idx].rrr             = rrr;
   g_layers[idx].useTrailing     = useTrailing;
   g_layers[idx].trailStartR     = trailStartR;
   g_layers[idx].trailDistR      = trailDistR;
   g_layers[idx].limitExpireBars = limitExpireBars;
   g_layers[idx].useMaxHold      = useMaxHold;
   g_layers[idx].maxHoldBars     = maxHoldBars;
   if(useStreakFilter && useStaticSL)
      Print("WARNING ", tag, ": UseStreakSizeFilter dinonaktifkan otomatis karena UseStaticSLPoint=true (konflik).");
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   for(int i = 0; i < 3; i++)
     {
      g_consecutive[i]      = 0;
      g_lastSignal[i]       = 0;
      g_lastZZDir[i]        = 0;
      g_lastZZAnchorTime[i] = 0;
     }
   g_lastBarTime = 0;

   SetLayer(0, "L1", L1_UseLayer, L1_ReverseMode, L1_StreakCount, L1_StreakCalcMode,
            0.0, L1_MaxConsecutiveTrades, L1_UseStaticLot, L1_StaticLotSize, L1_RiskPercentPerTrade,
            L1_UseStaticSLPoint, L1_StaticSLPoints, L1_UseStreakSizeFilter, L1_MinStreakPoints, L1_MaxStreakPoints,
            L1_RRR, L1_UseTrailingStop, L1_TrailStartR, L1_TrailDistR,
            0, L1_UseMaxHoldBars, L1_MaxHoldBars);

   SetLayer(1, "L2", L2_UseLayer, L2_ReverseMode, L2_StreakCount, L2_StreakCalcMode,
            L2_RetracePercent, L2_MaxConsecutiveTrades, L2_UseStaticLot, L2_StaticLotSize, L2_RiskPercentPerTrade,
            L2_UseStaticSLPoint, L2_StaticSLPoints, L2_UseStreakSizeFilter, L2_MinStreakPoints, L2_MaxStreakPoints,
            L2_RRR, L2_UseTrailingStop, L2_TrailStartR, L2_TrailDistR,
            L2_LimitExpireBars, L2_UseMaxHoldBars, L2_MaxHoldBars);

   SetLayer(2, "L3", L3_UseLayer, L3_ReverseMode, L3_StreakCount, L3_StreakCalcMode,
            L3_RetracePercent, L3_MaxConsecutiveTrades, L3_UseStaticLot, L3_StaticLotSize, L3_RiskPercentPerTrade,
            L3_UseStaticSLPoint, L3_StaticSLPoints, L3_UseStreakSizeFilter, L3_MinStreakPoints, L3_MaxStreakPoints,
            L3_RRR, L3_UseTrailingStop, L3_TrailStartR, L3_TrailDistR,
            L3_LimitExpireBars, L3_UseMaxHoldBars, L3_MaxHoldBars);

   if(UseZigZagFilter)
     {
      g_zzHandle = iCustom(_Symbol, ZZ_Timeframe, "Examples\\ZigZag", ZZ_Depth, ZZ_Deviation, ZZ_Backstep);
      if(g_zzHandle == INVALID_HANDLE)
        {
         Print("ERROR: Gagal memuat indikator Examples\\ZigZag. Pastikan indikator tersedia di folder Indicators\\Examples.");
         return(INIT_FAILED);
        }
      
      // --- TAMBAHAN: Tampilkan garis ZigZag otomatis di Chart utama (Subwindow 0) ---
      ChartIndicatorAdd(0, 0, g_zzHandle);
     }

   trade.SetExpertMagicNumber(MagicNumber);

   Print("EA V6.4 Initialized. Symbol=", _Symbol, " Period=", EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_zzHandle != INVALID_HANDLE)
     {
      // --- TAMBAHAN: Hapus garis ZigZag dari chart saat EA dilepas ---
      string shortName = ChartIndicatorName(0, 0, ChartIndicatorsTotal(0, 0) - 1);
      ChartIndicatorDelete(0, 0, shortName);

      IndicatorRelease(g_zzHandle);
      g_zzHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Deteksi Fase ZigZag (1 = Rentang Naik, -1 = Rentang Turun)       |
//+------------------------------------------------------------------+
bool GetZigZagPhase(int &zzDir, datetime &anchorTime)
  {
   zzDir      = 0;
   anchorTime = 0;
   if(g_zzHandle == INVALID_HANDLE) return false;

   double zzBuf[];
   ArraySetAsSeries(zzBuf, true);
   if(CopyBuffer(g_zzHandle, 0, 0, ZZ_LookbackBars, zzBuf) <= 0) return false;

   double   pivots[2];
   datetime pivotTimes[2];
   int      found = 0;

   // Cari 2 titik ekstrem ZigZag terakhir dari candle yang sudah close (bar >= 1)
   for(int i = 1; i < ZZ_LookbackBars && found < 2; i++)
     {
      if(zzBuf[i] != 0.0 && zzBuf[i] != EMPTY_VALUE)
        {
         pivots[found]     = zzBuf[i];
         pivotTimes[found] = iTime(_Symbol, ZZ_Timeframe, i);
         found++;
        }
     }

   if(found < 2) return false;

   // pivots[1] = titik pangkal gelombang saat ini, pivots[0] = ujung gelombang terbaru
   anchorTime = pivotTimes[1];
   if(pivots[0] > pivots[1])
      zzDir = 1;   // Rentang waktu NAIK (garis ZigZag mengarah ke atas)
   else if(pivots[0] < pivots[1])
      zzDir = -1;  // Rentang waktu TURUN (garis ZigZag mengarah ke bawah)
   else
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| Comment helpers: format "TAG|R"                                  |
//+------------------------------------------------------------------+
bool ParseComment(string cmt, string &layerTag, double &R)
  {
   string parts[];
   int n = StringSplit(cmt, '|', parts);
   if(n < 2) return false;
   layerTag = parts[0];
   R        = StringToDouble(parts[1]);
   return true;
  }

int TagToIndex(string tag)
  {
   if(tag == "L1") return 0;
   if(tag == "L2") return 1;
   if(tag == "L3") return 2;
   return -1;
  }

//+------------------------------------------------------------------+
//| Streak evaluation (Momentum Confirmation)                        |
//+------------------------------------------------------------------+
int EvaluateStreakGeneric(int count)
  {
   bool allGreen = true, allRed = true;
   for(int i = 1; i <= count; i++)
     {
      double o = iOpen(_Symbol, _Period, i), c = iClose(_Symbol, _Period, i);
      if(o <= 0 || c <= 0) return 0;
      if(c <= o) allGreen = false;
      if(c >= o) allRed   = false;
     }
   if(allGreen) return 1;
   if(allRed)   return -1;
   return 0;
  }

void GetStreakData(int count, double &openFirst, double &closeLast, double &highMax, double &lowMin)
  {
   openFirst = iOpen(_Symbol, _Period, count);
   closeLast = iClose(_Symbol, _Period, 1);
   highMax   = iHigh(_Symbol, _Period, 1);
   lowMin    = iLow(_Symbol, _Period, 1);
   for(int i = 2; i <= count; i++)
     {
      double h = iHigh(_Symbol, _Period, i); if(h > highMax) highMax = h;
      double l = iLow(_Symbol, _Period, i);  if(l < lowMin)  lowMin  = l;
     }
  }

double GetStreakRange(ENUM_STREAK_CALC_MODE mode, double openFirst, double closeLast, double highMax, double lowMin)
  {
   if(mode == STREAK_CALC_OPEN_CLOSE) return MathAbs(closeLast - openFirst);
   return (highMax - lowMin);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop();
   ManageMaxHoldBars();
   if(UseWeekendClose) CheckWeekendClose();

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar <= 0 || curBar == g_lastBarTime) return;
   g_lastBarTime = curBar;

   CleanupExpiredPendingOrders();

   if(CountMyPositions() >= MaxTotalOpenPositions) return;
   if(UseDayFilter && !IsDayAllowed()) return;
   if(UseSessionFilter && !IsSessionAllowed()) return;
   if(UseSpreadFilter && IsSpreadHigh()) return;
   if(UseWeekendClose && BlockNewTradeAfterWeekendClose && IsPastWeekendCloseHour()) return;

   if(g_layers[0].enabled) ProcessLayerSignal(0, curBar);
   if(g_layers[1].enabled) ProcessLayerSignal(1, curBar);
   if(g_layers[2].enabled) ProcessLayerSignal(2, curBar);
  }

//+------------------------------------------------------------------+
//| Proses sinyal + eksekusi per layer                               |
//+------------------------------------------------------------------+
void ProcessLayerSignal(int layerIdx, datetime barTime)
  {
   SLayerParams cfg = g_layers[layerIdx];
   if(iBars(_Symbol, _Period) < cfg.streakCount + 1) return;

   int  signal   = EvaluateStreakGeneric(cfg.streakCount);
   bool streakUp = (signal == 1);                        // arah momentum streak
   bool isBuy    = cfg.reverse ? !streakUp : streakUp;   // arah posisi (dibalik jika reverse)

   // --- Logika Filter & Kuota ZigZag ---
   if(UseZigZagFilter)
     {
      int      zzDir    = 0;
      datetime zzAnchor = 0;
      if(!GetZigZagPhase(zzDir, zzAnchor)) return;

      // Reset kuota MaxConsecutive HANYA ketika rentang waktu/gelombang ZigZag berganti
      if(zzDir != g_lastZZDir[layerIdx] || zzAnchor != g_lastZZAnchorTime[layerIdx])
        {
         g_consecutive[layerIdx]      = 0;
         g_lastZZDir[layerIdx]        = zzDir;
         g_lastZZAnchorTime[layerIdx] = zzAnchor;
        }

      // Jika tidak ada momentum confirmation di bar ini, keluar TANPA mereset g_consecutive
      if(signal == 0) return;

      // Pastikan arah trade searah dengan indikator ZigZag
      if(zzDir == 1  && !isBuy) return;   // ZigZag Naik -> Hanya boleh Buy
      if(zzDir == -1 &&  isBuy) return;   // ZigZag Turun -> Hanya boleh Sell

      // Batasi jumlah trade maksimal sebanyak X kali dalam 1 rentang waktu ZigZag ini
      if(g_consecutive[layerIdx] >= cfg.maxConsecutive) return;
     }
   else
     {
      // Perilaku lama jika UseZigZagFilter = false
      if(signal == 0)
        {
         g_consecutive[layerIdx] = 0;
         g_lastSignal[layerIdx]  = 0;
         return;
        }
      if(signal != g_lastSignal[layerIdx])
         g_consecutive[layerIdx] = 0;
      g_lastSignal[layerIdx] = signal;
      if(g_consecutive[layerIdx] >= cfg.maxConsecutive) return;
     }

   if(layerIdx > 0) CancelPendingForLayer(cfg.tag);

   SetAutoFillingType();
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(point <= 0 || ask <= 0 || bid <= 0) return;

   double openFirst, closeLast, highMax, lowMin;
   GetStreakData(cfg.streakCount, openFirst, closeLast, highMax, lowMin);

   // --- Streak size filter ---
   if(cfg.useStreakFilter)
     {
      double streakDist = GetStreakRange(cfg.calcMode, openFirst, closeLast, highMax, lowMin) / point;
      if(streakDist < cfg.minStreakPoints || streakDist > cfg.maxStreakPoints)
         return;
     }

   // --- Entry price ---
   double entry;
   if(layerIdx == 0)
     {
      entry = isBuy ? ask : bid;
     }
   else
     {
      double range = GetStreakRange(cfg.calcMode, openFirst, closeLast, highMax, lowMin);
      if(range <= 0) return;
      double frac = cfg.retracePercent / 100.0;
      double hi   = (cfg.calcMode == STREAK_CALC_OPEN_CLOSE) ? closeLast : highMax;
      double lo   = (cfg.calcMode == STREAK_CALC_OPEN_CLOSE) ? closeLast : lowMin;
      if(!cfg.reverse)
         entry = streakUp ? (hi - range * frac) : (lo + range * frac);   // retrace ke dalam streak
      else
         entry = streakUp ? (hi + range * frac) : (lo - range * frac);   // ekstensi melewati ekstrem streak
     }

   // --- Stop Loss (R) ---
   double R;
   if(cfg.useStaticSL)
      R = cfg.staticSLPoints * point;
   else
     {
      double anchor = (cfg.calcMode == STREAK_CALC_OPEN_CLOSE) ? openFirst : (streakUp ? lowMin : highMax);
      double dist   = streakUp ? (entry - anchor) : (anchor - entry);
      R = dist + SL_BufferPoints * point;
     }
   if(R <= 0 || R < stopLevel) return;

   double slPrice = isBuy ? (entry - R) : (entry + R);

   // --- Take Profit (RRR <= 0 = tanpa TP) ---
   double tp = 0.0;
   if(cfg.rrr > 0)
     {
      if(R * cfg.rrr < stopLevel) return;
      tp = isBuy ? (entry + R * cfg.rrr) : (entry - R * cfg.rrr);
     }

   // --- Lot ---
   double lot;
   if(cfg.useStaticLot)
      lot = NormalizeLot(cfg.staticLot);
   else
      lot = CalculateDynamicLot(R / point, cfg.riskPercent, cfg.staticLot);

   string cmt = cfg.tag + "|" + DoubleToString(R, _Digits);
   double slN = NormalizeDouble(slPrice, _Digits);
   double tpN = (tp > 0) ? NormalizeDouble(tp, _Digits) : 0.0;
   double enN = NormalizeDouble(entry, _Digits);

   bool ok = false;
   if(layerIdx == 0)
     {
      ok = isBuy ? trade.Buy(lot, _Symbol, enN, slN, tpN, cmt)
                 : trade.Sell(lot, _Symbol, enN, slN, tpN, cmt);
     }
   else
     {
      if(isBuy  && entry > (ask - stopLevel)) return;
      if(!isBuy && entry < (bid + stopLevel)) return;
      datetime expr = barTime + (cfg.limitExpireBars * PeriodSeconds(_Period));
      ok = isBuy ? trade.BuyLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_SPECIFIED, expr, cmt)
                 : trade.SellLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_SPECIFIED, expr, cmt);
     }
   if(!ok) Print("Error ", cfg.tag, " [", _Symbol, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction: hitung entry per layer                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;

   string layerTag; double rVal;
   if(!ParseComment(HistoryDealGetString(trans.deal, DEAL_COMMENT), layerTag, rVal)) return;
   int layerIdx = TagToIndex(layerTag);
   if(layerIdx < 0) return;
   g_consecutive[layerIdx]++;
  }

//+------------------------------------------------------------------+
//| Trailing Stop: kontinu, berbasis R, hanya bergerak searah profit |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(point <= 0 || bid <= 0 || ask <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string layerTag; double R;
      if(!ParseComment(PositionGetString(POSITION_COMMENT), layerTag, R)) continue;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx < 0) continue;

      SLayerParams cfg = g_layers[layerIdx];
      if(!cfg.useTrailing || R <= 0) continue;

      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);

      double profit = isBuy ? (bid - entry) : (entry - ask);
      if(profit < cfg.trailStartR * R) continue;

      double dist    = cfg.trailDistR * R;
      double newSL   = isBuy ? (bid - dist) : (ask + dist);
      double minGain = TRAIL_MIN_STEP_R * R;

      if(isBuy)
        {
         if(curSL > 0 && newSL < curSL + minGain) continue;
         if(newSL > bid - stopLevel) continue;
        }
      else
        {
         if(curSL > 0 && newSL > curSL - minGain) continue;
         if(newSL < ask + stopLevel) continue;
        }

      trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), curTP);
     }
  }

//+------------------------------------------------------------------+
//| Max Hold Bars                                                    |
//+------------------------------------------------------------------+
void ManageMaxHoldBars()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string layerTag; double R;
      if(!ParseComment(PositionGetString(POSITION_COMMENT), layerTag, R)) continue;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx < 0) continue;

      SLayerParams cfg = g_layers[layerIdx];
      if(!cfg.useMaxHold) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsOpen = iBarShift(_Symbol, _Period, openTime, false);
      if(barsOpen >= cfg.maxHoldBars)
         trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Lot management                                                   |
//+------------------------------------------------------------------+
int CountMyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      count++;
     }
   return count;
  }

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

double CalculateDynamicLot(double slPoints, double riskPercent, double fallbackLot)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickValue <= 0 || tickSize <= 0 || point <= 0 || slPoints <= 0) return NormalizeLot(fallbackLot);
   double valuePerPoint = tickValue * (point / tickSize);
   double rawLot = riskAmount / (slPoints * valuePerPoint);
   return NormalizeLot(rawLot);
  }

//+------------------------------------------------------------------+
//| Filter handlers                                                  |
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
   if(EnableAsianSession  && InHourRange(h, AsianStartHour,  AsianEndHour))  allowed = true;
   if(EnableLondonSession && InHourRange(h, LondonStartHour, LondonEndHour)) allowed = true;
   if(EnableUSSession     && InHourRange(h, USStartHour,     USEndHour))     allowed = true;
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
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      trade.PositionClose(ticket);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Pending order management                                         |
//+------------------------------------------------------------------+
void CleanupExpiredPendingOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      datetime expr = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(expr > 0 && expr <= TimeCurrent())
         trade.OrderDelete(ticket);
     }
  }

void CancelPendingForLayer(string layerTag)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), layerTag + "|") == 0)
        {
         trade.OrderDelete(ticket);
         Print(_Symbol, " ", layerTag, " - Pending lama dibatalkan, diganti sesuai streak terbaru.");
        }
     }
  }

void SetAutoFillingType()
  {
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                         trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| Custom fitness: Win Rate (%)                                     |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades <= 0) return 0.0;
   return (TesterStatistics(STAT_PROFIT_TRADES) / trades) * 100.0;
  }
//+------------------------------------------------------------------+
