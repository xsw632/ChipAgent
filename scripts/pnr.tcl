# pnr.tcl - OpenROAD PnR flow for nangate45
#
# Standalone Tcl script for physical design (floorplan, placement, CTS,
# routing, extraction, reports). Invoked by pnr.sh via:
#   openroad -no_init -exit -log <logfile> pnr.tcl
#
# All paths are read from environment variables set by pnr.sh:
#   DESIGN_NAME  - module name (e.g., ALU)
#   NETLIST      - path to gate-level netlist (.synth.v)
#   SDC_FILE     - path to SDC constraints
#   LIB_FILE     - path to nangate45 liberty (.lib)
#   TECH_LEF     - path to tech LEF
#   CELL_LEF     - path to cell LEF
#   PDK_DIR      - nangate45 platform directory
#   OUTPUT_DIR   - path to workspace/pnr/
#   REPORTS_DIR  - path to workspace/pnr/reports/
#   IS_SEQUENTIAL - "1" for sequential, "0" for combinational
#   RCX_RULES    - path to RC extraction rules

# ===== LOAD DESIGN =====
read_liberty $::env(LIB_FILE)
read_lef $::env(TECH_LEF)
read_lef $::env(CELL_LEF)
read_verilog $::env(NETLIST)
link_design $::env(DESIGN_NAME)
read_sdc $::env(SDC_FILE)

# ===== FLOORPLAN =====
# Auto-size with minimum floor for small modules to prevent PDN failure
# (PDN-0185: metal4 stripe pitch requires >= ~60um die width)
set num_cells [llength [get_cells -hier *]]
puts "Cell count: $num_cells"

if {$num_cells < 100} {
  # Small module: explicit minimum die area (70x70um)
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

# WNS/TNS via STA internal API
set wns_val [sta::format_time [sta::worst_slack_cmd max] 3]
set tns_val [sta::format_time [sta::total_negative_slack_cmd max] 3]
puts "PNR_WNS: $wns_val"
puts "PNR_TNS: $tns_val"

# ===== OUTPUT =====
write_def $::env(OUTPUT_DIR)/$::env(DESIGN_NAME).routed.def

puts "PNR_COMPLETE"
