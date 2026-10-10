---
name: chipyard-pnr-docker
description: "Run full Chipyard-to-ORFS PnR flow with multi-round parameter iteration in Docker: generate RTL from Chipyard Docker, preprocess nosram+SRAM override, run 3 rounds of ORFS synth→finish on sky130hd with progressive clock/utilization/density tuning for optimal PPA."
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
  - mcp__chipagent-backend-docker__check_environment
  - mcp__chipagent-backend-docker__generate_config
  - mcp__chipagent-backend-docker__run_stage
  - mcp__chipagent-backend-docker__get_report
  - mcp__chipagent-backend-docker__diagnose_failure
  - mcp__chipagent-backend-docker__clean_design
  - mcp__chipagent-backend-docker__compare_runs
---

# chip-agent:chipyard-pnr-docker

End-to-end **Docker** flow: Chipyard RTL generation → nosram preprocessing → SRAM override generation → ORFS full PnR (synth → floorplan → place → cts → route → finish) on sky130hd.

This skill handles the **hard parts** of getting Chipyard-generated Verilog through ORFS — entirely via Docker containers, no local Chipyard or ORFS installation required.

- RTL generation via Chipyard Docker image (`ictmrc/chipyard-image:1.9.1-ubuntu-22.04`)
- PnR execution via ORFS Docker image (`openroad/orfs:latest`) through MCP tools
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
□ Verify environment (Docker, Chipyard image, ORFS image)
□ Generate Verilog and consolidate nosram.sv (Docker)
□ Generate SRAM override modules (sram-mapping-docker agent)
□ Identify clock ports from ChipTop
□ Generate ORFS config.mk (container paths) and constraint.sdc
□ Run multi-round PnR iteration (3 rounds adaptive)
□ Compare rounds and select best result
```

## Instructions

**Determine the project root directory** from the user's current working project (the directory containing `scripts/` and `chisel-project/`; `MyDesign/` is created on first use), not from the skill's installation location. Use that directory as the base for all relative paths below.

**IMPORTANT — No local ORFS/Chipyard required.** This skill assumes only Docker + `$PROJECT_ROOT` are available. All ORFS stages run inside Docker containers via MCP tools. Results are auto-mounted to host filesystem.

**IMPORTANT — config.mk uses container paths.** All file paths in config.mk must use container paths:
- Project files: `/workspace/MyDesign/...` (host `$PROJECT_ROOT/MyDesign/...` is mounted as `/workspace`)
- ORFS internals: `/OpenROAD-flow-scripts/flow/...` (built into Docker image)
- SRAM22 macros: `/OpenROAD-flow-scripts/flow/platforms/sky130ram/sram22_sky130_macros/...` (mounted from host by MCP server)

**IMPORTANT — MCP server name.** All MCP tools are `mcp__chipagent-backend-docker__*` (Python server at `.claude/mcp-server-docker-python/server.py`).

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
```

**Resolve correct Chipyard config class name.** The user may pass a lowercase shorthand (e.g. `smallboom`, `tinyrocket`) that doesn't match the actual Scala class name. Search inside the Chipyard Docker image to find the exact `chipyard.*Config` class:

```bash
# Search for matching config class in Chipyard Docker
# Input like "smallboom" → find "SmallBoomConfig", "tinyrocket" → find "TinyRocketConfig"
docker run --rm \
  --entrypoint bash \
  ictmrc/chipyard-image:1.9.1-ubuntu-22.04 \
  -c "
    cd /workspace/chipyard
    # Search all config scala files for class definitions matching the user input
    grep -rn 'class .*Config extends' generators/ --include='*.scala' \
      | sed 's/.*class //' | sed 's/ extends.*//' \
      | grep -i '$RAW_CONFIG' || true
  "
```

From the search results, select the **first exact match** and set `CONFIG` and `DESIGN`:

```bash
# If user input already has uppercase (e.g. "SmallBoomConfig"), use it directly
if echo "$RAW_CONFIG" | grep -qE '[A-Z]'; then
    CONFIG=$(echo "$RAW_CONFIG" | grep -qE 'Config$' && echo "$RAW_CONFIG" || echo "${RAW_CONFIG}Config")
    DESIGN=$(echo "$CONFIG" | sed 's/Config$//')
else
    # Otherwise use the resolved class name from Docker search
    # e.g. RESOLVED_CONFIG="SmallBoomConfig" (from grep result above)
    CONFIG="${RESOLVED_CONFIG}"
    DESIGN=$(echo "$CONFIG" | sed 's/Config$//')
fi

WORK_DIR="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/pnr"
mkdir -p "$WORK_DIR"
```

### Step 1 -- Verify Environment

**No local Chipyard/ORFS paths to check.** Only Docker and MCP backend are required.

```bash
# Verify Docker is available
docker --version || STOP "Docker not installed"

# Verify Chipyard Docker image
docker image inspect ictmrc/chipyard-image:1.9.1-ubuntu-22.04 >/dev/null 2>&1 || \
    STOP "Chipyard Docker image not found: docker pull ictmrc/chipyard-image:1.9.1-ubuntu-22.04"

# Verify ORFS Docker image
docker image inspect openroad/orfs:latest >/dev/null 2>&1 || \
    STOP "ORFS Docker image not found: docker pull openroad/orfs:latest"
```

Call `mcp__chipagent-backend-docker__check_environment` to verify ORFS/sky130hd/sky130ram availability inside Docker.

### Step 2 -- Generate Verilog and Consolidate nosram.sv (Docker)

Run `make verilog CONFIG=<Config>` in `sims/verilator` inside Chipyard Docker to generate Verilog, then merge the split SV files listed in `.top.f` (excluding SRAM mems wrappers) into a single `nosram.sv`. Copy `mems.conf` files for SRAM mapping. All operations happen **inside the same Docker container** to preserve generated artifacts.

**Why `sims/verilator` instead of `vlsi/buildfile`?** The `buildfile` target requires `tutorial=sky130-openroad` which assumes Rocket-core IO binders and fails for BOOM and other non-Rocket configs due to DontTouch annotation mismatches. `make verilog` in `sims/verilator` works for all configs.

```bash
docker run --rm \
  -v "$WORK_DIR:/out" \
  --entrypoint bash \
  ictmrc/chipyard-image:1.9.1-ubuntu-22.04 \
  -c "
    export RISCV=/workspace/chipyard/.conda-env/riscv-tools
    export PATH=/workspace/chipyard/.conda-env/bin:\$PATH
    export JAVA_TOOL_OPTIONS='-Dfile.encoding=UTF-8 -Xmx8G'
    cd /workspace/chipyard/sims/verilator
    make verilog CONFIG=${CONFIG} 2>&1 | tail -5 || true

    GEN_DIR=/workspace/chipyard/sims/verilator/generated-src/chipyard.TestHarness.${CONFIG}
    TOP_F=\$GEN_DIR/chipyard.TestHarness.${CONFIG}.top.f

    # Merge all gen-collateral files listed in top.f into single nosram.sv
    # Skip SRAM mems wrapper files (*.mems.v) — we replace them with sky130_sram overrides
    NOSRAM_V=/out/${CONFIG}_nosram.sv
    > \$NOSRAM_V
    while IFS= read -r f; do
        if [ -f \"\$f\" ]; then
            if echo \"\$f\" | grep -q 'mems\.v'; then
                continue
            fi
            cat \"\$f\"
            echo \"\"
        fi
    done < \"\$TOP_F\" >> \$NOSRAM_V

    # Copy mems.conf files for SRAM mapping
    cp \$GEN_DIR/chipyard.TestHarness.${CONFIG}.top.mems.conf /out/mems.conf
    cp \$GEN_DIR/chipyard.TestHarness.${CONFIG}.model.mems.conf /out/model.mems.conf

    echo '=== nosram.sv generated ==='
    echo \"Lines: \$(wc -l < \$NOSRAM_V)\"
    echo \"Modules: \$(grep '^module ' \$NOSRAM_V | wc -l)\"
  "
```

**Timeout:** 600000ms (10 minutes).

**Verification:**
```bash
NOSRAM_V="$WORK_DIR/${CONFIG}_nosram.sv"
test -f "$NOSRAM_V" || STOP "nosram.sv not found — buildfile may have failed"
echo "Generated $(wc -l < "$NOSRAM_V") lines, $(grep '^module ' "$NOSRAM_V" | wc -l) modules"
```

**Do NOT include** the SRAM wrapper (`*.top.mems.v`) — it uses sram22 macros which we replace with sky130_sram macros via the override.

### Step 3 -- Generate SRAM Override Modules

**Delegate to `sram-mapping-docker` subagent.**

Before invoking the agent, prepare SRAM22 at `$PROJECT_ROOT/sram22_sky130_macros/`.

```bash
SRAM22_DIR="$PROJECT_ROOT/sram22_sky130_macros"

# Clone SRAM22 if not present
if [ ! -d "$SRAM22_DIR" ]; then
    git clone --depth 1 https://github.com/rahulk29/sram22_sky130_macros.git "$SRAM22_DIR"
fi

# Decompress GDS files
for gds_gz in "$SRAM22_DIR"/*/*.gds.gz; do
    [ -f "${gds_gz%.gz}" ] || gunzip -k "$gds_gz"
done
```

Spawn the `sram-mapping-docker` agent (from `agents/sram-mapping-docker.md`) with this context in the prompt:

```
Agent(
  subagent_type: "sram-mapping-docker",
  description: "Generate SRAM override modules (Docker)",
  prompt: "Generate SRAM override modules for Chipyard design (Docker mode).
    GEN_DIR: $WORK_DIR  (nosram.sv is here, read mems.conf from Docker or inline below)
    OUTPUT_DIR: $WORK_DIR
    ORFS_FLOW_PATH: $PROJECT_ROOT/OpenROAD-flow-scripts/flow
    DOCKER_IMAGE: openroad/orfs:latest
    SRAM22_DIR: $PROJECT_ROOT/sram22_sky130_macros
    Use macro_source field in sram_mapping.json: 'orfs' for ORFS macros, 'sram22' for SRAM22 macros."
)
```

**After the agent completes, verify the output:**

```bash
test -f "$WORK_DIR/sram_override.v" || STOP "sram-mapping-docker agent did not produce sram_override.v"
test -f "$WORK_DIR/sram_mapping.json" || STOP "sram-mapping-docker agent did not produce sram_mapping.json"
```

**Extract SRAM macro list** from the generated mapping for Step 5:

```bash
USED_MACROS=$(jq -r '.mappings[] | select(.macro != null) | .macro' "$WORK_DIR/sram_mapping.json" | sort -u)
echo "Used SRAM macros: $USED_MACROS"
```

### Step 4 -- Identify Clock Ports

Read the ChipTop module ports:
```bash
grep -A30 "^module ChipTop" "$WORK_DIR/${CONFIG}_nosram.sv" | head -20
```

Typical TinyRocketConfig ChipTop clock ports (verify from actual module definition):
- `clock_clock` — main core clock (input)
- `jtag_TCK` — JTAG clock (input, 100ns period)
- `serial_tl_clock` — serial link clock (**output**, generated clock — do NOT use `create_clock` on it)

### Step 5 -- Generate ORFS Config

Use `mcp__chipagent-backend-docker__generate_config` to create base config, then overwrite with full Chipyard-specific settings using **container paths**.

**6a. Generate base config:**

Note: `workspace_dir` is the output directory for config.mk and constraint.sdc on the host.
The tool writes files directly to this directory.

```
mcp__chipagent-backend-docker__generate_config(
  module_name="ChipTop",
  verilog_path="$WORK_DIR/${CONFIG}_nosram.sv",
  workspace_dir="$WORK_DIR/pnr",
  clock_port="clock_clock",
  clock_period_ns=10,
  core_utilization=55,
  place_density=0.65
)
```

**6b. Overwrite config.mk with full Chipyard-specific settings (container paths):**

The MCP-generated config uses host paths — replace with container paths for Docker execution. The SRAM macro list is dynamically built from `sram_mapping.json` generated by the sram-mapping-docker agent.

```bash
# Container path for ORFS flow
ORFS_CONTAINER="/OpenROAD-flow-scripts/flow"
# Container path for SRAM22 (mounted by MCP server from host ORFS path)
SRAM22_CONTAINER="/workspace/sram22_sky130_macros"

# Container path for nosram and override (host $PROJECT_ROOT mounts as /workspace)
NOSRAM_CONTAINER="/workspace/MyDesign/$DESIGN/workspace/pnr/${CONFIG}_nosram.sv"
OVERRIDE_CONTAINER="/workspace/MyDesign/$DESIGN/workspace/pnr/sram_override.v"
SDC_CONTAINER="/workspace/MyDesign/$DESIGN/workspace/pnr/constraint.sdc"

# Build SRAM macro lists dynamically from sram_mapping.json
MACROS=$(jq -r '.mappings[] | select(.macro != null) | .macro' "$WORK_DIR/sram_mapping.json" | sort -u)
MACRO_LIST=$(echo "$MACROS" | tr '\n' ' ')

# Build VERILOG_FILES: nosram + override + each macro's behavioral .v
VERILOG_LIST="$NOSRAM_CONTAINER $OVERRIDE_CONTAINER"
for m in $MACROS; do
    # Determine macro source (orfs vs sram22) from sram_mapping.json
    SOURCE=$(jq -r ".mappings[] | select(.macro == \"$m\") | .macro_source" "$WORK_DIR/sram_mapping.json" | head -1)
    if [ "$SOURCE" = "sram22" ]; then
        VERILOG_LIST="$VERILOG_LIST $SRAM22_CONTAINER/$m/$m.v"
    else
        VERILOG_LIST="$VERILOG_LIST $ORFS_CONTAINER/platforms/sky130ram/$m/$m.v"
    fi
done

# Build ADDITIONAL_LEFS/LIBS/GDS lines
LEFS=""; LIBS=""; GDS=""
for m in $MACROS; do
    SOURCE=$(jq -r ".mappings[] | select(.macro == \"$m\") | .macro_source" "$WORK_DIR/sram_mapping.json" | head -1)
    if [ "$SOURCE" = "sram22" ]; then
        MACRO_BASE="$SRAM22_CONTAINER/$m"
        LEFS="$LEFS $MACRO_BASE/$m.lef"
        LIBS="$LIBS $MACRO_BASE/${m}_tt_025C_1v80.lib"
        GDS="$GDS $MACRO_BASE/$m.gds"
    else
        MACRO_BASE="$ORFS_CONTAINER/platforms/sky130ram/$m"
        LEFS="$LEFS $MACRO_BASE/$m.lef"
        LIBS="$LIBS $MACRO_BASE/${m}_TT_1p8V_25C.lib"
        GDS="$GDS $MACRO_BASE/$m.gds"
    fi
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

export SDC_FILE = $SDC_CONTAINER

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
create_clock -name core_clock -period 10 [get_ports clock_clock]
create_clock -name jtag_clock -period 100 [get_ports jtag_TCK]
# NOTE: serial_tl_clock is an output (generated clock) — do NOT create_clock on it
# NOTE: For multi-round iteration, update core_clock period here to match round's clock_period_ns
set_clock_groups -asynchronous -group {core_clock} -group {jtag_clock}
set_input_delay -clock core_clock 0 [all_inputs -no_clocks]
set_output_delay -clock core_clock 0 [all_outputs]
SDCEOF
```

### Step 6 -- Run ORFS Full Flow (Multi-Round Iteration)

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

**6a. Clean previous run (direct MCP call):**
```
mcp__chipagent-backend-docker__clean_design(
  config_mk_path="$WORK_DIR/pnr/config.mk",
  orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow"
)
```

**6b. Initialize round parameters:**

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

**6c. Spawn background round executor (Round 1 — baseline):**

Spawn the `pnr-round-executor-docker` agent with `run_in_background: true`:

```
Agent(
  subagent_type: "pnr-round-executor-docker",
  description: "PnR Round 1: ChipTop (tinyRocket) — baseline (Docker)",
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
    orfs_flow_path: $PROJECT_ROOT/OpenROAD-flow-scripts/flow
    clock_port: clock_clock
    backend: docker
    NOTE: Use mcp__chipagent-backend-docker__* tools (NOT local).
    Stage timeouts: synth=30min, floorplan=60min, place=30min, cts=30min, route=120min, finish=30min.
  "
)
```

**6d. Handle round completion — diagnose and decide next parameters:**

When the background agent completes, you will receive a task notification. At that point:

1. **Save round results** via `compare_runs`:
   ```
   mcp__chipagent-backend-docker__compare_runs(
     action="save",
     workspace_dir="$WORK_DIR",
     run={"round": <current_round>, "config": {<params>}, "metrics": {<from report>}, "status": "pass"|"fail"}
   )
   ```

2. **Collect detailed metrics** via MCP:
   ```
   mcp__chipagent-backend-docker__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow")
   mcp__chipagent-backend-docker__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow")
   ```

3. **Diagnose results** — call `diagnose_failure` to get AI-readable analysis:
   ```
   mcp__chipagent-backend-docker__diagnose_failure(
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
   - Apply the Adaptive Tuning Logic (see above)
   - Determine the next round's `{clock_period_ns, core_utilization, place_density, gpl_timing_driven, gpl_routability_driven, setup_slack_margin}`

**6e. Launch next round (if more rounds remain and termination conditions not met):**

Check termination conditions first:
- If WNS >= 0 AND DRC == 0: **success**, proceed to Step 7
- If `current_round >= total_rounds`: **max rounds reached**, proceed to Step 7
- If consecutive WNS improvement < 0.1ns: **converged**, proceed to Step 7

Otherwise, launch next round with AI-decided parameters:

1. **Update `config.mk`** with the AI-decided parameters:
   ```bash
   # CP, CU, PD, GTD, GRD, SSM are the AI-decided values from Step 6d
   sed -i "s/^export CORE_UTILIZATION = .*/export CORE_UTILIZATION = $CU/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export PLACE_DENSITY = .*/export PLACE_DENSITY = $PD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export GPL_TIMING_DRIVEN = .*/export GPL_TIMING_DRIVEN = $GTD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export GPL_ROUTABILITY_DRIVEN = .*/export GPL_ROUTABILITY_DRIVEN = $GRD/" "$WORK_DIR/pnr/config.mk"
   sed -i "s/^export SETUP_SLACK_MARGIN = .*/export SETUP_SLACK_MARGIN = $SSM/" "$WORK_DIR/pnr/config.mk"
   ```

2. **Update `constraint.sdc`** with new clock period:
   ```bash
   sed -i "s/-period [0-9]* \[get_ports clock_clock\]/-period $CP [get_ports clock_clock]/" "$WORK_DIR/pnr/constraint.sdc"
   ```

3. **Clean ORFS cache:**
   ```
   mcp__chipagent-backend-docker__clean_design(
     config_mk_path="$WORK_DIR/pnr/config.mk",
     orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow"
   )
   ```

4. **Spawn next round executor** — same as Step 6c, replacing round_number=$NEXT_ROUND and current_params={CP,CU,PD,GTD,GRD,SSM}.

5. **Loop back to Step 6d** when this round completes.

### Step 7 -- Compare Rounds and Select Best Result

**7a. Load all round results and recommend best:**

```
mcp__chipagent-backend-docker__compare_runs(
  action="recommend",
  workspace_dir="$WORK_DIR"
)
```

**7b. Collect detailed metrics for each round** (if not already saved):

```
mcp__chipagent-backend-docker__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow")
mcp__chipagent-backend-docker__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow")
```

**7c. Display comparison table:**

```
=== Chipyard PnR Multi-Round Results: ChipTop (tinyRocket) [Docker] ===

| Round | Clock(ns) | Util% | Density | Timing-Driven | Routability | Slack Margin | WNS(ns) | TNS(ns) | Area(um^2) | DRC | Power(uW) | Status |
|-------|-----------|-------|---------|---------------|-------------|--------------|---------|---------|------------|-----|-----------|--------|
| R1    | 10        | 55    | 0.65    | -             | Y           | 0.2          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R2    | 8         | 60    | 0.72    | Y             | -           | 0.1          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R3    | 6         | 70    | 0.80    | Y             | Y           | 0.05         | ...     | ...     | ...        | ... | ...       | PASS/FAIL |

Best round: R<X> — <reason>
```

**7d. Report final recommended result:**

```
=== Final Recommended Result [Docker] ===
Round: R<X>
Clock Period: <ns> ns (<freq> MHz)
WNS: <wns> ns | TNS: <tns> ns
Area: <area> um^2
Power: <power> uW
DRC Violations: <count>
Status: PASS / FAIL
```

**Expected output files** (on host at `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/tinyRocket/base/`):
| File | Description |
|------|-------------|
| `6_final.gds` | Final GDSII layout (~255 MB) |
| `6_final.odb` | Final OpenDB database (~540 MB) |
| `6_final.v` | Final Verilog netlist (~40 MB) |
| `6_final.spef` | Parasitic extraction (~156 MB) |
| `6_final.def` | Final DEF file (~241 MB) |

## Anti-Patterns

- **NEVER** use `mcp__chipagent-backend__*` (local MCP) — use `mcp__chipagent-backend-docker__*`
- **NEVER** use local host paths in config.mk `VERILOG_FILES`/`LEFS`/`LIBS`/`SDC_FILE` — must use container paths (`/workspace/...` and `/OpenROAD-flow-scripts/flow/...`)
- **NEVER** use `make buildfile tutorial=sky130-openroad` for non-Rocket configs — it forces Rocket-specific IO binders and DontTouch annotations that fail for BOOM and other cores. Use `make verilog CONFIG=<Config>` in `sims/verilator` instead
- **NEVER** use `/root/chipyard` — correct Chipyard path inside Docker is `/workspace/chipyard/`
- **NEVER** forget to clone SRAM22 to host `$ORFS_FLOW_PATH/platforms/sky130ram/sram22_sky130_macros/` — the MCP server auto-mounts this path into Docker containers
- **NEVER** assume local ORFS/Chipyard installation exists — only Docker + `$PROJECT_ROOT`
- **NEVER** use behavioral SRAM stubs (reg arrays) — causes OOM in routing
- **NEVER** add `ENABLE_YOSYS_FLOW=1` to `make verilog` — it causes firtool strict annotation checking that fails for non-Rocket configs. The SFC (Scala FIRRTL Compiler) used by `sims/verilator` handles DontTouch annotations leniently
- **NEVER** append stub files that are already in `top.f` — causes duplicate module errors
- **NEVER** use `SYNTH_BLACKBOXES` without `ADDITIONAL_LEFS/LIBS/GDS` — causes missing cost error
- **NEVER** skip `clean_design` between PnR rounds — stale ORFS cache causes misleading results
- **NEVER** skip the baseline round (R1) — it validates the flow before aggressive tuning
- **NEVER** skip nosram preprocessing — behavioral SRAM modules cause OOM
- **NEVER** use `SWAP_ARITH_OPERATORS=1` — causes ABC crash on large designs
- **ALWAYS** use `timeout_minutes=120` for the `route` stage — detailed routing takes up to 120 minutes
- **ALWAYS** use `timeout_minutes=30` for the `synth` stage — ABC technology mapping needs 30 minutes
- **ALWAYS** use `timeout_minutes=30` for the `place` stage — repair_design resize processing needs 30 minutes
- **ALWAYS** set `SYNTH_HIERARCHICAL = 1` — preserves SRAM module boundaries
- **ALWAYS** set `MACRO_PLACE_HALO = 20 20` — prevents standard cells from overlapping SRAM halo
- **ALWAYS** set `DONT_USE_CELLS` for SRAM macros — prevents ABC from using them as logic cells
- **ALWAYS** set `SKIP_ANTENNA_REPAIR_POST_DRT = 1` — avoids OOM during antenna repair
- **ALWAYS** save round results via `compare_runs` before starting the next round
- **ALWAYS** use `compare_runs(action="recommend")` to select the best round objectively

## Input

$ARGUMENTS

A Chipyard config name (e.g., `tinyrocket`, `TinyRocketConfig`). Optional arguments:
- **Target frequency**: `100MHz` or `10ns` (AI will adaptively tune parameters to reach this target over multiple rounds)

## Output

Upon completion:
- GDS: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/tinyRocket/base/6_final.gds`
- Netlist: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/tinyRocket/base/6_final.v`
- SPEF: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/tinyRocket/base/6_final.spef`
- Reports: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/reports/sky130hd/tinyRocket/base/`
- Timing/area/DRC summary displayed in conversation
