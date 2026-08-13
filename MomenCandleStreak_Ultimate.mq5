//+------------------------------------------------------------------+
//| MomenCandleStreak_V5_3_AutoScope_CustomFitness.mq5                |
//| Base: V5 Independent Layer. Scope symbol/TF: auto (_Symbol/      |
//| _Period), diambil dari kode TripleLayer -- BUKAN multi-symbol.   |
//| Tambahan: custom OnTester() fitness utk Fast Generic Algorithm   |
//| (Custom Max) -- gabung Recovery Factor, R^2 kurva equity,        |
//| WinRate, dgn penalti trade count & DD hard cutoff.               |
//+------------------------------------------------------------------+
#property copyright "Custom EA - V5.3 Auto Scope + Custom Fitness"
#property version   "5.30"
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
input int    L1_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L1_StreakCalcMode = STREAK_CALC_OPEN_CLOSE; // StreakCalcMode dipakai HANYA utk SL dinamis
input int    L1_MaxConsecutiveTrades = 4;
input bool   L1_UseStaticLot         = true;
input double L1_StaticLotSize        = 0.03;
input double L1_RiskPercentPerTrade  = 1.0;
input bool   L1_UseStaticSLPoint     = false;
input double L1_StaticSLPoints       = 2500;
input bool   L1_UseStreakSizeFilter  = false; 
input double L1_MinStreakPoints      = 200;
input double L1_MaxStreakPoints      = 3000;
input double L1_RRR                  = 1.0;
input bool   L1_UseTrailingStop      = false;
input double L1_TrailStepPercent     = 10.0;
input bool   L1_UseMaxHoldBars       = false;
input int    L1_MaxHoldBars          = 10;

//================== INPUT: GROUP 2 - LAYER 2 (PENDING RETRACE) ==================
input group "=== 2. Layer 2 - Pending Limit Retrace ==="
input bool   L2_UseLayer             = true;
input int    L2_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L2_StreakCalcMode = STREAK_CALC_HIGH_LOW; //StreakCalcMode
input double L2_RetracePercent       = 40.0; // RetracePercent (skala 0-100)
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
input bool   L3_UseLayer             = true;
input int    L3_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L3_StreakCalcMode = STREAK_CALC_HIGH_LOW; //StreakCalcMode
input double L3_RetracePercent       = 70.0; // RetracePercent (skala 0-100)
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
input int  WeekendCloseHour              = 22;
input bool BlockNewTradeAfterWeekendClose = true;

//================== INPUT: GROUP 5 - SESSION & DAY FILTER ==================
input group "=== 5. Session & Day Filter ==="
input bool UseSessionFilter    = false;
input bool EnableAsianSession  = true;
input int  AsianStartHour      = 0;
input int  AsianEndHour        = 7;
input bool EnableLondonSession = true;
input int  LondonStartHour     = 7;
input int  LondonEndHour       = 15;
input bool EnableUSSession     = true;
input int  USStartHour         = 14;
input int  USEndHour           = 23;

input bool UseDayFilter  = true;
input bool TradeMonday   = true;
input bool TradeTuesday  = true;
input bool TradeWednesday= true;
input bool TradeThursday = true;
input bool TradeFriday   = true;

//================== INPUT: GROUP 6 - SYSTEM FILTER ==================
input group "=== 6. System Filter ==="
input bool   UseSpreadFilter      = true;
input double MaxSpreadPoints      = 500;
input int    MaxTotalOpenPositions = 10;
input double SL_BufferPoints      = 0;
input int    MagicNumber          = 777007;

//================== INPUT: GROUP 7 - CUSTOM FITNESS (OnTester) ==================
input group "=== 7. Custom Fitness - Fast Generic Algorithm (Custom Max) ==="
// bobot Recovery Factor (net profit vs DD)
input double Fitness_W_RecoveryFactor = 0.4;   //RecoveryFactor
// bobot kelurusan kurva equity (growth stabil)
input double Fitness_W_EquityR2       = 0.4;   //EquityR2
// bobot win rate
input double Fitness_W_WinRate        = 0.2;   //WWinrate
// dibawah ini fitness dipangkas proporsional
input int    Fitness_MinTrades        = 100;   //MinTrade
// hard cutoff: DD diatas ini fitness = 0
input double Fitness_MaxDD_Percent    = 30.0;  //DrawDown
// RF dinormalisasi thd angka ini (di-cap 1.0)
input double Fitness_RF_NormCap       = 5.0;   //NormCap

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
int          g_consecutive[3];   // 0=L1,1=L2,2=L3 -- naik hanya saat FILL (lihat OnTradeTransaction)
datetime     g_lastBarTime = 0;
double       g_equityCurve[];    // dicatat tiap bar baru, dipakai OnTester utk hitung R^2

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_consecutive[0]=0; g_consecutive[1]=0; g_consecutive[2]=0;
   g_lastBarTime = 0;
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
   Print("EA V5.3 Initialized. Symbol=", _Symbol, " Period=", EnumToString(_Period));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Comment helpers: format "TAG|R" contoh "L2|3.45"                 |
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
//| Streak evaluation (generic per streakCount)                      |
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
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailingStop();
   ManageMaxHoldBars();
   if(UseWeekendClose) CheckWeekendClose();

   datetime curBar = iTime(_Symbol,_Period,0);
   if(curBar<=0 || curBar==g_lastBarTime) return;
   g_lastBarTime = curBar;

   // catat equity tiap bar baru -- dipakai OnTester utk hitung R^2 kurva growth
   int n = ArraySize(g_equityCurve);
   ArrayResize(g_equityCurve, n+1);
   g_equityCurve[n] = AccountInfoDouble(ACCOUNT_EQUITY);

   CleanupExpiredPendingOrders();

   if(PositionsTotal() >= MaxTotalOpenPositions) return;
   if(UseSpreadFilter && IsSpreadHigh()) return;
   if(UseDayFilter && !IsDayAllowed()) return;
   if(UseSessionFilter && !IsSessionAllowed()) return;
   if(UseWeekendClose && BlockNewTradeAfterWeekendClose && IsPastWeekendCloseHour()) return;

   if(g_layers[0].enabled) ProcessLayerSignal(0, curBar);
   if(g_layers[1].enabled) ProcessLayerSignal(1, curBar);
   if(g_layers[2].enabled) ProcessLayerSignal(2, curBar);
  }

//+------------------------------------------------------------------+
//| Proses sinyal + eksekusi per layer (independen penuh)            |
//+------------------------------------------------------------------+
void ProcessLayerSignal(int layerIdx, datetime barTime)
  {
   SLayerParams cfg = g_layers[layerIdx];
   if(iBars(_Symbol,_Period) < cfg.streakCount+1) return;

   int signal = EvaluateStreakGeneric(cfg.streakCount);
   if(signal==0)
     {
      g_consecutive[layerIdx] = 0;
      return;
     }
   if(g_consecutive[layerIdx] >= cfg.maxConsecutive) return;

   // L2/L3: jangan tumpuk pending baru selama masih ada pending aktif utk layer ini
   if(layerIdx>0 && HasActivePendingForLayer(cfg.tag)) return;

   SetAutoFillingType();
   double point     = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double ask       = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   if(point<=0 || ask<=0 || bid<=0) return;

   double openFirst, closeLast, highMax, lowMin;
   GetStreakData(cfg.streakCount, openFirst, closeLast, highMax, lowMin);

   bool isBuy = (signal==1);

   // --- Filter ukuran streak (hanya jika dynamic SL) ---
   if(cfg.useStreakFilter)
     {
      double streakDist = GetStreakRange(cfg.calcMode, openFirst, closeLast, highMax, lowMin) / point;
      if(streakDist < cfg.minStreakPoints || streakDist > cfg.maxStreakPoints)
        {
         Print(_Symbol," ",cfg.tag," - Streak size ",streakDist," di luar filter [",cfg.minStreakPoints,"-",cfg.maxStreakPoints,"]. Skip.");
         return;
        }
     }

   // --- Entry price ---
   double entry;
   if(layerIdx==0)
     {
      entry = isBuy ? ask : bid;
     }
   else
     {
      double range = GetStreakRange(cfg.calcMode, openFirst, closeLast, highMax, lowMin);
      if(range<=0) return;
      double retraceFrac = cfg.retracePercent/100.0;
      if(isBuy)
        {
         double anchorHigh = (cfg.calcMode==STREAK_CALC_OPEN_CLOSE) ? closeLast : highMax;
         entry = anchorHigh - range*retraceFrac;
        }
      else
        {
         double anchorLow = (cfg.calcMode==STREAK_CALC_OPEN_CLOSE) ? closeLast : lowMin;
         entry = anchorLow + range*retraceFrac;
        }
     }

   // --- Stop Loss ---
   double slPrice;
   if(cfg.useStaticSL)
     {
      slPrice = isBuy ? (entry - cfg.staticSLPoints*point) : (entry + cfg.staticSLPoints*point);
     }
   else
     {
      double anchor = (cfg.calcMode==STREAK_CALC_OPEN_CLOSE) ? openFirst : (isBuy ? lowMin : highMax);
      slPrice = isBuy ? (anchor - SL_BufferPoints*point) : (anchor + SL_BufferPoints*point);
     }

   double R = isBuy ? (entry - slPrice) : (slPrice - entry);
   if(R<=0) return;

   double tp  = isBuy ? (entry + R*cfg.rrr) : (entry - R*cfg.rrr);
   double lot = cfg.useStaticLot ? NormalizeLot(cfg.staticLot)
                                  : CalculateDynamicLot(R/point, cfg.riskPercent, cfg.staticLot);

   string cmt = cfg.tag+"|"+DoubleToString(R,_Digits);

   bool ok=false;
   if(layerIdx==0)
     {
      ok = isBuy ? trade.Buy(lot,_Symbol,entry,slPrice,tp,cmt) : trade.Sell(lot,_Symbol,entry,slPrice,tp,cmt);
      if(!ok) Print("Error ",cfg.tag," [",_Symbol,"]: ",trade.ResultRetcode()," - ",trade.ResultRetcodeDescription());
     }
   else
     {
      if(isBuy  && entry > (ask-stopLevel)) return;
      if(!isBuy && entry < (bid+stopLevel)) return;
      datetime expr = barTime + (cfg.limitExpireBars * PeriodSeconds(_Period));
      ok = isBuy ? trade.BuyLimit(lot,entry,_Symbol,slPrice,tp,ORDER_TIME_SPECIFIED,expr,cmt)
                  : trade.SellLimit(lot,entry,_Symbol,slPrice,tp,ORDER_TIME_SPECIFIED,expr,cmt);
      if(!ok) Print("Error ",cfg.tag," [",_Symbol,"]: ",trade.ResultRetcode()," - ",trade.ResultRetcodeDescription());
     }
   // NOTE: g_consecutive TIDAK naik di sini. Naik hanya saat posisi FILL -> OnTradeTransaction (opsi B)
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction - counter naik hanya saat posisi kefill       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal,DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL) != _Symbol) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY) != DEAL_ENTRY_IN) return;

   string cmt = HistoryDealGetString(trans.deal,DEAL_COMMENT);
   string layerTag; double rVal;
   if(!ParseComment(cmt, layerTag, rVal)) return;

   int layerIdx = TagToIndex(layerTag);
   if(layerIdx<0) return;

   g_consecutive[layerIdx]++;
  }

//+------------------------------------------------------------------+
//| Lot management                                                    |
//+------------------------------------------------------------------+
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
//| Trailing Stop (per posisi, baca cfg dari comment tag)            |
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
         if(newSL>curSL) trade.PositionModify(ticket,newSL,curTP);
        }
      else
        {
         double newSL = entry - lockedR*R;
         if(curSL==0 || newSL<curSL) trade.PositionModify(ticket,newSL,curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Fitur: Auto-close posisi setelah N bar terbuka (per layer)       |
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
//| Filter Handlers                                                   |
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
//| Pending order management                                          |
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

void SetAutoFillingType()
  {
   uint filling = (uint)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)!=0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC)!=0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                        trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| R^2 regresi linear kurva equity -- ukuran "growth stabil"        |
//| Slope <=0 (equity gak naik bersih) -> dianggap 0, bukan "stabil" |
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

   double b = (n*sumXY - sumX*sumY) / denom; // slope
   double a = meanY - b*meanX;               // intercept

   if(b <= 0) return 0.0; // equity gak trending naik -> bukan growth stabil

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
//| Custom Fitness utk Fast Generic Algorithm (Custom Max)           |
//| Fitness = (W1*RF_norm + W2*R2_equity + W3*WinRate) * TradeFactor |
//| Hard cutoff: DD > Fitness_MaxDD_Percent -> fitness = 0           |
//+------------------------------------------------------------------+
double OnTester()
  {
   double trades = TesterStatistics(STAT_TRADES);
   if(trades <= 0) return 0.0;

   double ddPercent = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(ddPercent > Fitness_MaxDD_Percent) return 0.0; // hard cutoff DD

   double netProfit    = TesterStatistics(STAT_PROFIT);
   double profitTrades = TesterStatistics(STAT_PROFIT_TRADES);
   double initDeposit   = TesterStatistics(STAT_INITIAL_DEPOSIT);
   if(initDeposit<=0) initDeposit = 1.0;

   double ddMoney = (ddPercent/100.0) * initDeposit;
   double RF = netProfit / (ddMoney + 1.0);
   double RF_norm = MathMin(1.0, RF / Fitness_RF_NormCap);
   if(RF_norm < 0) RF_norm = 0;

   double winRate = profitTrades / trades;

   double r2 = ComputeEquityR2();

   double tradeFactor = MathMin(1.0, trades / (double)MathMax(1, Fitness_MinTrades));

   double fitness = (Fitness_W_RecoveryFactor*RF_norm
                    + Fitness_W_EquityR2*r2
                    + Fitness_W_WinRate*winRate) * tradeFactor;

   return fitness;
  }
//+------------------------------------------------------------------+
