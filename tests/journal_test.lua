-- Run the real CLI through an accepted batch using OpenOS-style nil close results.
local core=require('dt_core');local recipes=require('recipes')
local checks=0;local before=coreFixture.getChecks()
local function eq(a,b,why)checks=checks+1;assert(a==b,(why or '')..': '..tostring(a)..' != '..tostring(b))end
local function serialize(x)
 if type(x)=='string' then return string.format('%q',x) end
 if type(x)~='table' then return tostring(x) end
 local t={} for k,v in pairs(x) do t[#t+1]='['..serialize(k)..']='..serialize(v) end
 return '{'..table.concat(t,',')..'}'
end
local function run(failFlush)
 local root='/home/dissolution/';local files={};local time=0;local messages={};local errors={};local accepted=false;local flushed=0
 files[root..'bindings.dat']=serialize(coreFixture.bindings)
 local machine=coreFixture.Fake.new(recipes[8]);machine.outputMode='external'
 function machine:stage()return {items=self.stageItems,fluids=self.stageFluids}end
 function machine:capacityCheck()end
 local cfg={commissioningPassed=true,pollSeconds=0.25,jobTimeoutSeconds=1800,maxEUt=7680,preferCircuit=9,outputMode='external'}
 local keys={'filesystem','serialization','computer','dt_io','shell'};local old={}
 for _,k in ipairs(keys) do old[k]=package.loaded[k] end
 package.loaded.filesystem={path=function()return root end,exists=function(path)return files[path]~=nil end,
  remove=function(path)files[path]=nil;return true end,
  rename=function(from,to)eq(files[from]~=nil,true,'rename must follow a flushed write');eq(files[to],nil);files[to]=files[from];files[from]=nil;return true end}
 package.loaded.serialization={serialize=serialize,unserialize=function(text)return assert(load('return '..text))()end}
 package.loaded.computer={uptime=function()return time end}
 package.loaded.dt_io={new=function()return machine end}
 package.loaded.shell={resolve=function()return root..'dt.lua' end}
 local oldOpen,oldSleep,oldDofile,oldPrint,oldStderr=io.open,os.sleep,dofile,print,io.stderr
 io.open=function(path,mode)
  if mode=='r' then return {read=function()return files[path]end,close=function()return nil end} end
  local pending=''
  return {write=function(self,value)pending=pending..value;return self end,
   flush=function(self)
    if failFlush then return nil,'disk full' end
    flushed=flushed+1;files[path]=pending;return self
   end,
   close=function()return nil end}
 end
 os.sleep=function(seconds)
  time=time+seconds;machine:progress()
  if accepted then error('TEST_STOP_AFTER_ACCEPTANCE') end
  assert(time<1000,'test stalled')
 end
 dofile=function(path)
  if path==root..'config.lua' then return cfg end
  if path==root..'recipes.lua' then return recipes end
  return oldDofile(path)
 end
 print=function(...)
  local row={} for n=1,select('#',...) do row[#row+1]=tostring(select(n,...)) end
  local line=table.concat(row,' ');messages[#messages+1]=line
  if line:find('Input batch accepted',1,true) then accepted=true end
 end
 io.stderr={write=function(_,s)errors[#errors+1]=s end}
 local ok,err=pcall(assert(loadfile(testRoot..'/dt.lua')),'run')
 io.open,os.sleep,dofile,print,io.stderr=oldOpen,oldSleep,oldDofile,oldPrint,oldStderr
 for _,k in ipairs(keys) do package.loaded[k]=old[k] end
 assert(ok,err)
 return {accepted=accepted,flushed=flushed,files=files,errors=table.concat(errors,'\n'),machine=machine}
end
local good=run(false)
eq(good.accepted,true,'successful OpenOS close must not abort journal save')
eq(good.flushed>5,true,'journal must explicitly flush')
eq(good.machine.starts,1);eq(good.files['/home/dissolution/transaction.dat'],nil,'accepted handoff journal cleared')
eq(good.files['/home/dissolution/controller.lock'],nil)
eq(good.errors:find('TEST_STOP_AFTER_ACCEPTANCE',1,true)~=nil,true)
local full=run(true)
eq(full.accepted,false);eq(full.machine.starts,0,'storage failure must stop before machine start')
eq(full.errors:find('Cannot flush',1,true)~=nil,true);eq(full.errors:find('disk full',1,true)~=nil,true)
checks=checks+coreFixture.getChecks()-before
print('PASS: '..checks..' journal assertions; real CLI saves/clears a transaction with nil-returning OpenOS close and rejects a failed flush before starting.')
return {checks=checks}
