create_clock -name virtual_clk -period 8
set_input_delay -clock virtual_clk 0 [all_inputs]
set_output_delay -clock virtual_clk 0 [all_outputs]
set_max_delay 8 -from [all_inputs] -to [all_outputs]
