# Phase 17: Retry Orchestration & QoR Optimization - Research

**Researched:** 2026-04-02
**Domain:** Skill-layer retry orchestration, MCP tool for QoR history, PnR pipeline enhancement
**Confidence:** HIGH

## Summary

Phase 17 builds the retry orchestration loop in the PnR Skill layer and adds a `compare_runs` MCP tool for QoR history persistence. The Phase 16 infrastructure (diagnose_failure, clean_design, generate_config with tuning params) is complete and provides all the building blocks. This phase wires them together in `skills/pnr/SKILL.md` and adds the final MCP tool.

The work splits into two domains: (1) a new `compare_runs` MCP tool that persists run configs and metrics to `qor_history.json` in the workspace, and (2) modifications to the PnR skill instructions that replace the current "stop on failure" behavior with a 3-round retry loop using diagnose_failure -> clean_design -> generate_config -> run_stage, followed by a QoR comparison table and best-run recommendation.

The critical insight is that retry logic lives entirely in the Skill layer (LLM instructions), NOT in MCP tools. MCP tools remain stateless single-purpose operations. The Skill orchestrates the loop, tracks round state, and makes decisions. The `compare_runs` tool only handles persistence (save/load JSON).

**Primary recommendation:** Add `compare_runs` MCP tool for JSON persistence, then rewrite `skills/pnr/SKILL.md` Step 3-4 to include retry loop with stage-aware restart and QoR comparison reporting.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RETRY-02 | PnR skill retry loop: diagnose -> adjust -> clean -> regenerate -> re-run (max 3 rounds) | Skill layer orchestration pattern documented in Architecture section. Uses existing diagnose_failure, clean_design, generate_config, run_stage tools. |
| RETRY-03 | Retry adjusts params by error type: timing->clock_period, congestion->place_density, overflow->core_utilization | Already implemented in diagnose_failure.ts suggestParams(). Skill just applies suggested_params to generate_config call. |
| RETRY-04 | Stage-aware restart: skip synth when only placement params change | restart_from field in DiagnosisResult already computed by diagnose_failure. Skill uses it to determine which stage to start from. |
| QOR-01 | compare_runs MCP tool saves/retrieves run configs+metrics as JSON in workspace | New tool documented in Architecture section. Simple fs read/write of qor_history.json. |
| QOR-02 | After retries, display comparison table with per-run config, metrics, status | Skill formatting instructions documented in Code Examples. Data sourced from compare_runs tool. |
| QOR-03 | Recommend best run: tightest clock period with WNS >= 0, zero DRC | Selection algorithm documented in Code Examples. Deterministic filter+sort on metrics. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @modelcontextprotocol/sdk | 1.29.0 | MCP server framework | Already in use |
| zod | ^3.25 | Input validation | Already in use |
| node:fs | Node 22+ | JSON persistence for qor_history.json | Already in use |
| node:test + node:assert/strict | Node 22+ | Unit testing | Already in use |

### Supporting
No new dependencies needed.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| qor_history.json (flat file) | SQLite | Overkill for <10 runs per design; JSON is human-readable and zero-dependency |
| Best-run logic in MCP tool | Best-run logic in Skill (LLM) | MCP tool is deterministic and testable; LLM arithmetic unreliable |

**Installation:**
```bash
# No new packages needed
cd mcp-server && npm install
```

## Architecture Patterns

### Recommended Project Structure
```
mcp-server/
  tools/
    compare-runs.ts              # NEW: QoR history persistence
    diagnose-failure.ts          # existing (Phase 16)
    clean-design.ts              # existing (Phase 16)
    generate-config.ts           # existing (Phase 16, extended)
    run-stage.ts                 # existing
    get-report.ts                # existing
  tests/
    compare-runs.test.ts         # NEW
  index.ts                       # MODIFY: register compare_runs

skills/
  pnr/SKILL.md                  # MODIFY: add retry loop + QoR reporting
```

### Pattern 1: compare_runs MCP Tool
**What:** Persists and retrieves run history as JSON. Two operations: "save" appends a run entry, "load" returns all entries.
**When to use:** After each PnR run completes (success or failure), and before generating comparison table.
**Example:**
```typescript
// qor_history.json schema
interface QorRun {
  readonly round: number;
  readonly config: {
    readonly clock_period_ns: number;
    readonly core_utilization: number;
    readonly place_density?: number;
    readonly gpl_timing_driven?: boolean;
    readonly gpl_routability_driven?: boolean;
  };
  readonly metrics: {
    readonly wns?: number;
    readonly tns?: number;
    readonly area?: number;
    readonly total_power_w?: number;
    readonly drc_violations?: number;
    readonly cell_count?: number;
  };
  readonly status: "pass" | "fail";
  readonly error_type?: string;
  readonly timestamp: string;
}

// Tool interface:
// action: "save" -- append run to qor_history.json
// action: "load" -- return all runs from qor_history.json
// action: "recommend" -- return best run (tightest clock, WNS>=0, DRC=0)
```

### Pattern 2: Retry Loop in Skill Layer
**What:** The PnR skill Step 3 becomes a loop with max 3 rounds.
**When to use:** Replaces current linear "stop on failure" behavior.
**Pseudocode:**
```
for round in 1..3:
  run all stages from restart_point to finish
  collect metrics via get_report
  save run to compare_runs(action="save")

  if all stages succeed AND WNS >= 0 AND DRC == 0:
    break  # success

  if round == 3:
    break  # max retries reached

  # Diagnose and prepare retry
  call diagnose_failure with stage info + current params
  if severity == "critical":
    break  # not parameter-fixable

  call clean_design
  call generate_config with suggested_params merged
  set restart_point = diagnosis.restart_from
```

### Pattern 3: Stage-Aware Restart (RETRY-04)
**What:** When `restart_from` is "place" or later, skip synth and floorplan stages.
**When to use:** When diagnose_failure returns restart_from != "synth".
**Key detail:** The `restart_from` field from `diagnose_failure` already encodes this logic:
- timing_violation -> restart_from: "synth" (clock change affects synthesis)
- congestion/drc -> restart_from: "place" (only placement params changed)
- placement_overflow -> restart_from: "floorplan" (utilization change affects floorplan)

The skill simply runs stages starting from `restart_from` through "finish".

Stage ordering for partial restart:
```
const STAGE_ORDER = ["synth", "floorplan", "place", "cts", "route", "finish"];
const startIdx = STAGE_ORDER.indexOf(restart_from);
const stagesToRun = STAGE_ORDER.slice(startIdx);
```

**CRITICAL:** clean_design must STILL run before partial restart. ORFS caches ALL stages, not just the changed one. Without clean, even "place" stage reuses cached results.

### Pattern 4: Best-Run Recommendation (QOR-03)
**What:** Deterministic selection of best run from history.
**Algorithm:**
```
1. Filter runs where status == "pass" AND wns >= 0 AND drc_violations == 0
2. Sort by clock_period_ns ascending (tightest first)
3. If tie, sort by area ascending
4. Return first entry (or "no passing run" if filter is empty)
```

### Anti-Patterns to Avoid
- **Retry logic in MCP tool:** MCP tools must be stateless. The retry loop belongs in the Skill.
- **Not cleaning between retries:** ORFS caches by timestamp. Without clean_design before every retry, stale results are reused silently.
- **Retrying synthesis_error or combinational timing_violation:** These are severity "critical" -- not fixable by parameter adjustment. Skill must check severity and abort retry loop.
- **Modifying qor_history.json directly with Bash/Edit:** Use compare_runs tool for atomic read/write. Direct editing risks JSON corruption.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Error classification | LLM pattern matching on logs | diagnose_failure MCP tool | Already built in Phase 16, deterministic |
| Parameter adjustment | LLM arithmetic | diagnose_failure suggested_params | Already built, with bounds clamping |
| Config regeneration | Manual file editing | generate_config MCP tool | Atomic config.mk + SDC generation |
| Cache invalidation | Selective file deletion | clean_design MCP tool | ORFS owns dependency graph |
| QoR persistence | Inline JSON in Skill instructions | compare_runs MCP tool | Testable, survives sessions |
| Best-run selection | LLM judgment | compare_runs "recommend" action | Deterministic filter+sort |

**Key insight:** Phase 16 already built all the hard parts. Phase 17 is orchestration (Skill wiring) + persistence (one new tool) + presentation (table formatting).

## Common Pitfalls

### Pitfall 1: Forgetting to Clean Before Partial Restart
**What goes wrong:** Skipping clean_design when restart_from is "place" because "we're not re-running synth anyway." ORFS still has cached place/cts/route results that won't be regenerated.
**How to avoid:** ALWAYS call clean_design before every retry, regardless of restart_from. The clean takes <30 seconds; a stale retry wastes 10+ minutes producing identical wrong results.

### Pitfall 2: Infinite Retry on Non-Recoverable Errors
**What goes wrong:** Retrying synthesis_error or combinational timing_violation wastes all 3 rounds on unfixable errors.
**How to avoid:** Check `severity` field from diagnose_failure. If "critical", exit retry loop immediately with explanation.

### Pitfall 3: Config Parameter Drift Across Rounds
**What goes wrong:** Round 2 adjusts clock_period from 10 to 15. Round 3 should adjust from 15 (not 10), but Skill passes original value.
**How to avoid:** Track current parameters as mutable state in the Skill loop. Each round's generate_config call uses the latest merged parameters, and diagnose_failure receives the latest current values.

### Pitfall 4: qor_history.json Race Condition
**What goes wrong:** Multiple concurrent PnR runs on the same module overwrite each other's history.
**How to avoid:** Not a real concern -- PnR skill runs sequentially. But compare_runs should still read-then-append atomically (read file, parse, push, write).

### Pitfall 5: Missing Metrics on Failed Runs
**What goes wrong:** A run that fails at placement has no finish report, so WNS/TNS/area/power are undefined. The comparison table shows empty cells.
**How to avoid:** compare_runs save action accepts partial metrics. Display "N/A" for unavailable metrics. Failed runs still appear in the table with status "fail" and error_type.

## Code Examples

### compare_runs Tool Implementation
```typescript
// mcp-server/tools/compare-runs.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";

interface QorRun {
  readonly round: number;
  readonly config: Record<string, unknown>;
  readonly metrics: Record<string, unknown>;
  readonly status: "pass" | "fail";
  readonly error_type?: string;
  readonly timestamp: string;
}

export function loadHistory(historyPath: string): QorRun[] {
  if (!existsSync(historyPath)) return [];
  const content = readFileSync(historyPath, "utf-8");
  return JSON.parse(content) as QorRun[];
}

export function saveRun(historyPath: string, run: QorRun): QorRun[] {
  mkdirSync(dirname(historyPath), { recursive: true });
  const history = loadHistory(historyPath);
  const updated = [...history, run];
  writeFileSync(historyPath, JSON.stringify(updated, null, 2), "utf-8");
  return updated;
}

export function recommendBest(runs: QorRun[]): QorRun | null {
  const passing = runs.filter(r =>
    r.status === "pass" &&
    (r.metrics.wns as number | undefined) !== undefined &&
    (r.metrics.wns as number) >= 0 &&
    ((r.metrics.drc_violations as number | undefined) ?? 0) === 0
  );
  if (passing.length === 0) return null;
  passing.sort((a, b) => {
    const cpA = (a.config.clock_period_ns as number) ?? Infinity;
    const cpB = (b.config.clock_period_ns as number) ?? Infinity;
    if (cpA !== cpB) return cpA - cpB; // tightest first
    const areaA = (a.metrics.area as number) ?? Infinity;
    const areaB = (b.metrics.area as number) ?? Infinity;
    return areaA - areaB;
  });
  return passing[0];
}
```

### Skill Retry Loop (pseudocode for SKILL.md Step 3)
```markdown
### Step 3 -- Run Stages with Retry

Initialize tracking state:
- round = 1, max_rounds = 3
- current_params = { clock_period_ns, core_utilization } from Step 2
- restart_from = "synth" (first round runs all stages)
- HISTORY_PATH = MyDesign/$MODULE/workspace/qor_history.json

**Retry Loop:**

While round <= max_rounds:

  1. Run stages from restart_from through finish (call run_stage for each)
  2. After each stage, call get_report to collect metrics
  3. Determine pass/fail:
     - If any stage fails: status = "fail", collect stderr
     - If all succeed: check finish WNS and route DRC
     - pass = (all stages succeed AND WNS >= 0 AND DRC == 0)
  4. Call compare_runs(action="save") with round config, metrics, status
  5. If pass: break (success)
  6. If round == max_rounds: break (exhausted)
  7. Call diagnose_failure with stage info + current params
  8. If severity == "critical": break (not fixable)
  9. Merge suggested_params into current_params
  10. Call clean_design
  11. Call generate_config with updated current_params
  12. Set restart_from = diagnosis.restart_from
  13. round += 1
```

### QoR Comparison Table Format (QOR-02)
```markdown
=== QoR Comparison: <ModuleName> ===

| Round | Clock (ns) | Utilization | Density | WNS (ns) | TNS (ns) | Area (um2) | Power (uW) | DRC | Status |
|-------|-----------|-------------|---------|----------|----------|------------|------------|-----|--------|
| 1     | 10.0      | 40%         | -       | -2.5     | -15.3    | 1234       | 45.2       | 0   | FAIL   |
| 2     | 15.0      | 40%         | -       | 0.3      | 0.0      | 1456       | 38.1       | 0   | PASS   |

Recommendation: Round 2 (clock=15.0ns, WNS=0.3ns, area=1456um2)
```

### MCP Tool Registration for compare_runs
```typescript
// In compare-runs.ts registerCompareRuns function
server.tool(
  "compare_runs",
  "Save, load, or recommend best PnR run from QoR history",
  {
    action: z.enum(["save", "load", "recommend"]).describe("Operation"),
    workspace_dir: z.string().describe("Absolute path to module workspace"),
    run: z.object({
      round: z.number(),
      config: z.record(z.unknown()),
      metrics: z.record(z.unknown()),
      status: z.enum(["pass", "fail"]),
      error_type: z.string().optional(),
    }).optional().describe("Run data (required for save action)"),
  },
  async ({ action, workspace_dir, run }) => {
    const historyPath = resolve(workspace_dir, "qor_history.json");
    // dispatch on action...
  },
);
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Stop on first failure (v1.1.5) | Auto-retry with diagnosis (v1.2.0) | This phase | Up to 3 automatic recovery attempts |
| No QoR tracking | Persistent qor_history.json | This phase | Cross-session history, comparison tables |
| Manual clock relaxation | Error-type-specific parameter adjustment | Phase 16 | Different fixes for different errors |

## Open Questions

1. **Should compare_runs clear history on fresh PnR run?**
   - What we know: qor_history.json accumulates across sessions
   - Recommendation: Add a "clear" action that resets history. Call it at the start of Step 3 (before round 1) so each `/chip-agent:pnr` invocation starts fresh. Old history can be viewed by loading before clearing.

2. **Partial metrics display for failed early stages**
   - What we know: A run failing at placement has no finish metrics
   - Recommendation: Display "N/A" for unavailable metrics. The status column already shows FAIL.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in `node:test` + `node:assert/strict` |
| Config file | None (uses Node.js built-in runner) |
| Quick run command | `cd mcp-server && node --test tests/*.test.ts` |
| Full suite command | `cd mcp-server && node --test tests/*.test.ts` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RETRY-02 | Retry loop orchestration (3 rounds max) | manual (Skill layer) | N/A -- Skill instructions tested via `/chip-agent:pnr` | N/A |
| RETRY-03 | Error-type-specific param adjustment | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | Exists (Phase 16) |
| RETRY-04 | Stage-aware restart (restart_from field) | unit | `cd mcp-server && node --test tests/diagnose-failure.test.ts` | Exists (Phase 16) |
| QOR-01 | compare_runs save/load/recommend | unit | `cd mcp-server && node --test tests/compare-runs.test.ts` | Wave 0 |
| QOR-02 | Comparison table display | manual (Skill layer) | N/A -- verified by visual inspection | N/A |
| QOR-03 | Best-run recommendation algorithm | unit | `cd mcp-server && node --test tests/compare-runs.test.ts` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd mcp-server && node --test tests/*.test.ts`
- **Per wave merge:** `cd mcp-server && node --test tests/*.test.ts`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `mcp-server/tests/compare-runs.test.ts` -- covers QOR-01, QOR-03

## Sources

### Primary (HIGH confidence)
- Existing codebase (read directly, 2026-04-02):
  - `mcp-server/tools/diagnose-failure.ts` -- classifyError(), suggestParams(), DiagnosisResult interface
  - `mcp-server/tools/generate-config.ts` -- generateConfigMk(), generateSdc(), tuning params support
  - `mcp-server/tools/get-report.ts` -- parseFinishReport(), parseDrcReport(), metric extraction
  - `mcp-server/tools/clean-design.ts` -- clean_design tool
  - `skills/pnr/SKILL.md` -- current pipeline (no retry, linear stages)
- Phase 16 Research (`16-RESEARCH.md`) -- comprehensive error patterns, parameter bounds, ORFS caching behavior

### Secondary (MEDIUM confidence)
- ORFS documentation on stage dependencies and clean targets

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, extending proven patterns
- Architecture: HIGH -- compare_runs is simple JSON persistence; retry loop is straightforward orchestration of existing tools
- Pitfalls: HIGH -- inherited from Phase 16 research, all verified against ORFS behavior
- Skill modifications: MEDIUM -- Skill layer is LLM instructions, harder to unit test than MCP tools

**Research date:** 2026-04-02
**Valid until:** 2026-05-02
