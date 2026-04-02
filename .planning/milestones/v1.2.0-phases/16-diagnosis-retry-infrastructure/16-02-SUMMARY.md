---
phase: 16-diagnosis-retry-infrastructure
plan: 02
subsystem: infra
tags: [mcp, orfs, make, clean, placement, timing]

requires:
  - phase: 11-openroad-pnr-gds-export
    provides: "MCP server with run_stage, generate_config, get_report tools"
provides:
  - "clean_design MCP tool for ORFS cache reset via make clean_all"
  - "generate_config extended with placeDensity, gplTimingDriven, gplRoutabilityDriven"
  - "All 6 MCP tools registered in index.ts"
affects: [17-qor-optimization-loop]

tech-stack:
  added: []
  patterns: ["Spawn with shorter timeout for clean operations (30s vs 10min)"]

key-files:
  created: [mcp-server/tools/clean-design.ts, mcp-server/tests/clean-design.test.ts]
  modified: [mcp-server/tools/generate-config.ts, mcp-server/tests/generate-config.test.ts, mcp-server/index.ts]

key-decisions:
  - "30-second timeout for clean_design (fast operation; long runtime signals failure)"
  - "Optional tuning params omitted from config.mk when undefined (backward compatible)"

patterns-established:
  - "Shorter timeout pattern for lightweight make targets"

requirements-completed: [DIAG-03, DIAG-04]

duration: 7min
completed: 2026-04-02
---

# Phase 16 Plan 02: Clean Design Tool & Config Tuning Summary

**clean_design MCP tool wrapping make clean_all with 30s timeout, plus generate_config extended with placement density and timing-driven parameters**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-02T07:39:34Z
- **Completed:** 2026-04-02T07:46:10Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created clean_design tool with buildCleanArgs pure function and 30-second timeout
- Extended generate_config with optional placeDensity, gplTimingDriven, gplRoutabilityDriven parameters
- Registered all 6 MCP tools (4 existing + diagnose_failure + clean_design) in index.ts
- All 62 tests pass including 10 new tests

## Task Commits

1. **Task 1: Create clean-design tool and extend generate-config** - `e3dd17d` (feat, TDD)
2. **Task 2: Register Phase 16 tools in MCP server** - `a03f30d` (feat)

## Files Created/Modified
- `mcp-server/tools/clean-design.ts` - clean_design MCP tool with buildCleanArgs and registerCleanDesign
- `mcp-server/tools/generate-config.ts` - Extended ConfigMkParams with 3 optional tuning fields
- `mcp-server/tests/clean-design.test.ts` - 4 unit tests for buildCleanArgs
- `mcp-server/tests/generate-config.test.ts` - 6 new tests for tuning parameter behavior
- `mcp-server/index.ts` - Registers all 6 tools

## Decisions Made
- 30-second timeout for clean_design (clean is fast; exceeding 30s indicates a problem)
- Optional params use undefined check (not falsy) so gplTimingDriven=false is a valid explicit value

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All MCP tools for Phase 16 complete (diagnose_failure from Plan 01, clean_design from Plan 02)
- generate_config ready for retry Skill layer to pass tuning parameters
- Pre-existing tsconfig.json lacks allowImportingTsExtensions (not blocking; project uses Node native TS loader)

---
*Phase: 16-diagnosis-retry-infrastructure*
*Completed: 2026-04-02*
