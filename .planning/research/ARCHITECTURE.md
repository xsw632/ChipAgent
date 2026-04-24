# Architecture Patterns: Smart Retry & QoR Optimization

**Domain:** EDA Backend Flow Automation (MCP Server + PnR Skill extension)
**Researched:** 2026-04-02
**Focus:** Integration of error diagnosis, parameter retry, and QoR optimization into existing ChipAgent v1.1.5 architecture

## Existing Architecture Snapshot

Current system has 3 layers:

```
+---------------------------------------------+
|  PnR Skill (SKILL.md orchestration)          |  <-- Claude Code LLM follows steps
|  Steps: verify -> env -> config -> 6 stages  |
|         -> format report                     |
+---------+-----------------------------------+
          | MCP tool calls (JSON-RPC, stdio)
+---------v-----------------------------------+
|  MCP Server (chipagent-backend, TypeScript)   |
|  4 Tools:                                    |
|    check_environment  - ORFS/PDK detection   |
|    generate_config    - config.mk + SDC      |
|    run_stage          - make <target>         |
|    get_report         - parse report files    |
+---------+-----------------------------------+
          | spawn("make", [stage], {DESIGN_CONFIG})
+---------v-----------------------------------+
|  ORFS Make Flow (sky130hd, local install)    |
|  Targets: synth->floorplan->place->cts->     |
|           route->finish                      |
+---------------------------------------------+
```

**Key facts about existing implementation:**
- `run_stage` spawns `make <stage>` directly (local ORFS, no Docker) with 10-min timeout
- `get_report` reads from `{orfs_flow_path}/reports/sky130hd/{design}/base/` using regex parsers
- `generate_config` writes `config.mk` + `constraint.sdc` to `MyDesign/<Module>/workspace/pnr/`
- `generate_config` already accepts `core_utilization` as optional param (default 40)
- Skill runs all 6 stages sequentially, calls `get_report` after each, formats PPA at end
- No retry logic exists -- stage failure = pipeline stops with error message

## Recommended Architecture for v1.2.0

### Design Principle: Deterministic Diagnosis in MCP, Decision-Making in Skill

The LLM (driving the Skill) is the decision-maker. MCP tools are pure data extraction and execution. This means:
- **Diagnosis**: NEW MCP tool `diagnose_failure` -- deterministic regex pattern matching on logs/reports, returns structured error classification with parameter suggestions
- **Retry decisions**: Skill layer -- LLM reads diagnosis, applies suggested parameters (or overrides based on judgment)
- **Config regeneration**: EXTEND existing `generate_config` -- add optional override parameters (`place_density`, etc.)
- **Stage cleanup**: NEW MCP tool `clean_stage` -- wraps ORFS `make clean_<target>`
- **QoR history**: NEW MCP tool `qor_history` -- stores/retrieves run results as JSON in workspace
- **QoR comparison**: Skill layer -- LLM formats comparison table from history data

### Extended Architecture Diagram

```
+---------------------------------------------------------------+
|  PnR Skill (SKILL.md) -- EXTENDED                             |
|                                                                |
|  Steps 0-4: [existing pipeline, unchanged]                    |
|                                                                |
|  NEW Step 5: Post-Completion Check                             |
|    -> after all 6 stages succeed, check WNS from finish report|
|    -> if WNS < 0: treat as timing_violation                   |
|    -> save round 1 to qor_history                             |
|                                                                |
|  NEW Step 6: Diagnose (on failure or timing violation)         |
|    -> call diagnose_failure(stage, stderr, design, orfs_path) |
|    -> receive error_type + suggested_params + restart_from     |
|                                                                |
|  NEW Step 7: Retry Loop (max 3 rounds)                         |
|    -> call generate_config with adjusted params               |
|    -> call clean_stage for restart_from through finish         |
|    -> re-run stages from restart_from                         |
|    -> call get_report + qor_history(save)                     |
|    -> check success -> if not, repeat                         |
|                                                                |
|  NEW Step 8: QoR Comparison                                    |
|    -> call qor_history(list)                                  |
|    -> format comparison table (all rounds)                    |
|    -> recommend best configuration                            |
+------+--------------------------------------------------------+
       | MCP tool calls
+------v--------------------------------------------------------+
|  MCP Server (chipagent-backend) -- EXTENDED                    |
|                                                                |
|  EXISTING tools (unchanged):                                   |
|    check_environment                                          |
|    run_stage                                                  |
|    get_report                                                 |
|                                                                |
|  MODIFIED tool:                                                |
|    generate_config  <-- add place_density, gpl_timing_driven  |
|                                                                |
|  NEW tools:                                                    |
|    diagnose_failure <-- log/report pattern matching            |
|    clean_stage      <-- make clean_<target> wrapper            |
|    qor_history      <-- save/list run results as JSON          |
+------+--------------------------------------------------------+
       |
+------v--------------------+
|  ORFS Make Flow (unchanged)|
+----------------------------+
```

## Component Specifications

### Component 1: `diagnose_failure` (NEW MCP Tool)

**Responsibility:** Parse ORFS logs, reports, and stderr to classify failure type and suggest parameter adjustments.

**Why a NEW tool (not extending `get_report`):**
- `get_report` extracts *metrics* from successful stages -- different data sources (reports vs logs)
- Diagnosis reads *stderr* from failed `run_stage` calls and *log files* -- different input shape
- Diagnosis returns *recommendations* (suggested_params, restart_from) -- different output shape
- Keeping them separate preserves backward compatibility of `get_report`

**Input schema:**
```typescript
{
  stage: z.enum(["synth", "floorplan", "place", "cts", "route", "finish"]),
  design_name: z.string(),
  orfs_flow_path: z.string(),
  stderr: z.string().optional(),  // stderr captured from run_stage failure
  current_config: z.object({      // current parameters for computing adjustments
    clock_period_ns: z.number(),
    core_utilization: z.number(),
    place_density: z.number().optional(),
  }),
}
```

**Output schema:**
```typescript
{
  error_type: "timing_violation" | "congestion" | "drc" | "placement_overflow" | "synthesis_error" | "unknown",
  severity: "critical" | "recoverable",
  details: string,                    // human-readable error description
  suggested_params: {                 // parameter adjustments to try
    clock_period_ns?: number,         // new absolute value
    place_density?: number,           // new absolute value (0.0-1.0)
    core_utilization?: number,        // new absolute value (0-100)
  },
  restart_from: "synth" | "floorplan" | "place" | "cts" | "route",
}
```

**Error classification patterns** (regex on logs/stderr/reports):

| Pattern Source | Regex Pattern | error_type | Adjustment | restart_from |
|----------------|--------------|-----------|------------|-------------|
| finish report (WNS < 0) | `wns max ([-\d.]+)` where value < 0 | `timing_violation` | `clock_period_ns *= 1.5` | `synth` |
| stderr | `Unable to repair all setup violations` | `timing_violation` | `clock_period_ns *= 1.5` | `synth` |
| stderr | `\[ERROR GRT-0119\] Routing congestion too high` | `congestion` | `place_density -= 0.1`, `core_utilization -= 10` | `floorplan` |
| route DRC report | `violation type:` count > 0 | `drc` | `place_density -= 0.05` | `place` |
| stderr | `Placement failed\|density overflow` | `placement_overflow` | `place_density -= 0.15` or `core_utilization -= 15` | `floorplan` |
| stderr | `ERROR\|FATAL` (no specific match) | `unknown` | none (report to user) | N/A |
| synth log | `ERROR.*yosys\|Synthesis failed` | `synthesis_error` | none (RTL issue, not param-fixable) | N/A |

**Implementation approach:**
1. Read log files from `{orfs_flow_path}/logs/sky130hd/{design_name}/base/`
2. Read the finish report from `{orfs_flow_path}/reports/sky130hd/{design_name}/base/` if available
3. Parse `stderr` string from the failed `run_stage` response
4. Apply pattern matching in priority order (most specific first)
5. Compute suggested parameter values by adjusting `current_config` values
6. Return `severity: "critical"` for synthesis errors (not parameter-fixable), `"recoverable"` for others

**File location:** `mcp-server/tools/diagnose-failure.ts`

**Confidence:** HIGH -- Pattern matching on documented ORFS error strings. The specific regex patterns need validation against actual ORFS output (flag for phase-specific testing).

### Component 2: `generate_config` (MODIFIED MCP Tool)

**Current parameters:** `module_name`, `verilog_path`, `workspace_dir`, `clock_port`, `clock_period_ns`, `core_utilization`

**New optional parameters to add:**
```typescript
{
  // ... existing params unchanged ...
  // NEW: override params for retry (all optional, only written to config.mk when provided)
  place_density: z.number().min(0).max(1).optional()
    .describe("Placement density 0.0-1.0, overrides platform default"),
  gpl_timing_driven: z.boolean().optional()
    .describe("Enable timing-driven placement (default: true)"),
  gpl_routability_driven: z.boolean().optional()
    .describe("Enable routability-driven placement (default: true)"),
}
```

**Changes to `generateConfigMk` function:**
```typescript
// Current output:
// export DESIGN_NAME = ALU8
// export PLATFORM = sky130hd
// export VERILOG_FILES = /path/to/ALU8.v
// export SDC_FILE = /path/to/constraint.sdc
// export CORE_UTILIZATION = 40
// export TNS_END_PERCENT = 100

// NEW: conditionally append override lines
if (params.place_density !== undefined) {
  lines.push(`export PLACE_DENSITY = ${params.place_density}`);
}
if (params.gpl_timing_driven !== undefined) {
  lines.push(`export GPL_TIMING_DRIVEN = ${params.gpl_timing_driven ? 1 : 0}`);
}
if (params.gpl_routability_driven !== undefined) {
  lines.push(`export GPL_ROUTABILITY_DRIVEN = ${params.gpl_routability_driven ? 1 : 0}`);
}
```

**Why modify rather than new tool:**
- Config generation is already this tool's job
- Adding optional params is fully backward-compatible (existing callers unaffected)
- Avoids duplicating Verilog parsing, SDC generation, directory creation logic

**File location:** `mcp-server/tools/generate-config.ts` (modify existing)

**Confidence:** HIGH -- Straightforward extension.

### Component 3: `clean_stage` (NEW MCP Tool)

**Responsibility:** Run `make clean_<stage>` to remove ORFS artifacts before retry.

**Why needed:**
- ORFS `make` is incremental -- re-running without cleaning uses cached results
- Must clean from the restart stage onward to get fresh results with new parameters
- No existing way to clean stages through MCP

**Input schema:**
```typescript
{
  stage: z.enum(["synth", "floorplan", "place", "cts", "route", "finish"]),
  config_mk_path: z.string(),
  orfs_flow_path: z.string(),
}
```

**Implementation:** Reuse `buildMakeArgs` pattern from `run-stage.ts` but with `clean_<stage>` target:
```typescript
spawn("make", [`clean_${stage}`], {
  cwd: orfsFlowPath,
  env: { ...process.env, DESIGN_CONFIG: configMkPath },
});
```

**Usage in Skill:** When retrying from stage X, the Skill calls `clean_stage` for each stage from X through `finish` (6 calls max), then re-runs stages from X onward.

**Stage order for cleaning (important):**
```
synth -> floorplan -> place -> cts -> route -> finish
```
If `restart_from = "place"`, clean: place, cts, route, finish (in order).

**File location:** `mcp-server/tools/clean-stage.ts`

**Confidence:** HIGH -- Direct make target wrapper, same pattern as existing `run_stage`.

### Component 4: `qor_history` (NEW MCP Tool)

**Responsibility:** Persist and retrieve QoR run results for multi-round comparison.

**Why a tool (not Skill file I/O):**
- Consistent JSON schema with Zod validation
- Atomic append (no risk of LLM corrupting JSON structure)
- Encapsulates storage location

**Input schema (two actions via discriminated union):**
```typescript
// Save action
{
  action: z.literal("save"),
  workspace_dir: z.string(),
  run: z.object({
    round: z.number(),
    timestamp: z.string(),
    config: z.object({
      clock_period_ns: z.number(),
      core_utilization: z.number(),
      place_density: z.number().nullable(),
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
    timing_met: z.boolean(),
    error_type: z.string().nullable(),
  }),
}

// List action
{
  action: z.literal("list"),
  workspace_dir: z.string(),
}
```

**Storage location:** `MyDesign/<Module>/workspace/pnr/qor_history.json`

**Storage format:**
```json
{
  "module": "ALU8",
  "runs": [
    {
      "round": 1,
      "timestamp": "2026-04-02T14:30:00Z",
      "config": {
        "clock_period_ns": 10,
        "core_utilization": 40,
        "place_density": null
      },
      "metrics": {
        "cell_count": 85,
        "synth_area": 1234.5,
        "wns": -0.5,
        "tns": -1.2,
        "total_power_uw": 45.3,
        "area": 1500,
        "utilization": 35,
        "drc_violations": 0
      },
      "timing_met": false,
      "error_type": "timing_violation"
    }
  ]
}
```

**File location:** `mcp-server/tools/qor-history.ts`

**Confidence:** HIGH -- Simple JSON file I/O with Zod validation.

## Data Flow: Complete Retry Loop

```
User: /chip-agent:pnr ALU8

EXISTING Step 0-2: verify Verilog -> check_environment -> generate_config(defaults)
EXISTING Step 3: run all 6 stages sequentially with get_report after each
                                |
                     +----------+----------+
                     |                     |
              ALL stages pass        Stage X fails
                     |              (run_stage success=false)
                     v                     |
              Check finish metrics         v
              get_report("finish")    diagnose_failure(stage=X, stderr)
                     |                     |
              +------+------+              v
              |             |         error_type + suggested_params
         WNS >= 0      WNS < 0            |
              |             |              v
              v             v         +----+----+
         SUCCESS      timing_violation|         |
              |             |     recoverable  critical
              |             v         |         |
              |        diagnose_failure         v
              |        (stage="finish",    STOP: report
              |         WNS from report)   synthesis/RTL issue
              |             |
              v             v
    qor_history(save,  qor_history(save,
      round=1,           round=N,
      timing_met=true)   timing_met=false)
              |             |
              |             v
              |     Round < 3?
              |      YES: generate_config(suggested_params)
              |            clean_stage(restart_from..finish)
              |            re-run stages from restart_from
              |            -> loop back to check
              |      NO: max retries exhausted
              |             |
              v             v
    qor_history(list) -> format comparison table
    Format final PPA report (best round highlighted)
    DONE
```

**Critical nuance -- timing violations are NOT stage failures:**
ORFS completes all 6 stages successfully even when WNS is negative. The Skill MUST check WNS from `get_report("finish")` AFTER all stages succeed. This is a post-completion check, not a stage failure handler.

Detection branches:
1. `run_stage` returns `success: false` -> stage failed -> `diagnose_failure` with stderr
2. All stages succeed, WNS < 0 -> timing violation -> `diagnose_failure` with finish report data
3. All stages succeed, WNS >= 0 -> true success

## Stage-Aware Retry: What to Re-Run

Different parameter changes affect different stages:

| Parameter Changed | restart_from | Stages to Clean | Stages to Re-Run | Rationale |
|-------------------|-------------|----------------|------------------|-----------|
| `clock_period_ns` | `synth` | ALL (synth..finish) | ALL 6 stages | SDC changes affect synthesis constraints |
| `core_utilization` | `floorplan` | floorplan..finish | floorplan..finish (5 stages) | Die area changes, synthesis netlist unchanged |
| `place_density` | `place` | place..finish | place..finish (4 stages) | Only affects placement onward |

This optimization saves 30-60 seconds per retry by skipping synthesis when only placement params change.

## Anti-Patterns to Avoid

### Anti-Pattern 1: LLM Parsing Raw Logs Directly

**What:** Having the Skill use `Read` tool on ORFS log files and interpret error messages.

**Why bad:** ORFS logs can be 5K-50K lines. Sending to LLM wastes tokens and produces inconsistent diagnosis.

**Instead:** `diagnose_failure` tool does all log parsing via regex, returns structured JSON.

### Anti-Pattern 2: Retry Logic Inside MCP Server

**What:** Having `run_stage` auto-retry on failure or having a single "run_all_with_retry" tool.

**Why bad:** MCP tools should be stateless, single-purpose. Retry requires cross-stage context. Removes user visibility.

**Instead:** Skill drives the retry loop, calling individual tools. User sees each retry attempt.

### Anti-Pattern 3: QoR History in MCP Server Memory

**What:** Keeping run history in TypeScript variables.

**Why bad:** MCP server may restart between sessions. History lost.

**Instead:** `qor_history` tool persists to JSON file in module workspace.

### Anti-Pattern 4: Full Clean on Every Retry

**What:** Running `make clean_all` before each retry.

**Why bad:** Synthesis takes 15-60s. If fix is PLACE_DENSITY, only placement onward needs re-running.

**Instead:** `clean_stage` from `restart_from` through `finish` only.

### Anti-Pattern 5: Modifying config.mk In-Place Without Regeneration

**What:** Using `sed` or `Edit` to patch individual lines in config.mk.

**Why bad:** Partial updates risk inconsistency (e.g., changing clock period in config.mk but not in SDC).

**Instead:** Always call `generate_config` with full parameter set. It regenerates both config.mk and SDC atomically.

## Integration Points Summary

| Integration | Type | File(s) Affected |
|-------------|------|------------------|
| `diagnose_failure` | New MCP tool | `mcp-server/tools/diagnose-failure.ts`, `mcp-server/index.ts` |
| `clean_stage` | New MCP tool | `mcp-server/tools/clean-stage.ts`, `mcp-server/index.ts` |
| `qor_history` | New MCP tool | `mcp-server/tools/qor-history.ts`, `mcp-server/index.ts` |
| `generate_config` params | Modify existing | `mcp-server/tools/generate-config.ts` |
| PnR Skill retry + diagnosis | Modify existing | `skills/pnr/SKILL.md` |
| PnR Skill QoR comparison | Modify existing | `skills/pnr/SKILL.md` |
| Skill allowed-tools list | Modify existing | `skills/pnr/SKILL.md` frontmatter |
| Report formatter (comparison table) | Extend existing | `agents/pnr-report-formatter.md` |
| MCP tool registration | Modify existing | `mcp-server/index.ts` (3 new imports + registerX calls) |
| Tests | New files | `mcp-server/tests/diagnose-failure.test.ts`, `clean-stage.test.ts`, `qor-history.test.ts` |

## Suggested Build Order

Dependencies dictate this sequence:

**Phase 1: `clean_stage` tool + `generate_config` extension**
- Both are independent, can be built in parallel
- `clean_stage` is simplest (same pattern as `run_stage`)
- `generate_config` extension is backward-compatible (just adding optional Zod params)
- Tests: unit tests for both

**Phase 2: `diagnose_failure` tool**
- Needs understanding of actual ORFS log patterns (test with real ORFS output)
- Independent of retry logic -- can test diagnosis in isolation
- Tests: unit tests with sample log/stderr strings

**Phase 3: `qor_history` tool**
- Independent of diagnosis -- just JSON file I/O
- Can be built in parallel with Phase 2
- Tests: unit tests for save/list operations

**Phase 4: Skill retry loop (SKILL.md rewrite)**
- Depends on Phases 1-3 (all tools must exist)
- Wire diagnosis -> config regeneration -> clean -> re-run loop
- Add timing violation detection (WNS check after finish)
- Tests: manual end-to-end with ALU module

**Phase 5: QoR comparison table + report update**
- Depends on Phase 3 (qor_history) and Phase 4 (retry produces multiple rounds)
- Update `pnr-report-formatter.md` to handle comparison table format
- Tests: manual end-to-end

**Rationale:** Phases 1-3 are independent MCP tool implementations -- can largely be built in parallel. Phase 4 integrates everything. Phase 5 is polish.

## Sources

- [ORFS Flow Variables](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/FlowVariables.md) -- PLACE_DENSITY, CORE_UTILIZATION, GPL_TIMING_DRIVEN tunable parameters
- [ORFS Tutorial](https://openroad-flow-scripts.readthedocs.io/en/latest/tutorials/FlowTutorial.html) -- stage flow, clean targets, error patterns
- [OpenROAD Timing Discussions](https://github.com/The-OpenROAD-Project/OpenROAD/discussions/3608) -- setup/hold violation patterns and RSZ warnings
- [OpenROAD DRC Discussions](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/discussions/745) -- DRC violation patterns
- [ORFS Adding New Designs](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/docs/user/AddingNewDesign.md) -- config.mk structure and parameter overrides
- Existing codebase (verified locally, 2026-04-02):
  - `mcp-server/index.ts` -- MCP server registration pattern
  - `mcp-server/tools/run-stage.ts` -- `buildMakeArgs` pattern, spawn/timeout handling
  - `mcp-server/tools/get-report.ts` -- report parsing functions, STAGE_REPORT_MAP
  - `mcp-server/tools/generate-config.ts` -- config.mk + SDC generation, Zod schema
  - `skills/pnr/SKILL.md` -- current pipeline orchestration
  - `agents/pnr-report-formatter.md` -- report formatting rules
