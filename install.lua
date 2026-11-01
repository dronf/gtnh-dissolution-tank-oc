-- OpenOS fresh-install downloader. Run from /tmp; does not start the machine.
local component=require('component')
local fs=require('filesystem')
local internet=require('internet')
local shell=require('shell')
assert(component.isAvailable('internet'),'Insert an Internet Card; HTTP must be enabled by the server')

-- Pin one tested runtime snapshot so a download never mixes revisions.
local revision='075b98d7dddc23cc25f5e54d5e97058110b8d9a8'
local base='https://raw.githubusercontent.com/dronf/gtnh-dissolution-tank-oc/'..revision..'/'
local files={
  {'dt.lua',12309},{'dt_core.lua',8317},{'dt_io.lua',12386},
  {'dt_bindings.lua',1733},{'recipes.lua',10944},{'config.lua',1666}
}
local args={...}
assert(#args<=1,'Usage: lua install.lua [new-install-directory]')
local target=shell.resolve(args[1] or '/home/dissolution'):gsub('/+$','')
assert(target~='' and target~='/','Choose a new installation directory')
assert(not fs.exists(target),'Destination already exists: '..target..'. Existing files were not changed. Choose a NEW directory to install another copy.')
local parent=fs.path(target)
if not fs.exists(parent) then assert(fs.makeDirectory(parent)) end
local temporary
for n=1,100 do
  local candidate=target..'.download-'..n
  if not fs.exists(candidate) then temporary=candidate;break end
end
assert(temporary,'No free download staging directory')
assert(fs.makeDirectory(temporary))
local function cleanup()
  -- Delete only our six named files and our newly created, now-empty directory.
  for _,entry in ipairs(files) do pcall(fs.remove,temporary..'/'..entry[1]) end
  pcall(fs.remove,temporary)
end
local ok,why=xpcall(function()
  for _,entry in ipairs(files) do
    local name,expected=entry[1],entry[2]
    print('Downloading '..name)
    local chunks={};local size=0
    local response=internet.request(base..name,nil,{['user-agent']='DissolutionTank-OpenOS-Installer'})
    for chunk in response do
      size=size+#chunk
      assert(size<=expected,'Unexpected response size for '..name..'; check the download URL / HTTP access')
      chunks[#chunks+1]=chunk
    end
    assert(size==expected,'Incomplete download of '..name..'; installation not committed')
    local contents=table.concat(chunks)
    local compiled,reason=load(contents,'='..name,'t')
    assert(compiled,'Invalid Lua download for '..name..': '..tostring(reason))
    local f=assert(io.open(temporary..'/'..name,'wb'))
    local written,writeReason=f:write(contents)
    local flushed,flushReason=f:flush()
    local closed,closeReason=f:close()
    assert(written,'Cannot write '..name..': '..tostring(writeReason))
    assert(flushed,'Cannot flush '..name..': '..tostring(flushReason))
    -- OpenOS close() can succeed with no return value. Check its error result.
    assert(closed~=false and closeReason==nil,'Cannot close '..name..': '..tostring(closeReason))
  end
  assert(not fs.exists(target),'Destination appeared while downloading; existing files were not changed')
  assert(fs.rename(temporary,target))
end,debug.traceback)
if not ok then cleanup();error(why,0) end
print('Installed six files to '..target)
print('Runtime revision: '..revision)
print('Next:')
print('cd '..target)
print('lua dt.lua components')
print('edit config.lua')
print('For top-mounted transposers: stageSide=up, machineSide=down in BOTH input entries.')
print('Read the guide and commission before enabling run. No machine was started.')
return true
