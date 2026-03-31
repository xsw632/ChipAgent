---
phase: 10-yosys-synthesis
plan: 01
subsystem: synthesis
tags: [yosys, nangate45, gate-level-netlist, asic-synthesis, tcl]

# Dependency graph
requires:
  - phase: 09-environment-sdc-foundation
    provides: validate-pdk.sh, generate_sdc.sh, _common.sh, detect-env.sh, .chipagent/env.json
provides:
  - "scripts/synth.tcl -- Yosys Tcl ASIC synthesis recipe for nangate45"
  - "scripts/synth.sh -- Bash wrapper for synthesis pipeline with pre-flight checks"
  - "Gate-level netlists at workspace/pnr/<Module>.synth.v"
  - "Synthesis reports at workspace/pnr/reports/synth_stat.txt"
affects: [11-openroad-pnr, pnr, timing, gds]

# Tech tracking
tech-stack:
  added: [yosys-tcl-scripts]
  patterns: [two-file-architecture (bash-wrapper + tcl-recipe), env-var-bridge between bash and yosys-tcl]

key-files:
  created:
    - scripts/synth.tcl
    - scripts/synth.sh
  modified: []

key-decisions:
  - "Yosys Tcl mode (-c) requires yosys prefix on all commands"
  - "Simplified flow without hilomap/insbuf -- OpenROAD parses netlists fine without tie/buffer cells"
  - "stat -liberty for area numbers instead of bare stat"

patterns-established:
  - "Two-file pattern: bash orchestration (synth.sh) + Tcl synthesis recipe (synth.tcl) connected via exported env vars"
  - "Module name extracted from Verilog source (grep '^module '), not from directory name"

requirements-completed: [SYN-01, SYN-03]

# Metrics
duration: 7min
completed: 2026-03-31
---

# Phase 10 Plan 01: Yosys Synthesis Pipeline Summary

**Yosys ASIC synthesis pipeline producing nangate45 gate-level netlists for ALU (492 cells, 517um2) and Counter8 (28 cells, 58um2) with synthesis statistics reporting**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-31T14:58:46Z
- **Completed:** 2026-03-31T15:05:46Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created Yosys Tcl synthesis recipe (synth.tcl) with full nangate45 ASIC flow: read_liberty, read_verilog -DSYNTHESIS, synth -top -flatten, dfflibmap, abc, cleanup passes, stat -liberty, write_verilog
- Created bash wrapper (synth.sh) with pre-flight PDK validation, SDC generation, Yosys invocation, output verification, and synthesis summary printing
- End-to-end verified on both module types: ALU (combinational, 492 cells) and Counter8 (sequential, 28 cells with DFF_X1 flip-flops)
- Confirmed OpenROAD can parse both netlists via read_verilog + link_design without errors

## Task Commits

Each task was committed atomically:

1. **Task 1: Create synth.tcl Yosys synthesis recipe** - `d60ab44` (feat)
2. **Task 2: Create synth.sh bash wrapper with pre-flight checks and e2e verification** - `7fdf1a5` (feat)

## Files Created/Modified
- `scripts/synth.tcl` - Yosys Tcl ASIC synthesis recipe for nangate45 technology mapping
- `scripts/synth.sh` - Bash wrapper orchestrating pre-flight checks, env var setup, Yosys invocation, and output verification

## Decisions Made
- Used `yosys` prefix on all Tcl commands (required by Yosys -c Tcl mode, discovered during testing)
- Simplified flow without hilomap/insbuf -- OpenROAD parses the netlists without tie/buffer cells; Phase 11 can add them if needed
- Used `stat -liberty` (not bare `stat`) to get area numbers in synthesis reports

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added yosys prefix to all commands in synth.tcl for Tcl mode compatibility**
- **Found during:** Task 2 (end-to-end verification)
- **Issue:** Yosys Tcl interpreter mode (`-c` flag) requires all Yosys synthesis commands to be prefixed with `yosys` (e.g., `yosys read_liberty` instead of bare `read_liberty`). Without the prefix, commands are treated as undefined Tcl procedures.
- **Fix:** Added `yosys` prefix to all 11 commands in synth.tcl (read_liberty, read_verilog, synth, dfflibmap, abc, setundef, splitnets, opt_clean, tee x2, write_verilog)
- **Files modified:** scripts/synth.tcl
- **Verification:** Both ALU and Counter8 synthesize successfully; OpenROAD parses both netlists
- **Committed in:** 7fdf1a5 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Essential fix for correctness -- Tcl mode requires the yosys prefix. No scope creep.

## Issues Encountered
None beyond the Tcl prefix deviation documented above.

## User Setup Required
None - no external service configuration required. PDK and Yosys were already configured by Phase 9.

## Next Phase Readiness
- Gate-level netlists ready at workspace/pnr/<Module>.synth.v for Phase 11 OpenROAD PnR
- SDC constraints already generated at workspace/pnr/constraint.sdc alongside netlists
- Synthesis reports with gate count and area available for downstream quality checks
- Both combinational (ALU) and sequential (Counter8) module types verified end-to-end

---
*Phase: 10-yosys-synthesis*
*Completed: 2026-03-31*
