---
phase: 11-openroad-pnr-gds-export
plan: 01
subsystem: backend-pnr
tags: [openroad, klayout, pnr, gds, nangate45, physical-design]

# Dependency graph
requires:
  - phase: 10-yosys-synthesis
    provides: gate-level netlists in workspace/pnr/<Module>.synth.v
  - phase: 09-pdk-sdc-infrastructure
    provides: SDC constraints, PDK validation, environment detection
provides:
  - scripts/pnr.sh bash wrapper for full PnR + GDS pipeline
  - scripts/pnr.tcl OpenROAD Tcl recipe with conditional CTS and auto-sizing
  - scripts/def2gds.py KLayout DEF-to-GDS merge script
  - Routed DEF and GDS output for any synthesized module
  - Timing/power/area reports in workspace/pnr/reports/
affects: [workflow-skill, phase-12-if-any]

# Tech tracking
tech-stack:
  added: [openroad-26Q1, klayout-0.30.7-pya]
  patterns: [three-file-architecture-pnr, marker-based-report-extraction, auto-die-sizing, conditional-cts]

key-files:
  created:
    - scripts/pnr.tcl
    - scripts/def2gds.py
    - scripts/pnr.sh
  modified: []

key-decisions:
  - "Auto-size die area: <100 cells uses 70x70um floor, >=100 uses 30% utilization"
  - "Report capture via OpenROAD -log with marker-delimited sections extracted by sed"
  - "CTS conditionally skipped for combinational modules based on IS_SEQUENTIAL flag"
  - "KLayout DEF loading uses LEF files via layoutOptions, not .lyt tech file"

patterns-established:
  - "Three-file PnR architecture: pnr.sh (orchestrator) + pnr.tcl (OpenROAD recipe) + def2gds.py (KLayout merge)"
  - "Marker-delimited report extraction from OpenROAD log (TIMING_REPORT_START/END pattern)"
  - "Auto-sizing die area with minimum floor for small modules to prevent PDN failure"

requirements-completed: [PNR-01, PNR-02, PNR-03, GDS-01]

# Metrics
duration: 15min
completed: 2026-04-01
---

# Phase 11 Plan 01: OpenROAD PnR + GDS Export Summary

**OpenROAD PnR pipeline with conditional CTS and KLayout GDS export for nangate45, verified on ALU (combinational) and Counter8 (sequential)**

## Performance

- **Duration:** 15 min
- **Started:** 2026-04-01T08:56:37Z
- **Completed:** 2026-04-01T09:12:31Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Complete PnR pipeline: floorplan, placement, CTS (conditional), routing, extraction, reports, GDS export
- ALU (492 cells, combinational): timing MET (WNS 0.458ns), 517um2 area, 543KB GDS, no clock buffers
- Counter8 (28 cells, sequential): timing MET (WNS 1.439ns), 62um2 area, 129KB GDS, clock buffers from CTS
- Auto-sizing die area handles both small (<100 cells) and normal modules without manual configuration

## Task Commits

Each task was committed atomically:

1. **Task 1: Create pnr.tcl and def2gds.py** - `6a7f858` (feat)
2. **Task 2: Create pnr.sh with end-to-end verification** - `b22b9ee` (feat)

## Files Created/Modified
- `scripts/pnr.tcl` - OpenROAD Tcl PnR recipe with conditional CTS, auto-sizing, marker-delimited reports
- `scripts/def2gds.py` - KLayout Python script for DEF-to-GDS merge via pya API with LEF-based loading
- `scripts/pnr.sh` - Bash wrapper orchestrating OpenROAD PnR and KLayout GDS export

## Decisions Made
- Auto-size die area: <100 cells uses explicit 70x70um minimum (prevents PDN-0185 metal4 stripe failure), >=100 cells uses utilization-based sizing at 30%
- Report capture via OpenROAD `-log` with marker extraction (26Q1 does not support `-file` on report commands or `redirect`)
- CTS skip for combinational modules controlled by IS_SEQUENTIAL environment variable
- KLayout DEF loading uses LEF files via `layoutOptions.lefdef_config.lef_files` (not `.lyt` tech file which produces dummy macros)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - both modules completed end-to-end on first run.

## User Setup Required

None - no external service configuration required. OpenROAD 26Q1, KLayout 0.30.7, and nangate45 PDK are pre-installed.

## Next Phase Readiness
- PnR pipeline complete for any synthesized module
- GDS export verified for both combinational and sequential designs
- Reports (timing, power, area) available for quality analysis
- Ready for integration into the full workflow skill pipeline

## Self-Check: PASSED

All created files exist. All commit hashes verified in git log.

---
*Phase: 11-openroad-pnr-gds-export*
*Completed: 2026-04-01*
