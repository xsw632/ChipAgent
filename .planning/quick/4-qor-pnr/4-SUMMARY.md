---
phase: 4-qor-pnr
plan: 1
subsystem: mcp-server
tags: [qor, pnr, recommendation, power, dynamic-rounds]
dependency_graph:
  requires: [compare-runs tool, SKILL.md pipeline]
  provides: [power-aware recommendBest, mandatory multi-round QoR, dynamic round expansion]
  affects: [skills/pnr/SKILL.md, mcp-server/tools/compare-runs.ts]
tech_stack:
  added: []
  patterns: [tertiary sort key, dynamic round expansion]
key_files:
  created: []
  modified:
    - mcp-server/tools/compare-runs.ts
    - mcp-server/tests/compare-runs.test.ts
    - skills/pnr/SKILL.md
decisions:
  - "Use Infinity as default for missing total_power_w so runs with power data always rank higher"
  - "Use proportional clock tightening (baseline * 0.8/0.7) instead of fixed -2ns for cross-design portability"
  - "Expand from 3 to 5 rounds when synth_cell_count > 1000 (large design heuristic)"
metrics:
  duration: 501s
  completed: "2026-04-13"
  tasks: 2
  files_modified: 3
---

# Quick Task 4: QoR PnR Summary

Power-aware QoR recommendation with mandatory multi-round comparison and dynamic parameter generation based on design complexity.

## Changes Made

### Task 1: Power tiebreaker in recommendBest (TDD)
- Added `total_power_w` as tertiary sort key in `recommendBest` (after `clock_period_ns`, then `area`)
- Missing `total_power_w` values treated as `Infinity`, so runs with actual power data are preferred
- Updated recommend action message to include power metric
- Added 4 new tests: power tiebreak, missing power handling, clock priority confirmation, stable sort

### Task 2: SKILL.md mandatory multi-round QoR
- Added MANDATORY rule at top of Step 3 forbidding early exit from comparison rounds
- Replaced 3 static round plans with baseline-only initialization in Step 2
- Added dynamic round expansion after Round 1 based on `synth_cell_count`
- 3 rounds by default, 5 rounds when cell count exceeds 1000
- Uses proportional clock tightening (`baseline * 0.8` / `baseline * 0.7`) instead of fixed offset
- Updated round completion messages to show `X/N` format with remaining count
- Added anti-pattern against skipping remaining rounds
- Updated recommendation display to include power (`power={P}uW`)

## Commits

| Commit  | Message |
|---------|---------|
| 03c69e2 | feat(4-qor-pnr): add power tiebreaker to recommendBest sort |
| d3d09f9 | feat(4-qor-pnr): mandatory multi-round QoR with dynamic params and progress indicators |

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

All modified files verified present. Both commits verified in git log.
