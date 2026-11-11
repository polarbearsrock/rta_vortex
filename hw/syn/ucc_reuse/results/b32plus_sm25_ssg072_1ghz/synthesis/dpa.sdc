set CLK_PERIOD 1.0
create_clock -name clk -period $CLK_PERIOD -waveform [list 0 [expr {$CLK_PERIOD / 2.0}]] [get_ports clk_i]
set_clock_uncertainty 0.05 [get_clocks clk]
set_clock_transition -rise 0.05 [get_clocks clk]
set_clock_transition -fall 0.05 [get_clocks clk]
set _in_ports  [remove_from_collection [all_inputs] [get_ports {clk_i rst_ni dpa_mode_i}]]
set _out_ports [all_outputs]
set_input_delay  [expr {$CLK_PERIOD * 0.30}] -clock clk $_in_ports
set_output_delay [expr {$CLK_PERIOD * 0.30}] -clock clk $_out_ports
set_driving_cell -lib_cell BUFFD4BWP30P140 $_in_ports
set_load 0.005 $_out_ports
set_max_transition [expr {$CLK_PERIOD * 0.10}] [current_design]
set_max_fanout 32 [current_design]
set_false_path -from [get_ports rst_ni]
set_case_analysis 1 [get_ports dpa_mode_i]
