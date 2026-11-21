#property copyright "Custom EA - V6.6 (ZigZag Momentum, Wave Quota & Daily P/L Limit)"
#property version   "6.60"

#include <Trade\Trade.mqh>
CTrade trade;

//================== ENUM ==================
enum ENUM_STREAK_CALC_MODE
  {
   STREAK_CALC_OPEN_CLOSE,  // Open candle pertama ke Close candle terakhir streak
   STREAK_CALC_HIGH_LOW     // High tertinggi ke Low terendah seluruh streak
  };

enum ENUM_TESTER_FITNESS
  {
   TESTER_WINRATE_FILTERED, // Win Rate (%) dgn syarat Net Profit > 0 & Min Trades
   TESTER_PROFIT_FACTOR,    // Profit Factor dgn syarat Min Trades
   TESTER_COMPOSITE_SCORE   // Skor Gabungan: WinRate * RecoveryFactor * ln(Trades+1)
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
input double L1_TrailDistR           = 1.0;     // Catatan: agar bisa lock profit sebelum TP, set < L1_RRR (mis. 0.5)
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
input int  WeekendCloseHour               = 20;   // Jam Server Broker (hari Jumat)
input bool BlockNewTradeAfterWeekendClose = true;

//================== INPUT: GROUP 5 - SESSION & DAY FILTER ==================
input group "=== 5. Session & Day Filter (Jam Server Broker) ==="
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
input bool TradeSaturday  = false;
input bool TradeSunday    = false;

//================== INPUT: GROUP 6 - SYSTEM FILTER ==================
input group "=== 6. System Filter ==="
input bool   UseSpreadFilter            = true;
input double MaxSpreadPoints            = 500;
input int    MaxTotalOpenPositions      = 10;
input bool   CountPendingInMaxPositions = true;  // Ikut hitung pending order dalam batas posisi
input double MaxLotCap                  = 0.0;   // Batas atas lot pengaman (0 = ikuti max broker)
input double SL_BufferPoints            = 0;
input int    MagicNumber                = 777070;

//================== INPUT: GROUP 7 - ZIGZAG FILTER ==================
input group "=== 7. ZigZag Trend & Quota Filter ==="
input bool            UseZigZagFilter = true;           // Aktifkan Filter & Kuota ZigZag
input ENUM_TIMEFRAMES ZZ_Timeframe    = PERIOD_CURRENT; // Timeframe Indikator ZigZag
input int             ZZ_Depth        = 12;             // ZigZag Depth
input int             ZZ_Deviation    = 5;              // ZigZag Deviation
input int             ZZ_Backstep     = 3;              // ZigZag Backstep
input int             ZZ_LookbackBars = 300;            // Bar pencarian titik ZigZag

//================== INPUT: GROUP 8 - DAILY PROFIT & LOSS LIMIT ==================
input group "=== 8. Daily Profit & Loss Limit ==="
input bool   UseDailyProfitLossLimit  = true;           // Aktifkan Batas Profit/Loss Harian
input double DailyProfitTargetPercent = 10.0;           // Target Profit Harian (%) (0 = Nonaktif)
input double DailyMaxLossPercent      = 5.0;            // Batas Max Loss Harian (%) (0 = Nonaktif, isi positif)
input bool   IncludeFloatingInDailyPL = true;           // Ikut hitung perubahan Floating P/L hari ini
input bool   CloseAllOnDailyLimitHit  = true;           // Tutup semua posisi & pending saat batas tercapai

//================== INPUT: GROUP 9 - OPTIMIZATION FITNESS ==================
input group "=== 9. Optimization Fitness (OnTester) ==="
input ENUM_TESTER_FITNESS TesterFitnessMode = TESTER_WINRATE_FILTERED;
input int                 TesterMinTrades   = 30;       // Minimal jumlah trade agar skor optimasi valid

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
int          g_consecutive[3];
int          g_lastSignal[3];
int          g_lastZZDir[3];
datetime     g_lastZZAnchorTime[3];
ulong        g_lastCountedOrder[3];

int          g_zzHandle       = INVALID_HANDLE;
bool         g_zzAddedToChart = false;
string       g_zzShortName    = "";
datetime     g_lastBarTime    = 0;

// Variabel kontrol Daily Profit/Loss Limit (ter-cache)
datetime     g_dayStartTime      = 0;
double       g_dayStartBalance   = 0.0;
double       g_dayStartFloating  = 0.0;
double       g_todayRealizedPL   = 0.0;
bool         g_dailyLimitReached = false;
bool         g_realizedDirty     = true;
int          g_lastPosTotal      = -1;

// Variabel anti-spam retry saat close/delete gagal
datetime     g_lastCloseRetryTime     = 0;
datetime     g_lastMaxHoldRetryTime   = 0;
datetime     g_lastCleanupRetryTime   = 0;
bool         g_hasPendingMaxHoldClose = false;
bool         g_hasPendingOrderCleanup = false;

const double TRAIL_MIN_STEP_R         = 0.02; // Minimal perbaikan SL trailing dalam satuan R
const int    CLOSE_RETRY_COOLDOWN_SEC = 3;    // Jeda retry jika Close/Delete gagal

//+------------------------------------------------------------------+
//| Isi parameter satu layer                                         |
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
   g_layers[idx].useStreakFilter = useStreakFilter; // Tidak lagi dinonaktifkan paksa saat StaticSL aktif
   g_layers[idx].minStreakPoints = minStreak;
   g_layers[idx].maxStreakPoints = maxStreak;
   g_layers[idx].rrr             = rrr;
   g_layers[idx].useTrailing     = useTrailing;
   g_layers[idx].trailStartR     = trailStartR;
   g_layers[idx].trailDistR      = trailDistR;
   g_layers[idx].limitExpireBars = limitExpireBars;
   g_layers[idx].useMaxHold      = useMaxHold;
   g_layers[idx].maxHoldBars     = maxHoldBars;

   if(enabled && useTrailing && rrr > 0.0 && trailDistR >= rrr)
      Print("INFO ", tag, ": TrailDistR (", DoubleToString(trailDistR, 2), ") >= RRR (", DoubleToString(rrr, 2),
            "). Trailing hanya mempersempit SL dan tidak akan mengunci profit sebelum TP tersentuh.");
  }

//+------------------------------------------------------------------+
//| Validasi input sebelum inisialisasi                              |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(MaxTotalOpenPositions < 1)
     {
      Print("ERROR: MaxTotalOpenPositions minimal 1.");
      return false;
     }
   if(UseZigZagFilter && (ZZ_Depth < 1 || ZZ_LookbackBars < 10))
     {
      Print("ERROR: ZZ_Depth minimal 1 dan ZZ_LookbackBars minimal 10.");
      return false;
     }

   for(int i = 0; i < 3; i++)
     {
      if(!g_layers[i].enabled) continue;
      string t = g_layers[i].tag;

      if(g_layers[i].streakCount < 1)
        {
         Print("ERROR ", t, ": StreakCount minimal 1.");
         return false;
        }
      if(g_layers[i].maxConsecutive < 1)
        {
         Print("ERROR ", t, ": MaxConsecutiveTrades minimal 1.");
         return false;
        }
      if(g_layers[i].useStaticSL && g_layers[i].staticSLPoints <= 0.0)
        {
         Print("ERROR ", t, ": StaticSLPoints harus > 0.");
         return false;
        }
      if(g_layers[i].useStreakFilter && g_layers[i].minStreakPoints > g_layers[i].maxStreakPoints)
        {
         Print("ERROR ", t, ": MinStreakPoints tidak boleh lebih besar dari MaxStreakPoints.");
         return false;
        }
      if(g_layers[i].useMaxHold && g_layers[i].maxHoldBars < 1)
        {
         Print("ERROR ", t, ": MaxHoldBars minimal 1.");
         return false;
        }
      if(i > 0)
        {
         if(g_layers[i].limitExpireBars < 1)
           {
            Print("ERROR ", t, ": LimitExpireBars minimal 1.");
            return false;
           }
         if(g_layers[i].retracePercent <= 0.0)
           {
            Print("ERROR ", t, ": RetracePercent harus > 0.");
            return false;
           }
         if(!g_layers[i].reverse && !g_layers[i].useStaticSL && g_layers[i].retracePercent >= 100.0)
           {
            Print("ERROR ", t, ": RetracePercent harus < 100 saat mode normal & Dynamic SL.");
            return false;
           }
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   for(int i = 0; i < 3; i++)
     {
      g_consecutive[i]      = 0;
      g_lastSignal[i]       = 0;
      g_lastZZDir[i]        = 0;
      g_lastZZAnchorTime[i] = 0;
      g_lastCountedOrder[i] = 0;
     }

   g_zzHandle               = INVALID_HANDLE;
   g_zzAddedToChart         = false;
   g_zzShortName            = "";
   g_lastBarTime            = 0;
   g_dayStartTime           = 0;
   g_dayStartBalance        = 0.0;
   g_dayStartFloating       = 0.0;
   g_todayRealizedPL        = 0.0;
   g_dailyLimitReached      = false;
   g_realizedDirty          = true;
   g_lastPosTotal           = -1;
   g_lastCloseRetryTime     = 0;
   g_lastMaxHoldRetryTime   = 0;
   g_lastCleanupRetryTime   = 0;
   g_hasPendingMaxHoldClose = false;
   g_hasPendingOrderCleanup = false;

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

   if(!ValidateInputs())
      return(INIT_PARAMETERS_INCORRECT);

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("WARNING: Akun bukan tipe Hedging. Tracking multi-layer, Trailing Stop, dan MaxHoldBars berbasis comment paling akurat pada akun Hedging.");

   if(UseZigZagFilter)
     {
      g_zzHandle = iCustom(_Symbol, ZZ_Timeframe, "Examples\\ZigZag", ZZ_Depth, ZZ_Deviation, ZZ_Backstep);
      if(g_zzHandle == INVALID_HANDLE)
        {
         Print("ERROR: Gagal memuat indikator Examples\\ZigZag. Pastikan indikator tersedia di folder Indicators\\Examples.");
         return(INIT_FAILED);
        }

      // Hanya pasang ke chart jika timeframe sama & bukan optimasi non-visual
      bool canDraw = (ZZ_Timeframe == PERIOD_CURRENT || ZZ_Timeframe == _Period)
                  && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
      if(canDraw)
        {
         int beforeTotal = ChartIndicatorsTotal(0, 0);
         if(ChartIndicatorAdd(0, 0, g_zzHandle))
           {
            g_zzAddedToChart = true;
            int afterTotal = ChartIndicatorsTotal(0, 0);
            if(afterTotal > beforeTotal)
               g_zzShortName = ChartIndicatorName(0, 0, afterTotal - 1);
           }
        }
     }

   trade.SetExpertMagicNumber(MagicNumber);
   SetAutoFillingType();

   Print("EA V6.6 Initialized. Symbol=", _Symbol, " Period=", EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_zzAddedToChart && g_zzHandle != INVALID_HANDLE)
     {
      int  total   = ChartIndicatorsTotal(0, 0);
      bool deleted = false;
      for(int i = total - 1; i >= 0; i--)
        {
         string name = ChartIndicatorName(0, 0, i);
         int    h    = ChartIndicatorGet(0, 0, name);
         if(h != INVALID_HANDLE)
           {
            bool match = (h == g_zzHandle);
            IndicatorRelease(h);
            if(match)
              {
               ChartIndicatorDelete(0, 0, name);
               deleted = true;
               break;
              }
           }
        }
      if(!deleted && g_zzShortName != "")
         ChartIndicatorDelete(0, 0, g_zzShortName);

      g_zzAddedToChart = false;
      g_zzShortName    = "";
     }

   if(g_zzHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_zzHandle);
      g_zzHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| GlobalVariable key helper (persisten baseline harian di live)    |
//+------------------------------------------------------------------+
string MakeGVKey(string suffix)
  {
   return "EAV66_" + _Symbol + "_" + IntegerToString(MagicNumber) + "_" + suffix;
  }

//+------------------------------------------------------------------+
//| Hitung Realized P/L hari ini (MagicNumber & Symbol)              |
//+------------------------------------------------------------------+
double GetTodayRealizedPL(datetime dayStart)
  {
   if(!HistorySelect(dayStart, TimeCurrent() + 60)) return 0.0;

   double totalPL    = 0.0;
   int    totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if((int)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;

      ENUM_DEAL_TYPE dType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      if(dType != DEAL_TYPE_BUY && dType != DEAL_TYPE_SELL) continue;

      totalPL += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
               + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
               + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
               + HistoryDealGetDouble(dealTicket, DEAL_FEE);
     }
   return totalPL;
  }

//+------------------------------------------------------------------+
//| Hitung Floating P/L saat ini (MagicNumber & Symbol)              |
//+------------------------------------------------------------------+
double GetFloatingPL()
  {
   double floating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      floating += PositionGetDouble(POSITION_PROFIT)
                + PositionGetDouble(POSITION_SWAP);
     }
   return floating;
  }

//+------------------------------------------------------------------+
//| Hapus semua pending order milik EA ini (dengan cooldown retry)   |
//+------------------------------------------------------------------+
void CancelAllMyPendingOrders()
  {
   if(CountMyPendingOrders() == 0) return;
   datetime now = TimeCurrent();
   if(g_lastCloseRetryTime > 0 && (now - g_lastCloseRetryTime) < CLOSE_RETRY_COOLDOWN_SEC)
      return;

   bool anyFailed = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      if(!trade.OrderDelete(ticket))
        {
         anyFailed = true;
         Print("Warning: Gagal hapus pending #", ticket, " retcode=", trade.ResultRetcode());
        }
     }
   g_lastCloseRetryTime = anyFailed ? now : 0;
  }

//+------------------------------------------------------------------+
//| Tutup semua posisi & pending milik EA (dengan cooldown retry)    |
//+------------------------------------------------------------------+
void CloseAllMyPositionsAndOrders()
  {
   if(CountMyPositions() == 0 && CountMyPendingOrders() == 0) return;
   datetime now = TimeCurrent();
   if(g_lastCloseRetryTime > 0 && (now - g_lastCloseRetryTime) < CLOSE_RETRY_COOLDOWN_SEC)
      return;

   bool anyFailed = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      if(!trade.PositionClose(ticket))
        {
         anyFailed = true;
         Print("Warning: Gagal close posisi #", ticket, " retcode=", trade.ResultRetcode());
        }
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      if(!trade.OrderDelete(ticket))
        {
         anyFailed = true;
         Print("Warning: Gagal hapus pending #", ticket, " retcode=", trade.ResultRetcode());
        }
     }

   g_lastCloseRetryTime = anyFailed ? now : 0;
  }

//+------------------------------------------------------------------+
//| Cek & Update Status Batas Profit/Loss Harian (Ringan / Cached)   |
//+------------------------------------------------------------------+
bool CheckDailyLimit()
  {
   if(!UseDailyProfitLossLimit) return false;

   datetime now      = TimeCurrent();
   datetime dayStart = now - (now % 86400); // Jam 00:00:00 waktu server

   // Reset otomatis saat ganti hari atau inisialisasi pertama
   if(dayStart != g_dayStartTime)
     {
      bool isGenuineRollover = (g_dayStartTime != 0);
      g_dayStartTime         = dayStart;
      g_dailyLimitReached    = false;
      g_lastCloseRetryTime   = 0;

      g_todayRealizedPL = GetTodayRealizedPL(dayStart);
      g_realizedDirty   = false;
      g_lastPosTotal    = PositionsTotal();

      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE) - g_todayRealizedPL;
      if(g_dayStartBalance <= 0.0)
         g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      // Catat baseline floating posisi menginap (overnight) agar tidak langsung memicu limit di 00:00
      string kDay   = MakeGVKey("DT");
      string kFloat = MakeGVKey("DF");
      bool   isTest = (bool)MQLInfoInteger(MQL_TESTER);

      if(isGenuineRollover)
        {
         g_dayStartFloating = GetFloatingPL();
         if(!isTest)
           {
            GlobalVariableSet(kDay, (double)dayStart);
            GlobalVariableSet(kFloat, g_dayStartFloating);
           }
        }
      else
        {
         if(!isTest && GlobalVariableCheck(kDay) && (datetime)GlobalVariableGet(kDay) == dayStart && GlobalVariableCheck(kFloat))
            g_dayStartFloating = GlobalVariableGet(kFloat);
         else if((now - dayStart) < 60)
           {
            g_dayStartFloating = GetFloatingPL();
            if(!isTest)
              {
               GlobalVariableSet(kDay, (double)dayStart);
               GlobalVariableSet(kFloat, g_dayStartFloating);
              }
           }
         else
            g_dayStartFloating = 0.0;
        }

      Print("Hari baru dimulai (", TimeToString(dayStart, TIME_DATE),
            "). Saldo Awal=", DoubleToString(g_dayStartBalance, 2),
            " Floating Awal=", DoubleToString(g_dayStartFloating, 2));
     }

   // Jika hari ini sudah kena limit
   if(g_dailyLimitReached)
     {
      if(CloseAllOnDailyLimitHit) CloseAllMyPositionsAndOrders();
      else                        CancelAllMyPendingOrders();
      return true;
     }

   // Refresh Realized P/L hanya jika terjadi transaksi atau perubahan jumlah posisi
   int curPosTotal = PositionsTotal();
   if(curPosTotal != g_lastPosTotal)
     {
      g_lastPosTotal  = curPosTotal;
      g_realizedDirty = true;
     }
   if(g_realizedDirty)
     {
      g_todayRealizedPL = GetTodayRealizedPL(dayStart);
      g_realizedDirty   = false;
     }

   double baseBalance = g_dayStartBalance + (IncludeFloatingInDailyPL ? g_dayStartFloating : 0.0);
   if(baseBalance <= 0.0) baseBalance = g_dayStartBalance;
   if(baseBalance <= 0.0) return false;

   double totalPL = g_todayRealizedPL;
   if(IncludeFloatingInDailyPL)
      totalPL += (GetFloatingPL() - g_dayStartFloating);

   double pctPL = (totalPL / baseBalance) * 100.0;

   // Cek Target Profit Harian (+%)
   if(DailyProfitTargetPercent > 0.0 && pctPL >= DailyProfitTargetPercent)
     {
      g_dailyLimitReached  = true;
      g_lastCloseRetryTime = 0;
      Print("TARGET PROFIT HARIAN TERCAPAI: +", DoubleToString(pctPL, 2), "% (Target: +",
            DoubleToString(DailyProfitTargetPercent, 2), "%). Stop entry hari ini, lanjut besok.");
      if(CloseAllOnDailyLimitHit) CloseAllMyPositionsAndOrders();
      else                        CancelAllMyPendingOrders();
      return true;
     }

   // Cek Max Loss Harian (-%)
   double maxLossLimit = -MathAbs(DailyMaxLossPercent);
   if(DailyMaxLossPercent > 0.0 && pctPL <= maxLossLimit)
     {
      g_dailyLimitReached  = true;
      g_lastCloseRetryTime = 0;
      Print("BATAS LOSS HARIAN TERCAPAI: ", DoubleToString(pctPL, 2), "% (Batas: ",
            DoubleToString(maxLossLimit, 2), "%). Stop entry hari ini, lanjut besok.");
      if(CloseAllOnDailyLimitHit) CloseAllMyPositionsAndOrders();
      else                        CancelAllMyPendingOrders();
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Deteksi Fase ZigZag (1 = Naik, -1 = Turun)                       |
//+------------------------------------------------------------------+
bool GetZigZagPhase(int &zzDir, datetime &anchorTime)
  {
   zzDir      = 0;
   anchorTime = 0;
   if(g_zzHandle == INVALID_HANDLE) return false;

   int calculated = BarsCalculated(g_zzHandle);
   if(calculated < 2) return false;

   int toCopy = MathMin(ZZ_LookbackBars, calculated);
   double zzBuf[];
   ArraySetAsSeries(zzBuf, true);
   int copied = CopyBuffer(g_zzHandle, 0, 0, toCopy, zzBuf);
   if(copied < 2) return false;

   double   pivots[2];
   datetime pivotTimes[2];
   int      found = 0;

   // Scan mulai dari i = 0 agar tidak terbalik saat pivot aktif berpindah ke bar 0 (gap / MTF)
   for(int i = 0; i < copied && found < 2; i++)
     {
      if(zzBuf[i] != 0.0 && zzBuf[i] != EMPTY_VALUE)
        {
         datetime t = iTime(_Symbol, ZZ_Timeframe, i);
         if(t <= 0) return false;
         pivots[found]     = zzBuf[i];
         pivotTimes[found] = t;
         found++;
        }
     }

   if(found < 2) return false;

   anchorTime = pivotTimes[1];
   if(pivots[0] > pivots[1])
      zzDir = 1;
   else if(pivots[0] < pivots[1])
      zzDir = -1;
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
   if(count < 1 || iBars(_Symbol, _Period) < count + 1) return 0;

   bool allGreen = true, allRed = true;
   for(int i = 1; i <= count; i++)
     {
      double o = iOpen(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      if(o <= 0.0 || c <= 0.0) return 0;
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
   // 1. Cek batas profit/loss harian (realized di-cache)
   bool dailyBlocked = CheckDailyLimit();

   // 2. Manajemen posisi aktif TETAP berjalan meskipun daily limit tercapai (CloseAll=false)
   ManageTrailingStop();
   if(UseWeekendClose) CheckWeekendClose();
   if(g_hasPendingMaxHoldClose) ManageMaxHoldBars();
   if(g_hasPendingOrderCleanup) CleanupExpiredPendingOrders();

   // 3. Logika per bar baru
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar <= 0 || curBar == g_lastBarTime) return;
   g_lastBarTime = curBar;

   // Refresh realized P/L ringan 1x per bar (jaga-jaga rollover swap)
   g_realizedDirty = true;

   // Reset cooldown agar eksekusi bar baru langsung jalan
   g_lastMaxHoldRetryTime = 0;
   g_lastCleanupRetryTime = 0;
   ManageMaxHoldBars();
   CleanupExpiredPendingOrders();

   // Jika daily limit aktif, hentikan proses entry baru
   if(dailyBlocked) return;

   // 4. Sinkronisasi fase ZigZag / streak 1x per bar (sebelum filter agar reset & pembatalan pending konsisten)
   bool     zzValid  = false;
   int      zzDir    = 0;
   datetime zzAnchor = 0;

   if(UseZigZagFilter)
     {
      zzValid = GetZigZagPhase(zzDir, zzAnchor);
      if(zzValid)
        {
         for(int i = 0; i < 3; i++)
           {
            if(!g_layers[i].enabled) continue;
            if(zzDir != g_lastZZDir[i] || zzAnchor != g_lastZZAnchorTime[i])
              {
               g_consecutive[i]      = 0;
               g_lastZZDir[i]        = zzDir;
               g_lastZZAnchorTime[i] = zzAnchor;
               // Batalkan pending dari gelombang sebelumnya agar tidak terisi melawan ZigZag baru
               if(i > 0) CancelPendingForLayer(g_layers[i].tag);
              }
           }
        }
     }
   else
     {
      for(int i = 0; i < 3; i++)
        {
         if(!g_layers[i].enabled) continue;
         int sig = EvaluateStreakGeneric(g_layers[i].streakCount);
         if(sig == 0)
           {
            g_consecutive[i] = 0;
            g_lastSignal[i]  = 0;
           }
         else if(sig != g_lastSignal[i])
           {
            g_consecutive[i] = 0;
            g_lastSignal[i]  = sig;
           }
        }
     }

   // 5. Filter global untuk entry baru
   if(UseDayFilter && !IsDayAllowed()) return;
   if(UseSessionFilter && !IsSessionAllowed()) return;
   if(UseSpreadFilter && IsSpreadHigh()) return;
   if(UseWeekendClose && BlockNewTradeAfterWeekendClose && IsPastWeekendCloseHour()) return;
   if(UseZigZagFilter && !zzValid) return;

   // 6. Proses sinyal per layer
   for(int i = 0; i < 3; i++)
     {
      if(g_layers[i].enabled)
         ProcessLayerSignal(i, curBar, zzDir);
     }
  }

//+------------------------------------------------------------------+
//| Proses sinyal + eksekusi per layer                               |
//+------------------------------------------------------------------+
void ProcessLayerSignal(int layerIdx, datetime barTime, int zzDir)
  {
   int signal = EvaluateStreakGeneric(g_layers[layerIdx].streakCount);
   if(signal == 0) return;

   bool streakUp = (signal == 1);
   bool isBuy    = g_layers[layerIdx].reverse ? !streakUp : streakUp;

   // Filter arah ZigZag
   if(UseZigZagFilter)
     {
      if(zzDir == 1  && !isBuy) return;
      if(zzDir == -1 &&  isBuy) return;
     }

   // Cek kuota trade per fase/gelombang
   if(g_consecutive[layerIdx] >= g_layers[layerIdx].maxConsecutive) return;

   // Cek batas total posisi (memperhitungkan pending order & pergantian pending layer ini sendiri)
   int activeExposure = CountMyPositions();
   if(CountPendingInMaxPositions)
     {
      int ownPending = (layerIdx > 0) ? CountPendingForLayer(g_layers[layerIdx].tag) : 0;
      activeExposure += (CountMyPendingOrders() - ownPending);
     }
   if(activeExposure >= MaxTotalOpenPositions) return;

   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(point <= 0.0 || ask <= 0.0 || bid <= 0.0) return;

   double minStep = MathMax(tickSize, point);
   double minStop = (stopLevel > 0.0) ? stopLevel : minStep;
   double eps     = point * 0.01;

   double openFirst, closeLast, highMax, lowMin;
   GetStreakData(g_layers[layerIdx].streakCount, openFirst, closeLast, highMax, lowMin);

   double range = GetStreakRange(g_layers[layerIdx].calcMode, openFirst, closeLast, highMax, lowMin);
   if(range <= 0.0) return;

   // --- Streak size filter (berfungsi baik untuk Static SL maupun Dynamic SL) ---
   if(g_layers[layerIdx].useStreakFilter)
     {
      double streakDistPts = range / point;
      if(streakDistPts < g_layers[layerIdx].minStreakPoints || streakDistPts > g_layers[layerIdx].maxStreakPoints)
         return;
     }

   // --- Harga Entry ---
   double entry;
   double frac = g_layers[layerIdx].retracePercent / 100.0;
   if(layerIdx == 0)
     {
      entry = isBuy ? ask : bid;
     }
   else
     {
      double hi = (g_layers[layerIdx].calcMode == STREAK_CALC_OPEN_CLOSE) ? closeLast : highMax;
      double lo = (g_layers[layerIdx].calcMode == STREAK_CALC_OPEN_CLOSE) ? closeLast : lowMin;
      if(!g_layers[layerIdx].reverse)
         entry = streakUp ? (hi - range * frac) : (lo + range * frac); // retrace ke dalam streak
      else
         entry = streakUp ? (hi + range * frac) : (lo - range * frac); // ekstensi melewati ekstrem streak
     }

   // --- Stop Loss (R) ---
   double R;
   if(g_layers[layerIdx].useStaticSL)
     {
      R = g_layers[layerIdx].staticSLPoints * point;
     }
   else
     {
      double dist = 0.0;
      if(!g_layers[layerIdx].reverse)
        {
         double anchor = (g_layers[layerIdx].calcMode == STREAK_CALC_OPEN_CLOSE)
                       ? openFirst
                       : (streakUp ? lowMin : highMax);
         dist = streakUp ? (entry - anchor) : (anchor - entry);
        }
      else
        {
         // Mode Reverse: cerminan simetris dari mode normal
         // L1 -> 100% range; L2/L3 (frac < 1) -> (1 - frac)*range (SL seragam di 100% ekstensi), else 100% range
         if(layerIdx == 0 || frac >= 1.0)
            dist = range;
         else
            dist = range * (1.0 - frac);
        }
      R = dist + SL_BufferPoints * point;
     }

   if(R <= 0.0) return;

   double enN     = NormalizePrice(entry);
   double slPrice = isBuy ? (enN - R) : (enN + R);
   double slN     = NormalizePrice(slPrice);
   double R_eff   = MathAbs(enN - slN);
   if(R_eff <= 0.0 || slN <= 0.0) return;

   // --- Take Profit berbasis R_eff agar konsisten dengan SL ter-normalisasi ---
   double tpN = 0.0;
   if(g_layers[layerIdx].rrr > 0.0)
     {
      double tpRaw = isBuy ? (enN + R_eff * g_layers[layerIdx].rrr)
                           : (enN - R_eff * g_layers[layerIdx].rrr);
      tpN = NormalizePrice(tpRaw);
      if(tpN <= 0.0) return;
     }

   // --- Validasi StopLevel & Sisi Pasar (SETELAH normalisasi harga) ---
   if(layerIdx == 0)
     {
      if(isBuy)
        {
         if((bid - slN) + eps < minStop) return;
         if(tpN > 0.0 && ((tpN - bid) + eps < minStop || tpN <= enN)) return;
        }
      else
        {
         if((slN - ask) + eps < minStop) return;
         if(tpN > 0.0 && ((ask - tpN) + eps < minStop || tpN >= enN)) return;
        }
     }
   else
     {
      if(isBuy)
        {
         if((ask - enN) + eps < minStop) return;
         if((enN - slN) + eps < minStop) return;
         if(tpN > 0.0 && (tpN - enN) + eps < minStop) return;
        }
      else
        {
         if((enN - bid) + eps < minStop) return;
         if((slN - enN) + eps < minStop) return;
         if(tpN > 0.0 && (enN - tpN) + eps < minStop) return;
        }
     }

   // --- Hitung Lot + Proteksi Free Margin ---
   double lot;
   if(g_layers[layerIdx].useStaticLot)
      lot = NormalizeLot(g_layers[layerIdx].staticLot);
   else
      lot = CalculateDynamicLot(R_eff, g_layers[layerIdx].riskPercent, g_layers[layerIdx].staticLot);

   ENUM_ORDER_TYPE marginOrderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   lot = AdjustLotForMargin(marginOrderType, lot, enN);
   if(lot <= 0.0)
     {
      Print("Warning ", g_layers[layerIdx].tag, ": Free margin tidak cukup untuk membuka posisi.");
      return;
     }

   // Batalkan pending lama HANYA setelah order baru dipastikan valid lolos semua filter
   if(layerIdx > 0)
      CancelPendingForLayer(g_layers[layerIdx].tag);

   string cmt = g_layers[layerIdx].tag + "|" + DoubleToString(R_eff, _Digits);
   bool   ok  = false;

   if(layerIdx == 0)
     {
      // Harga 0.0 agar CTrade mengambil tick Bid/Ask terbaru saat eksekusi
      ok = isBuy ? trade.Buy(lot, _Symbol, 0.0, slN, tpN, cmt)
                 : trade.Sell(lot, _Symbol, 0.0, slN, tpN, cmt);
     }
   else
     {
      uint     expMode = (uint)SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
      datetime expr    = barTime + (g_layers[layerIdx].limitExpireBars * PeriodSeconds(_Period));

      if((expMode & SYMBOL_EXPIRATION_SPECIFIED) != 0 && expr > TimeCurrent())
        {
         ok = isBuy ? trade.BuyLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_SPECIFIED, expr, cmt)
                    : trade.SellLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_SPECIFIED, expr, cmt);

         // Fallback otomatis ke GTC jika broker menolak durasi expiry pendek (10022)
         if(!ok && trade.ResultRetcode() == TRADE_RETCODE_INVALID_EXPIRATION)
           {
            ok = isBuy ? trade.BuyLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, cmt)
                       : trade.SellLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, cmt);
           }
        }
      else
        {
         ok = isBuy ? trade.BuyLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, cmt)
                    : trade.SellLimit(lot, enN, _Symbol, slN, tpN, ORDER_TIME_GTC, 0, cmt);
        }
     }

   if(!ok)
      Print("Error ", g_layers[layerIdx].tag, " [", _Symbol, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction: hitung entry per layer & refresh P/L cache   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   g_realizedDirty = true;

   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN) return;

   ulong  orderTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   string layerTag;
   double rVal;

   bool parsed = ParseComment(HistoryDealGetString(trans.deal, DEAL_COMMENT), layerTag, rVal);
   if(!parsed && orderTicket > 0 && HistoryOrderSelect(orderTicket))
      parsed = ParseComment(HistoryOrderGetString(orderTicket, ORDER_COMMENT), layerTag, rVal);
   if(!parsed) return;

   int layerIdx = TagToIndex(layerTag);
   if(layerIdx < 0) return;

   // Hindari penghitungan ganda bila 1 order mengalami partial fills
   if(orderTicket > 0 && orderTicket == g_lastCountedOrder[layerIdx]) return;
   g_lastCountedOrder[layerIdx] = orderTicket;

   g_consecutive[layerIdx]++;
  }

//+------------------------------------------------------------------+
//| Trailing Stop: kontinu, berbasis R, cek FreezeLevel & TickSize   |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double stopLevel   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
   double bid         = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask         = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(point <= 0.0 || bid <= 0.0 || ask <= 0.0) return;

   double minStep = MathMax(tickSize, point);
   double minStop = (stopLevel > 0.0) ? stopLevel : minStep;
   double eps     = point * 0.01;

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

      if(!g_layers[layerIdx].useTrailing || R <= 0.0) continue;

      bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      // Cek Freeze Level sebelum modifikasi
      if(freezeLevel > 0.0)
        {
         if(isBuy)
           {
            if(curSL > 0.0 && (bid - curSL) < freezeLevel + eps) continue;
            if(curTP > 0.0 && (curTP - bid) < freezeLevel + eps) continue;
           }
         else
           {
            if(curSL > 0.0 && (curSL - ask) < freezeLevel + eps) continue;
            if(curTP > 0.0 && (ask - curTP) < freezeLevel + eps) continue;
           }
        }

      double profit = isBuy ? (bid - entry) : (entry - ask);
      if(profit < g_layers[layerIdx].trailStartR * R) continue;

      double dist    = g_layers[layerIdx].trailDistR * R;
      double newSL   = NormalizePrice(isBuy ? (bid - dist) : (ask + dist));
      if(newSL <= 0.0) continue;

      double minGain = MathMax(TRAIL_MIN_STEP_R * R, minStep);

      if(isBuy)
        {
         if(curSL > 0.0 && (newSL - curSL) + eps < minGain) continue;
         if((bid - newSL) + eps < minStop) continue;
         if(curSL > 0.0 && MathAbs(newSL - curSL) < minStep * 0.5) continue;
        }
      else
        {
         if(curSL > 0.0 && (curSL - newSL) + eps < minGain) continue;
         if((newSL - ask) + eps < minStop) continue;
         if(curSL > 0.0 && MathAbs(newSL - curSL) < minStep * 0.5) continue;
        }

      if(!trade.PositionModify(ticket, newSL, curTP))
        {
         uint rc = trade.ResultRetcode();
         if(rc != TRADE_RETCODE_NO_CHANGES)
            Print("Warning Trailing #", ticket, " retcode=", rc, " - ", trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Max Hold Bars (dijalankan per bar baru + retry jika gagal)       |
//+------------------------------------------------------------------+
void ManageMaxHoldBars()
  {
   datetime now = TimeCurrent();
   if(g_lastMaxHoldRetryTime > 0 && (now - g_lastMaxHoldRetryTime) < CLOSE_RETRY_COOLDOWN_SEC)
      return;

   bool anyFailed = false;
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

      if(!g_layers[layerIdx].useMaxHold || g_layers[layerIdx].maxHoldBars < 1) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int      barsOpen = iBarShift(_Symbol, _Period, openTime, false);
      if(barsOpen >= g_layers[layerIdx].maxHoldBars)
        {
         if(!trade.PositionClose(ticket))
           {
            anyFailed = true;
            Print("Warning MaxHoldBars close #", ticket, " retcode=", trade.ResultRetcode());
           }
        }
     }

   g_hasPendingMaxHoldClose = anyFailed;
   g_lastMaxHoldRetryTime   = anyFailed ? now : 0;
  }

//+------------------------------------------------------------------+
//| Helper Normalisasi Harga & Lot                                   |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0.0)
      price = MathRound(price / tickSize) * tickSize;
   return NormalizeDouble(price, _Digits);
  }

int GetVolumeDigits(double step)
  {
   if(step <= 0.0) return 2;
   int    digits = 0;
   double s      = step;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1e-8)
     {
      s *= 10.0;
      digits++;
     }
   return digits;
  }

double NormalizeLot(double targetLot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(MaxLotCap > 0.0 && MaxLotCap < maxLot)
      maxLot = MaxLotCap;

   int volDigits = GetVolumeDigits(stepLot);
   if(stepLot > 0.0)
      targetLot = MathFloor((targetLot / stepLot) + 1e-9) * stepLot;
   if(targetLot < minLot) targetLot = minLot;
   if(targetLot > maxLot) targetLot = maxLot;
   return NormalizeDouble(targetLot, volDigits);
  }

double CalculateDynamicLot(double slPriceDist, double riskPercent, double fallbackLot)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(riskAmount <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0 || slPriceDist <= 0.0)
      return NormalizeLot(fallbackLot);

   double ticks  = slPriceDist / tickSize;
   double rawLot = riskAmount / (ticks * tickValue);
   return NormalizeLot(rawLot);
  }

double AdjustLotForMargin(ENUM_ORDER_TYPE orderType, double lot, double price)
  {
   double minLot     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin <= 0.0) return 0.0;

   double marginRequired = 0.0;
   if(!OrderCalcMargin(orderType, _Symbol, lot, price, marginRequired) || marginRequired <= 0.0)
      return lot;

   double usableMargin = freeMargin * 0.95;
   if(marginRequired <= usableMargin)
      return lot;

   double scaled = lot * (usableMargin / marginRequired);
   if(scaled < minLot) return 0.0;

   double adjLot = NormalizeLot(scaled);
   if(OrderCalcMargin(orderType, _Symbol, adjLot, price, marginRequired) && marginRequired > usableMargin)
      return 0.0;

   return adjLot;
  }

//+------------------------------------------------------------------+
//| Counter posisi & pending order                                   |
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

int CountMyPendingOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      count++;
     }
   return count;
  }

int CountPendingForLayer(string layerTag)
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), layerTag + "|") == 0)
         count++;
     }
   return count;
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
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
     {
      case 0: return TradeSunday;
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      case 6: return TradeSaturday;
      default: return false;
     }
  }

bool InHourRange(int h, int startH, int endH)
  {
   if(startH == endH) return true;
   if(startH < endH)  return (h >= startH && h < endH);
   return (h >= startH || h < endH);
  }

bool IsSessionAllowed()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int  h       = dt.hour;
   bool allowed = false;
   if(EnableAsianSession  && InHourRange(h, AsianStartHour,  AsianEndHour))  allowed = true;
   if(EnableLondonSession && InHourRange(h, LondonStartHour, LondonEndHour)) allowed = true;
   if(EnableUSSession     && InHourRange(h, USStartHour,     USEndHour))     allowed = true;
   return allowed;
  }

bool IsPastWeekendCloseHour()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= WeekendCloseHour);
  }

void CheckWeekendClose()
  {
   if(!IsPastWeekendCloseHour()) return;
   CloseAllMyPositionsAndOrders();
  }

//+------------------------------------------------------------------+
//| Pending order management                                         |
//+------------------------------------------------------------------+
void CleanupExpiredPendingOrders()
  {
   datetime now = TimeCurrent();
   if(g_lastCleanupRetryTime > 0 && (now - g_lastCleanupRetryTime) < CLOSE_RETRY_COOLDOWN_SEC)
      return;

   bool anyFailed = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      ENUM_ORDER_TYPE_TIME timeType = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
      datetime             expr     = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);

      bool expired = false;
      if(timeType == ORDER_TIME_SPECIFIED && expr > 0)
        {
         // Strict '<' agar tidak bentrok dengan penghapusan otomatis server di detik tepat expiry
         if(expr < now) expired = true;
        }
      else
        {
         // Untuk order GTC (fallback), cek kedaluwarsa berbasis jumlah bar
         string layerTag; double rVal;
         if(ParseComment(OrderGetString(ORDER_COMMENT), layerTag, rVal))
           {
            int layerIdx = TagToIndex(layerTag);
            if(layerIdx > 0)
              {
               datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
               int      barsOpen  = iBarShift(_Symbol, _Period, setupTime, false);
               if(barsOpen >= g_layers[layerIdx].limitExpireBars)
                  expired = true;
              }
           }
        }

      if(expired)
        {
         if(!trade.OrderDelete(ticket))
           {
            anyFailed = true;
            Print("Warning: Gagal hapus pending expired #", ticket, " retcode=", trade.ResultRetcode());
           }
        }
     }

   g_hasPendingOrderCleanup = anyFailed;
   g_lastCleanupRetryTime   = anyFailed ? now : 0;
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
         if(trade.OrderDelete(ticket))
            Print(_Symbol, " ", layerTag, " - Pending lama dibatalkan.");
         else
            Print("Warning ", layerTag, ": Gagal batal pending #", ticket, " retcode=", trade.ResultRetcode());
        }
     }
  }

void SetAutoFillingType()
  {
   ENUM_SYMBOL_TRADE_EXECUTION execMode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if(execMode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
     {
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
      return;
     }
   if((filling & SYMBOL_FILLING_FOK) != 0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                         trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| Custom fitness untuk Strategy Tester Optimization                |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < TesterMinTrades || trades <= 0.0) return 0.0;

   double netProfit = TesterStatistics(STAT_PROFIT);
   if(netProfit <= 0.0) return 0.0;

   double winRate = (TesterStatistics(STAT_PROFIT_TRADES) / trades) * 100.0;

   if(TesterFitnessMode == TESTER_WINRATE_FILTERED)
      return winRate;

   if(TesterFitnessMode == TESTER_PROFIT_FACTOR)
      return TesterStatistics(STAT_PROFIT_FACTOR);

   double recovery = TesterStatistics(STAT_RECOVERY_FACTOR);
   if(recovery <= 0.0) return 0.0;
   return (winRate / 100.0) * recovery * MathLog(trades + 1.0);
  }
//+------------------------------------------------------------------+
