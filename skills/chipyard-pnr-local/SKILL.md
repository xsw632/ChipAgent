---
name: chipyard-pnr-local
description: "Run full Chipyard-to-ORFS PnR flow with multi-round parameter iteration: generate RTL from Chipyard with ENABLE_YOSYS_FLOW, preprocess nosram+SRAM override, run 3 rounds of ORFS synth→finish on sky130hd with progressive clock/utilization/density tuning for optimal PPA."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
  - Agent
  - WebSearch
  - WebFetch
  - mcp__chipagent-backend__check_environment
  - mcp__chipagent-backend__generate_config
  - mcp__chipagent-backend__run_stage
  - mcp__chipagent-backend__get_report
  - mcp__chipagent-backend__diagnose_failure
  - mcp__chipagent-backend__clean_design
  - mcp__chipagent-backend__compare_runs
---

# chip-agent:chipyard-pnr

End-to-end flow: Chipyard RTL generation → nosram preprocessing → SRAM override generation → ORFS full PnR (synth → floorplan → place → cts → route → finish) on sky130hd.

This skill handles the **hard parts** of getting Chipyard-generated Verilog through ORFS:
- `ENABLE_YOSYS_FLOW` flag for Yosys-compatible emission
- Behavioral SRAM → sky130_sram macro override (avoids FF-based OOM)
- SYNTH_BLACKBOXES + ADDITIONAL_LEFS/LIBS/GDS for SRAM macros
- Multi-clock domain SDC constraints
- Module consolidation from 260+ split SV files

## Usage

```
/chip-agent:chipyard-pnr <config> 
```

**Examples:**

```
/chip-agent:chipyard-pnr tinyrocket
/chip-agent:chipyard-pnr TinyRocketConfig
/chip-agent:chipyard-pnr tinyrocket 100MHz
```

Create the checklist and go on.
```
□ Parse arguments and setup work directory
□ Verify environment (Chipyard, ORFS, sky130hd, Docker)
□ Generate Verilog from Chipyard VLSI flow
□ Consolidate split SV files into single nosram.sv
□ Generate SRAM override modules (sram-mapping agent)
□ Identify clock ports from ChipTop
□ Generate ORFS config.mk and constraint.sdc
□ Run multi-round PnR iteration (3 rounds adaptive)
□ Compare rounds and select best result
```

## Instructions

**Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all relative paths below.


## Pipeline

### Step 0 -- Parse Arguments and Setup

```bash
PROJECT_ROOT="<project-root>"
RAW_CONFIG=$(echo "$ARGUMENTS" | awk '{print $1}')
FREQ_ARG=$(echo "$ARGUMENTS" | awk '{print $2}')
if [ -z "$RAW_CONFIG" ]; then RAW_CONFIG="tinyrocket"; fi

# Parse optional target frequency from second argument
# e.g. "tinyrocket 100MHz" → TARGET_FREQ_MHZ=100, "tinyrocket 10ns" → TARGET_CLOCK_NS=10
TARGET_FREQ_MHZ=""
TARGET_CLOCK_NS=""
if [ -n "$FREQ_ARG" ]; then
    if echo "$FREQ_ARG" | grep -qiE 'MHz$'; then
        TARGET_FREQ_MHZ=$(echo "$FREQ_ARG" | grep -oiE '[0-9]+')
        TARGET_CLOCK_NS=$(echo "scale=1; 1000 / $TARGET_FREQ_MHZ" | bc)
    elif echo "$FREQ_ARG" | grep -qiE 'ns$'; then
        TARGET_CLOCK_NS=$(echo "$FREQ_ARG" | grep -oiE '[0-9]+(\.[0-9]+)?')
        TARGET_FREQ_MHZ=$(echo "scale=0; 1000 / $TARGET_CLOCK_NS" | bc)
    fi
fi

# Baseline defaults: validated 50MHz/20ns on sky130hd (WNS=0.00, DRC=0)
BASELINE_FREQ_MHZ="${TARGET_FREQ_MHZ:-50}"
BASELINE_CLOCK_NS="${TARGET_CLOCK_NS:-20}"

# DESIGN (workspace path): strip "Config", capitalize → "TinyRocket"
if echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    DESIGN=$(echo "$RAW_CONFIG" | sed 's/Config$//')
else
    DESIGN="$(echo "${RAW_CONFIG:0:1}" | tr '[:lower:]' '[:upper:]')${RAW_CONFIG:1}"
fi
WORK_DIR="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/pnr"

# CONFIG (Chipyard config name): ensure "Config" suffix → "TinyRocketConfig"
if echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    CONFIG=$(echo "$RAW_CONFIG" | grep -qE 'Config$' && echo "$RAW_CONFIG" || echo "${RAW_CONFIG}Config")
else
    CONFIG="$(echo "${RAW_CONFIG:0:1}" | tr '[:lower:]' '[:upper:]')${RAW_CONFIG:1}Config"
fi

mkdir -p "$WORK_DIR"
```

### Step 1 -- Verify Environment

```bash
# Read env.json for paths
CHIPYARD_DIR=$(jq -r '.chipyard.path' "$PROJECT_ROOT/.chipagent/env.json")
RISCV=$(jq -r '.chipyard.riscv_path' "$PROJECT_ROOT/.chipagent/env.json")
ORFS_FLOW_PATH=$(jq -r '.orfs.flow_path' "$PROJECT_ROOT/.chipagent/env.json")
```

Verify:
```bash
test -d "$CHIPYARD_DIR" && test -f "$CHIPYARD_DIR/build.sbt" || STOP "Chipyard not found at $CHIPYARD_DIR"
test -d "$ORFS_FLOW_PATH" && test -f "$ORFS_FLOW_PATH/Makefile" || STOP "ORFS not found at $ORFS_FLOW_PATH"
```

Call `mcp__chipagent-backend__check_environment` to verify ORFS/sky130hd/Docker readiness.

### Step 2 -- Generate Verilog from Chipyard (VLSI Flow)

**Use the VLSI flow**, not the simulation flow. The VLSI flow produces a clean ChipTop-only filelist.

```bash
# Setup conda environment
eval "$(/home/mingzhenjia/miniconda3/bin/conda shell.bash hook)" 2>/dev/null
conda activate "$CHIPYARD_DIR/.conda-env" 2>/dev/null

# Clean previous build (optional but recommended)
cd "$CHIPYARD_DIR/vlsi" && rm -rf build-sky130-openroad generated-src/chipyard.harness.TestHarness.${CONFIG}*

# Run VLSI buildfile (elaboration + FIRRTL→Verilog + MacroCompiler)
cd "$CHIPYARD_DIR/vlsi" && \
export RISCV="$RISCV" && \
export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8" && \
make buildfile tutorial=sky130-openroad 2>&1 | tail -80
```

**Timeout:** 600000ms (10 minutes). The `tutorial=sky130-openroad` automatically sets:
- `CONFIG=TinyRocketConfig`
- `ENABLE_YOSYS_FLOW=1`
- `tech_name=sky130`
- `VLSI_OBJ_DIR=build-sky130-openroad`

**Verification:**
```bash
GEN_DIR="$CHIPYARD_DIR/vlsi/generated-src/chipyard.harness.TestHarness.$CONFIG"
TOP_F="$GEN_DIR/chipyard.harness.TestHarness.$CONFIG.top.f"
MEMS_CONF="$GEN_DIR/chipyard.harness.TestHarness.$CONFIG.mems.conf"

test -f "$TOP_F" || STOP "top.f not found — buildfile may have failed"
test -f "$MEMS_CONF" || STOP "mems.conf not found"
echo "Generated $(cat "$TOP_F" | wc -l) files in top.f"
cat "$MEMS_CONF"
```

**Expected mems.conf content** (for TinyRocketConfig):
```
name data_arrays_0_0_ext depth 4096 width 8 ports mrw mask_gran 8
name tag_array_0_ext depth 64 width 21 ports mrw mask_gran 21
name data_arrays_0_0_0_ext depth 1024 width 32 ports mrw mask_gran 32
```

### Step 3 -- Consolidate Verilog Files

Merge the split SV files from `top.f` into a single file. The `top.f` filelist contains ChipTop-only modules (no TestHarness) and already includes stub files (EICG_wrapper.v, IOCell.v, plusarg_reader.v).

```bash
COLL="$GEN_DIR/gen-collateral"
TOP_F="$GEN_DIR/chipyard.harness.TestHarness.$CONFIG.top.f"
NOSRAM_V="$WORK_DIR/${CONFIG}_nosram.sv"

# Merge all files from top.f into single file
cat "$TOP_F" | while read f; do
    cat "$f"
    echo ""
done > "$NOSRAM_V"

echo "Merged: $NOSRAM_V ($(wc -l < "$NOSRAM_V") lines)"
```

**Do NOT append** EICG_wrapper.v, IOCell.v, plusarg_reader.v — they are already in `top.f`.

**Do NOT include** the SRAM wrapper (`*.top.mems.v`) — it uses sram22 macros which we replace with sky130_sram macros via the override.

**Verify no duplicates:**
```bash
# Should show 0 — all modules should be unique
grep "^module " "$NOSRAM_V" | sort | uniq -d | wc -l
```

### Step 4 -- Generate SRAM Override Modules

**Delegate to `sram-mapping` subagent.**

The SRAM override generation involves complex tiling logic (depth splitting, column grouping, wmask expansion, read MUX). Invoke the dedicated `sram-mapping` agent which encapsulates the full mapping analysis and code generation.

Spawn the `sram-mapping` agent (from `agents/sram-mapping.md`) with this context in the prompt:

```
GEN_DIR: <path to gen-collateral directory>
OUTPUT_DIR: <path to work directory>
ORFS_FLOW_PATH: <path to ORFS flow/ directory>
```

Example:
```
Agent(
  subagent_type: "sram-mapping",
  description: "Generate SRAM override modules",
  prompt: "Generate SRAM override modules for Chipyard design.
    GEN_DIR: /home/user/chipyard/vlsi/generated-src/chipyard.harness.TestHarness.TinyRocketConfig/gen-collateral
    OUTPUT_DIR: /home/user/ChipAgent-Test/try
    ORFS_FLOW_PATH: /home/user/OpenROAD-flow-scripts/flow"
)
```

The agent will:
1. Read `mems.conf` to parse SRAM specs (depth, width, ports, mask_gran)
2. Find behavioral module instantiation sites to infer port interfaces
3. Select the best-fit `sky130_sram_*` macro for each SRAM
4. Design the tiling strategy (depth tiles, column groups, bit slicing)
5. Generate `$WORK_DIR/sram_override.v` with correct override modules
6. Write `$WORK_DIR/sram_mapping.json` with structured mapping metadata
7. Perform a Yosys compile check

**After the agent completes, verify the output:**

```bash
test -f "$WORK_DIR/sram_override.v" || STOP "sram-mapping agent did not produce sram_override.v"
test -f "$WORK_DIR/sram_mapping.json" || STOP "sram-mapping agent did not produce sram_mapping.json"
```

**Extract SRAM macro list** from the generated mapping for Step 6:

```bash
USED_MACROS=$(jq -r '.mappings[] | select(.macro != null) | .macro' "$WORK_DIR/sram_mapping.json" | sort -u)
echo "Used SRAM macros: $USED_MACROS"
```

This macro list is needed in Step 6 to populate `SYNTH_BLACKBOXES`, `ADDITIONAL_LEFS/LIBS/GDS`, and `DONT_USE_CELLS` in config.mk.

### Step 5 -- Identify Clock Ports

Read the ChipTop module ports:
```bash
grep -A30 "^module ChipTop" "$WORK_DIR/${CONFIG}_nosram.sv" | head -20
```

Typical TinyRocketConfig ChipTop clock ports:
- `clock_uncore_clock` — main core clock (10ns period)
- `serial_tl_clock` — serial link clock
- `jtag_TCK` — JTAG clock (100ns period)

### Step 6 -- Generate ORFS Config

Use `mcp__chipagent-backend__generate_config` to create base config, then manually enhance it.

**6a. Generate base config:**

Note: `workspace_dir` is the output directory for config.mk and constraint.sdc.
The tool writes files directly to this directory (no extra `/pnr` appended).

```
mcp__chipagent-backend__generate_config(
  module_name="ChipTop",
  verilog_path="$WORK_DIR/${CONFIG}_nosram.sv",
  workspace_dir="$WORK_DIR/pnr",
  clock_port="clock_uncore_clock",
  clock_period_ns=10,
  core_utilization=55,
  place_density=0.65
)
```

**6b. Overwrite config.mk with full Chipyard-specific settings:**

The MCP-generated config is a minimal template. Replace it with the full config that includes SRAM macro paths, blackboxes, and physical constraints. The SRAM macro list is dynamically built from `sram_mapping.json` generated by `/chip-agent:sram-mapping`.

```bash
SRAM_DIR="$ORFS_FLOW_PATH/platforms/sky130ram"

# Build SRAM macro lists dynamically from sram_mapping.json
MACROS=$(jq -r '.mappings[] | select(.macro != null) | .macro' "$WORK_DIR/sram_mapping.json" | sort -u)
MACRO_LIST=$(echo "$MACROS" | tr '\n' ' ')

# Build VERILOG_FILES: nosram + override + each macro's behavioral .v
VERILOG_LIST="$WORK_DIR/${CONFIG}_nosram.sv $WORK_DIR/sram_override.v"
for m in $MACROS; do
    VERILOG_LIST="$VERILOG_LIST $SRAM_DIR/$m/$m.v"
done

# Build ADDITIONAL_LEFS/LIBS/GDS lines
LEFS=""; LIBS=""; GDS=""
for m in $MACROS; do
    LEFS="$LEFS $SRAM_DIR/$m/$m.lef"
    LIBS="$LIBS $SRAM_DIR/$m/${m}_TT_1p8V_25C.lib"
    GDS="$GDS $SRAM_DIR/$m/$m.gds"
done

# Format as backslash-continued Makefile lines
VERILOG_LINES=$(echo "$VERILOG_LIST" | sed 's/  */ \\\n    /g')
LEF_LINES=$(echo "$LEFS" | sed 's/^ *//' | sed 's/  */ \\\n    /g')
LIB_LINES=$(echo "$LIBS" | sed 's/^ *//' | sed 's/  */ \\\n    /g')
GDS_LINES=$(echo "$GDS" | sed 's/^ *//' | sed 's/  */ \\\n    /g')

cat > "$WORK_DIR/pnr/config.mk" << CFGEOF
export DESIGN_NAME = ChipTop
export PLATFORM = sky130hd
export DESIGN_NICKNAME = tinyRocket

export VERILOG_FILES = \\
    $VERILOG_LINES

export SDC_FILE = $WORK_DIR/pnr/constraint.sdc

# Blackbox SRAM macros during synthesis (Yosys leaves them as abstract blocks)
export SYNTH_BLACKBOXES = $MACRO_LIST

# SRAM macro physical files for OpenROAD floorplan/place/route
export ADDITIONAL_LEFS = \\
    $LEF_LINES
export ADDITIONAL_LIBS = \\
    $LIB_LINES
export ADDITIONAL_GDS = \\
    $GDS_LINES

# Prevent ABC from mapping to SRAM cells
export DONT_USE_CELLS += $MACRO_LIST

# Hierarchical synthesis to preserve SRAM blackbox instances
export SYNTH_HIERARCHICAL = 1
export SYNTH_MINIMUM_KEEP_SIZE = 1000
export ABC_AREA = 1

# Physical parameters (validated: TinyRocket 50MHz on sky130hd, R2 pass)
export CORE_UTILIZATION = 50
export PLACE_DENSITY = 0.65
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export SETUP_SLACK_MARGIN = 0.3
export MACRO_PLACE_HALO = 20 20

# CTS tuning
export CTS_CLUSTER_SIZE = 20
export CTS_CLUSTER_DIAMETER = 50

export TNS_END_PERCENT = 100
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
export NUM_CORES = 4

# Skip IR drop analysis (SRAM halo blocks PDN vias)
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
CFGEOF
```

**6c. Write SDC with multi-clock constraints:**

```bash
cat > "$WORK_DIR/pnr/constraint.sdc" << SDCEOF
current_design ChipTop
create_clock -name core_clock -period 10 [get_ports clock_uncore_clock]
create_clock -name serial_clock -period 10 [get_ports serial_tl_clock]
create_clock -name jtag_clock -period 100 [get_ports jtag_TCK]
# NOTE: For multi-round iteration, update core_clock period here to match round's clock_period_ns
set_clock_groups -asynchronous -group {core_clock} -group {serial_clock} -group {jtag_clock}
set_input_delay -clock core_clock 0 [all_inputs -no_clocks]
set_output_delay -clock core_clock 0 [all_outputs]
SDCEOF
```

### Step 7 -- Run ORFS Full Flow (Multi-Round Iteration)

Run at least **3 rounds** of PnR iteration. The user sets a target frequency; the AI adaptively tunes parameters based on each round's diagnostic results. Each round runs as a background subagent.

**Parameter Knobs:**

| Parameter | Description | Tuning Direction |
|-----------|-------------|------------------|
| `clock_period_ns` | Clock period (ns) = 1000 / freq_mhz | Progressively approach target frequency |
| `core_utilization` | Core utilization (%) | Congestion → decrease, timing slack → increase |
| `place_density` | Placement density (0.0–1.0) | Congestion → decrease, timing slack → increase |
| `gpl_timing_driven` | Timing-driven placement | Large negative WNS → enable |
| `gpl_routability_driven` | Routability-driven placement | Many DRC violations → enable |
| `setup_slack_margin` | Timing margin (ns) | Progressively tighten to 0.05ns |

**Validated Baseline** (TinyRocketConfig + sky130hd, no need to re-validate):

| Parameter | Validated Value | Validation Result |
|-----------|-----------------|-------------------|
| `clock_period_ns` | 20 (50MHz) | WNS=0.00, TNS=0.00, DRC=0 |
| `core_utilization` | 50 | Area=3,001,640µm², util=51% |
| `place_density` | 0.65 | No congestion issues |
| `gpl_timing_driven` | 1 | **Critical**: without it WNS=-0.12ns |
| `gpl_routability_driven` | 1 | DRC=0 |
| `setup_slack_margin` | 0.3 | Sufficient timing margin |
| Design fmax ceiling | ~54MHz | Critical path ~18.4ns, cannot break through via PnR tuning |
| SRAM macro count | 6 | 5×sky130_sram_1rw1r_64x256_8 + 1×sky130_sram_1rw1r_44x64_8 |

**Usage rules:**
- When target ≤ 50MHz, skip baseline validation — Round 1 directly uses `baseline_clock_ns` (known to pass)
- When target > fmax ceiling, attempt target in Round 1, then converge to achievable frequency upon failure
- All rounds enable `gpl_timing_driven=1` by default

**Adaptive Tuning Logic:**

Round 1 uses the baseline frequency. Round 2+ calls `diagnose_failure` and `get_report` to read previous round results, then adjusts parameters:

| Diagnostic Signal | Meaning | AI Adjustment |
|-------------------|---------|---------------|
| WNS << 0 (e.g. < -2ns) | Severe timing violation | Relax clock_period (+2ns), reduce utilization (-5%), enable gpl_timing_driven |
| WNS slightly negative (e.g. -0.5ns) | Minor timing violation | Fine-tune clock_period (+0.5ns), reduce place_density (-0.05), tighten slack_margin |
| WNS >= 0 | Timing met | Can tighten clock_period (-1ns), increase utilization (+5%) |
| DRC violations > 0 | Routing issues | Reduce place_density (-0.1), reduce utilization (-5%), enable gpl_routability_driven |
| Large TNS | Multiple paths violating | Significantly relax clock_period, reduce utilization |
| TNS close to 0 | Only a few paths violating | Fine-tune only |
| Routing congestion hotspots | Local congestion | Reduce place_density, enable gpl_routability_driven |
| OOM / timeout | Insufficient resources | Reduce utilization and place_density |

**Tuning principles:**
1. Adjust only 1-2 parameters per round; do not drastically change multiple parameters simultaneously
2. Resolve timing violations first, then pursue area/power optimization
3. If WNS >= 0 and DRC == 0, the current parameters are viable — try tightening the clock to continue approaching the target
4. If WNS does not improve for two consecutive rounds, the limit has been reached — stop iterating
5. Progressively tighten slack_margin from 0.3ns to 0.05ns, but do not tighten when timing is violating

**Termination conditions:** WNS>=0 and DRC==0 / max rounds reached / consecutive WNS improvement < 0.1ns / target frequency achieved.

**7a. Clean previous run (direct MCP call):**
```
mcp__chipagent-backend__clean_design(
  config_mk_path="$WORK_DIR/pnr/config.mk",
  orfs_flow_path="$ORFS_FLOW_PATH/flow"
)
```

**7b. Initialize round parameters:**

```bash
# Set total rounds (minimum 3, maximum 5)
TOTAL_ROUNDS=3

# Round 1 parameters: use baseline clock directly (already validated to pass)
# When baseline ≤ 50MHz, skip validation — Round 1 runs baseline, Round 2+ pushes toward target
R1_CLOCK="${BASELINE_CLOCK_NS:-${TARGET_CLOCK_NS:-10}}"
R1_UTIL=50
R1_DENSITY=0.65
R1_TIMING_DRIVEN=1
R1_ROUTABILITY_DRIVEN=1
R1_SLACK_MARGIN=0.3
```

**7c. Spawn background round executor (Round 1 — baseline):**

Spawn the `pnr-round-executor` agent with `run_in_background: true`:

```
Agent(
  subagent_type: "pnr-round-executor",
  description: "PnR Round 1: ChipTop (tinyRocket) — baseline",
  run_in_background: true,
  prompt: "
    module: ChipTop
    project_root: $PROJECT_ROOT
    round_number: 1
    total_rounds: 3
    restart_from: synth
    current_params: { clock_period_ns: $R1_CLOCK, core_utilization: $R1_UTIL, place_density: $R1_DENSITY, gpl_timing_driven: $R1_TIMING_DRIVEN, gpl_routability_driven: $R1_ROUTABILITY_DRIVEN, setup_slack_margin: $R1_SLACK_MARGIN }
    config_mk: $WORK_DIR/pnr/config.mk
    design_name: ChipTop
    orfs_flow_path: $ORFS_FLOW_PATH/flow
    clock_port: clock_uncore_clock
    NOTE: Stage timeouts: synth=30min, floorplan=60min, place=30min, cts=30min, route=120min, finish=30min.
  "
)
```

**7d. Handle round completion — diagnose and decide next parameters:**

When the background agent completes, you will receive a task notification. At that point:

1. **Save round results** via `compare_runs`:
   ```
   mcp__chipagent-backend__compare_runs(
     action="save",
     workspace_dir="$WORK_DIR",
     run={"round": <current_round>, "config": {<params>}, "metrics": {<from report>}, "status": "pass"|"fail"}
   )
   ```

2. **Collect detailed metrics** via MCP:
   ```
   mcp__chipagent-backend__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$ORFS_FLOW_PATH/flow")
   mcp__chipagent-backend__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$ORFS_FLOW_PATH/flow")
   ```

3. **Diagnose results** — call `diagnose_failure` to get AI-readable analysis:
   ```
   mcp__chipagent-backend__diagnose_failure(
     stage="finish",
     success=<true|false>,
     current_clock_period_ns=<current CP>,
     current_core_utilization=<current CU>,
     current_place_density=<current PD>,
     sdc_content=<read constraint.sdc>,
     finish_report_content=<from get_report>
   )
   ```

4. **Decide next round parameters** based on diagnostic signals:
   - Read WNS, TNS, DRC violations, area, power from the reports
   - Apply the Adaptive Tuning Logic (see below)
   - Determine the next round's `{clock_period_ns, core_utilization, place_density, gpl_timing_driven, gpl_routability_driven, setup_slack_margin}`

**7e. Launch next round (if more rounds remain and termination conditions not met):**

Check termination conditions first:
- If WNS >= 0 AND DRC == 0: **success**, proceed to Step 8
- If `current_round >= total_rounds`: **max rounds reached**, proceed to Step 8
- If consecutive WNS improvement < 0.1ns: **converged**, proceed to Step 8

Otherwise, launch next round with AI-decided parameters:

1. **Update `config.mk`** with the AI-decided parameters:
   ```bash
   # CP, CU, PD, GTD, GRD, SSM are the AI-decided values from Step 7d
   sed -i "s/^export CORE_UTILIZATION = .*/export CORE_UTILIZATION = $CU/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export PLACE_DENSITY = .*/export PLACE_DENSITY = $PD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export GPL_TIMING_DRIVEN = .*/export GPL_TIMING_DRIVEN = $GTD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export GPL_ROUTABILITY_DRIVEN = .*/export GPL_ROUTABILITY_DRIVEN = $GRD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export SETUP_SLACK_MARGIN = .*/export SETUP_SLACK_MARGIN = $SSM/" "$WORK_DIR/pnr/config.mk"
   ```

2. **Update `constraint.sdc`** with new clock period:
   ```bash
   sed -i "s/-period [0-9]* \[get_ports clock_uncore_clock\]/-period $CP [get_ports clock_uncore_clock]/" "$WORK_DIR/pnr/constraint.sdc"
   sed -i "s/-period [0-9]* \[get_ports serial_tl_clock\]/-period $CP [get_ports serial_tl_clock]/" "$WORK_DIR/pnr/constraint.sdc"
   ```

3. **Clean ORFS cache:**
   ```
   mcp__chipagent-backend__clean_design(
     config_mk_path="$WORK_DIR/pnr/config.mk",
     orfs_flow_path="$ORFS_FLOW_PATH/flow"
   )
   ```

4. **Spawn next round executor** — same as Step 7c, replacing round_number=$NEXT_ROUND and current_params={CP,CU,PD,GTD,GRD,SSM}.

5. **Loop back to Step 7d** when this round completes.

### Step 8 -- Compare Rounds and Select Best Result

**8a. Load all round results and recommend best:**

```
mcp__chipagent-backend__compare_runs(
  action="recommend",
  workspace_dir="$WORK_DIR"
)
```

**8b. Collect detailed metrics for each round** (if not already saved):

```
mcp__chipagent-backend__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$ORFS_FLOW_PATH/flow")
mcp__chipagent-backend__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$ORFS_FLOW_PATH/flow")
```

**8c. Display comparison table:**

```
=== Chipyard PnR Multi-Round Results: ChipTop (tinyRocket) ===

| Round | Clock(ns) | Util% | Density | Timing-Driven | Routability | Slack Margin | WNS(ns) | TNS(ns) | Area(um^2) | DRC | Power(uW) | Status |
|-------|-----------|-------|---------|---------------|-------------|--------------|---------|---------|------------|-----|-----------|--------|
| R1    | 10        | 55    | 0.65    | -             | Y           | 0.2          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R2    | 8         | 60    | 0.72    | Y             | -           | 0.1          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R3    | 6         | 70    | 0.80    | Y             | Y           | 0.05         | ...     | ...     | ...        | ... | ...       | PASS/FAIL |

Best round: R<X> — <reason>
```

**8d. Report final recommended result:**

```
=== Final Recommended Result ===
Round: R<X>
Clock Period: <ns> ns (<freq> MHz)
WNS: <wns> ns | TNS: <tns> ns
Area: <area> um^2
Power: <power> uW
DRC Violations: <count>
Status: PASS / FAIL
```

**Expected output files** (at `$ORFS_FLOW_PATH/flow/results/sky130hd/tinyRocket/base/`):
| File | Description |
|------|-------------|
| `6_final.gds` | Final GDSII layout (~255 MB) |
| `6_final.odb` | Final OpenDB database (~540 MB) |
| `6_final.v` | Final Verilog netlist (~40 MB) |
| `6_final.spef` | Parasitic extraction (~156 MB) |
| `6_final.def` | Final DEF file (~241 MB) |

## Anti-Patterns

- **NEVER** use behavioral SRAM stubs (reg arrays) — causes OOM in routing 
- **NEVER** omit `ENABLE_YOSYS_FLOW=1` — causes Yosys parse errors on packed arrays
- **NEVER** append stub files that are already in `top.f` — causes duplicate module errors
- **NEVER** use `SYNTH_BLACKBOXES` without `ADDITIONAL_LEFS/LIBS/GDS` — causes missing cost error
- **NEVER** use the simulation flow (`make verilog`) — includes TestHarness modules
- **ALWAYS** use `timeout_minutes=120` for the `route` stage — detailed routing takes up to 120 minutes for complex designs
- **ALWAYS** use `timeout_minutes=30` for the `synth` stage — ABC technology mapping for 70+ modules needs 30 minutes
- **ALWAYS** use `timeout_minutes=30` for the `place` stage — repair_design resize processing 90K+ nets needs 30 minutes
- **NEVER** skip `clean_all` between retries — ORFS caches stale results
- **ALWAYS** verify Yosys compiles the design before running ORFS (Step 4 verification)
- **ALWAYS** set `SYNTH_HIERARCHICAL = 1` — preserves SRAM module boundaries
- **ALWAYS** set `MACRO_PLACE_HALO = 20 20` — prevents standard cells from overlapping SRAM halo
- **ALWAYS** set `DONT_USE_CELLS` for SRAM macros — prevents ABC from using them as logic cells
- **ALWAYS** set `SKIP_ANTENNA_REPAIR_POST_DRT = 1` — avoids OOM during antenna repair
- **ALWAYS** run `clean_design` between PnR rounds — stale ORFS cache causes misleading results
- **ALWAYS** save round results via `compare_runs` before starting the next round
- **ALWAYS** use `compare_runs(action="recommend")` to select the best round objectively
- **NEVER** skip the baseline round (R1) — it validates the flow before aggressive tuning
- **NEVER** enable both `gpl_timing_driven` and `gpl_routability_driven` in early rounds — they conflict and can cause poor placement
- **PREFER** starting with routability-driven in R1, then timing-driven in R2, then both in R3 only if needed
- **NEVER** skip nosram preprocessing — behavioral SRAM modules cause OOM
- **NEVER** use `SWAP_ARITH_OPERATORS=1` — causes ABC crash on large designs

## Input

$ARGUMENTS

A Chipyard config name (e.g., `tinyrocket`, `TinyRocketConfig`). Optional arguments:
- **Work directory**: `/path/to/try`
- **Target frequency**: `100MHz` or `10ns` (AI will adaptively tune parameters to reach this target over multiple rounds)自动搜索更大 macro — 如果总 macro 数 >200，ORFS 默认 macro 太小，就克隆 SRAM22 仓库找更大 macro

## Output

Upon completion:
- GDS: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.gds`
- Netlist: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.v`
- SPEF: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.spef`
- Reports: `$ORFS_FLOW/reports/sky130hd/tinyRocket/base/`
- Timing/area/DRC summary displayed in conversation
