# Prefilled GTNH 2.9 material identities

`dt_bindings.lua` supplies all item and fluid identities automatically. You do **not** need samples, a creative inventory, or every ingredient in storage to register the recipes. The identities are string registry names plus item metadata; world-specific numeric IDs are not used by the controller.

Run this on the OC computer to inspect the effective identities, even before wiring/configuring components:

```sh
lua dt.lua materials
```

It reports the defaults, any local overrides, and **33 / 33** recipes with identities. This is catalog coverage, not proof that ingredients are present or that every recipe has been live-tested.

## Item identities

| Alias | Registry name | Base metadata |
|---|---|---:|
| `saltpeter` | `gregtech:gt.metaitem.01` | 2836 |
| `prismarine_shard` | `Botania:manaResource` | 10 |
| `flower` | `Botania:shinyFlower` | 0 |
| `virus` | `Botania:virus` | 0 |
| `witchery_ingredient` | `witchery:ingredient` | 78 |
| `golden_oak` | `thaumicbases:goldenOakSapling` | 2 |
| `rainbow_cactus` | `thaumicbases:rainbowCactus` | 0 |
| `rose_vine` | `WitchingGadgets:WG_RoseVine` | 0 |
| `circuit` | `gregtech:gt.integrated_circuit` | 1 |

Recipes override metadata where needed: all 16 glimmering flower colors, Witchery ingredient variants 21/22/78, golden-oak variants 2/3, and circuits 1/9. The profile expects normal stacks without extra NBT. Custom named/tagged variants can be bound explicitly if your server uses them.

The prismarine recipe uses Botania's resource item at metadata 10. A similarly named shard from a different mod is not silently treated as the same stack.

## Fluid identities

| Alias | Exact fluid registry name |
|---|---|
| `water` | `water` |
| `monazite_muddy` | `muddy monazite rare earth solution` |
| `bastnasite_conditioned` | `conditioned bastnasite mud` |
| `nitric_acid` | `nitricacid` |
| `samarium_muddy` | `muddy samarium rare earth solution` |
| `samarium_mud` | `samarium rare earth mud` |
| `industrial_hf` | `hydrofluoricacid` |
| `hydrogen_peroxide` | `fluid.hydrogenperoxide` |
| `prismarine_peroxide` | `prismarinecontaminatedhydrogenperoxide` |
| `purifying_fluid` | `fluidpure` |
| `liquid_death` | `fluiddeath` |

Spaces and punctuation in these names are intentional. `hydrofluoricacid` is the industrial-strength fluid in this checked pack; ordinary GT HF is distinct (`hydrofluoricacid_gt5u`). Fluids use the unqualified name returned by OC, not an FML ownership prefix such as `bartworks:`.

## Optional overrides

Existing `bindings.dat` values override the defaults, so earlier manual bindings remain in effect. New `bind-item`, `bind-fluid`, and `bind-circuits` commands save local overrides; they are useful only for differences from the checked pack. Inspect the effective result with `materials`. Do not change bindings during an unfinished input transaction.

The hardware configuration, selected-fluid probe, and real ingredients for a recipe you want to run are still necessary. You can commission recipes as ingredients become available. Unused recipes do not require ingredient samples or a test batch before you use a different recipe.

## Evidence and limits

All nine item registry names were found in the GTNH 2.9 Release pack's loaded FML item/block remap entries. Their mapped numeric IDs matched the items in the archived recipe dump; those IDs are retained only as evidence in [the test fixture](tests/fixtures/gtnh-2.9-identities.json). All eleven fluid names were found in the loaded FML default-fluid registry entries. The checked pack contains GregTech **5.09.54.265**.

Metadata and recipe variants were cross-checked against the existing recipe catalog, its archived dump comparison, and primary source code:

* [GT material ID map](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/gregtech/api/enums/MaterialsIDMap.java): Saltpeter material 836; the dust prefix gives item metadata 2836.
* [GT generic item registration](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/gregtech/api/items/GTGenericItem.java) and [integrated circuit](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/gregtech/common/items/ItemIntegratedCircuit.java).
* [Flora recipe variants](https://github.com/GTNewHorizons/NewHorizonsCoreMod/blob/master/src/main/java/com/dreammaster/scripts/ScriptBiomesOPlenty.java).
* [Lanthanoid material names](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/gtnhlanth/common/register/WerkstoffMaterialPool.java), [fluid registration](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/bartworks/system/material/WerkstoffLoader.java), and [GT fluid builder](https://github.com/GTNewHorizons/GT5-Unofficial/blob/master/src/main/java/gregtech/common/fluid/GTFluidBuilder.java).

Your actual server may change registrations or ore unification. A mismatch prevents a recipe match rather than loading a guessed substitute. Bind the material you actually use only if a difference is found. The profile is not a live recipe enumeration API and does not establish that every catalog recipe has been run in Minecraft.
