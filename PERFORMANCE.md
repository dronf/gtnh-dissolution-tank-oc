# Transfer speed and automatic tuning

The fluid-input transposer exposes `getFluidTransferRate()`, so the controller reads its actual configured rate instead of guessing its tier from its name. Query it with `lua dt.lua rates` while the controller is stopped. The rate is detected at command startup; restart after changing hardware.

| Hardware | Reported fluid rate | Auto maximum request | Active wait when blocked |
|---|---:|---:|---:|
| Basic / MV | 2,560 L/s | 10,240 L | 0.25 s |
| HV | 10,240 L/s | 40,960 L | 0.10 s |
| EV | 40,960 L/s | 128,000 L | 0.05 s |
| IV | 163,840 L/s | 128,000 L | 0.05 s |

Auto request size is the lesser of four seconds of reported fluid throughput and 128,000 L. `transferWindowSeconds` changes the four-second target. A request is further bounded by the exact remaining recipe requirement and available staged fluid. The driver always rereads the machine after a transfer, including partial or zero transfers. With no rate API, auto mode uses a 128,000 L request ceiling and 0.1 s active wait. Positive numeric `fluidChunk` and `pollSeconds` settings override auto tuning.

Only upgrade the **fluid-input transposer** for this benefit. The tier-specific rate applies to fluids; upgrading the item transposer does not speed up item callbacks. Check NEI for the IV transposer upgrade recipe on your server. Replacing a transposer may change its component UUID; update only its address, retain directions, and rerun `check` and the selected-fluid `probe` before use.

## What changed in the script

- Item inventories use a fresh `getAllStacks().getAll()` snapshot instead of reading every slot through a separate component callback. Older components without snapshots retain the slot-reading fallback.
- Successful transfers and phase transitions advance without an added polling delay. Waiting or blocked transfers back off at the selected active interval; an empty staging area uses `idlePollSeconds` (0.5 s in the template).
- A durable journal checkpoint is written once per phase before its first action. Repeated transfers within a phase reconcile against actual hatch/bus contents after an interruption.
- Redstone writes occur only when changing the requested level. Startup still explicitly sets the signal low and waits one second for the cover to observe it.

Native component calls, file I/O, server ticks and the machine's own recipe duration still take time. The script cannot bypass the transposer's native throughput limit.

## Measured controller overhead

The following are host-side measurements of the real CLI and driver with mocked OC components, a 108-slot staging chest, one batch, and full requested transfers. Old and new rows use the **same IV rate**. These are operation counts, not measured Minecraft wall-clock speedups. The sleep column counts explicitly requested positive sleeps and includes the one-time startup second; native callback costs are excluded.

| Recipe / controller | Fluid requests | Per-slot reads | Bulk snapshots | Journal saves | Redstone writes | Explicit sleep |
|---|---:|---:|---:|---:|---:|---:|
| Samarium 1 / Old IV | 2 | 173 | 0 | 11 | 12 | 3.5 s |
| Samarium 1 / New IV auto | 2 | 5 | 13 | 5 | 3 | 1 s |
| Fresh prismarine / Old IV | 8 | 301 | 0 | 16 | 17 | 4.75 s |
| Fresh prismarine / New IV auto | 2 | 0 | 13 | 5 | 3 | 1 s |
| Monazite 9 / Old IV | 99 | 771 | 0 | 109 | 110 | 28 s |
| Monazite 9 / New IV auto | 2 | 5 | 15 | 5 | 3 | 1 s |

For Monazite 9 on the basic transposer, auto mode reduces 99 fluid requests to 10. IV auto mode needs two requests, one for each fluid. These call counts use the original quad staging source; a fluid spanning two Ingredient Buffer compartments needs an additional request. The simulations pass 127,092 assertions, including all 33 recipes and 66 interruptions after fluid movement; see [TEST-RESULTS.txt](TEST-RESULTS.txt). Live world commissioning remains necessary.

For reference, dividing total input volume by reported rate gives these **bandwidth-only floors**:

| Recipe | Total input fluids | Basic / MV | IV |
|---|---:|---:|---:|
| Samarium leach 1 | 2,000 L | 0.78 s | 0.012 s |
| Fresh prismarine | 8,000 L | 3.13 s | 0.049 s |
| Monazite 9 | 99,000 L | 38.67 s | 0.604 s |

Actual loading takes longer, especially for small batches: both fluid callbacks, inventory checks, phase checkpoints, circuit movement and machine-start observation still run. The IV fluid rate is 64 times basic; that does not make the whole system 64 times faster.

## Update an existing installation

1. Stop upstream feeding. Wait for **“Input batch accepted; ready for next staged lot”**, confirm the machine inputs are empty and both circuits are home, then press Q (Ctrl+C on older versions). A recipe may still be processing; verify its expected products in ME separately. Do not change code/configuration during an unfinished journaled transaction.
2. Back up the six Lua files and any `bindings.dat` while stopped. Download the following **three code files only** into your installation. Keep your configured UUIDs, sides, slots, commissioning flag and local state.

```sh
cd /home/dissolution
wget -f https://raw.githubusercontent.com/dronf/gtnh-dissolution-tank-oc/4f43b67b0c78b62b2d8006a124374009e29ac889/dt.lua dt.lua
wget -f https://raw.githubusercontent.com/dronf/gtnh-dissolution-tank-oc/4f43b67b0c78b62b2d8006a124374009e29ac889/dt_core.lua dt_core.lua
wget -f https://raw.githubusercontent.com/dronf/gtnh-dissolution-tank-oc/4f43b67b0c78b62b2d8006a124374009e29ac889/dt_io.lua dt_io.lua
```

Confirm all three downloads succeeded before continuing. If one fails, retry it or restore all three backed-up code files together. Do not run a mixed version.

3. Run `edit config.lua`. Change the existing tuning values to `fluidChunk='auto'` and `pollSeconds='auto'`. You may add `idlePollSeconds=0.5` and `transferWindowSeconds=4`; those are optional. Preserve your hardware settings, especially `redstone.side='front'` for a computer facing east with its wire on world east.
4. Run `lua dt.lua rates`. After an IV fluid-transposer upgrade it should report **163840 L/s**, a **128000 L** maximum request, and **0.05 s** active wait. With the original basic transposer, expect 2560 L/s, 10240 L and 0.25 s.
5. Run `lua dt.lua check`, stage one known recipe, inspect `lua dt.lua plan`, then `lua dt.lua run`. Verify the real product arrives in ME before unattended feeding.

The fresh installer intentionally refuses an existing installation directory. Do not use it to replace a configured controller.

## Primary implementation references

- [OC transfer implementation](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/server/component/traits/InventoryTransfer.scala): reported rate and rate-dependent native transfer delay.
- [GTNH transposer tiers](https://github.com/GTNewHorizons/NewHorizonsCoreMod/blob/master/src/main/java/com/dreammaster/scripts/ScriptOpenComputers.java): tier-specific fluid rates and upgrade recipes.
- [OC inventory snapshots](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/scala/li/cil/oc/server/component/traits/WorldInventoryAnalytics.scala) and [snapshot array indexing](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/java/li/cil/oc/api/prefab/ItemStackArrayValue.java).

Upstream sources can change. The rate reported by your actual component is the tuning input.
