local profiles=require('dt_bindings');local core=require('dt_core');local recipes=require('recipes')
local checks=0
local function eq(a,b,why)checks=checks+1;assert(a==b,(why or '')..': '..tostring(a)..' != '..tostring(b))end
local defaults=profiles.merge()
eq(#core.keys(defaults.items),9);eq(#core.keys(defaults.fluids),11)
for symbol,identity in pairs(registryFixture.items) do
 eq(defaults.items[symbol].name,identity.name,'loaded item registry: '..symbol)
 eq(defaults.items[symbol].damage,identity.damage,'source metadata: '..symbol)
end
for symbol,name in pairs(registryFixture.fluids) do eq(defaults.fluids[symbol],name,'loaded fluid registry: '..symbol) end
-- Construct real-ID staging lots from the independent fixture. No samples or saved bindings exist.
for _,r in ipairs(recipes) do
 local stage={items={},fluids={}}
 for _,i in ipairs(r.items) do
  local item=registryFixture.items[i.key]
  local key=core.itemKey({name=item.name,damage=i.damage or item.damage,tag=''})
  stage.items[key]=(stage.items[key] or 0)+i.count
 end
 for symbol,n in pairs(r.fluids) do stage.fluids[registryFixture.fluids[symbol]]=n end
 local match,why=core.match(stage,recipes,defaults,{maxEUt=7680,preferCircuit=9})
 assert(match,why);eq(match.recipe.id,r.id,'sample-free recognition');eq(match.batches,1)
end
local saved={items={saltpeter={name='custom:saltpeter',damage=7,tag='custom-NBT'}},fluids={industrial_hf='custom:industrial_hf'}}
local merged=profiles.merge(saved)
eq(merged.items.saltpeter.name,'custom:saltpeter');eq(merged.items.saltpeter.tag,'custom-NBT')
eq(merged.fluids.industrial_hf,'custom:industrial_hf');eq(merged.fluids.water,'water')
merged.items.saltpeter.damage=99;merged.items.circuit.damage=20
eq(saved.items.saltpeter.damage,7,'do not mutate saved overrides')
eq(profiles.merge().items.circuit.damage,1,'do not mutate defaults')
eq(profiles.merge().items.saltpeter.damage,2836)
eq(profiles.merge({items={}}).fluids.water,'water','legacy partial binding file')
eq(defaults.fluids.monazite_muddy,'muddy monazite rare earth solution','preserve spaces in fluid name')
eq(defaults.items.prismarine_shard.damage,10,'Botania prismarine variant')
-- Run the actual CLI's new materials command with no configured component access or samples.
local oldFS,oldSerialization,oldComputer,oldShell=package.loaded.filesystem,package.loaded.serialization,package.loaded.computer,package.loaded.shell
package.loaded.shell={resolve=function(path)return path end}
package.loaded.filesystem={path=function()return testRoot..'/' end,exists=function()return false end}
package.loaded.serialization={unserialize=function()error('No saved data exists')end}
package.loaded.computer={uptime=function()error('Materials command must not start the controller')end}
local output={};local oldPrint=print
print=function(...)local row={} for n=1,select('#',...) do row[#row+1]=tostring(select(n,...)) end output[#output+1]=table.concat(row,' ')end
local ok,err=pcall(assert(loadfile(testRoot..'/dt.lua')),'materials')
print=oldPrint
package.loaded.filesystem=oldFS;package.loaded.serialization=oldSerialization;package.loaded.computer=oldComputer;package.loaded.shell=oldShell
assert(ok,err)
local text=table.concat(output,'\n')
eq(text:find('33 / 33',1,true)~=nil,true,'CLI resolves all recipes without hardware')
eq(text:find('Botania:manaResource@10',1,true)~=nil,true)
eq(text:find('(GTNH 2.9 default)',1,true)~=nil,true)
print('PASS: '..checks..' sample-free binding assertions; 9 loaded item identities, 11 fluid identities, all 33 recipe matches, override precedence, and hardware-free materials command.')
return {checks=checks}
