# DDR3 控制器项目实现报告 v2

## 1. 项目概述

本项目实现了一个基于 AXI4 接口的 DDR3 SDRAM 控制器，适用于教学与入门级 FPGA/ASIC 原型验证。控制器采用全同步单时钟设计（aclk），通过 DFI（DDR PHY Interface）标准接口对接 DDR3 PHY，支持 DDR3-1600 时序规格（近似）。

### 主要特性

| 特性 | 规格 |
|---|---|
| AXI 数据宽度 | 32-bit |
| AXI 地址宽度 | 32-bit |
| DDR3 几何 | 1Gb ×8，8 Bank，15位行地址，10位列地址 |
| 最大 Outstanding 读事务 | 4 |
| 4KB 地址边界保护 | ✓ |
| 初始化步骤 | 完整 11 步（MRS2/3/1/0 + ZQCL） |
| 饥饿防护 | 255周期饥饿强制调度 |

---

## 2. 整体架构

```
AXI Master
    │
    ▼
┌─────────────────┐
│  axi_slave_if   │  ← AXI4 五通道握手，Outstanding 计数
└────────┬────────┘
         │ req/wbuf/rbuf
         ▼
┌─────────────────┐
│   cmd_split     │  ← 4KB 边界检查 + Row 边界拆分
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ cmd_reorder_l1  │  ← Page-hit 优先 + 饥饿防护
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ cmd_reorder_l2  │  ← Refresh 优先级调度
└────────┬────────┘
         │
    ┌────┴──────┐
    │ Scheduler │  ← PRE/ACT/RD/WR 状态机
    └────┬──────┘
         │
         ▼
┌─────────────────┐
│    dfi_if       │  ← 命令编码 + CWL 写使能流水线 + phy_clk
└─────────────────┘
         │
    DDR3 PHY / Model
```

---

## 3. 模块详细说明

### 3.1 AXI Slave 接口（axi_slave_if）

负责处理 AXI4 的五通道握手协议，核心改进：

**Outstanding 读事务计数**：新增 `outstanding_rd_cnt`（3位计数器），允许最多 `MAX_OUTSTANDING=4` 笔读事务并发进行。原实现仅允许1笔在途读事务（`r_beats_rem==0`），新实现通过计数器解耦 arready 与 r_beats_rem，显著提升读带宽利用率。

```
AR握手成功 → outstanding_rd_cnt++
R通道 rlast 传递完成 → outstanding_rd_cnt--
arready = !ar_full && (outstanding_rd_cnt < MAX_OUTSTANDING)
```

### 3.2 命令拆分模块（cmd_split v2）

在原有 Row 边界拆分基础上，新增 **4KB 地址边界保护**：

```
4KB剩余字节 = 0x1000 - cur_addr[11:0]
beats_to_4k = 4KB剩余字节 / 4（4字节/beat）
最终chunk = min(row约束, 4KB约束, 剩余beats)
```

特殊处理：当地址恰好对齐 4KB 边界时，`boundary_4k = 0x1000`，`beats_to_4k_raw` 截取低9位为0，此时视为256 beats（AXI最大burst长度），不限制本次传输。

这一设计保证了 AMBA AXI4 协议的 4KB 边界不跨越规范（Section A3.4）。

### 3.3 命令重排序 L1（cmd_reorder_l1）

Page-hit 优先调度结合**饥饿计数器**防止 page-miss 请求无限期等待：

- **饥饿计数器**：每个队列槽位维护 8-bit 计数器 `q_starve[]`
- **累加逻辑**：每周期对所有有效槽位递增计数（饱和在 255）
- **强制调度**：若任意槽位饥饿计数达到 255，强制选择该槽位（最高优先级），覆盖 page-hit 决策
- **重置时机**：槽位被选中输出或新命令插入时，计数器归零

```
优先级：饥饿强制 > Page-hit > FIFO顺序
```

### 3.4 DFI 接口（dfi_if v2）

新增两项功能：

**phy_clk 输出**：`assign phy_clk = ~clk;` 提供 DDR PHY 所需的 180° 相位时钟。

**CWL 对齐写使能流水线**：使用 16-bit 移位寄存器 `wr_en_pipe`，在 WR 命令发出时设置 bit[CWL-1]（CWL=8 → bit7），每周期右移，当 bit0 为1时断言 `dfi_wrdata_en`。这确保写数据与内部 WR 命令之间精确 CWL 周期的时序对齐。

```
WR命令 → wr_en_pipe[7]=1
每周期 → wr_en_pipe >>= 1
8周期后 → wr_en_pipe[0]=1 → dfi_wrdata_en=1
```

### 3.5 初始化状态机（init_fsm v2）

实现完整 DDR3 JEDEC 规定的初始化序列（11步）：

```
S_CKE_LOW_WAIT  : CKE=0，等待 200 周期
S_CKE_DEASSERT  : CKE 上升（1 周期）
S_CKE_HIGH_WAIT : CKE=1，等待 tXPR=5 周期
S_MRS2          : MRS bank2, addr=0x0018（CWL=8）
S_WAIT_MRS2     : 等待 tMRD=4 周期
S_MRS3          : MRS bank3, addr=0x0000
S_WAIT_MRS3     : 等待 tMRD=4 周期
S_MRS1          : MRS bank1, addr=0x0004（DLL enable）
S_WAIT_MRS1     : 等待 tMRD=4 周期
S_MRS0          : MRS bank0, addr=0x0650（CL=11, DLL reset, BL=8）
S_WAIT_MRS0     : 等待 tMOD=12 周期
S_ZQCL          : ZQCL 校准命令
S_WAIT_ZQINIT   : 等待 tZQinit=64 周期（仿真缩短版）
S_DONE          : init_done=1
```

---

## 4. 参数配置

新增参数（ddr3_params.vh）：

```verilog
`define T_SIM_INIT_CKE_LOW  200   // CKE 低电平等待
`define T_SIM_TXPR          5     // tXPR（仿真加速）
`define T_SIM_TMOD          12    // tMOD
`define T_SIM_ZQINIT        64    // tZQinit（仿真加速）
`define T_INIT_TMRD         4     // tMRD
`define MAX_OUTSTANDING     4     // AXI 最大并发读事务
`define AXI_4KB_MASK        12    // 4KB 边界掩码位数
```

---

## 5. 仿真验证

### 5.1 测试覆盖

| 测试名称 | 功能 | 状态 |
|---|---|---|
| test_basic_rw | 基本读写验证 | ✓ |
| test_burst | 突发传输 | ✓ |
| test_page_hit | Page-hit 优先调度 | ✓ |
| test_reorder | 命令重排序 | ✓ |
| test_refresh | 刷新控制 | ✓ |
| test_4k_boundary | 4KB 边界拆分 | ✓ (新增) |
| test_outstanding | Outstanding 并发读 | ✓ (新增) |
| test_starvation | 饥饿防护机制 | ✓ (新增) |

### 5.2 编译验证

```bash
cd sim && make compile
# iverilog -g2012 -Wall -I../rtl -I../tb/tests ...
```

### 5.3 Scoreboard 性能统计

`scoreboard.sv` 新增性能统计能力：
- 写/读事务计数与 beat 累计
- 仿真时间测量（ns）
- 有效带宽估算（MB/s）

---

## 6. 综合约束

`syn/` 目录提供综合脚本模板：
- `syn/scripts/run_syn.tcl`：Synopsys DC 综合流程
- `syn/constraints/ddr3_ctrl_top.sdc`：时序约束（400 MHz 目标频率）

---

## 7. 已知限制与后续工作

1. **仿真加速**：初始化等待周期已大幅缩短；真实 DDR3 需扩展至 200us/500us
2. **PHY 模型**：当前使用行为级 ddr3_model.v，未集成 IBIS/HSPICE 信号完整性分析
3. **ECC**：未实现错误检测与纠正
4. **多周期路径**：地址映射与重排序逻辑存在多周期路径，需在 SDC 中声明
5. **功耗优化**：clock gating 与 power gating 未实现

---

*报告生成：DDR3 Controller Project v2*
