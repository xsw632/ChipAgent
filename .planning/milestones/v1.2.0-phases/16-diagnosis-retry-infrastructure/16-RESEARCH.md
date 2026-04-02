# Phase 16: Diagnosis & Retry Infrastructure - Research

**Researched:** 2026-04-02
**Domain:** MCP Server tool extension -- error classification, design cleanup, config tuning, failure diagnosis for ORFS-based PnR pipeline
**Confidence:** HIGH

## Summary

Phase 16 adds the MCP tool infrastructure that enables intelligent failure diagnosis and parameter retry for the PnR pipeline. Specifically, this phase delivers two new MCP tools (`diagnose_failure`, `clean_design`) and extends one existing tool (`generate_config`) -- all within the existing TypeScript MCP server. No new dependencies are required. The existing patterns from `run-stage.ts`, `get-report.ts`, and `generate-config.ts` directly apply to all new work.

The most critical technical insight is that ORFS timing violations are silent successes: all 6 stages complete with exit code 0, but WNS < 0 in the finish report. The `diagnose_failure` tool must handle two distinct paths: (1) stage failure via non-zero exit code with stderr analysis, and (2) successful completion with post-finish WNS check. Both must return the same structured JSON with error classification and suggested parameter adjustments.

The second critical insight is that ORFS make caches results by file timestamp, not by config content. Changing `PLACE_DENSITY` in config.mk does NOT automatically invalidate cached placement results. The `clean_design` tool (wrapping `make clean_all`) is a non-negotiable prerequisite for any retry logic -- without it, retries silently reuse stale results and the QoR comparison table shows identical metrics labeled as different configurations.

**Primary recommendation:** Implement `diagnose_failure` and `clean_design` as new tool files in `mcp-server/tools/`, extend `generate_config` with optional tuning parameters, and write comprehensive unit tests using `node:test` following existing patterns. Keep all tools stateless and deterministic.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DIAG-01 | Agent auto-classifies flow failures into error types (timing_violation, congestion, drc, placement_overflow, synthesis_error) from ORFS logs, reports, and stderr | `diagnose_failure` tool with regex-based pattern matching on stderr + finish report WNS/DRC metrics. Classification patterns documented in Code Examples section. |
| DIAG-02 | Agent detects "silent" timing violations where all stages succeed but WNS < 0 in finish report | `diagnose_failure` tool accepts finish report metrics as input; when all stages succeed but WNS < 0, classifies as `timing_violation`. Two detection paths documented in Architecture section. |
| DIAG-03 | New `clean_design` MCP tool runs `make clean_all` to reset ORFS cached artifacts before retry | `clean_design` tool wraps `make clean_all DESIGN_CONFIG=<path>` in ORFS flow directory. Uses same spawn pattern as existing `run_stage`. Verified clean targets from ORFS Makefile. |
| DIAG-04 | Existing `generate_config` MCP tool extended with optional tuning parameters (place_density, gpl_timing_driven, gpl_routability_driven) | Add optional zod parameters to existing tool. New params conditionally append `export VARIABLE = value` lines to config.mk. Backward-compatible -- existing callers unaffected. |
| RETRY-01 | New `diagnose_failure` MCP tool parses ORFS output and returns structured error classification with suggested parameter adjustments | Tool returns JSON with `error_type`, `severity`, `details`, `suggested_params` (computed adjustments), and `restart_from` (stage-aware restart point). Error-to-parameter mapping documented in Architecture section. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @modelcontextprotocol/sdk | 1.29.0 | MCP server framework | Already in use; all tools register via `McpServer.tool()` |
| zod | ^3.25 | Input validation + schemas | Already in use; all tool params validated via zod schemas |
| Node.js built-ins (fs, path, child_process) | Node 22+ | File I/O, process spawning | Already in use; no additional packages needed |
| node:test + node:assert/strict | Node 22+ | Unit testing | Already in use; 26 existing tests pass with `node --test` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| TypeScript | 5.x | Type checking (noEmit) | Already configured via tsconfig.json |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Regex log parsing | ORFS metadata.json | metadata.json has comprehensive metrics in METRICS2.1 format, but format is complex with hierarchical keys like `finish__timing__setup__ws`. Regex on known log patterns is simpler and sufficient for the 5 error types needed. metadata.json can be a future enhancement. |
| Separate `suggest_parameters` tool | Inline logic in `diagnose_failure` | Separate tool was considered in milestone research but adds an extra MCP round-trip. Since parameter suggestions are deterministic from error type + current config, embedding them in `diagnose_failure` output reduces tool calls from 2 to 1 per diagnosis. |
| `make clean_all` via `run_stage` | Dedicated `clean_design` tool | Could add "clean_all" to VALID_STAGES in run_stage, but clean is semantically different from running a flow stage. Separate tool keeps interfaces clear. |

**Installation:**
```bash
# No new packages needed. Existing setup is sufficient:
cd mcp-server && npm install
```

## Architecture Patterns

### Recommended Project Structure
```
mcp-server/
  tools/
    check-environment.ts     # existing
    generate-config.ts       # MODIFY: add optional tuning params
    run-stage.ts             # existing, unchanged
    get-report.ts            # existing, unchanged
    diagnose-failure.ts      # NEW: error classification
    clean-design.ts          # NEW: ORFS clean wrapper
  tests/
    generate-config.test.ts  # existing + ADD new tests for tuning params
    get-report.test.ts       # existing, unchanged
    run-stage.test.ts        # existing, unchanged
    diagnose-failure.test.ts # NEW: error classification tests
    clean-design.test.ts     # NEW: clean tool tests
  index.ts                   # MODIFY: register 2 new tools
  package.json               # unchanged
  tsconfig.json              # unchanged
```

### Pattern 1: MCP Tool Registration (existing pattern to follow)
**What:** Each tool lives in its own file, exports a `registerXxx(server: McpServer)` function, uses zod for input validation.
**When to use:** Every new MCP tool.
**Example:**
```typescript
// Source: mcp-server/tools/check-environment.ts (existing pattern)
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export function registerCleanDesign(server: McpServer): void {
  server.tool(
    "clean_design",
    "Reset ORFS cached artifacts for a design via make clean_all",
    {
      config_mk_path: z.string().describe("Absolute path to config.mk"),
      orfs_flow_path: z.string().describe("Absolute path to ORFS flow/ directory"),
    },
    async (params): Promise<{ content: Array<{ type: "text"; text: string }> }> => {
      // implementation
      return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
    },
  );
}
```

### Pattern 2: Process Spawning (from run-stage.ts)
**What:** Spawn `make` subprocess with DESIGN_CONFIG env var, collect stdout/stderr, handle timeout.
**When to use:** `clean_design` tool implementation.
**Example:**
```typescript
// Source: mcp-server/tools/run-stage.ts lines 59-91
const proc = spawn("make", ["clean_all"], {
  cwd: orfsFlowPath,
  env: { ...process.env, DESIGN_CONFIG: configMkPath },
  stdio: ["ignore", "pipe", "pipe"],
});
```

### Pattern 3: Report Parsing (from get-report.ts)
**What:** Regex-based extraction of structured metrics from ORFS text output.
**When to use:** `diagnose_failure` when parsing stderr and finish report.
**Example:**
```typescript
// Source: mcp-server/tools/get-report.ts lines 6-12
export function parseFinishReport(content: string): Record<string, string> {
  const metrics: Record<string, string> = {};
  const wnsMatch = content.match(/report_wns\n-+\nwns max ([\d.-]+)/);
  if (wnsMatch) metrics.wns = wnsMatch[1];
  return metrics;
}
```

### Pattern 4: Conditional Config Lines (for generate_config extension)
**What:** Only append config.mk lines when optional parameters are provided.
**When to use:** Extending `generateConfigMk()` with tuning parameters.
**Example:**
```typescript
// Extension to existing generateConfigMk in generate-config.ts
function generateConfigMk(params: ConfigMkParams): string {
  const lines = [
    `export DESIGN_NAME = ${designName}`,
    `export PLATFORM = sky130hd`,
    `export VERILOG_FILES = ${params.verilogAbsPath}`,
    `export SDC_FILE = ${params.sdcAbsPath}`,
    `export CORE_UTILIZATION = ${params.coreUtilization}`,
    `export TNS_END_PERCENT = 100`,
  ];
  // Only append when explicitly provided (backward compatible)
  if (params.placeDensity !== undefined) {
    lines.push(`export PLACE_DENSITY = ${params.placeDensity}`);
  }
  if (params.gplTimingDriven !== undefined) {
    lines.push(`export GPL_TIMING_DRIVEN = ${params.gplTimingDriven ? 1 : 0}`);
  }
  if (params.gplRoutabilityDriven !== undefined) {
    lines.push(`export GPL_ROUTABILITY_DRIVEN = ${params.gplRoutabilityDriven ? 1 : 0}`);
  }
  return lines.join("\n") + "\n";
}
```

### Pattern 5: diagnose_failure Two-Path Detection
**What:** Error classification has two entry paths that produce the same output structure.
**When to use:** The core `diagnose_failure` tool logic.
```
Path A: Stage failure (run_stage returned success=false)
  Input: stage name + stderr from failed run_stage
  Parse stderr for error patterns
  Return error_type + suggested_params + restart_from

Path B: Silent timing violation (all stages succeeded)
  Input: stage="finish" + finish report metrics (WNS, DRC count)
  Check WNS < 0 or DRC > 0
  Return error_type + suggested_params + restart_from
```

### Anti-Patterns to Avoid
- **Putting retry logic in MCP tools:** MCP tools must be stateless single-purpose operations. The retry loop belongs in the Skill layer (Phase 17). This phase only provides the infrastructure tools.
- **Parsing raw ORFS logs in the Skill (LLM):** ORFS logs are 5K-50K lines. Sending them to Claude wastes tokens and produces inconsistent classification. The `diagnose_failure` tool does regex parsing and returns structured JSON.
- **Manually editing config.mk with sed/Edit:** Partial edits risk config.mk/SDC inconsistency (changing clock in config.mk but not in SDC). Always regenerate via `generate_config` tool which writes both files atomically.
- **Using intermediate stage WNS for diagnosis:** Only finish-stage WNS is reliable for timing violation diagnosis. Intermediate WNS (floorplan, place, CTS) is pessimistic because timing repair has not completed. Exception: if routing fails with non-zero exit code, use route-stage data since finish is unavailable.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ORFS cache invalidation | Custom file timestamp tracking | `make clean_all` via `clean_design` tool | ORFS Makefile owns the dependency graph; trying to selectively invalidate is fragile and error-prone |
| Config.mk + SDC regeneration | Manual file editing with `sed` or `Edit` | `generate_config` tool (extended) | Tool generates both files atomically, ensuring clock period consistency between config.mk and SDC |
| Error pattern matching | LLM interpretation of raw logs | `diagnose_failure` tool with tested regex | Deterministic, testable, no token waste; LLM interpretation varies across invocations |
| Parameter adjustment computation | LLM arithmetic on current values | `diagnose_failure` suggested_params | Deterministic computation with bounds checking; LLM arithmetic is unreliable |

**Key insight:** Every piece of deterministic logic (parsing, classification, adjustment computation, file generation) belongs in the MCP tool layer where it can be unit tested. The Skill layer only makes decisions about whether to retry and which tool to call.

## Common Pitfalls

### Pitfall 1: ORFS Make Caches Stale Results (CRITICAL)
**What goes wrong:** Changing config.mk parameters and re-running `make <stage>` does NOT re-execute the stage if cached output files are newer than the Makefile target prerequisites. The retry silently reuses old results.
**Why it happens:** ORFS Make tracks file timestamps, not config.mk content. Editing config.mk does not change timestamps of intermediate `.odb` files.
**How to avoid:** Run `make clean_all DESIGN_CONFIG=<path>` via `clean_design` tool before EVERY retry iteration. This is non-negotiable.
**Warning signs:** Retry completes in <1 second (real runs take minutes). Report metrics are byte-identical across iterations.

### Pitfall 2: Config.mk/SDC Inconsistency on Clock Period Change
**What goes wrong:** When retrying with different `clock_period_ns`, both config.mk and constraint.sdc must be regenerated. A naive approach might only edit config.mk, leaving the SDC with the old period. ORFS reads clock from SDC, not from a config.mk variable.
**Why it happens:** The clock constraint is in the SDC file (`create_clock -period <ns>`). config.mk only points to the SDC file path.
**How to avoid:** Always call `generate_config` tool with the new clock period -- it regenerates BOTH files atomically. Never manually edit either file.
**Warning signs:** Timing report shows a different clock period than the retry intended. SDC file has an older timestamp than config.mk.

### Pitfall 3: Parameter Range Violations Crash OpenROAD
**What goes wrong:** PLACE_DENSITY outside [0.3, 0.85] causes placement to either fail instantly or run until timeout. CORE_UTILIZATION below 20 or above 70 produces bad results on sky130hd.
**Why it happens:** OpenROAD has hard limits but does not always report them clearly (sometimes segfaults).
**How to avoid:** Validate and clamp parameter ranges in `generate_config` and/or in `diagnose_failure` suggested_params computation. Defined bounds: PLACE_DENSITY [0.30, 0.85], CORE_UTILIZATION [20, 70], CLOCK_PERIOD [1.0, 100.0].
**Warning signs:** OpenROAD segfault during placement. Placement takes >10 minutes (timeout).

### Pitfall 4: Confusing Congestion with DRC
**What goes wrong:** Routing congestion and DRC violations are related but require different fixes. Treating all routing failures as DRC (reduce density slightly) when the root cause is congestion (needs more aggressive density/utilization reduction) wastes retry attempts.
**Why it happens:** Both manifest as routing-stage problems, but congestion causes global route overflow while DRC is about local spacing violations.
**How to avoid:** Check stderr for congestion keywords (`overflow`, `GRT-0119`, `Routing congestion too high`) separately from DRC count in route report. Apply different parameter adjustments.
**Warning signs:** DRC count > 0 with "short" violation types suggests congestion, not local spacing.

### Pitfall 5: Combinational Module "Timing Violation" Is Not Clock-Fixable
**What goes wrong:** Combinational modules use a virtual clock. A WNS < 0 means the combinational path delay exceeds the virtual period. Relaxing the virtual clock just hides the issue rather than fixing it.
**Why it happens:** The retry logic treats all timing violations the same, but virtual clock timing is fundamentally different.
**How to avoid:** `diagnose_failure` must detect sequential vs combinational (from SDC content or from `isSequential()` check on Verilog) and return different severity: `recoverable` for sequential (can relax real clock), `critical` for combinational (needs RTL change, not parameter-fixable).
**Warning signs:** `constraint.sdc` contains `create_clock -name virtual_clk` instead of `[get_ports ...]`.

## Code Examples

Verified patterns for implementation.

### diagnose_failure: Error Classification Logic
```typescript
// Error type classification priority order (most specific first)
interface DiagnosisResult {
  readonly error_type: "timing_violation" | "congestion" | "drc" |
                       "placement_overflow" | "synthesis_error" | "unknown";
  readonly severity: "critical" | "recoverable";
  readonly details: string;
  readonly suggested_params: {
    readonly clock_period_ns?: number;
    readonly place_density?: number;
    readonly core_utilization?: number;
  };
  readonly restart_from: "synth" | "floorplan" | "place" | "cts" | "route" | "finish";
}

// Classification patterns (applied in order):
// 1. Synthesis error: stage="synth" + success=false -> synthesis_error, severity=critical
// 2. Placement overflow: stderr matches /placement overflow|not enough sites|Cannot place/i
//    -> placement_overflow, suggested: core_utilization -= 15
// 3. Congestion: stderr matches /GRT-0119|Routing congestion too high|overflow/i
//    -> congestion, suggested: place_density -= 0.1
// 4. DRC: route report violations > 0 -> drc, suggested: place_density -= 0.05
// 5. Timing violation: finish WNS < 0 -> timing_violation, suggested: clock_period_ns *= 1.5
// 6. Unknown: none matched -> unknown, severity=critical

function classifySynthesisError(stderr: string): boolean {
  return /ERROR|FATAL|Synthesis failed/i.test(stderr);
}

function classifyPlacementOverflow(stderr: string): boolean {
  return /placement overflow|not enough sites|Cannot place|density overflow/i.test(stderr);
}

function classifyCongestion(stderr: string): boolean {
  return /GRT-0119|Routing congestion too high|Total overflow:\s*[1-9]/i.test(stderr);
}
```

### clean_design: Process Spawn Pattern
```typescript
// Source: follows run-stage.ts spawn pattern
// Runs: make clean_all DESIGN_CONFIG=<path>
export function buildCleanArgs(
  configMkPath: string,
  orfsFlowPath: string,
): { args: string[]; cwd: string; env: Record<string, string | undefined> } {
  return {
    args: ["clean_all"],
    cwd: orfsFlowPath,
    env: { ...process.env, DESIGN_CONFIG: configMkPath },
  };
}
```

### generate_config Extension: Tuning Parameters
```typescript
// Source: extends existing generate-config.ts
// New optional zod parameters (backward compatible):
{
  // ... all existing params unchanged ...
  place_density: z.number().min(0.2).max(0.95).optional()
    .describe("Placement density override (0.0-1.0)"),
  gpl_timing_driven: z.boolean().optional()
    .describe("Enable timing-driven placement"),
  gpl_routability_driven: z.boolean().optional()
    .describe("Enable routability-driven placement"),
}
```

### ORFS Error Patterns (from logs and stderr)

| Error Type | Pattern Source | Regex | Confidence |
|------------|--------------|-------|------------|
| Synthesis failure | synth stderr | `/ERROR\|FATAL/i` (when stage=synth) | HIGH |
| Placement overflow | place stderr | `/placement overflow\|not enough sites\|Cannot place/i` | MEDIUM |
| Congestion | route stderr | `/GRT-0119\|Routing congestion too high/i` | HIGH (from ORFS docs) |
| DRC violations | route report | parseDrcReport returns violations > 0 | HIGH (existing parser) |
| Timing violation (setup) | finish report | parseFinishReport WNS < 0 | HIGH (existing parser) |
| Timeout | any stage | stderr === "Process timed out after 10 minutes" | HIGH (existing code) |

### Parameter Adjustment Rules

| Error Type | Parameter | Adjustment | Bounds | restart_from |
|------------|-----------|------------|--------|-------------|
| timing_violation | clock_period_ns | *= 1.5 | [1.0, 100.0] | synth |
| congestion | place_density | -= 0.1 | [0.30, 0.85] | place |
| congestion (with utilization) | core_utilization | -= 10 | [20, 70] | floorplan |
| drc | place_density | -= 0.05 | [0.30, 0.85] | place |
| placement_overflow | core_utilization | -= 15 | [20, 70] | floorplan |
| synthesis_error | N/A | none (not parameter-fixable) | N/A | N/A |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Standalone Tcl scripts (v1.1.2) | ORFS make flow via MCP (v1.1.5) | 2026-04-02 | Clean targets, make dependency tracking, platform defaults |
| No retry (pipeline stops on failure) | Diagnosis + retry infrastructure (v1.2.0) | This phase | Enables automatic failure recovery and QoR optimization |
| Hardcoded clock relaxation (50% per attempt) | Error-type-specific parameter adjustment | This phase | Different error types get different fixes instead of one-size-fits-all |

**Deprecated/outdated:**
- `scripts/synth.sh`, `scripts/pnr.sh`: Migration stubs from v1.1.2 that exit with error. DO NOT use.
- Standalone Yosys/OpenROAD Tcl scripts: Replaced by ORFS make flow in v1.1.5.

## Open Questions

1. **Exact GRT overflow regex pattern**
   - What we know: ORFS reports global route overflow via `[INFO GRT-0018] Total overflow: N`
   - What's unclear: Whether this pattern appears in stderr captured by `run_stage` or only in the GRT log file
   - Recommendation: Check both stderr and log file in `diagnose_failure`. Parse log file from `{orfs_flow_path}/logs/sky130hd/{design}/base/` as fallback.

2. **Hold violation detection**
   - What we know: Hold violations reported in finish report, but existing `parseFinishReport` only extracts setup WNS/TNS
   - What's unclear: Exact format of hold slack in ORFS finish report for sky130hd
   - Recommendation: Defer hold violation detection to a future enhancement. For Phase 16, focus on setup timing, congestion, DRC, placement overflow, and synthesis errors -- these cover the 5 required error types.

3. **clean_all execution time**
   - What we know: `make clean_all` removes files from results/, reports/, and logs/ directories
   - What's unclear: Whether clean_all is fast (just `rm -f`) or slow (involves make dependency resolution)
   - Recommendation: Set a 30-second timeout on clean_design (much shorter than the 10-minute run_stage timeout). If clean takes longer, something is wrong.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in `node:test` + `node:assert/strict` |
| Config file | None (uses Node.js built-in runner) |
| Quick run command | `cd mcp-server && node --test tests/*.test.ts` |
| Full suite command | `cd mcp-server && node --test tests/*.test.ts` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DIAG-01 | Error classification from stderr patterns | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | Wave 0 |
| DIAG-02 | Silent timing violation detection (WNS < 0 on success) | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | Wave 0 |
| DIAG-03 | clean_design calls make clean_all correctly | unit | `cd mcp-server && node --test tests/clean-design.test.ts` | Wave 0 |
| DIAG-04 | generate_config with optional tuning params in output | unit | `cd mcp-server && node --test tests/generate-config.test.ts` | Exists (extend) |
| RETRY-01 | diagnose_failure returns structured JSON with suggestions | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd mcp-server && node --test tests/*.test.ts`
- **Per wave merge:** `cd mcp-server && node --test tests/*.test.ts`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mcp-server/tests/diagnose-failure.test.ts` -- covers DIAG-01, DIAG-02, RETRY-01
- [ ] `mcp-server/tests/clean-design.test.ts` -- covers DIAG-03
- [ ] Extend `mcp-server/tests/generate-config.test.ts` -- covers DIAG-04 (existing file, new test cases)

## Sources

### Primary (HIGH confidence)
- Existing codebase (read directly, 2026-04-02):
  - `mcp-server/tools/generate-config.ts` -- config.mk + SDC generation, `isSequential()` detection, zod schema
  - `mcp-server/tools/run-stage.ts` -- `buildMakeArgs()` pattern, spawn with timeout, `VALID_STAGES`
  - `mcp-server/tools/get-report.ts` -- `parseFinishReport()`, `parseDrcReport()`, STAGE_REPORT_MAP
  - `mcp-server/tools/check-environment.ts` -- tool registration pattern
  - `mcp-server/index.ts` -- server setup and tool registration
  - `mcp-server/tests/*.test.ts` -- test patterns using `node:test`
  - `skills/pnr/SKILL.md` -- current pipeline orchestration (no retry, stops on failure)
- [ORFS Makefile clean targets](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/Makefile) -- `clean_all`, `clean_synth`, `clean_floorplan`, etc. definitions verified
- [ORFS Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) -- PLACE_DENSITY, GPL_TIMING_DRIVEN, GPL_ROUTABILITY_DRIVEN, SETUP_SLACK_MARGIN, HOLD_SLACK_MARGIN defaults and descriptions

### Secondary (MEDIUM confidence)
- [ORFS Flow Tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html) -- clean workflow, stage dependencies, when to clean
- [ORFS Walkthrough](https://vlsida.github.io/chip-tutorials/orfs-walkthrough.html) -- stale result behavior confirmed
- `.planning/research/PITFALLS.md` -- comprehensive pitfall analysis from milestone research
- `.planning/research/ARCHITECTURE.md` -- architecture patterns from milestone research
- `.planning/research/FEATURES.md` -- error pattern taxonomy from milestone research

### Tertiary (LOW confidence)
- GRT overflow regex pattern (`GRT-0018` vs `GRT-0119`) -- derived from ORFS GitHub issues, not verified against local installation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, extending proven patterns from existing codebase
- Architecture: HIGH -- follows existing MCP tool patterns exactly; new tools use same registration, zod, spawn, and JSON response patterns
- Pitfalls: HIGH -- critical pitfalls (stale cache, config/SDC inconsistency) verified from ORFS documentation and confirmed by milestone-level research
- Error patterns: MEDIUM -- regex patterns for ORFS errors derived from documentation and GitHub issues; some patterns need validation against actual sky130hd logs during implementation

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable domain -- ORFS make interface changes slowly)
