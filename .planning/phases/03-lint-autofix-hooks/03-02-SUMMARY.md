---
phase: 03-lint-autofix-hooks
plan: 02
subsystem: hooks
tags: [verilator, lint, hooks, claude-plugin, auto-fix]

requires:
  - phase: 03-lint-autofix-hooks-01
    provides: lint.sh script and chisel-warnings.vlt waiver file
provides:
  - Event-keyed PostToolUse hook for compile-on-write automation
  - Lint stage with 3-attempt auto-fix loop in generate.md pipeline
affects: [04-testbench-sim]

tech-stack:
  added: []
  patterns: [event-keyed hooks format, lint auto-fix loop with attempt limit]

key-files:
  created: []
  modified: [hooks/hooks.json, skills/generate.md]

key-decisions:
  - "Lint is skill-orchestrated only (no PostToolUse hook) to prevent infinite loops"
  - "Auto-fix loop targets Chisel source, never generated Verilog"

patterns-established:
  - "Event-keyed hooks.json format: hooks object keyed by event name, matcher as regex string"
  - "Pipeline auto-fix pattern: 3 attempts max, then stop and report"

requirements-completed: [LINT-02, LINT-03, HOOK-01, HOOK-02, HOOK-03]

duration: 4min
completed: 2026-03-17
---

# Phase 3 Plan 2: Hooks and Lint Pipeline Summary

**Event-keyed PostToolUse compile hook and 7-stage pipeline with lint auto-fix loop (3-attempt limit)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-17T10:43:25Z
- **Completed:** 2026-03-17T10:47:25Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Rewrote hooks.json from legacy flat-array to official event-keyed format
- Added Step 4 Lint with 3-attempt auto-fix loop to generate.md pipeline
- Pipeline table updated: Lint marked Active, all 7 stages documented

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite hooks.json to official event-keyed format** - `2bf8f31` (feat)
2. **Task 2: Update generate.md with lint stage and auto-fix loop** - `1934164` (feat)

## Files Created/Modified
- `hooks/hooks.json` - Event-keyed PostToolUse hook for compile automation
- `skills/generate.md` - Full 7-stage pipeline with lint auto-fix loop

## Decisions Made
- Lint is skill-orchestrated only (no PostToolUse hook) to prevent infinite loops
- Auto-fix loop targets Chisel source, never generated Verilog

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full lint pipeline operational: compile-on-write hook + skill-orchestrated lint with auto-fix
- Ready for Phase 4: testbench generation and simulation

---
*Phase: 03-lint-autofix-hooks*
*Completed: 2026-03-17*
