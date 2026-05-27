create_clock -period 10.000 -name clock -waveform {0.000 5.000} [get_ports clock]
set_max_transition 0.800 [current_design]
