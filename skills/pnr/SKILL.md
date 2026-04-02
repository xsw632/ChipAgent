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
MODULE="$ARGUMENTS"   # first argument: bare module name (PascalCase)
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
- If **exists**: continue to Step 1.

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

2. Call `mcp__chipagent-backend__generate_config` with:
   - `module_name`: `$MODULE`
   - `verilog_path`: absolute path to `MyDesign/$MODULE/workspace/generated/$MODULE.v`
   - `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`
   - `clock_port`: from spec.json or `"clock"`
   - `clock_period_ns`: from spec.json or `10`

3. Extract and save for subsequent steps:
   - `CONFIG_MK` = `config_mk` from response
   - `DESIGN_NAME` = `design_name` from response

4. Initialize tracking state for retry loop:
   - `current_params` = `{ clock_period_ns: <from spec.json or 10>, core_utilization: 40 }`
   - `restart_from` = `"synth"`
   - `round` = `1`
   - `max_rounds` = `3`

### Step 2.5 -- Clear QoR History

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"clear"`
- `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`

This resets the QoR history for a fresh run. Each `/chip-agent:pnr` invocation starts with an empty history.

### Step 3 -- Run Stages with Retry

Stage ordering: `STAGE_ORDER = ["synth", "floorplan", "place", "cts", "route", "finish"]`

**Retry Loop -- While `round <= max_rounds`:**

Display a clear separator: `=== PnR Round {round}/{max_rounds} (restart from {restart_from}) ===`

**3a. Run stages from `restart_from` through `finish`:**

Determine the stages to run by slicing `STAGE_ORDER` from the index of `restart_from` to the end. For each stage in the slice:

1. Call `mcp__chipagent-backend__run_stage` with:
   - `stage`: the current stage name
   - `config_mk_path`: `CONFIG_MK` (from Step 2)
   - `orfs_flow_path`: `ORFS_FLOW_PATH` (from Step 1)

2. Call `mcp__chipagent-backend__get_report` with:
   - `design_name`: `DESIGN_NAME` (from Step 2)
   - `stage`: the current stage name
   - `orfs_flow_path`: `ORFS_FLOW_PATH` (from Step 1)

3. Present per-stage metrics to the user immediately after each stage:

   | Stage | Metric Display |
   |-------|---------------|
   | synth | `Synthesis: <cell_count> cells, <synth_area> um^2` |
   | floorplan | `Floorplan: WNS=<wns>ns, TNS=<tns>ns` |
   | place | `Placement: WNS=<wns>ns, TNS=<tns>ns` |
   | cts | `CTS: WNS=<wns>ns, TNS=<tns>ns` |
   | route | `Routing: <violations> DRC violations` |
   | finish | `Finish: WNS=<wns>ns, TNS=<tns>ns, Power=<total_w * 1e6>uW, Area=<area>um^2` |

4. If `run_stage` returns `success === false`:
   - Record `failed_stage` = current stage name and `stderr` from response
   - Set `status` = `"fail"`
   - Stop running further stages for this round (break inner loop)

**3b. Determine pass/fail:**

- If any `run_stage` returned `success === false`: `status = "fail"`
- If all stages succeeded: check **finish** report `wns` and **route** report `violations`
  - `pass` = all stages succeed AND `wns >= 0` AND `violations == 0`
  - If not pass: `status = "fail"` (silent timing or DRC failure)
- If pass: `status = "pass"`

**3c. Collect metrics from reports:**

Gather from available `get_report` responses:
- From **finish**: `wns`, `tns`, `area`, `total_w` (as `total_power_w`)
- From **route**: `violations` (as `drc_violations`)
- From **synth**: `cell_count`

Use partial metrics if a stage failed early (earlier stage metrics are still valid). Set unavailable metrics to `null`.

**3d. Save run to QoR history:**

Call `mcp__chipagent-backend__compare_runs` with:
- `action`: `"save"`
- `workspace_dir`: absolute path to `MyDesign/$MODULE/workspace`
- `run`:
  - `round`: current round number
  - `config`: `current_params` (snapshot of `{ clock_period_ns, core_utilization, place_density, ... }`)
  - `metrics`: `{ wns, tns, area, total_power_w, drc_violations, cell_count }` (use `null` for unavailable)
  - `status`: `"pass"` or `"fail"`
  - `error_type`: the error type string if status is "fail", omit if "pass"

**3e. Check exit conditions:**

- If `status == "pass"`: Display "Round {round} PASSED. Design meets timing and DRC targets." Break the retry loop.
- If `round == max_rounds`: Display "Max retries exhausted ({max_rounds} rounds). Proceeding to QoR comparison." Break the retry loop.

**3f. Diagnose failure and prepare retry:**

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

**3g. Check severity:**

If `severity == "critical"`: Display "Critical error: {details}. Not fixable by parameter adjustment. Aborting retry." Break the retry loop.

**3h. Apply adjustments:**

1. Merge `suggested_params` into `current_params`: overwrite matching keys, keep others unchanged.
2. Display: `"Round {round} diagnosed: {error_type}. Adjusting: {list changed params with old -> new values}. Restarting from {restart_from}."`

**3i. Clean and regenerate:**

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

**3j. Prepare next round:**

1. Set `restart_from` = `diagnosis.restart_from`
2. Increment `round += 1`
3. Continue retry loop.

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

- If a best run is returned: Display `"Recommendation: Round {N} (clock={X}ns, WNS={Y}ns, area={Z}um2)"`
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
| 2 | Generate Config | Create config.mk + constraint.sdc via MCP; initialize retry state |
| 2.5 | Clear QoR History | Reset qor_history.json for fresh run |
| 3 | Run Stages with Retry | Up to 3 rounds: run stages -> diagnose -> clean -> adjust -> re-run |
| 4 | QoR Comparison | Display comparison table + best-run recommendation |
| 5 | Format Report | PPA summary via pnr-report-formatter agent (best passing run only) |

## Input

$ARGUMENTS

A module name (PascalCase, e.g., `ALU8`, `Counter8`). The module must already have compiled Verilog at `MyDesign/<ModuleName>/workspace/generated/<ModuleName>.v`.

## Output

Upon pipeline completion, the following artifacts are produced at ORFS paths (reported by get_report):

- Netlist: `{orfs_flow_path}/results/sky130hd/{design_name}/base/1_2_yosys.v`
- GDS: `{orfs_flow_path}/results/sky130hd/{design_name}/base/6_1_merged.gds`
- Reports: `{orfs_flow_path}/reports/sky130hd/{design_name}/base/`
- Formatted PPA verification report (displayed in conversation)

## Anti-Patterns

- DO NOT call `scripts/synth.sh` or `scripts/pnr.sh` -- they are migration stubs that exit with error
- DO NOT read report files directly from `MyDesign/$MODULE/workspace/pnr/reports/` -- use `mcp__chipagent-backend__get_report` which reads from ORFS paths
- DO NOT skip per-stage metric display -- show metrics after EACH stage completes
- DO NOT manually run `make` commands -- use the MCP tools which handle ORFS make invocation
- DO NOT skip `clean_design` between retries -- ORFS caches all stages; without cleaning, even partial restarts reuse stale cached results
- DO NOT retry when severity is `"critical"` -- synthesis errors and combinational timing violations are not fixable by parameter adjustment
- DO NOT reset `current_params` to original values between rounds -- build on previous adjustments to avoid parameter drift
