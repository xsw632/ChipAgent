# synth.tcl - Yosys ASIC synthesis for nangate45
#
# Standalone Tcl script for gate-level synthesis mapping to nangate45
# standard cells. Invoked by synth.sh via: yosys -c synth.tcl
#
# All paths are read from environment variables set by synth.sh:
#   DESIGN_NAME  - module name (e.g., ALU)
#   VERILOG_FILE - path to input Verilog
#   LIB_FILE     - path to nangate45 liberty (.lib)
#   OUTPUT_DIR   - path to workspace/pnr/
#   REPORTS_DIR  - path to workspace/pnr/reports/

# Read standard cell library (blackbox mode for synthesis)
read_liberty -lib $::env(LIB_FILE)

# Read RTL Verilog with SYNTHESIS define to skip simulation-only blocks
# (excludes Chisel RANDOMIZE init blocks wrapped in ifndef SYNTHESIS)
read_verilog -DSYNTHESIS $::env(VERILOG_FILE)

# High-level synthesis: elaborate, optimize, flatten
# -top is required to select the correct top module
# -flatten gives ABC maximum optimization opportunity for small Chisel modules
synth -top $::env(DESIGN_NAME) -flatten

# Technology mapping: flip-flops FIRST, then combinational logic
# dfflibmap maps register cells (DFF_X1 etc.) before abc maps combinational gates
dfflibmap -liberty $::env(LIB_FILE)
abc -liberty $::env(LIB_FILE)

# Post-mapping cleanup
# setundef -zero: replace undefined values with 0 (prevents X propagation)
setundef -zero
# splitnets: split multi-bit nets for cleaner netlist
splitnets
# opt_clean -purge: remove unused cells and wires
opt_clean -purge

# Reports (check for diagnostics only -- do NOT use check -assert)
tee -o $::env(REPORTS_DIR)/synth_check.txt check
tee -o $::env(REPORTS_DIR)/synth_stat.txt stat -liberty $::env(LIB_FILE)

# Write gate-level netlist (structural Verilog for OpenROAD compatibility)
write_verilog -noattr -noexpr -nohex -nodec $::env(OUTPUT_DIR)/$::env(DESIGN_NAME).synth.v
