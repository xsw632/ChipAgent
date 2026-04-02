---
phase: 16-diagnosis-retry-infrastructure
plan: 01
subsystem: mcp-server
tags: [mcp, orfs, error-classification, retry, diagnosis]

requires: []
provides:
  - "diagnose_failure MCP tool with 5 error type classification and parameter suggestions"
  - "classifyError and suggestParams pure functions for retry orchestration"
affects: [17-qor-optimization-skill]

tech-stack:
  added: []
  patterns: ["error classification with priority chain", "bounded parameter suggestion with clamping"]

key-files:
  created:
    - mcp-server/tools/diagnose-failure.ts
    - mcp-server/tests/diagnose-failure.test.ts
  modified: []

key-decisions:
  - "Classification priority: synthesis > placement_overflow > congestion > drc > timing_violation > unknown"
  - "Sequential vs combinational timing distinguished by SDC virtual_clk pattern"

patterns-established:
  - "Error classification via regex priority chain with structured DiagnosisResult return type"
  - "Parameter suggestion with min/max clamping to prevent unreasonable values"

requirements-completed: [DIAG-01, DIAG-02, RETRY-01]

duration: 4min
completed: 2026-04-02
---

# Phase 16 Plan 01: Diagnose Failure Tool Summary

**diagnose_failure MCP tool classifying 5 ORFS error types with bounded parameter suggestions and restart-from stage mapping**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-02T07:39:15Z
- **Completed:** 2026-04-02T07:43:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- diagnose_failure MCP tool classifies timing_violation, congestion, drc, placement_overflow, synthesis_error
- Silent timing detection: success=true + WNS < 0 correctly identified
- Sequential vs combinational timing distinction via SDC content analysis
- 26 unit tests covering all error types, severity, bounds clamping, and restart_from mapping

## Task Commits

Each task was committed atomically:

1. **Task 1: Create diagnose-failure test file** - `05f8e80` (test)
2. **Task 2: Implement diagnose-failure tool** - `571457b` (feat)

## Files Created/Modified
- `mcp-server/tools/diagnose-failure.ts` - Error classification, parameter suggestions, MCP tool registration
- `mcp-server/tests/diagnose-failure.test.ts` - 26 unit tests covering all classification and suggestion logic

## Decisions Made
- Classification priority order: synthesis_error first (most specific), unknown last (fallback)
- Sequential vs combinational distinguished by presence of "virtual_clk" in SDC content
- Parameter bounds: clock_period [1.0, 100.0], place_density [0.30, 0.85], core_utilization [20, 70]

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- diagnose_failure tool ready for registration in MCP server index.ts
- classifyError and suggestParams exported for use by Phase 17 retry skill
- All 62 existing tests still pass (no regressions)

---
*Phase: 16-diagnosis-retry-infrastructure*
*Completed: 2026-04-02*
