//+------------------------------------------------------------------+
//| MomenCandleStreak_Merged_v1.0.mq5                                 |
//| Gabungan 2 sistem entry terpisah, dipilih via EntryMode:          |
//|   MODE_MARKET_LAYERING = sistem v3.1 (Market L1 + Pending L2)     |
//|   MODE_DUAL_PENDING    = sistem D1.3 (Pending L1 + Pending L2)    |
//| SEMUA variabel dari kedua file asli DIPERTAHANKAN, tidak dihapus |
//| satupun -- untuk keperluan testing banding drawdown/profit.      |
//|                                                                    |
//| CATATAN WAJIB: hanya SATU sistem aktif per waktu (sesuai toggle).|
//| Kedua sistem TIDAK berjalan bersamaan dalam 1 tick -- ini disengaja|
//| karena tujuannya membandingkan, bukan menggabungkan sinyal.      |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== MODE PEMILIH SISTEM ==================
enum ENUM_ENTRY_MODE
  {
   MODE_MARKET_LAYERING = 0, // Sistem v3.1: Layer1 Market + Layer2 Pending Retrace
   MODE_DUAL_PENDING    = 1, // Sistem D1.3: Layer1 & Layer2 sama2 Pending Retrace
   MODE_TRIPLE_LAYER    = 2  // BARU: Layer1 Market + Layer2 Retrace40% + Layer3 Retrace70%
  };
input group "=== 0. PILIH SISTEM ENTRY (hanya satu aktif per waktu) ==="
input ENUM_ENTRY_MODE EntryMode = MODE_MARKET_LAYERING;

//====================================================================
//======================  BLOK INPUT: SISTEM v3.1  ==================
//====================================================================
input group "=== [v3.1] Cakupan Symbol & Timeframe ==="
input string SymbolList          = "XAUUSD";
input string TimeframeList       = "H1";

input group "=== [v3.1] Strategi & Layering ==="
input int    StreakCount         = 2;
input double RetracePercent      = 0; // Retrace x% dari candle kedua (50% = 0.50)
input int    MaxConsecutiveTrades= 4;    // Batas maksimal trade berurutan

input group "=== [v3.1] Lot Management ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.05;
input double RiskPercentPerTrade = 1.0;

input group "=== [v3.1] Target TP & SL ==="
input double SL_BufferPoints     = 0;
input double MaxSLPoints         = 1000;
input double RiskRewardRatio     = 1.0;

input group "=== [v3.1] Trailing Stop ==="
input bool   UseTrailingStop     = false;
input double TrailStepPercent    = 10.0;

input group "=== [v3.1] SL Static (Override) ==="
input bool   UseStaticSL         = true;
input double StaticSLPoints      = 25000;

input group "=== [v3.1] Weekend Close ==="
input bool   UseWeekendClose     = true;
input int    WeekendCloseHour    = 22;
input bool   BlockNewTradeAfterWeekendClose = true;

input group "=== [v3.1] Session Filter ==="
input bool   UseSessionFilter    = false;
input bool   EnableAsianSession  = true;
input int    AsianStartHour      = 1;
input int    AsianEndHour        = 9;
input bool   EnableLondonSession = true;
input int    LondonStartHour     = 9;
input int    LondonEndHour       = 17;
input bool   EnableUSSession     = true;
input int    USStartHour         = 14;
input int    USEndHour           = 22;

input group "=== [v3.1] Day Filter ==="
input bool   TradeMonday         = true;
input bool   TradeTuesday        = true;
input bool   TradeWednesday      = true;
input bool   TradeThursday       = true;
input bool   TradeFriday         = true;

input group "=== [v3.1] Filter Umum ==="
input bool   UseSpreadFilter     = false;
input double MaxSpreadPoints     = 500;
input bool   OnePositionPerSymbol= false;
input int    MaxTotalOpenPositions = 3;
input int    MagicNumber         = 777007;

//====================================================================
//======================  BLOK INPUT: MODE TRIPLE LAYER (BARU)  =====
//====================================================================
input group "=== [Triple] Layer 1 (Market) ==="
input bool   TripleUseL1         = true;  // matikan kalau mau tes tanpa Layer1
input double TripleL1_RRR        = 1.5;   // TP Layer1 = R x ratio ini (R = SL bersama)
input double TripleL1_Lot        = 0.03;

input group "=== [Triple] Layer 2 (Retrace) ==="
input bool   TripleUseL2         = true;  // matikan kalau mau tes tanpa Layer2
input double TripleL2_RetracePct = 0.40;  // 40%
input double TripleL2_RRR        = 2.0;
input double TripleL2_Lot        = 0.03;

input group "=== [Triple] Layer 3 (Retrace) ==="
input bool   TripleUseL3         = true;  // matikan kalau mau tes tanpa Layer3
input double TripleL3_RetracePct = 0.70;  // 70%
input double TripleL3_RRR        = 2.5;
input double TripleL3_Lot        = 0.03;

input group "=== [Triple] Manajemen ==="
input int    TripleMagicNumber   = 777099; // magic terpisah, tak bentrok mode lain

//====================================================================
//======================  BLOK INPUT: SISTEM D1.3  ==================
//====================================================================
input group "=== [D1.3] 1. Pengaturan Layer 1 (Entry 1) ==="
input bool     InpUseLayer1           = true;
input double   InpLayer1_Retrace      = 40.0;
input double   InpLayer1_RRR          = 2.25;
input double   InpLayer1_Lot          = 0.04;

input group "=== [D1.3] 2. Pengaturan Layer 2 (Entry 2) ==="
input bool     InpUseLayer2           = true;
input double   InpLayer2_Retrace      = 70.0;
input double   InpLayer2_RRR          = 2.0;
input double   InpLayer2_Lot          = 0.04;

input group "=== [D1.3] 3. Parameter Strategi Streak & Pending ==="
input int      InpStreakCount         = 2;
input int      InpLimitExpireBars     = 1;

input group "=== [D1.3] 4. Filter Batasan Ukuran Candle 1 & 2 ==="
input bool     InpUseStreakSizeFilter = false;
input double   InpMinStreakPoints     = 20000;
input double   InpMaxStreakPoints     = 30000;

input group "=== [D1.3] 5. Pengaturan Stop Loss ==="
input bool     InpUseStaticSL         = false;
input double   InpStaticSLPoints      = 25000;
input int      InpSLBufferPoints      = 0;

input group "=== [D1.3] 6. Filter Sesi Trading (Server Time) ==="
input bool     InpUseAsianSession     = true;
input int      InpAsianStartHour      = 0;
input int      InpAsianEndHour        = 8;
input bool     InpUseLondonSession    = true;
input int      InpLondonStartHour     = 8;
input int      InpLondonEndHour       = 16;
input bool     InpUseUSSession        = true;
input int      InpUSStartHour         = 16;
input int      InpUSEndHour           = 23;

input group "=== [D1.3] 7. Filter Hari Trading ==="
input bool     InpTradeMonday         = true;
input bool     InpTradeTuesday        = true;
input bool     InpTradeWednesday      = true;
input bool     InpTradeThursday       = true;
input bool     InpTradeFriday         = true;

input group "=== [D1.3] 8. Management & ID ==="
input ulong    InpMagicNumber         = 777013;

//====================================================================
//======================  GLOBAL: SISTEM v3.1  ======================
//====================================================================
struct SymTFState
  {
   string          symbol;
   ENUM_TIMEFRAMES tf;
   datetime        lastBarTime;
   int             consecutiveTrades;
  };
SymTFState g_states[];

//====================================================================
//======================  GLOBAL: SISTEM D1.3  ======================
//====================================================================
int      g_totalSetups = 0;
int      g_retraceHits = 0;
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| OnInit -- setup KEDUA sistem sekaligus (yang tidak aktif idle)  |
//+------------------------------------------------------------------+
int OnInit()
  {
   // --- Setup array multi symbol/TF punya v3.1 ---
   string symbols[]; string tfs[];
   int nSym = StringSplit(SymbolList, ',', symbols);
   int nTf  = StringSplit(TimeframeList, ',', tfs);

   if(nSym <= 0 || nTf <= 0)
     {
      Print("ERROR [v3.1]: SymbolList atau TimeframeList kosong/invalid.");
     }
   else
     {
      ArrayResize(g_states, nSym * nTf);
      int idx = 0;
      for(int s=0; s<nSym; s++)
        {
         string sym = symbols[s];
         StringTrimLeft(sym); StringTrimRight(sym);
         if(!SymbolSelect(sym, true))
           {
            Print("WARNING [v3.1]: Symbol '", sym, "' tidak ditemukan, dilewati.");
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
               Print("WARNING [v3.1]: Timeframe '", tfStr, "' tidak dikenali, dilewati.");
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
      if(idx == 0 && EntryMode == MODE_MARKET_LAYERING)
         Print("WARNING [v3.1]: Tidak ada kombinasi symbol/timeframe valid, sistem ini tidak akan trading.");
     }

   // --- Setup D1.3 (single symbol/period chart aktif) ---
   g_lastBarTime = 0;
   g_totalSetups = 0;
   g_retraceHits = 0;
   EventSetTimer(1);

   // Magic default ikut mode aktif; akan di-set ulang tiap kali sebelum eksekusi trade di masing2 sistem
   trade.SetExpertMagicNumber(EntryMode == MODE_MARKET_LAYERING ? MagicNumber : (int)InpMagicNumber);

   Print("EA Gabungan siap. EntryMode aktif = ", EnumToString(EntryMode));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   if(EntryMode == MODE_DUAL_PENDING) UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| OnTick -- ROUTER, panggil sistem sesuai EntryMode                |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(EntryMode == MODE_MARKET_LAYERING)
     {
      trade.SetExpertMagicNumber(MagicNumber);
      RunMarketLayeringSystem();
     }
   else if(EntryMode == MODE_DUAL_PENDING)
     {
      trade.SetExpertMagicNumber((int)InpMagicNumber);
      RunDualPendingSystem();
     }
   else // MODE_TRIPLE_LAYER
     {
      trade.SetExpertMagicNumber(TripleMagicNumber);
      RunTripleLayerSystem();
     }
  }

//====================================================================
//===============  SISTEM 1: MARKET LAYERING (v3.1)  ================
//===============  Badan asli OnTick() v3.1, TIDAK diubah  ==========
//====================================================================
void RunMarketLayeringSystem()
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
         Print(sym, " [v3.1] - Batas maks ", MaxConsecutiveTrades, " trade sekuensial tercapai. Skip.");
         continue;
        }

      bool executed = false;
      if(signal == 1)  executed = ExecuteLayeredTrade(sym, tf, ORDER_TYPE_BUY, currentBarTime);
      if(signal == -1) executed = ExecuteLayeredTrade(sym, tf, ORDER_TYPE_SELL, currentBarTime);

      if(executed)
        {
         g_states[i].consecutiveTrades++;
         Print(sym, " [v3.1] Trade Berhasil. Consecutive Count: ", g_states[i].consecutiveTrades);
        }
     }
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
   if(stepLot > 0) targetLot = MathFloor(targetLot / stepLot) * stepLot;
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
      default: return false;
     }
  }

//+------------------------------------------------------------------+
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

   double slLevel = iOpen(sym, tf, firstCandleIdx);
   bool anyExecuted = false;

   double entryL1 = (type == ORDER_TYPE_BUY) ? ask : bid;
   double slL1;

   if(UseStaticSL)
     {
      slL1 = (type == ORDER_TYPE_BUY) ? (entryL1 - StaticSLPoints*point) : (entryL1 + StaticSLPoints*point);
     }
   else
     {
      double rawSL = (type == ORDER_TYPE_BUY) ? (slLevel - SL_BufferPoints*point)
                                                : (slLevel + SL_BufferPoints*point);
      slL1 = rawSL;

      if(type == ORDER_TYPE_BUY)
        {
         double rawDistPoints = (entryL1 - rawSL) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints)
           {
            slL1 = entryL1 - (MaxSLPoints * point);
            Print(sym, " [v3.1] - SL terlalu jauh (", rawDistPoints, " pt). Dicap ke MaxSLPoints: ", MaxSLPoints);
           }
        }
      else
        {
         double rawDistPoints = (rawSL - entryL1) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints)
           {
            slL1 = entryL1 + (MaxSLPoints * point);
            Print(sym, " [v3.1] - SL terlalu jauh (", rawDistPoints, " pt). Dicap ke MaxSLPoints: ", MaxSLPoints);
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
      else Print("Error Layer 1 [v3.1][", sym, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
     }

   double limitPriceL2, tpL2, slL2, R2;

   if(type == ORDER_TYPE_BUY)
     {
      limitPriceL2 = h1 - RetracePercent * range1;
      slL2         = slL1;
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
   else
     {
      limitPriceL2 = l1 + RetracePercent * range1;
      slL2         = slL1;
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

//====================================================================
//===============  SISTEM 3: TRIPLE LAYER (BARU)  ===================
//===============  L1/L2/L3 punya konfigurasi TERPISAH (retrace%,   =
//===============  RRR, lot masing2 beda input) -- bisa diotak-atik  =
//===============  kombinasinya sendiri2 tanpa saling pengaruh       =
//====================================================================
void RunTripleLayerSystem()
  {
   if(UseWeekendClose) CheckWeekendClose_Triple();
   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   for(int i=0; i<ArraySize(g_states); i++)
     {
      string sym = g_states[i].symbol;
      ENUM_TIMEFRAMES tf = g_states[i].tf;

      datetime currentBarTime = iTime(sym, tf, 0);
      if(currentBarTime <= 0 || currentBarTime == g_states[i].lastBarTime) continue;

      g_states[i].lastBarTime = currentBarTime;

      DeleteStalePendingOrders_Triple(sym);

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
         Print(sym, " [Triple] - Batas maks ", MaxConsecutiveTrades, " trade sekuensial tercapai. Skip.");
         continue;
        }

      bool executed = false;
      if(signal == 1)  executed = ExecuteTripleLayerTrade(sym, tf, ORDER_TYPE_BUY, currentBarTime);
      if(signal == -1) executed = ExecuteTripleLayerTrade(sym, tf, ORDER_TYPE_SELL, currentBarTime);

      if(executed)
        {
         g_states[i].consecutiveTrades++;
         Print(sym, " [Triple] Sinyal diproses. Consecutive Count: ", g_states[i].consecutiveTrades);
        }
     }
  }

//+------------------------------------------------------------------+
//| Eksekusi 3 layer. SETIAP layer independen: enable/disable, lot,  |
//| retrace%, RRR masing2 dari input SENDIRI-SENDIRI (lihat blok     |
//| input "=== [Triple] Layer N ===" di atas). SL dari sumber yang   |
//| sama (StaticSL/dinamis+cap), supaya perbandingan antar layer     |
//| adil (variabel yang beda cuma titik entry & RR/lot per layer).   |
//+------------------------------------------------------------------+
bool ExecuteTripleLayerTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type, datetime barTime)
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

   double slLevel = iOpen(sym, tf, firstCandleIdx);
   bool anyExecuted = false;

   // --- SL BERSAMA (acuan sama utk L1/L2/L3, biar perbandingan antar layer adil) ---
   double entryRef = (type == ORDER_TYPE_BUY) ? ask : bid;
   double slShared;

   if(UseStaticSL)
     {
      slShared = (type == ORDER_TYPE_BUY) ? (entryRef - StaticSLPoints*point) : (entryRef + StaticSLPoints*point);
     }
   else
     {
      double rawSL = (type == ORDER_TYPE_BUY) ? (slLevel - SL_BufferPoints*point) : (slLevel + SL_BufferPoints*point);
      slShared = rawSL;
      if(type == ORDER_TYPE_BUY)
        {
         double rawDistPoints = (entryRef - rawSL) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints) slShared = entryRef - (MaxSLPoints * point);
        }
      else
        {
         double rawDistPoints = (rawSL - entryRef) / point;
         if(MaxSLPoints > 0 && rawDistPoints > MaxSLPoints) slShared = entryRef + (MaxSLPoints * point);
        }
     }

   // --- LAYER 1: MARKET (konfigurasi sendiri: TripleL1_RRR, TripleL1_Lot, toggle TripleUseL1) ---
   if(TripleUseL1)
     {
      double entryL1 = entryRef;
      double R1 = (type == ORDER_TYPE_BUY) ? (entryL1 - slShared) : (slShared - entryL1);
      if(R1 > 0)
        {
         double tpL1 = (type == ORDER_TYPE_BUY) ? (entryL1 + R1*TripleL1_RRR) : (entryL1 - R1*TripleL1_RRR);
         double lotL1 = NormalizeLot(sym, TripleL1_Lot);
         bool resL1 = (type == ORDER_TYPE_BUY) ?
                      trade.Buy(lotL1, sym, entryL1, slShared, tpL1, "TRI_L1|"+DoubleToString(R1,_Digits)) :
                      trade.Sell(lotL1, sym, entryL1, slShared, tpL1, "TRI_L1|"+DoubleToString(R1,_Digits));
         if(resL1) anyExecuted = true;
         else Print("Error Triple L1 [", sym, "]: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
     }

   // --- LAYER 2: RETRACE (konfigurasi sendiri: TripleL2_RetracePct, TripleL2_RRR, TripleL2_Lot, TripleUseL2) ---
   if(TripleUseL2)
      anyExecuted = PlaceTripleRetraceLayer(sym, tf, type, barTime, h1, l1, range1, slShared,
                                             TripleL2_RetracePct, TripleL2_RRR, TripleL2_Lot,
                                             "TRI_L2", ask, bid, stopLevel, point) || anyExecuted;

   // --- LAYER 3: RETRACE (konfigurasi sendiri: TripleL3_RetracePct, TripleL3_RRR, TripleL3_Lot, TripleUseL3) ---
   if(TripleUseL3)
      anyExecuted = PlaceTripleRetraceLayer(sym, tf, type, barTime, h1, l1, range1, slShared,
                                             TripleL3_RetracePct, TripleL3_RRR, TripleL3_Lot,
                                             "TRI_L3", ask, bid, stopLevel, point) || anyExecuted;

   return anyExecuted;
  }

//+------------------------------------------------------------------+
//| Generic pending-limit placer, dipakai Layer2 & Layer3 -- tiap    |
//| panggilan terima parameter retrace/RRR/lot SENDIRI2, jadi Layer2 |
//| dan Layer3 sama sekali tak saling pengaruh saat diubah manual.   |
//+------------------------------------------------------------------+
bool PlaceTripleRetraceLayer(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type, datetime barTime,
                              double h1, double l1, double range1, double slShared,
                              double retracePct, double rrr, double lot, string tag,
                              double ask, double bid, double stopLevel, double point)
  {
   double limitPrice, tp, R;

   if(type == ORDER_TYPE_BUY)
     {
      limitPrice = h1 - retracePct * range1;
      R = limitPrice - slShared;
      if(R <= 0 || limitPrice > (ask - stopLevel)) return false;
      tp = limitPrice + R * rrr;
      double lotN = NormalizeLot(sym, lot);
      datetime expr = barTime + PeriodSeconds(tf);
      return trade.BuyLimit(lotN, limitPrice, sym, slShared, tp, ORDER_TIME_SPECIFIED, expr, tag+"|"+DoubleToString(R,_Digits));
     }
   else
     {
      limitPrice = l1 + retracePct * range1;
      R = slShared - limitPrice;
      if(R <= 0 || limitPrice < (bid + stopLevel)) return false;
      tp = limitPrice - R * rrr;
      double lotN = NormalizeLot(sym, lot);
      datetime expr = barTime + PeriodSeconds(tf);
      return trade.SellLimit(lotN, limitPrice, sym, slShared, tp, ORDER_TIME_SPECIFIED, expr, tag+"|"+DoubleToString(R,_Digits));
     }
  }

//+------------------------------------------------------------------+
void DeleteStalePendingOrders_Triple(string sym)
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != TripleMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;
      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT)
         trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
void CheckWeekendClose_Triple()
  {
   if(!IsPastWeekendCloseHour()) return;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != TripleMagicNumber) continue;
      trade.PositionClose(ticket);
     }
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != TripleMagicNumber) continue;
      trade.OrderDelete(ticket);
     }
  }

//====================================================================
//===============  SISTEM 2: DUAL PENDING RETRACE (D1.3)  ===========
//===============  Badan asli OnTick() D1.3, TIDAK diubah  ==========
//===============  (fungsi bentrok nama diberi suffix _D13)  ========
//====================================================================
void RunDualPendingSystem()
  {
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;

   if(HasActivePositionOrPending()) return;

   if(!IsDayAllowed_D13() || !IsSessionAllowed_D13()) return;

   int streakDirection = CheckStreakSignal();
   if(streakDirection == 0) return;

   double streakOpenToCloseDistance = MathAbs(iClose(_Symbol, _Period, 1) - iOpen(_Symbol, _Period, InpStreakCount)) / _Point;

   if(InpUseStreakSizeFilter)
     {
      if(streakOpenToCloseDistance < InpMinStreakPoints || streakOpenToCloseDistance > InpMaxStreakPoints)
        {
         PrintFormat("Model D1.3: Sinyal Diabaikan! Ukuran Streak (%.1f pt) di luar batas [%.0f - %.0f pt]",
                     streakOpenToCloseDistance, InpMinStreakPoints, InpMaxStreakPoints);
         return;
        }
     }

   g_lastBarTime = currentBarTime;
   g_totalSetups++;

   double streakHigh  = GetStreakHigh(InpStreakCount);
   double streakLow   = GetStreakLow(InpStreakCount);
   double streakRange = streakHigh - streakLow;

   if(streakRange <= 0) return;

   datetime expirationTime = currentBarTime + (InpLimitExpireBars * PeriodSeconds(_Period));

   SetAutoFillingType(_Symbol); // dipinjam dari fungsi v3.1, cegah reject filling mode broker

   if(InpUseLayer1)
      SendLayerOrder(streakDirection, streakHigh, streakLow, streakRange,
                     InpLayer1_Retrace, InpLayer1_RRR, InpLayer1_Lot,
                     expirationTime, "Model D1.3 - L1");

   if(InpUseLayer2)
      SendLayerOrder(streakDirection, streakHigh, streakLow, streakRange,
                     InpLayer2_Retrace, InpLayer2_RRR, InpLayer2_Lot,
                     expirationTime, "Model D1.3 - L2");
  }

//+------------------------------------------------------------------+
void SendLayerOrder(int streakDir, double streakHigh, double streakLow, double streakRange,
                    double retracePct, double rrr, double lotSize,
                    datetime expireTime, string commentStr)
  {
   double limitPrice = 0;
   double slPrice    = 0;
   double tpPrice    = 0;
   ENUM_ORDER_TYPE orderType;

   if(streakDir == 1)
     {
      orderType  = ORDER_TYPE_BUY_LIMIT;
      limitPrice = streakHigh - (streakRange * (retracePct / 100.0));

      if(InpUseStaticSL)
         slPrice = limitPrice - (InpStaticSLPoints * _Point);
      else
         slPrice = streakLow - (InpSLBufferPoints * _Point);

      double riskDistance = limitPrice - slPrice;
      if(riskDistance <= 0) return;

      tpPrice = limitPrice + (riskDistance * rrr);
     }
   else
     {
      orderType  = ORDER_TYPE_SELL_LIMIT;
      limitPrice = streakLow + (streakRange * (retracePct / 100.0));

      if(InpUseStaticSL)
         slPrice = limitPrice + (InpStaticSLPoints * _Point);
      else
         slPrice = streakHigh + (InpSLBufferPoints * _Point);

      double riskDistance = slPrice - limitPrice;
      if(riskDistance <= 0) return;

      tpPrice = limitPrice - (riskDistance * rrr);
     }

   limitPrice = NormalizeDouble(limitPrice, _Digits);
   slPrice    = NormalizeDouble(slPrice, _Digits);
   tpPrice    = NormalizeDouble(tpPrice, _Digits);

   if(trade.OrderOpen(_Symbol, orderType, lotSize, limitPrice, limitPrice, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expireTime, commentStr))
     {
      PrintFormat("%s: Order %s terpasang di %.5f (Retrace %.1f%%) | SL: %.5f | TP: %.5f",
                  commentStr, EnumToString(orderType), limitPrice, retracePct, slPrice, tpPrice);
     }
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagicNumber)
        {
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
           {
            g_retraceHits++;
            UpdateDashboard();
           }
        }
     }
  }

//+------------------------------------------------------------------+
double OnTester()
  {
   if(g_totalSetups == 0) return 0.0;
   return ((double)g_retraceHits / (double)g_totalSetups) * 100.0;
  }

//+------------------------------------------------------------------+
//| Rename dari IsDayAllowed()/IsSessionAllowed() -- hindari bentrok |
//| nama dgn fungsi v3.1 yg fungsinya serupa tapi pakai input beda   |
//+------------------------------------------------------------------+
bool IsDayAllowed_D13()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
     {
      case 1: return InpTradeMonday;
      case 2: return InpTradeTuesday;
      case 3: return InpTradeWednesday;
      case 4: return InpTradeThursday;
      case 5: return InpTradeFriday;
      default: return false;
     }
  }

bool IsSessionAllowed_D13()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;

   bool inAsian  = InpUseAsianSession  && IsTimeInHourRange(currentHour, InpAsianStartHour, InpAsianEndHour);
   bool inLondon = InpUseLondonSession && IsTimeInHourRange(currentHour, InpLondonStartHour, InpLondonEndHour);
   bool inUS     = InpUseUSSession     && IsTimeInHourRange(currentHour, InpUSStartHour, InpUSEndHour);

   return (inAsian || inLondon || inUS);
  }

bool IsTimeInHourRange(int hour, int startHour, int endHour)
  {
   if(startHour < endHour)
      return (hour >= startHour && hour < endHour);
   else
      return (hour >= startHour || hour < endHour);
  }

//+------------------------------------------------------------------+
int CheckStreakSignal()
  {
   bool bullish = true;
   bool bearish = true;

   for(int i = 1; i <= InpStreakCount; i++)
     {
      double closePrice = iClose(_Symbol, _Period, i);
      double openPrice  = iOpen(_Symbol, _Period, i);

      if(closePrice <= openPrice) bullish = false;
      if(closePrice >= openPrice) bearish = false;
     }

   if(bullish) return 1;
   if(bearish) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
bool HasActivePositionOrPending()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) > 0)
        {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
            return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
double GetStreakHigh(int count)
  {
   double maxHigh = iHigh(_Symbol, _Period, 1);
   for(int i = 2; i <= count; i++)
     {
      double h = iHigh(_Symbol, _Period, i);
      if(h > maxHigh) maxHigh = h;
     }
   return maxHigh;
  }

double GetStreakLow(int count)
  {
   double minLow = iLow(_Symbol, _Period, 1);
   for(int i = 2; i <= count; i++)
     {
      double l = iLow(_Symbol, _Period, i);
      if(l < minLow) minLow = l;
     }
   return minLow;
  }

//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   double hitRate = (g_totalSetups > 0) ? ((double)g_retraceHits / (double)g_totalSetups) * 100.0 : 0.0;

   string text = "=========================================\n";
   text += "     MODEL D1.3 - DUAL LAYER PANEL      \n";
   text += "  (EA GABUNGAN - Mode Aktif: " + EnumToString(EntryMode) + ")\n";
   text += "=========================================\n";
   text += StringFormat("Layer 1 : %s (%.1f%% Retrace | RRR 1:%.1f)\n", InpUseLayer1 ? "ON" : "OFF", InpLayer1_Retrace, InpLayer1_RRR);
   text += StringFormat("Layer 2 : %s (%.1f%% Retrace | RRR 1:%.1f)\n", InpUseLayer2 ? "ON" : "OFF", InpLayer2_Retrace, InpLayer2_RRR);
   text += StringFormat("Mode SL : %s\n", InpUseStaticSL ? "STATIC" : "DYNAMIC");
   text += StringFormat("Total Setups : %d | Total Hits : %d\n", g_totalSetups, g_retraceHits);
   text += StringFormat("Retrace Hit Rate : %.2f%%\n", hitRate);
   text += "=========================================\n";

   Comment(text);
  }
//+------------------------------------------------------------------+
