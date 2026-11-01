-- Replace the two transposer addresses and redstone address with full UUIDs.
-- Directions are absolute world directions, viewed FROM each transposer.
return {
  -- Default: your ME output hatch/bus exports products. No output components needed.
  outputMode='external',
  inputFluids={address='REPLACE-FLUID-INPUT-UUID',stageSide='up',machineSide='north'},
  inputItems={address='REPLACE-ITEM-INPUT-UUID',stageSide='up',machineSide='north',lockerSide='west'},
  -- Optional old layout: set outputMode='managed' and configure two more transposers:
  -- outputFluids={address='REPLACE-FLUID-OUTPUT-UUID',machineSide='north',storeSide='up'},
  -- outputItems={address='REPLACE-ITEM-OUTPUT-UUID',machineSide='north',storeSide='up'},
  redstone={address='REPLACE-REDSTONE-UUID',side='east'},
  -- Real LV Input Bus slots. The dedicated ghost-circuit slot must remain empty.
  consumedSlot=1,circuitSlot=2,
  circuitLockerSlots={[1]=1,[9]=2},
  maxEUt=7680,
  -- Choose circuit 9 over circuit 1 if both match the complete staging lot.
  preferCircuit=9,
  -- Optional: pin a specific recipe ID to resolve ambiguity or commission one recipe.
  onlyRecipe=nil,
  -- In the checked GTNH transfer implementation, sourceTank is a raw zero-based index.
  -- Reading getFluidInTank returns a Lua one-based array. Run `probe` before enabling `run`.
  sourceTankBase=0,
  fluidChunk=1000,itemChunk=64,
  pollSeconds=0.25,jobTimeoutSeconds=1800,
  commissioningPassed=false
}
