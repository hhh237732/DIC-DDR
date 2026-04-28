# ddr3_ctrl_top.sdc — Timing constraints placeholder
# Target: DDR3-1600 (800 MHz DDR, 400 MHz controller clock)

set CLK_PERIOD 2.5
create_clock -name aclk -period $CLK_PERIOD [get_ports aclk]
set_clock_uncertainty 0.1 [get_clocks aclk]
set_input_delay  0.5 -clock aclk [all_inputs]
set_output_delay 0.5 -clock aclk [all_outputs]

set_max_fanout  20 [all_inputs]
set_max_transition 0.2 [all_designs]
