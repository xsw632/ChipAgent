---
phase: 08-debug-command
plan: 01
subsystem: simulation
tags: [vcd, waveform, verilator, trace, debug]

requires:
  - phase: 05-skill-decomposition
    provides: simulate.sh script and testbench-generator agent
provides:
  - VCD trace generation in simulation pipeline
  - VCD tracing hooks in all testbench templates
affects: [08-debug-command plan 02 (debug agent needs VCD files)]

tech-stack:
  added: [verilated_vcd_c.h (Verilator VCD API)]
  patterns: [VCD tracing setup/dump/close lifecycle in testbenches]

key-files:
  created: []
  modified:
    - scripts/simulate.sh
    - agents/testbench-generator.md

key-decisions:
  - "Testbenches write to trace.vcd in CWD; simulate.sh relocates to $LOG_DIR/$MODULE.vcd"
  - "VCD dump at every eval() call for combinational; at both clock edges for sequential"

patterns-established:
  - "VCD lifecycle: traceEverOn -> trace(tfp,99) -> open -> dump per eval -> close before final"
  - "tick() helper accepts tfp and sim_time by reference for sequential modules"

requirements-completed: [SKILL-07]

duration: 5min
completed: 2026-03-20
---

# Phase 8 Plan 1: VCD Trace Infrastructure Summary

**VCD waveform trace generation via Verilator --trace flag and verilated_vcd_c.h hooks in all testbench templates**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-20T11:50:35Z
- **Completed:** 2026-03-20T11:55:52Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Added --trace flag to Verilator invocation in simulate.sh
- Added VCD file relocation logic (trace.vcd -> $LOG_DIR/$MODULE.vcd) after simulation
- Updated all four testbench templates with VCD tracing hooks (include, setup, dump, close)
- Added VCD Tracing Conventions documentation section
- Added VCD-specific anti-patterns (traceEverOn, tfp->close ordering)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add --trace flag and VCD tracing hooks** - `6074a49` (feat)

## Files Created/Modified
- `scripts/simulate.sh` - Added --trace flag and VCD relocation after simulation
- `agents/testbench-generator.md` - VCD hooks in all templates, new conventions section, anti-patterns

## Decisions Made
- Testbenches write VCD to "trace.vcd" in CWD; simulate.sh moves it to canonical location
- Sequential tick() helpers pass tfp and sim_time by reference for dual-edge dumping

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- VCD traces now generated alongside sim_result.log for every simulation run
- Plan 02 (debug agent) can locate VCD files at workspace/<Module>/sim/logs/<Module>.vcd

---
*Phase: 08-debug-command*
*Completed: 2026-03-20*
