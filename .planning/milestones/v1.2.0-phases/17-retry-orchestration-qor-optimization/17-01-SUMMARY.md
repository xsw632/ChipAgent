---
phase: 17-retry-orchestration-qor-optimization
plan: 01
subsystem: mcp
tags: [mcp-tool, qor, json-persistence, compare-runs, tdd]

# Dependency graph
requires:
  - phase: 16-diagnosis-retry-infrastructure
    provides: diagnose_failure and clean_design MCP tools, generate_config tuning params
provides:
  - compare_runs MCP tool with save/load/recommend/clear actions
  - QoR history JSON persistence layer
  - Best-run recommendation algorithm (tightest clock, zero DRC, smallest area)
affects: [17-02-pnr-retry-loop]

# Tech tracking
tech-stack:
  added: []
  patterns: [read-append-write atomic JSON persistence, deterministic filter+sort recommendation]

key-files:
  created:
    - mcp-server/tools/compare-runs.ts
    - mcp-server/tests/compare-runs.test.ts
  modified:
    - mcp-server/index.ts

key-decisions:
  - "recommendBest uses deterministic filter+sort (not LLM judgment) for reliable best-run selection"
  - "Four actions (save/load/recommend/clear) in single tool rather than separate tools for cohesion"
  - "qor_history.json uses flat file JSON (not SQLite) -- sufficient for <10 runs per design"

patterns-established:
  - "QorRun interface with readonly config/metrics Record<string, unknown> for flexible schema"
  - "read-append-write pattern for atomic JSON persistence with mkdirSync for parent dirs"

requirements-completed: [QOR-01, QOR-03]

# Metrics
duration: 6min
completed: 2026-04-02
---

# Phase 17 Plan 01: compare_runs QoR History Tool Summary

**compare_runs MCP tool with JSON persistence, 4 actions (save/load/recommend/clear), and deterministic best-run selection by tightest clock period with zero DRC**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-02T09:02:58Z
- **Completed:** 2026-04-02T09:09:54Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- compare_runs MCP tool with save, load, recommend, and clear actions
- Deterministic best-run recommendation: filters pass+wns>=0+drc=0, sorts by clock_period_ns ascending then area ascending
- 11 unit tests covering all 8 specified behaviors plus edge cases
- Full TDD cycle (RED -> GREEN) with zero regressions (73/73 tests pass)

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: failing tests** - `f837bdd` (test)
2. **Task 1 GREEN: implementation** - `c880305` (feat)

_TDD task with RED and GREEN commits. No REFACTOR needed -- code already followed immutable patterns._

## Files Created/Modified
- `mcp-server/tools/compare-runs.ts` - QoR history tool with loadHistory, saveRun, recommendBest, registerCompareRuns exports
- `mcp-server/tests/compare-runs.test.ts` - 11 unit tests covering all specified behaviors
- `mcp-server/index.ts` - Added import and registration of registerCompareRuns

## Decisions Made
- recommendBest uses deterministic filter+sort rather than LLM judgment for reliable selection
- Four actions (save/load/recommend/clear) combined in single MCP tool for cohesion
- QorRun interface uses Record<string, unknown> for config and metrics to support flexible schema across different designs
- Flat file JSON chosen over SQLite -- zero dependency, human-readable, sufficient for <10 runs per design

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- compare_runs tool is registered and ready for Plan 02 (PnR skill retry loop)
- Plan 02 can call compare_runs(action="save") after each round and compare_runs(action="recommend") for final selection
- All Phase 16 tools (diagnose_failure, clean_design, generate_config) remain green

## Self-Check: PASSED

- [x] mcp-server/tools/compare-runs.ts exists
- [x] mcp-server/tests/compare-runs.test.ts exists
- [x] 17-01-SUMMARY.md exists
- [x] Commit f837bdd (test RED) verified
- [x] Commit c880305 (feat GREEN) verified

---
*Phase: 17-retry-orchestration-qor-optimization*
*Completed: 2026-04-02*
