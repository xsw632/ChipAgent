# Phase 14: Config Generation + ORFS Stage Execution - Research

**Researched:** 2026-04-02
**Domain:** ORFS make flow integration, MCP tool implementation (TypeScript)
**Confidence:** HIGH

## Summary

Phase 14 adds three MCP tools to the existing `chipagent-backend` server: `generate_config` (config.mk + constraint.sdc), `run_stage` (execute ORFS make targets), and `get_report` (extract metrics from ORFS output). The MCP server scaffold from Phase 13 uses `@modelcontextprotocol/sdk` 1.29.0 with Zod validation and the register-function pattern (`registerCheckEnvironment` style).

ORFS uses a `DESIGN_CONFIG` variable pointing to a `config.mk` file. The Makefile produces outputs in `{WORK_HOME}/results/{PLATFORM}/{DESIGN_NICKNAME}/{FLOW_VARIANT}/`, logs in `logs/...`, and reports in `reports/...`. The six make targets are: `synth`, `floorplan`, `place`, `cts`, `route`, `finish`. Report files include `synth_stat.txt`, stage-numbered `.rpt` files, and `5_route_drc.rpt`.

**Primary recommendation:** Implement each tool as a separate file under `mcp-server/tools/`, following the existing `check-environment.ts` pattern. Config files go into `MyDesign/{Module}/workspace/pnr/`. Run make from ORFS `flow/` directory with `DESIGN_CONFIG` pointing to the generated config.mk.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MCP-03 | `generate_config` tool creating config.mk and constraint.sdc | Config.mk template from ORFS examples + existing generate_sdc.sh logic |
| CFG-01 | Auto-generate config.mk with correct ORFS variables | ORFS config.mk format verified from sky130hd/gcd/config.mk |
| CFG-02 | Auto-generate constraint.sdc with sky130hd timing defaults | Existing generate_sdc.sh has sequential/combinational detection; default 10ns per project decisions |
| MCP-04 | `run_stage` tool executing individual ORFS make targets | Make invocation with DESIGN_CONFIG env var, 6 targets verified in Makefile |
| MCP-05 | `get_report` tool extracting metrics from ORFS output | Report file locations and formats verified from existing ORFS run outputs |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @modelcontextprotocol/sdk | 1.29.0 | MCP server framework | Already in use from Phase 13 |
| zod | ^3.25 or ^4.0 | Input validation schemas | Already in package.json |
| node:child_process | built-in | Execute make commands | spawn/execSync for ORFS make |
| node:fs | built-in | Read report files, write config | File I/O for config generation and report parsing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| node:path | built-in | Path construction | Joining ORFS paths |

No new dependencies needed. Everything builds on Phase 13 foundation.

## Architecture Patterns

### Recommended Project Structure
```
mcp-server/
  index.ts                    # Server entry, registers all tools
  tools/
    check-environment.ts      # Phase 13 (existing)
    generate-config.ts        # Phase 14: MCP-03, CFG-01, CFG-02
    run-stage.ts              # Phase 14: MCP-04
    get-report.ts             # Phase 14: MCP-05
```

### Pattern 1: Tool Registration Pattern
**What:** Each tool exports a `registerXxx(server: McpServer)` function
**When to use:** All new tools
**Example:**
```typescript
// From check-environment.ts (verified, existing code)
export function registerGenerateConfig(server: McpServer): void {
  server.tool(
    "generate_config",
    "Generate ORFS config.mk and constraint.sdc for a ChipAgent module",
    {
      module_name: z.string().describe("PascalCase module name"),
      verilog_path: z.string().describe("Absolute path to compiled Verilog"),
      clock_port: z.string().optional().describe("Clock port name (omit for combinational)"),
      clock_period_ns: z.number().default(10).describe("Clock period in nanoseconds"),
      core_utilization: z.number().default(40).describe("Core utilization percentage"),
    },
    async (params) => { /* ... */ }
  );
}
```

### Pattern 2: Config.mk Template
**What:** Minimal config.mk matching ORFS expectations
**Example:**
```makefile
export DESIGN_NAME = ALU8
export PLATFORM    = sky130hd

export VERILOG_FILES = /absolute/path/to/ALU8.v
export SDC_FILE      = /absolute/path/to/constraint.sdc

export CORE_UTILIZATION = 40
export TNS_END_PERCENT = 100
```

Key points from ORFS sky130hd examples:
- `DESIGN_NAME` must match the Verilog module name (extracted from file, not filename)
- `VERILOG_FILES` can be absolute paths
- `SDC_FILE` can be absolute path
- `CORE_UTILIZATION` typically 40-45 for sky130hd
- `TNS_END_PERCENT = 100` is standard

### Pattern 3: SDC Generation (Sequential vs Combinational)
**What:** Detect `always @(posedge` in Verilog to determine module type
**Sequential SDC (10ns default for sky130hd):**
```sdc
current_design ALU8

set clk_name  core_clock
set clk_port  [get_ports clock]
set clk_period 10.0

create_clock -name $clk_name -period $clk_period $clk_port

set non_clock_inputs [all_inputs -no_clocks]
set_input_delay  [expr $clk_period * 0.2] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * 0.2] -clock $clk_name [all_outputs]
```

**Combinational SDC:**
```sdc
current_design ALU8

set clk_period 10.0

create_clock -name virtual_clk -period $clk_period

set_input_delay  0.0 -clock virtual_clk [all_inputs]
set_output_delay 0.0 -clock virtual_clk [all_outputs]
set_max_delay $clk_period -from [all_inputs] -to [all_outputs]
```

Note: Use `[all_inputs -no_clocks]` for sequential (matches ORFS gcd example), not `[all_inputs]` from old generate_sdc.sh.

### Pattern 4: Make Invocation
**What:** Run ORFS make targets from the flow directory
```typescript
import { spawn } from "node:child_process";

// Must run from ORFS flow/ directory
// DESIGN_CONFIG must point to the generated config.mk
const proc = spawn("make", [stage], {
  cwd: orfsFlowPath,
  env: { ...process.env, DESIGN_CONFIG: configMkPath },
  stdio: ["ignore", "pipe", "pipe"],
});
```

The 6 valid stages: `synth`, `floorplan`, `place`, `cts`, `route`, `finish`

### Pattern 5: ORFS Output Directory Structure
```
{ORFS_FLOW}/results/{PLATFORM}/{DESIGN_NICKNAME}/{FLOW_VARIANT}/
  1_synth.odb
  6_final.gds
{ORFS_FLOW}/logs/{PLATFORM}/{DESIGN_NICKNAME}/{FLOW_VARIANT}/
  1_2_yosys.log
  6_report.log
{ORFS_FLOW}/reports/{PLATFORM}/{DESIGN_NICKNAME}/{FLOW_VARIANT}/
  synth_stat.txt        # Cell count, wire count after synthesis
  2_floorplan_final.rpt # Floorplan metrics
  3_global_place.rpt    # Placement metrics
  3_detailed_place.rpt
  4_cts_final.rpt       # CTS metrics
  5_global_route.rpt    # Routing metrics
  5_route_drc.rpt       # DRC violations (empty = clean)
  6_finish.rpt          # Final timing (WNS, TNS, area)
```

Where `DESIGN_NICKNAME` defaults to `DESIGN_NAME`, `FLOW_VARIANT` defaults to `base`, `PLATFORM` is `sky130hd`.

### Anti-Patterns to Avoid
- **Running make from wrong directory:** Must `cwd` to ORFS `flow/` directory
- **Using relative paths in config.mk:** Use absolute paths for VERILOG_FILES and SDC_FILE since make runs from ORFS flow dir
- **Hardcoding ORFS path:** Must use check_environment result or detect dynamically (reuse `findOrfs()` logic)
- **Blocking the event loop:** Use `spawn` not `execSync` for potentially long-running make stages

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sequential/combinational detection | Custom AST parser | grep for `always @(posedge` | Chisel output is predictable; regex is sufficient |
| Module name extraction | Filename parsing | `grep -m1 '^module '` from Verilog | Filename may differ from actual module name |
| ORFS path resolution | New discovery logic | Reuse `findOrfs()` from check-environment.ts | Already implemented and tested |

## Common Pitfalls

### Pitfall 1: DESIGN_NICKNAME vs DESIGN_NAME
**What goes wrong:** ORFS uses DESIGN_NICKNAME for directory paths but DESIGN_NAME for the actual design. If not set, DESIGN_NICKNAME defaults to DESIGN_NAME.
**How to avoid:** Don't set DESIGN_NICKNAME in config.mk -- let it default. Output dirs will be at `results/sky130hd/{DESIGN_NAME}/base/`.

### Pitfall 2: Make targets are incremental
**What goes wrong:** Running `make synth` twice skips synthesis if outputs exist. Running `make place` before `make floorplan` fails.
**How to avoid:** The `run_stage` tool should document that stages must run in order. Consider adding `make clean_{stage}` before re-runs if needed. For now, let the skill (Phase 15) manage ordering.

### Pitfall 3: Long-running make stages
**What goes wrong:** Synthesis and routing can take minutes. Using `execSync` blocks the MCP server.
**How to avoid:** Use `child_process.spawn` with stream capture. Collect stdout/stderr incrementally. Set reasonable timeouts (10 min per stage).

### Pitfall 4: Report file timing
**What goes wrong:** Reports only exist after their corresponding stage completes. Querying reports before stage runs returns file-not-found.
**How to avoid:** `get_report` should return clear error when report files don't exist yet, indicating which stage needs to run first.

### Pitfall 5: Clock port naming in Chisel
**What goes wrong:** Chisel's default clock port is named `clock` in generated Verilog (not `clk`).
**How to avoid:** Default clock port to `clock` in the SDC template. Allow override via tool parameter.

## Code Examples

### Report Parsing: 6_finish.rpt
The finish report has a predictable format with labeled sections:
```
==========================================================================
finish report_tns
--------------------------------------------------------------------------
tns max -0.62

==========================================================================
finish report_wns
--------------------------------------------------------------------------
wns max -0.05
```

Parse with regex:
```typescript
function parseFinishReport(content: string): Record<string, string> {
  const metrics: Record<string, string> = {};
  const tnsMatch = content.match(/report_tns\n-+\ntns max ([\d.-]+)/);
  if (tnsMatch) metrics.tns = tnsMatch[1];
  const wnsMatch = content.match(/report_wns\n-+\nwns max ([\d.-]+)/);
  if (wnsMatch) metrics.wns = wnsMatch[1];
  return metrics;
}
```

### Report Parsing: synth_stat.txt
```
   Number of cells:                503
```
Parse cell count: `content.match(/Number of cells:\s+(\d+)/)`

### Report Parsing: 6_report.log (area)
First line: `Design area 912 um^2 79% utilization.`
Parse: `content.match(/Design area (\d+) um\^2 (\d+)% utilization/)`

### Report Parsing: 5_route_drc.rpt
Empty file = 0 DRC violations. Non-empty = count lines matching violation patterns.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| synth.sh + pnr.sh (Tcl scripts) | ORFS make flow | Phase 13 (v1.1.5) | Scripts are now stubs; all flow via ORFS make |
| nangate45 PDK, 2ns clock | sky130hd PDK, 10ns clock | Phase 13 (v1.1.5) | Different timing defaults, different report formats |
| Direct bash from skill | MCP tools | Phase 13+ (v1.1.5) | Skill calls MCP tools instead of scripts |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in test runner (node --test) |
| Config file | none -- see Wave 0 |
| Quick run command | `node --test mcp-server/tests/*.test.ts` |
| Full suite command | `node --test mcp-server/tests/*.test.ts` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MCP-03 | generate_config produces valid config.mk + constraint.sdc | unit | `node --test mcp-server/tests/generate-config.test.ts` | No -- Wave 0 |
| CFG-01 | config.mk has correct ORFS variables | unit | (same as MCP-03) | No -- Wave 0 |
| CFG-02 | constraint.sdc correct for sequential/combinational | unit | (same as MCP-03) | No -- Wave 0 |
| MCP-04 | run_stage executes make targets, returns status | integration | `node --test mcp-server/tests/run-stage.test.ts` | No -- Wave 0 |
| MCP-05 | get_report extracts metrics as JSON | unit | `node --test mcp-server/tests/get-report.test.ts` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `node --test mcp-server/tests/*.test.ts`
- **Per wave merge:** Full suite
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `mcp-server/tests/generate-config.test.ts` -- covers MCP-03, CFG-01, CFG-02
- [ ] `mcp-server/tests/run-stage.test.ts` -- covers MCP-04
- [ ] `mcp-server/tests/get-report.test.ts` -- covers MCP-05
- [ ] Test fixtures: sample Verilog files (sequential + combinational), sample ORFS report files

## Open Questions

1. **ORFS WORK_HOME location**
   - What we know: ORFS defaults to `WORK_HOME=.` (inside flow/ dir), so results go to `flow/results/...`
   - What's unclear: Should we override WORK_HOME to put outputs in the module's workspace?
   - Recommendation: Keep default (ORFS flow dir). Copy/reference results from there. Overriding WORK_HOME may break internal Makefile paths.

2. **Concurrent module builds**
   - What we know: ORFS output dirs include design name, so different modules don't collide
   - What's unclear: Whether parallel make invocations are safe
   - Recommendation: For Phase 14, single execution is fine. Concurrency is out of scope.

## Sources

### Primary (HIGH confidence)
- ORFS Makefile at `~/OpenROAD-flow-scripts/flow/Makefile` -- make targets, variable definitions
- ORFS `scripts/variables.mk` -- RESULTS_DIR, LOG_DIR, REPORTS_DIR path patterns
- ORFS `designs/sky130hd/gcd/config.mk` -- minimal config.mk example
- ORFS `designs/sky130hd/gcd/constraint.sdc` -- SDC format reference
- Existing `mcp-server/tools/check-environment.ts` -- tool registration pattern
- Existing `scripts/generate_sdc.sh` -- sequential/combinational detection logic
- Existing ORFS run outputs at `reports/nangate45/gcd/base/` -- report file formats

### Secondary (MEDIUM confidence)
- ORFS `designs/sky130hd/ibex/config.mk` -- more complex config example

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- using existing dependencies, no new libraries
- Architecture: HIGH -- follows established Phase 13 patterns, verified against ORFS Makefile
- Pitfalls: HIGH -- verified from actual ORFS output files and Makefile analysis

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable ORFS flow, unlikely to change)
