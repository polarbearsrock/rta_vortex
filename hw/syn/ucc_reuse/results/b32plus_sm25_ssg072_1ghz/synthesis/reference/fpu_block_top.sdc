# RTA bench: one 32-lane FP32 unit (VX_fpu_std: FMA, FDIV/FSQRT, FCVT, FNCP per lane) of the B200-like Vortex core, 1 GHz target in TSMC N28 (time unit 1 ns).
set CLK_PERIOD 1.0
create_clock -name clk -period $CLK_PERIOD -waveform [list 0 [expr {$CLK_PERIOD / 2.0}]] [get_ports clk]
set_clock_uncertainty 0.05 [get_clocks clk]
set_clock_transition -rise 0.05 [get_clocks clk]
set_clock_transition -fall 0.05 [get_clocks clk]
set _in_ports  [remove_from_collection [all_inputs] [get_ports {clk reset}]]
set _out_ports [all_outputs]
# Top-level ports are the operands and results of one block: 30 % of the period on each side.
set_input_delay  [expr {$CLK_PERIOD * 0.30}] -clock clk $_in_ports
set_output_delay [expr {$CLK_PERIOD * 0.30}] -clock clk $_out_ports
set_driving_cell -lib_cell BUFFD4BWP30P140 $_in_ports
set_load 0.005 $_out_ports
set_max_transition [expr {$CLK_PERIOD * 0.10}] [current_design]
set_max_fanout 32 [current_design]
# reset is synchronous in Vortex but fans out to every unit: treated as a static signal
set_false_path -from [get_ports reset]
