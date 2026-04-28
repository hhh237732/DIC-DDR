##############################################################
# Read RTL Design Files
##############################################################

set RTL_ROOT "../../rtl"

# ---- Source parameters header ----
# (Included via `include in RTL files — DC picks it up via search_path)

# ---- Analyze & Elaborate ----
set rtl_files [list \
    ${RTL_ROOT}/axi/sync_fifo.v       \
    ${RTL_ROOT}/axi/axi_slave_if.v    \
    ${RTL_ROOT}/cmd/addr_map.v        \
    ${RTL_ROOT}/cmd/cmd_split.v       \
    ${RTL_ROOT}/cmd/cmd_reorder_l1.v  \
    ${RTL_ROOT}/cmd/cmd_reorder_l2.v  \
    ${RTL_ROOT}/buffer/write_buffer.v \
    ${RTL_ROOT}/buffer/read_buffer.v  \
    ${RTL_ROOT}/bank/bank_ctrl.v      \
    ${RTL_ROOT}/bank/bank_ctrl_top.v  \
    ${RTL_ROOT}/refresh/refresh_ctrl.v \
    ${RTL_ROOT}/init/init_fsm.v       \
    ${RTL_ROOT}/dfi/dfi_if.v          \
    ${RTL_ROOT}/ddr3_ctrl_top.v       \
]

foreach f $rtl_files {
    analyze -format verilog -define {SYNTHESIS=1} $f
}

elaborate ${DESIGN_TOP}
current_design ${DESIGN_TOP}
link

echo "Design read complete: [sizeof_collection [get_cells]] cells"
