//+------------------------------------------------------------------+
//|                                                  BotVang_V10.mq5 |
//|  H1 Signal | AI Python API | Multi-Class | Ensemble | SMC A+ Pro |
//|  V10.9: Setup A+ (Sweep -> BOS -> OB -> LTF Confirm -> FVG 50%)  |
//|  Fix: Per-bar guard | Param Lookback | Institutional Entry       |
//+------------------------------------------------------------------+
#property copyright "BotVang"
#property version   "10.9"
#property strict
#include <Trade\Trade.mqh>

//==========================================================================
//| CẤU TRÚC DỮ LIỆU                                                       |
//==========================================================================
struct AIResponse {   
   string signal;        
   double confidence;    
   double sl_dist;       
   double tp_dist;    
};

struct SMC_Aplus_State {   
   bool sweep_detected;   
   bool bos_detected;   
   double ob_high;   
   double ob_low;   
   datetime setup_time;
};

//==========================================================================
//| INPUTS                                                                 |
//==========================================================================
input string  inpAIServerURL    = "http://127.0.0.1:8000/predict"; 
input string  inpSymbol        = "XAUUSD";
input int     inpMagic         = 999999;
input double  inpRiskPct       = 1.0;
input double  inpMaxEquityDD   = 15.0;
input double  inpDailyMaxLoss  = 2.0;
input double  inpWeeklyMaxLoss = 8.0;
input bool    inpUseNewsFilter = true;
input int     inpMinsBefore    = 30;
input int     inpMinsAfter     = 30;
input bool    inpCloseFriday   = true;
input int     inpFridayHour    = 22;
input int     inpFridayMin     = 45;
input double  inpTargetProfit  = 0.0;
input bool    inpUseTrailing   = true;
input double  inpTrailStartATR = 1.0;
input double  inpTrailStepATR  = 0.5;
input bool    inpUsePartialClose = true;
input double  inpTP1_Mult      = 1.0;
input double  inpTP2_Mult      = 2.0;
input double  inpTP3_Mult      = 3.0;
input double  inpPart1_Pct     = 0.30;
input double  inpPart2_Pct     = 0.20;
input double  inpPart3_Pct     = 0.30;
input int     inpATRPeriod     = 14;
input int     inpEMA1          = 20;
input int     inpEMA2          = 50;
input double  inpMinATR        = 1.5;
input int     inpVolK          = 14;
input double  inpVolMult       = 3.0;
input bool    inpUseADXFilter  = true;
input int     inpADXPeriod     = 14;
input double  inpMinADX        = 20.0;
input bool    inpConfidenceLot    = true;
input double  inpConfidenceLotMin = 0.4;
input double  inpMinConfidence    = 0.45;
input int     inpMaxPositions  = 3;
input int     inpMaxScaleIns   = 3;
input bool    inpTrade247      = false;
input bool    inpSessionFilter = true;
input int     inpSessionStart  = 1;
input int     inpSessionEnd    = 17;

//--- SMC A+ SETUP SETTINGS
input bool          inpUseSMC_Aplus    = true; 
enum ENUM_SMC_ENTRY { ENTRY_CONSERVATIVE, ENTRY_AGGRESSIVE };
input ENUM_SMC_ENTRY inpEntryMethod     = ENTRY_CONSERVATIVE; 
input int           inpSMC_Lookback     = 50; 
input double        inpOB_Buffer_Pips   = 2.0;

//==========================================================================
//| GLOBAL VARIABLES                                                       |
//==========================================================================
int      h_atr, h_ema1, h_ema2, h_adx, h_ema200_4h;
double   vbuf[50];
int      vidx = 0, vcnt = 0;
double   vema = 0, vmean = 0, valpha = 0;

struct ScaleIn { ulong ticket; double entry, lot, sl, tp; bool alive; };
struct MyPos {   
   ulong ticket; int dir; double entry, tp, init_lot, cur_lot, sl;   
   int close_step, scale_cnt; ScaleIn si[3];   
   datetime last_scalein_bar, t_open; bool alive;
};

MyPos    gPos[];
int      gPosCnt = 0;
CTrade   trade;
datetime lastTradeBar = 0;
datetime lastCheckedBar = 0; 
string   csvFile = "botvang_v10_log.csv";
const string GV_WEEKLY_BAL     = "BotVang_WeeklyBal";
const string GV_WEEK_NUMBER    = "BotVang_WeekNum";
const string GV_EMERGENCY_STOP = "BotVang_EmergencyStop";
double   weeklyStartBal    = 0;
bool     emergency_stopped = false;
bool     is_synced         = false;
datetime lastDriftCheck    = 0;

//==========================================================================
//| INIT & DEINIT                                                          |
//==========================================================================
int OnInit() {   
   trade.SetExpertMagicNumber(inpMagic);   
   if(!SymbolSelect(inpSymbol, true)) return INIT_FAILED;   
   
   h_atr       = iATR(inpSymbol, PERIOD_H1, inpATRPeriod);   
   h_ema1      = iMA(inpSymbol, PERIOD_H1, inpEMA1, 0, MODE_EMA, PRICE_CLOSE);   
   h_ema2      = iMA(inpSymbol, PERIOD_H1, inpEMA2, 0, MODE_EMA, PRICE_CLOSE);   
   h_adx       = iADX(inpSymbol, PERIOD_H1, inpADXPeriod);   
   h_ema200_4h = iMA(inpSymbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);   
   
   if(h_atr==INVALID_HANDLE || h_ema1==INVALID_HANDLE || h_ema2==INVALID_HANDLE ||      
      h_adx==INVALID_HANDLE || h_ema200_4h==INVALID_HANDLE) return INIT_FAILED;      
      
   valpha = 2.0 / (inpVolK + 1.0);   
   ArrayInitialize(vbuf, 0);   
   emergency_stopped = (GlobalVariableGet(GV_EMERGENCY_STOP) == 1.0);   
   is_synced = false;   
   UpdateWeeklyBalance();   
   
   Print("=== BotVang V10.9 | SMC Setup A+ Pipeline | Entry:", EnumToString(inpEntryMethod), " ===");   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {   
   IndicatorRelease(h_atr); IndicatorRelease(h_ema1);   
   IndicatorRelease(h_ema2); IndicatorRelease(h_adx);   
   IndicatorRelease(h_ema200_4h);
}

//==========================================================================
//| AI WEB API CONNECTION                                                 |
//==========================================================================
AIResponse AI_Request_Server() {   
   AIResponse res;   
   res.signal = "ERROR"; res.confidence = 0.0; res.sl_dist = 0.0; res.tp_dist = 0.0;   
   string postData = StringFormat("{\"symbol\":\"%s\", \"timeframe\":\"H1\"}", inpSymbol);   
   char post[], result[];   
   string headers;   
   StringToCharArray(postData, post);      
   
   int http_res = WebRequest("POST", inpAIServerURL, NULL, 5000, post, result, headers);   
   if(http_res == 200) {      
      string response = CharArrayToString(result);      
      if(StringFind(response, "\"signal\":\"BUY\"") != -1) res.signal = "BUY";      
      else if(StringFind(response, "\"signal\":\"SELL\"") != -1) res.signal = "SELL";      
      else res.signal = "WAIT";            
      
      int confPos = StringFind(response, "\"confidence\":");      
      if(confPos != -1) res.confidence = StringToDouble(StringSubstr(response, confPos + 13, 5));      
      int slPos = StringFind(response, "\"sl_dist\":");      
      if(slPos != -1) res.sl_dist = StringToDouble(StringSubstr(response, slPos + 10, 6));      
      int tpPos = StringFind(response, "\"tp_dist\":");      
      if(tpPos != -1) res.tp_dist = StringToDouble(StringSubstr(response, tpPos + 10, 6));   
   }   
   return res;
}

//==========================================================================
//| SMC A+ CORE LOGIC - THE "INSTITUTIONAL" PIPELINE                       |
//==========================================================================
// 1. Phát hiện Quét Thanh Khoản (Sweep)
bool DetectAplusSweep(int signal, double &sweep_price) {   
   MqlRates rates[]; ArraySetAsSeries(rates, true);   
   if(CopyRates(inpSymbol, PERIOD_H1, 0, inpSMC_Lookback, rates) < inpSMC_Lookback) return false;      
   
   if(signal == 1) { // Buy: Tìm cú quét đáy      
      double lowest = rates[1].low;      
      int low_idx = 1;      
      for(int i=2; i<inpSMC_Lookback; i++) {         
         if(rates[i].low < lowest) { lowest = rates[i].low; low_idx = i; }      
      }      
      if(rates[0].low < lowest && rates[0].close > lowest) {         
         sweep_price = lowest; return true;      
      }   
   } else { // Sell: Tìm cú quét đỉnh      
      double highest = rates[1].high;      
      int high_idx = 1;      
      for(int i=2; i<inpSMC_Lookback; i++) {         
         if(rates[i].high > highest) { highest = rates[i].high; high_idx = i; }      
      }      
      if(rates[0].high > highest && rates[0].close < highest) {         
         sweep_price = highest; return true;      
      }   
   }   
   return false;
}

// 2. Phát hiện Phá vỡ cấu trúc (BOS) sau Sweep
bool DetectAplusBOS(int signal, double sweep_price) {   
   MqlRates rates[]; ArraySetAsSeries(rates, true);   
   if(CopyRates(inpSymbol, PERIOD_H1, 0, 10, rates) < 10) return false;      
   
   if(signal == 1) { // Bullish BOS: Đóng cửa trên đỉnh gần nhất      
      double peak = rates[1].high;      
      for(int i=2; i<10; i++) if(rates[i].high > peak) peak = rates[i].high;      
      return (rates[0].close > peak);   
   } else { // Bearish BOS: Đóng cửa dưới đáy gần nhất      
      double valley = rates[1].low;      
      for(int i=2; i<10; i++) if(rates[i].low < valley) valley = rates[i].low;      
      return (rates[0].close < valley);   
   }
}

// 3. Xác định Order Block (OB)
void GetAplusOB(int signal, double &ob_high, double &ob_low) {   
   MqlRates rates[]; ArraySetAsSeries(rates, true);   
   CopyRates(inpSymbol, PERIOD_H1, 0, 10, rates);   
   if(signal == 1) { // Bullish OB: Cây nến giảm cuối cùng trước cú đẩy BOS      
      for(int i=1; i<10; i++) {         
         if(rates[i].close < rates[i].open) {            
            ob_high = rates[i].high; ob_low = rates[i].low; return;         
         }      
      }   
   } else { // Bearish OB: Cây nến tăng cuối cùng trước cú sập BOS      
      for(int i=1; i<10; i++) {         
         if(rates[i].close > rates[i].open) {            
            ob_high = rates[i].high; ob_low = rates[i].low; return;         
         }      
      }   
   }
}

// 4. Xác nhận LTF (M15/M5) và FVG 50%
bool IsLTFConfirmed(int signal) {   
   MqlRates rates[]; ArraySetAsSeries(rates, true);   
   if(CopyRates(inpSymbol, PERIOD_M15, 0, 10, rates) < 10) return false;      
   
   // Step 1: Check CHoCH (Change of Character)   
   bool choch = false;   
   if(signal == 1) {      
      if(rates[0].close > rates[2].high) choch = true;   
   } else {      
      if(rates[0].close < rates[2].low) choch = true;   
   }      
   
   if(!choch) return false;   
   
   // Step 2: Tìm FVG và kiểm tra giá có ở vùng 50% (Midpoint) không   
   for(int i=1; i<5; i++) {      
      if(signal == 1 && rates[i+2].high < rates[i].low) { // Bullish FVG         
         double fvg_mid = (rates[i+2].high + rates[i].low) / 2.0;         
         double current_price = SymbolInfoDouble(inpSymbol, SYMBOL_BID);         
         if(current_price >= fvg_mid - (10 * _Point) && current_price <= rates[i].low) return true;      
      } else if(signal == -1 && rates[i+2].low > rates[i].high) { // Bearish FVG         
         double fvg_mid = (rates[i+2].low + rates[i].high) / 2.0;         
         double current_price = SymbolInfoDouble(inpSymbol, SYMBOL_BID);         
         if(current_price <= fvg_mid + (10 * _Point) && current_price >= rates[i].high) return true;      
      }   
   }   
   return false;
}

//==========================================================================
//| FINAL SMC A+ PIPELINE                                                  |
//==========================================================================
bool IsSMC_Aplus_Confirmed(int signal) {   
   if(!inpUseSMC_Aplus) return true;   
   
   // T1: Trend HTF (4H EMA 200)   
   double ema200_buf[]; ArraySetAsSeries(ema200_buf, true);   
   if(CopyBuffer(h_ema200_4h, 0, 0, 1, ema200_buf) >= 1) {      
      double ema200 = ema200_buf[0], c4h = iClose(inpSymbol, PERIOD_H4, 1);      
      if(signal == 1 && c4h < ema200) return false;      
      if(signal == -1 && c4h > ema200) return false;   
   }   
   
   // T2: Thực hiện quy trình A+ (Sweep -> BOS -> OB)   
   double sweep_p = 0, ob_h = 0, ob_l = 0;   
   if(!DetectAplusSweep(signal, sweep_p)) return false;   
   if(!DetectAplusBOS(signal, sweep_p)) return false;   
   GetAplusOB(signal, ob_h, ob_l);   
   
   // T3: Kiểm tra Retest OB   
   double current_price = SymbolInfoDouble(inpSymbol, SYMBOL_BID);   
   bool in_ob = (signal == 1) ? (current_price >= ob_l && current_price <= ob_h)                               
                               : (current_price >= ob_l && current_price <= ob_h);   
   if(!in_ob) return false;   
   
   // T4: Xác nhận LTF (M15) - Chế độ Conservative vs Aggressive   
   if(inpEntryMethod == ENTRY_CONSERVATIVE) {      
      if(!IsLTFConfirmed(signal)) return false;   
   } else {      
      // Aggressive: Chỉ cần Retest OB và AI Confidence cao      
      return true;    
   }   
   return true;
}

//==========================================================================
//| ENTRY SYSTEM                                                          |
//==========================================================================
void TryEntry(double ask, double bid, double spread) {   
   datetime currentBar = iTime(inpSymbol, PERIOD_H1, 0);   
   if(currentBar == lastCheckedBar) return;    
   lastCheckedBar = currentBar;    
   
   MqlDateTime dt; TimeCurrent(dt);   
   if(inpCloseFriday && dt.day_of_week==5 && (dt.hour>inpFridayHour||(dt.hour==inpFridayHour&&dt.min>=inpFridayMin))) return;   
   if(IsHighImpactNewsZone()) return;   
   if(!IsInSession()) return;   
   if(!CheckWeeklyLimit()) return;   
   if(!IsMarketOpen()) return;   
   if(CountMyPositions() >= inpMaxPositions) return;   
   if(!CheckVolGate(spread)) return;   
   
   double atr = Buf(h_atr, 1);   
   if(atr < inpMinATR) return;   
   if(inpUseADXFilter) {      
      double adxB[]; ArraySetAsSeries(adxB, true);      
      if(CopyBuffer(h_adx, 0, 1, 1, adxB) > 0 && adxB[0] < inpMinADX) return;   
   }   
   
   AIResponse ai = AI_Request_Server();   
   if(ai.signal == "WAIT" || ai.signal == "ERROR") return;   
   
   int signal = (ai.signal == "BUY") ? 1 : -1;   
   
   // ÁP DỤNG SETUP A+   
   if(!IsSMC_Aplus_Confirmed(signal)) return;   
   if(inpMinConfidence > 0.0 && ai.confidence < inpMinConfidence) return;   
   
   int dir = (signal == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;   
   double price = (dir == ORDER_TYPE_BUY) ? ask : bid;   
   double sl_dist = (ai.sl_dist > 0) ? ai.sl_dist : (atr * 2.0);    
   double tp_dist = (ai.tp_dist > 0) ? ai.tp_dist : (atr * 4.0);   
   double sl = (dir == ORDER_TYPE_BUY) ? price - sl_dist : price + sl_dist;   
   double tp = (dir == ORDER_TYPE_BUY) ? price + tp_dist : price - tp_dist;      
   
   double lot = CalcLot(MathAbs(price - sl)); if(lot <= 0) return;   
   if(inpConfidenceLot) {      
      double cs = inpConfidenceLotMin + (1.0 - inpConfidenceLotMin) * MathMax(0.0, MathMin(1.0, (ai.confidence - 0.33) / 0.67));      
      lot = NormLot(lot * cs);   
   }   
   
   int digits = (int)SymbolInfoInteger(inpSymbol, SYMBOL_DIGITS);   
   sl = NormalizeDouble(sl, digits); tp = NormalizeDouble(tp, digits);   
   string comment = StringFormat("V10.9_%.3f_%s_SMC_Aplus", ai.confidence, ai.signal);   
   
   bool ok = (dir == ORDER_TYPE_BUY) ? trade.Buy(lot, inpSymbol, ask, sl, tp, comment) : trade.Sell(lot, inpSymbol, bid, sl, tp, comment);   
   if(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE) {      
      lastTradeBar = currentBar;      
      RegisterPos(trade.ResultOrder(), dir, price, lot, sl, tp);      
      LogCSV("ENTRY_Aplus", lot, price, sl, tp, trade.ResultOrder(), "OPEN", ai.confidence);   
   }
}

//==========================================================================
//| CORE ENGINE & UTILS (V10.8 LOGIC)                                      |
//==========================================================================
void OnTick() {   
   if(!is_synced) { SyncPositions(); is_synced = true; }   
   MqlTick tick;   
   if(!SymbolInfoTick(inpSymbol, tick)) return;   
   double ask = tick.ask, bid = tick.bid, spread = ask - bid;   
   
   ManageFridayClose();   
   if(!CheckEquityDrawdown()) return;   
   if(emergency_stopped) return;   
   
   UpdateWeeklyBalance();   
   if(!CheckDailyLimit()) return;   
   UpdateVolGate(spread);   
   
   datetime currentBar = iTime(inpSymbol, PERIOD_H1, 0);   
   static datetime lastLogBar = 0;   
   if(currentBar != lastLogBar) { LogOpenPositions(); lastLogBar = currentBar; }   
   
   CheckDailyDrift();   
   CleanDeadPositions();   
   ManageReversal(ask, bid);   
   ManageTargetProfit();   
   ManagePartialClose(ask, bid);   
   ManageTrailingStop(ask, bid);   
   ManageScaleIn(ask, bid);   
   TryEntry(ask, bid, spread);
}

void SyncPositions() {   
   ArrayFree(gPos); gPosCnt = 0;   
   double atr = Buf(h_atr, 1); if(atr <= 0) atr = 1.0;   
   int total = PositionsTotal();   
   for(int i = 0; i < total; i++) {      
      ulong ticket = PositionGetTicket(i);      
      if(ticket <= 0 || PositionGetString(POSITION_SYMBOL) != inpSymbol || PositionGetInteger(POSITION_MAGIC) != inpMagic) continue;      
      
      int slot = gPosCnt++; ArrayResize(gPos, gPosCnt);      
      gPos[slot].ticket = ticket; gPos[slot].dir = (int)PositionGetInteger(POSITION_TYPE);      
      gPos[slot].entry = PositionGetDouble(POSITION_PRICE_OPEN); gPos[slot].tp = PositionGetDouble(POSITION_TP);      
      gPos[slot].sl = PositionGetDouble(POSITION_SL); gPos[slot].init_lot = PositionGetDouble(POSITION_VOLUME);      
      gPos[slot].cur_lot = gPos[slot].init_lot; gPos[slot].alive = true; gPos[slot].scale_cnt = 0;      
      gPos[slot].t_open = (datetime)PositionGetInteger(POSITION_TIME);      
      
      double cur_price = PositionGetDouble(POSITION_PRICE_CURRENT);      
      double dist = (gPos[slot].dir == ORDER_TYPE_BUY) ? (cur_price - gPos[slot].entry) : (gPos[slot].entry - cur_price);      
      if(dist >= inpTP3_Mult * atr) gPos[slot].close_step = 3;      
      else if(dist >= inpTP2_Mult * atr) gPos[slot].close_step = 2;      
      else if(dist >= inpTP1_Mult * atr || gPos[slot].sl == gPos[slot].entry) gPos[slot].close_step = 1;      
      else gPos[slot].close_step = 0;   
   }
}

void ManageFridayClose() {   
   if(!inpCloseFriday) return;   
   MqlDateTime dt; TimeCurrent(dt);   
   if(dt.day_of_week==5 && (dt.hour>inpFridayHour||(dt.hour==inpFridayHour&&dt.min>=inpFridayMin)))      
      if(CountMyPositions()>0) CloseAllPositions();
}

void CloseAllPositions() {   
   for(int i=0;i<gPosCnt;i++) {      
      if(!gPos[i].alive) continue;      
      if(PositionSelectByTicket(gPos[i].ticket)) trade.PositionClose(gPos[i].ticket);      
      for(int j=0;j<gPos[i].scale_cnt;j++)         
         if(gPos[i].si[j].alive&&PositionSelectByTicket(gPos[i].si[j].ticket)) trade.PositionClose(gPos[i].si[j].ticket);      
      gPos[i].alive=false;   
   }
}

void CleanDeadPositions() {   
   for(int i=0;i<gPosCnt;i++) {      
      if(gPos[i].alive&&!PositionSelectByTicket(gPos[i].ticket)) gPos[i].alive=false;      
      for(int j=0;j<gPos[i].scale_cnt;j++)         
         if(gPos[i].si[j].alive&&PositionSelectByTicket(gPos[i].si[j].ticket)) gPos[i].si[j].alive=false;   
   }
}

void ManagePartialClose(double ask, double bid) {   
   if(!inpUsePartialClose) return;   
   double atr=Buf(h_atr,1); if(atr<=0) return;   
   for(int i=0;i<gPosCnt;i++) {      
      if(!gPos[i].alive||!PositionSelectByTicket(gPos[i].ticket)) continue;      
      double cp=(gPos[i].dir==ORDER_TYPE_BUY)?bid:ask;      
      double dist=(gPos[i].dir==ORDER_TYPE_BUY)?(cp-gPos[i].entry):(gPos[i].entry-cp);      
      if(gPos[i].close_step==0&&dist>=inpTP1_Mult*atr) {         
         double vol=NormLot(gPos[i].init_lot*inpPart1_Pct);         
         if(vol>0&&trade.PositionClosePartial(gPos[i].ticket,vol)) {            
            trade.PositionModify(gPos[i].ticket,gPos[i].entry,PositionGetDouble(POSITION_TP));            
            gPos[i].close_step=1;         
         }      
      } else if(gPos[i].close_step==1&&dist>=inpTP2_Mult*atr) {         
         double vol=NormLot(gPos[i].init_lot*inpPart2_Pct);         
         if(vol>0&&trade.PositionClosePartial(gPos[i].ticket,vol)) gPos[i].close_step=2;      
      } else if(gPos[i].close_step==2&&dist>=inpTP3_Mult*atr) {         
         double vol=NormLot(gPos[i].init_lot*inpPart3_Pct);         
         if(vol>0&&trade.PositionClosePartial(gPos[i].ticket,vol)) gPos[i].close_step=3;      
      }   
   }
}

void ManageTargetProfit() {   
   if(inpTargetProfit<=0) return;   
   for(int i=0;i<gPosCnt;i++) {      
      if(!gPos[i].alive) continue;      
      double total=0;      
      if(PositionSelectByTicket(gPos[i].ticket)) total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);      
      for(int j=0;j<gPos[i].scale_cnt;j++)         
         if(gPos[i].si[j].alive&&PositionSelectByTicket(gPos[i].si[j].ticket))            
            total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);      
      if(total>=inpTargetProfit) {         
         if(PositionSelectByTicket(gPos[i].ticket)) trade.PositionClose(gPos[i].ticket);         
         gPos[i].alive=false;         
         for(int j=0;j<gPos[i].scale_cnt;j++)            
            if(gPos[i].si[j].alive&&PositionSelectByTicket(gPos[i].si[j].ticket)) trade.PositionClose(gPos[i].si[j].ticket);      
      }   
   }
}

void ManageTrailingStop(double ask, double bid) {   
   if(!inpUseTrailing) return;   
   double atr=Buf(h_atr,1); if(atr<=0) return;   
   int digits=(int)SymbolInfoInteger(inpSymbol,SYMBOL_DIGITS);   
   for(int i=0;i<gPosCnt;i++) {      
      if(!gPos[i].alive) continue;      
      if(PositionSelectByTicket(gPos[i].ticket)) _TrailOne(gPos[i].ticket,gPos[i].dir,atr,digits,ask,bid);      
      for(int j=0;j<gPos[i].scale_cnt;j++)         
         if(gPos[i].si[j].alive&&PositionSelectByTicket(gPos[i].si[j].ticket)) _TrailOne(gPos[i].si[j].ticket,gPos[i].dir,atr,digits,ask,bid);   
   }
}

void _TrailOne(ulong ticket,int dir,double atr,int digits,double ask,double bid) {   
   double cp=( dir==ORDER_TYPE_BUY)?bid:ask;   
   double op=PositionGetDouble(POSITION_PRICE_OPEN);   
   double csl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);   
   if(dir==ORDER_TYPE_BUY) {      
      if(cp-op>=inpTrailStartATR*atr) {         
         double nsl=NormalizeDouble(cp-inpTrailStepATR*atr,digits);         
         if(nsl>csl&&nsl<cp) trade.PositionModify(ticket,nsl,tp);      
      }   
   } else {      
      if(op-cp>=inpTrailStartATR*atr) {         
         double nsl=NormalizeDouble(cp+inpTrailStepATR*atr,digits);         
         if((csl==0||nsl<csl)&&nsl>cp) trade.PositionModify(ticket,nsl,tp);      
      }   
   }
}

void ManageReversal(double ask, double bid) {   
   double e1=Buf(h_ema1,1), e2=Buf(h_ema1,2);   
   double c1=iClose(inpSymbol,PERIOD_H1,1), c2=iClose(inpSymbol,PERIOD_H1,2);   
   if(e1<=0||e2<=0) return;   
   for(int i=0;i<gPosCnt;i++) {      
      if(!gPos[i].alive||!PositionSelectByTicket(gPos[i].ticket)) continue;      
      bool r1=(gPos[i].dir==ORDER_TYPE_BUY&&c1<e1)||(gPos[i].dir==ORDER_TYPE_SELL&&c1>e1);      
      bool r2=(gPos[i].dir==ORDER_TYPE_BUY&&c2<e2)||(gPos[i].dir==ORDER_TYPE_SELL&&c2>e2);      
      if(r1&&r2) {         
         if(trade.PositionClose(gPos[i].ticket)) gPos[i].alive=false;         
         for(int j=0;j<gPos[i].scale_cnt;j++)            
            if(gPos[i].si[j].alive&&PositionSelectByTicket(gPos[i].si[j].ticket)) trade.PositionClose(gPos[i].si[j].ticket);      
      }   
   }
}

void ManageScaleIn(double ask, double bid) {   
   double ema1=Buf(h_ema1,1), atr=Buf(h_atr,1);   
   if(ema1<=0||atr<=0) return;   
   for(int i=0;i<gPosCnt;i++) {      
      if(!gPos[i].alive||gPos[i].scale_cnt>=inpMaxScaleIns) continue;      
      if(!PositionSelectByTicket(gPos[i].ticket)) continue;      
      datetime h1bar=iTime(inpSymbol,PERIOD_H1,0);      
      if(gPos[i].last_scalein_bar==h1bar||PositionGetDouble(POSITION_PROFIT)<=0) continue;      
      double cp=(gPos[i].dir==ORDER_TYPE_BUY)?ask:bid;      
      if((gPos[i].dir==ORDER_TYPE_BUY&&cp<ema1)||(gPos[i].dir==ORDER_TYPE_SELL&&cp>ema1)) continue;      
      
      int sc=gPos[i].scale_cnt;      
      double pe=(sc==0)?gPos[i].entry:gPos[i].si[sc-1].entry;      
      double pt=(sc==0)?gPos[i].tp:gPos[i].si[sc-1].tp;      
      double c1=iClose(inpSymbol,PERIOD_H1,1);      
      if((gPos[i].dir==ORDER_TYPE_BUY&&c1<(pe+pt)/2.0)||(gPos[i].dir==ORDER_TYPE_SELL&&c1>(pe+pt)/2.0)) continue;      
      
      double si_lot=NormLot(gPos[i].init_lot*(sc==0?0.5:sc==1?0.25:0.125));      
      if(si_lot<SymbolInfoDouble(inpSymbol,SYMBOL_VOLUME_MIN)) continue;      
      
      int digits=(int)SymbolInfoInteger(inpSymbol,SYMBOL_DIGITS);      
      int regime=(gPos[i].dir==ORDER_TYPE_BUY)?1:-1;      
      
      // -- ĐÃ SỬA LỖI Ở ĐÂY --
      double sl_dist = atr * 2.0; 
      double tp_dist = atr * 4.0; 
      
      double si_sl = NormalizeDouble((gPos[i].dir==ORDER_TYPE_BUY) ? (cp - sl_dist) : (cp + sl_dist), digits);
      double si_tp = NormalizeDouble((gPos[i].dir==ORDER_TYPE_BUY) ? (cp + tp_dist) : (cp - tp_dist), digits);
      // -----------------------
      
      bool ok=(gPos[i].dir==ORDER_TYPE_BUY)?trade.Buy(si_lot,inpSymbol,ask,si_sl,si_tp,"BV_SI"):trade.Sell(si_lot,inpSymbol,bid,si_sl,si_tp,"BV_SI");      
      if(ok&&trade.ResultRetcode()==TRADE_RETCODE_DONE) {         
         gPos[i].si[sc].ticket=trade.ResultOrder(); gPos[i].si[sc].alive=true;         
         gPos[i].si[sc].entry=cp; gPos[i].si[sc].lot=si_lot;         
         gPos[i].scale_cnt++; gPos[i].last_scalein_bar=h1bar;      
      }   
   }
}

//==========================================================================
//| UTILS & RISK GUARDS                                                     |
//==========================================================================
bool CheckEquityDrawdown() {   
   if(inpMaxEquityDD<=0) return true;   
   double bal=AccountInfoDouble(ACCOUNT_BALANCE), eq=AccountInfoDouble(ACCOUNT_EQUITY);   
   if(bal<=0) return true;   
   double dd=((bal-eq)/bal)*100.0;   
   if(dd>=inpMaxEquityDD) {      
      if(!emergency_stopped) {         
         CloseAllPositions();         
         emergency_stopped=true;         
         GlobalVariableSet(GV_EMERGENCY_STOP,1.0);      
      }      
      return false;   
   }   
   return true;
}

void CheckDailyDrift() {   
   datetime now=TimeCurrent(); MqlDateTime dt; TimeToStruct(now,dt);   
   if(dt.hour!=8||dt.min>5) return;   
   if(now-lastDriftCheck<3600*20) return;   
   lastDriftCheck=now;   
   AIResponse res = AI_Request_Server();   
   Print(StringFormat("[DRIFT] %s | Signal=%s | Conf=%.4f", TimeToString(now), res.signal, res.confidence));
}

bool IsHighImpactNewsZone() {   
   if(!inpUseNewsFilter) return false;   
   datetime now=TimeCurrent(); MqlCalendarValue values[];   
   if(CalendarValueHistory(values,now-(inpMinsAfter*60),now+(inpMinsBefore*60),"US")) {      
      for(int i=0;i<ArraySize(values);i++) {         
         MqlCalendarEvent ev;         
         if(CalendarEventById(values[i].event_id,ev)&&ev.importance==CALENDAR_IMPORTANCE_HIGH) return true;      
      }   
   }   
   return false;
}

void RegisterPos(ulong t,int d,double e,double l,double sl,double tp) {   
   int slot=-1;   
   for(int i=0;i<gPosCnt;i++) if(!gPos[i].alive){slot=i;break;}   
   if(slot==-1){slot=gPosCnt++;ArrayResize(gPos,gPosCnt);}   
   gPos[slot].ticket=t; gPos[slot].dir=d; gPos[slot].entry=e;   
   gPos[slot].tp=tp; gPos[slot].init_lot=l; gPos[slot].cur_lot=l;   
   gPos[slot].sl=sl; gPos[slot].alive=true; gPos[slot].close_step=0;   
   gPos[slot].scale_cnt=0; gPos[slot].t_open=TimeCurrent();   
   for(int j=0;j<3;j++) gPos[slot].si[j].alive=false;
}

void LogOpenPositions() {   
   int total=PositionsTotal(); if(total==0) return;   
   for(int i=0;i<total;i++) {      
      ulong tk=PositionGetTicket(i);      
      if(tk>0&&PositionGetString(POSITION_SYMBOL)==inpSymbol&&PositionGetInteger(POSITION_MAGIC)==inpMagic)         
         Print(StringFormat("[%s] #%I64u | %s %.2f lot | P&L: $%.2f",            
            PositionGetString(POSITION_SYMBOL),tk,            
            (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?"BUY":"SELL",            
            PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PROFIT)));   
   }
}

double Buf(int handle,int shift) {   
   double b[]; ArraySetAsSeries(b,true);   
   return (CopyBuffer(handle,0,shift,1,b)>0)?b[0]:-1.0;
}

bool IsInSession() {   
   if(inpTrade247) return true;   
   MqlDateTime dt; TimeGMT(dt);   
   if(inpSessionStart<=inpSessionEnd) return (dt.hour>=inpSessionStart&&dt.hour<inpSessionEnd);   
   return (dt.hour>=inpSessionStart||dt.hour<inpSessionEnd);
}

bool IsMarketOpen() { 
   MqlTick t; return SymbolInfoTick(inpSymbol,t)&&(TimeCurrent()-t.time<300); 
}

double GetDailyProfit() {   
   HistorySelect(iTime(inpSymbol,PERIOD_D1,0),TimeCurrent());   
   double p=0;   
   for(int i=HistoryDealsTotal()-1;i>=0;i--) {      
      ulong t=HistoryDealGetTicket(i);      
      if(HistoryDealGetInteger(t,DEAL_MAGIC)==inpMagic) p+=HistoryDealGetDouble(t,DEAL_PROFIT);   
   }   
   return p;
}

bool CheckDailyLimit() {   
   double p=GetDailyProfit();   
   return (inpDailyMaxLoss<=0)||(p>-(AccountInfoDouble(ACCOUNT_BALANCE)*inpDailyMaxLoss/100.0));
}

void UpdateWeeklyBalance() {   
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);   
   int dsm=(dt.day_of_week==0)?6:(dt.day_of_week-1);   
   datetime tm=TimeCurrent()-dt.hour*3600-dt.min*60-dt.sec;   
   datetime mm=tm-(datetime)(dsm*86400);   
   int wn=(int)(mm/86400);   
   double sw=GlobalVariableGet(GV_WEEK_NUMBER);   
   if((int)sw!=wn) {      
      weeklyStartBal=AccountInfoDouble(ACCOUNT_BALANCE);      
      GlobalVariableSet(GV_WEEKLY_BAL,weeklyStartBal);      
      GlobalVariableSet(GV_WEEK_NUMBER,(double)wn);   
   } else if(weeklyStartBal<=0) {      
      weeklyStartBal=GlobalVariableGet(GV_WEEKLY_BAL);      
      if(weeklyStartBal<=0) weeklyStartBal=AccountInfoDouble(ACCOUNT_BALANCE);   
   }
}

bool CheckWeeklyLimit() {   
   if(inpWeeklyMaxLoss<=0||weeklyStartBal<=0) return true;   
   double lp=(AccountInfoDouble(ACCOUNT_BALANCE)-weeklyStartBal)/weeklyStartBal*100.0;   
   return (lp>-inpWeeklyMaxLoss);
}

void UpdateVolGate(double sp) {   
   if(vidx>=50) vidx = 0;   
   vbuf[vidx++]=sp; if(vcnt<50) vcnt++;   
   if(vcnt<14) return;   
   double s=0; for(int i=0;i<14;i++) s+=vbuf[i];   
   vmean=s/14.0; vema=(vema==0)?sp:valpha*sp+(1.0-valpha)*vema;
}

bool CheckVolGate(double sp) { 
   if(vcnt<14) return false; return sp<=vema+3.0*inpVolMult; 
}

int CountMyPositions() {   
   int c=0;   
   for(int i=0;i<gPosCnt;i++) if(gPos[i].alive&&PositionSelectByTicket(gPos[i].ticket)) c++;   
   return c;
}

void LogCSV(string ty,double lo,double pr,double sl,double tp,ulong ti,string st,double extra) {   
   int fh=FileOpen(csvFile,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI);   
   if(fh==INVALID_HANDLE) return;   
   FileSeek(fh,0, SEEK_END);   
   FileWrite(fh,StringFormat("%s,%s,%.3f,%.5f,%.5f,%.5f,%llu,%s,%.4f",      
      TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES),ty,lo,pr,sl,tp,ti,st,extra));   
   FileClose(fh);
}

double CalcLot(double sl_dist) {   
   if(sl_dist<=0) return -1.0;   
   double ru=AccountInfoDouble(ACCOUNT_BALANCE)*inpRiskPct/100.0;   
   double tv=SymbolInfoDouble(inpSymbol,SYMBOL_TRADE_TICK_VALUE);   
   double ts=SymbolInfoDouble(inpSymbol,SYMBOL_TRADE_TICK_SIZE);   
   if(tv<=0||ts<=0) return -1.0;   
   return NormLot(ru/((sl_dist/ts)*tv));
}

double NormLot(double l) {   
   double step=SymbolInfoDouble(inpSymbol,SYMBOL_VOLUME_STEP);   
   l=MathRound(l/step)*step;   
   return MathMax(MathMin(l,SymbolInfoDouble(inpSymbol,SYMBOL_VOLUME_MAX)),SymbolInfoDouble(inpSymbol,SYMBOL_VOLUME_MIN));
}