---
phase: 12-pnr-command-report-integration
plan: 01
subsystem: cli
tags: [pnr, openroad, yosys, klayout, gds, synthesis, place-and-route]

requires:
  - phase: 11-openroad-pnr-gds-export
    provides: "pnr.sh, synth.sh, generate_sdc.sh scripts for synthesis and PnR"
provides:
  - "/chip-agent:pnr slash command for user-invocable physical implementation pipeline"
  - "PnR report formatting agent for timing/power/area/DRC summaries"
affects: []

tech-stack:
  added: []
  patterns: [slash-command-pipeline, agent-report-formatting, auto-fix-retry-loop]

key-files:
  created:
    - skills/pnr/SKILL.md
    - agents/pnr-report-formatter.md
  modified:
    - CLAUDE.md

key-decisions:
  - "No synthesis retry -- synthesis failures require RTL changes outside PnR scope"
  - "50% clock period increase per auto-fix retry attempt"
  - "Power always reported in microwatts, never raw Watts"

patterns-established:
  - "PnR pipeline pattern: prereq check -> synth -> PnR+GDS with auto-fix -> format report"
  - "Timing auto-fix: relax clock period by 50%, re-run both synth and PnR, max 3 attempts"

requirements-completed: [CMD-01, CMD-02, CMD-03]

duration: 2min
completed: 2026-04-01
---

# Phase 12 Plan 01: PnR Command + Report Integration Summary

**User-invocable /chip-agent:pnr slash command with 4-step pipeline (prereq, synth, PnR+GDS, report) and timing auto-fix retry**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-01T10:48:09Z
- **Completed:** 2026-04-01T10:50:18Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created PnR report formatting agent that parses timing/power/area/synthesis/DRC reports into human-readable summary
- Created /chip-agent:pnr skill with 4-step pipeline and timing auto-fix retry loop
- Updated CLAUDE.md with new command documentation

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PnR report formatting agent** - `44f60b6` (feat)
2. **Task 2: Create PnR slash command skill and update CLAUDE.md** - `a80d8c0` (feat)

## Files Created/Modified
- `agents/pnr-report-formatter.md` - Agent that parses 5 PnR report files into formatted verification summary
- `skills/pnr/SKILL.md` - Slash command definition with 4-step pipeline and auto-fix retry
- `CLAUDE.md` - Added /chip-agent:pnr to command list and Commands section

## Decisions Made
- No synthesis retry: synthesis failures require RTL changes outside PnR scope, so the command stops with diagnostic info rather than retrying
- 50% clock period increase per retry: balances aggressive timing relaxation vs finding a feasible clock quickly
- Power always in microwatts: raw Watts values for small modules are unreadable (e.g., 0.0000023 W vs 2.3 uW)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 12 complete: /chip-agent:pnr command is ready for use on any module with compiled Verilog
- All v1.1.2 phases (9-12) are now complete
- The full flow from natural language to GDS is available via `/chip-agent:workflow` + `/chip-agent:pnr`

## Self-Check: PASSED

All files and commits verified:
- skills/pnr/SKILL.md: FOUND
- agents/pnr-report-formatter.md: FOUND
- 12-01-SUMMARY.md: FOUND
- Commit 44f60b6: FOUND
- Commit a80d8c0: FOUND

---
*Phase: 12-pnr-command-report-integration*
*Completed: 2026-04-01*
