# Stack Research: v1.2.0 Smart Retry & QoR Optimization

**Domain:** Error diagnosis, parameter tuning, and QoR comparison for ChipAgent PnR pipeline
**Researched:** 2026-04-02
**Confidence:** HIGH

## Scope

This document covers ONLY the stack additions/changes needed for v1.2.0 features. The existing validated stack (MCP server with @modelcontextprotocol/sdk 1.29.0, zod, TypeScript, Node.js 24, ORFS make flow, sky130hd PDK) is NOT re-researched.

**What is new in v1.2.0:**
1. Error classification from ORFS logs (timing violations, congestion, DRC)
2. Error-type-specific parameter retry (PLACE_DENSITY, CLOCK_PERIOD, CTS_CLUSTER_SIZE, etc.)
3. Multi-round QoR optimization with configuration comparison table

---

## Core Recommendation: No New Dependencies

**Extend the existing MCP server. Do not add new frameworks, databases, or libraries.**

Rationale:
- The existing stack (Node.js + TypeScript + zod + MCP SDK) is sufficient for all three features
- Error classification is regex-based log parsing -- already proven by `get-report.ts` parsers
- Parameter tuning is config.mk generation with different values -- already done by `generate-config.ts`
- QoR comparison is JSON file storage + in-memory comparison -- no database needed
- Adding dependencies increases install complexity for a course assignment with tight deadline (April 13)

---

## Recommended Stack Additions

### New MCP Tools (extend existing server)

No new npm packages required. All new functionality is implemented as additional MCP tools registered in `mcp-server/index.ts`, using the same patterns as existing tools.

| New Tool | Purpose | Implementation Approach |
|----------|---------|------------------------|
| `diagnose_failure` | Parse ORFS logs/stderr to classify error type | Regex-based log parsing (same pattern as `get-report.ts`) |
| `suggest_parameters` | Return adjusted parameters based on error type | Pure logic: error type -> parameter adjustment map |
| `save_run_result` | Persist run metrics + config to JSON file | `fs.writeFileSync` to workspace directory |
| `compare_runs` | Load all saved runs and return comparison table | `fs.readdirSync` + `JSON.parse` on saved results |

### ORFS Tunable Parameters for config.mk

These parameters are written into `config.mk` by `generate_config`. The existing tool already accepts `core_utilization` and `clock_period_ns`. New parameters to support:

| Parameter | ORFS Variable | Default | What It Controls | When to Tune |
|-----------|--------------|---------|------------------|--------------|
| `clock_period_ns` | SDC `create_clock -period` | 10 | Clock constraint (ns) | Timing violations (negative WNS) |
| `core_utilization` | `CORE_UTILIZATION` | 40 | Die area sizing (%) | Area optimization, congestion |
| `place_density` | `PLACE_DENSITY` | Platform default (~0.6 for sky130hd) | Cell placement density (0.0-1.0) | Congestion (lower), timing (higher) |
| `cts_cluster_size` | `CTS_CLUSTER_SIZE` | Not set (OpenROAD default: 30) | Max sinks per CTS cluster | Clock skew, CTS timing |
| `cts_cluster_diameter` | `CTS_CLUSTER_DIAMETER` | Not set (OpenROAD default) | Max cluster diameter (um) | Clock skew distribution |
| `cell_pad_global` | `CELL_PAD_IN_SITES_GLOBAL_PLACEMENT` | 0 | Cell padding in global placement | Routability, congestion |
| `cell_pad_detail` | `CELL_PAD_IN_SITES_DETAIL_PLACEMENT` | 0 | Cell padding in detail placement | DRC violations |
| `gpl_timing_driven` | `GPL_TIMING_DRIVEN` | 1 | Timing-driven global placement | Timing closure |
| `gpl_routability_driven` | `GPL_ROUTABILITY_DRIVEN` | 1 | Routability-driven placement | Congestion |
| `setup_slack_margin` | `SETUP_SLACK_MARGIN` | 0 | Extra margin for setup repair (ns) | Aggressive timing closure |
| `hold_slack_margin` | `HOLD_SLACK_MARGIN` | 0 | Extra margin for hold repair (ns) | Hold violations |

**Confidence:** HIGH -- sourced from [ORFS FlowVariables documentation](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) and verified against ORFS GitHub.

### Error Classification Patterns

Error types to detect from ORFS stdout/stderr and report files:

| Error Type | Detection Source | Pattern / Signal |
|------------|-----------------|------------------|
| **Timing violation (setup)** | `get_report` finish stage | `wns < 0` (negative worst negative slack) |
| **Timing violation (hold)** | finish report or logs | `hold__ws < 0` in metadata or hold slack in report |
| **Congestion** | place/route logs, stderr | `"routing congestion"`, `"overflow"`, `GRT overflow > 0` |
| **DRC violations** | `get_report` route stage | `violations > 0` from `parseDrcReport` |
| **Placement failure** | place stage stderr | `"failed to find placement"`, `"utilization too high"`, non-zero exit |
| **CTS failure** | cts stage stderr | `"no clock found"`, `"CTS"` errors, non-zero exit |
| **Synthesis failure** | synth stage stderr | Non-zero exit code (not retryable at PnR level) |
| **Timeout** | `run_stage` response | `stderr === "Process timed out after 10 minutes"` |

**Confidence:** MEDIUM -- patterns derived from ORFS GitHub issues, PR discussions, and common OpenROAD error messages. Some patterns may need refinement against actual sky130hd logs during implementation.

### Error-to-Parameter Retry Strategy

Each error type maps to specific parameter adjustments. Applied cumulatively across retry rounds:

| Error Type | Parameter Adjustments | Rationale |
|------------|----------------------|-----------|
| **Timing (setup)** | `clock_period_ns *= 1.5` | Relax timing constraint (existing behavior, keep it) |
| **Timing (setup), round 2** | `clock_period_ns *= 1.5` + `setup_slack_margin = 0.2` | Add repair margin on top of relaxed clock |
| **Timing (setup), round 3** | Above + `gpl_timing_driven = 1` (ensure on) + `place_density += 0.05` | Denser placement improves timing paths |
| **Congestion** | `place_density -= 0.1` (min 0.3) | Spread cells to reduce routing demand |
| **Congestion, round 2** | `place_density -= 0.1` + `cell_pad_global = 2` | Add padding to create routing channels |
| **DRC violations** | `cell_pad_detail = 1` | Spacing between cells in detail placement |
| **DRC, round 2** | `cell_pad_detail = 2` + `place_density -= 0.05` | More aggressive spacing |
| **Placement failure** | `core_utilization -= 10` (min 20) | More die area for cell placement |

**Confidence:** MEDIUM -- strategies aligned with ORFS AutoTuner best practices and [METRICS2.1 paper](https://vlsicad.ucsd.edu/Publications/Conferences/388/c388.pdf). Exact adjustment magnitudes may need calibration on sky130hd ALU designs.

### QoR Run Storage Format

Store each run as a JSON file in the module workspace. No database needed.

**File location:** `MyDesign/<Module>/workspace/pnr/runs/run_<N>.json`

**Schema (validated with zod, same dependency already in use):**

```typescript
const RunResultSchema = z.object({
  run_id: z.number(),
  timestamp: z.string().datetime(),
  config: z.object({
    clock_period_ns: z.number(),
    core_utilization: z.number(),
    place_density: z.number().optional(),
    cts_cluster_size: z.number().optional(),
    cts_cluster_diameter: z.number().optional(),
    cell_pad_global: z.number().optional(),
    cell_pad_detail: z.number().optional(),
    gpl_timing_driven: z.number().optional(),
    gpl_routability_driven: z.number().optional(),
    setup_slack_margin: z.number().optional(),
    hold_slack_margin: z.number().optional(),
  }),
  metrics: z.object({
    cell_count: z.number().nullable(),
    synth_area: z.number().nullable(),
    wns: z.number().nullable(),
    tns: z.number().nullable(),
    total_power_uw: z.number().nullable(),
    area: z.number().nullable(),
    utilization: z.number().nullable(),
    drc_violations: z.number().nullable(),
  }),
  status: z.enum(["success", "timing_violation", "congestion", "drc", "placement_failure", "cts_failure", "synthesis_failure", "timeout", "unknown_error"]),
  error_detail: z.string().optional(),
});
```

**Confidence:** HIGH -- uses zod (already a dependency), JSON files (portable, no setup), workspace directory convention (already established).

---

## Integration Points with Existing MCP Server

### Minimal Changes to Existing Tools

| Existing Tool | Change Needed | Why |
|---------------|--------------|-----|
| `generate_config` | Accept additional optional parameters (place_density, cts_cluster_size, etc.) and write them to config.mk | Currently only writes DESIGN_NAME, PLATFORM, VERILOG_FILES, SDC_FILE, CORE_UTILIZATION, TNS_END_PERCENT. Needs to support all tunable params. |
| `run_stage` | No change needed | Already returns success/failure, exit code, stdout, stderr. `diagnose_failure` consumes this output. |
| `get_report` | No change needed | Already extracts WNS, TNS, DRC, power, area. These feed into `save_run_result`. |

### New Tool Registration in index.ts

```typescript
// Add to mcp-server/index.ts
import { registerDiagnoseFailure } from "./tools/diagnose-failure.ts";
import { registerSuggestParameters } from "./tools/suggest-parameters.ts";
import { registerSaveRunResult } from "./tools/save-run-result.ts";
import { registerCompareRuns } from "./tools/compare-runs.ts";

registerDiagnoseFailure(server);
registerSuggestParameters(server);
registerSaveRunResult(server);
registerCompareRuns(server);
```

### New Files to Create

| File | Purpose | Approximate LOC |
|------|---------|-----------------|
| `mcp-server/tools/diagnose-failure.ts` | Error classification from logs/stderr/metrics | ~120 |
| `mcp-server/tools/suggest-parameters.ts` | Error-type to parameter adjustment mapping | ~100 |
| `mcp-server/tools/save-run-result.ts` | Persist run config + metrics to JSON | ~60 |
| `mcp-server/tools/compare-runs.ts` | Load and compare all runs for a design | ~80 |
| `mcp-server/tests/diagnose-failure.test.ts` | Unit tests for error classification | ~150 |
| `mcp-server/tests/suggest-parameters.test.ts` | Unit tests for parameter suggestions | ~100 |
| `mcp-server/tests/save-run-result.test.ts` | Unit tests for run persistence | ~60 |
| `mcp-server/tests/compare-runs.test.ts` | Unit tests for run comparison | ~60 |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Run storage | JSON files in workspace | SQLite via better-sqlite3 | Overkill for <20 runs per design. Adds native dependency. JSON files are human-readable and git-friendly. |
| Run storage | JSON files in workspace | ORFS metadata.json parsing | ORFS metadata.json has complex hierarchical keys (`finish__timing__setup__ws`). Our `get_report` already extracts what we need into simpler structures. Reusing our own format is more maintainable. |
| Parameter tuning | Hardcoded strategy map | ORFS AutoTuner | AutoTuner requires Ray Tune + Python + significant compute time. Way beyond scope for a course assignment retry feature. Our rule-based approach is deterministic and fast. |
| Error classification | Regex on logs/stderr | ORFS rules.json comparison | rules.json requires golden reference files we don't have. Our designs are novel (generated from NL). Regex on known patterns is simpler and sufficient. |
| Comparison output | Markdown table in conversation | HTML report file | Skill output is conversation text. Markdown table renders well in Claude Code. No need for external viewer. |

---

## What NOT to Add

| Technology | Why Not |
|------------|---------|
| Any database (SQLite, LevelDB, etc.) | JSON files are sufficient for <20 runs per design |
| Ray Tune / AutoTuner | Far too heavy for rule-based retry; requires Python ML stack |
| Additional npm packages | Everything needed is achievable with Node.js built-ins (fs, path, child_process) + existing zod |
| Python scripts for log parsing | Keep all logic in TypeScript MCP server for consistency |
| Docker SDK / dockerode | System has ORFS installed natively; Docker is an alternative deployment, not primary |
| Express/HTTP server | MCP uses stdio transport; no HTTP needed |

---

## Installation

No new installation steps. The existing `npm install` in `mcp-server/` already provides all needed dependencies:

```bash
cd mcp-server && npm install
# Installs: @modelcontextprotocol/sdk@1.29.0, zod@^3.25
# That's all we need.
```

---

## Sources

- [ORFS Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) -- all PLACE_DENSITY, CTS_CLUSTER_SIZE, etc. parameter names and descriptions (HIGH confidence)
- [ORFS GitHub: AutoTuner variables issue #946](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/issues/946) -- AutoTuner best-result JSON showing tunable parameter space (HIGH confidence)
- [OpenROAD CTS documentation](https://openroad.readthedocs.io/en/latest/main/src/cts/README.html) -- CTS_CLUSTER_SIZE maps to `-sink_clustering_size` (HIGH confidence)
- [METRICS2.1 and Flow Tuning paper](https://vlsicad.ucsd.edu/Publications/Conferences/388/c388.pdf) -- QoR optimization via parameter tuning methodology (MEDIUM confidence, academic)
- [ORFS congestion issue #174](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/issues/174) -- congestion error patterns and mitigation (MEDIUM confidence)
- [ORFS Metrics documentation](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/contrib/Metrics.md) -- metadata.json structure for QoR tracking (HIGH confidence)
- [ORFS-agent paper](https://arxiv.org/html/2506.08332v1) -- LLM-based ORFS optimization agent architecture (LOW confidence, academic/future work)
- Existing codebase: `mcp-server/tools/get-report.ts`, `generate-config.ts`, `run-stage.ts` -- proven patterns for log parsing and config generation (HIGH confidence, verified by reading source)
