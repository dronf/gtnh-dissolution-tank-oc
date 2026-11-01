-- GTNH 2.9 profile: registry names checked against the loaded Release-pack log.
-- Metadata checked against recipe sources and the archived 33-recipe dump.
-- Numeric world item IDs are deliberately not used. See REGISTRY.md.
local M={}
M.defaults={
  items={
    saltpeter={name='gregtech:gt.metaitem.01',damage=2836,tag=''},
    prismarine_shard={name='Botania:manaResource',damage=10,tag=''},
    flower={name='Botania:shinyFlower',damage=0,tag=''},
    virus={name='Botania:virus',damage=0,tag=''},
    witchery_ingredient={name='witchery:ingredient',damage=78,tag=''},
    golden_oak={name='thaumicbases:goldenOakSapling',damage=2,tag=''},
    rainbow_cactus={name='thaumicbases:rainbowCactus',damage=0,tag=''},
    rose_vine={name='WitchingGadgets:WG_RoseVine',damage=0,tag=''},
    circuit={name='gregtech:gt.integrated_circuit',damage=1,tag=''}
  },
  fluids={
    water='water',
    monazite_muddy='muddy monazite rare earth solution',
    bastnasite_conditioned='conditioned bastnasite mud',
    nitric_acid='nitricacid',
    samarium_muddy='muddy samarium rare earth solution',
    samarium_mud='samarium rare earth mud',
    industrial_hf='hydrofluoricacid',
    hydrogen_peroxide='fluid.hydrogenperoxide',
    prismarine_peroxide='prismarinecontaminatedhydrogenperoxide',
    purifying_fluid='fluidpure',
    liquid_death='fluiddeath'
  }
}
local function copy(x)
  if type(x)~='table' then return x end
  local out={} for k,v in pairs(x) do out[k]=copy(v) end return out
end
function M.merge(overrides)
  local out=copy(M.defaults)
  for _,kind in ipairs({'items','fluids'}) do
    for key,value in pairs(overrides and overrides[kind] or {}) do
      out[kind][key]=copy(value)
    end
  end
  return out
end
return M
