//+------------------------------------------------------------------+
//| MomenCandleStreak_Ultimate_V2.2.mq5                      |
//| Base: v2.1 Layering dengan Auto-Filling & Tester Protection        |
//+------------------------------------------------------------------+
#property copyright "Custom EA - Educational/Experimental Use"
#property version   "7.20"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//================== INPUT ==================
input group "=== Strategi & Layering ==="
input int    StreakCount         = 2;
input double RetracePercent      = 0.50; // Retrace x% dari candle kedua (50% = 0.50)
input int    MaxConsecutiveTrades= 3;    // Maksimal 3x trade berurutan

input group "=== Lot (Static Default) ==="
input bool   UseStaticLot        = true;
input double StaticLotSize       = 0.01;
input double RiskPercentPerTrade = 1.0;  // Nonaktif jika UseStaticLot = true

input group "=== Target TP & SL ==="
input double SL_BufferPoints     = 0;    // SL di Open Candle Pertama (0 Buffer)
input double RiskRewardRatio     = 1.0;  // TP Layer 1 (1:1 RR)

input group "=== Filter Umum ==="
input bool   UseSpreadFilter     = false;// Matikan filter spread saat backtest
input double MaxSpreadPoints     = 5000;
input int    MaxTotalOpenPositions = 10;
input int    MagicNumber         = 777007;

//================== GLOBAL VARIABLES ==================
datetime g_lastBarTime = 0;
int      g_consecutiveTrades = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Auto-detect Order Filling Mode yang didukung Broker/Tester
   SetAutoFillingType(_Symbol);

   Print("=== EA v7 INITIALIZED ===");
   Print("Symbol: ", _Symbol, " | TF: ", EnumToString(_Period));
   Print("Layer 1: Market (RR ", RiskRewardRatio, ") | Layer 2: Retrace ", RetracePercent*100, "%");
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(PositionsTotal() >= MaxTotalOpenPositions) return;

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return; // Hanya jalankan saat candle baru terbuka
   g_lastBarTime = currentBarTime;

   // Hapus pending order Layer 2 yang belum tersentuh dari candle sebelumnya
   DeleteStalePendingOrders(_Symbol);

   // Cek Spread jika diaktifkan
   if(UseSpreadFilter && IsSpreadHigh(_Symbol))
     {
      Print("Skip: Spread terlalu tinggi pada ", _Symbol);
      return;
     }

   int signal = EvaluateStreak(_Symbol, _Period);

   // Jika tidak ada streak (misal candle selang-seling), reset hitungan sekuensial
   if(signal == 0)
     {
      g_consecutiveTrades = 0;
      return;
     }

   // Cek Batasan Sekuensial Max Trade Berurutan
   if(g_consecutiveTrades >= MaxConsecutiveTrades)
     {
      Print("Skip: Mencapai batas maks ", MaxConsecutiveTrades, " trade sekuensial.");
      return;
     }

   // Eksekusi Trade
   if(signal == 1)  ExecuteLayeredTrade(_Symbol, _Period, ORDER_TYPE_BUY, currentBarTime);
   if(signal == -1) ExecuteLayeredTrade(_Symbol, _Period, ORDER_TYPE_SELL, currentBarTime);
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
void ExecuteLayeredTrade(string sym, ENUM_TIMEFRAMES tf, ENUM_ORDER_TYPE type, datetime barTime)
  {
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);

   if(point <= 0 || ask <= 0 || bid <= 0)
     {
      Print("Error: Harga/Point tidak valid pada ", sym);
      return;
     }

   int firstCandleIdx = StreakCount; 

   double h1 = iHigh(sym, tf, 1);
   double l1 = iLow(sym, tf, 1);
   double range1 = h1 - l1;
   if(range1 <= 0) return;

   // SL diambil dari Open candle lompatan pertama (Candle StreakCount)
   double slLevel = iOpen(sym, tf, firstCandleIdx);

   // --- LAYER 1: Market Order Instant ---
   double entryL1 = (type == ORDER_TYPE_BUY) ? ask : bid;
   double slL1    = (type == ORDER_TYPE_BUY) ? (slLevel - SL_BufferPoints*point) : (slLevel + SL_BufferPoints*point);
   double R1      = (type == ORDER_TYPE_BUY) ? (entryL1 - slL1) : (slL1 - entryL1);

   if(R1 > 0)
     {
      double tpL1  = (type == ORDER_TYPE_BUY) ? (entryL1 + R1 * RiskRewardRatio) : (entryL1 - R1 * RiskRewardRatio);
      
      bool res = false;
      if(type == ORDER_TYPE_BUY)
         res = trade.Buy(StaticLotSize, sym, entryL1, slL1, tpL1, "S7_L1");
      else
         res = trade.Sell(StaticLotSize, sym, entryL1, slL1, tpL1, "S7_L1");

      if(res)
        {
         g_consecutiveTrades++;
         Print("SUCCESS: Layer 1 Terbuka. Streak Berurutan ke-", g_consecutiveTrades);
        }
      else
        {
         Print("ERROR: Gagal Buka Layer 1. Retcode: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        }
     }
   else
     {
      Print("Skip Trade: Nilai R1 <= 0 (Entry: ", entryL1, " | SL: ", slL1, ")");
     }

   // --- LAYER 2: Pending Limit Order (Retrace x% Candle 1) ---
   double limitPriceL2, tpL2, slL2, R2;

   if(type == ORDER_TYPE_BUY)
     {
      limitPriceL2 = h1 - RetracePercent * range1;
      slL2         = slLevel - SL_BufferPoints*point;
      tpL2         = h1; // TP Layer 2 di High Candle Lompatan Kedua
      R2           = limitPriceL2 - slL2;

      if(R2 > 0 && limitPriceL2 < ask)
        {
         datetime expr = barTime + PeriodSeconds(tf);
         trade.BuyLimit(StaticLotSize, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2");
        }
     }
   else // SELL
     {
      limitPriceL2 = l1 + RetracePercent * range1;
      slL2         = slLevel + SL_BufferPoints*point;
      tpL2         = l1; // TP Layer 2 di Low Candle Lompatan Kedua
      R2           = slL2 - limitPriceL2;

      if(R2 > 0 && limitPriceL2 > bid)
        {
         datetime expr = barTime + PeriodSeconds(tf);
         trade.SellLimit(StaticLotSize, limitPriceL2, sym, slL2, tpL2, ORDER_TIME_SPECIFIED, expr, "S7_L2");
        }
     }
  }
//+------------------------------------------------------------------+
