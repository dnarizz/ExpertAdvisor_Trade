//+------------------------------------------------------------------+
//| MomenCandleStreak_V5_Independent.mq5                             |
//| Rombak total: 3 layer independen, tiap layer full-config sendiri |

// Beda ROOT dengan V5.1 tetapi sistemasi dan metodenya sama (Hasil Claude Chrome)
// Tambahan Fitur yaitu bisa Auto-close Position setelah beberapa waktu (Dalam Bar)
// Salah satu Bedanya dengan V5.1 adalah V5.2 harus declare Pair dan Timeframe sendiri sedangkan V5.1 sudah otomatis adapt 

//+------------------------------------------------------------------+
#property copyright "Custom EA - V5 Independent Layer Architecture"
#property version   "5.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== ENUM ==================
enum ENUM_STREAK_CALC_MODE
  {
   STREAK_CALC_OPEN_CLOSE,  // Open candle pertama ke Close candle terakhir streak
   STREAK_CALC_HIGH_LOW     // High tertinggi ke Low terendah seluruh streak
  };

//================== INPUT: GROUP 1 - SYMBOL & TIMEFRAME ==================
input group "=== 1. Cakupan Symbol & Timeframe ==="
input string SymbolList    = "XAUUSD";
input string TimeframeList = "H1";

//================== INPUT: GROUP 2 - LAYER 1 (MARKET) ==================
input group "=== 2. Layer 1 - Market Instant ==="
input bool   L1_UseLayer             = true;
input int    L1_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L1_StreakCalcMode = STREAK_CALC_OPEN_CLOSE; // dipakai HANYA utk SL dinamis
input int    L1_MaxConsecutiveTrades = 4;
input bool   L1_UseStaticLot         = true;
input double L1_StaticLotSize        = 0.03;
input double L1_RiskPercentPerTrade  = 1.0;
input bool   L1_UseStaticSLPoint     = false;
input double L1_StaticSLPoints       = 2500;
input bool   L1_UseStreakSizeFilter  = false; // hanya efektif jika L1_UseStaticSLPoint = false
input double L1_MinStreakPoints      = 200;
input double L1_MaxStreakPoints      = 3000;
input double L1_RRR                  = 1.0;
input bool   L1_UseTrailingStop      = false;
input double L1_TrailStepPercent     = 10.0;
input bool   L1_UseMaxHoldBars       = false;
input int    L1_MaxHoldBars          = 10;

//================== INPUT: GROUP 3 - LAYER 2 (PENDING RETRACE) ==================
input group "=== 3. Layer 2 - Pending Limit Retrace ==="
input bool   L2_UseLayer             = true;
input int    L2_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L2_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L2_RetracePercent       = 40.0;
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

//================== INPUT: GROUP 4 - LAYER 3 (PENDING RETRACE) ==================
input group "=== 4. Layer 3 - Pending Limit Retrace ==="
input bool   L3_UseLayer             = true;
input int    L3_StreakCount          = 2;
input ENUM_STREAK_CALC_MODE L3_StreakCalcMode = STREAK_CALC_HIGH_LOW;
input double L3_RetracePercent       = 70.0;
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

//================== INPUT: GROUP 5 - WEEKEND CLOSE ==================
input group "=== 5. Weekend Close ==="
input bool UseWeekendClose               = true;
input int  WeekendCloseHour              = 22;
input bool BlockNewTradeAfterWeekendClose = true;

//================== INPUT: GROUP 6 - SESSION & DAY FILTER ==================
input group "=== 6. Session & Day Filter ==="
input bool UseSessionFilter    = false;
input bool EnableAsianSession  = true;
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

//================== INPUT: GROUP 7 - SYSTEM FILTER ==================
input group "=== 7. System Filter ==="
input bool   UseSpreadFilter      = true;
input double MaxSpreadPoints      = 500;
input int    MaxTotalOpenPositions = 3;
input double SL_BufferPoints      = 0;
input int    MagicNumber          = 777007;

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

struct SymTFState
  {
   string          symbol;
   ENUM_TIMEFRAMES tf;
   datetime        lastBarTime;
   int             consecutiveTrades[3]; // index 0=L1,1=L2,2=L3
  };

SLayerParams g_layers[3];
SymTFState   g_states[];

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   // ---- Build state array (symbol x timeframe) ----
   string symbols[]; string tfs[];
   int nSym = StringSplit(SymbolList, ',', symbols);
   int nTf  = StringSplit(TimeframeList, ',', tfs);
   if(nSym<=0 || nTf<=0) { Print("ERROR: SymbolList/TimeframeList kosong."); return(INIT_FAILED); }

   ArrayResize(g_states, nSym*nTf);
   int idx=0;
   for(int s=0;s<nSym;s++)
     {
      string sym = symbols[s];
      StringTrimLeft(sym); StringTrimRight(sym);
      if(!SymbolSelect(sym,true)) { Print("WARNING: Symbol '",sym,"' tidak ditemukan."); continue; }

      for(int t=0;t<nTf;t++)
        {
         string tfStr = tfs[t];
         StringTrimLeft(tfStr); StringTrimRight(tfStr);
         bool valid;
         ENUM_TIMEFRAMES tf = StringToTimeframe(tfStr, valid);
         if(!valid) { Print("WARNING: Timeframe '",tfStr,"' tidak dikenali."); continue; }

         g_states[idx].symbol = sym;
         g_states[idx].tf = tf;
         g_states[idx].lastBarTime = 0;
         g_states[idx].consecutiveTrades[0]=0;
         g_states[idx].consecutiveTrades[1]=0;
         g_states[idx].consecutiveTrades[2]=0;
         idx++;
        }
     }
   ArrayResize(g_states, idx);

   // ---- Build layer params dari input ----
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
   Print("EA V5 Independent Initialized. Active States: ", idx);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Timeframe helpers                                                 |
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

string TimeframeToString(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
     }
   return "H1";
  }

//+------------------------------------------------------------------+
//| Comment helpers: format "TAG|TF|R" contoh "L2|H1|3.45"           |
//+------------------------------------------------------------------+
bool ParseComment(string cmt, string &layerTag, string &tfStr, double &R)
  {
   string parts[];
   int n = StringSplit(cmt, '|', parts);
   if(n<3) return false;
   layerTag = parts[0];
   tfStr    = parts[1];
   R        = StringToDouble(parts[2]);
   return true;
  }

int TagToIndex(string tag)
  {
   if(tag=="L1") return 0;
   if(tag=="L2") return 1;
   if(tag=="L3") return 2;
   return -1;
  }

int FindStateIndex(string sym, string tfStr)
  {
   for(int i=0;i<ArraySize(g_states);i++)
      if(g_states[i].symbol==sym && TimeframeToString(g_states[i].tf)==tfStr) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Streak evaluation (generic per streakCount)                      |
//+------------------------------------------------------------------+
int EvaluateStreakGeneric(string sym, ENUM_TIMEFRAMES tf, int count)
  {
   bool allGreen=true, allRed=true;
   for(int i=1;i<=count;i++)
     {
      double o=iOpen(sym,tf,i), c=iClose(sym,tf,i);
      if(o<=0 || c<=0) return 0;
      if(c<=o) allGreen=false;
      if(c>=o) allRed=false;
     }
   if(allGreen) return 1;
   if(allRed)   return -1;
   return 0;
  }

void GetStreakData(string sym, ENUM_TIMEFRAMES tf, int count,
                    double &openFirst, double &closeLast, double &highMax, double &lowMin)
  {
   openFirst = iOpen(sym,tf,count);
   closeLast = iClose(sym,tf,1);
   highMax   = iHigh(sym,tf,1);
   lowMin    = iLow(sym,tf,1);
   for(int i=2;i<=count;i++)
     {
      double h=iHigh(sym,tf,i); if(h>highMax) highMax=h;
      double l=iLow(sym,tf,i);  if(l<lowMin)  lowMin=l;
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
   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0;i<ArraySize(g_states);i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime curBar = iTime(sym,tf,0);
      if(curBar<=0 || curBar==g_states[i].lastBarTime) continue;
      g_states[i].lastBarTime = curBar;

      CleanupExpiredPendingOrders(sym);

      if(UseSpreadFilter && IsSpreadHigh(sym)) continue;
      if(UseDayFilter && !IsDayAllowed()) continue;
      if(UseSessionFilter && !IsSessionAllowed()) continue;
      if(UseWeekendClose && BlockNewTradeAfterWeekendClose && IsPastWeekendCloseHour()) continue;

      if(g_layers[0].enabled) ProcessLayerSignal(i,0,sym,tf,curBar);
      if(g_layers[1].enabled) ProcessLayerSignal(i,1,sym,tf,curBar);
      if(g_layers[2].enabled) ProcessLayerSignal(i,2,sym,tf,curBar);
     }
  }

//+------------------------------------------------------------------+
//| Proses sinyal + eksekusi per layer (independen penuh)            |
//+------------------------------------------------------------------+
void ProcessLayerSignal(int stateIdx, int layerIdx, string sym, ENUM_TIMEFRAMES tf, datetime barTime)
  {
   SLayerParams cfg = g_layers[layerIdx];
   if(iBars(sym,tf) < cfg.streakCount+1) return;

   int signal = EvaluateStreakGeneric(sym,tf,cfg.streakCount);
   if(signal==0)
     {
      g_states[stateIdx].consecutiveTrades[layerIdx] = 0;
      return;
     }
   if(g_states[stateIdx].consecutiveTrades[layerIdx] >= cfg.maxConsecutive) return;

   // L2/L3: jangan tumpuk pending baru selama masih ada pending aktif utk layer ini
   if(layerIdx>0 && HasActivePendingForLayer(sym, cfg.tag)) return;

   SetAutoFillingType(sym);
   double point     = SymbolInfoDouble(sym,SYMBOL_POINT);
   double ask       = SymbolInfoDouble(sym,SYMBOL_ASK);
   double bid       = SymbolInfoDouble(sym,SYMBOL_BID);
   double stopLevel = SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL)*point;
   if(point<=0 || ask<=0 || bid<=0) return;

   double openFirst, closeLast, highMax, lowMin;
   GetStreakData(sym,tf,cfg.streakCount, openFirst, closeLast, highMax, lowMin);

   bool isBuy = (signal==1);

   // --- Filter ukuran streak (hanya jika dynamic SL) ---
   if(cfg.useStreakFilter)
     {
      double streakDist = GetStreakRange(cfg.calcMode, openFirst, closeLast, highMax, lowMin) / point;
      if(streakDist < cfg.minStreakPoints || streakDist > cfg.maxStreakPoints)
        {
         Print(sym," ",cfg.tag," - Streak size ",streakDist," di luar filter [",cfg.minStreakPoints,"-",cfg.maxStreakPoints,"]. Skip.");
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
   double lot = cfg.useStaticLot ? NormalizeLot(sym,cfg.staticLot)
                                  : CalculateDynamicLot(sym, R/point, cfg.riskPercent, cfg.staticLot);

   string tfStr = TimeframeToString(tf);
   string cmt   = cfg.tag+"|"+tfStr+"|"+DoubleToString(R,_Digits);

   bool ok=false;
   if(layerIdx==0)
     {
      ok = isBuy ? trade.Buy(lot,sym,entry,slPrice,tp,cmt) : trade.Sell(lot,sym,entry,slPrice,tp,cmt);
      if(!ok) Print("Error ",cfg.tag," [",sym,"]: ",trade.ResultRetcode()," - ",trade.ResultRetcodeDescription());
     }
   else
     {
      if(isBuy  && entry > (ask-stopLevel)) return;
      if(!isBuy && entry < (bid+stopLevel)) return;
      datetime expr = barTime + (cfg.limitExpireBars * PeriodSeconds(tf));
      ok = isBuy ? trade.BuyLimit(lot,entry,sym,slPrice,tp,ORDER_TIME_SPECIFIED,expr,cmt)
                  : trade.SellLimit(lot,entry,sym,slPrice,tp,ORDER_TIME_SPECIFIED,expr,cmt);
      if(!ok) Print("Error ",cfg.tag," [",sym,"]: ",trade.ResultRetcode()," - ",trade.ResultRetcodeDescription());
     }
   // NOTE: counter consecutiveTrades TIDAK naik di sini.
   // Naik hanya saat posisi benar2 kefill -> lihat OnTradeTransaction (Q4 = opsi B)
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction - counter naik hanya saat posisi kefill       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if((int)HistoryDealGetInteger(trans.deal,DEAL_MAGIC) != MagicNumber) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY) != DEAL_ENTRY_IN) return;

   string sym = HistoryDealGetString(trans.deal,DEAL_SYMBOL);
   string cmt = HistoryDealGetString(trans.deal,DEAL_COMMENT);

   string layerTag, tfStr; double rVal;
   if(!ParseComment(cmt, layerTag, tfStr, rVal)) return;

   int layerIdx = TagToIndex(layerTag);
   if(layerIdx<0) return;

   int stateIdx = FindStateIndex(sym, tfStr);
   if(stateIdx<0) return;

   g_states[stateIdx].consecutiveTrades[layerIdx]++;
  }

//+------------------------------------------------------------------+
//| Lot management                                                    |
//+------------------------------------------------------------------+
double NormalizeLot(string sym, double targetLot)
  {
   double minLot  = SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(stepLot>0) targetLot = MathFloor(targetLot/stepLot)*stepLot;
   if(targetLot<minLot) targetLot=minLot;
   if(targetLot>maxLot) targetLot=maxLot;
   return NormalizeDouble(targetLot,2);
  }

double CalculateDynamicLot(string sym, double slPoints, double riskPercent, double fallbackLot)
  {
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE)*(riskPercent/100.0);
   double tickValue  = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(sym,SYMBOL_POINT);
   if(tickValue<=0 || tickSize<=0 || point<=0 || slPoints<=0) return NormalizeLot(sym,fallbackLot);
   double valuePerPoint = tickValue*(point/tickSize);
   double rawLot = riskAmount/(slPoints*valuePerPoint);
   return NormalizeLot(sym,rawLot);
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

      string cmt = PositionGetString(POSITION_COMMENT);
      string layerTag, tfStr; double R;
      if(!ParseComment(cmt, layerTag, tfStr, R)) continue;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx<0) continue;

      SLayerParams cfg = g_layers[layerIdx];
      if(!cfg.useTrailing || R<=0) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      long   type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double bid = SymbolInfoDouble(sym,SYMBOL_BID);
      double ask = SymbolInfoDouble(sym,SYMBOL_ASK);

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
//| Fitur baru: Auto-close posisi setelah N bar terbuka (per layer)  |
//+------------------------------------------------------------------+
void ManageMaxHoldBars()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      string cmt = PositionGetString(POSITION_COMMENT);
      string layerTag, tfStr; double R;
      if(!ParseComment(cmt, layerTag, tfStr, R)) continue;
      int layerIdx = TagToIndex(layerTag);
      if(layerIdx<0) continue;

      SLayerParams cfg = g_layers[layerIdx];
      if(!cfg.useMaxHold) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      bool valid; ENUM_TIMEFRAMES tf = StringToTimeframe(tfStr, valid);
      if(!valid) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int barsOpen = iBarShift(sym, tf, openTime, false);
      if(barsOpen >= cfg.maxHoldBars)
         trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Filter Handlers                                                   |
//+------------------------------------------------------------------+
bool IsSpreadHigh(string sym)
  {
   double spreadPoints = (double)SymbolInfoInteger(sym,SYMBOL_SPREAD);
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
//| Pending order management (bug expiry lama sudah difix)           |
//+------------------------------------------------------------------+
void CleanupExpiredPendingOrders(string sym)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      datetime expr = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(expr>0 && expr<=TimeCurrent())
         trade.OrderDelete(ticket);
     }
  }

bool HasActivePendingForLayer(string sym, string layerTag)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if((int)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt, layerTag+"|")==0) return true;
     }
   return false;
  }

void SetAutoFillingType(string sym)
  {
   uint filling = (uint)SymbolInfoInteger(sym,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)!=0)      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC)!=0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else                                        trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }
//+------------------------------------------------------------------+
