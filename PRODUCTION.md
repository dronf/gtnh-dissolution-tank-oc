# Production operation, Q quit key, and OpenOS autostart

`lua dt.lua run` is already a continuous watcher. Leave it running: it identifies exact staged lots, meters fluids, loads consumed items, inserts the reusable circuit last, enables starts, and returns the circuit after input acceptance. Native ME outputs deliver products. The input-accepted message does not certify finished products or their delivery.

## Install the Q quit-key update

Stop feeding and wait for **“Input batch accepted; ready for next staged lot”** with the inputs empty and both circuits home. Stop the old controller before changing code. If an unfinished transaction remains, inspect and finish/recover it using the matching old files first. Back up your existing Lua files while stopped.

Download these **two code files only**. Keep your configuration, addresses and local state:

```sh
cd /home/dissolution
wget -f https://raw.githubusercontent.com/dronf/gtnh-dissolution-tank-oc/4f43b67b0c78b62b2d8006a124374009e29ac889/dt.lua dt.lua
wget -f https://raw.githubusercontent.com/dronf/gtnh-dissolution-tank-oc/4f43b67b0c78b62b2d8006a124374009e29ac889/dt_core.lua dt_core.lua
```

Check that both downloads succeeded before running. Retry failed downloads or restore both backed-up files together; do not run mixed versions. This update assumes you already installed the rate-aware `dt_io.lua`; older installations should complete [the performance update](PERFORMANCE.md) first.

Run `lua dt.lua run`. While the OC terminal is focused, press **Q** (uppercase also works) to quit. The program lowers the start signal, removes its process lock, unregisters its keyboard handler and leaves the shell available. It checks for a quit request before committing after an inventory read. An already executing component call must return first; a fluid call on basic hardware can take several seconds. A machine recipe already started can finish.

If Q stops during input loading or before the circuit comes home, the transaction remains. Inspect the machine and use `lua dt.lua resume` to continue it. If there is no pending transaction, use `lua dt.lua run`. Do not clear a legitimate transaction simply to restart.

## Foreground autostart on this dedicated computer

Yes: after the live checks below, enable foreground autostart so the terminal shows status and Q remains the operator stop key. Run:

```sh
edit /home/.shrc
```

Add this **one line**, preserving any existing contents:

```sh
lua /home/dissolution/dt.lua run
```

Do not also start a background copy or add a second startup command. OpenOS sources `/home/.shrc` from its profile. The foreground controller runs until Q or a fault, then returns to the prompt. Q does not restart it automatically in a loop. To disable autostart, press Q and remove the line from `.shrc`.

**This retains the existing recovery guards.** Autostart refuses a leftover `controller.lock` or unfinished transaction. A power cut or reboot while the controller was running can leave a lock even if it was merely idle; autostart then stops for inspection. Confirm no controller is running, inspect the inputs/circuits and machine, run `lua dt.lua unlock`, then use `resume` for a retained transaction or `run` if none exists. It never automatically unlocks, erases state, or replays an uncertain batch. Cleanly press Q before a planned reboot to allow normal automatic startup afterward.

Keep the computer, both transposers, machine, ME interfaces/outputs and their power loaded together. Ensure reliable power, no maintenance fault, and ME storage capacity. Back up the configured HDD while stopped. This setup launches after **OpenOS boots**; it does not remotely power on a computer that remains switched off.

## AE2 on-demand feeding: recommended production layout

For unattended mixed recipes, use **one Ingredient Buffer** as the shared item-and-fluid staging block. Feed it from **one ME Dual Interface**. The ingredient buffer exposes both an item inventory and fluid compartments, allowing the same provider's blocking mode to see the complete staged lot. Your current separate chest and staging quad can still be used for manual operation; ordinary chest-only blocking cannot isolate their combined contents.

The checked AE2FC **1.5.116-gtnh** Ingredient Buffer has **9 item slots and four 64,000 L fluid compartments**. Large Ingredient Buffer has 27 slots and seven 64,000 L compartments. The standard buffer has enough capacity for every single recipe in this catalog: a 90,000 L input spans two compartments. The driver sums matching staged fluids and transfers from each source compartment; all 33 recipes pass simulations with 64,000 L source compartments. The actual machine input remains the **LuV Quad Input Hatch**, with 128,000 L per compartment.

1. Stop the feeder/controller with no unfinished transaction and confirm circuits are home. Place the Ingredient Buffer face-adjacent to **both** transposers. Change `inputFluids.stageSide` and `inputItems.stageSide` to point at that same buffer, using absolute world directions from each transposer. Both `machineSide='down'` entries stay appropriate if the transposers remain above the hatch and bus. Keep the circuit locker on a separate face of the item transposer and adjust `lockerSide` if it moves. OC cables let the computer connect without occupying the buffer's space.
2. Place a full-block **ME Dual Interface**, connected to the main ME network, with its output directed at **only the Ingredient Buffer**. Leave its stock/keep-supplied slots empty. This is one shared pattern provider for the tank; do not run separate unsynchronized item/fluid providers or multiple providers feeding the same buffer.
3. Enable ordinary **blocking mode**. Disable **Smart Blocking** for initial production. Fit a **Locking Card**, select **Lock Crafting → Until crafting result is returned**, and disable **Allow pattern optimization** if available. Start with one-batch patterns and no pattern multiplication. This serializes requests until the declared guaranteed products enter the same ME network, while blocking mode also prevents mixing whenever items or fluids remain staged. Do not direct one interface into both separate staging blocks: use the single shared target.
4. Encode **processing** patterns with exact consumed items and fluid liters from NEI/the catalog, **omitting reusable circuits**. Declare guaranteed outputs only. Chance-based samarium byproducts must not be required returns. The Dual Interface handles actual fluids; an ordinary ME Interface can emit fluid packets instead. Add Pattern Capacity Cards as needed; three additional rows provide 36 pattern slots for the 33 recipes, leaving the fourth upgrade slot for the Locking Card.
5. Keep the existing native ME Output Hatch and ME Output Bus connected to that same ME network. Do not send those outputs back into staging. The OC controller neither creates patterns nor reports craft completion; AE2 sees the actual returned products.

Example **top view only** for diagonally separated transposers (rotate to match your build):

```text
                     North
       [Fluid TP]   [Ingredient Buffer] <-- ME Dual Interface
       [free]       [Item TP] -- Circuit locker
                     South
```

In this example the fluid transposer's `stageSide='east'`, the item transposer's `stageSide='north'`, and its `lockerSide='east'`. Both machine sides are down. The buffer is level with the transposers, not balanced above their diagonal corner. This diagram assumes no computer/locker already occupies those cells: rearrange cable-connected components or rotate the layout as needed. Change sides only after finishing the existing transaction.

## Live production acceptance checks

1. Run `lua dt.lua check`. Put a small test fluid in the new buffer, use `lua dt.lua scan` to identify its compartment, then `lua dt.lua probe N` with that nonempty compartment number. Confirm exactly one liter transfers and returns. Remove test contents before production.
2. Install one known processing pattern. Request one batch in AE2. Confirm complete staged ingredients, the correct plan, one machine start, circuit return and expected products in ME. Confirm the interface unlocks on the real result.
3. Request several batches, then two different recipes concurrently. The provider must keep its lots separate and both AE2 jobs must finish without leftovers. Confirm a fluid-only recipe works too. Expand to circuit 9 and the 90,000 L inputs as ingredients become available; inspect exact liter totals when a fluid spans compartments.
4. Test Q while idle; restart with `run`. Test Q during loading under supervision, inspect and `resume`, and verify no duplicate products/inputs. Test a planned reboot after Q and confirm `.shrc` starts exactly one controller. A leftover journal/lock should stop automatic operation for inspection.
5. Add the remaining patterns gradually. If a result never returns, the result lock is expected to hold. Diagnose machine power/maintenance, output storage and guaranteed pattern amounts; do not blindly unlock/repeat a recipe whose inputs were already consumed.

## References and limits

This production layout is inferred from the implementations in the **installed pack's versions**, not an in-world AE2 integration test. Hardware direction/probe checks and the live acceptance steps are required.

- [OpenOS profile](https://github.com/GTNewHorizons/OpenComputers/blob/master/src/main/resources/assets/opencomputers/loot/openos/etc/profile.lua): sources `.shrc` as shell commands.
- [AE2 rv3-beta-1095-GTNH interface](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/rv3-beta-1095-GTNH/src/main/java/appeng/helpers/DualityInterface.java): blocking, fluid-aware pattern dispatch, result lock and item/fluid result interception.
- [AE2 fluid/item inventory adapter](https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial/blob/rv3-beta-1095-GTNH/src/main/java/appeng/util/inv/AdaptorFluidHandler.java): shared item/fluid insertion and emptiness checks.
- [AE2FC Ingredient Buffer](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/1.5.116-gtnh/src/main/java/com/glodblock/github/common/tile/TileIngredientBuffer.java), [Large Ingredient Buffer](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/1.5.116-gtnh/src/main/java/com/glodblock/github/common/tile/TileLargeIngredientBuffer.java), and [fluid inventory](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/1.5.116-gtnh/src/main/java/com/glodblock/github/inventory/AEFluidInventory.java): capacities, inventory access and fluid spanning.
