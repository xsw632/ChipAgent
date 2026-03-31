# Technology Stack: RTL-to-GDS Additions

**Project:** ChipAgent v1.1.2 RTL-to-GDS
**Researched:** 2026-03-31
**Confidence:** HIGH (all tools verified on local machine, PDK files inspected, ORFS Tcl scripts read line-by-line)

## Scope

This document covers ONLY the stack additions for v1.1.2 RTL-to-GDS. The existing validated stack (Chisel 3.6.1, Scala 2.13.10, sbt 1.10.7, Verilator 5.008+, npm plugin packaging, per-module workspace isolation) is NOT re-researched.

---

## Installed Tool Versions (Verified 2026-03-31)

| Tool | Version | Path | Purpose |
|------|---------|------|---------|
| Yosys | 0.53+26 | `/usr/local/bin/yosys` | Logic synthesis: RTL Verilog to gate-level netlist |
| OpenROAD | 26Q1-951-g6975124cf2 | system path | Place-and-route: gate-level netlist to physical layout |
| KLayout | **NOT INSTALLED** | -- | GDS export (DEF-to-GDS stream out) |

**KLayout is not installed.** The ORFS flow uses KLayout for DEF-to-GDS conversion via `klayout.sh`. Without it, the pipeline produces routed DEF + timing/power/area reports but NOT GDS files.

**Recommendation:** Scope v1.1.2 to DEF output + reports. GDS export requires KLayout installation and can be added as a follow-up. The DEF + reports provide the core PPA (power/performance/area) value.

---

## nangate45 PDK (Verified at `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45/`)

### Core Files

| File | Relative Path | Role |
|------|---------------|------|
| Tech LEF | `lef/NangateOpenCellLibrary.tech.lef` | Metal layer definitions, routing rules, via definitions |
| Cell LEF | `lef/NangateOpenCellLibrary.macro.mod.lef` | Standard cell physical geometries (pin shapes, obstructions) |
| Liberty | `lib/NangateOpenCellLibrary_typical.lib` | Timing/power characterization for synthesis and STA |
| GDS | `gds/NangateOpenCellLibrary.gds` | Cell layout geometries for stream-out (requires KLayout) |
| RCX rules | `rcx_patterns.rules` | Parasitic extraction rules for OpenRCX (10 metal layers) |
| Layer RC | `setRC.tcl` | Per-layer resistance/capacitance for wire delay estimation |

### Platform Configuration Files (Tcl -- source from PDK dir)

| File | Role | How ChipAgent Uses It |
|------|------|-----------------------|
| `grid_strategy-M1-M4-M7.tcl` | Power distribution network: VDD/VSS global connections, stripes on M1/M4/M7 | `source` then `pdngen` |
| `tapcell.tcl` | Well-tie and endcap cell insertion | `source` (uses `$::env(TAP_CELL_NAME)` -- must set env var OR inline the command) |
| `fastroute.tcl` | Global routing layer adjustments (M2-M3: 0.5, M4-M10: 0.25) + routing layer ranges | `source` before `global_route` (uses `$::env(MIN_ROUTING_LAYER)` etc. -- must set) |
| `make_tracks.tcl` | Routing track definitions per metal layer (M1-M10) | `source` after `initialize_floorplan` |
| `setRC.tcl` | Layer parasitics for estimation | `source` early in session |

**Critical note on PDK Tcl files:** Several PDK Tcl files reference `$::env(...)` variables. ChipAgent's generated Tcl script must either:
- (A) Set the required env vars before `source`-ing the PDK files, OR
- (B) Inline the equivalent commands directly (avoids env var dependencies)

Option B is recommended for simplicity. The key inlined equivalents:

```tcl
# Instead of sourcing tapcell.tcl (which reads $::env(TAP_CELL_NAME)):
tapcell -distance 120 -tapcell_master TAPCELL_X1 -endcap_master TAPCELL_X1

# Instead of sourcing fastroute.tcl (which reads $::env(MIN_ROUTING_LAYER) etc.):
set_global_routing_layer_adjustment metal2-metal3 0.5
set_global_routing_layer_adjustment metal4-metal10 0.25
set_routing_layers -signal metal2-metal10
set_routing_layers -clock metal4-metal10
```

The `grid_strategy-M1-M4-M7.tcl`, `make_tracks.tcl`, and `setRC.tcl` files do NOT reference env vars and can be safely `source`-d directly.

### Key PDK Constants (from `config.mk`)

```bash
PROCESS              = 45
PLACE_SITE           = FreePDK45_38x28_10R_NP_162NW_34O
TIEHI_CELL_AND_PORT  = "LOGIC1_X1 Z"
TIELO_CELL_AND_PORT  = "LOGIC0_X1 Z"
MIN_BUF_CELL_AND_PORTS = "BUF_X1 A Z"
ABC_DRIVER_CELL      = BUF_X1
ABC_LOAD_IN_FF       = 3.898
FILL_CELLS           = "FILLCELL_X1 FILLCELL_X2 FILLCELL_X4 FILLCELL_X8 FILLCELL_X16 FILLCELL_X32"
DONT_USE_CELLS       = "TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1"
IO_PLACER_H          = metal5
IO_PLACER_V          = metal6
MIN_ROUTING_LAYER    = metal2
MIN_CLK_ROUTING_LAYER = metal4
MAX_ROUTING_LAYER    = metal10
CORE_UTILIZATION     = 55  # (from GCD example -- reasonable default)
PLACE_DENSITY        = 0.30  # (from platform config.mk)
```

---

## Flow Architecture: Standalone Scripts, Not ORFS Makefile

ChipAgent must invoke `yosys` and `openroad` directly with custom Tcl scripts rather than using the ORFS Makefile.

### Why Standalone

1. ORFS Makefile expects ~50+ environment variables via `config.mk` + `variables.mk` + `defaults.py`
2. ORFS uses rigid directory structure (`flow/results/`, `flow/reports/`, `flow/logs/`)
3. ChipAgent needs per-module workspace isolation (`MyDesign/<Module>/workspace/pnr/`)
4. ChipAgent needs Claude-readable error messages, not Makefile noise
5. The actual Tcl commands are straightforward -- ORFS complexity is in its configurability, not its core flow

### 7-Stage Pipeline

```
[Input: verified RTL Verilog from workspace/generated/]

Stage 1: SDC Generation (bash)     --> workspace/pnr/constraint.sdc
Stage 2: Yosys Synthesis (yosys)   --> workspace/pnr/results/synth.v + reports
Stage 3: Floorplan (openroad)      --> placed/routed design (single session)
Stage 4: Placement (openroad)      |
Stage 5: CTS (openroad)            | (skip if combinational)
Stage 6: Routing (openroad)        |
Stage 7: Reports + Export          --> final.def + timing/power/area reports

[Output: DEF, gate-level Verilog, timing/power/area reports]
```

Stages 3-7 run in a single OpenROAD Tcl session (not separate invocations) because OpenROAD maintains the design database in memory. Splitting would require writing/reading ODB files between stages, adding complexity for no benefit.

---

## Script Specifications

### Stage 1: SDC Generation (`scripts/generate_sdc.sh`)

Generates SDC constraints by analyzing the Verilog for clock ports. Uses bash + grep -- no external dependencies.

**Clock Detection Heuristic:**
- Parse `workspace/generated/<Module>.v` for `input` ports named `clock`, `clk`, `CLK`, or `io_clock`
- Chisel's default clock port is named `clock` in generated Verilog
- If clock found: sequential SDC with `create_clock` on that port
- If no clock: combinational SDC with virtual clock + `set_max_delay`

**Sequential SDC Template:**

```sdc
current_design ${DESIGN_NAME}

set clk_name  core_clock
set clk_port  [get_ports clock]
set clk_period 2.0

create_clock -name $clk_name -period $clk_period $clk_port

set non_clock_inputs [lsearch -all -inline -not [all_inputs] clock]
set_input_delay  [expr $clk_period * 0.2] -clock $clk_name $non_clock_inputs
set_output_delay [expr $clk_period * 0.2] -clock $clk_name [all_outputs]
```

Note: The GCD example uses `[all_inputs -no_clocks]` for non-clock input selection. However, `all_inputs -no_clocks` is an OpenSTA command, not standard SDC. The `lsearch` approach works in both Yosys and OpenROAD. Alternative: use `set_input_delay` on `[all_inputs]` and let the tool handle clock ports (they get constrained by `create_clock` anyway).

**Combinational SDC Template:**

```sdc
current_design ${DESIGN_NAME}

create_clock -name virtual_clk -period 2.0

set_input_delay  0.4 -clock virtual_clk [all_inputs]
set_output_delay 0.4 -clock virtual_clk [all_outputs]
set_max_delay 2.0 -from [all_inputs] -to [all_outputs]
```

**Default clock period:** 2.0ns (500MHz equivalent). Conservative for nangate45. Overridable via `spec.json` field `clock_period_ns`.

**Why 2.0ns default:** The GCD example in ORFS uses 0.46ns (highly aggressive). For ChipAgent's auto-generated modules, 2.0ns is relaxed enough to avoid timing failures while still driving meaningful optimization during synthesis.

### Stage 2: Yosys Synthesis (`scripts/synth.sh`)

Invokes `yosys` with a generated Tcl script file. The Tcl file is written to `workspace/pnr/synth.tcl` and passed via `yosys -c synth.tcl`.

**Minimal Yosys Tcl for nangate45:**

```tcl
# Read liberty for technology mapping
read_liberty -lib ${LIB_FILE}

# Read RTL Verilog
read_verilog ${VERILOG_FILE}

# Synthesize -- flatten hierarchy for small modules
synth -top ${DESIGN_NAME} -flatten

# Flip-flop mapping (sequential only -- omit for combinational)
dfflibmap -liberty ${LIB_FILE}

# Technology mapping with ABC
abc -liberty ${LIB_FILE} \
    -D ${CLOCK_PERIOD_PS} \
    -constr ${ABC_CONSTR_FILE}

# Tie cells
hilomap -singleton \
    -hicell LOGIC1_X1 Z \
    -locell LOGIC0_X1 Z

# Insert buffers for pass-through wires
insbuf -buf BUF_X1 A Z

# Cleanup
splitnets
opt_clean -purge

# Reports
tee -o ${REPORTS_DIR}/synth_check.txt check
tee -o ${REPORTS_DIR}/synth_stat.txt stat -liberty ${LIB_FILE}

# Write gate-level netlist
write_verilog -noattr -noexpr -nohex -nodec ${RESULTS_DIR}/synth.v
```

**Key variations:**
- **Combinational modules:** Omit `dfflibmap`. Use `abc -liberty ${LIB_FILE}` without `-D` flag.
- **Sequential modules:** Include `dfflibmap` and pass `-D ${CLOCK_PERIOD_PS}` (period in picoseconds, e.g., 2000 for 2ns).

**ABC constraints file** (`abc.constr`):
```
set_driving_cell BUF_X1
set_load 3.898
```

**Yosys invocation:**
```bash
yosys -c "${PNR_DIR}/synth.tcl" > "${PNR_DIR}/logs/synth.log" 2>&1
```

### Stages 3-7: OpenROAD PnR (`scripts/pnr.sh`)

Single `openroad` invocation with a generated Tcl script. All stages in one session.

**OpenROAD Tcl for nangate45 (complete flow):**

```tcl
# --- Configuration ---
set PLATFORM_DIR  "${NANGATE45_DIR}"
set DESIGN_NAME   "${MODULE_NAME}"
set RESULTS_DIR   "${PNR_RESULTS_DIR}"
set REPORTS_DIR   "${PNR_REPORTS_DIR}"

# --- Read libraries ---
read_liberty ${PLATFORM_DIR}/lib/NangateOpenCellLibrary_typical.lib
read_lef ${PLATFORM_DIR}/lef/NangateOpenCellLibrary.tech.lef
read_lef ${PLATFORM_DIR}/lef/NangateOpenCellLibrary.macro.mod.lef

# --- Read design ---
read_verilog ${RESULTS_DIR}/synth.v
link_design ${DESIGN_NAME}
read_sdc ${PNR_DIR}/constraint.sdc

# --- Layer RC ---
source ${PLATFORM_DIR}/setRC.tcl

# --- Floorplan ---
initialize_floorplan -utilization 55 \
    -aspect_ratio 1.0 \
    -core_space 2.0 \
    -site FreePDK45_38x28_10R_NP_162NW_34O
source ${PLATFORM_DIR}/make_tracks.tcl

# --- IO placement ---
place_pins -hor_layers metal5 -ver_layers metal6

# --- Tapcell (inlined -- avoids env var dependency) ---
tapcell -distance 120 \
    -tapcell_master TAPCELL_X1 \
    -endcap_master TAPCELL_X1

# --- Power distribution network ---
source ${PLATFORM_DIR}/grid_strategy-M1-M4-M7.tcl
pdngen

# --- Global placement ---
set_dont_use {TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1}
global_placement -density 0.30

# --- Resizing and repair ---
estimate_parasitics -placement
buffer_ports
repair_design
repair_timing -setup -hold

# --- Detailed placement ---
detailed_placement
check_placement -verbose

# --- CTS (sequential modules only) ---
if { [llength [all_clocks]] > 0 } {
    repair_clock_inverters
    clock_tree_synthesis -sink_clustering_enable -repair_clock_nets
    set_propagated_clock [all_clocks]
    estimate_parasitics -placement
    repair_timing -setup -hold
    detailed_placement
}

# --- Global routing (inlined -- avoids env var dependency) ---
set_global_routing_layer_adjustment metal2-metal3 0.5
set_global_routing_layer_adjustment metal4-metal10 0.25
set_routing_layers -signal metal2-metal10
set_routing_layers -clock metal4-metal10
global_route -congestion_report_file ${REPORTS_DIR}/congestion.rpt

# --- Detailed routing ---
detailed_route \
    -output_drc ${REPORTS_DIR}/route_drc.rpt \
    -verbose 1

# --- Filler cells ---
filler_placement {FILLCELL_X1 FILLCELL_X2 FILLCELL_X4 FILLCELL_X8 FILLCELL_X16 FILLCELL_X32}
check_placement

# --- Parasitic extraction ---
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file ${PLATFORM_DIR}/rcx_patterns.rules
write_spef ${RESULTS_DIR}/final.spef
read_spef ${RESULTS_DIR}/final.spef

# --- Timing / Power / Area reports ---
report_checks -path_delay min_max -format full_clock_expanded \
    > ${REPORTS_DIR}/timing.rpt
report_tns  > ${REPORTS_DIR}/tns.rpt
report_wns  > ${REPORTS_DIR}/wns.rpt
report_power > ${REPORTS_DIR}/power.rpt
report_design_area > ${REPORTS_DIR}/area.rpt
report_cell_usage  > ${REPORTS_DIR}/cell_usage.rpt

# --- Write final outputs ---
write_def     ${RESULTS_DIR}/final.def
write_verilog ${RESULTS_DIR}/final.v
```

**CTS skip logic:** The `if { [llength [all_clocks]] > 0 }` check handles combinational modules. When SDC uses a virtual clock (not bound to a port), `all_clocks` returns the virtual clock. However, CTS only operates on real clocks (bound to ports). The correct guard is:

```tcl
# Check if any real clock port exists (not virtual)
set real_clocks [get_ports -filter "direction == input" -quiet clock]
if { [llength $real_clocks] > 0 } {
    # ... CTS flow ...
}
```

Alternatively, since ChipAgent generates the SDC and knows if the module is sequential, the `is_sequential` flag from spec.json can drive a simple boolean substitution in the Tcl template.

**OpenROAD invocation:**
```bash
openroad -no_splash -exit "${PNR_DIR}/pnr.tcl" > "${PNR_DIR}/logs/pnr.log" 2>&1
```

The `-exit` flag ensures OpenROAD exits after script completion (no interactive prompt). The `-no_splash` flag suppresses the ASCII art banner.

---

## SDC Generation: Combinational vs Sequential Decision

### How to Detect Module Type

**From spec.json (preferred):** If `spec.json` includes port information, check for `clock` or `clk` in the `inputs` array. This is the most reliable because it comes from the requirement parser which already understands the module semantics.

**From Verilog (fallback):** Grep the generated Verilog for clock port declarations:
```bash
grep -qE '^\s*input\s+(wire\s+)?clock\b' "${VERILOG_FILE}"
```

Chisel always names its implicit clock port `clock` in generated Verilog. User-defined clock ports would appear as `io_clk` or `io_clock` (with the `io_` prefix from Chisel's IO bundle convention).

### SDC Implications by Module Type

| Aspect | Sequential (has clock) | Combinational (no clock) |
|--------|----------------------|--------------------------|
| SDC clock | `create_clock` on real port | `create_clock -name virtual_clk -period 2.0` (no port) |
| Yosys `dfflibmap` | Yes | No (no flip-flops to map) |
| Yosys `abc -D` | Yes (period in ps) | No (omit `-D` flag) |
| OpenROAD CTS | Yes (full CTS flow) | Skip (no clock tree) |
| OpenROAD repair_timing | `-setup -hold` | `-setup` only (no hold without real clock) |

---

## Workspace Layout Extension

```
MyDesign/<Module>/workspace/
    generated/              # existing: Chisel-compiled RTL Verilog
    sim/                    # existing: testbench, VCD, sim logs
    pnr/                    # NEW: synthesis + PnR artifacts
        constraint.sdc      # auto-generated SDC
        abc.constr           # ABC driving cell / load constraints
        synth.tcl            # generated Yosys Tcl script
        pnr.tcl              # generated OpenROAD Tcl script
        logs/
            synth.log        # Yosys stdout/stderr
            pnr.log          # OpenROAD stdout/stderr
        results/
            synth.v          # Yosys gate-level netlist
            final.def        # routed DEF
            final.v          # final gate-level Verilog
            final.spef       # parasitics
        reports/
            synth_check.txt  # Yosys synthesis checks
            synth_stat.txt   # Yosys area/cell statistics
            timing.rpt       # OpenSTA timing (setup + hold)
            tns.rpt          # total negative slack
            wns.rpt          # worst negative slack
            power.rpt        # power breakdown
            area.rpt         # design area
            cell_usage.rpt   # cell usage breakdown
            congestion.rpt   # routing congestion map
            route_drc.rpt    # DRC violations from detailed routing
```

---

## New Scripts to Create

| Script | Input | Output | Tool |
|--------|-------|--------|------|
| `scripts/generate_sdc.sh <Module>` | `workspace/generated/<Module>.v` + `spec.json` | `workspace/pnr/constraint.sdc` | bash/grep |
| `scripts/synth.sh <Module>` | `workspace/generated/<Module>.v` + SDC | `workspace/pnr/results/synth.v` + reports | `yosys` |
| `scripts/pnr.sh <Module>` | `workspace/pnr/results/synth.v` + SDC | `workspace/pnr/results/final.*` + reports | `openroad` |

All scripts follow existing ChipAgent conventions:
- Source `_common.sh` for plugin root detection
- Accept bare module name or `MyDesign/<Module>` path
- Create output directories with `mkdir -p`
- Capture tool output to log file, display on error
- Exit non-zero on failure with diagnostic context

### PDK Path Resolution

Scripts need the nangate45 platform directory path. Resolution order:
1. `NANGATE45_DIR` environment variable (if set)
2. `ORFS_DIR/flow/platforms/nangate45` (if `ORFS_DIR` is set)
3. `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45` (hardcoded fallback for this machine)
4. Check `.chipagent/env.json` for detected PDK path

Recommendation: Store the detected path in `.chipagent/env.json` during `/chip-agent:initialize` and read it from there in scripts. This mirrors the existing pattern for other tool paths.

---

## Integration with Existing Pipeline

```
/chip-agent:generate or /chip-agent:workflow (existing)
    parse -> generate -> compile -> lint -> testbench -> simulate -> report
    [verified Verilog in workspace/generated/]

/chip-agent:pnr <ModuleName> (NEW)
    1. Verify workspace/generated/<Module>.v exists
    2. Generate SDC (scripts/generate_sdc.sh)
    3. Run synthesis (scripts/synth.sh)
    4. Run PnR (scripts/pnr.sh)
    5. Parse and display reports
    [DEF + reports in workspace/pnr/]
```

The `/chip-agent:pnr` command is a new skill that reads from `workspace/generated/` (the verified Verilog) and writes all artifacts to `workspace/pnr/`. It does NOT modify any existing artifacts.

---

## Environment Detection Additions

Extend `detect-env.sh` and `.chipagent/env.json` (written by `/chip-agent:initialize`):

New tool detections:
```bash
# Yosys
detect_tool "yosys" "yosys" "yosys --version 2>&1 | head -1" '[0-9]+\.[0-9]+(\+[0-9]+)?'

# OpenROAD
detect_tool "openroad" "openroad" "openroad -version 2>&1 | head -1" '[0-9]+Q[0-9]'

# KLayout (optional)
detect_tool "klayout" "klayout" "klayout -v 2>&1 | head -1" '[0-9]+\.[0-9]+(\.[0-9]+)?'
```

New PDK detection:
```bash
# nangate45 PDK presence
NANGATE45_DIR=""
for candidate in \
    "${ORFS_DIR}/flow/platforms/nangate45" \
    "/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45"; do
  if [ -f "${candidate}/lib/NangateOpenCellLibrary_typical.lib" ]; then
    NANGATE45_DIR="$candidate"
    break
  fi
done
```

New capability flag:
```json
{
  "capabilities": {
    "can_compile": true,
    "can_lint": true,
    "can_simulate": true,
    "can_synthesize": true,
    "can_pnr": true,
    "can_gds": false
  }
}
```

Where:
- `can_synthesize` = yosys installed AND nangate45 liberty exists
- `can_pnr` = openroad installed AND nangate45 LEF + liberty exist
- `can_gds` = klayout installed AND nangate45 GDS exists

---

## Alternatives Considered

| Category | Chosen | Alternative | Why Not |
|----------|--------|-------------|---------|
| Flow runner | Standalone Yosys + OpenROAD scripts | ORFS `make` targets | 50+ env vars, rigid paths, poor error messages for Claude |
| PnR session | Single OpenROAD invocation | Separate per-stage invocations | Would need ODB write/read between stages; adds complexity |
| SDC generation | Auto-detect clock from Verilog | Require user-provided SDC | Users won't know SDC format; auto-generation is feasible |
| PDK Tcl sourcing | Inline critical commands, source safe files | Source all PDK Tcl files | Some PDK Tcl files read env vars that won't be set |
| GDS export | Defer (KLayout not installed) | Install KLayout now | DEF + reports deliver core value; GDS can follow |
| PDK | nangate45 | sky130, ASAP7 | nangate45 already available, well-documented, fast |
| Command | Separate `/chip-agent:pnr` | Extend `/chip-agent:workflow` | PnR is optional and slow; distinct command is cleaner |
| Clock period | 2.0ns default | Aggressive (0.5ns) or user-only | 2.0ns avoids timing failures; still drives meaningful optimization |
| Tcl generation | Shell script writes .tcl file, passes to tool | Inline Tcl via `-p` flag | Easier to debug; `.tcl` file preserved in workspace for inspection |
| Yosys invocation | `yosys -c file.tcl` | `yosys -p "script commands"` | File-based is debuggable and avoids shell quoting issues |
| OpenROAD invocation | `openroad -no_splash -exit file.tcl` | Multiple openroad calls per stage | Single session avoids ODB I/O overhead |

---

## Sources

- **Local tools:** `yosys --version` = 0.53+26, `openroad -version` = 26Q1-951-g6975124cf2 (verified 2026-03-31)
- **PDK files:** Direct inspection of `/home/mingzhenjia/OpenROAD-flow-scripts/flow/platforms/nangate45/` -- config.mk, all Tcl files, lib/, lef/, gds/ directories (verified 2026-03-31)
- **ORFS flow scripts:** Line-by-line read of `synth_canonicalize.tcl`, `synth_preamble.tcl`, `synth.tcl`, `synth_odb.tcl`, `floorplan.tcl`, `global_place.tcl`, `resize.tcl`, `cts.tcl`, `global_route.tcl`, `detail_route.tcl`, `fillcell.tcl`, `final_report.tcl`, `load.tcl`, `pdn.tcl`, `flow.sh` at `/home/mingzhenjia/OpenROAD-flow-scripts/flow/scripts/` (verified 2026-03-31)
- **GCD example:** `/home/mingzhenjia/OpenROAD-flow-scripts/flow/designs/nangate45/gcd/config.mk` and `constraint.sdc` (verified 2026-03-31)
- **Existing ChipAgent scripts:** `_common.sh`, `compile.sh`, `detect-env.sh` at `/home/mingzhenjia/ChipAgent/scripts/` (verified 2026-03-31)

---
*Stack research for: ChipAgent v1.1.2 -- RTL-to-GDS via Yosys + OpenROAD*
*Researched: 2026-03-31*
