# DDR3 控制器设计规格说明（中文）

## 1. 目标
- 构建 AXI4 到 DDR3/DFI 的完整访问路径。
- 支持 burst、地址映射、命令拆分、重排、刷新与初始化。

## 2. 关键参数
- 数据宽度 32-bit，地址宽度 32-bit，ID 4-bit
- DDR3 几何：8 banks / 15-bit row / 10-bit col
- 时序参数见 `rtl/ddr3_params.vh`

## 3. 模块说明
- `axi_slave_if.v`：AXI 五通道握手与 FIFO 解耦
- `cmd_split.v`：跨行拆分
- `addr_map.v`：可配置映射策略
- `cmd_reorder_l1.v`：page-hit 插队
- `cmd_reorder_l2.v`：读写分组+优先级+auto-pre
- `bank_ctrl*.v`：bank 状态与时序约束
- `refresh_ctrl.v`：刷新请求与紧急刷新
- `init_fsm.v`：初始化时序
- `dfi_if.v`：命令映射到 DFI
- `ddr3_ctrl_top.v`：整体集成与调度

## 4. 验证
- `tb/tb_top.sv` 为统一入口，`+TESTNAME=` 选择用例
- 至少运行 `test_basic_rw`
