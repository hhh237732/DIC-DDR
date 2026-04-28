##############################################################
# DC Setup Script — update library paths before use
##############################################################

# ---- Library Paths (update for your PDK) ----
set PDK_ROOT    "/path/to/pdk/28nm"
set STD_CELL    "${PDK_ROOT}/stdcell/typical/db"
set IO_LIB      "${PDK_ROOT}/io/typical/db"

# ---- Search Paths ----
set search_path [list . \
    ${STD_CELL} \
    ${IO_LIB}   \
    ../../rtl   \
    ../../rtl/axi \
    ../../rtl/cmd \
    ../../rtl/bank \
    ../../rtl/buffer \
    ../../rtl/dfi \
    ../../rtl/init \
    ../../rtl/refresh \
]

# ---- Target & Link Libraries ----
set target_library "${STD_CELL}/typical_1v0_25c.db"
set link_library   "* ${target_library}"

# ---- Design Constraints ----
set CLK_PERIOD_NS 2.5
set CLK_NAME      "aclk"
set DESIGN_TOP    "ddr3_ctrl_top"

echo "DC setup complete: target=${target_library}"
