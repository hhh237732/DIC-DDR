# run_syn.tcl — Placeholder synthesis script (Synopsys DC / Cadence Genus)
# Usage (from repo root): dc_shell -f syn/scripts/run_syn.tcl

set TOP_MODULE ddr3_ctrl_top
set RTL_DIR    rtl
set SYN_DIR    syn

# Read RTL
analyze -format sverilog -define {} \
    [glob $RTL_DIR/*.v $RTL_DIR/**/*.v]
elaborate $TOP_MODULE

# Apply constraints
read_sdc $SYN_DIR/constraints/ddr3_ctrl_top.sdc

# Compile
compile_ultra -no_autoungroup

# Reports
report_timing > $SYN_DIR/reports/timing.rpt
report_area   > $SYN_DIR/reports/area.rpt
report_power  > $SYN_DIR/reports/power.rpt

write -format verilog -output $SYN_DIR/reports/netlist.v $TOP_MODULE
