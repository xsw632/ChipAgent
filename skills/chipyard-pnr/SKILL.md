---
name: chipyard-pnr
description: "Run full Chipyard-to-ORFS PnR flow: generate RTL from Chipyard with ENABLE_YOSYS_FLOW, preprocess nosram+SRAM override, run ORFS synth→finish on sky130hd."
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
/chip-agent:chipyard-pnr <config> [work_dir]
```

**Examples:**

```
/chip-agent:chipyard-pnr tinyrocket
/chip-agent:chipyard-pnr TinyRocketConfig
/chip-agent:chipyard-pnr tinyrocket /path/to/try
```

## Instructions

**Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

## Critical Pitfalls (READ FIRST)

These are non-obvious failure modes discovered through production runs. **Every one of these will cause the flow to fail silently or catastrophically if ignored.**

### Pitfall 1: FF-based SRAMs cause OOM in routing (CRITICAL)

**Problem:** If behavioral SRAM modules (`data_arrays_0_0_ext`, etc.) are synthesized to flip-flops, the design explodes from ~100K cells to millions of cells. Detailed routing (`5_2_route`) will be killed by OOM killer (signal 9) at 13+ GB memory.

**Root cause:** `data_arrays_0_0_ext` is 4096x8 = 32,768 flip-flops per instance. With multiple instances, this creates hundreds of thousands of FFs that bloat the design.

**Solution:** Use the **nosram + SRAM override** approach:
1. Use the Chipyard-generated behavioral Verilog as-is (modules are undefined external modules)
2. Provide `sram_override.v` that replaces behavioral SRAMs with `sky130_sram_*` macro instantiations
3. Blackbox the `sky130_sram_*` macros during synthesis via `SYNTH_BLACKBOXES`
4. Provide LEF/LIB/GDS files so OpenROAD can place the physical SRAM macros

**NEVER** provide behavioral SRAM stubs (reg arrays) as substitutes — this causes the OOM problem.

### Pitfall 2: ENABLE_YOSYS_FLOW is mandatory

**Problem:** Without `ENABLE_YOSYS_FLOW=1`, firtool emits SystemVerilog packed-array patterns (`wire [2:0][8:0] _GEN = '{9'h0, ...}`) that Yosys cannot parse, causing `ERROR: syntax error, unexpected OP_CAST` in `1_1_yosys_canonicalize`.

**Solution:** Always pass `ENABLE_YOSYS_FLOW=1` to `make buildfile` or `make verilog`. In Chipyard's `vlsi/tutorial.mk`, the `sky130-openroad` tutorial already sets this flag, but verify it is set.

**What it does** (from `chipyard/common.mk`):
1. Enables SFC LowFIRRTL lowering with `ReplSeqMem` for SRAM extraction
2. Appends `disallowPackedArrays` to MFC lowering options

### Pitfall 3: Duplicate module definitions

**Problem:** If you concatenate `EICG_wrapper.v`, `IOCell.v`, `plusarg_reader.v` files AND they are already in the `top.f` filelist, Yosys errors: `ERROR: Re-definition of module \EICG_wrapper!`

**Solution:** Only concatenate files from the `top.f` filelist (which already includes stubs). Do NOT manually append stub files that are already in the list.

### Pitfall 4: SYNTH_MEMORY_MAX_BITS too small (if using behavioral fallback)

**Problem:** If you fall back to behavioral SRAMs (FF-based), ORFS errors: `Error: Synthesized memory size 4096 exceeds SYNTH_MEMORY_MAX_BITS`

**Solution:** Set `SYNTH_MEMORY_MAX_BITS = 131072` in config.mk. But this only applies to the FF-based fallback — the preferred SRAM macro approach does NOT need this.

### Pitfall 5: SRAM blackbox cost information

**Problem:** If you use `(* blackbox *)` attribute on SRAM modules without providing LEF/LIB, ORFS errors: `ERROR: Missing cost information on instanced blackbox sram22_*`

**Solution:** Do NOT use custom sram22 blackbox stubs. Instead, use the ORFS-provided `sky130_sram_*` macros which have LEF/LIB/GDS files. Set `SYNTH_BLACKBOXES` in config.mk and provide `ADDITIONAL_LEFS/LIBS/GDS`.

### Pitfall 6: Chipyard VLSI flow vs simulation flow

**Problem:** `make verilog` (simulation flow) generates TestHarness + ChipTop in split SV files. `make buildfile` (VLSI flow) generates ChipTop-only in `top.f` filelist with SRAM MacroCompiler output.

**Solution:** Use the **VLSI flow** (`make buildfile tutorial=sky130-openroad`) for ORFS. It produces a clean `top.f` filelist (ChipTop only, no TestHarness) and SRAM wrapper modules. The simulation flow includes TestHarness modules that are not needed and complicate the design.

## Pipeline

### Step 0 -- Parse Arguments and Setup

```bash
PROJECT_ROOT="<project-root>"
RAW_CONFIG="$ARGUMENTS"
WORK_DIR="${2:-$PROJECT_ROOT/try}"  # default: try/ in project root
```

Normalize config name (same as `/chip-agent:chipyard`):
- `tinyrocket` → `TinyRocketConfig`
- `TinyRocket` → `TinyRocketConfig`
- `TinyRocketConfig` → `TinyRocketConfig`

```bash
if [ -z "$RAW_CONFIG" ]; then
    CONFIG="TinyRocketConfig"
elif echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    if echo "$RAW_CONFIG" | grep -qE 'Config$'; then
        CONFIG="$RAW_CONFIG"
    else
        CONFIG="${RAW_CONFIG}Config"
    fi
else
    FIRST=$(echo "${RAW_CONFIG:0:1}" | tr '[:lower:]' '[:upper:]')
    REST="${RAW_CONFIG:1}"
    CONFIG="${FIRST}${REST}Config"
fi
```

Create work directory:
```bash
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
```
mcp__chipagent-backend__generate_config(
  module_name="ChipTop",
  verilog_path="$WORK_DIR/${CONFIG}_nosram.sv",
  workspace_dir="$WORK_DIR",
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

# Physical parameters
export CORE_UTILIZATION = 55
export PLACE_DENSITY = 0.65
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
set_clock_groups -asynchronous -group {core_clock} -group {serial_clock} -group {jtag_clock}
set_input_delay -clock core_clock 0 [all_inputs -no_clocks]
set_output_delay -clock core_clock 0 [all_outputs]
SDCEOF
```

### Step 7 -- Run ORFS Full Flow

Run each stage sequentially via `make`. Do NOT use `mcp__chipagent-backend__run_stage` — it may have parameter issues with absolute paths. Use direct `make` commands.

```bash
ORFS_FLOW="$ORFS_FLOW_PATH/flow"
CONFIG_MK="$WORK_DIR/pnr/config.mk"
DESIGN_CONFIG="$CONFIG_MK"

# Clean any previous run
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" clean_all

# 7a. Synthesis (~10 min, ~2.7 GB)
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" synth 2>&1 | tail -20

# Verify synthesis output
test -f "$ORFS_FLOW/results/sky130hd/tinyRocket/base/1_synth.odb" || STOP "Synthesis failed"

# 7b. Floorplan (~1.5 min, ~12 GB for PDN)
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" floorplan 2>&1 | tail -10

# 7c. Placement (~6 min, ~1.4 GB)
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" place 2>&1 | tail -10

# 7d. CTS (~6 min, ~1.4 GB)
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" cts 2>&1 | tail -10

# 7e. Routing (~56 min, ~7 GB peak during DRT)
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" route 2>&1 | tail -10

# 7f. Finish + GDS merge (~2 min)
cd "$ORFS_FLOW" && make DESIGN_CONFIG="$DESIGN_CONFIG" finish 2>&1 | tail -20
```

**Total runtime:** ~82 minutes on a modern machine.

**Timeout per stage:** Use 600000ms (10 min) for most stages. Routing may take up to 60 minutes.

**Memory requirements:**
- Synthesis: ~3 GB
- Floorplan/PDN: ~12 GB (PDN generation is memory-intensive)
- Place: ~2 GB
- CTS: ~2 GB
- Route (DRT): ~7-8 GB
- Finish: ~2 GB

### Step 8 -- Collect Results and Report

```bash
RESULTS_DIR="$ORFS_FLOW/results/sky130hd/tinyRocket/base"
REPORTS_DIR="$ORFS_FLOW/reports/sky130hd/tinyRocket/base"

# List output artifacts
echo "=== Output Artifacts ==="
ls -lh "$RESULTS_DIR"/6_final.* 2>/dev/null

# Read timing/area report
cat "$REPORTS_DIR/6_finish.rpt" 2>/dev/null | grep -A1 "report_tns\|report_wns\|report_worst_slack\|report_clock_min_period\|violation count"

# Read DRC report
cat "$REPORTS_DIR/5_route_drc.rpt" 2>/dev/null | tail -5
```

**Expected output files:**
| File | Description |
|------|-------------|
| `6_final.gds` | Final GDSII layout (~255 MB) |
| `6_final.odb` | Final OpenDB database (~540 MB) |
| `6_final.v` | Final Verilog netlist (~40 MB) |
| `6_final.spef` | Parasitic extraction (~156 MB) |
| `6_final.def` | Final DEF file (~241 MB) |

## Pipeline Stages Summary

| # | Stage | Duration | Peak Memory | Key Notes |
|---|-------|----------|-------------|-----------|
| 0 | Parse & Setup | - | - | Normalize config, create work dir |
| 1 | Verify Environment | - | - | Check chipyard, ORFS, sky130hd |
| 2 | Generate Verilog | ~5 min | ~2 GB | `make buildfile tutorial=sky130-openroad` |
| 3 | Consolidate SV | ~10 sec | ~100 MB | Merge 237 files from top.f |
| 4 | SRAM Override | - | - | Delegate to `/chip-agent:sram-mapping`, yosys check |
| 5 | Identify Clocks | - | - | Parse ChipTop ports |
| 6 | Generate Config | - | - | config.mk + multi-clock SDC |
| 7a | Synthesis | ~10 min | ~3 GB | Yosys + ABC |
| 7b | Floorplan | ~1.5 min | ~12 GB | Init + tapcell + PDN |
| 7c | Placement | ~6 min | ~2 GB | Global + detailed placement |
| 7d | CTS | ~6 min | ~2 GB | Clock tree synthesis |
| 7e | Routing | ~56 min | ~7 GB | GRT + DRT + antenna repair |
| 7f | Finish | ~2 min | ~2 GB | Fill + GDS merge |
| 8 | Report | - | - | Collect timing/area/DRC metrics |

## Anti-Patterns

- **NEVER** use behavioral SRAM stubs (reg arrays) — causes OOM in routing (13+ GB)
- **NEVER** omit `ENABLE_YOSYS_FLOW=1` — causes Yosys parse errors on packed arrays
- **NEVER** append stub files that are already in `top.f` — causes duplicate module errors
- **NEVER** use `SYNTH_BLACKBOXES` without `ADDITIONAL_LEFS/LIBS/GDS` — causes missing cost error
- **NEVER** use the simulation flow (`make verilog`) — includes TestHarness modules
- **NEVER** use `mcp__chipagent-backend__run_stage` for this flow — parameter path issues
- **NEVER** skip `clean_all` between retries — ORFS caches stale results
- **ALWAYS** verify Yosys compiles the design before running ORFS (Step 4 verification)
- **ALWAYS** set `SYNTH_HIERARCHICAL = 1` — preserves SRAM module boundaries
- **ALWAYS** set `MACRO_PLACE_HALO = 20 20` — prevents standard cells from overlapping SRAM halo
- **ALWAYS** set `DONT_USE_CELLS` for SRAM macros — prevents ABC from using them as logic cells
- **ALWAYS** set `SKIP_ANTENNA_REPAIR_POST_DRT = 1` — avoids OOM during antenna repair

## Input

$ARGUMENTS

A Chipyard config name (e.g., `tinyrocket`, `TinyRocketConfig`). Optional second argument for work directory.

## Output

Upon completion:
- GDS: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.gds`
- Netlist: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.v`
- SPEF: `$ORFS_FLOW/results/sky130hd/tinyRocket/base/6_final.spef`
- Reports: `$ORFS_FLOW/reports/sky130hd/tinyRocket/base/`
- Timing/area/DRC summary displayed in conversation
