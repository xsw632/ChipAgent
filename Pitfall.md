# Critical Pitfalls — Chipyard → ORFS PnR Flow

These are non-obvious failure modes discovered through production runs. **Every one of these will cause the flow to fail silently or catastrophically if ignored.**

## Pitfall 0: TinyRocket default caches overflow 16 GB RAM at PDN (CRITICAL)

**Problem:** Default `With1TinyCore` uses D$ nSets=256 (16 KB scratchpad) and I$ nSets=64 (4 KB). This produces behavioral arrays of depth **4096** (D$ data) and **1024** (I$ data). sky130 SRAM macros max out at 256 deep, so a faithful mapping needs 16-way and 4-way depth tiling. With ~4 D$ banks × 16 tiles = ~64 macros plus icache/tag → **70+ physical SRAM macros**, die explodes to ~10000×10000 µm, and `pdngen` stdcell grid insertion (`[INFO PDN-0001] Inserting grid: grid`) peaks at **~14 GB RSS** → OOM killed on a 16 GB system.

**Verify the symptom:** the floorplan log dies with `Command terminated by signal 9` immediately after `Inserting grid: grid` (before any macro grid lines). `mems.conf` shows `data_arrays_0_0_ext depth 4096`. `2_2_floorplan_macro.tcl` has 50+ lines.

**Why simplifying PDN does NOT fix it:** the bottleneck is the stdcell met4/met5 stripe graph, which scales with die area. Die area is driven by SRAM macro count. Adding swap also doesn't help — OOM killer triggers on RSS, not virtual memory; swap thrash just delays the kill.

**Solution:** Shrink the Chipyard cache config so each array fits in one sky130 SRAM macro (depth ≤ 256). Edit `generators/rocket-chip/src/main/scala/subsystem/Configs.scala`, change `With1TinyCore`'s `dcache.nSets` from 256→16 and `icache.nSets` from 64→16 (1 KB caches each). After this, `mems.conf` shows depth ≤ 256, override needs only ~6 macros, die ~2551×2551 µm, PDN peak **~4.5 GB**, full flow fits in 7 GB.

Trade-off: 1 KB caches are functional but tiny. Only suitable for baremetal/bringup demos, not Linux. Verified: 50 MHz target → fmax 50.56 MHz, WNS 0, TNS 0, DRC 0, 189 MB GDS, route peak 6.5 GB.

## Pitfall 1: FF-based SRAMs cause OOM in routing (CRITICAL)

**Problem:** If behavioral SRAM modules (`data_arrays_0_0_ext`, etc.) are synthesized to flip-flops, the design explodes from ~100K cells to millions of cells. Detailed routing (`5_2_route`) will be killed by OOM killer (signal 9) at 13+ GB memory.

**Root cause:** `data_arrays_0_0_ext` is 4096x8 = 32,768 flip-flops per instance. With multiple instances, this creates hundreds of thousands of FFs that bloat the design.

**Solution:** Use the **nosram + SRAM override** approach:
1. Use the Chipyard-generated behavioral Verilog as-is (modules are undefined external modules)
2. Provide `sram_override.v` that replaces behavioral SRAMs with `sky130_sram_*` macro instantiations
3. Blackbox the `sky130_sram_*` macros during synthesis via `SYNTH_BLACKBOXES`
4. Provide LEF/LIB/GDS files so OpenROAD can place the physical SRAM macros

**NEVER** provide behavioral SRAM stubs (reg arrays) as substitutes — this causes the OOM problem.

## Pitfall 2: ENABLE_YOSYS_FLOW is mandatory

**Problem:** Without `ENABLE_YOSYS_FLOW=1`, firtool emits SystemVerilog packed-array patterns (`wire [2:0][8:0] _GEN = '{9'h0, ...}`) that Yosys cannot parse, causing `ERROR: syntax error, unexpected OP_CAST` in `1_1_yosys_canonicalize`.

**Solution:** Always pass `ENABLE_YOSYS_FLOW=1` to `make buildfile` or `make verilog`. In Chipyard's `vlsi/tutorial.mk`, the `sky130-openroad` tutorial already sets this flag, but verify it is set.

**What it does** (from `chipyard/common.mk`):
1. Enables SFC LowFIRRTL lowering with `ReplSeqMem` for SRAM extraction
2. Appends `disallowPackedArrays` to MFC lowering options

## Pitfall 3: Duplicate module definitions

**Problem:** If you concatenate `EICG_wrapper.v`, `IOCell.v`, `plusarg_reader.v` files AND they are already in the `top.f` filelist, Yosys errors: `ERROR: Re-definition of module \EICG_wrapper!`

**Solution:** Only concatenate files from the `top.f` filelist (which already includes stubs). Do NOT manually append stub files that are already in the list.

## Pitfall 4: SYNTH_MEMORY_MAX_BITS too small (if using behavioral fallback)

**Problem:** If you fall back to behavioral SRAMs (FF-based), ORFS errors: `Error: Synthesized memory size 4096 exceeds SYNTH_MEMORY_MAX_BITS`

**Solution:** Set `SYNTH_MEMORY_MAX_BITS = 131072` in config.mk. But this only applies to the FF-based fallback — the preferred SRAM macro approach does NOT need this.

## Pitfall 5: SRAM blackbox cost information

**Problem:** If you use `(* blackbox *)` attribute on SRAM modules without providing LEF/LIB, ORFS errors: `ERROR: Missing cost information on instanced blackbox sram22_*`

**Solution:** Do NOT use custom sram22 blackbox stubs. Instead, use the ORFS-provided `sky130_sram_*` macros which have LEF/LIB/GDS files. Set `SYNTH_BLACKBOXES` in config.mk and provide `ADDITIONAL_LEFS/LIBS/GDS`.

## Pitfall 6: Chipyard VLSI flow vs simulation flow

**Problem:** `make verilog` (simulation flow) generates TestHarness + ChipTop in split SV files. `make buildfile` (VLSI flow) generates ChipTop-only in `top.f` filelist with SRAM MacroCompiler output.

**Solution:** Use the **VLSI flow** (`make buildfile tutorial=sky130-openroad`) for ORFS. It produces a clean `top.f` filelist (ChipTop only, no TestHarness) and SRAM wrapper modules. The simulation flow includes TestHarness modules that are not needed and complicate the design.
