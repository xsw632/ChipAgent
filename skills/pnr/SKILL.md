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

### Step 3 -- Run All 6 Stages Sequentially

For each stage in order: **synth**, **floorplan**, **place**, **cts**, **route**, **finish**:

1. Call `mcp__chipagent-backend__run_stage` with:
   - `stage`: the current stage name
   - `config_mk_path`: `CONFIG_MK` (from Step 2)
   - `orfs_flow_path`: `ORFS_FLOW_PATH` (from Step 1)

2. Check the response:
   - If `success === false`: STOP with error:
     ```
     <STAGE_NAME> FAILED.
     Error: <last 20 lines of stderr>
     ```

3. Call `mcp__chipagent-backend__get_report` with:
   - `design_name`: `DESIGN_NAME` (from Step 2)
   - `stage`: the current stage name
   - `orfs_flow_path`: `ORFS_FLOW_PATH` (from Step 1)

4. Present per-stage metrics to the user immediately after each stage:

   | Stage | Metric Display |
   |-------|---------------|
   | synth | `Synthesis: <cell_count> cells, <synth_area> um^2` |
   | floorplan | `Floorplan: WNS=<wns>ns, TNS=<tns>ns` |
   | place | `Placement: WNS=<wns>ns, TNS=<tns>ns` |
   | cts | `CTS: WNS=<wns>ns, TNS=<tns>ns` |
   | route | `Routing: <violations> DRC violations` |
   | finish | `Finish: WNS=<wns>ns, TNS=<tns>ns, Power=<total_w * 1e6>uW, Area=<area>um^2` |

5. Save the `get_report` response metrics for use in Step 4.

### Step 4 -- Format PPA Report

Read the agent definition at `agents/pnr-report-formatter.md` (relative to plugin root) and follow the agent's rules to format a PPA summary report.

Pass the agent these data accumulated from Step 3 get_report responses:
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
| 2 | Generate Config | Create config.mk + constraint.sdc via MCP |
| 3 | Run 6 Stages | synth -> floorplan -> place -> cts -> route -> finish via MCP |
| 4 | Format Report | PPA summary via pnr-report-formatter agent |

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
