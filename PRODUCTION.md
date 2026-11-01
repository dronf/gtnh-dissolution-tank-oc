# Moving from the first successful batch to production

The controller's `run` command already watches staging continuously and loads successive exact batches. Its external-output mode finishes an input transaction after the machine consumes the inputs and returns the circuit. It can queue the next batch while production runs. Product delivery is observed by AE2 and the player through the native ME output path.

## Live acceptance checks

1. Confirm the first recipe's expected fluid and any guaranteed item products actually arrived in ME. The input-accepted message alone does not establish this.
2. Install the [performance update](PERFORMANCE.md) while no input transaction is pending. Test one known recipe again and check the signal falls low and the circuit returns home.
3. Stage two exact batches of that same recipe. Verify two input handoffs, no duplicate loads, the circuit's return, and the expected total products in ME. Then test an alternating recipe and circuit 9 as ingredients become available.
4. Keep the computer, transposers, tank, AE2 feeder, ME outputs and their power connections loaded together. Provide dependable power, clear maintenance faults and ensure the ME destination has capacity.
5. Back up the configured HDD while stopped. After a reboot, inspect physical inputs, circuits and machine state before using `unlock` and `resume` for a retained transaction, or `run` when none exists. Automatic startup/recovery is not installed by this package.

## AE2 crafting on demand

Use processing patterns with the exact consumed items and fluids from NEI, targeting the **separate staging inventories**. Omit reusable circuits: the controller supplies and retrieves those. Advertise the guaranteed outputs that return through the ME Output Hatch/Bus. Do not require chance-based samarium byproducts as guaranteed crafting returns.

**Serialize deliveries across both staging buffers.** Different recipe lots must not overlap. A blocking interface that checks only the chest does not establish that the fluid staging hatch is empty, and several supported recipes have no consumed items at all. Partial pattern delivery is safe only while it remains isolated from every other recipe: the controller waits for a complete bound recipe and rejects unrelated/excess materials.

Before opening all 33 patterns, verify your chosen fluid-capable AE2 provider arrangement can deliver one complete lot to both buffers and prevent the next recipe from entering until that lot has been handed off. First test one request, then a request for several batches, then simultaneous requests for two different recipes. Inspect both buffers and confirm AE2 receives the expected outputs. Keep feeding limited to the tested arrangement until those checks pass.

The package does not yet provide an AE2 dispatch handshake or create patterns. Its continuous watcher and strict matching support on-demand feeding, but end-to-end queue isolation must be supplied and verified in the upstream feeder. A generic chest-only blocking setup is insufficient for this two-buffer layout.
