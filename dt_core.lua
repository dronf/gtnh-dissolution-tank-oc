-- Pure batch planner/state machine. No component or filesystem dependencies.
local M = {}
local function check(ok, why) if not ok then error(why, 0) end end
local function keys(t) local a={} for k in pairs(t) do a[#a+1]=k end table.sort(a) return a end
M.keys=keys
function M.itemKey(spec)
  check(spec and spec.name and spec.damage ~= nil, 'Missing item identity')
  return spec.name..'@'..tostring(spec.damage)..'#'..(spec.tag or '')
end
function M.resolveItem(entry, bindings)
  local b=bindings.items[entry.key]
  check(b, 'Unbound item: '..entry.key)
  return M.itemKey({name=b.name,damage=entry.damage or b.damage,tag=b.tag})
end
function M.targets(recipe, bindings)
  local t={items={},fluids={},circuit=nil,fluidOrder={}}
  for _,i in ipairs(recipe.items) do
    local k=M.resolveItem(i,bindings); t.items[k]=(t.items[k] or 0)+i.count
  end
  for symbol,n in pairs(recipe.fluids) do
    local name=bindings.fluids[symbol]; check(name,'Unbound fluid: '..symbol)
    check(not t.fluids[name], 'Two material aliases resolve to the same fluid')
    t.fluids[name]=n
  end
  t.fluidOrder=keys(t.fluids)
  check(#t.fluidOrder==2,'Dissolution catalog must have two input fluids')
  if recipe.circuit>0 then t.circuit=M.resolveItem({key='circuit',damage=recipe.circuit},bindings) end
  return t
end
local function factor(actual, wanted, current)
  for k,n in pairs(actual) do if n>0 and not wanted[k] then return nil end end
  for k,n in pairs(wanted) do
    local a=actual[k] or 0
    if a<n or a%n~=0 then return nil end
    local f=a/n
    if current and current~=f then return nil end
    current=f
  end
  return current
end
-- Strict matching: all staging contents must be one recipe's integral multiple.
function M.match(stage, recipes, bindings, cfg)
  local matches={}
  for _,r in ipairs(recipes) do
    if r.eut<=cfg.maxEUt and (not cfg.onlyRecipe or cfg.onlyRecipe==r.id) then
      local ok,t=pcall(M.targets,r,bindings)
      if ok then
        local k=factor(stage.fluids,t.fluids,nil)
        if k and factor(stage.items,t.items,k)==k then matches[#matches+1]={recipe=r,batches=k} end
      end
    end
  end
  if #matches==1 then return matches[1] end
  if #matches>1 and cfg.preferCircuit then
    local preferred={}
    for _,m in ipairs(matches) do if m.recipe.circuit==cfg.preferCircuit then preferred[#preferred+1]=m end end
    if #preferred==1 then return preferred[1] end
  end
  local names={} for _,m in ipairs(matches) do names[#names+1]=m.recipe.id end
  return nil,#matches==0 and 'Waiting for a complete, bound recipe; staging may contain mixed/partial inputs'
    or ('Ambiguous recipes: '..table.concat(names,', ')..'; set onlyRecipe or preferCircuit')
end
local function exact(a,b)
  for k,v in pairs(a) do if v>0 and v~=(b[k] or 0) then return false end end
  for k,v in pairs(b) do if v~=(a[k] or 0) then return false end end
  return true
end
local function empty(t) for _,v in pairs(t) do if v>0 then return false end end return true end
M.empty=empty
function M.managesOutputs(io) return io.outputMode~='external' end
local function circuitMap(t) return t.circuit and {[t.circuit]=1} or {} end
local function allItems(t)
  local a={} for k,n in pairs(t.items) do a[k]=n end
  if t.circuit then a[t.circuit]=(a[t.circuit] or 0)+1 end return a
end
local function validateFluidDest(input,t)
  for name,n in pairs(input.fluids) do
    check(t.fluids[name] and n<=t.fluids[name], 'Unexpected/excess fluid in machine inputs')
  end
  for index,name in ipairs(t.fluidOrder) do
    local d=input.tanks[index]
    check(d and d.capacity>=t.fluids[name],'Input hatch '..index..' is too small')
    check(not d.name or d.amount==0 or d.name==name,'Wrong fluid in input hatch '..index)
    check((d.amount or 0)<=t.fluids[name],'Too much fluid in input hatch '..index)
  end
end
function M.preflight(io)
  local x=io:inputs()
  check(empty(x.items) and empty(x.fluids),'Input bus/hatches must be empty before a new transaction')
  if M.managesOutputs(io) then
    local o=io:outputs()
    check(empty(o.items) and o.amount==0,'Output bus/hatch must be empty before a new transaction')
  end
end
-- Caller must persist job before each invocation. Transfers are reconciled by reading the machine.
function M.step(io, job, recipe, bindings)
  local t=M.targets(recipe,bindings)
  if io.setTargets then io:setTargets(t) end
  local input=io:inputs()
  if job.phase~='armed' then io:enable(false) end
  if job.phase=='fluids' then
    check(empty(input.items),'Items/circuit appeared before fluid loading finished')
    validateFluidDest(input,t)
    for index,name in ipairs(t.fluidOrder) do
      local need=t.fluids[name]-(input.tanks[index].amount or 0)
      if need>0 then io:fillFluid(name,need,index);return 'Loading '..name end
    end
    check(exact(input.fluids,t.fluids),'Fluid totals differ from the recipe')
    job.phase='items';return 'Fluids verified'
  elseif job.phase=='items' then
    check(exact(input.fluids,t.fluids),'Fluids changed while loading items')
    for k,n in pairs(input.items) do check(t.items[k] and n<=t.items[k],'Unexpected/excess input item') end
    for _,k in ipairs(keys(t.items)) do
      local need=t.items[k]-(input.items[k] or 0)
      if need>0 then io:fillItem(k,need);return 'Loading consumed item' end
    end
    job.phase='circuit';return 'Consumed items verified'
  elseif job.phase=='circuit' then
    check(exact(input.fluids,t.fluids),'Fluids changed before circuit insertion')
    local wanted=allItems(t)
    for k,n in pairs(input.items) do check(wanted[k] and n<=wanted[k],'Unexpected/excess bus contents') end
    for k,n in pairs(t.items) do check(input.items[k]==n,'Consumed ingredients changed') end
    if t.circuit and not input.items[t.circuit] then io:insertCircuit(recipe.circuit,t.circuit);return 'Inserting reusable circuit last' end
    check(exact(input.items,wanted),'Bus does not match complete recipe')
    job.phase='armed';return 'Ready to commit'
  elseif job.phase=='armed' then
    if empty(input.fluids) and exact(input.items,circuitMap(t)) then
      io:enable(false)
      if not M.managesOutputs(io) then
        job.phase='return';return 'Batch accepted; outputs handled externally'
      end
      job.phase='result';return 'Batch consumed; waiting for output'
    end
    check(exact(input.fluids,t.fluids) and exact(input.items,allItems(t)),
      'Inputs changed unexpectedly at commit; inspect machine before resuming')
    io:enable(true);return 'Waiting for machine to start'
  elseif job.phase=='result' then
    check(empty(input.fluids) and exact(input.items,circuitMap(t)),'Input contents changed during processing')
    local o=io:outputs()
    check(o.amount<=recipe.outputAmount,'Unexpected output fluid quantity')
    if o.amount==recipe.outputAmount then job.phase='drain';return 'Fluid output confirms completion' end
    return 'Processing / waiting for power, maintenance, or output'
  elseif job.phase=='drain' then
    check(empty(input.fluids) and exact(input.items,circuitMap(t)),'Inputs changed while draining outputs')
    local o=io:outputs()
    if o.amount>0 or not empty(o.items) then io:drainOutput();return 'Draining outputs' end
    job.phase='return';return 'Outputs cleared'
  elseif job.phase=='return' then
    check(empty(input.fluids),'Input fluid remained after completion')
    if t.circuit and input.items[t.circuit] then
      check(exact(input.items,circuitMap(t)),'Unexpected items alongside circuit')
      io:returnCircuit(recipe.circuit,t.circuit);return 'Returning reusable circuit'
    end
    check(empty(input.items),'Unexpected item remained in input bus')
    if t.circuit then check(io:circuitHome(recipe.circuit,t.circuit),'Reusable circuit is missing from its locker') end
    job.phase='complete'
    return M.managesOutputs(io) and 'Batch complete' or 'Input handoff complete; production/export not observed'
  elseif job.phase=='complete' then
    M.preflight(io);return 'Batch complete'
  end
  error('Unknown journal phase: '..tostring(job.phase),0)
end
return M
