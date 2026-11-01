-- Real CLI + real I/O driver through mocked OC APIs. Count expensive work, not wall time.
local recipes=require('recipes');local checks=0;local fixtureBefore=ioFixture.getChecks()
local core=require('dt_core');local driver=require('dt_io')
local function eq(a,b,why)checks=checks+1;assert(a==b,(why or '')..': '..tostring(a)..' != '..tostring(b))end
local function serialize(x)
 if type(x)=='string' then return string.format('%q',x) end
 if type(x)~='table' then return tostring(x) end
 local t={} for k,v in pairs(x) do t[#t+1]='['..serialize(k)..']='..serialize(v) end
 return '{'..table.concat(t,',')..'}'
end
local function execute(recipe,options,sources)
 if type(recipe)=='string' then for _,r in ipairs(recipes) do if r.id==recipe then recipe=r;break end end end
 local options=options or {auto=true,snapshots=true,rate=163840,fluidLimit=128000,itemLimit=64,stageSlots=108}
 local p,initialIO=ioFixture.makePlatform(recipe,'external',options)
 if options.emptyStage then
  for n=1,p.stageI.n do p.stageI[n]=nil end
  for _,tank in ipairs(p.stageF) do tank.amount=0;tank.name=nil end
 end
 local useCore=core;local useDriver=driver;local script=cliSource
 if sources then
  useCore=assert(load(sources.core,'=baseline-core'))()
  local savedCore=package.loaded.dt_core;package.loaded.dt_core=useCore
  useDriver=assert(load(sources.io,'=baseline-io'))();package.loaded.dt_core=savedCore
  script=sources.main
 end
 local cfg=initialIO.cfg;cfg.commissioningPassed=true;cfg.pollSeconds=options.auto and 'auto' or 0.25
 cfg.jobTimeoutSeconds=1800;cfg.preferCircuit=9
 local root='/home/dissolution/';local files={[root..'bindings.dat']=serialize(ioFixture.bindings)}
 local metrics={jobWrites=0,fileWrites=0,sleepSeconds=0,loops=0,reboots=0}
 local time=0;local finished=false;local interrupted=false;local errors={};local lastLine=''
 local keys={'filesystem','serialization','computer','dt_io','dt_core','shell','event'};local old={}
 for _,k in ipairs(keys) do old[k]=package.loaded[k] end
 package.loaded.filesystem={path=function()return root end,exists=function(path)return files[path]~=nil end,
  remove=function(path)files[path]=nil;return true end,
  rename=function(from,to)assert(files[from] and not files[to]);files[to]=files[from];files[from]=nil;return true end}
 package.loaded.serialization={serialize=serialize,unserialize=function(text)return assert(load('return '..text))()end}
 package.loaded.computer={uptime=function()return time end}
 package.loaded.dt_core=useCore
 local keyListener;local quitSent=false
 local function sendQuit()
  if keyListener and not quitSent then
   quitSent=true;keyListener('key_down','keyboard',options.quitChar or 113,16,'operator')
  end
 end
 package.loaded.event={listen=function(name,fn)assert(name=='key_down');keyListener=fn;metrics.listeners=(metrics.listeners or 0)+1;return true end,
  ignore=function(name,fn)assert(name=='key_down' and fn==keyListener);keyListener=nil;metrics.ignored=(metrics.ignored or 0)+1;return true end}
 package.loaded.dt_io={new=function()
  local result=useDriver.new(cfg,ioFixture.bindings)
  if options.quitDuringArmedRead then
   local inputs=result.inputs
   result.inputs=function(self)
    local data=inputs(self)
    if lastLine:find('[armed]',1,true) then sendQuit() end
    return data
   end
  end
  return result
 end}
 package.loaded.shell={resolve=function()return root..'dt.lua' end}
 local oldOpen,oldSleep,oldDofile,oldPrint,oldStderr=io.open,os.sleep,dofile,print,io.stderr
 io.open=function(path,mode)
  if mode=='r' then return {read=function()return files[path]end,close=function()return nil end} end
  local contents=''
  return {write=function(self,s)contents=contents..s;return self end,
   flush=function(self)files[path]=contents;metrics.fileWrites=metrics.fileWrites+1;if path==root..'transaction.dat.new' then metrics.jobWrites=metrics.jobWrites+1 end return self end,
   close=function()return nil end}
 end
 os.sleep=function(seconds)
  seconds=seconds or 0;time=time+seconds;p:progress();metrics.loops=metrics.loops+1
  if finished then
   if options.quitAfterAcceptance then sendQuit();return end
   error('BENCHMARK_FINISHED')
  end
  metrics.sleepSeconds=metrics.sleepSeconds+seconds
  if options.quitPhase and (options.quitPhase=='idle' or lastLine:find('['..options.quitPhase..']',1,true)) then sendQuit() end
  if options.interruptAfter and not interrupted and p.stats.fluidMoves>=options.interruptAfter then
   interrupted=true;metrics.reboots=metrics.reboots+1;error('TEST_REBOOT')
  end
  if options.stopAfter and p.stats.fluidMoves>=options.stopAfter then error('TEST_BLOCKED_TRANSFER') end
  assert(metrics.loops<5000,'benchmark stalled')
 end
 dofile=function(path)
  if path==root..'config.lua' then return cfg end
  if path==root..'recipes.lua' then return recipes end
  return oldDofile(path)
 end
 print=function(...)
  local t={} for n=1,select('#',...) do t[#t+1]=tostring(select(n,...)) end
  lastLine=table.concat(t,' ')
  if lastLine:find('Stopped by Q.',1,true) then metrics.stopped=true;metrics.stopMessage=lastLine end
  if lastLine:find('Input batch accepted',1,true) then finished=true end
 end
 io.stderr={write=function(_,s)errors[#errors+1]=s end}
 local ok,err=pcall(assert(load(script,'=dt.lua')),'run')
 if ok and options.interruptAfter and not finished then ok,err=pcall(assert(load(script,'=dt.lua')),'resume') end
 if ok and options.resumeAfterQuit and metrics.stopped and not finished then ok,err=pcall(assert(load(script,'=dt.lua')),'resume') end
 io.open,os.sleep,dofile,print,io.stderr=oldOpen,oldSleep,oldDofile,oldPrint,oldStderr
 for _,k in ipairs(keys) do package.loaded[k]=old[k] end
 assert(ok,err)
 if not options.stopAfter and not options.quitPhase and not options.quitDuringArmedRead then assert(finished,recipe.id..' | '..lastLine..' | fluid moves '..p.stats.fluidMoves..' | '..table.concat(errors,'\n')) end
 if options.resumeAfterQuit then assert(finished,table.concat(errors,'\n')) end
 for k,v in pairs(p.stats) do metrics[k]=v end
 metrics.starts=p.starts;metrics.accepted=finished
 return metrics,p,files,initialIO
end

for _,r in ipairs(recipes) do
 local metrics,p,files=execute(r)
 eq(metrics.starts,1,r.id);eq(metrics.jobWrites,5,'phase checkpoints')
 eq(metrics.redstoneWrites,3,'only startup OFF, commit ON, accepted OFF')
 eq(metrics.fluidMoves,2,'IV full transfers use one call per fluid')
 eq(metrics.snapshots>0,true);eq(metrics.slotReads<=12,true,'avoid per-slot bus/chest scans')
 eq(files['/home/dissolution/transaction.dat'],nil)
end
-- Partial transfers can repeat many times in one durable phase without identical journal writes.
local partial=execute('monazite_9',{auto=true,snapshots=true,rate=163840,fluidLimit=511,itemLimit=7,stageSlots=108})
eq(partial.fluidMoves>100,true);eq(partial.jobWrites,5);eq(partial.redstoneWrites,3)
-- Reboot after either input transfer for every recipe; resume reads physical quantities.
for _,r in ipairs(recipes) do for position=1,2 do
 local metrics=execute(r,{auto=true,snapshots=true,rate=163840,fluidLimit=128000,itemLimit=64,stageSlots=108,interruptAfter=position})
 eq(metrics.starts,1,r.id);eq(metrics.reboots,1);eq(metrics.fluidMoves,2,'must not reload already transferred fluid')
end end
-- A stalled transfer must back off rather than busy-loop or release ingredients.
local blocked,p,files=execute('prismarine_fresh',{auto=true,snapshots=true,rate=163840,fluidLimit=0,stopAfter=5})
eq(blocked.accepted,false);eq(blocked.starts,0);eq(blocked.jobWrites,1);eq(blocked.sleepSeconds>1,true)
eq(files['/home/dissolution/transaction.dat']~=nil,true)
-- Rate-derived settings differ appropriately; old forks retain the per-slot fallback.
local _,basic=ioFixture.makePlatform(recipes[4],'external',{auto=true,snapshots=true,rate=2560})
eq(basic.fluidChunkLimit,10240);eq(basic.activePollSeconds,0.25);eq(basic:fluidRate(),2560)
local _,iv=ioFixture.makePlatform(recipes[4],'external',{auto=true,snapshots=true,rate=163840})
eq(iv.fluidChunkLimit,128000);eq(iv.activePollSeconds,0.05)
local p,io=ioFixture.makePlatform(recipes[1],'external',{snapshots=true})
p.bus[5]={name='test:circuit',damage=9,size=0,hasTag=false}
eq(pcall(function()io:inputs()end),false,'snapshot must still catch a zero-count ghost circuit')
-- A cached high output remains a level: the machine starts a queued batch when it becomes free.
local p,io=ioFixture.makePlatform(recipes[4],'external',{auto=true,snapshots=true,rate=163840,fluidLimit=128000})
p.running=100000;local job={phase='fluids'}
for n=1,100 do core.step(io,job,recipes[4],ioFixture.bindings);if job.phase=='armed' then break end end
eq(job.phase,'armed')
for n=1,10 do core.step(io,job,recipes[4],ioFixture.bindings) end
eq(p.starts,0);eq(p.stats.redstoneWrites,2);eq(p.signal,15)
p.running=1;p:progress();eq(p.starts,1,'held high must start after previous work finishes')
for n=1,10 do core.step(io,job,recipes[4],ioFixture.bindings);if job.phase=='complete' then break end end
eq(job.phase,'complete');eq(p.stats.redstoneWrites,3);eq(p.signal,0)
checks=checks+ioFixture.getChecks()-fixtureBefore
print('PASS: '..checks..' performance assertions; 33 full CLI jobs, phase checkpoints, two IV fluid calls per recipe, snapshot indexing, 66 mid-transfer reboots, rate adaptation and blocked-transfer backoff.')
return {checks=checks,run=execute}
