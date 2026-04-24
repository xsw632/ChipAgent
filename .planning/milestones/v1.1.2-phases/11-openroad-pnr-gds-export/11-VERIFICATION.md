---
phase: 11-openroad-pnr-gds-export
verified: 2026-04-01T17:30:00Z
status: passed
score: 5/5 must-haves verified
---

# Phase 11: OpenROAD PnR + GDS Export Verification Report

**Phase Goal:** A synthesized netlist is physically implemented through floorplan, placement, CTS, and routing, producing a routed DEF, GDS, and physical design reports
**Verified:** 2026-04-01T17:30:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Running scripts/pnr.sh ALU produces a routed DEF and GDS for a combinational module | VERIFIED | ALU.routed.def (273KB), ALU.gds (543KB) exist in MyDesign/ALU/workspace/pnr/ |
| 2 | Running scripts/pnr.sh Counter8 produces a routed DEF and GDS for a sequential module | VERIFIED | Counter8.routed.def (89KB), Counter8.gds (129KB) exist in MyDesign/Counter8/workspace/pnr/ |
| 3 | Timing report shows WNS/slack; power report shows breakdown; area report shows utilization | VERIFIED | timing.rpt has 1 "slack" match, area.rpt has "Design area", power.rpt has 2 power-related lines |
| 4 | Die area is automatically sized without manual configuration | VERIFIED | pnr.tcl lines 31-43: cell count < 100 uses 70x70um floor, else utilization-based 30% |
| 5 | Combinational modules have no clock buffers; sequential modules have clock buffers from CTS | VERIFIED | ALU.routed.def: 0 clkbuf matches; Counter8.routed.def: 7 clkbuf matches |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/pnr.tcl` | OpenROAD Tcl PnR recipe with conditional CTS (min 50 lines, contains "initialize_floorplan") | VERIFIED | 115 lines, contains initialize_floorplan (line 36/41), conditional CTS (line 64-71), marker reports |
| `scripts/def2gds.py` | KLayout DEF-to-GDS merge via pya API (min 25 lines, contains "pya.Layout") | VERIFIED | 57 lines, contains pya.Layout (line 25), lefdef_config.lef_files (line 23) |
| `scripts/pnr.sh` | Bash wrapper orchestrating PnR + GDS (min 80 lines, contains "openroad") | VERIFIED | 223 lines, executable, contains openroad invocation (line 134), klayout invocation (lines 177-184) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| scripts/pnr.sh | scripts/pnr.tcl | openroad invocation with env vars | WIRED | Line 134: `openroad -no_init -exit -log "$LOG_FILE" "$PLUGIN_ROOT/scripts/pnr.tcl"` |
| scripts/pnr.sh | scripts/def2gds.py | klayout -zz -r invocation with -rd params | WIRED | Lines 177-184: klayout invocation with -rd parameters and -r def2gds.py |
| scripts/pnr.tcl | PDK platform files | source env(PDK_DIR)/*.tcl | WIRED | Lines 45-46: make_tracks.tcl, grid_strategy; Line 61: setRC.tcl |
| scripts/pnr.sh | scripts/validate-pdk.sh | pre-flight validation call | WIRED | Line 65: `bash "$PLUGIN_ROOT/scripts/validate-pdk.sh"` |
| scripts/pnr.sh | workspace/pnr/reports/ | sed extraction with markers | WIRED | Lines 161-168: TIMING_REPORT_START/END, POWER_REPORT_START/END, AREA_REPORT_START/END |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| PNR-01 | 11-01-PLAN | pnr.sh runs full OpenROAD flow, outputs routed DEF | SATISFIED | ALU.routed.def and Counter8.routed.def both exist with non-trivial sizes |
| PNR-02 | 11-01-PLAN | Timing (WNS/TNS), power, and area reports in workspace/pnr/reports/ | SATISFIED | timing.rpt, power.rpt, area.rpt all present and non-empty for both modules |
| PNR-03 | 11-01-PLAN | Smart defaults: auto-size die area, skip CTS for combinational | SATISFIED | pnr.tcl auto-sizes (lines 31-43), CTS conditional on IS_SEQUENTIAL; ALU has 0 clkbuf, Counter8 has 7 |
| GDS-01 | 11-01-PLAN | KLayout DEF-to-GDS merge produces final GDS | SATISFIED | ALU.gds (543KB) and Counter8.gds (129KB) both exist and are non-zero |

No orphaned requirements found -- all 4 IDs (PNR-01, PNR-02, PNR-03, GDS-01) mapped to Phase 11 in REQUIREMENTS.md are claimed by 11-01-PLAN.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | - | - | - | No TODO/FIXME/PLACEHOLDER/HACK patterns found in any created file |

### Human Verification Required

### 1. End-to-end PnR on a new module

**Test:** Run `bash scripts/pnr.sh <NewModule>` on a freshly synthesized module not yet PnR'd
**Expected:** Produces routed DEF, GDS, and 3 report files without errors
**Why human:** Verifies the pipeline generalizes beyond the two tested modules

### 2. Timing report correctness

**Test:** Open MyDesign/ALU/workspace/pnr/reports/timing.rpt and check WNS/slack values are physically plausible
**Expected:** Non-negative WNS for ALU (purely combinational, relaxed constraint), plausible path delay
**Why human:** Cannot programmatically assess whether timing values are physically reasonable

### 3. GDS visual inspection

**Test:** Open ALU.gds and Counter8.gds in KLayout GUI and verify cells have real geometry
**Expected:** Standard cells visible with metal routing, no empty bounding boxes
**Why human:** Programmatic checks confirm file exists and size, but not visual correctness

### Gaps Summary

No gaps found. All 5 observable truths verified, all 3 artifacts pass all three levels (exists, substantive, wired), all 5 key links confirmed, all 4 requirements satisfied. Both commit hashes (6a7f858, b22b9ee) verified in git log.

---

_Verified: 2026-04-01T17:30:00Z_
_Verifier: Claude (gsd-verifier)_
