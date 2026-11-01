-- Execute the real installer against an in-memory OpenOS filesystem and HTTP service.
local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,(why or '')..': '..tostring(a)..' != '..tostring(b))end
local function run(options)
 local options=options or {};local dirs={['/home']=true};local data={};local calls=0
 if options.existing then dirs['/home/dissolution']=true;data['/home/dissolution/config.lua']='MY CONFIG' end
 local old={};for _,k in ipairs({'component','filesystem','internet','shell'}) do old[k]=package.loaded[k] end
 package.loaded.component={isAvailable=function()return not options.noCard end}
 package.loaded.shell={resolve=function(x)return x end}
 package.loaded.filesystem={
  path=function(x)return x:match('^(.*)/[^/]+$') or '/' end,
  exists=function(x)return dirs[x]~=nil or data[x]~=nil end,
  makeDirectory=function(x)eq(dirs[x],nil);dirs[x]=true;return true end,
  remove=function(x)
   if data[x] then data[x]=nil;return true end
   for k in pairs(data) do if k:sub(1,#x+1)==x..'/' then return nil,'not empty' end end
   dirs[x]=nil;return true
  end,
  rename=function(from,to)
   eq(dirs[to],nil,'must not replace a destination');eq(dirs[from],true)
   dirs[to]=true;dirs[from]=nil
   local moved={} for k,v in pairs(data) do if k:sub(1,#from+1)==from..'/' then moved[to..k:sub(#from+1)]=v;data[k]=nil end end
   for k,v in pairs(moved) do data[k]=v end
   return true
  end
 }
 package.loaded.internet={request=function(url)
  calls=calls+1
  eq(url:find('/5f3198306fbbdf93d893c7c592541f22b84f76c5/',1,true)~=nil,true,'pinned source')
  local name=url:match('/([^/]+)$');local contents=assert(installerPayloads[name],name)
  if options.badSize and calls==3 then contents=contents:sub(1,-2) end
  if options.badLua and calls==3 then contents=string.rep('?',#contents) end
  local offset=1
  return function()
   if options.networkFailure and calls==3 and offset>1 then error('connection lost') end
   if offset>#contents then return end
   local s=contents:sub(offset,offset+256);offset=offset+#s;return s
  end
 end}
 local oldOpen,oldPrint=io.open,print
 print=function()end
 io.open=function(path,mode)
  eq(mode,'wb');eq(dirs[path:match('^(.*)/[^/]+$')],true)
  return {write=function(self,value)data[path]=value;return self end,close=function()return true end}
 end
 local ok,reason=pcall(assert(loadfile(testRoot..'/install.lua')),options.destination)
 io.open=oldOpen;print=oldPrint
 for k,v in pairs(old) do package.loaded[k]=v end
 return {ok=ok,reason=reason,dirs=dirs,data=data,calls=calls}
end
local good=run();eq(good.ok,true,tostring(good.reason));eq(good.calls,6)
for name,contents in pairs(installerPayloads) do eq(good.data['/home/dissolution/'..name],contents) end
eq(good.dirs['/home/dissolution.download-1'],nil)
local existing=run({existing=true});eq(existing.ok,false);eq(existing.calls,0);eq(existing.data['/home/dissolution/config.lua'],'MY CONFIG')
for _,fault in ipairs({'badSize','badLua','networkFailure'}) do
 local result=run({[fault]=true});eq(result.ok,false,fault);eq(result.dirs['/home/dissolution'],nil)
 eq(result.dirs['/home/dissolution.download-1'],nil);eq(next(result.data),nil,'failed install must leave no partial runtime')
end
local noCard=run({noCard=true});eq(noCard.ok,false);eq(noCard.calls,0);eq(next(noCard.data),nil)
local root=run({destination='/'});eq(root.ok,false);eq(root.calls,0)
local custom=run({destination='/home/another-tank'});eq(custom.ok,true,tostring(custom.reason));eq(custom.dirs['/home/another-tank'],true)
print('PASS: '..checks..' installer assertions; all six pinned files, existing-install protection, incomplete/invalid downloads, network interruption, cleanup and alternate destinations.')
return {checks=checks}
