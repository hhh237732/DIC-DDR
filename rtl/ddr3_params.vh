`ifndef DDR3_PARAMS_VH
`define DDR3_PARAMS_VH

// ============================================================
// DDR3 参数头文件（教学配置）
// 说明：下列参数以控制器 ck 周期为单位。
// ============================================================

`define DDR_DQ_WIDTH      32
`define DDR_STRB_WIDTH    (`DDR_DQ_WIDTH/8)
`define AXI_ADDR_WIDTH    32
`define AXI_ID_WIDTH      4

// DDR3 几何参数（1Gb x8）
`define DDR_BANK_BITS     3
`define DDR_BANK_NUM      8
`define DDR_ROW_BITS      15
`define DDR_COL_BITS      10

// 时序参数（DDR3-1600 近似）
`define tRCD  11
`define tRP   11
`define tRAS  28
`define tRC   39
`define tWR   12
`define tRTP  6
`define tCCD  4
`define tRRD  6
`define tFAW  24
`define tWTR  6
`define tRFC  110
`define tREFI 6240
`define CL    11
`define CWL   8

// 初始化等待（真实应远大于此，仿真加速）
`define INIT_200US_CYC  200
`define INIT_500US_CYC  500
`define INIT_ZQCL_CYC   64

// 命令编码（控制器内部）
`define CMD_NOP   3'd0
`define CMD_ACT   3'd1
`define CMD_RD    3'd2
`define CMD_WR    3'd3
`define CMD_PRE   3'd4
`define CMD_REF   3'd5
`define CMD_MRS   3'd6
`define CMD_ZQCL  3'd7

// 初始化时序参数（仿真友好版）
`define T_INIT_CKE_LOW   200
`define T_INIT_TXPR      5
`define T_INIT_TMRD      4
`define T_INIT_TMOD      12
`define T_INIT_ZQINIT    512

// 仿真缩短版
`define T_SIM_INIT_CKE_LOW  200
`define T_SIM_TXPR          5
`define T_SIM_TMOD          12
`define T_SIM_ZQINIT        64

// Outstanding 参数
`define MAX_OUTSTANDING     4

// 4KB 边界参数
`define AXI_4KB_MASK        12

`endif
