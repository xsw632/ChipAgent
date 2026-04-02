---
phase: 17-retry-orchestration-qor-optimization
verified: 2026-04-02T19:30:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 17: Retry Orchestration & QoR Optimization Verification Report

**Phase Goal:** PnR skill automatically retries failed flows with diagnosed parameter adjustments and presents multi-round QoR comparison with best-run recommendation
**Verified:** 2026-04-02T19:30:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

**Plan 01 Truths (compare_runs MCP tool):**

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | compare_runs save action appends a run entry to qor_history.json | VERIFIED | saveRun in compare-runs.ts:21-26 reads, spreads, writes. Test "appends without overwriting" passes at line 68-79 |
| 2 | compare_runs load action returns all entries from qor_history.json | VERIFIED | loadHistory in compare-runs.ts:15-18 reads and parses JSON. MCP handler returns full history at case "load" line 121-133 |
| 3 | compare_runs recommend action returns tightest-clock passing run with zero DRC | VERIFIED | recommendBest in compare-runs.ts:29-51 filters pass+wns>=0+drc=0, sorts by clock_period then area. 5 tests pass covering picking, tie-breaking, ignoring wns<0, ignoring drc>0 |
| 4 | compare_runs clear action resets history to empty array | VERIFIED | Case "clear" in compare-runs.ts:160-175 writes `[]` to file. Returns `{cleared: true, total_runs: 0}` |
| 5 | Missing qor_history.json returns empty array on load | VERIFIED | loadHistory returns `[]` when !existsSync (line 16). Test "returns empty array for nonexistent file" passes |

**Plan 02 Truths (PnR skill retry orchestration):**

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 6 | PnR skill retries failed flows up to 3 rounds automatically | VERIFIED | SKILL.md:104 `max_rounds = 3`, line 118 `While round <= max_rounds`, line 184 "Max retries exhausted" break |
| 7 | Retry calls diagnose_failure, clean_design, generate_config with adjusted params | VERIFIED | SKILL.md:188 calls diagnose_failure, line 210 calls clean_design, line 215 calls generate_config with current_params |
| 8 | Retry skips synthesis when only placement params change (stage-aware restart) | VERIFIED | SKILL.md:116 STAGE_ORDER definition, line 122-124 slices from restart_from, line 229 sets restart_from from diagnosis.restart_from |
| 9 | Retry aborts immediately on critical severity errors | VERIFIED | SKILL.md:201 checks severity=="critical" and breaks with abort message. Anti-pattern at line 324 reinforces |
| 10 | After all rounds, a QoR comparison table is displayed | VERIFIED | SKILL.md:233-261 Step 4 loads all runs, formats markdown table with Round/Clock/Utilization/Density/WNS/TNS/Area/Power/DRC/Status columns |
| 11 | Best run is recommended based on tightest clock with WNS>=0 and DRC=0 | VERIFIED | SKILL.md:263-270 calls compare_runs(action="recommend"), displays "Recommendation: Round {N}" or "No passing run found" |
| 12 | compare_runs clear is called at start of each pnr invocation | VERIFIED | SKILL.md:106-112 Step 2.5 calls compare_runs(action="clear") before entering retry loop |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `mcp-server/tools/compare-runs.ts` | compare_runs MCP tool with save/load/recommend/clear | VERIFIED | 179 lines, exports QorRun interface, loadHistory, saveRun, recommendBest, registerCompareRuns |
| `mcp-server/tests/compare-runs.test.ts` | Unit tests (min 60 lines) | VERIFIED | 183 lines, 11 tests across 3 suites, all passing |
| `mcp-server/index.ts` | MCP server with compare_runs registered | VERIFIED | Line 9 imports registerCompareRuns, line 22 calls registerCompareRuns(server) |
| `skills/pnr/SKILL.md` | PnR skill with retry loop, QoR comparison, best-run recommendation (min 150 lines) | VERIFIED | 325 lines. Contains retry loop (Step 3), QoR comparison (Step 4), PPA report (Step 5), anti-patterns |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| mcp-server/index.ts | mcp-server/tools/compare-runs.ts | import + registerCompareRuns(server) | WIRED | Line 9: `import { registerCompareRuns }`, Line 22: `registerCompareRuns(server)` |
| mcp-server/tests/compare-runs.test.ts | mcp-server/tools/compare-runs.ts | import loadHistory, saveRun, recommendBest | WIRED | Line 6: `import { loadHistory, saveRun, recommendBest }` |
| skills/pnr/SKILL.md | diagnose_failure MCP tool | MCP tool call in retry loop | WIRED | Line 16: allowed-tools list, Line 188: call with stage/stderr/report args |
| skills/pnr/SKILL.md | compare_runs MCP tool | MCP tool call for save/load/recommend/clear | WIRED | Line 18: allowed-tools list, Lines 108/171/237/265: calls with all 4 actions |
| skills/pnr/SKILL.md | clean_design MCP tool | MCP tool call before each retry | WIRED | Line 17: allowed-tools list, Line 210: call with config_mk_path and orfs_flow_path |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RETRY-02 | 17-02 | PnR skill implements retry loop: diagnose -> adjust -> clean -> regenerate -> re-run (max 3 rounds) | SATISFIED | SKILL.md Step 3 implements full retry loop with all 5 stages in sequence |
| RETRY-03 | 17-02 | Retry adjusts parameters based on error type (timing->clock, congestion->density, overflow->utilization) | SATISFIED | SKILL.md:188-206 calls diagnose_failure which returns suggested_params; line 205 merges into current_params |
| RETRY-04 | 17-02 | Stage-aware restart: skip synth when only placement params change | SATISFIED | SKILL.md:116 STAGE_ORDER, line 124 slices from restart_from, line 229 sets restart_from from diagnosis |
| QOR-01 | 17-01 | compare_runs MCP tool saves/retrieves run configs+metrics as JSON | SATISFIED | compare-runs.ts implements save/load/recommend/clear with qor_history.json persistence, 11 tests passing |
| QOR-02 | 17-02 | After all rounds, PnR skill displays comparison table with per-run config, metrics, status | SATISFIED | SKILL.md:233-261 Step 4 loads runs and formats markdown table with 10 columns |
| QOR-03 | 17-01 | Agent recommends best run: tightest clock, WNS>=0, zero DRC | SATISFIED | recommendBest filters pass+wns>=0+drc=0, sorts by clock_period then area. 5 unit tests validate |

**Orphaned requirements check:** REQUIREMENTS.md maps RETRY-02, RETRY-03, RETRY-04, QOR-01, QOR-02, QOR-03 to Phase 17. All 6 appear in plan frontmatter (17-01: QOR-01, QOR-03; 17-02: RETRY-02, RETRY-03, RETRY-04, QOR-02). No orphans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| compare-runs.ts | 16 | `return []` | Info | Legitimate: correct behavior for missing file |
| compare-runs.ts | 39 | `return null` | Info | Legitimate: correct behavior for no passing runs |

No TODO, FIXME, PLACEHOLDER, console.log, or stub patterns found in any artifact.

### Human Verification Required

### 1. End-to-End PnR Retry Flow

**Test:** Run `/chip-agent:pnr ALU8` with a design that has a tight clock period (e.g., 2ns) likely to cause timing violations
**Expected:** Skill should attempt up to 3 rounds, displaying round separators, per-stage metrics, diagnosis messages with param adjustments, and finally a QoR comparison table with recommendation
**Why human:** Requires ORFS installation with sky130hd PDK; real make flow execution cannot be simulated programmatically

### 2. Stage-Aware Restart Behavior

**Test:** Observe retry behavior when only placement parameters (place_density) change vs. when clock_period changes
**Expected:** Placement-only changes restart from floorplan (skipping synth); clock changes restart from synth
**Why human:** Requires observing actual ORFS stage execution sequence during retry

### 3. Critical Severity Abort

**Test:** Trigger a synthesis error (e.g., invalid Verilog) and observe retry behavior
**Expected:** Skill should detect critical severity and abort immediately without retrying
**Why human:** Requires triggering actual ORFS synthesis failure

### Gaps Summary

No gaps found. All 12 observable truths verified. All 4 required artifacts pass existence, substantive, and wiring checks. All 5 key links verified as wired. All 6 requirement IDs satisfied with implementation evidence. No anti-pattern blockers detected.

**Test results:** 11/11 compare-runs tests pass. Full MCP test suite passes with 0 failures.

---

_Verified: 2026-04-02T19:30:00Z_
_Verifier: Claude (gsd-verifier)_
