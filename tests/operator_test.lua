-- Operator stop through the real CLI/driver. No Minecraft keyboard is simulated.
local checks=0;local fixtureBefore=ioFixture.getChecks()
local function eq(a,b,why)checks=checks+1;assert(a==b,(why or '')..': '..tostring(a)..' != '..tostring(b))end
local function options(extra)
 local o={auto=true,snapshots=true,rate=163840,fluidLimit=128000,itemLimit=64,stageSlots=108}
 for k,v in pairs(extra) do o[k]=v end
 return o
end
for _,phase in ipairs({'fluids','items','circuit','armed','return'}) do
 local m,p,files=performanceFixture.run('samarium_leach_1',options({quitPhase=phase}))
 eq(m.stopped,true,phase);eq(p.signal,0,'Q must lower the gate')
 eq(files['/home/dissolution/controller.lock'],nil,'Q must release the process lock')
 eq(m.listeners,1);eq(m.ignored,1,'Q handler must not leak into the shell')
 eq(m.starts<=1,true,'quit never duplicates a batch')
 eq(files['/home/dissolution/transaction.dat']~=nil,true,'unfinished phase must retain a journal')
 local resumed,after,remaining=performanceFixture.run('samarium_leach_1',options({quitPhase=phase,resumeAfterQuit=true}))
 eq(resumed.accepted,true);eq(resumed.starts,1,'resume must start exactly once')
 eq(resumed.listeners,2);eq(resumed.ignored,2);eq(after.signal,0)
 eq(remaining['/home/dissolution/transaction.dat'],nil)
end
local idle,p,files=performanceFixture.run('samarium_leach_1',options({quitPhase='idle',emptyStage=true}))
eq(idle.stopped,true);eq(idle.starts,0);eq(p.signal,0);eq(idle.ignored,1)
eq(files['/home/dissolution/transaction.dat'],nil,'idle quit has no journal')
eq(files['/home/dissolution/controller.lock'],nil)
local complete,p,files=performanceFixture.run('samarium_leach_1',options({quitAfterAcceptance=true}))
eq(complete.stopped,true);eq(complete.accepted,true);eq(complete.starts,1);eq(p.signal,0)
eq(files['/home/dissolution/transaction.dat'],nil,'accepted handoff remains cleared')
local upper,p,files=performanceFixture.run('samarium_leach_1',options({quitPhase='fluids',quitChar=81}))
eq(upper.stopped,true,'uppercase Q');eq(p.signal,0);eq(upper.starts,0)
-- If the quit event arrives while an armed inventory read yields, do not raise the gate.
local during,p,files=performanceFixture.run('samarium_leach_1',options({quitDuringArmedRead=true}))
eq(during.stopped,true);eq(during.starts,0,'Q during the armed snapshot must prevent commit');eq(p.signal,0)
eq(files['/home/dissolution/transaction.dat']~=nil,true);eq(during.ignored,1)
-- A fluid-only recipe also retains its staged handoff and resumes exactly once.
local fluidOnly,p,files=performanceFixture.run('prismarine_fresh',options({quitPhase='armed',resumeAfterQuit=true}))
eq(fluidOnly.stopped,true);eq(fluidOnly.accepted,true);eq(fluidOnly.starts,1);eq(p.signal,0)
-- Ingredient Buffer stages 4 x 64k L: a 90k fluid spans two source compartments.
for _,recipe in ipairs(require('recipes')) do
 local m,p,files=performanceFixture.run(recipe,options({stageTankCapacity=64000}))
 eq(m.accepted,true,recipe.id);eq(m.starts,1);eq(p.signal,0)
 eq(files['/home/dissolution/transaction.dat'],nil)
end
checks=checks+ioFixture.getChecks()-fixtureBefore
print('PASS: '..checks..' operator assertions; Q/q stop, gate OFF, retained journals, listener cleanup, armed-read cancellation, exact-once resume and all 33 recipes from 64k source compartments.')
return {checks=checks}
