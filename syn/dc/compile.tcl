##############################################################
# Main DC Synthesis Script
# Usage: dc_shell -f dc/compile.tcl | tee dc/reports/compile.log
##############################################################

source dc/setup.tcl
source dc/read_design.tcl
source dc/constraints.tcl

# ---- Compile ----
compile_ultra -no_autoungroup -timing_high_effort_script

# ---- Post-compile Optimizations ----
optimize_registers
# size_cell (if needed for timing closure)

# ---- Reports ----
report_timing -delay_type max -max_paths 10 -nworst 3 \
    > dc/reports/timing_max.rpt
report_timing -delay_type min -max_paths 5 \
    > dc/reports/timing_min.rpt
report_area  -hierarchy \
    > dc/reports/area.rpt
report_power -analysis_effort high \
    > dc/reports/power.rpt
report_constraint -all_violators \
    > dc/reports/violations.rpt

# ---- Save Netlist ----
write -format verilog -hierarchy -output dc/reports/ddr3_ctrl_top_netlist.v
write_sdc dc/reports/ddr3_ctrl_top_post_syn.sdc

echo "Synthesis complete."
