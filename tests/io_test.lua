-- Exercise the real dt_io driver through mocked OpenComputers component APIs.
local core=require('dt_core');local recipes=require('recipes')
local componentMap={};local checks=0
local function eq(a,b) checks=checks+1;assert(a==b,tostring(a)..' != '..tostring(b)) end
local function clone(a) if type(a)~='table' then return a end local b={} for k,v in pairs(a) do b[k]=clone(v) end return b end
package.loaded.component={
 list=function(kind)
  local a={} for address,p in pairs(componentMap) do if p.kind==kind then a[#a+1]=address end end
  table.sort(a);local n=0;return function()n=n+1;return a[n] end
 end,
 proxy=function(a)return assert(componentMap[a])end
}
package.loaded.sides={down=0,up=1,north=2,south=3,west=4,east=5}
package.loaded.dt_io=nil;local driver=require('dt_io')
local bindings={items={},fluids={}}
for _,r in ipairs(recipes) do
 for _,i in ipairs(r.items) do bindings.items[i.key]={name='test:'..i.key,damage=0,tag=''} end
 for f in pairs(r.fluids) do bindings.fluids[f]='test:'..f end
end
bindings.items.circuit={name='test:circuit',damage=1,tag=''}
local cfg={
 inputFluids={address='fluid-in',stageSide='up',machineSide='north'},
 inputItems={address='item-in',stageSide='up',machineSide='north',lockerSide='west'},
 outputFluids={address='fluid-out',machineSide='north',storeSide='up'},
 outputItems={address='item-out',machineSide='north',storeSide='up'},
 redstone={address='rs',side='east'},consumedSlot=1,circuitSlot=2,
 circuitLockerSlots={[1]=1,[9]=2},sourceTankBase=0,fluidChunk=1000,itemChunk=64,maxEUt=7680
}
local function inv(n)return {n=n}end
local function tankArray(n)
 local a={} for i=1,n do a[i]={amount=0,capacity=128000} end return a
end
local function makePlatform(r,outputMode,options)
 local options=options or {}
 local targets=core.targets(r,bindings)
 local c={stageI=inv(options.stageSlots or 27),bus=inv(5),locker=inv(27),outBus=inv(4),chest=inv(27),
  stageF=tankArray(4),input=tankArray(4),output=tankArray(1),store=tankArray(4),running=0,starts=0,
  stats={slotReads=0,snapshots=0,redstoneWrites=0,fluidMoves=0,itemMoves=0}}
 local function stack(key,n)
  local name,damage=key:match('^(.-)@(%d+)#');return {name=name,damage=tonumber(damage),size=n,hasTag=false}
 end
 for key,n in pairs(targets.items) do c.stageI[1]=stack(key,n) end
 for _,n in ipairs({1,9}) do c.locker[n==1 and 1 or 2]=stack(core.resolveItem({key='circuit',damage=n},bindings),1) end
 -- Use nonconsecutive source tank positions; the driver must rescan/select the right compartment.
 c.stageF[4].name=targets.fluidOrder[1];c.stageF[4].amount=targets.fluids[targets.fluidOrder[1]]
 c.stageF[2].name=targets.fluidOrder[2];c.stageF[2].amount=targets.fluids[targets.fluidOrder[2]]
 if options.stageTankCapacity then
  local staged={}
  for _,tank in ipairs(c.stageF) do if tank.amount>0 then staged[#staged+1]={name=tank.name,amount=tank.amount} end end
  for _,tank in ipairs(c.stageF) do tank.name=nil;tank.amount=0;tank.capacity=options.stageTankCapacity end
  local index=1
  for _,fluid in ipairs(staged) do
   local remaining=fluid.amount
   while remaining>0 do
    local tank=assert(c.stageF[index],'staging capacity exceeded')
    tank.name=fluid.name;tank.amount=math.min(remaining,tank.capacity);remaining=remaining-tank.amount;index=index+1
   end
  end
 end
 local function itemTP(map)
  local tp={kind='transposer',
   getInventorySize=function(side)return assert(map[side]).n end,
   getStackInSlot=function(side,slot)c.stats.slotReads=c.stats.slotReads+1;return clone(assert(map[side])[slot]) end,
   transferItem=function(from,to,count,src,dst)
    c.stats.itemMoves=c.stats.itemMoves+1
    local a,b=assert(map[from]),assert(map[to]);local s=a[src];if not s then return 0 end
    if not dst then for i=1,b.n do if not b[i] then dst=i;break end end end
    if not dst then return 0 end
    if b[dst] and core.itemKey(driver.identity(b[dst]))~=core.itemKey(driver.identity(s)) then return 0 end
    local n=math.min(count,s.size,options.itemLimit or 7,64-(b[dst] and b[dst].size or 0))
    if n<=0 then return 0 end
    if not b[dst] then b[dst]=clone(s);b[dst].size=0 end
    b[dst].size=b[dst].size+n;s.size=s.size-n;if s.size==0 then a[src]=nil end
    return n
   end}
  if options.snapshots then
   tp.getAllStacks=function(side)
    c.stats.snapshots=c.stats.snapshots+1
    local inventory=assert(map[side]);local snapshot={}
    for index=1,inventory.n do snapshot[index-1]=clone(inventory[index] or {}) end
    return {getAll=function()return snapshot end}
   end
  end
  return tp
 end
 local function fluidTP(map)
  return {kind='transposer',getTankCount=function(s)return #assert(map[s])end,
   getFluidTransferRate=function()return options.rate or 2560 end,
   getFluidInTank=function(s)return clone(assert(map[s]))end,
   transferFluid=function(from,to,count,sourceTank)
    c.stats.fluidMoves=c.stats.fluidMoves+1
    local a,b=assert(map[from]),assert(map[to]);local s=a[sourceTank+1]
    if not s or s.amount==0 then return false,0 end
    local sink
    for _,t in ipairs(b) do if t.amount>0 and t.name==s.name then sink=t;break end end
    if not sink then for _,t in ipairs(b) do if t.amount==0 then sink=t;break end end end
    if not sink then return false,0 end
    local n=math.min(count,s.amount,options.fluidLimit or 511,sink.capacity-sink.amount)
    if n<=0 then return false,0 end
    sink.name=s.name;sink.amount=sink.amount+n;s.amount=s.amount-n;if s.amount==0 then s.name=nil end
    return true,n
   end}
 end
 componentMap={['fluid-in']=fluidTP({[1]=c.stageF,[2]=c.input}),['fluid-out']=fluidTP({[2]=c.output,[1]=c.store}),
  ['item-in']=itemTP({[1]=c.stageI,[2]=c.bus,[4]=c.locker}),['item-out']=itemTP({[2]=c.outBus,[1]=c.chest})}
 local function startBatch()
  local anyFluid=false for _,t in ipairs(c.input) do if t.amount>0 then anyFluid=true end end
  if c.running==0 and anyFluid then
   c.starts=c.starts+1;eq(c.starts,1)
   for name,n in pairs(targets.fluids) do local total=0 for _,t in ipairs(c.input) do if t.name==name then total=total+t.amount end end eq(total,n) end
   if targets.circuit then eq(core.itemKey(driver.identity(c.bus[2])),targets.circuit);eq(c.bus[2].size,1) else eq(c.bus[2],nil) end
   c.bus[1]=nil;for _,t in ipairs(c.input) do t.amount=0;t.name=nil end;c.running=c.duration or 5
  end
 end
 componentMap.rs={kind='redstone',setOutput=function(_,signal)
  c.stats.redstoneWrites=c.stats.redstoneWrites+1;c.signal=signal
  if signal>0 then startBatch() end
 end}
 function c:progress()
  if self.running>0 then self.running=self.running-1;if self.running==0 then
   self.output[1].amount=r.outputAmount;self.output[1].name='test:product';self.outBus[1]={name='test:byproduct',damage=0,size=3,hasTag=false}
   if self.signal and self.signal>0 then startBatch() end
  end end
 end
 local config=clone(cfg)
 if options.auto then config.fluidChunk='auto';config.pollSeconds='auto';config.idlePollSeconds=0.5 end
 if outputMode=='external' then
  config.outputMode='external';config.outputFluids=nil;config.outputItems=nil
  componentMap['fluid-out']=nil;componentMap['item-out']=nil
 end
 return c,driver.new(config,bindings),targets
end
for _,r in ipairs(recipes) do
 local platform,io,t=makePlatform(r);io:capacityCheck();core.preflight(io)
 local stage=io:stage()
 for k,n in pairs(t.fluids) do eq(stage.fluids[k],n) end
 local job={phase='fluids'}
 for n=1,3000 do platform:progress();core.step(io,job,r,bindings);if job.phase=='complete' then break end end
 eq(job.phase,'complete');eq(platform.starts,1);core.preflight(io)
 eq(io:circuitHome(1,core.resolveItem({key='circuit',damage=1},bindings)),true)
 eq(io:circuitHome(9,core.resolveItem({key='circuit',damage=9},bindings)),true)
 eq(platform.store[1].amount,r.outputAmount);eq(platform.chest[1].size,3)
end
local p,io=makePlatform(recipes[8])
-- Extra/ghost slots must be detected even when their displayed count is zero.
p.bus[5]={name='test:circuit',damage=9,size=0,hasTag=false};eq(pcall(function()io:inputs()end),false)
p.bus[5]=nil;p.input[1].capacity=64000;eq(pcall(function()io:capacityCheck()end),false)
p.input[1].capacity=128000
-- Commissioning probe uses the real driver to select a non-first compartment, then returns the unit.
io:probe(2);eq(core.empty(io:inputs().fluids),true)
local original=clone(p.stageF)
io.cfg.sourceTankBase=1;eq(pcall(function()io:probe(2)end),false)
eq(p.stageF[2].amount,original[2].amount)
print('PASS: real OC I/O driver, all 33 recipes, '..checks..' assertions, quad source/destination selection, circuits, output drains, protected slots, capacity and API probe.')
return {checks=checks,makePlatform=makePlatform,bindings=bindings,getChecks=function()return checks end}
