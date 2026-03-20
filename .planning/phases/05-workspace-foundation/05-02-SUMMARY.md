---
phase: 05-workspace-foundation
plan: 02
subsystem: infra
tags: [bash, workspace, verilator, lint, simulation]

# Dependency graph
requires:
  - phase: 05-workspace-foundation
    provides: Workspace-aware compile.sh with per-module artifact isolation (Plan 01)
provides:
  - Workspace-aware lint.sh with waiver file fallback
  - Workspace-aware simulate.sh with isolated obj_dir and logs
  - TrivialModule testbench (sim/tb_TrivialModule.cpp)
  - Complete Phase 5 verification script (12 checks across compile, lint, simulate)
affects: [06-skill-decomposition, 07-orchestrator]

# Tech tracking
tech-stack:
  added: []
  patterns: [workspace-aware-lint, workspace-aware-simulation, waiver-file-fallback, slash-detection-heuristic]

key-files:
  created:
    - sim/tb_TrivialModule.cpp
  modified:
    - scripts/lint.sh
    - scripts/simulate.sh
    - scripts/test-phase5.sh

key-decisions:
  - "simulate.sh uses '/' detection heuristic to distinguish workspace paths from bare module names"
  - "Waiver file fallback: check per-module first, then global generated/chisel-warnings.vlt"
  - "Added -I$PLUGIN_ROOT/sim to CFLAGS for shared testbench headers across modes"

patterns-established:
  - "Workspace waiver fallback: per-module -> global -> empty (no waiver)"
  - "simulate.sh path detection: contains '/' = workspace mode, bare name = v1.0 flat mode"

requirements-completed: [WKSP-02]

# Metrics
duration: 4min
completed: 2026-03-20
---

# Phase 5 Plan 2: Workspace Lint and Simulate Summary

**Workspace-aware lint.sh and simulate.sh with waiver fallback, isolated obj_dir/logs, and full 12-check verification**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-20T04:20:04Z
- **Completed:** 2026-03-20T04:24:38Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- lint.sh accepts optional workspace path argument, resolves to workspace/generated/ for linting
- simulate.sh detects workspace paths via '/' heuristic, routes obj_dir and logs to workspace/sim/
- Both scripts implement waiver file fallback (per-module then global then empty)
- Backward-compatible: no args = flat mode behavior identical to v1.0
- TrivialModule testbench created for simulation testing
- Expanded test-phase5.sh from 6 to 12 checks, all passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Add workspace support to lint.sh and simulate.sh** - `6fbe0c5` (feat)
2. **Task 2: Expand test-phase5.sh with lint and simulate workspace tests** - `895bfac` (feat)

## Files Created/Modified
- `scripts/lint.sh` - Workspace-aware Verilator lint with waiver fallback
- `scripts/simulate.sh` - Workspace-aware Verilator simulation with isolated obj_dir
- `scripts/test-phase5.sh` - Full Phase 5 verification (12 checks: compile+lint+simulate in both modes)
- `sim/tb_TrivialModule.cpp` - Minimal TrivialModule testbench for Verilator simulation

## Decisions Made
- simulate.sh uses '/' detection heuristic: if arg contains '/', treat as workspace path; otherwise treat as v1.0 bare module name. This preserves full backward compatibility.
- Waiver file fallback chain: check per-module waiver first ($GENERATED_DIR/chisel-warnings.vlt), then fall back to global waiver ($PLUGIN_ROOT/generated/chisel-warnings.vlt), then no waiver.
- Added -I$PLUGIN_ROOT/sim to verilator CFLAGS so testbenches can include shared headers (e.g., cpu_test_template.h) regardless of flat or workspace mode.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three pipeline scripts (compile, lint, simulate) are workspace-aware
- Full end-to-end pipeline verified: compile -> lint -> simulate in both flat and workspace modes
- Phase 5 complete: workspace foundation ready for Phase 6 skill decomposition
- Skills can invoke individual pipeline stages on specific workspace modules

---
*Phase: 05-workspace-foundation*
*Completed: 2026-03-20*

## Self-Check: PASSED
- All 4 files verified on disk (lint.sh, simulate.sh, test-phase5.sh, tb_TrivialModule.cpp)
- Both task commits (6fbe0c5, 895bfac) found in git log
