-- Default ME/export mode: no output endpoint exists; acceptance is NOT production completion.
local core=require('dt_core');local recipes=require('recipes')
local checks=0
local fixtureStart=coreFixture.getChecks()+ioFixture.getChecks()
local function eq(a,b,msg) checks=checks+1;assert(a==b,(msg or '')..': '..tostring(a)..' != '..tostring(b)) end
local function copy(x) if type(x)~='table' then return x end local t={} for k,v in pairs(x) do t[k]=copy(v) end return t end
local bindings=coreFixture.bindings
local function forbidden() error('External mode touched an output endpoint') end

for _,r in ipairs(recipes) do
 for _,interruption in ipairs({'none','fluids','items','circuit','armed','return'}) do
  local io=coreFixture.Fake.new(r);io.outputMode='external';io.outputs=forbidden;io.drainOutput=forbidden
  -- Existing output contents must not prevent an input handoff.
  io.outAmount=123;io.outItems.previousProduct=1;core.preflight(io)
  local job={recipe=r.id,phase='fluids'};local interrupted=false
  for tick=1,4000 do
   io:progress();local durable=copy(job);core.step(io,job,r,bindings)
   eq(job.phase~='result' and job.phase~='drain',true,'output phase entered')
   if not interrupted and durable.phase==interruption then job=durable;io:enable(false);interrupted=true end
   if job.phase=='complete' then break end
  end
  eq(job.phase,'complete',r.id);eq(io.starts,1);eq(io.locker[1],1);eq(io.locker[9],1)
  eq(io.running>0,true,'acceptance must not wait for production')
  core.preflight(io)
  while io.running>0 do io:progress() end
  core.preflight(io);eq(io.outAmount,r.outputAmount,'external output must remain untouched')
 end
 -- Exercise the real driver with only two transposers and one redstone component registered.
 local p,io,t=ioFixture.makePlatform(r,'external');p.duration=100
 io.outputs=forbidden;io.drainOutput=forbidden
 io:capacityCheck();core.preflight(io)
 eq(io.outputFluids,nil);eq(io.outputItems,nil)
 -- scan must not invent output components either.
 local oldPrint=print;print=function()end
 local scanned,err=pcall(function()io:scan()end);print=oldPrint;assert(scanned,err)
 local job={phase='fluids'}
 for tick=1,3000 do p:progress();core.step(io,job,r,ioFixture.bindings);if job.phase=='complete' then break end end
 eq(job.phase,'complete');eq(p.starts,1);eq(p.running>0,true)
 eq(io:circuitHome(1,core.resolveItem({key='circuit',damage=1},ioFixture.bindings)),true)
 eq(io:circuitHome(9,core.resolveItem({key='circuit',damage=9},ioFixture.bindings)),true)
 eq(p.store[1].amount,0);eq(p.chest[1],nil)
end

-- A second staged recipe can be loaded while the previous one is still running.
-- The gate only opens after exact fluids, consumed items and the required circuit are present.
local io=coreFixture.Fake.new(recipes[1]);io.outputMode='external';io.outputs=forbidden;io.drainOutput=forbidden
function io:enable(value)
 self.enabled=value
 if not value or self.running>0 then return end
 for name,n in pairs(self.target.fluids) do eq(self.fluids[name],n,'queued fluid ratio') end
 for key,n in pairs(self.target.items) do eq(self.items[key],n,'queued ingredient') end
 if self.target.circuit then eq(self.items[self.target.circuit],1,'queued circuit') end
 self.starts=self.starts+1;self.fluids={};self.items=self.target.circuit and {[self.target.circuit]=1} or {};self.running=100000
end
local function steps(r,job,limit)
 for n=1,limit do core.step(io,job,r,bindings);if job.phase=='complete' then return end end
end
local first={phase='fluids'};steps(recipes[1],first,2000);eq(first.phase,'complete');eq(io.starts,1)
eq(io.running,100000);eq(io.locker[1],1)
local nextRecipe=recipes[5];io.r=nextRecipe;io.target=core.targets(nextRecipe,bindings)
io.stageItems=copy(io.target.items);io.stageFluids=copy(io.target.fluids)
local second={phase='fluids'};steps(nextRecipe,second,2000)
eq(second.phase,'armed');eq(io.starts,1,'must wait for busy machine');eq(io.locker[9],0)
eq(io.enabled,true,'only the complete queued batch is enabled')
io.running=0;core.step(io,second,nextRecipe,bindings);eq(io.starts,2)
steps(nextRecipe,second,10);eq(second.phase,'complete');eq(io.locker[9],1)
eq(io.running>0,true);core.preflight(io)
checks=checks+coreFixture.getChecks()+ioFixture.getChecks()-fixtureStart
print('PASS: external ME/export mode, '..checks..' assertions; all 33 recipes, six interruption positions each, no output components, early circuit returns, and a queued batch waiting for a busy machine.')
return {checks=checks}
