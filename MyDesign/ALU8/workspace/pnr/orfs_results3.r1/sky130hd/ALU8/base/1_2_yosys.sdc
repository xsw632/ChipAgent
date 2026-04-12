create_clock -name virtual_clk -period 5
set_input_delay -clock virtual_clk 0 [all_inputs]
set_output_delay -clock virtual_clk 0 [all_outputs]
set_max_delay 5 -from [all_inputs] -to [all_outputs]
