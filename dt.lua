local argv={...};local command=argv[1] or 'help'
-- Component discovery must work before any files or addresses are configured.
if command=='components' then
  local component=require('component')
  for _,kind in ipairs({'transposer','redstone'}) do for a in component.list(kind) do print(kind,a) end end
  return
end
local filesystem=require('filesystem')
local shell=require('shell')
local serialization=require('serialization')
local computer=require('computer')
-- OpenOS `lua dt.lua` compiles with source '=dt.lua', not an absolute @filename.
local source=debug.getinfo(1,'S').source
local filename=assert(source:match('^[@=](.+)$'),'Run dt.lua from its installation directory')
local here=filesystem.path(shell.resolve(filename))
package.path=here..'?.lua;'..package.path
local core=require('dt_core')
local driver=require('dt_io')
local profiles=require('dt_bindings')
local recipes=dofile(here..'recipes.lua')
assert(#recipes==33,'Expected the verified 33-recipe catalog')
local byId={} for _,r in ipairs(recipes) do byId[r.id]=r end
local function read(path)
  for _,p in ipairs({path,path..'.bak'}) do
    if filesystem.exists(p) then
      local f=assert(io.open(p,'r'));local text=f:read('*a');f:close()
      local ok,value=pcall(serialization.unserialize,text)
      if ok and type(value)=='table' then return value end
    end
  end
  if filesystem.exists(path) or filesystem.exists(path..'.bak') then error('Corrupt data file: '..path) end
end
local function writeFile(path,contents)
  local f=assert(io.open(path,'w'))
  local written,writeReason=f:write(contents)
  local flushed,flushReason=f:flush()
  local closed,closeReason=f:close()
  assert(written,'Cannot write '..path..': '..tostring(writeReason))
  assert(flushed,'Cannot flush '..path..': '..tostring(flushReason))
  -- OpenOS may return nil without an error after a successful close.
  assert(closed~=false and closeReason==nil,'Cannot close '..path..': '..tostring(closeReason))
end
local function save(path,value)
  writeFile(path..'.new',serialization.serialize(value))
  if filesystem.exists(path..'.bak') then assert(filesystem.remove(path..'.bak')) end
  if filesystem.exists(path) then assert(filesystem.rename(path,path..'.bak')) end
  assert(filesystem.rename(path..'.new',path))
end
local function erase(path)
  for _,suffix in ipairs({'','.bak','.new'}) do if filesystem.exists(path..suffix) then assert(filesystem.remove(path..suffix)) end end
end
local function stable(x)
  if type(x)~='table' then return type(x)..':'..tostring(x) end
  local k={} for a in pairs(x) do k[#k+1]=a end
  table.sort(k,function(a,b)return tostring(a)<tostring(b) end)
  local o={} for _,a in ipairs(k) do o[#o+1]=stable(a)..'='..stable(x[a]) end
  return '{'..table.concat(o,',')..'}'
end
local bindingPath=here..'bindings.dat'
local jobPath=here..'transaction.dat'
local lockPath=here..'controller.lock'
local overrides=read(bindingPath) or {items={},fluids={}}
overrides.items=overrides.items or {};overrides.fluids=overrides.fluids or {}
local bindings=profiles.merge(overrides)
local job=read(jobPath)
if command=='help' then
  print([[Dissolution Tank controller
  dt.lua components                  list component addresses
  dt.lua recipes                     print all 33 recipe IDs
  dt.lua materials                   show prefilled identities and local overrides (no hardware)
  dt.lua scan                        inspect configured inventories and tanks
  dt.lua bind-item SYMBOL SLOT        sample staging-chest item identity
  dt.lua bind-fluid SYMBOL TANK       sample staging-tank fluid registry name
  dt.lua bind-circuits                learn and verify the two circuit locker slots
  dt.lua check                        check capacities, bindings and circuits
  dt.lua rates                        report fluid transposer rate and transfer-time limits
  dt.lua plan                         identify complete staged recipe (no transfers)
  dt.lua probe TANK                    move/return 1 L to verify selected-tank API
  dt.lua run                          run new jobs; refuse an unfinished journal
                                      press Q to stop; preserves unfinished work
  dt.lua resume                       continue a journal after physical inspection
  dt.lua unlock                       remove stale process lock after a reboot
  dt.lua clear CONFIRM_EMPTY           clear journal ONLY after machine is idle/inputs empty
Edit config.lua first. Read GUIDE.html before commissioning.]])
  return
end
if command=='recipes' then
  for n,r in ipairs(recipes) do print(n,r.id,r.name,'circuit '..r.circuit,'EU/t '..r.eut) end
  return
elseif command=='materials' then
  for _,kind in ipairs({'items','fluids'}) do
    print(kind..':')
    for _,symbol in ipairs(core.keys(bindings[kind])) do
      local value=bindings[kind][symbol]
      print(symbol,kind=='items' and core.itemKey(value) or value,
        overrides[kind][symbol] and '(local override)' or '(GTNH 2.9 default)')
    end
  end
  local count=0
  for _,r in ipairs(recipes) do if pcall(core.targets,r,bindings) then count=count+1 end end
  print('Recipes with material identities:',count,'/ 33; no ingredient samples required')
  return
end
if command=='unlock' then
  assert(not argv[2], 'Usage: dt.lua unlock; first confirm no other controller process is running')
  if filesystem.exists(lockPath) then assert(filesystem.remove(lockPath)) end
  print('Stale process lock removed. This did not clear the transaction journal.');return
end
assert(not filesystem.exists(lockPath),'Another controller may be running. After a reboot, inspect the machine then use unlock.')
local cfg=dofile(here..'config.lua')
local ioMachine=driver.new(cfg,bindings)
ioMachine:enable(false)
os.sleep(1) -- Let the Machine Controller cover observe the low signal before touching inventories.
local function noJob() assert(not job,'An unfinished transaction exists; use resume or inspect/empty the machine before clear') end
local function signature(r) return stable({recipe=r,bindings=bindings,config=cfg}) end
local quitRequested=false
local keyEvents,quitListener
local function body()
  if command=='scan' then ioMachine:scan();return end
  if command=='rates' then
    local rate=ioMachine:fluidRate()
    if not rate then print('This transposer does not expose getFluidTransferRate');return end
    print('Fluid-input transposer:',rate,'L/s')
    print('Maximum fluid request:',ioMachine.fluidChunkLimit,'L; active wait:',ioMachine.activePollSeconds,'s')
    for _,entry in ipairs({{'Samarium leach 1',2000},{'Fresh prismarine',8000},{'Monazite 9',99000}}) do
      print(entry[1],string.format('%.3f s fluid-rate floor; excludes controller and machine processing',entry[2]/rate))
    end
    return
  end
  if command=='bind-item' then
    noJob();assert(argv[2] and tonumber(argv[3]),'Usage: bind-item SYMBOL SLOT')
    assert(profiles.defaults.items[argv[2]],'Unknown item symbol; use materials')
    bindings.items[argv[2]]=ioMachine:sampleItem(tonumber(argv[3]))
    overrides.items[argv[2]]=bindings.items[argv[2]];save(bindingPath,overrides)
    print('Bound',argv[2],core.itemKey(bindings.items[argv[2]]));return
  elseif command=='bind-fluid' then
    noJob();assert(argv[2] and tonumber(argv[3]),'Usage: bind-fluid SYMBOL TANK')
    assert(profiles.defaults.fluids[argv[2]],'Unknown fluid symbol; use materials')
    bindings.fluids[argv[2]]=ioMachine:sampleFluid(tonumber(argv[3]))
    overrides.fluids[argv[2]]=bindings.fluids[argv[2]];save(bindingPath,overrides)
    print('Bound',argv[2],bindings.fluids[argv[2]]);return
  elseif command=='bind-circuits' then
    noJob()
    local e=ioMachine.inputItems
    local one=e.tp.getStackInSlot(e.lockerSide,cfg.circuitLockerSlots[1])
    assert(one and one.size==1 and one.damage==1,'Locker must contain exactly one circuit programmed to 1')
    bindings.items.circuit=driver.identity(one)
    for _,n in ipairs({1,9}) do assert(ioMachine:circuitHome(n,core.resolveItem({key='circuit',damage=n},bindings)),
      'Locker must contain exactly one circuit programmed to '..n..' in its configured slot') end
    overrides.items.circuit=bindings.items.circuit
    save(bindingPath,overrides);print('Bound reusable circuit identities and verified locker');return
  elseif command=='check' then
    ioMachine:capacityCheck()
    local count=0
    for _,r in ipairs(recipes) do
      local ok,t=pcall(core.targets,r,bindings)
      if ok then count=count+1 else print(r.id,t) end
    end
    for _,n in ipairs({1,9}) do
      local key=core.resolveItem({key='circuit',damage=n},bindings)
      assert(ioMachine:circuitHome(n,key),'Circuit '..n..' must be home for commissioning check')
    end
    print('Recipes with all material bindings:',count,'/ 33')
    print('Output mode:',ioMachine.outputMode)
    print('This does not verify wiring polarity, live recipe validity, power or maintenance.');return
  elseif command=='plan' then
    noJob();local match,reason=core.match(ioMachine:stage(),recipes,bindings,cfg)
    if match then print(match.recipe.id,match.batches,'batch(es) staged; one will be loaded at a time') else print(reason) end
    return
  elseif command=='probe' then noJob();assert(tonumber(argv[2]),'Usage: probe TANK');ioMachine:probe(tonumber(argv[2]));return
  elseif command=='clear' then
    assert(argv[2]=='CONFIRM_EMPTY','Usage: clear CONFIRM_EMPTY, after visually verifying the machine is idle')
    core.preflight(ioMachine)
    for _,n in ipairs({1,9}) do assert(ioMachine:circuitHome(n,core.resolveItem({key='circuit',damage=n},bindings)),
      'Restore both circuits to the locker before clearing') end
    erase(jobPath);print('Journal cleared. Visually verify no recipe is still running before run.');return
  end
  assert(command=='run' or command=='resume','Unknown command; use help')
  assert(cfg.commissioningPassed,'Finish commissioning, then set commissioningPassed=true in config.lua')
  ioMachine:capacityCheck()
  if command=='run' then noJob() else assert(job,'No unfinished transaction to resume') end
  if job then assert(byId[job.recipe] and job.signature==signature(byId[job.recipe]),
    'Recipe/bindings/config changed since this transaction; restore them before resume') end
  writeFile(lockPath,tostring(computer.uptime()))
  keyEvents=require('event')
  quitListener=function(_,_,character)
    if character==113 or character==81 then quitRequested=true end -- q / Q
  end
  assert(keyEvents.listen('key_down',quitListener),'Cannot register the Q quit key')
  ioMachine.shouldStop=function()return quitRequested end
  print('Controller running. Press Q to stop safely; unfinished input work is retained.')
  local lastMessage,jobStart=nil,computer.uptime()
  local savedPhase=job and job.phase
  while not quitRequested do
    local progressed=false
    if not job then
      core.preflight(ioMachine)
      local match,reason=core.match(ioMachine:stage(),recipes,bindings,cfg)
      if match then
        job={recipe=match.recipe.id,phase='fluids',signature=signature(match.recipe)}
        save(jobPath,job);savedPhase=job.phase;jobStart=computer.uptime();lastMessage=nil;progressed=true
      elseif reason~=lastMessage then print(reason);lastMessage=reason end
    else
      local r=assert(byId[job.recipe],'Unknown recipe in journal')
      assert(computer.uptime()-jobStart<cfg.jobTimeoutSeconds,'Transaction timed out. Journal retained; inspect power, transfers and machine status before resume.')
      -- One durable intent per phase. Repeated/partial transfers within that phase
      -- recover from physical contents; they do not need another identical write.
      if job.phase~=savedPhase then save(jobPath,job);savedPhase=job.phase end
      local message
      message,progressed=core.step(ioMachine,job,r,bindings)
      local status=r.id..' ['..job.phase..'] '..message
      if status~=lastMessage then print(status);lastMessage=status end
      if job.phase=='complete' then
        core.preflight(ioMachine);erase(jobPath);job=nil;savedPhase=nil
        print(core.managesOutputs(ioMachine) and 'Ready for next batch' or 'Input batch accepted; ready for next staged lot (outputs external)')
      end
    end
    -- Advance successful work without a configured quarter-second delay per step.
    -- Still yield to OpenOS, and back off when waiting or a transfer moved nothing.
    local activePoll=ioMachine.activePollSeconds or (type(cfg.pollSeconds)=='number' and cfg.pollSeconds or 0.1)
    os.sleep(progressed and 0 or (job and activePoll or (cfg.idlePollSeconds or activePoll)))
  end
end
local ok,err=xpcall(body,debug.traceback)
if keyEvents and quitListener then pcall(keyEvents.ignore,'key_down',quitListener) end
pcall(function()ioMachine:enable(false)end)
if filesystem.exists(lockPath) then filesystem.remove(lockPath) end
if not ok then io.stderr:write(tostring(err)..'\nMachine start signal OFF; journal retained if present.\n') end
if ok and quitRequested then
  print(job and 'Stopped by Q. Start signal OFF; transaction retained. Inspect, then use resume.'
    or 'Stopped by Q. Start signal OFF; no unfinished input transaction. Use run to restart.')
end
