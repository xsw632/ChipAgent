---
name: chipyard-pnr-docker-test
description: "Run full Chipyard-to-ORFS PnR flow for large designs (SmallBOOM etc.) using All-Mock memory blackboxing in Docker: generate RTL, preprocess nosram, run multi-round ORFS synth->finish with mock SRAMs to avoid OOM."
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

# chip-agent:chipyard-pnr-docker-test (All-Mock)

End-to-end **Docker** flow for **large Chipyard designs** (SmallBOOM etc.) that cannot fit in memory with physical SRAM macros. Uses ORFS **All-Mock memory blackboxing** to replace all SRAMs with lightweight mock modules, reducing peak memory from 50+ GB to ~20 GB.

- RTL generation via Chipyard Docker image (`ictmrc/chipyard-image:1.9.1-ubuntu-22.04`)
- PnR execution via ORFS Docker image (`openroad/orfs:latest`) through MCP tools
- **All-Mock SRAM blackboxing** (no physical SRAM macros, no sram-mapping needed)
- Multi-clock domain SDC constraints
- Module consolidation from split SV files

**Key difference from chipyard-pnr-docker:** Skips SRAM override generation entirely. Uses `SYNTH_MEMORY_MAX_BITS=1` + `SYNTH_MOCK_LARGE_MEMORIES=1` + `SYNTH_KEEP_MOCKED_MEMORIES=1` so ORFS auto-generates mock SRAM blocks. The mock modules have no real timing data — this flow is for **place-and-route feasibility and area estimation**, not final timing signoff.

## Usage

```
/chip-agent:chipyard-pnr-docker-test <config>
```

**Examples:**

```
/chip-agent:chipyard-pnr-docker-test smallboom
/chip-agent:chipyard-pnr-docker-test SmallBoomConfig
/chip-agent:chipyard-pnr-docker-test smallboom 50MHz
```

Create the checklist and go on.
```
□ Parse arguments and setup work directory
□ Verify environment (Docker, Chipyard image, ORFS image)
□ Generate Verilog and consolidate nosram.sv (Docker)
□ Identify clock ports from ChipTop
□ Generate ORFS config.mk (All-Mock, container paths) and constraint.sdc
□ Run multi-round PnR iteration (3 rounds adaptive)
□ Compare rounds and select best result
```

## Instructions

**Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

**IMPORTANT — No local ORFS/Chipyard required.** This skill assumes only Docker + `$PROJECT_ROOT` are available. All ORFS stages run inside Docker containers via MCP tools. Results are auto-mounted to host filesystem.

**IMPORTANT — config.mk uses container paths.** All file paths in config.mk must use container paths:
- Project files: `/workspace/MyDesign/...` (host `$PROJECT_ROOT/MyDesign/...` is mounted as `/workspace`)
- ORFS internals: `/OpenROAD-flow-scripts/flow/...` (built into Docker image)

**IMPORTANT — MCP server name.** All MCP tools are `mcp__chipagent-backend-docker__*` (Python server at `.claude/mcp-server-docker-python/server.py`).

**IMPORTANT — All-Mock means no SRAM macros.** This flow does NOT use `SYNTH_BLACKBOXES`, `ADDITIONAL_LEFS/LIBS/GDS`, `sram_override.v`, or `sram_mapping.json`. All memory handling is done automatically by ORFS via the three mock variables.

**IMPORTANT — EDA reference knowledge.** Before choosing Round 2+ parameters, read the relevant reference from this skill directory:
- `references/orfs-metrics-and-objectives.md` when comparing rounds or deciding if a round is a valid QoR candidate
- `references/orfs-parameter-guide.md` before changing `config.mk` or `constraint.sdc`
- `references/orfs-failure-signatures.md` after any failed, DRC-dirty, or timing-dirty round

If this skill was installed as a single slash-command Markdown file, use the appended "Bundled chipyard-pnr-test references" section instead.

## Pipeline

### Step 0 -- Parse Arguments and Setup

```bash
PROJECT_ROOT="<project-root>"
RAW_CONFIG=$(echo "$ARGUMENTS" | awk '{print $1}')
FREQ_ARG=$(echo "$ARGUMENTS" | awk '{print $2}')
if [ -z "$RAW_CONFIG" ]; then RAW_CONFIG="smallboom"; fi

# Parse optional target frequency from second argument
# e.g. "smallboom 50MHz" → TARGET_FREQ_MHZ=50, "smallboom 20ns" → TARGET_CLOCK_NS=20
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

# Baseline defaults for large designs: start conservative
BASELINE_FREQ_MHZ="${TARGET_FREQ_MHZ:-50}"
BASELINE_CLOCK_NS="${TARGET_CLOCK_NS:-20}"
```

**Resolve correct Chipyard config class name.** The user may pass a lowercase shorthand (e.g. `smallboom`, `tinyrocket`) that doesn't match the actual Scala class name. Search inside the Chipyard Docker image to find the exact `chipyard.*Config` class:

```bash
# Search for matching config class in Chipyard Docker
# Input like "smallboom" → find "SmallBoomConfig"
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
    CONFIG="${RESOLVED_CONFIG}"
    DESIGN=$(echo "$CONFIG" | sed 's/Config$//')
fi

WORK_DIR="$PROJECT_ROOT/MyDesign/$DESIGN/workspace/pnr"
mkdir -p "$WORK_DIR"
```

### Step 1 -- Verify Environment

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

Call `mcp__chipagent-backend-docker__check_environment` to verify ORFS/sky130hd availability inside Docker.

### Step 2 -- Generate Verilog and Consolidate nosram.sv (Docker)

Run `make verilog CONFIG=<Config>` in `sims/verilator` inside Chipyard Docker to generate Verilog, then merge the split SV files listed in `.top.f` (excluding SRAM mems wrappers) into a single `nosram.sv`.

**Why `sims/verilator` instead of `vlsi/buildfile`?** The `buildfile` target requires `tutorial=sky130-openroad` which assumes Rocket-core IO binders and fails for BOOM and other non-Rocket configs. `make verilog` in `sims/verilator` works for all configs.

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
    # Skip SRAM mems wrapper files (*.mems.v) — All-Mock will handle them
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

    echo '=== nosram.sv generated ==='
    echo \"Lines: \$(wc -l < \$NOSRAM_V)\"
    echo \"Modules: \$(grep '^module ' \$NOSRAM_V | wc -l)\"
  "
```

**Timeout:** 600000ms (10 minutes).

**Verification:**
```bash
NOSRAM_V="$WORK_DIR/${CONFIG}_nosram.sv"
test -f "$NOSRAM_V" || STOP "nosram.sv not found — make verilog may have failed"
echo "Generated $(wc -l < "$NOSRAM_V") lines, $(grep '^module ' "$NOSRAM_V" | wc -l) modules"
```

**NOTE:** Unlike the physical-SRAM flow, we do NOT copy `mems.conf` or run `sram-mapping-docker`. The All-Mock approach lets ORFS handle all memories automatically.

### Step 3 -- Identify Clock Ports

Read the ChipTop module ports:
```bash
grep -A30 "^module ChipTop" "$WORK_DIR/${CONFIG}_nosram.sv" | head -20
```

Typical BOOM ChipTop clock ports (verify from actual module definition):
- `clock_clock` — main core clock (input)
- `io_debug_clock` or `jtag_TCK` — debug/JTAG clock (input)
- `serial_tl_clock` — serial link clock (**output**, generated clock — do NOT use `create_clock` on it)

### Step 4 -- Generate ORFS Config (All-Mock)

Use `mcp__chipagent-backend-docker__generate_config` to create base config, then overwrite with All-Mock settings using **container paths**.

**4a. Generate base config:**

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

**4b. Overwrite config.mk with All-Mock settings (container paths):**

The MCP-generated config uses host paths — replace with container paths for Docker execution. Use All-Mock memory blackboxing instead of physical SRAM macros.

```bash
# Container path for nosram (host $PROJECT_ROOT mounts as /workspace)
NOSRAM_CONTAINER="/workspace/MyDesign/$DESIGN/workspace/pnr/${CONFIG}_nosram.sv"
SDC_CONTAINER="/workspace/MyDesign/$DESIGN/workspace/pnr/constraint.sdc"

# Extract DESIGN_NICKNAME from CONFIG (e.g. "SmallBoomConfig" → "smallBoom")
NICKNAME=$(echo "$DESIGN" | sed 's/\(.\)\([A-Z]\)/\1_\2/' | tr '[:upper:]' '[:lower:]' | sed 's/_//')

cat > "$WORK_DIR/pnr/config.mk" << CFGEOF
export DESIGN_NAME = ChipTop
export PLATFORM = sky130hd
export DESIGN_NICKNAME = ${NICKNAME}

export VERILOG_FILES = \\
    $NOSRAM_CONTAINER

export SDC_FILE = $SDC_CONTAINER

# ============================================================
# All-Mock Memory Blackboxing (for large designs like SmallBOOM)
# ============================================================
# Treat ALL memories >1 bit as blackboxes (no FF expansion)
export SYNTH_MEMORY_MAX_BITS = 1
# Auto-generate mock placeholder modules for blackboxed memories
export SYNTH_MOCK_LARGE_MEMORIES = 1
# Keep mock modules through the entire flow (do not strip)
export SYNTH_KEEP_MOCKED_MEMORIES = 1

# Hierarchical synthesis to preserve module boundaries
export SYNTH_HIERARCHICAL = 1
export SYNTH_MINIMUM_KEEP_SIZE = 1000
export ABC_AREA = 1

# Physical parameters (conservative defaults for large designs)
export CORE_UTILIZATION = 40
export PLACE_DENSITY = 0.55
export GPL_TIMING_DRIVEN = 1
export GPL_ROUTABILITY_DRIVEN = 1
export SETUP_SLACK_MARGIN = 0.5
export MACRO_PLACE_HALO = 20 20

# CTS tuning
export CTS_CLUSTER_SIZE = 20
export CTS_CLUSTER_DIAMETER = 50

export TNS_END_PERCENT = 100
export SKIP_ANTENNA_REPAIR_POST_DRT = 1
export NUM_CORES = 4

# Skip IR drop analysis
export PWR_NETS_VOLTAGES =
export GND_NETS_VOLTAGES =
CFGEOF
```

**4c. Write SDC with multi-clock constraints:**

```bash
cat > "$WORK_DIR/pnr/constraint.sdc" << SDCEOF
current_design ChipTop
create_clock -name core_clock -period 20 [get_ports clock_clock]
# NOTE: Update clock port name based on Step 3 inspection
# NOTE: For multi-round iteration, update core_clock period here to match round's clock_period_ns
set_clock_groups -asynchronous -group {core_clock}
set_input_delay -clock core_clock 0 [all_inputs -no_clocks]
set_output_delay -clock core_clock 0 [all_outputs]
SDCEOF
```

**NOTE:** Verify the clock port name and additional clock domains from Step 3 before writing the SDC. The above is a template — adjust `create_clock` port and add other clocks (JTAG, etc.) as needed.

### Step 5 -- Run ORFS Full Flow (Multi-Round Iteration)

Run at least **3 rounds** of PnR iteration. The user sets a target frequency; the AI adaptively tunes parameters based on each round's diagnostic results. Each round runs as a background subagent.

For Round 2+ decisions, combine the bundled EDA references with `get_report`, `diagnose_failure`, and prior round history. The references are distilled from the repo's ORFS-Agent and EDA-Corpus material but do not replace actual run reports.

**All-Mock flow characteristics:**
- **Slower synthesis**: Yosys mock generation adds ~10-15 min to synth stage
- **Longer runtime**: Full flow ~7 hours for SmallBOOM with default parameters
- **Peak memory**: ~20 GB (vs 50+ GB without All-Mock)
- **No SRAM timing**: Mock modules have no real timing — use for area/routing feasibility

**Parameter Knobs:**

| Parameter | Description | Tuning Direction |
|-----------|-------------|------------------|
| `clock_period_ns` | Clock period (ns) = 1000 / freq_mhz | Progressively approach target frequency |
| `core_utilization` | Initial post-synthesis floorplan target (%) | Overflow/congestion → decrease; clean slack-only rounds may increase carefully |
| `place_density` | Placement density (0.0–1.0) | Congestion/DRC → decrease; area compaction only after routing is clean |
| `gpl_timing_driven` | Timing-driven placement | Keep enabled for large timed designs |
| `gpl_routability_driven` | Routability-driven placement | Keep enabled when congestion, overflow, or DRC appears |
| `setup_slack_margin` | Timing margin (ns) | Tighten only when timing is close or clean |

**Conservative Baseline for Large Designs:**

| Parameter | Default (Round 1) | Rationale |
|-----------|-------------------|-----------|
| `clock_period_ns` | 20 (50MHz) | Conservative baseline |
| `core_utilization` | 40 | Lower than small designs (35-45% for BOOM) |
| `place_density` | 0.55 | Lower to reduce congestion |
| `gpl_timing_driven` | 1 | Always on for large designs |
| `gpl_routability_driven` | 1 | Always on for large designs |
| `setup_slack_margin` | 0.5 | Start relaxed, tighten in later rounds |

**Adaptive Tuning Logic:**

Round 1 uses the baseline frequency. Round 2+ calls `diagnose_failure` and `get_report` to read previous round results, then adjusts parameters:

| Diagnostic Signal | Meaning | AI Adjustment |
|-------------------|---------|---------------|
| WNS < -2ns or large negative TNS | Severe timing violation | Relax clock_period (+1-2ns); keep timing-driven placement enabled; do not increase density |
| WNS slightly negative (e.g. -0.5ns) | Near timing closure | Fine-tune clock_period (+0.25-0.5ns) or reduce place_density slightly if congestion also appears |
| WNS >= 0 and DRC == 0 | Viable point | Save result; tighten clock (-0.5 to -1ns) only if target frequency is not met |
| DRC violations > 0 | Routing/detail-route legality issue | Reduce place_density (-0.05 to -0.10); reduce utilization if repeated |
| Placement overflow / not enough sites | Effective utilization too high | Reduce utilization (-5 to -10%) and density (-0.05 to -0.10) |
| Routing congestion hotspots | Too little routing whitespace | Reduce place_density; keep gpl_routability_driven enabled |
| OOM / timeout | Insufficient resources or over-aggressive target | Confirm All-Mock config, keep hierarchy, reduce aggressiveness |

**Tuning principles:**
1. Adjust only 1-2 parameters per round; do not drastically change multiple parameters simultaneously
2. Fix route legality before area compaction
3. If WNS >= 0 and DRC == 0, the current parameters are viable — save the round before tightening the clock
4. If WNS does not improve for two consecutive rounds, the limit has been reached — stop iterating
5. Progressively tighten slack_margin from 0.5ns to 0.05ns, but do not tighten when timing is violating
6. For All-Mock flow, timing results exclude SRAM delays — expect optimistic WNS compared to physical SRAM flow
7. Do not compare area/power from failed or DRC-dirty rounds as final QoR candidates

**Termination conditions:** WNS>=0 and DRC==0 / max rounds reached / consecutive WNS improvement < 0.1ns / target frequency achieved.

**5a. Clean previous run (direct MCP call):**
```
mcp__chipagent-backend-docker__clean_design(
  config_mk_path="$WORK_DIR/pnr/config.mk",
  orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow"
)
```

**5b. Initialize round parameters:**

```bash
# Set total rounds (minimum 3, maximum 5)
TOTAL_ROUNDS=3

# Round 1 parameters: conservative baseline for large designs
R1_CLOCK="${BASELINE_CLOCK_NS:-20}"
R1_UTIL=40
R1_DENSITY=0.55
R1_TIMING_DRIVEN=1
R1_ROUTABILITY_DRIVEN=1
R1_SLACK_MARGIN=0.5
```

**5c. Spawn background round executor (Round 1 — baseline):**

Spawn the `pnr-round-executor-docker` agent with `run_in_background: true`:

```
Agent(
  subagent_type: "pnr-round-executor-docker",
  description: "PnR Round 1: ChipTop (All-Mock) — baseline (Docker)",
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
    NOTE: All-Mock flow — synth stage will be slower due to mock SRAM generation.
    Stage timeouts: synth=60min, floorplan=60min, place=60min, cts=60min, route=180min, finish=30min.
  "
)
```

**5d. Handle round completion — diagnose and decide next parameters:**

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
   - Apply `references/orfs-metrics-and-objectives.md`, `references/orfs-parameter-guide.md`, and `references/orfs-failure-signatures.md` as needed
   - Determine the next round's `{clock_period_ns, core_utilization, place_density, gpl_timing_driven, gpl_routability_driven, setup_slack_margin}`

**5e. Launch next round (if more rounds remain and termination conditions not met):**

Check termination conditions first:
- If WNS >= 0 AND DRC == 0: **success**, proceed to Step 6
- If `current_round >= total_rounds`: **max rounds reached**, proceed to Step 6
- If consecutive WNS improvement < 0.1ns: **converged**, proceed to Step 6

Otherwise, launch next round with AI-decided parameters:

1. **Update `config.mk`** with the AI-decided parameters:
   ```bash
   # CP, CU, PD, GTD, GRD, SSM are the AI-decided values from Step 5d
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

4. **Spawn next round executor** — same as Step 5c, replacing round_number=$NEXT_ROUND and current_params={CP,CU,PD,GTD,GRD,SSM}.

5. **Loop back to Step 5d** when this round completes.

### Step 6 -- Compare Rounds and Select Best Result

**6a. Load all round results and recommend best:**

```
mcp__chipagent-backend-docker__compare_runs(
  action="recommend",
  workspace_dir="$WORK_DIR"
)
```

**6b. Collect detailed metrics for each round** (if not already saved):

```
mcp__chipagent-backend-docker__get_report(design_name="ChipTop", stage="finish", orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow")
mcp__chipagent-backend-docker__get_report(design_name="ChipTop", stage="route", orfs_flow_path="$PROJECT_ROOT/OpenROAD-flow-scripts/flow")
```

**6c. Display comparison table:**

```
=== Chipyard PnR Multi-Round Results: ChipTop (All-Mock) [Docker] ===

| Round | Clock(ns) | Util% | Density | Timing-Driven | Routability | Slack Margin | WNS(ns) | TNS(ns) | Area(um^2) | DRC | Power(uW) | Status |
|-------|-----------|-------|---------|---------------|-------------|--------------|---------|---------|------------|-----|-----------|--------|
| R1    | 20        | 40    | 0.55    | Y             | Y           | 0.5          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R2    | ...       | ...   | ...     | ...           | ...         | ...          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |
| R3    | ...       | ...   | ...     | ...           | ...         | ...          | ...     | ...     | ...        | ... | ...       | PASS/FAIL |

Best round: R<X> — <reason>
NOTE: Timing results exclude SRAM delays (All-Mock). Use for area/routing feasibility assessment.
```

**6d. Report final recommended result:**

```
=== Final Recommended Result (All-Mock) [Docker] ===
Round: R<X>
Clock Period: <ns> ns (<freq> MHz)
WNS: <wns> ns | TNS: <tns> ns
Area: <area> um^2
Power: <power> uW
DRC Violations: <count>
Status: PASS / FAIL
NOTE: Timing is optimistic — SRAM delays not modeled in All-Mock flow.
```

**Expected output files** (on host at `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/<nickname>/base/`):
| File | Description |
|------|-------------|
| `6_final.gds` | Final GDSII layout |
| `6_final.odb` | Final OpenDB database |
| `6_final.v` | Final Verilog netlist |
| `6_final.spef` | Parasitic extraction |
| `6_final.def` | Final DEF file |

## Anti-Patterns

- **NEVER** use `mcp__chipagent-backend__*` (local MCP) — use `mcp__chipagent-backend-docker__*`
- **NEVER** use local host paths in config.mk `VERILOG_FILES`/`SDC_FILE` — must use container paths (`/workspace/...`)
- **NEVER** use `make buildfile tutorial=sky130-openroad` for non-Rocket configs — it forces Rocket-specific IO binders that fail for BOOM. Use `make verilog CONFIG=<Config>` in `sims/verilator` instead
- **NEVER** use `/root/chipyard` — correct Chipyard path inside Docker is `/workspace/chipyard/`
- **NEVER** assume local ORFS/Chipyard installation exists — only Docker + `$PROJECT_ROOT`
- **NEVER** add `ENABLE_YOSYS_FLOW=1` to `make verilog` — causes firtool strict annotation checking that fails for non-Rocket configs
- **NEVER** use `SWAP_ARITH_OPERATORS=1` — causes ABC crash on large designs
- **NEVER** skip `clean_design` between PnR rounds — stale ORFS cache causes misleading results
- **NEVER** remove the three All-Mock variables (`SYNTH_MEMORY_MAX_BITS`, `SYNTH_MOCK_LARGE_MEMORIES`, `SYNTH_KEEP_MOCKED_MEMORIES`) — removing any one causes OOM or incorrect SRAM handling
- **NEVER** set `SYNTH_MEMORY_MAX_BITS` higher than 1 for large designs — defeats the purpose of All-Mock
- **NEVER** use `SYNTH_BLACKBOXES` + All-Mock simultaneously — they are conflicting approaches
- **ALWAYS** use `timeout_minutes=60` for the `synth` stage — All-Mock mock generation is slower
- **ALWAYS** use `timeout_minutes=180` for the `route` stage — detailed routing takes up to 3 hours for large designs
- **ALWAYS** set `SYNTH_HIERARCHICAL = 1` — preserves module boundaries for large designs
- **ALWAYS** start with conservative utilization (35-45%) for BOOM-class designs
- **ALWAYS** save round results via `compare_runs` before starting the next round
- **ALWAYS** use `compare_runs(action="recommend")` to select the best round objectively

## Input

$ARGUMENTS

A Chipyard config name (e.g., `smallboom`, `SmallBoomConfig`). Optional arguments:
- **Target frequency**: `50MHz` or `20ns` (AI will adaptively tune parameters to reach this target over multiple rounds)

## Output

Upon completion:
- GDS: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/<nickname>/base/6_final.gds`
- Netlist: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/<nickname>/base/6_final.v`
- SPEF: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/results/sky130hd/<nickname>/base/6_final.spef`
- Reports: `$PROJECT_ROOT/OpenROAD-flow-scripts/flow/reports/sky130hd/<nickname>/base/`
- Timing/area/DRC summary displayed in conversation
