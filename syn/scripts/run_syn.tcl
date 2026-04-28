# run_syn.tcl — Placeholder synthesis script (Synopsys DC / Cadence Genus)
# Usage: dc_shell -f syn/scripts/run_syn.tcl

set TOP_MODULE ddr3_ctrl_top
set RTL_DIR    ../rtl
set WORK_DIR   ../syn/work

# Read RTL
analyze -format sverilog -define {} \
    [glob $RTL_DIR/*.v $RTL_DIR/**/*.v]
elaborate $TOP_MODULE

# Apply constraints
read_sdc ../constraints/ddr3_ctrl_top.sdc

# Compile
compile_ultra -no_autoungroup

# Reports
report_timing > ../reports/timing.rpt
report_area   > ../reports/area.rpt
report_power  > ../reports/power.rpt

write -format verilog -output ../reports/netlist.v $TOP_MODULE
