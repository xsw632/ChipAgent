# Phase 11: OpenROAD PnR + GDS Export - Research

**Researched:** 2026-04-01
**Domain:** OpenROAD physical design (floorplan, placement, CTS, routing), KLayout GDS stream-out
**Confidence:** HIGH

## Summary

Phase 11 creates `scripts/pnr.sh` and `scripts/pnr.tcl` that run the full OpenROAD physical design flow on a Yosys-synthesized gate-level netlist, plus `scripts/def2gds.py` for KLayout-based GDS export. The flow was verified end-to-end on both ALU (combinational, 492 cells) and Counter8 (sequential, 28 cells) producing routed DEF files, timing/power/area reports, and GDS files. Both flows complete in under 30 seconds total.

The architecture follows the established two-file pattern from Phase 10 (synth.sh + synth.tcl): a bash wrapper (`pnr.sh`) handles path resolution, pre-flight validation, sequential/combinational detection, and environment setup, while a Tcl script (`pnr.tcl`) contains the OpenROAD PnR recipe. KLayout GDS export is handled by a separate Python script (`def2gds.py`) invoked via `klayout -zz -r`. The bash wrapper orchestrates all three stages.

Critical findings from live testing: (1) Very small modules (<100 cells like Counter8) fail PDN generation if utilization is set too high -- the die area becomes too small for nangate45 metal4 power stripes (56um pitch). A minimum die area of ~70x70um is needed. The solution is auto-sizing logic that uses a minimum floor for small modules. (2) CTS skip for combinational modules works correctly -- simply omitting `clock_tree_synthesis` and related commands produces clean timing with virtual clocks. (3) OpenROAD `report_power` and `report_design_area` print to stdout but return empty Tcl strings, so reports must be captured via the `-log` flag with marker-delimited sections and post-processed by the bash wrapper. (4) KLayout DEF-to-GDS merge requires LEF files passed via `layoutOptions.lefdef_config.lef_files`, NOT the `.lyt` tech file alone.

**Primary recommendation:** Create `scripts/pnr.sh` (bash wrapper), `scripts/pnr.tcl` (OpenROAD Tcl recipe with conditional CTS), and `scripts/def2gds.py` (KLayout Python merge script). The bash wrapper detects sequential vs combinational from the Verilog (reusing the Phase 9 `always @(posedge` heuristic), sets environment variables including IS_SEQUENTIAL flag, invokes OpenROAD with `-log` for report capture, post-processes the log to extract timing/power/area reports, then runs KLayout for GDS export.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PNR-01 | `scripts/pnr.sh <ModuleName>` runs full OpenROAD flow (floorplan, place, CTS, route) in single session, outputs routed DEF | Verified complete flow: `read_liberty` + `read_lef` + `read_verilog` + `link_design` + `read_sdc` + `initialize_floorplan` + `make_tracks` + `pdngen` + `tapcell` + `place_pins` + `global_placement` + `detailed_placement` + CTS (conditional) + `global_route` + `detailed_route` + `filler_placement` + `extract_parasitics` + `write_def`. Tested on ALU (comb) and Counter8 (seq). |
| PNR-02 | Timing (WNS/TNS), power (internal/switching/leakage), and area reports in `workspace/pnr/reports/` | Verified: `report_checks` for timing, `sta::worst_slack_cmd`/`sta::total_negative_slack_cmd` for WNS/TNS values, `report_power` for internal/switching/leakage breakdown, `report_design_area` for cell area and utilization. Reports captured via `-log` with markers and post-processed by bash. |
| PNR-03 | Smart defaults: auto-size die area from synthesis cell count, skip CTS for combinational modules | Verified: `initialize_floorplan -utilization 30` auto-sizes for normal modules; explicit die_area override (min 70x70um) for <100 cell modules to avoid PDN failure. CTS skip verified: omitting `clock_tree_synthesis` for combinational modules produces correct timing with virtual clocks. |
| GDS-01 | KLayout DEF-to-GDS merge produces final `<Module>.gds` in `workspace/pnr/` | Verified: KLayout 0.30.7 `pya` Python API reads DEF with LEF layout options, merges nangate45 GDS cells, writes output GDS. ALU.gds = 549KB, Counter8.gds = 129KB. No empty cell errors when LEF files are provided. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| OpenROAD | 26Q1-951 | Full physical design flow (floorplan through routing) | Installed at `/usr/bin/openroad`, verified on both module types |
| KLayout | 0.30.7 | DEF-to-GDS stream-out via Python API | Installed at `/usr/bin/klayout`, has `pya` Python module |
| nangate45 PDK | ORFS bundled | Standard cells, LEF, GDS, RC extraction rules | At `$PDK_DIR` resolved by env.json |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| synth.sh (Phase 10) | Produces gate-level netlist consumed by pnr.sh | Must run before pnr.sh |
| generate_sdc.sh (Phase 9) | Produces SDC constraints consumed by OpenROAD | Called by synth.sh; SDC at `workspace/pnr/constraint.sdc` |
| validate-pdk.sh (Phase 9) | Pre-flight PDK file validation | Called by pnr.sh before OpenROAD invocation |
| _common.sh | Plugin root path resolution | Sourced by pnr.sh |
| jq | Read PDK path from env.json | PDK path resolution in pnr.sh |

### nangate45 Platform Files Used

| File | Path (relative to PDK_DIR) | Purpose |
|------|----------------------------|---------|
| Liberty | `lib/NangateOpenCellLibrary_typical.lib` | Timing/power data for STA |
| Tech LEF | `lef/NangateOpenCellLibrary.tech.lef` | Metal layers, routing rules |
| Cell LEF | `lef/NangateOpenCellLibrary.macro.mod.lef` | Standard cell geometries |
| Cell GDS | `gds/NangateOpenCellLibrary.gds` | Cell layouts for GDS merge |
| RCX rules | `rcx_patterns.rules` | Parasitic extraction model |
| PDN grid | `grid_strategy-M1-M4-M7.tcl` | VDD/VSS power grid definition |
| Tracks | `make_tracks.tcl` | Metal layer routing track definitions |
| RC values | `setRC.tcl` | Per-layer resistance/capacitance values |
| Fastroute | `fastroute.tcl` | Global routing layer adjustments |
| Tapcell | `tapcell.tcl` | Tapcell/endcap insertion config |

### No New Dependencies

This phase adds no new software. OpenROAD 26Q1, KLayout 0.30.7, and all PDK files are already installed and detected by Phase 9.

## Architecture Patterns

### Recommended Project Structure Changes

```
scripts/
  pnr.sh                # NEW: Bash wrapper for PnR pipeline
  pnr.tcl               # NEW: OpenROAD Tcl script for physical design
  def2gds.py            # NEW: KLayout Python script for DEF-to-GDS merge
  synth.sh              # EXISTING (Phase 10): called by pnr.sh if netlist missing
  validate-pdk.sh       # EXISTING (Phase 9): called by pnr.sh
  generate_sdc.sh       # EXISTING (Phase 9): SDC already at workspace/pnr/constraint.sdc
  _common.sh            # EXISTING: shared path resolution
MyDesign/<Module>/
  workspace/
    pnr/
      <Module>.synth.v         # From Phase 10 (input)
      constraint.sdc           # From Phase 9 (input)
      <Module>.routed.def      # NEW: routed DEF output (PNR-01)
      <Module>.gds             # NEW: final GDS output (GDS-01)
      reports/
        synth_stat.txt         # From Phase 10 (existing)
        synth_check.txt        # From Phase 10 (existing)
        timing.rpt             # NEW: timing report (PNR-02)
        power.rpt              # NEW: power report (PNR-02)
        area.rpt               # NEW: area report (PNR-02)
```

### Pattern 1: Three-File Architecture (pnr.sh + pnr.tcl + def2gds.py)

**What:** Separate bash orchestration, OpenROAD recipe, and KLayout merge into three files.

**Why this pattern:**
- pnr.sh handles all ChipAgent-specific concerns (path resolution, sequential detection, report extraction)
- pnr.tcl is a pure OpenROAD recipe that could be run standalone for debugging
- def2gds.py is a pure KLayout script that could be run standalone for debugging
- Same pattern as Phase 10 (synth.sh + synth.tcl), extended with one more tool

**Environment variables passed from pnr.sh to pnr.tcl:**

| Variable | Value | Example |
|----------|-------|---------|
| `DESIGN_NAME` | Module name from Verilog | `ALU` |
| `NETLIST` | Path to gate-level netlist | `.../workspace/pnr/ALU.synth.v` |
| `SDC_FILE` | Path to SDC constraints | `.../workspace/pnr/constraint.sdc` |
| `LIB_FILE` | Path to nangate45 liberty | `$PDK_DIR/lib/NangateOpenCellLibrary_typical.lib` |
| `TECH_LEF` | Path to tech LEF | `$PDK_DIR/lef/NangateOpenCellLibrary.tech.lef` |
| `CELL_LEF` | Path to cell LEF | `$PDK_DIR/lef/NangateOpenCellLibrary.macro.mod.lef` |
| `PDK_DIR` | nangate45 platform directory | `/home/.../flow/platforms/nangate45` |
| `OUTPUT_DIR` | Path to workspace/pnr/ | `.../workspace/pnr` |
| `REPORTS_DIR` | Path to workspace/pnr/reports/ | `.../workspace/pnr/reports` |
| `IS_SEQUENTIAL` | "1" or "0" | "0" for ALU, "1" for Counter8 |
| `RCX_RULES` | Path to RC extraction rules | `$PDK_DIR/rcx_patterns.rules` |

**Environment variables for def2gds.py (passed via KLayout -rd):**

| Variable | Value | Example |
|----------|-------|---------|
| `design_name` | Module name | `ALU` |
| `in_def` | Path to routed DEF | `.../workspace/pnr/ALU.routed.def` |
| `tech_lef` | Path to tech LEF | `$PDK_DIR/lef/NangateOpenCellLibrary.tech.lef` |
| `cell_lef` | Path to cell LEF | `$PDK_DIR/lef/NangateOpenCellLibrary.macro.mod.lef` |
| `in_gds` | Path to nangate45 cell GDS | `$PDK_DIR/gds/NangateOpenCellLibrary.gds` |
| `out_file` | Path to output GDS | `.../workspace/pnr/ALU.gds` |

### Pattern 2: pnr.sh Bash Wrapper

**What:** `scripts/pnr.sh <ModuleName>` orchestrates the full PnR + GDS flow.

**Key steps:**
1. Source `_common.sh` for PLUGIN_ROOT
2. Resolve module path (bare name, MyDesign/Module, etc.) -- same as synth.sh
3. Verify synthesized netlist exists at `workspace/pnr/<Module>.synth.v`
4. Verify SDC exists at `workspace/pnr/constraint.sdc`
5. Call `validate-pdk.sh` (exit on failure)
6. Read PDK path from env.json (or env var fallback)
7. Detect sequential vs combinational from Verilog (`always @(posedge`)
8. Set environment variables for Tcl script
9. Create `workspace/pnr/reports/` directory
10. Invoke `openroad -no_init -exit -log <logfile> pnr.tcl`
11. Check exit code; on failure, show log tail
12. Verify routed DEF exists
13. Extract reports from OpenROAD log (timing, power, area) using sed/grep with markers
14. Invoke `klayout -zz -r def2gds.py` for GDS export
15. Verify GDS exists
16. Print summary (WNS, TNS, area, power, file paths)

### Pattern 3: pnr.tcl OpenROAD Recipe

**What:** Standalone OpenROAD Tcl script that performs the complete physical design flow.

**Verified pipeline (tested on ALU and Counter8):**

```tcl
# ===== LOAD =====
read_liberty $::env(LIB_FILE)
read_lef $::env(TECH_LEF)
read_lef $::env(CELL_LEF)
read_verilog $::env(NETLIST)
link_design $::env(DESIGN_NAME)
read_sdc $::env(SDC_FILE)

# ===== FLOORPLAN =====
# Auto-size with minimum floor for small modules
set num_cells [llength [get_cells -hier *]]
if {$num_cells < 100} {
  initialize_floorplan -die_area "0 0 70 70" \
    -core_area "5 5 65 65" \
    -site FreePDK45_38x28_10R_NP_162NW_34O
} else {
  initialize_floorplan -utilization 30 -aspect_ratio 1 \
    -core_space 5 -site FreePDK45_38x28_10R_NP_162NW_34O
}

source $::env(PDK_DIR)/make_tracks.tcl
source $::env(PDK_DIR)/grid_strategy-M1-M4-M7.tcl
pdngen
set TAP_CELL_NAME "TAPCELL_X1"
tapcell -distance 120 -tapcell_master $TAP_CELL_NAME \
  -endcap_master $TAP_CELL_NAME
place_pins -hor_layers metal5 -ver_layers metal6

# ===== PLACEMENT =====
global_placement -density 0.3
detailed_placement
check_placement -verbose

# ===== RC + CTS =====
source $::env(PDK_DIR)/setRC.tcl
estimate_parasitics -placement

if {$::env(IS_SEQUENTIAL)} {
  repair_clock_inverters
  clock_tree_synthesis -sink_clustering_enable
  detailed_placement
  estimate_parasitics -placement
  repair_timing
  detailed_placement
}

# ===== ROUTING =====
set_global_routing_layer_adjustment metal2-metal3 0.5
set_global_routing_layer_adjustment metal4-metal10 0.25
set_routing_layers -signal metal2-metal10
if {$::env(IS_SEQUENTIAL)} {
  set_routing_layers -clock metal4-metal10
}
global_route

set_propagated_clock [all_clocks]
detailed_route -output_drc $::env(REPORTS_DIR)/drc.rpt -verbose 1

# ===== POST-ROUTE =====
filler_placement "FILLCELL_X1 FILLCELL_X2 FILLCELL_X4 FILLCELL_X8 FILLCELL_X16 FILLCELL_X32"
check_placement

# ===== EXTRACTION =====
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file $::env(RCX_RULES)

# ===== REPORTS =====
puts "=== TIMING_REPORT_START ==="
report_checks -path_delay max -format full_clock_expanded
puts "=== TIMING_REPORT_END ==="

puts "=== POWER_REPORT_START ==="
report_power
puts "=== POWER_REPORT_END ==="

puts "=== AREA_REPORT_START ==="
report_design_area
puts "=== AREA_REPORT_END ==="

# WNS/TNS via STA internal API
set wns_val [sta::format_time [sta::worst_slack_cmd max] 3]
set tns_val [sta::format_time [sta::total_negative_slack_cmd max] 3]
puts "WNS: $wns_val"
puts "TNS: $tns_val"

# ===== OUTPUT =====
write_def $::env(OUTPUT_DIR)/$::env(DESIGN_NAME).routed.def
```

### Pattern 4: def2gds.py KLayout Script

**What:** KLayout Python script that merges routed DEF with nangate45 cell GDS.

**Verified approach (tested on both ALU and Counter8):**

```python
import pya
import os
import sys

# Variables passed via klayout -rd
# design_name, in_def, tech_lef, cell_lef, in_gds, out_file

layoutOptions = pya.LoadLayoutOptions()
layoutOptions.lefdef_config.lef_files = [tech_lef, cell_lef]

main_layout = pya.Layout()
main_layout.read(in_def, layoutOptions)

top_cell_index = main_layout.cell(design_name).cell_index()

for i in main_layout.each_cell():
    if i.cell_index() != top_cell_index:
        if not i.name.startswith("VIA_"):
            i.clear()

main_layout.read(in_gds)

top_only_layout = pya.Layout()
top_only_layout.dbu = main_layout.dbu
top = top_only_layout.create_cell(design_name)
top.copy_tree(main_layout.cell(design_name))

errors = 0
for i in top_only_layout.each_cell():
    if i.is_empty():
        print(f"[WARNING] Empty cell: {i.name}")
        errors += 1

top_only_layout.write(out_file)
sys.exit(errors)
```

**KLayout invocation from pnr.sh:**
```bash
klayout -zz \
  -rd design_name="$DESIGN_NAME" \
  -rd in_def="$OUTPUT_DIR/$DESIGN_NAME.routed.def" \
  -rd tech_lef="$TECH_LEF" \
  -rd cell_lef="$CELL_LEF" \
  -rd in_gds="$PDK_DIR/gds/NangateOpenCellLibrary.gds" \
  -rd out_file="$OUTPUT_DIR/$DESIGN_NAME.gds" \
  -r "$PLUGIN_ROOT/scripts/def2gds.py"
```

### Pattern 5: Report Extraction from OpenROAD Log

**What:** OpenROAD report commands (`report_power`, `report_design_area`, `report_tns`, `report_wns`) print to stdout but return empty Tcl strings. The pnr.tcl script prints delimited markers around each report section. The pnr.sh bash wrapper runs OpenROAD with `-log` flag and extracts report sections using `sed`.

**Why this approach:** OpenROAD 26Q1 does not support `-file` on `report_checks` or `report_power`. The `redirect` command is also unavailable. The only reliable mechanism is the `-log` flag combined with marker-based extraction.

**Extraction in pnr.sh:**
```bash
# Run OpenROAD with log capture
openroad -no_init -exit -log "$LOG_FILE" "$PLUGIN_ROOT/scripts/pnr.tcl"

# Extract reports from log
sed -n '/=== TIMING_REPORT_START ===/,/=== TIMING_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "===" > "$REPORTS_DIR/timing.rpt"

sed -n '/=== POWER_REPORT_START ===/,/=== POWER_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "===" > "$REPORTS_DIR/power.rpt"

sed -n '/=== AREA_REPORT_START ===/,/=== AREA_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "===" > "$REPORTS_DIR/area.rpt"

# Extract WNS/TNS from log
WNS=$(grep '^WNS:' "$LOG_FILE" | awk '{print $2}')
TNS=$(grep '^TNS:' "$LOG_FILE" | awk '{print $2}')
```

### Pattern 6: Auto-Sizing Die Area (PNR-03)

**What:** Automatically determine die area from synthesis cell count, with a minimum floor to prevent PDN failures.

**Why needed:** The nangate45 PDN grid (`grid_strategy-M1-M4-M7.tcl`) uses metal4 stripes with a 56um pitch. If the die width is less than ~60um (from total stripe width + offset), `pdngen` fails with `PDN-0185: Insufficient width`. This happens for very small modules (<100 cells like Counter8 with 28 cells).

**Verified approach:**
```tcl
set num_cells [llength [get_cells -hier *]]
if {$num_cells < 100} {
  # Small module: use explicit minimum die area (70x70um)
  # Ensures PDN metal4 stripes (56um pitch) fit
  initialize_floorplan -die_area "0 0 70 70" \
    -core_area "5 5 65 65" \
    -site FreePDK45_38x28_10R_NP_162NW_34O
} else {
  # Normal module: utilization-based auto-sizing
  # 30% utilization gives ~3.3x area overhead for routing
  initialize_floorplan -utilization 30 -aspect_ratio 1 \
    -core_space 5 -site FreePDK45_38x28_10R_NP_162NW_34O
}
```

**Why 30% utilization:** Provides generous routing space. Higher utilization (40-50%) can cause congestion for modules with wide buses. Lower (20-25%) wastes area. 30% is the sweet spot for small Chisel modules.

**Why 70x70um minimum:** The PDN metal4 stripe offset is 2um with a 0.48um width and 56um pitch. A die width of 70um accommodates one full stripe and the offset. Testing confirmed 70um works while 12um (Counter8 at 40% util) fails.

### Pattern 7: CTS Skip for Combinational Modules (PNR-03)

**What:** Conditionally skip CTS and clock-routing configuration for combinational modules.

**Verified approach:** The `IS_SEQUENTIAL` environment variable (set by pnr.sh from Verilog analysis) controls CTS in pnr.tcl:

```tcl
if {$::env(IS_SEQUENTIAL)} {
  # Full CTS flow
  repair_clock_inverters
  clock_tree_synthesis -sink_clustering_enable
  detailed_placement
  estimate_parasitics -placement
  repair_timing
  detailed_placement
}
```

**Also conditional:** Clock routing layer setting
```tcl
if {$::env(IS_SEQUENTIAL)} {
  set_routing_layers -clock metal4-metal10
}
```

**Why this works:** Combinational modules have only a virtual clock in SDC. There are no clock sinks (flip-flops) to drive. `clock_tree_synthesis` with 0 sinks is harmless but unnecessary. Skipping it avoids log noise and potential edge cases.

### Anti-Patterns to Avoid

- **Do not use high utilization for small modules.** Utilization of 40%+ on <100-cell modules produces die areas too small for the PDN grid. Use a minimum die area floor.
- **Do not use `report_checks -file` in OpenROAD 26Q1.** The `-file` flag does not exist in this version. Use `-log` with markers.
- **Do not use `redirect` in OpenROAD 26Q1.** The `redirect` command is not available. Use the `-log` flag approach.
- **Do not pass the `.lyt` tech file to KLayout for DEF reading.** The `.lyt` file does not contain LEF information. Instead, pass LEF files directly via `layoutOptions.lefdef_config.lef_files`.
- **Do not hardcode die area for all modules.** Use auto-sizing with utilization for normal modules, explicit minimum only for small ones.
- **Do not run `repair_timing` before CTS for sequential modules.** Timing repair needs estimated parasitics after CTS, not before.
- **Do not use `global_placement -density 0.5` or higher for small modules.** High density combined with small die area causes placement failures. Use 0.3 as the default.
- **Do not forget `set_propagated_clock [all_clocks]` before detailed routing.** Without it, clocks are treated as ideal during STA which hides timing violations.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sequential/combinational detection | Custom Verilog analysis | Reuse Phase 9 `always @(posedge` heuristic | Already proven, used by generate_sdc.sh |
| PDK validation | Inline file-exists checks | `validate-pdk.sh` (Phase 9) | Single source of truth for all PDK file validation |
| PDK path resolution | Hardcoded paths | env.json `pdk.nangate45.path` | detect-env.sh already resolves through candidate chain |
| Module path resolution | Custom path logic | Follow synth.sh/compile.sh pattern | Consistent UX across all scripts |
| Power grid definition | Custom PDN Tcl | nangate45 `grid_strategy-M1-M4-M7.tcl` | ORFS-maintained, handles VDD/VSS connections correctly |
| Track definitions | Custom make_tracks | nangate45 `make_tracks.tcl` | ORFS-maintained, correct pitch/offset per metal layer |
| RC parasitic values | Custom setRC | nangate45 `setRC.tcl` | ORFS-maintained, calibrated per-layer resistance/capacitance |
| Routing layer config | Custom fastroute | nangate45 `fastroute.tcl` | ORFS-maintained, correct layer adjustments |
| Tapcell insertion | Custom tapcell config | nangate45 `tapcell.tcl` | ORFS-maintained, correct distance and cell names |
| GDS merge logic | Custom GDS stitching | KLayout `pya` API with DEF+LEF+GDS merge | Battle-tested in ORFS, handles VIA cells and orphan cleanup |

**Key insight:** The nangate45 platform directory contains pre-configured Tcl scripts for every platform-specific aspect of the PnR flow. The pnr.tcl script should `source` these directly rather than reimplementing them. This is exactly what ORFS does.

## Common Pitfalls

### Pitfall 1: PDN Failure on Small Modules (CRITICAL)

**What goes wrong:** `pdngen` fails with `PDN-0185: Insufficient width to add straps on layer metal4` when die width is less than ~60um. This happens with Counter8 (28 cells, ~58um2 area) at 40% utilization, which produces a die of only ~12x12um.
**Why it happens:** The nangate45 PDN grid has metal4 stripes with 56um pitch and 2um offset. The total stripe width requirement exceeds the die width of small modules at high utilization.
**How to avoid:** Use a minimum die area floor of 70x70um for modules with fewer than ~100 cells. For larger modules, utilization-based sizing (30%) works correctly.
**Warning signs:** OpenROAD error `PDN-0185: Insufficient width` during pdngen.
**Verification result:** ALU (492 cells) at 40% utilization = die ~37x37um -- works. Counter8 (28 cells) at 40% = die ~12x12um -- FAILS. Counter8 at explicit 70x70um -- works.

### Pitfall 2: Report Commands Don't Return Strings (CRITICAL)

**What goes wrong:** `report_power`, `report_design_area`, `report_tns`, `report_wns` print to stdout but return empty Tcl strings. Code like `set result [report_power]` captures nothing. The `report_checks -file` flag also does not exist in OpenROAD 26Q1.
**Why it happens:** OpenROAD 26Q1 does not implement file redirect on these report commands. The `redirect` Tcl command also does not exist.
**How to avoid:** Use OpenROAD `-log` flag to capture all stdout to a log file. Print marker lines (`=== SECTION_START ===` / `=== SECTION_END ===`) around each report in pnr.tcl. Extract sections with `sed` in pnr.sh.
**Warning signs:** Report files are empty (0 bytes) or contain only the marker text.
**Verified alternative:** For WNS/TNS specifically, `sta::format_time [sta::worst_slack_cmd max] 3` returns a Tcl string that can be written to file with `puts`.

### Pitfall 3: KLayout Needs LEF Files, Not .lyt Tech File

**What goes wrong:** Using `tech.load(tech_file)` with `FreePDK45.lyt` causes KLayout to create "dummy macro" cells for every standard cell, producing a GDS with empty cell placeholders instead of real geometry.
**Why it happens:** The `.lyt` tech file contains layer mapping information but not LEF cell definitions. KLayout needs the LEF files to understand cell sizes and pin locations for DEF parsing.
**How to avoid:** Pass LEF files directly via `layoutOptions.lefdef_config.lef_files = [tech_lef, cell_lef]`.
**Warning signs:** KLayout output shows "Macro not found in LEF file: <CELLNAME> - creating dummy macro" for every cell type.

### Pitfall 4: Chisel clock/reset Ports on Combinational Modules (from Phase 9)

**What goes wrong:** Chisel `Module` generates `clock` and `reset` ports even for purely combinational designs. If PnR detects a clock port and runs CTS, it inserts buffers for 0 sinks.
**Why it happens:** Chisel's Module class unconditionally adds implicit clock and reset.
**How to avoid:** Use `always @(posedge` heuristic (not clock port presence) to detect sequential modules. Set `IS_SEQUENTIAL` environment variable for pnr.tcl to conditionally skip CTS.

### Pitfall 5: set_input_delay Warning on Clock Port

**What goes wrong:** OpenROAD warns `set_input_delay relative to a clock defined on the same port/pin not allowed` when SDC applies `set_input_delay` to `[all_inputs]` which includes the clock port.
**Why it happens:** The SDC uses `[all_inputs]` without filtering out the clock port. The `create_clock` command already constrains the clock port.
**How to avoid:** This is a WARNING, not an ERROR. It's harmless -- OpenROAD ignores the constraint on the clock port. The alternative (filtering with `lsearch`) adds complexity for no functional benefit. Accept the warning.

### Pitfall 6: DEF UNITS Mismatch Warning in KLayout

**What goes wrong:** KLayout prints `DEF UNITS does not match reader DBU` warning when reading DEF files.
**Why it happens:** OpenROAD writes DEF with `UNITS DISTANCE MICRONS 2000` (DBU = 0.0005um) while KLayout defaults to DBU = 0.001um. KLayout auto-adjusts.
**How to avoid:** This is a WARNING, not an ERROR. KLayout correctly handles the DBU conversion. The output GDS is geometrically correct. No action needed.

## Code Examples

### Complete pnr.tcl (Verified on OpenROAD 26Q1)

```tcl
# pnr.tcl - OpenROAD PnR flow for nangate45
# Environment variables set by pnr.sh:
#   DESIGN_NAME, NETLIST, SDC_FILE, LIB_FILE, TECH_LEF, CELL_LEF,
#   PDK_DIR, OUTPUT_DIR, REPORTS_DIR, IS_SEQUENTIAL, RCX_RULES

# ===== LOAD DESIGN =====
read_liberty $::env(LIB_FILE)
read_lef $::env(TECH_LEF)
read_lef $::env(CELL_LEF)
read_verilog $::env(NETLIST)
link_design $::env(DESIGN_NAME)
read_sdc $::env(SDC_FILE)

# ===== FLOORPLAN =====
set num_cells [llength [get_cells -hier *]]
puts "Cell count: $num_cells"

if {$num_cells < 100} {
  # Small module: explicit minimum die area to fit PDN grid
  initialize_floorplan -die_area "0 0 70 70" \
    -core_area "5 5 65 65" \
    -site FreePDK45_38x28_10R_NP_162NW_34O
} else {
  # Normal module: utilization-based auto-sizing
  initialize_floorplan -utilization 30 -aspect_ratio 1 \
    -core_space 5 -site FreePDK45_38x28_10R_NP_162NW_34O
}

source $::env(PDK_DIR)/make_tracks.tcl
source $::env(PDK_DIR)/grid_strategy-M1-M4-M7.tcl
pdngen

set TAP_CELL_NAME "TAPCELL_X1"
tapcell -distance 120 -tapcell_master $TAP_CELL_NAME \
  -endcap_master $TAP_CELL_NAME

place_pins -hor_layers metal5 -ver_layers metal6

# ===== PLACEMENT =====
global_placement -density 0.3
detailed_placement
check_placement -verbose

# ===== RC ESTIMATION + CTS =====
source $::env(PDK_DIR)/setRC.tcl
estimate_parasitics -placement

if {$::env(IS_SEQUENTIAL)} {
  repair_clock_inverters
  clock_tree_synthesis -sink_clustering_enable
  detailed_placement
  estimate_parasitics -placement
  repair_timing
  detailed_placement
}

# ===== ROUTING =====
set_global_routing_layer_adjustment metal2-metal3 0.5
set_global_routing_layer_adjustment metal4-metal10 0.25
set_routing_layers -signal metal2-metal10
if {$::env(IS_SEQUENTIAL)} {
  set_routing_layers -clock metal4-metal10
}
global_route

set_propagated_clock [all_clocks]
detailed_route -output_drc $::env(REPORTS_DIR)/drc.rpt -verbose 1

# ===== POST-ROUTE =====
filler_placement "FILLCELL_X1 FILLCELL_X2 FILLCELL_X4 FILLCELL_X8 FILLCELL_X16 FILLCELL_X32"
check_placement

# ===== EXTRACTION =====
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file $::env(RCX_RULES)

# ===== REPORTS (with markers for bash extraction) =====
puts "=== TIMING_REPORT_START ==="
report_checks -path_delay max -format full_clock_expanded
puts "=== TIMING_REPORT_END ==="

puts "=== POWER_REPORT_START ==="
report_power
puts "=== POWER_REPORT_END ==="

puts "=== AREA_REPORT_START ==="
report_design_area
puts "=== AREA_REPORT_END ==="

set wns_val [sta::format_time [sta::worst_slack_cmd max] 3]
set tns_val [sta::format_time [sta::total_negative_slack_cmd max] 3]
puts "PNR_WNS: $wns_val"
puts "PNR_TNS: $tns_val"

# ===== OUTPUT =====
write_def $::env(OUTPUT_DIR)/$::env(DESIGN_NAME).routed.def

puts "PNR_COMPLETE"
```

### Verified Report Output Formats

**Timing report (ALU, combinational):**
```
Startpoint: io_a[1] (input port clocked by virtual_clk)
Endpoint: io_zero (output port clocked by virtual_clk)
Path Group: virtual_clk
Path Type: max
  ...
           0.48   slack (MET)
```

**Power report format:**
```
Group                  Internal  Switching    Leakage      Total
                          Power      Power      Power      Power (Watts)
----------------------------------------------------------------
Sequential             0.00e+00   0.00e+00   0.00e+00   0.00e+00   0.0%
Combinational          8.33e-05   8.31e-05   1.29e-05   1.79e-04 100.0%
Clock                  0.00e+00   0.00e+00   0.00e+00   0.00e+00   0.0%
Macro                  0.00e+00   0.00e+00   0.00e+00   0.00e+00   0.0%
Pad                    0.00e+00   0.00e+00   0.00e+00   0.00e+00   0.0%
----------------------------------------------------------------
Total                  8.33e-05   8.31e-05   1.29e-05   1.79e-04 100.0%
                          46.5%      46.3%       7.2%
```

**Area report format:**
```
Design area 517 um^2 41% utilization.
```

**Timing summary (Counter8, sequential):**
```
WNS: 1.440
TNS: 0.000
```

### pnr.sh Report Extraction Pattern

```bash
# Extract timing report
sed -n '/=== TIMING_REPORT_START ===/,/=== TIMING_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "^=== " > "$REPORTS_DIR/timing.rpt"

# Extract power report
sed -n '/=== POWER_REPORT_START ===/,/=== POWER_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "^=== " > "$REPORTS_DIR/power.rpt"

# Extract area report
sed -n '/=== AREA_REPORT_START ===/,/=== AREA_REPORT_END ===/p' "$LOG_FILE" \
  | grep -v "^=== " > "$REPORTS_DIR/area.rpt"

# Extract WNS/TNS
WNS=$(grep '^PNR_WNS:' "$LOG_FILE" | awk '{print $2}')
TNS=$(grep '^PNR_TNS:' "$LOG_FILE" | awk '{print $2}')
```

### def2gds.py Complete Script

```python
import pya
import sys
import os

# Variables passed via klayout -rd flags
# design_name, in_def, tech_lef, cell_lef, in_gds, out_file

# Load DEF with LEF context
layoutOptions = pya.LoadLayoutOptions()
layoutOptions.lefdef_config.lef_files = [tech_lef, cell_lef]

main_layout = pya.Layout()
main_layout.read(in_def, layoutOptions)

top_cell_index = main_layout.cell(design_name).cell_index()

# Clear orphan cells (preserve VIA_ cells from DEF)
for i in main_layout.each_cell():
    if i.cell_index() != top_cell_index:
        if not i.name.startswith("VIA_"):
            i.clear()

# Merge standard cell GDS
main_layout.read(in_gds)

# Copy to clean layout
top_only_layout = pya.Layout()
top_only_layout.dbu = main_layout.dbu
top = top_only_layout.create_cell(design_name)
top.copy_tree(main_layout.cell(design_name))

# Verify all cells have geometry
errors = 0
for i in top_only_layout.each_cell():
    if i.is_empty():
        print(f"[ERROR] Empty cell: {i.name}")
        errors += 1

top_only_layout.write(out_file)
print(f"GDS written: {out_file} ({os.path.getsize(out_file)} bytes)")
sys.exit(errors)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ORFS Makefile + multi-stage ODB files | Standalone Tcl script in single OpenROAD session | v1.1.2 decision | Simpler, no ORFS runtime dependency |
| `.lyt` tech file for KLayout DEF reading | Direct LEF file passing via `layoutOptions.lefdef_config.lef_files` | Verified 2026-04-01 | Correct cell resolution without dummy macros |
| `report_checks -file` for report output | `-log` with marker extraction | Verified 2026-04-01 (26Q1 limitation) | Works around missing -file flag in 26Q1 |
| Fixed die area | Auto-sizing with minimum floor | Verified 2026-04-01 | Handles both small (28 cells) and large (492 cells) modules |

**ORFS features NOT needed for ChipAgent:**
- Multi-stage ODB checkpoint saving (single session flow is sufficient)
- Macro placement (`macro_place.tcl`) -- no SRAM or hard macros
- `repair_tie_fanout` -- Yosys netlist does not have tie cells requiring fanout repair
- `remove_buffers` / `replace_arith_modules` -- not needed for small Chisel modules
- `buffer_ports` -- small modules don't need IO buffering
- `DONT_USE_CELLS` -- not critical for small modules, can be added later
- Antenna repair -- small modules unlikely to have antenna violations
- Power grid analysis (`analyze_power_grid`) -- deferred to future requirements

## Open Questions

1. **Intermediate-sized modules (100-500 cells) die area**
   - What we know: <100 cells uses 70x70um floor; >=100 uses 30% utilization
   - What's unclear: Whether the 100-cell threshold is optimal. Some modules in the 100-200 range might need a larger floor.
   - Recommendation: Start with the 100-cell threshold. If PDN failures occur on intermediate modules, increase the threshold or add a more sophisticated area calculation.

2. **repair_timing for combinational modules**
   - What we know: CTS is skipped for combinational modules. The `repair_timing` call is inside the CTS conditional block.
   - What's unclear: Whether combinational modules benefit from post-placement `repair_timing` (buffer insertion for long wire delays).
   - Recommendation: Skip for now. ALU passes timing at 2ns with 0.48ns slack. Add if future modules show timing violations on combinational paths.

3. **DRC violations in detailed routing**
   - What we know: Detailed route produces a `drc.rpt` file. Neither ALU nor Counter8 showed violations.
   - What's unclear: Whether more complex modules would produce DRC violations.
   - Recommendation: Check DRC report in pnr.sh and warn (but don't fail) on violations. Phase 12 auto-fix can potentially address DRC issues.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash scripts + OpenROAD verification |
| Config file | none |
| Quick run command | `bash scripts/pnr.sh ALU` |
| Full suite command | `bash scripts/pnr.sh ALU && bash scripts/pnr.sh Counter8` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PNR-01 (combinational) | pnr.sh produces routed DEF for ALU | smoke | `bash scripts/pnr.sh ALU && test -f MyDesign/ALU/workspace/pnr/ALU.routed.def` | Wave 0 |
| PNR-01 (sequential) | pnr.sh produces routed DEF for Counter8 | smoke | `bash scripts/pnr.sh Counter8 && test -f MyDesign/Counter8/workspace/pnr/Counter8.routed.def` | Wave 0 |
| PNR-02 (timing) | timing.rpt contains WNS/TNS | smoke | `grep -q 'slack' MyDesign/ALU/workspace/pnr/reports/timing.rpt` | Wave 0 |
| PNR-02 (power) | power.rpt contains Internal/Switching/Leakage | smoke | `grep -q 'Internal.*Switching.*Leakage' MyDesign/ALU/workspace/pnr/reports/power.rpt` | Wave 0 |
| PNR-02 (area) | area.rpt contains cell area and utilization | smoke | `grep -q 'Design area' MyDesign/ALU/workspace/pnr/reports/area.rpt` | Wave 0 |
| PNR-03 (auto-size) | Die area auto-sized without manual config | integration | Run pnr.sh on both modules; neither requires manual die area input | Wave 0 |
| PNR-03 (CTS skip) | Combinational module has no clock buffers | integration | `grep -L 'clkbuf' MyDesign/ALU/workspace/pnr/ALU.routed.def` succeeds (no clock buffers) | Wave 0 |
| PNR-03 (CTS present) | Sequential module has clock buffers | integration | `grep -q 'clkbuf' MyDesign/Counter8/workspace/pnr/Counter8.routed.def` | Wave 0 |
| GDS-01 (combinational) | KLayout produces ALU.gds | smoke | `test -f MyDesign/ALU/workspace/pnr/ALU.gds && test -s MyDesign/ALU/workspace/pnr/ALU.gds` | Wave 0 |
| GDS-01 (sequential) | KLayout produces Counter8.gds | smoke | `test -f MyDesign/Counter8/workspace/pnr/Counter8.gds && test -s MyDesign/Counter8/workspace/pnr/Counter8.gds` | Wave 0 |

### Sampling Rate

- **Per task commit:** `bash scripts/pnr.sh ALU` (combinational quick check, ~15s)
- **Per wave merge:** `bash scripts/pnr.sh ALU && bash scripts/pnr.sh Counter8` (both types, ~30s)
- **Phase gate:** Both modules PnR + GDS complete; all report files non-empty; timing MET

### Wave 0 Gaps

- [ ] `scripts/pnr.sh` -- main PnR wrapper script
- [ ] `scripts/pnr.tcl` -- OpenROAD Tcl PnR recipe
- [ ] `scripts/def2gds.py` -- KLayout DEF-to-GDS merge script
- [ ] Both existing modules (ALU, Counter8) must have synthesized netlists in `workspace/pnr/` (already present from Phase 10)
- [ ] Both existing modules must have SDC files in `workspace/pnr/` (already present from Phase 9/10)

## Sources

### Primary (HIGH confidence)

- OpenROAD 26Q1-951 at `/usr/bin/openroad` -- full PnR flow tested end-to-end on ALU (combinational) and Counter8 (sequential). All commands verified: `initialize_floorplan`, `pdngen`, `global_placement`, `detailed_placement`, `clock_tree_synthesis`, `global_route`, `detailed_route`, `extract_parasitics`, `report_checks`, `report_power`, `report_design_area`, `write_def`.
- KLayout 0.30.7 at `/usr/bin/klayout` -- DEF-to-GDS merge verified with `pya` Python API on both modules. LEF-based loading confirmed; tech-file-only approach produces empty cells.
- nangate45 PDK at ORFS flow/platforms/nangate45/ -- all platform Tcl files read and verified: `make_tracks.tcl`, `grid_strategy-M1-M4-M7.tcl`, `setRC.tcl`, `fastroute.tcl`, `tapcell.tcl`, `config.mk`.
- ORFS flow scripts at `flow/scripts/` -- read `floorplan.tcl`, `global_place.tcl`, `cts.tcl`, `global_route.tcl`, `detail_route.tcl`, `fillcell.tcl`, `final_report.tcl`, `pdn.tcl`, `io_placement.tcl`, `detail_place.tcl`, `load.tcl`, `klayout.tcl` for reference patterns.
- ORFS `util/def2stream.py` -- reference implementation for KLayout GDS merge.
- Phase 10 research (10-RESEARCH.md) and implementation (`synth.sh`, `synth.tcl`) -- established patterns.
- Phase 9 research (09-RESEARCH.md) and implementation (`detect-env.sh`, `validate-pdk.sh`, `generate_sdc.sh`) -- infrastructure.

### Secondary (MEDIUM confidence)

- PDN failure on small modules (PDN-0185) -- discovered through live testing, not documented in ORFS or OpenROAD docs. Root cause (metal4 stripe pitch vs die width) confirmed through experimentation.
- Report command behavior (stdout-only, no -file flag) -- discovered through live testing. May change in future OpenROAD versions.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools verified installed, full flow tested end-to-end on both module types
- Architecture: HIGH -- three-file pattern proven (extends Phase 10 pattern), all platform Tcl files verified, report extraction approach tested
- Pitfalls: HIGH -- all pitfalls discovered through live testing, not just documentation; PDN failure, report capture, KLayout LEF requirement all verified and solutions confirmed
- GDS export: HIGH -- KLayout pya API tested on both modules, correct cell resolution confirmed with LEF-based approach

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable -- tools and PDK are local installations, not changing)
