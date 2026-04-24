---
phase: 17-retry-orchestration-qor-optimization
plan: 02
subsystem: skill
tags: [pnr, retry-orchestration, qor-comparison, stage-aware-restart, mcp-tools]

# Dependency graph
requires:
  - phase: 17-retry-orchestration-qor-optimization
    provides: compare_runs MCP tool for QoR history save/load/recommend/clear
  - phase: 16-diagnosis-retry-infrastructure
    provides: diagnose_failure, clean_design MCP tools, generate_config tuning params
provides:
  - PnR skill with 3-round retry loop, stage-aware restart, QoR comparison table, and best-run recommendation
  - Complete v1.2.0 feature set for intelligent PnR failure handling
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [retry-loop with mutable param accumulation, stage-order slicing for partial restart, QoR comparison display]

key-files:
  created: []
  modified:
    - skills/pnr/SKILL.md

key-decisions:
  - "Retry loop uses mutable current_params that accumulate adjustments across rounds (no reset between rounds)"
  - "Critical severity errors abort retry immediately -- synthesis errors and combinational timing violations are not parameter-fixable"
  - "clean_design called before every retry to prevent ORFS stale cache issues"
  - "Best-run recommendation drives Step 5 PPA report -- only runs if a passing round exists"

patterns-established:
  - "Retry orchestration in Skill layer: diagnose -> clean -> regenerate config -> re-run from restart_from"
  - "QoR comparison table as standard post-pipeline output format"
  - "Stage-aware restart via STAGE_ORDER slice from diagnosis restart_from"

requirements-completed: [RETRY-02, RETRY-03, RETRY-04, QOR-02]

# Metrics
duration: 4min
completed: 2026-04-02
---

# Phase 17 Plan 02: PnR Retry Orchestration and QoR Comparison Summary

**PnR skill rewritten with 3-round retry loop, stage-aware restart from diagnosis, QoR comparison table, and deterministic best-run recommendation**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-02T10:08:00Z
- **Completed:** 2026-04-02T10:12:07Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- PnR skill implements 3-round retry loop: run stages -> diagnose failure -> clean design -> adjust params -> re-run from restart_from
- Stage-aware restart skips synthesis when only placement/routing parameters change (STAGE_ORDER slicing)
- Critical severity errors abort retry immediately with clear messaging
- QoR comparison table displayed after all rounds with per-run metrics (clock, utilization, density, WNS, TNS, area, power, DRC, status)
- Best-run recommendation via compare_runs(action="recommend") with fallback messaging when no passing round exists
- Three new MCP tools added to allowed-tools: diagnose_failure, clean_design, compare_runs
- Anti-patterns section updated with retry-specific rules (no skip clean, no retry critical, no param reset)

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite PnR skill with retry loop and QoR reporting** - `2f33950` (feat)
2. **Task 2: Verify PnR skill retry orchestration** - human-verify checkpoint (approved, no code commit)

## Files Created/Modified
- `skills/pnr/SKILL.md` - Complete rewrite with retry orchestration (Step 2 init state, Step 2.5 clear QoR, Step 3 retry loop, Step 4 QoR comparison, Step 5 PPA report for best run, updated pipeline table and anti-patterns)

## Decisions Made
- Retry loop uses mutable current_params that accumulate adjustments across rounds -- avoids parameter drift by never resetting to original values
- Critical severity errors (synthesis_error, combinational timing_violation) abort retry immediately rather than wasting rounds
- clean_design is mandatory before every retry to prevent ORFS stale cache issues
- Step 5 PPA report only runs if compare_runs recommend returns a best run -- prevents formatting invalid data
- Pipeline stages table renumbered to reflect new Step 2.5 (Clear QoR) and Step 3 (Retry Loop) structure

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- v1.2.0 feature set is complete: all Phase 16 + Phase 17 tools and skill orchestration in place
- PnR skill ready for end-to-end testing with actual ORFS installations
- Known concern: ORFS error regex patterns in diagnose_failure need validation against actual sky130hd log output

## Self-Check: PASSED

- [x] skills/pnr/SKILL.md exists
- [x] 17-02-SUMMARY.md exists
- [x] Commit 2f33950 (feat task 1) verified

---
*Phase: 17-retry-orchestration-qor-optimization*
*Completed: 2026-04-02*
