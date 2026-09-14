//+------------------------------------------------------------------+
//| MomenCandleStreak_V6_0.mq5                                       |
//| V6.0: Bug fixes + 6 fitur baru utk max WR + konsisten compound  |
//| Changelog dari V5.3:                                              |
//|  - FIX: Spread filter sekarang dipanggil (sebelumnya dead code)  |
//|  - FIX: OnTester pakai composite fitness (bukan WR murni)        |
//|  - NEW: Multi-Timeframe Confirmation (MTF Filter)                |
//|  - NEW: Candle Body Ratio Filter                                  |
//|  - NEW: Break-Even Stop (BEP)                                    |
//|  - NEW: Anti-Revenge Cooldown                                     |
//|  - NEW: Dynamic RRR (ATR-Adaptive)                               |
//|  - NEW: Equity Curve Trading (Meta-Filter)                       |
//|  - OPTIMIZED: Default parameters untuk XAUUSD H4                |
//+------------------------------------------------------------------+
#property copyright "Custom EA - V6.0 Max WR + Consistent Compound"
#property version   "6.00"
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
input int    L1_StreakCount          = 2;        // KEPT at 2
input ENUM_STREAK_CALC_MODE L1_StreakCalcMode = STREAK_CALC_HIGH_LOW; // CHANGED from OC to HL
input int    L1_MaxConsecutiveTrades = 3;        // CHANGED from 7 to 3
input bool   L1_UseStaticLot         = false;    // CHANGED to dynamic lot
input double L1_StaticLotSize        = 0.03;
input double L1_RiskPercentPerTrade  = 1.0;
input bool   L1_UseStaticSLPoint     = false;
input double L1_StaticSLPoints       = 2500;
input bool   L1_UseStreakSizeFilter  = true;     // CHANGED to true
input double L1_MinStreakPoints      = 5000;     // CHANGED: $5.00 min
input double L1_MaxStreakPoints      = 50000;    // CHANGED: $50.00 max
input double L1_RRR                  = 1.0;      // Base RRR (Dynamic RRR adjusts)
input bool   L1_UseTrailingStop      = true;
input double L1_TrailStepPercent     = 50.0;     // CHANGED from 80 to 50
input bool   L1_UseMaxHoldBars       = true;     // CHANGED to true
input int    L1_MaxHoldBars          = 12;       // ~2 days on H4

//================== INPUT: GROUP 2 - LAYER 2 (PENDING RETRACE) ==================
input group "=== 2. Layer 2 - Pending Limit Retrace ==="
input bool   L2_UseLayer             = false;
input int    L2_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L2_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L2_RetracePercent       = 40.0; // skala 0-100
input int    L2_MaxConsecutiveTrades = 4;
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
input double L2_TrailStepPercent     = 10.0;
input int    L2_LimitExpireBars      = 1;
input bool   L2_UseMaxHoldBars       = false;
input int    L2_MaxHoldBars          = 10;

//================== INPUT: GROUP 3 - LAYER 3 (PENDING RETRACE) ==================
input group "=== 3. Layer 3 - Pending Limit Retrace ==="
input bool   L3_UseLayer             = false;
input int    L3_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L3_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L3_RetracePercent       = 70.0; // skala 0-100
input int    L3_MaxConsecutiveTrades = 4;
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
input double L3_TrailStepPercent     = 10.0;
input int    L3_LimitExpireBars      = 1;
input bool   L3_UseMaxHoldBars       = false;
input int    L3_MaxHoldBars          = 10;

//================== INPUT: GROUP 4 - WEEKEND CLOSE ==================
input group "=== 4. Weekend Close ==="
input bool UseWeekendClose               = true;
input int  WeekendCloseHour              = 20;
input bool BlockNewTradeAfterWeekendClose = true;

//================== INPUT: GROUP 5 - SESSION & DAY FILTER ==================
input group "=== 5. Session & Day Filter ==="
input bool UseSessionFilter    = true;    // CHANGED to true
input bool EnableAsianSession  = false;   // CHANGED to false (noise filter)
input int  AsianStartHour      = 1;
input int  AsianEndHour        = 7;
input bool EnableLondonSession = true;
input int  LondonStartHour     = 7;
input int  LondonEndHour       = 16;
input bool EnableUSSession     = true;
input int  USStartHour         = 14;
input int  USEndHour           = 23;

input bool UseDayFilter  = true;
input bool TradeMonday   = true;
input bool TradeTuesday  = true;
input bool TradeWednesday= true;
input bool TradeThursday = true;
input bool TradeFriday   = true;

//================== INPUT: GROUP 6a/6b/6c - TREND FILTER ==================
input group "=== 6a. Trend Filter (ADX) ==="
input bool   UseADXFilter = false;
input int    ADX_Period   = 14;
input double ADX_MinLevel = 25.0;

input group "=== 6b. Trend Filter (MA Alignment) ==="
input bool          UseMAFilter   = false;
input int           MA_FastPeriod = 20;
input int           MA_SlowPeriod = 50;
input ENUM_MA_METHOD MA_Method    = MODE_EMA;

input group "=== 6c. Trend Filter (Choppiness Index) ==="
input bool   UseChoppinessFilter = true;   // CHANGED to true
input int    Choppiness_Period   = 14;
input double Choppiness_MaxLevel = 61.8;

//================== INPUT: GROUP 7 - SYSTEM FILTER ==================
input group "=== 7. System Filter ==="
input bool   UseSpreadFilter      = true;
input double MaxSpreadPoints      = 400;   // CHANGED from 500
input int    MaxTotalOpenPositions = 2;     // CHANGED from 3
input double SL_BufferPoints      = 200;   // CHANGED from 0 ($0.20 buffer)
input int    MagicNumber          = 777060; // CHANGED for V6

//================== INPUT: GROUP 8 - MTF Confirmation ==================
input group "=== 8. Multi-Timeframe Confirmation ==="
input bool            UseMTF_Filter      = true;
input ENUM_TIMEFRAMES MTF_Timeframe      = PERIOD_D1;
input int             MTF_CandleLookback = 1;  // 1 = completed candle, 0 = forming

//================== INPUT: GROUP 9 - Candle Quality Filter ==================
input group "=== 9. Candle Quality Filter ==="
input bool   UseCandleBodyFilter  = true;
input double MinCandleBodyPercent = 40.0;  // Minimum body/range ratio per candle (%)

//================== INPUT: GROUP 10 - Break-Even Stop ==================
input group "=== 10. Break-Even Stop ==="
input bool   UseBEP       = true;
input double BEP_TriggerR = 1.0;   // Activate BEP when profit >= 1R
input double BEP_LockR    = 0.05;  // Lock SL at entry + 0.05R (covers spread)

//================== INPUT: GROUP 11 - Anti-Revenge Cooldown ==================
input group "=== 11. Anti-Revenge Cooldown ==="
input bool UseCooldown         = true;
input int  CooldownAfterLosses = 3;    // After N consecutive losses
input int  CooldownBars        = 3;    // Skip next N bars (~12h on H4)

//================== INPUT: GROUP 12 - Dynamic RRR ==================
input group "=== 12. Dynamic RRR (ATR-Adaptive) ==="
input bool   UseDynamicRRR      = true;
input int    DynRRR_ATR_Period  = 14;
input int    DynRRR_MA_Period   = 50;    // MA length for average ATR
input double DynRRR_LowThresh   = 0.8;   // ATR ratio below this = low vol
input double DynRRR_HighThresh  = 1.2;   // ATR ratio above this = high vol
input double DynRRR_LowVolMult  = 0.7;   // RRR multiplier at low vol (TP closer)
input double DynRRR_HighVolMult = 1.3;   // RRR multiplier at high vol (TP farther)

//================== INPUT: GROUP 13 - Equity Curve Trading ==================
input group "=== 13. Equity Curve Trading ==="
input bool UseEquityCurveFilter  = true;
input int  EquityCurve_MAPeriod  = 30;    // MA period of equity curve (in bars)
input bool EquityCurve_SkipMode  = false; // true=skip trades, false=halve lot

//================== INPUT: GROUP 14 - CUSTOM FITNESS ==================
input group "=== 14. Custom Fitness - Optimizer (Custom Max) ==="
input double Fitness_W_RecoveryFactor = 0.3;
input double Fitness_W_EquityR2       = 0.5;   // HIGHEST weight for smooth equity
input double Fitness_W_WinRate        = 0.2;
input int    Fitness_MinTrades        = 50;    // CHANGED from 100
input double Fitness_MaxDD_Percent    = 20.0;  // CHANGED from 30 (stricter)
input double Fitness_RF_NormCap       = 5.0;

//================== STRUCT ==================
struct SLayerParams
  {
   bool                  enabled;
   string                tag;
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
   double                trailStepPercent;
   int                   limitExpireBars;
   bool                  useMaxHold;
   int                   maxHoldBars;
  };

SLayerParams g_layers[3];
int          g_consecutive[3];   // 0=L1,1=L2,2=L3
int          g_lastSignal[3];    
datetime     g_lastBarTime = 0;
double       g_equityCurve[];    

int          g_adxHandle = INVALID_HANDLE;
int          g_maFastHandle = INVALID_HANDLE;
int          g_maSlowHandle = INVALID_HANDLE;
int          g_atrHandle = INVALID_HANDLE; // dipakai Choppiness Index

int          g_atrDynHandle = INVALID_HANDLE;  // for Dynamic RRR (ATR period=DynRRR_ATR_Period)

int          g_globalLossStreak = 0;
datetime     g_cooldownEndTime  = 0;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_consecutive[0]=0; g_consecutive[1]=0; g_consecutive[2]=0;
   g_lastSignal[0]=0; g_lastSignal[1]=0; g_lastSignal[2]=0;
   g_lastBarTime = 0;
   g_globalLossStreak = 0;
   g_cooldownEndTime = 0;
   ArrayResize(g_equityCurve, 0);

   g_layers[0].enabled         = L1_UseLayer;
   g_layers[0].tag              = "L1";
   g_layers[0].streakCount      = L1_StreakCount;
   g_layers[0].calcMode         = L1_StreakCalcMode;
   g_layers[0].retracePercent   = 0;
   g_layers[0].maxConsecutive   = L1_MaxConsecutiveTrades;
   g_layers[0].useStaticLot     = L1_UseStaticLot;
   g_layers[0].staticLot        = L1_StaticLotSize;
   g_layers[0].riskPercent      = L1_RiskPercentPerTrade;
   g_layers[0].useStaticSL      = L1_UseStaticSLPoint;
   g_layers[0].staticSLPoints   = L1_StaticSLPoints;
   g_layers[0].useStreakFilter  = L1_UseStreakSizeFilter && !L1_UseStaticSLPoint;
   g_layers[0].minStreakPoints  = L1_MinStreakPoints;
   g_layers[0].maxStreakPoints  = L1_MaxStreakPoints;
   g_layers[0].rrr               = L1_RRR;
   g_layers[0].useTrailing      = L1_UseTrailingStop;
   g_layers[0].trailStepPercent = L1_TrailStepPercent;
   g_layers[0].limitExpireBars  = 0;
   g_layers[0].useMaxHold       = L1_UseMaxHoldBars;
   g_layers[0].maxHoldBars      = L1_MaxHoldBars;
   if(L1_UseStreakSizeFilter && L1_UseStaticSLPoint)
      Print("WARNING L1: UseStreakSizeFilter dinonaktifkan otomatis karena UseStaticSLPoint=true (konflik).");

   g_layers[1].enabled         = L2_UseLayer;
   g_layers[1].tag              = "L2";
   g_layers[1].streakCount      = L2_StreakCount;
   g_layers[1].calcMode         = L2_StreakCalcMode;
   g_layers[1].retracePercent   = L2_RetracePercent;
   g_layers[1].maxConsecutive   = L2_MaxConsecutiveTrades;
   g_layers[1].useStaticLot     = L2_UseStaticLot;
   g_layers[1].staticLot        = L2_StaticLotSize;
   g_layers[1].riskPercent      = L2_RiskPercentPerTrade;
   g_layers[1].useStaticSL      = L2_UseStaticSLPoint;
   g_layers[1].staticSLPoints   = L2_StaticSLPoints;
   g_layers[1].useStreakFilter  = L2_UseStreakSizeFilter && !L2_UseStaticSLPoint;
   g_layers[1].minStreakPoints  = L2_MinStreakPoints;
   g_layers[1].maxStreakPoints  = L2_MaxStreakPoints;
   g_layers[1].rrr               = L2_RRR;
   g_layers[1].useTrailing      = L2_UseTrailingStop;
   g_layers[1].trailStepPercent = L2_TrailStepPercent;
   g_layers[1].limitExpireBars  = L2_LimitExpireBars;
   g_layers[1].useMaxHold       = L2_UseMaxHoldBars;
   g_layers[1].maxHoldBars      = L2_MaxHoldBars;
   if(L2_UseStreakSizeFilter && L2_UseStaticSLPoint)
      Print("WARNING L2: UseStreakSizeFilter dinonaktifkan otomatis karena UseStaticSLPoint=true (konflik).");

   g_layers[2].enabled         = L3_UseLayer;
   g_layers[2].tag              = "L3";
   g_layers[2].streakCount      = L3_StreakCount;
   g_layers[2].calcMode         = L3_StreakCalcMode;
   g_layers[2].retracePercent   = L3_RetracePercent;
   g_layers[2].maxConsecutive   = L3_MaxConsecutiveTrades;
   g_layers[2].useStaticLot     = L3_UseStaticLot;
   g_layers[2].staticLot        = L3_StaticLotSize;
   g_layers[2].riskPercent      = L3_RiskPercentPerTrade;
   g_layers[2].useStaticSL      = L3_UseStaticSLPoint;
   g_layers[2].staticSLPoints   = L3_StaticSLPoints;
   g_layers[2].useStreakFilter  = L3_UseStreakSizeFilter && !L3_UseStaticSLPoint;
   g_layers[2].minStreakPoints  = L3_MinStreakPoints;
   g_layers[2].maxStreakPoints  = L3_MaxStreakPoints;
   g_layers[2].rrr               = L3_RRR;
   g_layers[2].useTrailing      = L3_UseTrailingStop;
   g_layers[2].trailStepPercent = L3_TrailStepPercent;
   g_layers[2].limitExpireBars  = L3_LimitExpireBars;
   g_layers[2].useMaxHold       = L3_UseMaxHoldBars;
   g_layers[2].maxHoldBars      = L3_MaxHoldBars;
   if(L3_UseStreakSizeFilter && L3_UseStaticSLPoint)
      Print("WARNING L3: UseStreakSizeFilter dinonaktifkan otomatis karena UseStaticSLPoint=true (konflik).");

   trade.SetExpertMagicNumber(MagicNumber);

   if(UseADXFilter)
     {
      g_adxHandle = iADX(_Symbol, _Period, ADX_Period);
      if(g_adxHandle == INVALID_HANDLE)
        {
         Print("ERROR: Gagal buat handle ADX. EA berhenti.");
         return(INIT_FAILED);
        }
     }

   if(UseMAFilter)
     {
      g_maFastHandle = iMA(_Symbol, _Period, MA_FastPeriod, 0, MA_Method, PRICE_CLOSE);
      g_maSlowHandle = iMA(_Symbol, _Period, MA_SlowPeriod, 0, MA_Method, PRICE_CLOSE);
      if(g_maFastHandle==INVALID_HANDLE || g_maSlowHandle==INVALID_HANDLE)
        {
         Print("ERROR: Gagal buat handle MA. EA berhenti.");
         return(INIT_FAILED);
        }
     }

   if(UseChoppinessFilter)
     {
      g_atrHandle = iATR(_Symbol, _Period, 1);
      if(g_atrHandle == INVALID_HANDLE)
        {
         Print("ERROR: Gagal buat handle ATR (Choppiness). EA berhenti.");
         return(INIT_FAILED);
        }
     }

   if(UseDynamicRRR)
     {
      g_atrDynHandle = iATR(_Symbol, _Period, DynRRR_ATR_Period);
      if(g_atrDynHandle == INVALID_HANDLE)
        {
         Print("ERROR: Failed to create ATR handle for Dynamic RRR.");
         return(INIT_FAILED);
        }
     }

   Print("EA V6.0 Initialized. Symbol=", _Symbol, " Period=", EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_adxHandle    != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_maFastHandle != INVALID_HANDLE) IndicatorRelease(g_maFastHandle);
   if(g_maSlowHandle != INVALID_HANDLE) IndicatorRelease(g_maSlowHandle);
   if(g_atrHandle    != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_atrDynHandle != INVALID_HANDLE) IndicatorRelease(g_atrDynHandle);
  }

//+------------------------------------------------------------------+
//| Trend Filter (ADX)                                               |
//+------------------------------------------------------------------+
bool IsTrendingByADX()
  {
   if(!UseADXFilter) return true;
   if(g_adxHandle == INVALID_HANDLE) return true;

   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(g_adxHandle, 0, 1, 1, adxBuf) <= 0) return true;

   double adxValue = adxBuf[0];
   return (adxValue >= ADX_MinLevel);
  }

//+------------------------------------------------------------------+
//| Trend Filter (MA Alignment)                                      |
//+------------------------------------------------------------------+
bool IsTrendAlignedByMA(bool isBuy)
  {
   if(!UseMAFilter) return true;
   if(g_maFastHandle==INVALID_HANDLE || g_maSlowHandle==INVALID_HANDLE) return true;

   double fastBuf[], slowBuf[];
   ArraySetAsSeries(fastBuf,true);
   ArraySetAsSeries(slowBuf,true);
   if(CopyBuffer(g_maFastHandle,0,1,1,fastBuf)<=0) return true;
   if(CopyBuffer(g_maSlowHandle,0,1,1,slowBuf)<=0) return true;

   bool uptrend = fastBuf[0] > slowBuf[0];
   return isBuy ? uptrend : !uptrend;
  }

//+------------------------------------------------------------------+
//| Trend Filter (Choppiness Index)                                   |
//+------------------------------------------------------------------+
double ComputeChoppiness()
  {
   if(g_atrHandle==INVALID_HANDLE) return -1;

   double trBuf[];
   ArraySetAsSeries(trBuf,true);
   if(CopyBuffer(g_atrHandle,0,1,Choppiness_Period,trBuf) <= 0) return -1;

   double sumTR=0;
   for(int i=0;i<Choppiness_Period;i++) sumTR += trBuf[i];

   int hhIdx = iHighest(_Symbol,_Period,MODE_HIGH,Choppiness_Period,1);
   int llIdx = iLowest(_Symbol,_Period,MODE_LOW,Choppiness_Period,1);
   if(hhIdx<0 || llIdx<0) return -1;

   double hh = iHigh(_Symbol,_Period,hhIdx);
   double ll = iLow(_Symbol,_Period,llIdx);
   double range = hh-ll;
   if(range<=0) return 100.0;

   double ci = 100.0 * MathLog10(sumTR/range) / MathLog10((double)Choppiness_Period);
   return ci;
  }

bool IsTrendingByChoppiness()
  {
   if(!UseChoppinessFilter) return true;
   double ci = ComputeChoppiness();
   if(ci < 0) return true;
   return (ci <= Choppiness_MaxLevel);
  }

//+------------------------------------------------------------------+
//| NEW FILTER FUNCTIONS                                             |
//+------------------------------------------------------------------+
bool IsMTFAligned(bool isBuy)
  {
   if(!UseMTF_Filter) return true;
   double closeHTF = iClose(_Symbol, MTF_Timeframe, MTF_CandleLookback);
   double openHTF  = iOpen(_Symbol, MTF_Timeframe, MTF_CandleLookback);
   if(closeHTF <= 0 || openHTF <= 0) return true;
   bool htfBullish = (closeHTF > openHTF);
   return isBuy ? htfBullish : !htfBullish;
  }

bool IsCandleBodyValid(int streakCount)
  {
   if(!UseCandleBodyFilter) return true;
   double minRatio = MinCandleBodyPercent / 100.0;
   for(int i = 1; i <= streakCount; i++)
     {
      double o = iOpen(_Symbol, _Period, i);
      double c = iClose(_Symbol, _Period, i);
      double h = iHigh(_Symbol, _Period, i);
      double l = iLow(_Symbol, _Period, i);
      double range = h - l;
      if(range <= 0) return false;
      double body = MathAbs(c - o);
      if((body / range) < minRatio) return false;
     }
   return true;
  }

bool IsCooldownActive()
  {
   if(!UseCooldown) return false;
   return (TimeCurrent() < g_cooldownEndTime);
  }

bool IsEquityCurveHealthy()
  {
   if(!UseEquityCurveFilter) return true;
   int n = ArraySize(g_equityCurve);
   if(n < EquityCurve_MAPeriod + 1) return true;
   double sum = 0;
   for(int i = n - EquityCurve_MAPeriod; i < n; i++)
      sum += g_equityCurve[i];
   double equityMA = sum / EquityCurve_MAPeriod;
   return (g_equityCurve[n-1] >= equityMA);
  }

double GetEquityLotMultiplier()
  {
   if(!UseEquityCurveFilter || EquityCurve_SkipMode) return 1.0;
   if(IsEquityCurveHealthy()) return 1.0;
   return 0.5;
  }

double GetDynamicRRR(double baseRRR)
  {
   if(!UseDynamicRRR) return baseRRR;
   if(g_atrDynHandle == INVALID_HANDLE) return baseRRR;
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int copied = CopyBuffer(g_atrDynHandle, 0, 1, DynRRR_MA_Period, atrBuf);
   if(copied < DynRRR_MA_Period) return baseRRR;
   double currentATR = atrBuf[0];
   double sumATR = 0;
   for(int i = 0; i < DynRRR_MA_Period; i++) sumATR += atrBuf[i];
   double avgATR = sumATR / DynRRR_MA_Period;
   if(avgATR <= 0) return baseRRR;
   double ratio = currentATR / avgATR;
   double clampedRatio = MathMax(DynRRR_LowThresh, MathMin(DynRRR_HighThresh, ratio));
   double denom = DynRRR_HighThresh - DynRRR_LowThresh;
   if(denom <= 0) return baseRRR;
   double t = (clampedRatio - DynRRR_LowThresh) / denom;
   double multiplier = DynRRR_LowVolMult + t * (DynRRR_HighVolMult - DynRRR_LowVolMult);
   return baseRRR * multiplier;
  }

//+------------------------------------------------------------------+
//| Comment helpers: format "TAG|R"                                  |
//+------------------------------------------------------------------+
bool ParseComment(string cmt, string &layerTag, double &R)
  {
   string parts[];
   int n = StringSplit(cmt, '|', parts);
   if(n<2) return false;
   layerTag = parts[0];
   R        = StringToDouble(parts[1]);
   return true;
  }

int TagToIndex(string tag)
  {
   if(tag=="L1") return 0;
   if(tag=="L2") return 1;
   if(tag=="L3") return 2;
   return -1;
  }

//+------------------------------------------------------------------+
//| Streak evaluation                                                |
//+------------------------------------------------------------------+
int EvaluateStreakGeneric(int count)
  {
   bool allGreen=true, allRed=true;
   for(int i=1;i<=count;i++)
     {
      double o=iOpen(_Symbol,_Period,i), c=iClose(_Symbol,_Period,i);
      if(o<=0 || c<=0) return 0;
      if(c<=o) allGreen=false;
      if(c>=o) allRed=false;
     }
   if(allGreen) return 1;
   if(allRed)   return -1;
   return 0;
  }

void GetStreakData(int count, double &openFirst, double &closeLast, double &highMax, double &lowMin)
  {
   openFirst = iOpen(_Symbol,_Period,count);
   closeLast = iClose(_Symbol,_Period,1);
   highMax   = iHigh(_Symbol,_Period,1);
   lowMin    = iLow(_Symbol,_Period,1);
   for(int i=2;i<=count;i++)
     {
      double h=iHigh(_Symbol,_Period,i); if(h>highMax) highMax=h;
      double l=iLow(_Symbol,_Period,i);  if(l<lowMin)  lowMin=l;
     }
  }

double GetStreakRange(ENUM_STREAK_CALC_MODE mode, double openFirst, double closeLast, double highMax, double lowMin)
  {
   if(mode==STREAK_CALC_OPEN_CLOSE) return MathAbs(closeLast-openFirst);
   return (highMax-lowMin);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop();
   ManageBEP();           
   ManageMaxHoldBars();
   if(UseWeekendClose) CheckWeekendClose();

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar <= 0 || curBar == g_lastBarTime) return;
   g_lastBarTime = curBar;

   int n = ArraySize(g_equityCurve);
   ArrayResize(g_equityCurve, n+1);
   g_equityCurve[n] = AccountInfoDouble(ACCOUNT_EQUITY);

   CleanupExpiredPendingOrders();

   if(CountMyPositions() >= MaxTotalOpenPositions) return;
   if(UseDayFilter && !IsDayAllowed()) return;
   if(UseSessionFilter && !IsSessionAllowed()) return;
   if(UseSpreadFilter && IsSpreadHigh()) return;              
   if(UseADXFilter && !IsTrendingByADX()) return;
   if(UseChoppinessFilter && !IsTrendingByChoppiness()) return;
   if(UseWeekendClose && BlockNewTradeAfterWeekendClose && IsPastWeekendCloseHour()) return;
   if(UseEquityCurveFilter && EquityCurve_SkipMode && !IsEquityCurveHealthy()) return;  
   if(IsCooldownActive()) return;                              

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

   int signal = EvaluateStreakGeneric(cfg.streakCount);
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

   if(layerIdx > 0) CancelPendingForLayer(cfg.tag);

   SetAutoFillingType();
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   if(point <= 0 || ask <= 0 || bid <= 0) return;

   double openFirst, closeLast, highMax, lowMin;
   GetStreakData(cfg.streakCount, openFirst, closeLast, highMax, lowMin);

   bool isBuy = (signal == 1);

   // --- NEW: MTF Confirmation (must be before MA filter since both are directional) ---
   if(!IsMTFAligned(isBuy)) return;

   // --- Existing: MA Alignment filter ---
   if(!IsTrendAlignedByMA(isBuy)) return;

   // --- NEW: Candle Body Quality filter ---
   if(!IsCandleBodyValid(cfg.streakCount)) return;

   // --- Existing: Streak Size filter ---
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
      double retraceFrac = cfg.retracePercent / 100.0;
      if(isBuy)
        {
         double anchorHigh = (cfg.calcMode == STREAK_CALC_OPEN_CLOSE) ? closeLast : highMax;
         entry = anchorHigh - range * retraceFrac;
        }
      else
        {
         double anchorLow = (cfg.calcMode == STREAK_CALC_OPEN_CLOSE) ? closeLast : lowMin;
         entry = anchorLow + range * retraceFrac;
        }
     }

   // --- Stop Loss ---
   double slPrice;
   if(cfg.useStaticSL)
     {
      slPrice = isBuy ? (entry - cfg.staticSLPoints * point) : (entry + cfg.staticSLPoints * point);
     }
   else
     {
      double anchor = (cfg.calcMode == STREAK_CALC_OPEN_CLOSE) ? openFirst : (isBuy ? lowMin : highMax);
      slPrice = isBuy ? (anchor - SL_BufferPoints * point) : (anchor + SL_BufferPoints * point);
     }

   double R = isBuy ? (entry - slPrice) : (slPrice - entry);
   if(R <= 0) return;

   // --- NEW: Dynamic RRR ---
   double effectiveRRR = GetDynamicRRR(cfg.rrr);

   double tp = isBuy ? (entry + R * effectiveRRR) : (entry - R * effectiveRRR);

   // --- Lot calculation with equity curve multiplier ---
   double eqMult = GetEquityLotMultiplier();
   double lot;
   if(cfg.useStaticLot)
      lot = NormalizeLot(cfg.staticLot * eqMult);
   else
      lot = CalculateDynamicLot(R / point, cfg.riskPercent * eqMult, cfg.staticLot);

   string cmt = cfg.tag + "|" + DoubleToString(R, _Digits);

   bool ok = false;
   if(layerIdx == 0)
     {
      ok = isBuy ? trade.Buy(lot, _Symbol, NormalizeDouble(entry, _Digits), NormalizeDouble(slPrice, _Digits), NormalizeDouble(tp, _Digits), cmt)
                 : trade.Sell(lot, _Symbol, NormalizeDouble(entry, _Digits), NormalizeDouble(slPrice, _Digits), NormalizeDouble(tp, _Digits), cmt);
      if(!ok) Print("Error ", cfg.tag, " [", _Symbol, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }
   else
     {
      if(isBuy  && entry > (ask - stopLevel)) return;
      if(!isBuy && entry < (bid + stopLevel)) return;
      datetime expr = barTime + (cfg.limitExpireBars * PeriodSeconds(_Period));
      ok = isBuy ? trade.BuyLimit(lot, NormalizeDouble(entry, _Digits), _Symbol, NormalizeDouble(slPrice, _Digits), NormalizeDouble(tp, _Digits), ORDER_TIME_SPECIFIED, expr, cmt)
                 : trade.SellLimit(lot, NormalizeDouble(entry, _Digits), _Symbol, NormalizeDouble(slPrice, _Digits), NormalizeDouble(tp, _Digits), ORDER_TIME_SPECIFIED, expr, cmt);
      if(!ok) Print("Error ", cfg.tag, " [", _Symbol, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(dealEntry == DEAL_ENTRY_IN)
     {
      string cmt = HistoryDealGetString(trans.deal, DEAL_COMMENT);
      string layerTag; double rVal;
      if(!ParseComment(cmt, layerTag, rVal)) return;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx < 0) return;
      g_consecutive[layerIdx]++;
     }
   else if(dealEntry == DEAL_ENTRY_OUT)
     {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                    + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                    + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

      if(profit < 0)
        {
         g_globalLossStreak++;
         if(UseCooldown && g_globalLossStreak >= CooldownAfterLosses)
           {
            g_cooldownEndTime = TimeCurrent() + CooldownBars * PeriodSeconds(_Period);
            g_globalLossStreak = 0;
            Print("Cooldown activated for ", CooldownBars, " bars after ", CooldownAfterLosses, " consecutive losses.");
           }
        }
      else if(profit > 0)
        {
         g_globalLossStreak = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage BEP                                                       |
//+------------------------------------------------------------------+
void ManageBEP()
  {
   if(!UseBEP) return;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      string layerTag; double R;
      if(!ParseComment(cmt, layerTag, R)) continue;
      if(R <= 0) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(type == POSITION_TYPE_BUY)
        {
         double profitR = (bid - entry) / R;
         double bepSL   = entry + BEP_LockR * R;
         if(profitR >= BEP_TriggerR && curSL < bepSL)
            trade.PositionModify(ticket, NormalizeDouble(bepSL, _Digits), curTP);
        }
      else
        {
         double profitR = (entry - ask) / R;
         double bepSL   = entry - BEP_LockR * R;
         if(profitR >= BEP_TriggerR && (curSL == 0 || curSL > bepSL))
            trade.PositionModify(ticket, NormalizeDouble(bepSL, _Digits), curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Lot management                                                   |
//+------------------------------------------------------------------+
int CountMyPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      count++;
     }
   return count;
  }

double NormalizeLot(double targetLot)
  {
   double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(stepLot>0) targetLot = MathFloor(targetLot/stepLot)*stepLot;
   if(targetLot<minLot) targetLot=minLot;
   if(targetLot>maxLot) targetLot=maxLot;
   return NormalizeDouble(targetLot,2);
  }

double CalculateDynamicLot(double slPoints, double riskPercent, double fallbackLot)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE)*(riskPercent/100.0);
   double tickValue  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(tickValue<=0 || tickSize<=0 || point<=0 || slPoints<=0) return NormalizeLot(fallbackLot);
   double valuePerPoint = tickValue*(point/tickSize);
   double rawLot = riskAmount/(slPoints*valuePerPoint);
   return NormalizeLot(rawLot);
  }

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      string layerTag; double R;
      if(!ParseComment(cmt, layerTag, R)) continue;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx<0) continue;

      SLayerParams cfg = g_layers[layerIdx];
      if(!cfg.useTrailing || R<=0) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      double stepFrac = cfg.trailStepPercent/100.0;
      double profitR = (type==POSITION_TYPE_BUY) ? ((bid-entry)/R) : ((entry-ask)/R);
      double stepsPassed = MathFloor(profitR/stepFrac);
      if(stepsPassed<1) continue;
      double lockedR = -1.0 + stepsPassed*stepFrac;

      if(type==POSITION_TYPE_BUY)
        {
         double newSL = entry + lockedR*R;
         if(newSL>curSL) trade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),curTP);
        }
      else
        {
         double newSL = entry - lockedR*R;
         if(curSL==0 || newSL<curSL) trade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| ManageMaxHoldBars                                                |
//+------------------------------------------------------------------+
void ManageMaxHoldBars()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      string layerTag; double R;
      if(!ParseComment(cmt, layerTag, R)) continue;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx<0) continue;

      SLayerParams cfg = g_layers[layerIdx];
      if(!cfg.useMaxHold) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsOpen = iBarShift(_Symbol, _Period, openTime, false);
      if(barsOpen >= cfg.maxHoldBars)
         trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Filter Handlers                                                  |
//+------------------------------------------------------------------+
bool IsSpreadHigh()
  {
   double spreadPoints = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   return (spreadPoints > MaxSpreadPoints);
  }

bool IsDayAllowed()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
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
   if(startH<=endH) return (h>=startH && h<endH);
   return (h>=startH || h<endH);
  }

bool IsSessionAllowed()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int h = dt.hour;
   bool allowed=false;
   if(EnableAsianSession  && InHourRange(h,AsianStartHour,AsianEndHour))   allowed=true;
   if(EnableLondonSession && InHourRange(h,LondonStartHour,LondonEndHour)) allowed=true;
   if(EnableUSSession     && InHourRange(h,USStartHour,USEndHour))         allowed=true;
   return allowed;
  }

bool IsPastWeekendCloseHour()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return (dt.day_of_week==5 && dt.hour>=WeekendCloseHour);
  }

void CheckWeekendClose()
  {
   if(!IsPastWeekendCloseHour()) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      trade.PositionClose(ticket);
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Pending order management                                         |
//+------------------------------------------------------------------+
void CleanupExpiredPendingOrders()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      datetime expr = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(expr>0 && expr<=TimeCurrent())
         trade.OrderDelete(ticket);
     }
  }

bool HasActivePendingForLayer(string layerTag)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, layerTag+"|")==0) return true;
     }
   return false;
  }

void CancelPendingForLayer(string layerTag)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, layerTag+"|")==0)
        {
         trade.OrderDelete(ticket);
         Print(_Symbol," ",layerTag," - Pending lama dibatalkan, diganti sesuai streak terbaru.");
        }
     }
  }

void SetAutoFillingType()
  {
   uint filling = (uint)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)!=0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC)!=0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                        trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| R^2 regresi linear kurva equity                                  |
//+------------------------------------------------------------------+
double ComputeEquityR2()
  {
   int n = ArraySize(g_equityCurve);
   if(n<3) return 0.0;

   double sumX=0, sumY=0, sumXY=0, sumXX=0;
   for(int i=0;i<n;i++)
     {
      double x=(double)i, y=g_equityCurve[i];
      sumX += x; sumY += y; sumXY += x*y; sumXX += x*x;
     }
   double meanX = sumX/n, meanY = sumY/n;
   double denom = (n*sumXX - sumX*sumX);
   if(MathAbs(denom) < 1e-10) return 0.0;

   double b = (n*sumXY - sumX*sumY) / denom;
   double a = meanY - b*meanX;

   if(b <= 0) return 0.0;

   double ssTot=0, ssRes=0;
   for(int i=0;i<n;i++)
     {
      double x=(double)i, y=g_equityCurve[i];
      double pred = a + b*x;
      ssRes += (y-pred)*(y-pred);
      ssTot += (y-meanY)*(y-meanY);
     }
   if(ssTot<=0) return 0.0;

   double r2 = 1.0 - (ssRes/ssTot);
   if(r2<0) r2=0;
   if(r2>1) r2=1;
   return r2;
  }

//+------------------------------------------------------------------+
//| Custom Fitness                                                   |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades <= 0) return 0.0;

   double ddPercent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(ddPercent > Fitness_MaxDD_Percent) return 0.0;

   double netProfit    = TesterStatistics(STAT_PROFIT);
   double profitTrades = TesterStatistics(STAT_PROFIT_TRADES);
   double initDeposit  = TesterStatistics(STAT_INITIAL_DEPOSIT);
   if(initDeposit <= 0) initDeposit = 1.0;

   double ddMoney = (ddPercent / 100.0) * initDeposit;
   double RF = netProfit / (ddMoney + 1.0);
   double RF_norm = MathMin(1.0, RF / Fitness_RF_NormCap);
   if(RF_norm < 0) RF_norm = 0;

   double winRate = profitTrades / trades;
   double r2 = ComputeEquityR2();
   double tradeFactor = MathMin(1.0, trades / (double)MathMax(1, Fitness_MinTrades));

   double fitness = (Fitness_W_RecoveryFactor * RF_norm
                   + Fitness_W_EquityR2 * r2
                   + Fitness_W_WinRate * winRate) * tradeFactor;

   return fitness;
  }
//+------------------------------------------------------------------+
