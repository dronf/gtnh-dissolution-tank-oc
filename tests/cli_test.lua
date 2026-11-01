-- Match the real OpenOS lua.lua launcher: load(contents, '=' .. filename).
local recipes=require('recipes');local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,(why or '')..': '..tostring(a)..' != '..tostring(b))end
local function run(command,source,cwd,noConfig)
 local root='/home/dissolution/';local loaded={};local resolved={};local lines={};local scans=0;local enables=0
 local keys={'component','filesystem','serialization','computer','dt_io','shell'};local old={}
 for _,key in ipairs(keys) do old[key]=package.loaded[key] end
 local components={transposer={'fluid-transposer-uuid','item-transposer-uuid'},redstone={'redstone-uuid'}}
 package.loaded.component={list=function(kind)
  local n=0;return function()n=n+1;return components[kind][n]end
 end}
 package.loaded.shell={resolve=function(path)
  resolved[#resolved+1]=path
  return path:sub(1,1)=='/' and path or cwd..'/'..path
 end}
 package.loaded.filesystem={path=function(path)
  eq(path,root..'dt.lua','resolve relative source before taking its directory')
  return path:match('^(.*)/[^/]+$')..'/'
 end,exists=function(path)
  eq(path:sub(1,#root),root,'all local state must be beside the script')
  return false
 end}
 package.loaded.serialization={}
 package.loaded.computer={}
 package.loaded.dt_io={new=function(cfg)
  eq(cfg.marker,'beside-script')
  return {enable=function()enables=enables+1 end,scan=function()scans=scans+1 end}
 end}
 local oldDofile,oldPrint,oldSleep=dofile,print,os.sleep
 dofile=function(path)
  loaded[#loaded+1]=path
  eq(path:sub(1,#root),root,'data file resolved from incorrect root')
  if path==root..'recipes.lua' then return recipes end
  if path==root..'config.lua' then
   assert(not noConfig,'config must not load for '..command)
   return {marker='beside-script'}
  end
  error('Unexpected file: '..path)
 end
 print=function(...)
  local t={} for n=1,select('#',...) do t[#t+1]=tostring(select(n,...)) end
  lines[#lines+1]=table.concat(t,' ')
 end
 os.sleep=function()end
 local ok,reason=pcall(assert(load(cliSource,source)),command)
 dofile,print,os.sleep=oldDofile,oldPrint,oldSleep
 for _,key in ipairs(keys) do package.loaded[key]=old[key] end
 return {ok=ok,reason=reason,loaded=loaded,resolved=resolved,lines=table.concat(lines,'\n'),scans=scans,enables=enables}
end
local components=run('components','=dt.lua','/home/dissolution',true)
eq(components.ok,true,tostring(components.reason));eq(#components.loaded,0);eq(#components.resolved,0)
for _,id in ipairs({'fluid-transposer-uuid','item-transposer-uuid','redstone-uuid'}) do eq(components.lines:find(id,1,true)~=nil,true) end
for _,command in ipairs({'help','recipes','materials'}) do
 local diagnostic=run(command,'=dt.lua','/home/dissolution',true)
 eq(diagnostic.ok,true,tostring(diagnostic.reason));eq(diagnostic.enables,0)
 if command=='materials' then eq(diagnostic.lines:find('33 / 33',1,true)~=nil,true) end
end
for _,case in ipairs({{'=dt.lua','/home/dissolution'},{'=/home/dissolution/dt.lua','/tmp'},{'@/home/dissolution/dt.lua','/tmp'}}) do
 local scan=run('scan',case[1],case[2],false)
 eq(scan.ok,true,tostring(scan.reason));eq(scan.scans,1)
 eq(scan.loaded[#scan.loaded],'/home/dissolution/config.lua')
end
print('PASS: '..checks..' CLI assertions; real OpenOS relative/absolute chunk names, native file execution, config beside the script, and component discovery before configuration.')
return {checks=checks}
