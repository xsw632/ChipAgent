---
phase: 15-pnr-skill-orchestration-ppa-reporting
plan: 02
subsystem: pnr
tags: [mcp, orfs, sky130hd, ppa, skill]

requires:
  - phase: 15-01
    provides: "MCP server report parsers (parseTiming, parsePower, parseArea, parseDRC)"
  - phase: 13-01
    provides: "MCP server with check_environment, generate_config, run_stage, get_report tools"
provides:
  - "MCP-based PnR orchestration skill (skills/pnr/SKILL.md)"
  - "Updated PPA report formatter agent accepting structured MCP metrics"
affects: [pnr-workflow, chip-agent-pnr-command]

tech-stack:
  added: []
  patterns: ["MCP tool orchestration in skill files", "structured metric passing between skill and agent"]

key-files:
  created: []
  modified:
    - skills/pnr/SKILL.md
    - agents/pnr-report-formatter.md

key-decisions:
  - "Skill calls 4 MCP tools instead of synth.sh/pnr.sh scripts"
  - "Per-stage metrics displayed after each of 6 ORFS stages"
  - "Agent receives structured metrics, no file parsing needed"

patterns-established:
  - "MCP skill pattern: skill orchestrates MCP tools, agent formats results"

requirements-completed: [FLOW-01, FLOW-02, FLOW-03, RPT-01]

duration: 3min
completed: 2026-04-02
---

# Phase 15 Plan 02: PnR Skill Orchestration + PPA Reporting Summary

**Rewrote /chip-agent:pnr skill to orchestrate 6 ORFS stages via MCP tools with per-stage metrics and formatted PPA summary report**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-02T04:45:52Z
- **Completed:** 2026-04-02T04:49:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Rewrote skills/pnr/SKILL.md to call check_environment, generate_config, run_stage, and get_report MCP tools
- Skill sequences all 6 ORFS stages (synth, floorplan, place, cts, route, finish) with per-stage metric display
- Updated pnr-report-formatter agent to accept structured metrics from MCP responses instead of parsing raw files
- PPA report includes timing (WNS/TNS/MET/VIOLATED), power (uW with percentages), area (synth + post-PnR), DRC, ORFS artifact paths

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite skills/pnr/SKILL.md for MCP orchestration** - `f930124` (feat)
2. **Task 2: Update pnr-report-formatter agent for ORFS metrics** - `eddefd2` (feat)

## Files Created/Modified
- `skills/pnr/SKILL.md` - MCP-based PnR orchestration skill with 5-step pipeline
- `agents/pnr-report-formatter.md` - PPA report formatter accepting structured MCP metrics

## Decisions Made
None - followed plan as specified.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- PnR skill fully wired to MCP backend tools
- Ready for end-to-end testing with actual ORFS installation

---
*Phase: 15-pnr-skill-orchestration-ppa-reporting*
*Completed: 2026-04-02*
