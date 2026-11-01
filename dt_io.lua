local component=require('component')
local sides=require('sides')
local core=require('dt_core')
local M={}
local function check(ok,msg) if not ok then error(msg,0) end end
local function canon(x)
  if type(x)~='table' then return type(x)..':'..tostring(x) end
  local a={} local kk={} for k in pairs(x) do kk[#kk+1]=k end
  table.sort(kk,function(a,b)return tostring(a)<tostring(b) end)
  for _,k in ipairs(kk) do a[#a+1]=canon(k)..'='..canon(x[k]) end
  return '{'..table.concat(a,',')..'}'
end
function M.identity(stack)
  if not stack then return nil end
  check(stack.name and stack.damage~=nil,'Item inspection is disabled or incomplete')
  check(not stack.hasTag or stack.tag~=nil,'Tagged item needs visible NBT; do not bind it using hidden NBT')
  return {name=stack.name,damage=stack.damage,tag=stack.tag and canon(stack.tag) or '',label=stack.label}
end
local function proxy(prefix,kind)
  local matches={}
  for a in component.list(kind) do if a:sub(1,#prefix)==prefix then matches[#matches+1]=a end end
  check(#matches==1,'Address must identify exactly one '..kind..': '..tostring(prefix))
  return component.proxy(matches[1])
end
local function side(s) local n=type(s)=='number' and s or sides[s];check(n~=nil,'Invalid side '..tostring(s));return n end
local function sum(items)
  local t={} for _,s in ipairs(items) do if s.size>0 then t[s.key]=(t[s.key] or 0)+s.size end end return t
end
local function slots(tp,s)
  local n,why=tp.getInventorySize(s);check(n,'Cannot inspect inventory: '..tostring(why))
  local a={}
  for i=1,n do
    local stack,err=tp.getStackInSlot(s,i)
    check(not err,'Cannot inspect inventory slot: '..tostring(err))
    if stack and stack.name then
      local id=M.identity(stack)
      a[#a+1]={slot=i,key=core.itemKey(id),size=stack.size or 0,label=stack.label,identity=id}
    end
  end
  return a,n
end
local function tanks(tp,s)
  local n,why=tp.getTankCount(s);check(n,'Cannot inspect tanks: '..tostring(why))
  local all,err=tp.getFluidInTank(s);check(type(all)=='table','Cannot inspect fluid data: '..tostring(err))
  local a={}
  for i=1,n do
    local x=all[i];check(type(x)=='table','Missing tank '..i)
    a[i]={index=i,name=x.name,amount=x.amount or 0,capacity=x.capacity or 0,label=x.label}
  end
  return a
end
local function fluids(a)
  local t={} for _,x in ipairs(a) do if x.amount>0 then check(x.name,'Fluid has no registry name');t[x.name]=(t[x.name] or 0)+x.amount end end return t
end
function M.new(cfg,bindings)
  local self={cfg=cfg,bindings=bindings,outputMode=cfg.outputMode or 'managed'}
  check(self.outputMode=='external' or self.outputMode=='managed','outputMode must be external or managed')
  local roles={'inputFluids','inputItems'}
  if self.outputMode=='managed' then roles[#roles+1]='outputFluids';roles[#roles+1]='outputItems' end
  for _,role in ipairs(roles) do
    check(type(cfg[role])=='table','Missing component configuration: '..role)
    self[role]={tp=proxy(cfg[role].address,'transposer')}
    for k,v in pairs(cfg[role]) do if k~='address' then self[role][k]=side(v) end end
  end
  self.redstone=proxy(cfg.redstone.address,'redstone');self.redstoneSide=side(cfg.redstone.side)
  check(cfg.consumedSlot~=cfg.circuitSlot,'Consumed-item and reusable-circuit slots must differ')
  return setmetatable(self,{__index=M})
end
function M:enable(value) self.redstone.setOutput(self.redstoneSide,value and 15 or 0) end
function M:setTargets(t) self.target=t end
function M:stage()
  local i=self.inputItems;local f=self.inputFluids
  return {items=sum(slots(i.tp,i.stageSide)),fluids=fluids(tanks(f.tp,f.stageSide))}
end
function M:inputs()
  local i=self.inputItems;local f=self.inputFluids
  local a,n=slots(i.tp,i.machineSide)
  check(self.cfg.consumedSlot<=n and self.cfg.circuitSlot<=n,'Configured bus slot does not exist')
  for _,s in ipairs(a) do
    check(s.slot==self.cfg.consumedSlot or s.slot==self.cfg.circuitSlot,
      'Clear all other bus slots, including the dedicated ghost-circuit slot (slot '..s.slot..')')
  end
  local raw=tanks(f.tp,f.machineSide);local total=fluids(raw);local virtual={}
  if self.target then
    local used={}
    for index,name in ipairs(self.target.fluidOrder) do
      local found
      for k,x in ipairs(raw) do if x.amount>0 and x.name==name then
        check(not found,'Same fluid appears in multiple machine compartments');found=x;used[k]=true
      end end
      if not found then
        for k,x in ipairs(raw) do if x.amount==0 and not used[k] then found=x;used[k]=true;break end end
      end
      check(found,'No free machine fluid compartment')
      virtual[index]={name=found.amount>0 and found.name or nil,amount=found.amount,capacity=found.capacity}
    end
  else virtual=raw end
  return {items=sum(a),fluids=total,tanks=virtual,rawTanks=raw,slots=a}
end
function M:outputs()
  check(self.outputMode=='managed','External output mode does not inspect machine outputs')
  local f=self.outputFluids;local i=self.outputItems
  local a=tanks(f.tp,f.machineSide);check(#a==1,'Use one ordinary machine Output Hatch')
  return {items=sum(slots(i.tp,i.machineSide)),amount=a[1].amount,name=a[1].name,capacity=a[1].capacity}
end
function M:fillFluid(name,need)
  local f=self.inputFluids
  for _,x in ipairs(tanks(f.tp,f.stageSide)) do if x.name==name and x.amount>0 then
    local _,moved=f.tp.transferFluid(f.stageSide,f.machineSide,math.min(need,x.amount,self.cfg.fluidChunk),x.index-1+self.cfg.sourceTankBase)
    check(type(moved)=='number','Fluid transfer failed: '..tostring(moved));return moved
  end end
  return 0
end
function M:fillItem(key,need)
  local i=self.inputItems
  for _,s in ipairs(slots(i.tp,i.stageSide)) do if s.key==key and s.size>0 then
    local moved,why=i.tp.transferItem(i.stageSide,i.machineSide,math.min(need,s.size,self.cfg.itemChunk),s.slot,self.cfg.consumedSlot)
    check(type(moved)=='number','Item transfer failed: '..tostring(why));return moved
  end end
  return 0
end
function M:locker(number)
  local i=self.inputItems;local slot=self.cfg.circuitLockerSlots[number]
  check(slot,'No locker slot configured for circuit '..number)
  local stack=i.tp.getStackInSlot(i.lockerSide,slot)
  if not stack then return nil,slot end
  return {key=core.itemKey(M.identity(stack)),size=stack.size or 0},slot
end
function M:circuitHome(number,key)
  local s=self:locker(number);return s and s.key==key and s.size==1
end
function M:insertCircuit(number,key)
  local i=self.inputItems;local s,slot=self:locker(number)
  check(s and s.key==key and s.size==1,'Put exactly one correctly programmed circuit in its locker slot')
  check(not i.tp.getStackInSlot(i.machineSide,self.cfg.circuitSlot),'Circuit destination slot is occupied')
  local moved=i.tp.transferItem(i.lockerSide,i.machineSide,1,slot,self.cfg.circuitSlot)
  check(moved==1,'Could not insert reusable circuit into an ordinary bus slot')
end
function M:returnCircuit(number,key)
  local i=self.inputItems;local home,slot=self:locker(number)
  check(not home,'Circuit locker return slot is occupied')
  local s=i.tp.getStackInSlot(i.machineSide,self.cfg.circuitSlot)
  check(s and core.itemKey(M.identity(s))==key and s.size==1,'Reusable circuit is not in the configured bus slot')
  check(i.tp.transferItem(i.machineSide,i.lockerSide,1,self.cfg.circuitSlot,slot)==1,'Could not return reusable circuit')
end
function M:drainOutput()
  check(self.outputMode=='managed','External output mode does not drain machine outputs')
  local f=self.outputFluids;local i=self.outputItems
  local a=tanks(f.tp,f.machineSide)
  if a[1].amount>0 then
    local _,n=f.tp.transferFluid(f.machineSide,f.storeSide,math.min(a[1].amount,self.cfg.fluidChunk),self.cfg.sourceTankBase)
    check(type(n)=='number','Output fluid transfer failed: '..tostring(n));return n
  end
  for _,s in ipairs(slots(i.tp,i.machineSide)) do if s.size>0 then
    local n,why=i.tp.transferItem(i.machineSide,i.storeSide,s.size,s.slot)
    check(type(n)=='number','Output item transfer failed: '..tostring(why));return n
  end end
  return 0
end
function M:capacityCheck()
  local a=tanks(self.inputFluids.tp,self.inputFluids.machineSide)
  check(#a>=2,'Machine input must expose at least two compartments (recommended: LuV Quad Input Hatch)')
  for _,t in ipairs(a) do check(t.capacity>=90000,'Every machine input compartment must hold at least 90,000 L for all 33 recipes') end
  if self.outputMode=='managed' then
    check(self:outputs().capacity>=99000,'Machine Output Hatch must hold at least 99,000 L')
  end
  check(self.cfg.maxEUt>=7680,'All 33 recipes require an IV-capable energy supply; maxEUt is too low')
end
function M:scan()
  for role,e in pairs({inputFluids=self.inputFluids,outputFluids=self.outputFluids}) do
    for _,field in ipairs(role=='inputFluids' and {'stageSide','machineSide'} or {'machineSide','storeSide'}) do
      print(role..'.'..field)
      for _,t in ipairs(tanks(e.tp,e[field])) do print(t.index,t.name or '(empty)',t.amount,'/',t.capacity) end
    end
  end
  for role,e in pairs({inputItems=self.inputItems,outputItems=self.outputItems}) do
    for _,field in ipairs(role=='inputItems' and {'stageSide','machineSide','lockerSide'} or {'machineSide','storeSide'}) do
      print(role..'.'..field)
      local a,n=slots(e.tp,e[field]);print('Inventory slots:',n)
      for _,s in ipairs(a) do print(s.slot,s.label or s.key,s.size,s.key) end
    end
  end
end
function M:sampleItem(slot)
  local e=self.inputItems;local s=e.tp.getStackInSlot(e.stageSide,slot)
  check(s and s.size>0,'No sample in staging chest slot '..slot);return M.identity(s)
end
function M:sampleFluid(index)
  local e=self.inputFluids;local a=tanks(e.tp,e.stageSide)
  check(a[index] and a[index].name and a[index].amount>0,'No fluid in staging compartment '..index)
  return a[index].name
end
function M:probe(index)
  local e=self.inputFluids;local src=tanks(e.tp,e.stageSide)
  check(src[index] and src[index].amount>0,'Select a nonempty staging compartment')
  local before=fluids(tanks(e.tp,e.machineSide));check(core.empty(before),'Machine fluid input must be empty for probe')
  local ok,n=e.tp.transferFluid(e.stageSide,e.machineSide,1,index-1+self.cfg.sourceTankBase)
  check(ok and n==1,'Probe moved nothing: check extraction sides/covers/sourceTankBase')
  local actual=fluids(tanks(e.tp,e.machineSide))
  check(actual[src[index].name]==1 and #core.keys(actual)==1,'Wrong probe fluid: isolate machine and correct sourceTankBase')
  -- Return the one measured unit; rescan because the multi-tank slot may change after emptying.
  local raw=tanks(e.tp,e.machineSide);local source
  for _,t in ipairs(raw) do if t.amount>0 then source=t.index end end
  local _,back=e.tp.transferFluid(e.machineSide,e.stageSide,1,source-1+self.cfg.sourceTankBase)
  check(back==1 and core.empty(fluids(tanks(e.tp,e.machineSide))),'Probe unit remains in machine; remove it before commissioning')
  print('Probe passed: '..src[index].name..'; transferred and returned exactly 1 L')
end
return M
