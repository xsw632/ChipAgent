---
phase: 14-config-generation-orfs-stage-execution
plan: 01
subsystem: mcp
tags: [orfs, config-mk, sdc, sky130hd, mcp-tool]

requires:
  - phase: 13-mcp-server-environment-foundation
    provides: MCP server framework, check_environment tool, findOrfs pattern
provides:
  - generate_config MCP tool producing config.mk and constraint.sdc
  - Pure functions generateConfigMk() and generateSdc() for reuse
affects: [14-02, pnr-flow, orfs-make-stages]

tech-stack:
  added: []
  patterns: [sequential-vs-combinational SDC detection, ORFS config.mk format]

key-files:
  created: [mcp-server/tools/generate-config.ts, mcp-server/tests/generate-config.test.ts]
  modified: [mcp-server/index.ts]

key-decisions:
  - "Extract module name from Verilog content via regex, not from parameter"
  - "Detect sequential vs combinational via always @(posedge pattern"
  - "Export pure functions for testability, register wrapper for MCP"

patterns-established:
  - "TDD pure functions pattern: export logic functions separately from MCP registration"
  - "SDC generation pattern: sequential gets real clock, combinational gets virtual clock"

requirements-completed: [MCP-03, CFG-01, CFG-02]

duration: 2min
completed: 2026-04-02
---

# Phase 14 Plan 01: Config Generation Summary

**generate_config MCP tool producing ORFS config.mk and constraint.sdc with sequential/combinational clock detection, 10 passing tests**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-02T03:13:16Z
- **Completed:** 2026-04-02T03:15:13Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- generate_config MCP tool with Zod-validated parameters and file output
- Pure generateConfigMk() producing DESIGN_NAME, PLATFORM=sky130hd, VERILOG_FILES, SDC_FILE, CORE_UTILIZATION, TNS_END_PERCENT
- Pure generateSdc() with sequential (real clock on port) vs combinational (virtual clock + set_max_delay) detection
- 10 unit tests covering all parameter combinations

## Task Commits

Each task was committed atomically:

1. **Task 1: Create generate-config tool with tests** - `3b4fc3b` (feat)
2. **Task 2: Register generate_config in MCP server** - `930cf1a` (feat)

## Files Created/Modified
- `mcp-server/tools/generate-config.ts` - generate_config MCP tool with pure functions
- `mcp-server/tests/generate-config.test.ts` - 10 unit tests for config and SDC generation
- `mcp-server/index.ts` - Added import and registration of generate_config

## Decisions Made
- Extract module name from Verilog content regex (`^module \w+`) rather than trusting the module_name parameter
- Detect sequential circuits via `always @(posedge` regex pattern
- Export pure functions (generateConfigMk, generateSdc) for direct testing without MCP overhead

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- generate_config tool ready for ORFS make flow integration
- config.mk and constraint.sdc written to {workspace_dir}/pnr/ as expected by ORFS

---
*Phase: 14-config-generation-orfs-stage-execution*
*Completed: 2026-04-02*
