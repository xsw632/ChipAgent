---
name: chipyard-pnr
description: "Run ORFS PnR flow on Chipyard-generated Verilog with sky130hd SRAM macros. Handles nosram preprocessing, SRAM override generation, ABC exclusion, OOM management, and all Chipyard-specific pitfalls."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - mcp__chipagent-backend__check_environment
  - mcp__chipagent-backend__generate_config
  - mcp__chipagent-backend__run_stage
  - mcp__chipagent-backend__get_report
  - mcp__chipagent-backend__diagnose_failure
  - mcp__chipagent-backend__clean_design
  - mcp__chipagent-backend__compare_runs
---

# chip-agent:chipyard-pnr

Physical implementation pipeline for Chipyard-generated SoC designs with SRAM macros on sky130hd. Handles all Chipyard-specific preprocessing (nosram stripping, SRAM override generation), ORFS configuration tuning, and known pitfalls that differ from standard-cell-only PnR.

## Usage

```
/chip-agent:chipyard-pnr <ConfigName>
```

**Example:**

```
/chip-agent:chipyard-pnr TinyRocketConfig
```

## Instructions

**Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Use that directory as the base for all relative paths below.

## Critical Pitfalls Reference

These issues were discovered through multiple PnR iterations on TinyRocketConfig. Each is marked with [PITFALL] in the pipeline steps below.

| # | Pitfall | Root Cause | Fix | Severity |
|---|---------|-----------|-----|----------|
| 1 | ABC SIGABRT crash during synth | sky130ram liberty files cause ABC to crash in technology mapping | Exclude ADDITIONAL_LIBS from ABC lib_args in synth_preamble.tcl | CRITICAL |
| 2 | Module redefinition errors | Chipyard Verilog has split_* sub-modules that conflict with SRAM overrides | Preprocess to strip _ext and split_* modules, create _nosram.v | CRITICAL |
| 3 | Floorplan OOM (>13.9GB) | OpenROAD with default 20 threads exceeds 15GB RAM | Set NUM_CORES=4 (NOT OPENROAD_NUM_THREADS) | HIGH |
| 4 | Route OOM during antenna repair | Antenna repair triggers second full route pass (2x memory) | Set SKIP_ANTENNA_REPAIR_POST_DRT=1 | HIGH |
| 5 | IR drop PSM-0069 VDD connectivity | SRAM macro halo blocks met1-met4 PDN vias near die edge | Set PWR_NETS_VOLTAGES= and GND_NETS_VOLTAGES= (empty) | MEDIUM |
| 6 | ABC9 crash (SWAP_ARITH_OPERATORS) | SWAP_ARITH_OPERATORS=1 triggers unstable ABC9 on large designs | Use ABC_AREA=1 instead, never set SWAP_ARITH_OPERATORS | HIGH |
| 7 | SRAM power pins not connected | SRAM LEF uses lowercase vdd/gnd, some pdn.tcl only map uppercase | Verify pdn.tcl has lowercase add_global_connection entries | HIGH |
| 8 | NUM_CORES vs OPENROAD_NUM_THREADS | OPENROAD_NUM_THREADS is ignored; NUM_CORES controls -threads | Always use NUM_CORES in config.mk | CRITICAL |

## Pipeline

### Step 0 -- Verify Prerequisites

Set up variables:

```bash
PLUGIN_ROOT="<plugin-root>"
CONFIG="$ARGUMENTS"   # e.g. TinyRocketConfig
```

**Normalize config name** (same logic as chipyard skill):
- If all lowercase: capitalize first letter, append `Config`
- If has uppercase but no `Config` suffix: append `Config`
- If empty: default to `TinyRocketConfig`

Check that staged Chipyard Verilog exists:

```bash
test -f "$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/generated/$CONFIG.v"
```

- If **missing**: STOP with:
  ```
  No Chipyard Verilog found for $CONFIG.
  Run `/chip-agent:chipyard $CONFIG` first.
  ```
- If **exists**: continue.

Check for SRAM mapping file:

```bash
test -f "$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/generated/sram_mapping.json"
```

- If **missing**: warn the user but continue (SRAM steps will be skipped).

### Step 1 -- Check Environment

Call `mcp__chipagent-backend__check_environment` with no arguments.

Verify:
- `orfs.installed` must be `true`
- `sky130hd.installed` must be `true`

Extract and save:
- `ORFS_FLOW_PATH` = `orfs.flow_path`

Also verify the synth_preamble.tcl ABC exclusion patch is present:

```bash
grep -q "Skipping ADDITIONAL_LIBS entry from ABC" "$ORFS_FLOW_PATH/scripts/synth_preamble.tcl"
```

- If **missing**: STOP with:
  ```
  [PITFALL-1] synth_preamble.tcl is missing the ABC exclusion patch.
  Without this, ABC will SIGABRT when SRAM liberty files are loaded.
  Apply the patch from Appendix A before continuing.
  ```

Verify sky130ram SRAM macros are available:

```bash
test -d "$ORFS_FLOW_PATH/platforms/sky130ram" && \
  ls "$ORFS_FLOW_PATH/platforms/sky130ram"/sky130_sram_*/ 2>/dev/null | head -5
```

- If **missing**: STOP with:
  ```
  sky130ram SRAM macros not found in $ORFS_FLOW_PATH/platforms/sky130ram.
  These are required for Chipyard SoC PnR.
  ```

Verify pdn.tcl has lowercase power pin mappings [PITFALL-7]:

```bash
grep -q 'pin_pattern {^vdd$}' "$ORFS_FLOW_PATH/platforms/sky130hd/pdn.tcl" && \
  grep -q 'pin_pattern {^gnd$}' "$ORFS_FLOW_PATH/platforms/sky130hd/pdn.tcl"
```

- If **missing**: warn the user:
  ```
  [PITFALL-7] pdn.tcl lacks lowercase vdd/gnd global connections.
  SRAM macro power pins will not connect to PDN.
  Add the two add_global_connection lines from Appendix B.
  ```

### Step 2 -- Nosram Preprocessing

**Purpose:** Chipyard-generated Verilog contains behavioral memory modules (e.g., `data_arrays_0_ext`, `split_data_arrays_0_ext`) that conflict with SRAM override definitions. We must strip these out to create a "nosram" version. [PITFALL-2]

**2a. Identify memory modules to strip:**

```bash
SRC_V="$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/generated/$CONFIG.v"
# Find all _ext memory module definitions
grep -n '^module.*_ext\b' "$SRC_V"
```

Also find `split_*` modules that wrap the `_ext` modules:

```bash
grep -n '^module split_.*_ext\b' "$SRC_V"
```

**2b. Create nosram Verilog:**

Strip all `_ext` and `split_*_ext` module definitions from the base Verilog. Use a Python one-liner:

```bash
NOSRAM_V="$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/generated/${CONFIG}_nosram.v"

python3 -c "
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
# Remove module definitions for *_ext and split_*_ext modules
content = re.sub(
    r'^module\s+(?:split_)?\w+_ext\b.*?^endmodule',
    '',
    content,
    flags=re.MULTILINE | re.DOTALL
)
# Clean up excessive blank lines
content = re.sub(r'\n{4,}', '\n\n', content)
with open(sys.argv[2], 'w') as f:
    f.write(content)
" "$SRC_V" "$NOSRAM_V"

echo "Created: $NOSRAM_V ($(wc -l < "$NOSRAM_V") lines)"
```

**2c. Verify no _ext modules remain:**

```bash
grep -c '^module.*_ext\b' "$NOSRAM_V"
# Should be 0
```

If non-zero, the regex did not catch all modules. Inspect and fix manually.

### Step 3 -- Generate SRAM Override Verilog

**Purpose:** Create wrapper modules that instantiate sky130hd SRAM macros in place of the stripped behavioral memories. The override file is loaded after the nosram Verilog, so ORFS "last definition wins" redefines the `_ext` modules with SRAM-based implementations.

**3a. Read sram_mapping.json:**

```bash
cat "$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/generated/sram_mapping.json"
```

Extract the mapping list. For each memory with `strategy: "sram_macro"` or `strategy: "multi_macro_tiling"`:
- `rtl_module`: the `_ext` module name
- `depth`, `width`, `ports`, `mask_gran`
- `macro`: target sky130hd SRAM macro name
- `tiles`: number of depth tiles (if > 1)

**3b. Generate override Verilog:**

For each mapped memory, generate a Verilog module that:
1. Matches the original `_ext` module port interface exactly
2. Instantiates the appropriate sky130hd SRAM macro(s)
3. Handles address decoding for depth-tiling (> 1 tile)
4. Handles width tiling (multiple macros side-by-side for wide data)
5. Connects byte-level write masks from the original port interface to the macro's wmask

**Override module template -- single macro (1 tile):**

```verilog
module <ext_module_name>(
  input  [ADDR_W-1:0] RW0_addr,
  input                RW0_clk,
  input  [DATA_W-1:0]  RW0_wdata,
  output [DATA_W-1:0]  RW0_rdata,
  input                RW0_en,
  input                RW0_wmode,
  input  [MASK_W-1:0]  RW0_wmask   // only if masked
);

  wire csb0 = ~RW0_en;
  wire web0 = ~RW0_wmode;
  wire [<WMASK_W-1>:0] wmask0 = <computed from RW0_wmask>;

  wire [<MACRO_DATA_W-1>:0] dout0;
  wire [<MACRO_DATA_W-1>:0] dout1;

  sky130_sram_<macro_suffix> u_sram (
    .clk0   (RW0_clk),
    .csb0   (csb0),
    .web0   (web0),
    .wmask0 (wmask0),
    .addr0  (RW0_addr),
    .din0   ({<pad>, RW0_wdata}),
    .dout0  (dout0),
    .clk1   (RW0_clk),
    .csb1   (1'b1),       // read port disabled
    .addr1  ({<ADDR_W>{1'b0}}),
    .dout1  (dout1)
  );

  assign RW0_rdata = dout0[<DATA_W-1>:0];
endmodule
```

**Override module template -- depth-tiled (N tiles):**

When memory depth > single macro depth (256 for sky130_sram_1rw1r_128x256_8), use N tiles:

```verilog
module <ext_module_name>(
  input  [ADDR_W-1:0] RW0_addr,
  input                RW0_clk,
  input  [DATA_W-1:0]  RW0_wdata,
  output [DATA_W-1:0]  RW0_rdata,
  input                RW0_en,
  input                RW0_wmode,
  input  [MASK_W-1:0]  RW0_wmask   // only if masked
);

  wire [<TILE_SEL_W-1>:0] tile_sel = RW0_addr[ADDR_W-1 -: TILE_SEL_W];
  wire [7:0] macro_addr = RW0_addr[7:0];  // lower 8 bits for 256-deep macros

  wire csb0 = ~RW0_en;
  wire web0 = ~RW0_wmode;

  genvar i;
  generate
    for (i = 0; i < <N>; i = i + 1) begin : gen_sram_tile
      wire [<MACRO_DATA_W-1>:0] dout0_tile;
      wire [<MACRO_DATA_W-1>:0] dout1_tile;
      wire [<WMASK_W-1>:0] wmask0 = <computed>;

      sky130_sram_<macro_suffix> u_sram (
        .clk0   (RW0_clk),
        .csb0   (csb0 | (tile_sel != i[<TILE_SEL_W-1>:0])),
        .web0   (web0),
        .wmask0 (wmask0),
        .addr0  (macro_addr),
        .din0   ({<pad>, RW0_wdata}),
        .dout0  (dout0_tile),
        .clk1   (RW0_clk),
        .csb1   (1'b1),
        .addr1  (8'b0),
        .dout1  (dout1_tile)
      );
    end
  endgenerate

  // MUX read data from active tile
  reg [DATA_W-1:0] rdata_reg;
  always @(*) begin
    rdata_reg = {DATA_W{1'b0}};
    case (tile_sel)
      <case for each tile: N'd0: rdata_reg = dout0_tile_N[DATA_W-1:0];>
      default: rdata_reg = {DATA_W{1'b0}};
    endcase
  end
  assign RW0_rdata = rdata_reg;
endmodule
```

**Width tiling for byte-lane architectures (like DCache data array):**

When a memory has byte-masked writes with width > macro width, decompose into per-byte-lane groups, each with its own depth tiling:

```verilog
genvar byte_lane, tile;
generate
  for (byte_lane = 0; byte_lane < NUM_BYTE_LANES; byte_lane = byte_lane + 1) begin : gen_byte_lane
    for (tile = 0; tile < NUM_DEPTH_TILES; tile = tile + 1) begin : gen_sram_tile
      // Each byte lane + tile gets one SRAM macro
      // Per-byte wmask: wmask0[0] = RW0_wmask[byte_lane]
      ...
    end
    // MUX per byte lane
    ...
    assign RW0_rdata[byte_lane*8 +: 8] = rdata_lane;
  end
endgenerate
```

**3c. Write the override file:**

```bash
OVERRIDE_V="$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/generated/${CONFIG}_sram_override.v"
# Write the generated override Verilog to this path
```

**3d. Verify override module port interfaces match the original:**

For each override module, confirm its ports exactly match what the nosram Verilog expects:

```bash
# Extract module instantiation from nosram Verilog
grep -A5 '<ext_module_name>' "$NOSRAM_V" | head -10
# Compare with override module definition
grep -A5 'module <ext_module_name>' "$OVERRIDE_V" | head -10
```

### Step 4 -- Install Design Files into ORFS

Copy all design files into the ORFS directory structure:

```bash
DESIGN_HOME="$ORFS_FLOW_PATH/designs"
DESIGN_DIR="$DESIGN_HOME/sky130hd/tinyRocket"
SRC_DIR="$DESIGN_HOME/src/tinyRocket"
mkdir -p "$DESIGN_DIR" "$SRC_DIR"

# Copy nosram Verilog
cp "$NOSRAM_V" "$SRC_DIR/$(basename "$NOSRAM_V")"

# Copy SRAM override Verilog
cp "$OVERRIDE_V" "$DESIGN_DIR/$(basename "$OVERRIDE_V")"
```

### Step 5 -- Generate Config

**5a. Read spec.json for clock parameters:**

```bash
cat "$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/spec.json"
```

Extract:
- `clock_port` (default: `"clock"`)
- `clock_period_ns` (default: `10`)

**5b. Determine the top-level module:**

For Chipyard designs, the actual synthesis top module is typically NOT `ChipTop`. Instead it's the core tile module. First check spec.json for `pnr_top_module`:

```bash
PNR_TOP=$(python3 -c "import json; d=json.load(open('$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/spec.json')); print(d.get('pnr_top_module',''))" 2>/dev/null)
```

If `pnr_top_module` is set and non-empty, use it. Otherwise, auto-detect:

```bash
if [ -z "$PNR_TOP" ]; then
    # Common Chipyard top modules for PnR synthesis:
    # - TinyRocketConfig -> RocketTile
    # - Other configs may differ -- check the Verilog hierarchy
    PNR_TOP=$(grep -o 'module [A-Za-z]*Tile ' "$NOSRAM_V" 2>/dev/null | head -1 | awk '{print $2}')
    if [ -z "$PNR_TOP" ]; then
        PNR_TOP="ChipTop"  # fallback
    fi
fi
echo "PnR top module: $PNR_TOP"
```

**IMPORTANT:** The `DESIGN_NAME` in config.mk must be the tile-level module (e.g., `RocketTile`), NOT `ChipTop`. `ChipTop` includes the TestHarness which is not needed for PnR.

**5c. Call `mcp__chipagent-backend__generate_config`:**

```bash
mcp__chipagent-backend__generate_config(
  module_name = "$PNR_TOP"
  verilog_path = absolute path to $NOSRAM_V
  workspace_dir = absolute path to MyDesign/$CONFIG/workspace
  clock_port = from spec.json
  clock_period_ns = from spec.json
  core_utilization = 55    # [PITFALL-3] Higher than default 40 for SRAM-heavy designs
)
```

**5d. Post-process config.mk with SRAM parameters:**

The MCP tool generates a basic config.mk. We must add SRAM-specific parameters. Read the generated config.mk, then append/edit:

```makefile
# === SRAM Configuration (added by chipyard-pnr skill) ===

export DESIGN_NICKNAME = tinyRocket
export VERILOG_FILES = \
    $(DESIGN_HOME)/src/tinyRocket/TinyRocketConfig_nosram.v \
    $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/TinyRocketConfig_sram_override.v \
    $(PLATFORM_DIR)/../sky130ram/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8.v \
    $(PLATFORM_DIR)/../sky130ram/sky130_sram_1rw1r_44x64_8/sky130_sram_1rw1r_44x64_8.v

# Blackbox SRAM macros during synthesis [PITFALL-1 prerequisite]
export SYNTH_BLACKBOXES = sky130_sram_1rw1r_128x256_8 sky130_sram_1rw1r_44x64_8

# SRAM macro library paths
SRAM_DIR = $(PLATFORM_DIR)/../sky130ram
export ADDITIONAL_LEFS = \
    $(SRAM_DIR)/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8.lef \
    $(SRAM_DIR)/sky130_sram_1rw1r_44x64_8/sky130_sram_1rw1r_44x64_8.lef
export ADDITIONAL_LIBS = \
    $(SRAM_DIR)/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8_TT_1p8V_25C.lib \
    $(SRAM_DIR)/sky130_sram_1rw1r_44x64_8/sky130_sram_1rw1r_44x64_8_TT_1p8V_25C.lib
export ADDITIONAL_GDS = \
    $(SRAM_DIR)/sky130_sram_1rw1r_128x256_8/sky130_sram_1rw1r_128x256_8.gds \
    $(SRAM_DIR)/sky130_sram_1rw1r_44x64_8/sky130_sram_1rw1r_44x64_8.gds

# Prevent ABC from mapping to SRAM cells [PITFALL-1 complementary]
export DONT_USE_CELLS += sky130_sram_1rw1r_128x256_8 sky130_sram_1rw1r_44x64_8

# Hierarchical synthesis to preserve SRAM black box instances
export SYNTH_HIERARCHICAL = 1
export SYNTH_MINIMUM_KEEP_SIZE ?= 1000

# Area-optimized ABC [PITFALL-6: never use SWAP_ARITH_OPERATORS]
export ABC_AREA = 1

# Design-specific physical parameters
export CORE_UTILIZATION = 55
export PLACE_DENSITY = 0.65
export MACRO_PLACE_HALO = 20 20

# CTS tuning
export CTS_CLUSTER_SIZE = 20
export CTS_CLUSTER_DIAMETER = 50

export TNS_END_PERCENT = 100

# [PITFALL-4] Skip antenna repair to avoid OOM during route
export SKIP_ANTENNA_REPAIR_POST_DRT = 1

# [PITFALL-3/PITFALL-8] Thread control: NUM_CORES (not OPENROAD_NUM_THREADS)
# 4 threads: good balance for 15GB RAM systems
# For <12GB RAM, use NUM_CORES=1
export NUM_CORES = 4

# [PITFALL-5] Skip IR drop analysis (SRAM halo blocks PDN vias)
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
```

**Adaptive NUM_CORES based on system RAM:**

```bash
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))

if [ "$TOTAL_RAM_GB" -lt 12 ]; then
    NUM_CORES=1
elif [ "$TOTAL_RAM_GB" -lt 16 ]; then
    NUM_CORES=4
else
    NUM_CORES=8
fi
```

**5e. Generate constraint.sdc:**

```tcl
set clk_name clock
set clk_period <from spec.json, default 10.0>
set clk_port [get_ports $clk_name]
create_clock $clk_port -name $clk_name -period $clk_period
set_input_delay 0.0 -clock $clk_name [all_inputs]
set_output_delay 0.0 -clock $clk_name [all_outputs]
set_clock_uncertainty 0.5 $clk_name
set_dont_use sky130_fd_sc_hd__probe_p_8
set_dont_use sky130_fd_sc_hd__probec_p_8
```

Write this to `$PLUGIN_ROOT/MyDesign/$CONFIG/workspace/pnr/constraint.sdc` and also copy to `$DESIGN_DIR/constraint.sdc`.

**5f. Save variables:**

- `CONFIG_MK` = path to the generated config.mk
- `DESIGN_NAME` = the tile module name (e.g., `RocketTile`)

### Step 5.5 -- Clear QoR History

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"clear"`
- `workspace_dir`: absolute path to `MyDesign/$CONFIG/workspace`

### Step 6 -- Run Comparison Rounds

**MANDATORY: All rounds must run to completion.**

Stage ordering: `STAGE_ORDER = ["synth", "floorplan", "place", "cts", "route", "finish"]`

**Round plans for Chipyard+SRAM designs:**

Unlike standard-cell PnR, Chipyard designs with SRAM macros need specific parameter ranges:

- **Round 1 baseline:**
  ```json
  {
    "clock_period_ns": 10,
    "core_utilization": 55,
    "place_density": 0.65,
    "num_cores": "<adaptive from Step 5d>",
    "skip_antenna_repair": true,
    "sram_aware": true
  }
  ```

- **Round 2** (if synth_cell_count > 5000):
  ```json
  {
    "clock_period_ns": 12.5,
    "core_utilization": 50,
    "place_density": 0.60,
    "num_cores": "<same>",
    "skip_antenna_repair": true,
    "sram_aware": true
  }
  ```

- **Round 3** (aggressive relaxation):
  ```json
  {
    "clock_period_ns": 15,
    "core_utilization": 45,
    "place_density": 0.55,
    "num_cores": "<same>",
    "skip_antenna_repair": true,
    "sram_aware": true
  }
  ```

**CRITICAL: SRAM-aware config regeneration:**

When regenerating config for each round/retry, you MUST preserve all SRAM-related parameters (VERILOG_FILES, SYNTH_BLACKBOXES, ADDITIONAL_*, DONT_USE_CELLS, SYNTH_HIERARCHICAL, ABC_AREA, SKIP_ANTENNA_REPAIR_POST_DRT, NUM_CORES, PWR_NETS_VOLTAGES, GND_NETS_VOLTAGES, MACRO_PLACE_HALO). The MCP `generate_config` tool only generates standard-cell configs. After each `generate_config` call, re-apply the SRAM parameters as described in Step 5d.

For each round:

1. Set round variables (round number, current_params, restart_from="synth", retry_attempt=1)
2. Display: `=== Chipyard-PnR Round {round}/{total} ===`
3. Call `mcp__chipagent-backend__clean_design` before first attempt
4. Generate config (MCP tool + SRAM post-processing)
5. Run stages from restart_from through finish:
   - Call `mcp__chipagent-backend__run_stage` for each stage
   - Call `mcp__chipagent-backend__get_report` after each stage
   - Display per-stage metrics immediately
   - If stage fails, record failed_stage and stop

6. Determine pass/fail:
   - Pass = all stages succeed AND wns >= 0 AND violations == 0
   - For Chipyard designs: timing violations (negative WNS) are **expected** on sky130hd. A round with WNS > -5ns and 0 DRC violations should be considered a "soft pass" for comparison purposes.

7. Save run to QoR history via `mcp__chipagent-backend__compare_runs`
8. If failed and retries remain, diagnose via `mcp__chipagent-backend__diagnose_failure` and retry
9. If severity is "critical", end the round

**OOM recovery [PITFALL-3]:**

If a stage fails with OOM (check stderr for "Cannot allocate memory", "Out of memory", or exit code 137):
1. Reduce `NUM_CORES` by half (minimum 1)
2. If `NUM_CORES` is already 1 and still OOM, this is a hard limit -- accept the failure
3. Clean and retry from the failed stage

### Step 7 -- QoR Comparison and Recommendation

**7a. Load all runs:**

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"load"`
- `workspace_dir`: absolute path to `MyDesign/$CONFIG/workspace`

**7b. Display comparison table:**

```
=== QoR Comparison: <ConfigName> (Chipyard+SRAM) ===

| Round | Clock (ns) | Util | Density | WNS (ns) | TNS (ns) | Area (um2) | Power (uW) | DRC | SRAMs | Status |
|-------|-----------|------|---------|----------|----------|------------|------------|-----|-------|--------|
```

Include a `SRAMs` column showing total SRAM macro count for context.

**7c. Best-run recommendation:**

Call `mcp__chipagent-backend__compare_runs` with `action: "recommend"`.

**Note for Chipyard designs:** It is normal for sky130hd to not meet timing at 100MHz with SRAM macros. The recommended run is the one with best WNS and clean DRC, even if WNS is negative. Report the achieved fmax:

```
fmax = 1000 / (clock_period_ns - WNS_ns) MHz
```

### Step 8 -- Format PPA Report

**Only run if at least one round completed (pass or soft-pass).**

Read the agent definition at `agents/pnr-report-formatter.md` and follow its rules to format a PPA summary report.

Add a Chipyard-specific section to the report:

```
Chipyard Configuration:
  Config:        <ConfigName>
  Top Module:    <DESIGN_NAME>
  SRAM Macros:   <N> total
    - sky130_sram_1rw1r_128x256_8: <count> instances
    - sky130_sram_1rw1r_44x64_8:   <count> instances
  Achieved fmax: <value> MHz (target: <target> MHz)

Known Limitations:
  - Timing not met: sky130hd 130nm process with SRAM macros limits achievable frequency
  - Antenna violations: <count> (skipped repair to avoid OOM; non-critical)
  - IR drop analysis: skipped (SRAM halo blocks PDN vias; functional where cells are placed)
```

## Pipeline Stages

| # | Stage | Description |
|---|-------|-------------|
| 0 | Verify Prerequisites | Check Chipyard Verilog, SRAM mapping, and ORFS patches |
| 1 | Check Environment | Verify ORFS, sky130hd, ABC patch, SRAM macros, pdn.tcl |
| 2 | Nosram Preprocess | Strip behavioral memory modules from Chipyard Verilog |
| 3 | SRAM Override | Generate wrapper modules instantiating sky130hd SRAM macros |
| 4 | Install Design | Copy files into ORFS directory structure |
| 5 | Generate Config | Create config.mk + constraint.sdc with SRAM parameters |
| 5.5 | Clear QoR History | Reset for fresh run |
| 6 | Run Comparison Rounds | Execute PnR with Chipyard+SRAM-aware parameters |
| 7 | QoR Comparison | Display comparison table + best-run recommendation |
| 8 | Format Report | PPA summary with Chipyard-specific annotations |

## Input

$ARGUMENTS

A Chipyard config name (e.g., `TinyRocketConfig`). The config must already have staged Verilog at `MyDesign/<Config>/workspace/generated/<Config>.v`, typically produced by `/chip-agent:chipyard`.

## Output

Upon completion:

- Nosram Verilog: `MyDesign/<Config>/workspace/generated/<Config>_nosram.v`
- SRAM override: `MyDesign/<Config>/workspace/generated/<Config>_sram_override.v`
- ORFS design files in `$ORFS_FLOW_PATH/designs/sky130hd/tinyRocket/`
- Netlist: `{orfs_flow_path}/results/sky130hd/{design_name}/base/1_2_yosys.v`
- GDS: `{orfs_flow_path}/results/sky130hd/{design_name}/base/6_1_merged.gds`
- ORFS reports: `{orfs_flow_path}/reports/sky130hd/{design_name}/base/`
- Formatted PPA report with Chipyard annotations

## Anti-Patterns

- DO NOT pass SRAM liberty files to ABC -- they cause SIGABRT [PITFALL-1]
- DO NOT include original `_ext` or `split_*_ext` modules alongside overrides -- redefinition errors [PITFALL-2]
- DO NOT use `OPENROAD_NUM_THREADS` -- it is ignored by ORFS make flow; use `NUM_CORES` [PITFALL-8]
- DO NOT set `SWAP_ARITH_OPERATORS = 1` -- causes ABC9 crash on large designs [PITFALL-6]
- DO NOT run antenna repair on memory-constrained systems -- OOM from second route pass [PITFALL-4]
- DO NOT expect timing closure at 100MHz on sky130hd with SRAM macros -- 130nm process limit
- DO NOT skip verifying pdn.tcl lowercase vdd/gnd entries -- SRAM power pins won't connect [PITFALL-7]
- DO NOT use DESIGN_NAME=ChipTop for PnR -- use the tile-level module (e.g., RocketTile)
- DO NOT let the MCP generate_config tool overwrite SRAM parameters -- always re-apply them after
- DO NOT skip clean_design between retries -- ORFS caches stale results

## Appendix A: synth_preamble.tcl ABC Exclusion Patch

Apply this patch to `$ORFS_FLOW_PATH/scripts/synth_preamble.tcl`. Find the section that builds `lib_args` (search for `foreach lib $::env(LIB_FILES)`) and replace it with:

```tcl
# Exclude ADDITIONAL_LIBS from ABC to prevent crashes on macro liberty files
# (e.g. sky130ram SRAM libs that cause ABC to SIGABRT).  These libs are still
# loaded via synth_stdcells.tcl for PnR timing, but must not reach ABC.
set additional_libs [list]
if { [env_var_exists_and_non_empty ADDITIONAL_LIBS] } {
  set additional_libs $::env(ADDITIONAL_LIBS)
}
set lib_args ""
foreach lib $::env(LIB_FILES) {
  if { $lib in $additional_libs } {
    puts "Skipping ADDITIONAL_LIBS entry from ABC: $lib"
    continue
  }
  append lib_args "-liberty $lib "
}
```

This replaces the original `foreach lib $::env(LIB_FILES) { append lib_args "-liberty $lib " }` loop.

## Appendix B: pdn.tcl Lowercase Power Pin Entries

Add these two lines to `$ORFS_FLOW_PATH/platforms/sky130hd/pdn.tcl` in the global connections section (after the existing uppercase entries):

```tcl
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^vdd$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^gnd$}
```

These are needed because sky130ram SRAM LEF files use lowercase `vdd`/`gnd` for power pins.

## Appendix C: TinyRocketConfig Reference Design

The following configuration was validated on a 15GB RAM system with sky130hd:

**SRAM macro inventory:**
- `sky130_sram_1rw1r_128x256_8`: 68 instances (64 DCache + 4 ICache)
- `sky130_sram_1rw1r_44x64_8`: 1 instance (DCache tag)
- Total: 69 SRAM macros

**Memory module mapping:**
| RTL Module | Depth x Width | SRAM Macro | Tiles | Total Instances |
|------------|---------------|------------|-------|-----------------|
| data_arrays_0_ext | 4096x32 | sky130_sram_1rw1r_128x256_8 | 16 per byte lane x 4 lanes | 64 |
| tag_array_0_ext | 64x21 | sky130_sram_1rw1r_44x64_8 | 1 | 1 |
| data_arrays_0_0_ext | 1024x32 | sky130_sram_1rw1r_128x256_8 | 4 | 4 |

**Achieved results (Round 1, clock=10ns):**
- WNS: -3.10 ns (fmax = 78.52 MHz)
- TNS: -428.83 ns
- Area: ~1,100,000 um^2
- DRC: 0 violations
- Power: ~3,700,000 uW

**Key parameters that made it work:**
- `CORE_UTILIZATION = 55`, `PLACE_DENSITY = 0.65`
- `NUM_CORES = 4` (15GB RAM system)
- `SKIP_ANTENNA_REPAIR_POST_DRT = 1`
- `ABC_AREA = 1` (never SWAP_ARITH_OPERATORS)
- `SYNTH_HIERARCHICAL = 1`
- Empty `PWR_NETS_VOLTAGES` / `GND_NETS_VOLTAGES`
