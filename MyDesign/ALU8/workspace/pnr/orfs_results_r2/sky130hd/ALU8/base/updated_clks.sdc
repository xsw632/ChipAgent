###############################################################################
# Created by write_sdc
###############################################################################
current_design ALU8
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name virtual_clk -period 3.0462 
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {clock}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[0]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[1]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[2]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[3]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[4]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[5]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[6]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputA[7]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[0]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[1]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[2]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[3]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[4]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[5]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[6]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_inputB[7]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_op[0]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_op[1]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_op[2]}]
set_input_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {reset}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[0]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[1]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[2]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[3]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[4]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[5]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[6]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_result[7]}]
set_output_delay 0.0000 -clock [get_clocks {virtual_clk}] -add_delay [get_ports {io_zero}]
set_max_delay\
    -from [list [get_ports {clock}]\
           [get_ports {io_inputA[0]}]\
           [get_ports {io_inputA[1]}]\
           [get_ports {io_inputA[2]}]\
           [get_ports {io_inputA[3]}]\
           [get_ports {io_inputA[4]}]\
           [get_ports {io_inputA[5]}]\
           [get_ports {io_inputA[6]}]\
           [get_ports {io_inputA[7]}]\
           [get_ports {io_inputB[0]}]\
           [get_ports {io_inputB[1]}]\
           [get_ports {io_inputB[2]}]\
           [get_ports {io_inputB[3]}]\
           [get_ports {io_inputB[4]}]\
           [get_ports {io_inputB[5]}]\
           [get_ports {io_inputB[6]}]\
           [get_ports {io_inputB[7]}]\
           [get_ports {io_op[0]}]\
           [get_ports {io_op[1]}]\
           [get_ports {io_op[2]}]\
           [get_ports {reset}]]\
    -to [list [get_ports {io_result[0]}]\
           [get_ports {io_result[1]}]\
           [get_ports {io_result[2]}]\
           [get_ports {io_result[3]}]\
           [get_ports {io_result[4]}]\
           [get_ports {io_result[5]}]\
           [get_ports {io_result[6]}]\
           [get_ports {io_result[7]}]\
           [get_ports {io_zero}]] 8.0000
###############################################################################
# Environment
###############################################################################
###############################################################################
# Design Rules
###############################################################################
