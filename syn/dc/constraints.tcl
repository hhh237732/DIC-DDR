##############################################################
# Timing / Area / Drive Constraints — 400 MHz target
##############################################################

# ---- Clock Definition ----
create_clock -name ${CLK_NAME} -period ${CLK_PERIOD_NS} [get_ports aclk]
set_clock_uncertainty -setup 0.1 [get_clocks ${CLK_NAME}]
set_clock_uncertainty -hold  0.05 [get_clocks ${CLK_NAME}]
set_clock_transition 0.05 [get_clocks ${CLK_NAME}]

# ---- Input Delays ----
set_input_delay  -max 0.4 -clock ${CLK_NAME} [all_inputs]
set_input_delay  -min 0.1 -clock ${CLK_NAME} [all_inputs]

# ---- Output Delays ----
set_output_delay -max 0.4 -clock ${CLK_NAME} [all_outputs]
set_output_delay -min 0.1 -clock ${CLK_NAME} [all_outputs]

# ---- Drive / Load ----
set_driving_cell -lib_cell BUFX4 -pin Y [all_inputs]
set_load 0.05 [all_outputs]

# ---- Area Constraint ----
set_max_area 50000

# ---- DRC ----
set_max_fanout 32 ${DESIGN_TOP}
set_max_transition 0.2 ${DESIGN_TOP}
set_max_capacitance 0.5 ${DESIGN_TOP}

# ---- False Paths ----
set_false_path -from [get_ports aresetn]

echo "Constraints applied: CLK=${CLK_PERIOD_NS}ns ($(expr 1000.0 / ${CLK_PERIOD_NS}) MHz)"
