local core=require('dt_core')
local recipes=require('recipes')
local checks=0
local function eq(a,b,msg) checks=checks+1;assert(a==b,(msg or '')..' expected '..tostring(a)..' got '..tostring(b)) end
local function copy(x) if type(x)~='table' then return x end local o={} for k,v in pairs(x) do o[k]=copy(v) end return o end
local function add(t,k,n) t[k]=(t[k] or 0)+n;if t[k]==0 then t[k]=nil end end
local bindings={items={},fluids={}}
for _,r in ipairs(recipes) do
 for _,i in ipairs(r.items) do bindings.items[i.key]={name='test:'..i.key,damage=0,tag=''} end
 for f in pairs(r.fluids) do bindings.fluids[f]='test:'..f end
end
bindings.items.circuit={name='test:circuit',damage=1,tag=''}
local Fake={};Fake.__index=Fake
function Fake.new(r)
 local t=core.targets(r,bindings)
 return setmetatable({r=r,target=t,items={},fluids={},stageItems=copy(t.items),stageFluids=copy(t.fluids),
   locker={[1]=1,[9]=1},outItems={},outAmount=0,running=0,starts=0,inserts=0,returns=0,enabled=false},Fake)
end
function Fake:setTargets(t) self.target=t end
function Fake:inputs()
 local t={}
 for i,k in ipairs(self.target.fluidOrder) do t[i]={name=self.fluids[k] and k or nil,amount=self.fluids[k] or 0,capacity=128000} end
 return {items=copy(self.items),fluids=copy(self.fluids),tanks=t}
end
function Fake:outputs() return {items=copy(self.outItems),amount=self.outAmount,capacity=128000} end
function Fake:enable(value)
 self.enabled=value
 if value and not self.pauseStart then
   eq(self.running,0,'started while previous recipe running')
   for k,n in pairs(self.target.fluids) do eq(self.fluids[k],n,'wrong ratio at start') end
   for k,n in pairs(self.target.items) do eq(self.items[k],n,'wrong item at start') end
   if self.target.circuit then eq(self.items[self.target.circuit],1,'missing reusable circuit') end
   self.starts=self.starts+1;eq(self.starts,1,'duplicate batch started')
   self.fluids={};for k,n in pairs(self.target.items) do add(self.items,k,-n) end
   self.running=7
 end
end
function Fake:progress()
 if self.running>0 then
   self.running=self.running-1
   if self.running==0 then self.outAmount=self.r.outputAmount;self.outItems.byproduct=3 end
 end
end
function Fake:fillFluid(name,need)
 eq(self.enabled,false,'fluid moved while start signal on');eq(core.empty(self.items),true,'item went before fluid')
 local n=math.min(need,self.stageFluids[name] or 0,137)
 add(self.stageFluids,name,-n);add(self.fluids,name,n)
end
function Fake:fillItem(key,need)
 eq(self.enabled,false)
 for k,n in pairs(self.target.fluids) do eq(self.fluids[k],n,'item sent before exact fluids') end
 local n=math.min(need,self.stageItems[key] or 0,3);add(self.stageItems,key,-n);add(self.items,key,n)
end
function Fake:insertCircuit(number,key)
 eq(self.enabled,false);eq(self.locker[number],1);eq(self.items[key],nil)
 self.items[key]=1;self.locker[number]=0;self.inserts=self.inserts+1
end
function Fake:returnCircuit(number,key)
 eq(self.enabled,false);eq(self.items[key],1);eq(self.locker[number],0)
 self.items[key]=nil;self.locker[number]=1;self.returns=self.returns+1
end
function Fake:circuitHome(number) return self.locker[number]==1 end
function Fake:drainOutput()
 eq(self.running,0);eq(self.enabled,false)
 if self.outAmount>0 then self.outAmount=self.outAmount-math.min(self.outAmount,157)
 else self.outItems={} end
end
local function execute(r,rebootPhase)
 local io=Fake.new(r);core.preflight(io)
 local job={recipe=r.id,phase='fluids'};local rebooted=false;local loops=0
 while job.phase~='complete' do
  loops=loops+1;assert(loops<5000,'stalled '..r.id)
  io:progress()
  local durable=copy(job)
  core.step(io,job,r,bindings)
  -- Power loss after an operation but before its new phase was saved.
  if not rebooted and durable.phase==rebootPhase then job=durable;io:enable(false);rebooted=true end
 end
 core.preflight(io)
 eq(io.starts,1,r.id);eq(io.locker[1],1);eq(io.locker[9],1)
 eq(io.inserts,r.circuit>0 and 1 or 0);eq(io.returns,r.circuit>0 and 1 or 0)
 eq(core.empty(io.stageItems),true);eq(core.empty(io.stageFluids),true)
 return io
end
eq(#recipes,33)
local cfg={maxEUt=7680,preferCircuit=9}
for _,r in ipairs(recipes) do
 local t=core.targets(r,bindings)
 local m,why=core.match({items=t.items,fluids=t.fluids},recipes,bindings,cfg)
 assert(m,why);eq(m.recipe.id,r.id,'automatic recognition');eq(m.batches,1)
 for _,phase in ipairs({'none','fluids','items','circuit','armed','result','drain','return'}) do execute(r,phase) end
end
-- Nine small monazite batches are ambiguous with one large batch; the documented preference resolves it.
local small=recipes[1];local t=core.targets(small,bindings)
local lot={items={},fluids={}}
for k,n in pairs(t.items) do lot.items[k]=n*9 end
for k,n in pairs(t.fluids) do lot.fluids[k]=n*9 end
local m=core.match(lot,recipes,bindings,cfg);eq(m.recipe.id,'monazite_9')
eq(core.match(lot,recipes,bindings,{maxEUt=7680}),nil,'ambiguous selection must stop')
cfg.onlyRecipe='monazite_1';eq(core.match(lot,recipes,bindings,cfg).batches,9);cfg.onlyRecipe=nil
lot.fluids.garbage=1;eq(core.match(lot,recipes,bindings,cfg),nil,'mixed fluids must stop')
lot.fluids.garbage=nil;lot.items.garbage=1;eq(core.match(lot,recipes,bindings,cfg),nil,'mixed items must stop')
-- Wrong and excess machine fluids must stop BEFORE adding items/circuit or enabling the machine.
local bad=Fake.new(recipes[8]);bad.fluids.garbage=1
eq(pcall(core.step,bad,{phase='fluids'},recipes[8],bindings),false);eq(bad.starts,0);eq(bad.inserts,0)
local over=Fake.new(recipes[8]);local name=over.target.fluidOrder[1];over.fluids[name]=over.target.fluids[name]+1
eq(pcall(core.step,over,{phase='fluids'},recipes[8],bindings),false)
-- Delayed/zero transfers never advance past the incomplete fluid stage.
local stalled=Fake.new(recipes[4]);stalled.stageFluids={};local job={phase='fluids'}
for n=1,50 do core.step(stalled,job,recipes[4],bindings) end
eq(job.phase,'fluids');eq(stalled.inserts,0);eq(stalled.starts,0)
local dirty=Fake.new(recipes[1]);dirty.items.unknown=1;eq(pcall(core.preflight,dirty),false)
local dirtyOut=Fake.new(recipes[1]);dirtyOut.outAmount=1;eq(pcall(core.preflight,dirtyOut),false)
-- Circuit-only input recipes leave the circuit, and are recognized as started only after BOTH fluids vanish.
local circ=Fake.new(recipes[4]);circ.pauseStart=true;local cj={phase='fluids'}
for n=1,100 do core.step(circ,cj,recipes[4],bindings);if cj.phase=='armed' then break end end
eq(cj.phase,'armed');circ.fluids[circ.target.fluidOrder[1]]=nil
eq(pcall(core.step,circ,cj,recipes[4],bindings),false,'partial consumption must halt')
print('PASS: '..checks..' assertions; all 33 recipes, 8 interruption positions each, circuit round trips, strict matching, partial transfers, and fail-closed faults.')
return {checks=checks,bindings=bindings,Fake=Fake,getChecks=function()return checks end}
