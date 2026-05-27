# Clock constraint for smallBOOM
create_clock -name clock -period 10.000 -waveform {0 5} [get_ports clock]
set_clock_transition 0.2 [get_clocks clock]
set_clock_uncertainty 0.5 [get_clocks clock]
set_input_delay -clock clock -max 2.0 [all_inputs]
set_output_delay -clock clock -max 2.0 [all_outputs]
set_max_fanout 16 [current_design]
