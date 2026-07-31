//+------------------------------------------------------------------+
//| gpterra.mq5                                                      |
//| Dynamic mother/child reverse-chain EA                            |
//| Strategy point: 0.1 price                                        |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "gpterra - dynamic two-input mother/child chain"
#define STRATEGY_POINT 0.1

input group "=== User inputs (only these trading inputs) ==="
input double InpLots                         = 0.01;
input double InpInitialDistancePips          = 10.0; // From current price to EACH first pending order
input double InpMotherProfitTriggerPips      = 20.0; // Mother profit before its reverse child

// The following are algorithm constants, not user trading inputs.
// Each generation keeps half of its parent's birth-profit budget.
#define CHILD_RATIO 0.50
#define EA_MAGIC 26072601
#define EA_DEVIATION_POINTS 20

string g_prefix="";
long   g_cycle=0;

enum ERole { ROLE_NONE=-1, ROLE_MOTHER=0, ROLE_CHILD=1 };

double P2Price(const double p) { return p*STRATEGY_POINT; }
int Digits_() { return (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS); }
double TickSize_()
{
   double t=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(t<=0) t=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   return t;
}
double Down(const double x)
{
   double t=TickSize_();
   return NormalizeDouble(MathFloor(x/t+1e-10)*t,Digits_());
}
double Up(const double x)
{
   double t=TickSize_();
   return NormalizeDouble(MathCeil(x/t-1e-10)*t,Digits_());
}
double BrokerDistance()
{
   long a=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long b=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax((double)MathMax(a,b)*SymbolInfoDouble(_Symbol,SYMBOL_POINT),TickSize_());
}

// Guard is derived automatically from broker limits and price granularity.
double GuardPrice() { return BrokerDistance()+2.0*TickSize_(); }
double GuardPips()  { return GuardPrice()/STRATEGY_POINT; }
double MotherR()    { return InpMotherProfitTriggerPips; }
double GenR(const int depth) { return MotherR()*MathPow(CHILD_RATIO,depth); }

// For parent depth n:
// F_n = L_(n+1) = 0.25 R_n - 2M; T_n = 0.75 R_n.
// This leaves at least two guards on both sides of the safety interval:
// F_n + R_(n+1) + M < T_n < R_n - L_(n+1) - M.
double FollowPips(const int parent_depth)
{
   return 0.25*GenR(parent_depth)-2.0*GuardPips();
}
double TrailPips(const int depth) { return 0.75*GenR(depth); }
double ChildInitialSLPips(const int child_depth)
{
   return FollowPips(child_depth-1);
}
bool CanSpawnFromDepth(const int depth)
{
   return FollowPips(depth)>0.0 && GenR(depth+1)>0.0;
}

// Complete calculated plan for one live position and its next child.
// Nothing in this structure is a user input.  It exists so every value
// requested by the strategy is explicit, auditable and used by the EA.
struct SDerivedPlan
{
   int    depth;
   double generation_profit_pips;       // profit of this position before child/trailing
   double initial_sl_pips;               // initial SL of this position (children only)
   double trail_trigger_pips;            // profit before this SL starts following
   double trail_distance_pips;           // distance of this position's SL from price
   double child_trigger_pips;            // profit before the reverse child is placed
   double child_follow_pips;             // reverse-child distance from current price
   double next_child_initial_sl_pips;    // SL put on that child after its fill
   double next_child_trail_trigger_pips;
   double next_child_trail_distance_pips;
   double next_child_child_trigger_pips;
   double next_child_follow_pips;
   double mother_fallback_sl_pips;       // before both original mothers have filled
};

bool BuildPlan(const int depth,SDerivedPlan &x)
{
   x.depth=depth;
   x.generation_profit_pips=GenR(depth);
   x.initial_sl_pips=(depth==0 ? 0.0 : ChildInitialSLPips(depth));
   x.trail_trigger_pips=x.generation_profit_pips;
   x.trail_distance_pips=TrailPips(depth);
   x.child_trigger_pips=x.generation_profit_pips;
   x.child_follow_pips=FollowPips(depth);
   x.next_child_initial_sl_pips=x.child_follow_pips;
   x.next_child_trail_trigger_pips=GenR(depth+1);
   x.next_child_trail_distance_pips=TrailPips(depth+1);
   x.next_child_child_trigger_pips=GenR(depth+1);
   x.next_child_follow_pips=FollowPips(depth+1);
   x.mother_fallback_sl_pips=2.0*InpInitialDistancePips+MotherR();
   return true;
}

void PrintPlan(const int depth)
{
   SDerivedPlan x; if(!BuildPlan(depth,x)) return;
   Print("gpterra plan depth=",depth,
         " | current: initialSL=",DoubleToString(x.initial_sl_pips,3),
         " trailProfit=",DoubleToString(x.trail_trigger_pips,3),
         " trailDistance=",DoubleToString(x.trail_distance_pips,3),
         " childProfit=",DoubleToString(x.child_trigger_pips,3),
         " childFollow=",DoubleToString(x.child_follow_pips,3),
         " | next child: initialSL=",DoubleToString(x.next_child_initial_sl_pips,3),
         " trailProfit=",DoubleToString(x.next_child_trail_trigger_pips,3),
         " trailDistance=",DoubleToString(x.next_child_trail_distance_pips,3),
         " childProfit=",DoubleToString(x.next_child_child_trigger_pips,3),
         " childFollow=",DoubleToString(x.next_child_follow_pips,3));
}

string MotherComment(const long cycle) { return "GPM:"+(string)cycle; }
string ChildComment(const ulong parent_id,const int depth)
{ return "GPC:"+(string)parent_id+":"+(string)depth; }
bool ParseMother(const string c,long &cycle)
{
   cycle=0; if(StringFind(c,"GPM:")!=0) return false;
   string x=StringSubstr(c,4); if(StringLen(x)==0) return false;
   cycle=(long)StringToInteger(x); return cycle>0;
}
bool ParseChild(const string c,ulong &parent,int &depth)
{
   parent=0; depth=0; if(StringFind(c,"GPC:")!=0) return false;
   string a=StringSubstr(c,4); int k=StringFind(a,":"); if(k<1) return false;
   string p=StringSubstr(a,0,k), d=StringSubstr(a,k+1);
   parent=(ulong)StringToInteger(p); depth=(int)StringToInteger(d);
   return parent>0 && depth>0;
}
ERole RoleOf(const string c,int &depth,long &cycle,ulong &parent)
{
   depth=0; cycle=0; parent=0;
   if(ParseMother(c,cycle)) return ROLE_MOTHER;
   if(ParseChild(c,parent,depth)) return ROLE_CHILD;
   return ROLE_NONE;
}
bool ManagedPosition(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=EA_MAGIC) return false;
   int d; long c; ulong p; return RoleOf(PositionGetString(POSITION_COMMENT),d,c,p)!=ROLE_NONE;
}
bool ManagedOrder(const ulong ticket)
{
   if(!OrderSelect(ticket)) return false;
   if(OrderGetString(ORDER_SYMBOL)!=_Symbol) return false;
   if((ulong)OrderGetInteger(ORDER_MAGIC)!=EA_MAGIC) return false;
   int d; long c; ulong p; return RoleOf(OrderGetString(ORDER_COMMENT),d,c,p)!=ROLE_NONE;
}

bool Good(const uint rc)
{ return rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED || rc==TRADE_RETCODE_NO_CHANGES; }
bool RemoveOrder(const ulong ticket)
{
   MqlTradeRequest q; MqlTradeResult r; ZeroMemory(q); ZeroMemory(r);
   q.action=TRADE_ACTION_REMOVE; q.order=ticket; q.magic=EA_MAGIC;
   return OrderSend(q,r) && Good(r.retcode);
}
bool SetSL(const ulong ticket,const double wanted)
{
   if(!PositionSelectByTicket(ticket)) return false;
   ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double sl=(ty==POSITION_TYPE_BUY ? Down(wanted) : Up(wanted));
   double old=PositionGetDouble(POSITION_SL);
   if(MathAbs(sl-old)<TickSize_()*0.5) return true;
   // Never submit a stop which is already on the wrong side of the live
   // Bid/Ask or inside Stops/Freeze distance.  The old version omitted this
   // validation in the mutual-mother path, causing repeated "Invalid stops".
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return false;
   double min=BrokerDistance(), eps=TickSize_()*0.1;
   if(ty==POSITION_TYPE_BUY  && tick.bid-sl < min-eps) return false;
   if(ty==POSITION_TYPE_SELL && sl-tick.ask < min-eps) return false;
   MqlTradeRequest q; MqlTradeResult r; ZeroMemory(q); ZeroMemory(r);
   q.action=TRADE_ACTION_SLTP; q.position=ticket; q.symbol=_Symbol;
   q.magic=EA_MAGIC; q.sl=sl; q.tp=PositionGetDouble(POSITION_TP);
   return OrderSend(q,r) && Good(r.retcode);
}
bool PlaceStop(const ENUM_ORDER_TYPE type,const double wanted,const string comment,ulong &ticket)
{
   ticket=0; MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
   double price=(type==ORDER_TYPE_BUY_STOP ? Up(wanted) : Down(wanted));
   double min=BrokerDistance();
   if(type==ORDER_TYPE_BUY_STOP && price<t.ask+min-TickSize_()*0.1) return false;
   if(type==ORDER_TYPE_SELL_STOP && price>t.bid-min+TickSize_()*0.1) return false;
   MqlTradeRequest q; MqlTradeResult r; MqlTradeCheckResult ck;
   ZeroMemory(q); ZeroMemory(r); ZeroMemory(ck);
   q.action=TRADE_ACTION_PENDING; q.symbol=_Symbol; q.magic=EA_MAGIC;
   q.volume=InpLots; q.type=type; q.price=price; q.deviation=EA_DEVIATION_POINTS;
   q.type_time=ORDER_TIME_GTC; q.type_filling=ORDER_FILLING_RETURN; q.comment=comment;
   if(!OrderCheck(q,ck) || !OrderSend(q,r) || !Good(r.retcode)) return false;
   ticket=r.order; return ticket>0;
}
bool ModifyOrderPrice(const ulong ticket,const double wanted)
{
   if(!OrderSelect(ticket)) return false;
   ENUM_ORDER_TYPE ty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   double price=(ty==ORDER_TYPE_BUY_STOP ? Up(wanted) : Down(wanted));
   if(MathAbs(price-OrderGetDouble(ORDER_PRICE_OPEN))<TickSize_()*0.5) return true;
   MqlTradeRequest q; MqlTradeResult r; ZeroMemory(q); ZeroMemory(r);
   q.action=TRADE_ACTION_MODIFY; q.order=ticket; q.symbol=_Symbol; q.magic=EA_MAGIC;
   q.price=price; q.sl=OrderGetDouble(ORDER_SL); q.tp=OrderGetDouble(ORDER_TP);
   q.stoplimit=OrderGetDouble(ORDER_PRICE_STOPLIMIT);
   q.type_time=(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   q.expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   return OrderSend(q,r) && Good(r.retcode);
}

int ManagedPositionsCount()
{
   int n=0; for(int i=PositionsTotal()-1;i>=0;i--) if(ManagedPosition(PositionGetTicket(i))) n++; return n;
}
int ManagedOrdersCount()
{
   int n=0; for(int i=OrdersTotal()-1;i>=0;i--)
   { ulong x=OrderGetTicket(i); if(ManagedOrder(x)) n++; }
   return n;
}
void DeleteAllManagedOrders()
{
   ulong a[]; ArrayResize(a,0);
   for(int i=OrdersTotal()-1;i>=0;i--) { ulong x=OrderGetTicket(i); if(ManagedOrder(x)) { int z=ArraySize(a); ArrayResize(a,z+1); a[z]=x; } }
   for(int j=0;j<ArraySize(a);j++) RemoveOrder(a[j]);
}
void StartCycle()
{
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
   g_cycle++; if(g_cycle<=0) g_cycle=1;
   double d=P2Price(InpInitialDistancePips); ulong b=0,s=0;
   if(!PlaceStop(ORDER_TYPE_BUY_STOP,t.ask+d,MotherComment(g_cycle),b)) return;
   if(!PlaceStop(ORDER_TYPE_SELL_STOP,t.bid-d,MotherComment(g_cycle),s)) { RemoveOrder(b); return; }
   Print("gpterra cycle ",g_cycle," created. BuyStop=",b," SellStop=",s);
}

// A parent can have exactly one reverse child for its entire life.
string SpawnKey(const ulong parent) { return g_prefix+"spawn."+(string)parent; }
bool Spawned(const ulong parent) { return GlobalVariableCheck(SpawnKey(parent)); }
void MarkSpawned(const ulong parent) { GlobalVariableSet(SpawnKey(parent),1.0); }
bool FindLiveChild(const ulong parent)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong x=PositionGetTicket(i); if(!ManagedPosition(x)) continue;
      ulong p; int d; if(ParseChild(PositionGetString(POSITION_COMMENT),p,d) && p==parent) return true;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong x=OrderGetTicket(i); if(!ManagedOrder(x)) continue;
      ulong p; int d; if(ParseChild(OrderGetString(ORDER_COMMENT),p,d) && p==parent) return true;
   }
   return false;
}
void DeleteOtherMotherPendings(const long cycle,const ulong winner)
{
   ulong a[]; ArrayResize(a,0);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong x=OrderGetTicket(i); if(!ManagedOrder(x)) continue;
      long c; if(ParseMother(OrderGetString(ORDER_COMMENT),c) && c==cycle) { int z=ArraySize(a); ArrayResize(a,z+1); a[z]=x; }
   }
   for(int j=0;j<ArraySize(a);j++) RemoveOrder(a[j]);
}
bool CreateChild(const ulong parent,const int parent_depth,const ENUM_POSITION_TYPE parent_type)
{
   if(!CanSpawnFromDepth(parent_depth) || Spawned(parent) || FindLiveChild(parent)) return false;
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
   SDerivedPlan plan; if(!BuildPlan(parent_depth,plan)) return false;
   double f=P2Price(plan.child_follow_pips); int child_depth=parent_depth+1;
   ENUM_ORDER_TYPE ty=(parent_type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL_STOP : ORDER_TYPE_BUY_STOP);
   double price=(ty==ORDER_TYPE_SELL_STOP ? t.bid-f : t.ask+f); ulong order=0;
   if(!PlaceStop(ty,price,ChildComment(parent,child_depth),order)) return false;
   MarkSpawned(parent);
   Print("gpterra child created. Parent=",parent," depth=",child_depth," order=",order);
   PrintPlan(child_depth);
   return true;
}

// If both original mothers activated, use their ACTUAL fills for exact mutual SL prices.
void ApplyMutualMotherStops()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong a=PositionGetTicket(i); if(!ManagedPosition(a)) continue;
      long cycleA; if(!ParseMother(PositionGetString(POSITION_COMMENT),cycleA)) continue;
      ENUM_POSITION_TYPE ta=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      for(int j=i-1;j>=0;j--)
      {
         ulong b=PositionGetTicket(j); if(!ManagedPosition(b)) continue;
         long cycleB; if(!ParseMother(PositionGetString(POSITION_COMMENT),cycleB) || cycleA!=cycleB) continue;
         ENUM_POSITION_TYPE tb=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(ta==tb) continue;
         double pa=PositionGetDouble(POSITION_PRICE_OPEN), pb=PositionGetDouble(POSITION_PRICE_OPEN), p=P2Price(MotherR());
         if(ta==POSITION_TYPE_BUY) { SetSL(a,pb-p); SetSL(b,pa+p); }
         else                      { SetSL(a,pb+p); SetSL(b,pa-p); }
      }
   }
}
void SetInitialSLIfMissing(const ulong ticket,const int depth,const ERole role)
{
   if(!PositionSelectByTicket(ticket) || PositionGetDouble(POSITION_SL)!=0.0) return;
   ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN), dist;
   SDerivedPlan plan; if(!BuildPlan(depth,plan)) return;
   if(role==ROLE_MOTHER) dist=P2Price(plan.mother_fallback_sl_pips); // temporary fallback until both fills are known
   else dist=P2Price(plan.initial_sl_pips);
   SetSL(ticket,ty==POSITION_TYPE_BUY ? open-dist : open+dist);
}
void ManagePosition(const ulong ticket)
{
   if(!ManagedPosition(ticket)) return;
   string comment=PositionGetString(POSITION_COMMENT); int depth; long cycle; ulong parent;
   ERole role=RoleOf(comment,depth,cycle,parent); if(role==ROLE_NONE) return;
   SetInitialSLIfMissing(ticket,depth,role);
   if(!PositionSelectByTicket(ticket)) return;
   ENUM_POSITION_TYPE ty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN), sl=PositionGetDouble(POSITION_SL);
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
   double fav=(ty==POSITION_TYPE_BUY ? t.bid : t.ask);
   double profit=(ty==POSITION_TYPE_BUY ? t.bid-open : open-t.ask);
   SDerivedPlan plan; if(!BuildPlan(depth,plan)) return;
   double r=P2Price(plan.generation_profit_pips), eps=TickSize_()*0.1;
   if(profit+eps<r) return;
   if(role==ROLE_MOTHER) DeleteOtherMotherPendings(cycle,ticket);
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   CreateChild(id,depth,ty);
   double wanted=(ty==POSITION_TYPE_BUY ? fav-P2Price(plan.trail_distance_pips) : fav+P2Price(plan.trail_distance_pips));
   double min=BrokerDistance();
   if(ty==POSITION_TYPE_BUY)
   {
      wanted=Down(wanted); if(wanted<=sl+eps || t.bid-wanted<min-eps) return;
   }
   else
   {
      wanted=Up(wanted); if((sl>0 && wanted>=sl-eps) || wanted-t.ask<min-eps) return;
   }
   SetSL(ticket,wanted);
}
void ManageChildOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong o=OrderGetTicket(i); if(!ManagedOrder(o)) continue;
      ulong parent; int depth; if(!ParseChild(OrderGetString(ORDER_COMMENT),parent,depth)) continue;
      ulong pt=0;
      for(int j=PositionsTotal()-1;j>=0;j--) { ulong x=PositionGetTicket(j); if(ManagedPosition(x) && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==parent) { pt=x; break; } }
      if(pt==0 || !PositionSelectByTicket(pt)) continue;
      ENUM_POSITION_TYPE pty=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE oty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE); double old=OrderGetDouble(ORDER_PRICE_OPEN);
      MqlTick t; if(!SymbolInfoTick(_Symbol,t)) continue;
      SDerivedPlan parent_plan; if(!BuildPlan(depth-1,parent_plan)) continue;
      double f=P2Price(parent_plan.child_follow_pips), wanted=old;
      if(pty==POSITION_TYPE_BUY && oty==ORDER_TYPE_SELL_STOP) { wanted=Down(t.bid-f); if(wanted<=old+TickSize_()*0.5) continue; }
      else if(pty==POSITION_TYPE_SELL && oty==ORDER_TYPE_BUY_STOP) { wanted=Up(t.ask+f); if(wanted>=old-TickSize_()*0.5) continue; }
      else continue;
      if(oty==ORDER_TYPE_SELL_STOP && t.bid-wanted<BrokerDistance()-TickSize_()*0.1) continue;
      if(oty==ORDER_TYPE_BUY_STOP && wanted-t.ask<BrokerDistance()-TickSize_()*0.1) continue;
      ModifyOrderPrice(o,wanted);
   }
}
void ResetIfNeeded()
{
   if(ManagedPositionsCount()>0) return;
   // Keep a pending initial counterpart while it is still close enough to trigger.
   double reset=P2Price(2.0*InpInitialDistancePips+MotherR());
   MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
   bool far=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong o=OrderGetTicket(i); if(!ManagedOrder(o)) continue;
      ENUM_ORDER_TYPE ty=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE); double p=OrderGetDouble(ORDER_PRICE_OPEN);
      double d=(ty==ORDER_TYPE_BUY_STOP ? MathAbs(p-t.ask) : MathAbs(t.bid-p)); if(d<=reset) far=false;
   }
   if(ManagedOrdersCount()==0 || far) { DeleteAllManagedOrders(); StartCycle(); }
}
bool Compatible(const double p)
{
   double u=P2Price(p)/TickSize_(); return MathAbs(u-MathRound(u))<1e-7;
}
int OnInit()
{
   if(InpLots<=0 || InpInitialDistancePips<=0 || MotherR()<=0 || !Compatible(InpInitialDistancePips) || !Compatible(MotherR())) return INIT_PARAMETERS_INCORRECT;
   if(MotherR()<=8.0*GuardPips()) { Alert("Mother profit trigger is too small for broker guard and dynamic chain."); return INIT_PARAMETERS_INCORRECT; }
   g_prefix="GPTERRA."+_Symbol+"."+(string)EA_MAGIC+".";
   Print("gpterra started. 1 strategy point=0.1 price; guard=",DoubleToString(GuardPips(),3)," pips.");
   Print("gpterra mother plan: initial mutual SL is actual mother gap + P; fallback initial SL=2D+P.");
   PrintPlan(0);
   return INIT_SUCCEEDED;
}
void OnTick()
{
   if(ManagedPositionsCount()==0 && ManagedOrdersCount()==0) StartCycle();
   ApplyMutualMotherStops();
   ulong a[]; ArrayResize(a,0);
   for(int i=PositionsTotal()-1;i>=0;i--) { ulong x=PositionGetTicket(i); if(ManagedPosition(x)) { int z=ArraySize(a); ArrayResize(a,z+1); a[z]=x; } }
   for(int j=0;j<ArraySize(a);j++) ManagePosition(a[j]);
   ManageChildOrders();
   ResetIfNeeded();
}
//+------------------------------------------------------------------+
