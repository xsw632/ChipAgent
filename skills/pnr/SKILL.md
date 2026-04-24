---
name: pnr
description: "Run ORFS make flow on sky130hd for synthesis, place-and-route, and GDS export. Produces timing/power/area reports and GDS file."
disable-model-invocation: true
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

# chip-agent:pnr

Physical implementation pipeline: synthesize compiled Verilog through ORFS make flow on sky130hd, run all PnR stages, and produce a formatted PPA verification report.

## Usage

```
/chip-agent:pnr <ModuleName>
```

**Example:**

```
/chip-agent:pnr ALU8
```

## Instructions

**Determine the plugin root directory** by finding the nearest ancestor directory of this skill file that contains `.claude-plugin/plugin.json`. Use that directory as the base for all relative paths below.

## Pipeline

### Step 0 -- Verify Prerequisites

Set up variables:

```bash
PLUGIN_ROOT="<plugin-root>"
<<<<<<< HEAD
MODULE="$ARGUMENTS"   # first argument: bare module name (PascalCase)
=======
RAW_MODULE="$ARGUMENTS"   # first argument: module name (any case)
```

**Normalize the module name** so frontend and backend accept the same spelling. Rule (matches `/chip-agent:chipyard`): if the argument is all-lowercase, capitalize the first letter and append `Config`; otherwise take it as-is. If the resulting directory does not exist but a `<Name>Config` directory does, fall back to that.

```bash
if [ -z "$RAW_MODULE" ]; then
    echo "Usage: /chip-agent:pnr <ModuleName>"; exit 1
fi
if echo "$RAW_MODULE" | grep -qE '[A-Z]'; then
    MODULE="$RAW_MODULE"
else
    FIRST=$(echo "${RAW_MODULE:0:1}" | tr '[:lower:]' '[:upper:]')
    MODULE="${FIRST}${RAW_MODULE:1}Config"
fi
# Fallback: if normalized dir missing but bare-PascalCase Config variant exists, use it
if [ ! -d "$PLUGIN_ROOT/MyDesign/$MODULE" ] && [ -d "$PLUGIN_ROOT/MyDesign/${MODULE}Config" ]; then
    MODULE="${MODULE}Config"
fi
# Final fallback: case-insensitive directory match in MyDesign/ (handles e.g. tinyrocket -> TinyRocketConfig)
if [ ! -d "$PLUGIN_ROOT/MyDesign/$MODULE" ]; then
    MATCH=$(ls "$PLUGIN_ROOT/MyDesign" 2>/dev/null | grep -i "^${RAW_MODULE}\(Config\)\?$" | head -1)
    if [ -n "$MATCH" ]; then MODULE="$MATCH"; fi
fi
echo "Resolved module: $MODULE"
>>>>>>> main
```

Check that compiled Verilog exists:

```bash
test -f "$PLUGIN_ROOT/MyDesign/$MODULE/workspace/generated/$MODULE.v"
```

- If **missing**: STOP with clear message:
  ```
  No compiled Verilog found for <ModuleName>.
  Run `/chip-agent:workflow <description>` first.
  ```
<<<<<<< HEAD
- If **exists**: continue to Step 1.
=======
- If **exists**: continue.

**Chipyard detection:** Check if this is a Chipyard-generated design:

```bash
test -f "$PLUGIN_ROOT/MyDesign/$MODULE/workspace/generated/sram_mapping.json"
```

Also check spec.json:

```bash
grep -q '"source".*"chipyard"' "$PLUGIN_ROOT/MyDesign/$MODULE/workspace/spec.json" 2>/dev/null
```

If either condition is true, this is a Chipyard+SRAM design. **STOP and redirect:**

```
Chipyard+SRAM design detected for <ModuleName>.
This requires the specialized chipyard-pnr flow (nosram preprocessing, SRAM override generation, ABC exclusion, OOM management).

Run: /chip-agent:chipyard-pnr <ModuleName>
```

Do NOT proceed with the standard-cell-only PnR pipeline below. The Chipyard flow has critical pitfalls (ABC SIGABRT, module redefinition, OOM) that this skill does not handle.
>>>>>>> main

### Step 1 -- Check Environment

Call `mcp__chipagent-backend__check_environment` with no arguments.

Verify the response:
- `orfs.installed` must be `true`
- `sky130hd.installed` must be `true`

If either is `false`, STOP with message:
```
ORFS or sky130hd PDK not found.
Install OpenROAD-flow-scripts and ensure sky130hd platform is available.
See: https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts
```

Extract and save for subsequent steps:
- `ORFS_FLOW_PATH` = `orfs.flow_path`

### Step 2 -- Generate Config

1. Read `MyDesign/$MODULE/workspace/spec.json` if it exists. Extract:
   - `clock_port` (default: `"clock"` if absent)
   - `clock_period_ns` (default: `10` if absent)
<<<<<<< HEAD

2. Call `mcp__chipagent-backend__generate_config` with:
   - `module_name`: `$MODULE`
=======
   - `top_module` (default: use first module in Verilog if absent)
   - `source` (optional, used for informational purposes)

2. Call `mcp__chipagent-backend__generate_config` with:
   - `module_name`: `top_module` from spec.json (for Chipyard flows this will be `ChipTop`), or `$MODULE` if no `top_module` specified
>>>>>>> main
   - `verilog_path`: absolute path to `MyDesign/$MODULE/workspace/generated/$MODULE.v`
   - `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`
   - `clock_port`: from spec.json or `"clock"`
   - `clock_period_ns`: from spec.json or `10`

3. Extract and save for subsequent steps:
   - `CONFIG_MK` = `config_mk` from response
   - `DESIGN_NAME` = `design_name` from response

4. Initialize comparison state:
   - `comparison_round_count` = `// will be determined dynamically after synth in Step 3`
   - `max_retries_per_round` = `2`
   - `round_plans` =
     1. Round 1 baseline: `{ clock_period_ns: <from spec.json or 10>, core_utilization: 40 }`
   - `synth_cell_count` = `null` (populated after Round 1 synth completes)

### Step 2.5 -- Clear QoR History

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"clear"`
- `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`

This resets the QoR history for a fresh run. Each `/chip-agent:pnr` invocation starts with an empty history.

### Step 3 -- Run Comparison Rounds

**MANDATORY: All rounds must run to completion.** Do NOT skip remaining rounds even if an earlier round passes. Every round's result is needed for QoR comparison.

Stage ordering: `STAGE_ORDER = ["synth", "floorplan", "place", "cts", "route", "finish"]`

For each `round_plan` in `round_plans`:

1. Set:
   - `round` = current 1-based round number
   - `current_params` = snapshot of the round plan
   - `restart_from` = `"synth"`
   - `retry_attempt` = `1`
   - `round_complete` = `false`

2. Display a clear separator: `=== PnR Round {round}/{comparison_round_count} (restart from {restart_from}) ===`

3. Before the first attempt in the round, call `mcp__chipagent-backend__clean_design` with:
   - `config_mk_path`: latest `CONFIG_MK`
   - `orfs_flow_path`: `ORFS_FLOW_PATH`

4. Generate config for the round by calling `mcp__chipagent-backend__generate_config` with:
   - `module_name`: `$MODULE`
   - `verilog_path`: absolute path to `MyDesign/$MODULE/workspace/generated/$MODULE.v`
   - `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`
   - `clock_port`: from spec.json or `"clock"`
   - `clock_period_ns`: `current_params.clock_period_ns`
   - `core_utilization`: `current_params.core_utilization`
   - `place_density`: `current_params.place_density` (only if defined)
   - `gpl_timing_driven`: `current_params.gpl_timing_driven` (only if defined)
   - `gpl_routability_driven`: `current_params.gpl_routability_driven` (only if defined)

5. Update `CONFIG_MK` from the response.

6. While `retry_attempt <= max_retries_per_round` and `round_complete == false`:

   **6a. Run stages from `restart_from` through `finish`:**

   Determine the stages to run by slicing `STAGE_ORDER` from the index of `restart_from` to the end. For each stage in the slice:

   1. Call `mcp__chipagent-backend__run_stage` with:
      - `stage`: the current stage name
      - `config_mk_path`: `CONFIG_MK`
      - `orfs_flow_path`: `ORFS_FLOW_PATH`

   2. Call `mcp__chipagent-backend__get_report` with:
      - `design_name`: `DESIGN_NAME`
      - `stage`: the current stage name
      - `orfs_flow_path`: `ORFS_FLOW_PATH`

   3. Present per-stage metrics to the user immediately after each stage:

      | Stage | Metric Display |
      |-------|---------------|
      | synth | `Synthesis: <cell_count> cells, <synth_area> um^2` |
      | floorplan | `Floorplan: WNS=<wns>ns, TNS=<tns>ns` |
      | place | `Placement: WNS=<wns>ns, TNS=<tns>ns` |
      | cts | `CTS: WNS=<wns>ns, TNS=<tns>ns` |
      | route | `Routing: <violations> DRC violations` |
      | finish | `Finish: WNS=<wns>ns, TNS=<tns>ns, Power=<total_w * 1e6>uW, Area=<area>um^2` |

      **After synth get_report:** Capture `synth_cell_count` from the synth report's `cell_count` field. This is used for dynamic round expansion after Round 1.

   4. If `run_stage` returns `success === false`:
      - Record `failed_stage` = current stage name and `stderr` from response
      - Set `status` = `"fail"`
      - Stop running further stages for this attempt

   **6b. Determine pass/fail:**

   - If any `run_stage` returned `success === false`: `status = "fail"`
   - If all stages succeeded: check **finish** report `wns` and **route** report `violations`
     - `pass` = all stages succeed AND `wns >= 0` AND `violations == 0`
     - If not pass: `status = "fail"`
   - If pass: `status = "pass"`

   **6c. Collect metrics from reports:**

   Gather from available `get_report` responses:
   - From **finish**: `wns`, `tns`, `area`, `total_w` (as `total_power_w`)
   - From **route**: `violations` (as `drc_violations`)
   - From **synth**: `cell_count`

   Use partial metrics if a stage failed early. Set unavailable metrics to `null`.

   **6d. Save run to QoR history only when the round is finishing:**

   - If `status == "pass"`, save the passing round immediately.
   - If `retry_attempt == max_retries_per_round`, save the failing round.
   - Otherwise, defer saving until retries are exhausted.

   Use `mcp__chipagent-backend__compare_runs` with:
   - `action`: `"save"`
   - `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`
   - `run`:
     - `round`: current round number
     - `config`: `current_params`
     - `metrics`: `{ wns, tns, area, total_power_w, drc_violations, cell_count }`
     - `status`: `"pass"` or `"fail"`
     - `error_type`: the error type string if status is `"fail"`, omit if `"pass"`

   **6e. Finish or retry the round:**

   - If `status == "pass"`: Display `"Round {round}/{comparison_round_count} completed (PASSED). {comparison_round_count - round} rounds remaining."` and set `round_complete = true`.
   - If `retry_attempt == max_retries_per_round`: Display `"Round {round}/{comparison_round_count} completed (FAILED, retries exhausted). {comparison_round_count - round} rounds remaining."` and set `round_complete = true`.
   - Otherwise continue to diagnosis.

   **Dynamic round expansion (after Round 1):**

   After Round 1 finishes (pass or exhausts retries), if `round_plans` has only 1 entry, expand based on `synth_cell_count`:

   - Round 2: `{ clock_period_ns: max(1, <baseline clock> * 0.8), core_utilization: 40, gpl_timing_driven: true }`
   - Round 3: `{ clock_period_ns: max(1, <baseline clock> * 0.8), core_utilization: 35, gpl_timing_driven: true, gpl_routability_driven: true }`
   - If `synth_cell_count > 1000`:
     - Round 4: `{ clock_period_ns: max(1, <baseline clock> * 0.8), core_utilization: 35, place_density: 0.55, gpl_routability_driven: true }`
     - Round 5: `{ clock_period_ns: max(1, <baseline clock> * 0.7), core_utilization: 30, gpl_timing_driven: true }`

   Set `comparison_round_count` to the total number of rounds (3 or 5).

   **6f. Diagnose failure and prepare retry:**

   Call `mcp__chipagent-backend__diagnose_failure` with:
   - `stage`: `failed_stage` (or `"finish"` if all stages succeeded but timing/DRC failed)
   - `success`: `false` if stage failed, `true` if silent timing/DRC failure
   - `stderr`: stderr from failed stage (or empty string if silent failure)
   - `finish_report_content`: raw finish report text (if available)
   - `drc_report_content`: raw DRC report text (if available)
   - `sdc_content`: content of `MyDesign/$MODULE/workspace/pnr/constraint.sdc`
   - `current_clock_period_ns`: `current_params.clock_period_ns`
   - `current_place_density`: `current_params.place_density` (if set)
   - `current_core_utilization`: `current_params.core_utilization`

   **6g. Check severity:**

   If `severity == "critical"`:
   - Save the failing run to QoR history if it has not been saved yet
   - Display `"Critical error: {details}. Not fixable by parameter adjustment. Ending round {round}/{comparison_round_count}."`
   - Set `round_complete = true`

   **6h. Apply adjustments:**

   1. Merge `suggested_params` into `current_params`: overwrite matching keys, keep others unchanged.
   2. Display: `"Round {round} diagnosed: {error_type}. Adjusting: {list changed params with old -> new values}. Restarting from {restart_from}."`

   **6i. Clean and regenerate for retry:**

   1. Call `mcp__chipagent-backend__clean_design` with:
      - `config_mk_path`: `CONFIG_MK`
      - `orfs_flow_path`: `ORFS_FLOW_PATH`

   2. Call `mcp__chipagent-backend__generate_config` with:
      - `module_name`: `$MODULE`
      - `verilog_path`: absolute path to `MyDesign/$MODULE/workspace/generated/$MODULE.v`
      - `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`
      - `clock_port`: from spec.json or `"clock"`
      - `clock_period_ns`: `current_params.clock_period_ns`
      - `core_utilization`: `current_params.core_utilization`
      - `place_density`: `current_params.place_density` (only if defined)
      - `gpl_timing_driven`: `current_params.gpl_timing_driven` (only if defined)
      - `gpl_routability_driven`: `current_params.gpl_routability_driven` (only if defined)

   3. Update `CONFIG_MK` from the new response.
   4. Set `restart_from` = `diagnosis.restart_from`
   5. Increment `retry_attempt += 1`

### Step 4 -- QoR Comparison and Recommendation

**4a. Load all runs:**

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"load"`
- `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`

**4b. Display comparison table:**

Format the comparison table from all runs:

```
=== QoR Comparison: <ModuleName> ===

| Round | Clock (ns) | Utilization | Density | WNS (ns) | TNS (ns) | Area (um2) | Power (uW) | DRC | Status |
|-------|-----------|-------------|---------|----------|----------|------------|------------|-----|--------|
```

For each run in the history:
- `Clock (ns)` = `config.clock_period_ns`
- `Utilization` = `config.core_utilization` with `%` suffix
- `Density` = `config.place_density` or `"-"` if not set
- `WNS (ns)` = `metrics.wns` or `"N/A"` if unavailable
- `TNS (ns)` = `metrics.tns` or `"N/A"` if unavailable
- `Area (um2)` = `metrics.area` or `"N/A"` if unavailable
- `Power (uW)` = `metrics.total_power_w * 1e6` or `"N/A"` if unavailable
- `DRC` = `metrics.drc_violations` or `"N/A"` if unavailable
- `Status` = `"PASS"` or `"FAIL"`

**4c. Best-run recommendation:**

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"recommend"`
- `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`

- If a best run is returned: Display `"Recommendation: Round {N} (clock={X}ns, WNS={Y}ns, area={Z}um2, power={P}uW)"` where `{P}` = `best.metrics.total_power_w * 1e6` or `"N/A"` if unavailable
- If no best run: Display `"No passing run found. All rounds failed or had timing/DRC violations."`

### Step 5 -- Format PPA Report

**Only run this step if at least one passing round exists** (i.e., compare_runs recommend returned a best run).

Use the best run's metrics for the report.

Read the agent definition at `agents/pnr-report-formatter.md` (relative to plugin root) and follow the agent's rules to format a PPA summary report.

Pass the agent these data accumulated from the best run's get_report responses:
- From **synth** get_report: `cell_count`, `synth_area`
- From **finish** get_report: `wns`, `tns`, `total_w`, `internal_pct`, `switching_pct`, `leakage_pct`, `area`, `utilization`
- From **route** get_report: `violations`
- `clock_name` and `clock_period_ns` from Step 2 (spec.json or defaults)
- `design_name` from Step 2
- `orfs_flow_path` from Step 1

The agent formats and presents the PPA summary report directly in the conversation.

## Pipeline Stages

| # | Stage | Description |
|---|-------|-------------|
| 0 | Verify Prerequisites | Check compiled Verilog exists for module |
| 1 | Check Environment | Verify ORFS + sky130hd via MCP |
| 2 | Generate Config | Create config.mk + constraint.sdc and initialize comparison-round presets |
| 2.5 | Clear QoR History | Reset qor_history.json for fresh run |
| 3 | Run Comparison Rounds | Baseline + alternative parameter rounds, with retries inside each round |
| 4 | QoR Comparison | Display comparison table + best-run recommendation |
| 5 | Format Report | PPA summary via pnr-report-formatter agent (best passing run only) |

## Input

$ARGUMENTS

A module name (PascalCase, e.g., `ALU8`, `Counter8`). The module must already have compiled Verilog at `MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v`.

## Output

Upon pipeline completion, the following artifacts are produced:

- Netlist: `{orfs_flow_path}/results/sky130hd/{design_name}/base/1_2_yosys.v`
- GDS: `{orfs_flow_path}/results/sky130hd/{design_name}/base/6_1_merged.gds`
- ORFS reports: `{orfs_flow_path}/reports/sky130hd/{design_name}/base/`
- ORFS logs: `{orfs_flow_path}/logs/sky130hd/{design_name}/base/`
- Formatted PPA verification report (displayed in conversation)

## Anti-Patterns

- DO NOT call `scripts/synth.sh` or `scripts/pnr.sh` -- they are migration stubs that exit with error
- DO NOT read report files directly from ORFS report directories in the skill logic -- use `mcp__chipagent-backend__get_report`, which is responsible for resolving the correct ORFS/workspace artifact locations
- DO NOT skip per-stage metric display -- show metrics after EACH stage completes
- DO NOT manually run `make` commands -- use the MCP tools which handle ORFS make invocation
- DO NOT skip `clean_design` between retries -- ORFS caches all stages; without cleaning, even partial restarts reuse stale cached results
- DO NOT retry when severity is `"critical"` -- synthesis errors and combinational timing violations are not fixable by parameter adjustment
- DO NOT reset `current_params` to original values between rounds -- build on previous adjustments to avoid parameter drift
- DO NOT skip remaining rounds when an earlier round passes -- all results feed the QoR comparison table
