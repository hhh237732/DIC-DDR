content = """# DDR3 控制器项目实现报告 v2

> **版本**：v2.0 ｜ **日期**：2025-07 ｜ **作者**：数字 IC 设计组 ｜ **语言**：Verilog-2012

---

## 目录

1. 项目缘起与背景
2. 设计目标与约束
3. DDR3 器件几何与选型依据
4. 顶层架构图
5. 时钟与频率体系
6. AXI 接口设计
7. Command Split 与地址映射
8. Buffer 设计
9. 两级命令重排
10. Bank Controller
11. Refresh Controller
12. Initialization FSM
13. DFI 接口生成方法
14. 仲裁与调度
15. 完整工作流程举例
16. APB/AHB/AXI 全面对比
17. 前端流程：Lint→综合→形式→STA
18. 验证方案与覆盖率
19. 性能分析
20. 可扩展方向
21. Q&A 30+ 题
22. 目录与文件清单
23. 修订记录

---

## 1. 项目缘起与背景

### 1.1 背景

随着 SoC 设计规模的持续扩大，片上 SRAM 的容量已无法满足高性能计算、图像处理以及 AI 推理等应用场景对大容量、高带宽存储的需求。DDR3 SDRAM 作为第三代双倍数据速率同步动态随机存取存储器，以其成熟工艺、较高带宽和合理成本，成为消费电子、嵌入式系统和 FPGA 加速器的主流外存选择。

为了让片上处理器或 AXI 总线主设备能够高效访问外部 DDR3 器件，必须在二者之间插入一个 **DDR3 控制器（DDR3 Memory Controller）**。控制器负责：
- 将 AXI4 标准总线事务翻译为 DDR3 JEDEC 原语命令序列（ACTIVATE、READ、WRITE、PRECHARGE、REFRESH 等）；
- 维护 DDR3 电气时序约束（tRCD、tRP、tRAS、tRC、tFAW、tWTR、tRTP 等）；
- 通过 DFI（DDR PHY Interface）标准接口对接底层 PHY；
- 调度多路并发事务，最大化有效带宽，同时保证延迟上界。

### 1.2 项目缘起

本项目源于对开源 DDR 控制器（如 liteDRAM、MIG）学习过程中发现的以下痛点：
1. 已有开源实现代码量庞大、可读性差，难以作为教学参考；
2. AXI4 outstanding 支持、4KB 边界保护、两级重排序等关键功能分散在不同代码路径，不易理解；
3. 前端完整流程（Lint、综合、形式验证、STA）缺乏系统性文档。

因此，本项目从零开始设计一个功能完整、代码清晰、注释丰富的教学级 DDR3 控制器，并配套完整的前端流程脚本与验证环境。

### 1.3 应用场景

| 应用领域 | 代表需求 | 控制器关键指标 |
|---|---|---|
| FPGA 原型验证平台 | 大容量帧缓冲 | 低延迟、支持 burst |
| 嵌入式 AI 推理 | 权重加载 | 高带宽、顺序访问 |
| 图像处理加速 | 行/列扫描 | page-hit 率高 |
| 通用 SoC | 混合读写 | 公平调度、刷新准确 |

---

## 2. 设计目标与约束

### 2.1 功能目标

| 编号 | 目标 | 说明 |
|---|---|---|
| F1 | 完整 AXI4 从端接口 | 支持 INCR burst，4bit ID，32bit 数据/地址 |
| F2 | DDR3-1600 时序合规 | CL=11，CWL=8，tRCD=11，tRP=11，tRAS=28 |
| F3 | 4KB 地址边界保护 | 符合 AMBA AXI4 规范 Section A3.4 |
| F4 | 两级命令重排序 | L1 页命中优先 + L2 读写分组调度 |
| F5 | 自动刷新 | tREFI=6240 周期，优先级最高 |
| F6 | DDR3 完整初始化 | 14 状态 FSM，MR0~MR3 + ZQCL |
| F7 | DFI 标准接口 | phy_clk 输出，CWL 对齐写使能流水线 |
| F8 | MAX_OUTSTANDING=4 | 最多 4 笔并发读事务 |

### 2.2 性能约束

```
目标时钟频率：400 MHz（2.5 ns 周期）
DDR3 数据速率：800 Mbps（等效 DDR3-1600）
峰值读带宽：800M × 8bit = 6.4 Gbps（单 x8 器件）
峰值写带宽：同上
AXI 接口带宽：400 MHz × 32bit = 12.8 Gbps（理论，受 DDR3 限制）
```

### 2.3 面积与功耗约束

- 目标工艺：TSMC 28nm HPC（或同等 FPGA 资源）
- 逻辑面积预算：< 50K 等效门
- 动态功耗预算：< 50 mW（控制器本身，不含 PHY）

### 2.4 可验证性约束

- 功能覆盖率目标：> 95%
- 代码行覆盖率目标：> 90%
- 断言覆盖率目标：> 85%
- 所有主要时序路径均有 SDC 声明

---

## 3. DDR3 器件几何与选型依据

### 3.1 器件规格

本项目选用 **1Gb × 8** 组织的 DDR3 SDRAM，典型器件如 Micron MT41J128M8。

| 参数 | 数值 | 说明 |
|---|---|---|
| 总容量 | 1 Gbit = 128 MB | 1024M bit |
| 数据位宽 | ×8（8位） | DQ[7:0] |
| Bank 数 | 8（BA[2:0]） | 3位 Bank 地址 |
| 行地址位数 | 15 位（RA[14:0]） | 32768 行/Bank |
| 列地址位数 | 10 位（CA[9:0]） | 1024 列/Bank |
| Burst Length | 8 | DDR3 最小 BL=8 |
| 时序等级 | DDR3-1600（11-11-11） | CL/tRCD/tRP=11 |

### 3.2 存储单元容量推导

**容量验证：**
```
总 bit = Bank × Row × Col × DQ宽度
      = 8 × 32768 × 1024 × 8
      = 8 × 2^15 × 2^10 × 8
      = 8 × 2^25 × 8
      = 2^30 × 8 / 8... 

重新算：
Row = 2^15 = 32768
Col = 2^10 = 1024  （每列 8bit）
Bank内容量 = 32768 × 1024 × 8 bit = 268,435,456 bit = 256 Mbit
8个Bank = 8 × 256 Mbit = 2048 Mbit = 2 Gbit

注：x8 器件中，1024列 × 每列8bit × 8bank × 32768行 = 2Gbit？
实际 MT41J128M8 是 1Gbit：16384行 × 1024列 × 8bit × 8bank = 1Gbit
→ 行地址实际14位（2^14=16384）
本项目配置为15位行地址（用于更大容量版本或预留）
```

### 3.3 地址空间映射

```
物理地址 = {BA[2:0], RA[14:0], CA[9:0]}
         = 3 + 15 + 10 = 28 位地址线
→ 可寻址空间 = 2^28 × 8bit = 2Gbit（BA扩展到8bank）
```

AXI 地址到 DDR3 地址的映射（本项目实现）：

```
AXI addr[27:25] → BA[2:0]   （Bank 地址）
AXI addr[24:10] → RA[14:0]  （Row 地址）
AXI addr[ 9: 0] → CA[ 9:0]  （Column 地址）
```

### 3.4 关键时序参数（DDR3-1600 @ 400MHz）

| 参数 | 含义 | 周期数 | 时间 |
|---|---|---|---|
| CL=11 | CAS 潜伏期（读） | 11 | 27.5 ns |
| CWL=8 | CAS 写潜伏期 | 8 | 20 ns |
| tRCD=11 | RAS-CAS 延迟 | 11 | 27.5 ns |
| tRP=11 | 预充电时间 | 11 | 27.5 ns |
| tRAS=28 | 行激活保持时间 | 28 | 70 ns |
| tRC=39 | 行周期时间 | 39 | 97.5 ns |
| tFAW=22 | 四激活窗口 | 22 | 55 ns |
| tWTR=6 | 写后读延迟 | 6 | 15 ns |
| tRTP=5 | 读后预充电延迟 | 5 | 12.5 ns |
| tREFI=6240 | 平均刷新间隔 | 6240 | 15.6 us |
| tRFC=88 | 刷新周期时间 | 88 | 220 ns |

---

## 4. 顶层架构图

### 4.1 模块层次结构

```mermaid
graph LR
    AXI_Master["AXI Master\n(CPU/DMA)"]

    subgraph DDR3_Controller["DDR3 控制器顶层 ddr3_ctrl_top"]
        AXI_IF["axi_slave_if\nAXI4从端接口\nOutstanding=4"]
        CMD_SPLIT["cmd_split\n行边界+4KB边界拆分"]
        CMD_RO_L1["cmd_reorder_l1\nL1重排：页命中优先\n饥饿计数255阈值"]
        CMD_RO_L2["cmd_reorder_l2\nL2重排：读写分组\nGROUP_MAX=8\n刷新优先"]
        BANK_CTRL["bank_ctrl × 8\n每Bank独立FSM\n时序计数器"]
        SCHED["scheduler\nPRE/ACT/RD/WR\n命令选择"]
        REFRESH["refresh_ctrl\n自动刷新\ntREFI=6240"]
        INIT["init_fsm\n14状态初始化\nMR0~MR3+ZQCL"]
        DFI["dfi_if\nDFI接口\nCWL流水线\nphy_clk"]
    end

    PHY["DDR3 PHY\n(SSTL15)"]
    DRAM["DDR3 SDRAM\nMT41J128M8"]

    AXI_Master -->|"AR/AW/W/R/B"| AXI_IF
    AXI_IF -->|"cmd+data"| CMD_SPLIT
    CMD_SPLIT --> CMD_RO_L1
    CMD_RO_L1 --> CMD_RO_L2
    CMD_RO_L2 --> SCHED
    REFRESH -->|"REF命令"| SCHED
    INIT -->|"初始化命令"| DFI
    SCHED --> BANK_CTRL
    BANK_CTRL -->|"timing OK信号"| SCHED
    SCHED -->|"ACT/RD/WR/PRE"| DFI
    DFI -->|"DFI信号"| PHY
    PHY -->|"LPDDR信号"| DRAM
```

### 4.2 数据流概览

```
写路径：AXI-W → 写数据缓冲 → DFI写数据 → PHY → DDR3
读路径：DDR3 → PHY → DFI读数据 → 读数据缓冲 → AXI-R

命令路径：AXI-AW/AR → cmd_split → L1重排 → L2重排 → 调度器
         → bank_ctrl（时序检查）→ DFI命令 → PHY → DDR3
```

---

## 5. 时钟与频率体系

### 5.1 时钟域设计

本项目采用**单时钟域**设计，所有逻辑使用同一时钟 `aclk`，消除跨时钟域（CDC）复杂性：

```
aclk (400 MHz)
  ├── AXI 接口逻辑
  ├── cmd_split / reorder
  ├── bank_ctrl × 8
  ├── refresh_ctrl
  ├── init_fsm
  └── dfi_if（控制信号同步）

phy_clk = ~aclk（180° 反相）
  └── DDR3 PHY 时钟输入（DDR 数据在两个相位边沿采样）
```

### 5.2 频率关系

```
控制器时钟：aclk = 400 MHz（周期 2.5 ns）
PHY 时钟：  phy_clk = 400 MHz，相位差 180°
DDR3 数据率：800 Mbps（双沿，等效 DDR3-1600）
AXI 总线频率：与 aclk 相同（400 MHz）
```

### 5.3 phy_clk 生成

```verilog
// dfi_if.v 中
assign phy_clk = ~clk;
// 注：实际设计中应使用专用时钟缓冲（BUFG/OBUFDS），
// 此处为仿真简化实现
```

### 5.4 DFI 接口时钟对齐

DFI 规范要求控制信号（cmd_addr）在时钟上升沿锁存，写数据（wrdata）在 CWL 之后的时钟边沿有效：

```
控制器周期 t0:   发出 WR 命令 → dfi_cs_n/ras_n/cas_n/we_n 有效
控制器周期 t8:   写数据应出现在 DFI 总线（CWL=8）
控制器周期 t8:   dfi_wrdata_en = 1（由 wr_en_pipe 流水线产生）
```

---

## 6. AXI 接口设计

### 6.1 AXI4 通道概述

AXI4（Advanced eXtensible Interface 4）是 ARM AMBA 总线协议族的第四代，采用独立的五通道握手机制：

| 通道 | 方向（从端视角） | 功能 |
|---|---|---|
| AW（写地址） | 输入 | 写事务地址和控制信息 |
| W（写数据） | 输入 | 写数据和字节使能 |
| B（写响应） | 输出 | 写事务完成状态 |
| AR（读地址） | 输入 | 读事务地址和控制信息 |
| R（读数据） | 输出 | 读数据和完成状态 |

### 6.2 关键信号列表

```verilog
// 写地址通道
input  [3:0]  s_awid;      // 事务 ID
input  [31:0] s_awaddr;    // 起始地址
input  [7:0]  s_awlen;     // burst 长度 = awlen+1 beats
input  [2:0]  s_awsize;    // beat 宽度（010 = 4字节）
input  [1:0]  s_awburst;   // burst 类型（01=INCR）
input         s_awvalid;
output        s_awready;

// 读地址通道（类似 AW）
// 写数据通道
input  [31:0] s_wdata;
input  [3:0]  s_wstrb;     // 字节使能
input         s_wlast;
// ...
```

### 6.3 Outstanding 读事务设计

**传统实现（单笔 outstanding）：**
```
AR 接受 → 等待 R 通道 rlast → 再接受下一笔 AR
缺陷：DDR3 读延迟（CL=11）造成总线空闲，带宽浪费
```

**本项目实现（MAX_OUTSTANDING=4）：**
```verilog
// 3位计数器，最大值4
reg [2:0] outstanding_rd_cnt;

// AR握手增加计数
always @(posedge clk) begin
    if (s_arvalid && s_arready)
        outstanding_rd_cnt <= outstanding_rd_cnt + 1;
    else if (s_rlast && s_rvalid && s_rready)
        outstanding_rd_cnt <= outstanding_rd_cnt - 1;
end

// arready 条件：队列未满 且 outstanding 未达上限
assign s_arready = !ar_queue_full && 
                   (outstanding_rd_cnt < MAX_OUTSTANDING);
```

**效果分析：**
```
读延迟：CL=11 周期 = 27.5 ns
若只有 1 笔 outstanding，每笔读事务需等待约 11+BL 周期
4笔 outstanding 可以流水化，效率提升 ~3.5×（理论）
```

### 6.4 4KB 边界依据

AMBA AXI4 规范 Section A3.4.1 规定：**任何 burst 事务不得跨越 4KB 地址边界**，原因是：

1. 系统总线可能将 4KB 对齐的地址段映射到不同从端设备；
2. 若 burst 跨越边界，低位地址的 slave 可能收到多余的节拍，导致协议违规；
3. 内存管理单元（MMU）的页面通常为 4KB 对齐，跨越边界意味着跨越物理页面。

因此，控制器的 `cmd_split` 模块必须在生成 DDR3 命令序列前，检查并在 4KB 边界处将 AXI burst 截断。

### 6.5 写响应时序

```
写事务完成条件：
1. 所有写数据 beat 已通过 W 通道传输（wlast 接收）
2. DDR3 写命令已成功发出（bank_ctrl timing 满足）
3. tWR（写恢复时间）完成后，BVALID 拉高
4. BREADY 握手完成，事务结束
```

---

## 7. Command Split 与地址映射

### 7.1 模块功能

`cmd_split` 模块将一个 AXI burst 事务拆分为若干**chunk（块）**，每个 chunk 满足以下约束：
- 不跨越 DDR3 行边界（同一 bank 内）
- 不跨越 AXI 4KB 地址边界
- 长度为 AXI burst 的整数个 beat

### 7.2 拆分算法

```python
# 伪代码（cmd_split 逻辑）
def split_burst(addr, len_beats):
    chunks = []
    cur_addr = addr
    rem_beats = len_beats
    
    while rem_beats > 0:
        # 计算行内剩余 beats
        col_bits = cur_addr[9:2]   # 列地址（4字节/beat → 右移2位）
        beats_to_row_end = (1024 - col_bits)  # 行内剩余列数
        
        # 计算 4KB 边界内剩余 beats
        offset_in_4k = cur_addr[11:0]
        bytes_to_4k = 0x1000 - offset_in_4k
        beats_to_4k = bytes_to_4k >> 2  # 每beat 4字节
        if beats_to_4k == 0:
            beats_to_4k = 256  # 恰好对齐时不限制
        
        # 本 chunk 的长度
        chunk_len = min(beats_to_row_end, beats_to_4k, rem_beats)
        
        # 提取 DDR3 地址
        bank = cur_addr[27:25]
        row  = cur_addr[24:10]
        col  = cur_addr[ 9: 2]
        
        chunks.append({bank, row, col, chunk_len, is_write})
        
        cur_addr += chunk_len * 4
        rem_beats -= chunk_len
    
    return chunks
```

### 7.3 拆分示例

**场景：** AXI 写事务，起始地址=0x00000FF0，长度=16 beats（64 字节）

```
起始地址：0x00000FF0
  - BA = addr[27:25] = 0
  - RA = addr[24:10] = 0x3C（即行63）
  - CA = addr[ 9: 2] = 0x3FC >> 2 = 0xFF = 252 列

行内剩余：1024 - 252 = 772 列 > 16，行边界不限制

4KB 偏移：0xFF0 → 距 4KB 边界 = 0x1000 - 0xFF0 = 0x10 = 16 字节 = 4 beats

→ Chunk 1：addr=0xFF0，len=4，bank=0，row=63，col=252
→ Chunk 2：addr=0x1000，len=12，bank=0，row=64，col=0
          （4KB 边界后，重新计算行地址：addr[24:10]变化）
```

### 7.4 地址映射寄存器

```verilog
// AXI 地址到 DDR3 地址映射
assign bank_addr = axi_addr[27:25];   // [2:0]   3位 bank
assign row_addr  = axi_addr[24:10];   // [14:0] 15位 row  
assign col_addr  = axi_addr[ 9: 2];   // [9:0]  10位 col（字节地址>>2）
// axi_addr[1:0] 为字节偏移，不传入 DDR3
```

---

## 8. Buffer 设计

### 8.1 写数据缓冲（Write Data Buffer）

写数据缓冲位于 AXI W 通道和 DFI 写数据路径之间，采用简单 FIFO 结构：

```
深度：16 × 32bit（可配置）
功能：
  1. 解耦 AXI 写数据接收与 DDR3 写命令时序
  2. 允许 AXI 主端提前发送写数据，提升总线利用率
  3. 在 DDR3 写延迟（CWL=8 周期）内缓存数据
```

```verilog
// 写数据 FIFO 简化示意
module wdata_fifo #(
    parameter DEPTH = 16,
    parameter WIDTH = 32
) (
    input  clk, rst_n,
    input  [WIDTH-1:0] wr_data,
    input  [3:0]       wr_strb,
    input              wr_en,
    output             full,
    output [WIDTH-1:0] rd_data,
    output [3:0]       rd_strb,
    input              rd_en,
    output             empty
);
```

### 8.2 读数据缓冲（Read Data Buffer）

读数据返回路径同样需要缓冲，因为 DDR3 读数据在 CL（=11）周期后才返回，而 AXI R 通道需要及时响应：

```
深度：MAX_OUTSTANDING × BL = 4 × 8 = 32 × 32bit
功能：
  1. 存储从 DFI 读回的数据
  2. 关联 AXI 事务 ID（ARID → RID 映射）
  3. 维护读数据返回顺序（按 AXI ID 排序或 FIFO）
```

### 8.3 命令队列（Command Queue）

L1/L2 重排序模块维护命令队列：

```
L1 队列深度：8（可配置）
每个队列槽位包含：
  - cmd_valid：槽位有效位
  - bank, row, col：DDR3 地址
  - len：本 chunk 的 beat 数
  - is_write：读/写标志
  - axid：AXI 事务 ID（用于读数据关联）
  - q_starve[7:0]：饥饿计数器（L1 专用）
```

---

## 9. 两级命令重排

### 9.1 设计动机

DDR3 SDRAM 性能与 **page-hit（开页命中）** 率密切相关：
- **Page hit（页命中）**：目标 bank 已激活且行地址匹配，直接发 CAS 命令，延迟最小（仅 tCL）
- **Page miss（页缺失）**：目标 bank 已激活但行不匹配，需先 PRE 后 ACT，额外延迟 tRP+tRCD
- **Page empty（页空）**：目标 bank 未激活，需 ACT，额外延迟 tRCD

通过重排序，优先服务与当前激活行相同的命令，可显著提高 page-hit 率，从而提升带宽和降低平均延迟。

### 9.2 L1 重排（cmd_reorder_l1）

**功能：** Page-hit 优先队列 + 饥饿防护

#### 9.2.1 算法伪代码

```python
# L1 重排选择逻辑
def select_cmd_l1(queue, bank_open_row):
    # 优先级 1：饥饿强制（任意槽位计数达 255）
    for slot in queue:
        if slot.valid and slot.starve_cnt == 255:
            return slot  # 强制选择，防饥饿
    
    # 优先级 2：Page hit（bank 已打开且行匹配）
    for slot in queue:
        if slot.valid:
            if bank_open_row[slot.bank] == slot.row:
                return slot  # 页命中
    
    # 优先级 3：FIFO 顺序（最早入队）
    return queue.front()

# 饥饿计数器更新
def update_starve(queue, selected_slot):
    for slot in queue:
        if slot.valid:
            if slot == selected_slot:
                slot.starve_cnt = 0  # 选中时清零
            else:
                slot.starve_cnt = min(slot.starve_cnt + 1, 255)  # 饱和递增
```

#### 9.2.2 硬件实现关键代码

```verilog
// 饥饿计数器阵列（8个槽位，每个8位）
reg [7:0] q_starve [0:QUEUE_DEPTH-1];

// 饥饿检测：任意有效槽位达 255
wire starve_force;
wire [QUEUE_DEPTH-1:0] starve_hit;
genvar i;
generate
    for (i = 0; i < QUEUE_DEPTH; i = i+1) begin
        assign starve_hit[i] = q_valid[i] && (q_starve[i] == 8'hFF);
    end
endgenerate
assign starve_force = |starve_hit;

// 每周期更新饥饿计数
always @(posedge clk or negedge rst_n) begin
    for (int j = 0; j < QUEUE_DEPTH; j++) begin
        if (q_valid[j]) begin
            if (selected_idx == j && cmd_accepted)
                q_starve[j] <= 8'h00;
            else if (q_starve[j] != 8'hFF)
                q_starve[j] <= q_starve[j] + 1;
        end
    end
end
```

#### 9.2.3 L1 调度示例

```
时刻 T0：队列状态
  Slot0: bank=2, row=100, col=0,  write, starve=0   ← 当前激活行：bank2 row=100
  Slot1: bank=2, row=200, col=0,  write, starve=50
  Slot2: bank=2, row=100, col=4,  read,  starve=80  ← page hit!
  Slot3: bank=3, row=50,  col=0,  read,  starve=120

T0 决策：Slot2 page-hit → 选 Slot2（更新 starve[2]=0，其余递增）

时刻 T10：Slot1.starve 达到 255
  强制选择 Slot1（即使不是 page-hit）→ 防止 row=200 饥饿
```

### 9.3 L2 重排（cmd_reorder_l2）

**功能：** 读写分组调度 + 刷新优先级

#### 9.3.1 读写分组原理

DDR3 读写切换需要额外的时序开销（tWTR、tRTW），因此将连续的读命令或写命令分组执行，可减少切换次数：

```
GROUP_MAX = 8：每组最多连续服务 8 笔同类型命令
切换条件：
  1. 当前组已达 GROUP_MAX
  2. 当前组队列为空，切换到另一类型
  3. 刷新请求到来（最高优先级，中断当前组）
```

#### 9.3.2 L2 状态机

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> REFRESH_WAIT : refresh_req（最高优先级）
    IDLE --> READ_GROUP : 有读命令
    IDLE --> WRITE_GROUP : 有写命令（无读命令）
    READ_GROUP --> REFRESH_WAIT : refresh_req
    READ_GROUP --> WRITE_GROUP : group_cnt==GROUP_MAX 或读队列空
    WRITE_GROUP --> REFRESH_WAIT : refresh_req
    WRITE_GROUP --> READ_GROUP : group_cnt==GROUP_MAX 或写队列空
    REFRESH_WAIT --> IDLE : refresh_done
```

#### 9.3.3 调度优先级表

| 优先级 | 条件 | 动作 |
|---|---|---|
| 1（最高） | refresh_req=1 | 暂停读写，发刷新命令 |
| 2 | 当前组未满 且 同类命令可用 | 继续当前读/写组 |
| 3 | 当前组满 或 当前组无命令 | 切换读/写模式 |
| 4（最低） | 队列空 | IDLE 等待 |

---

## 10. Bank Controller

### 10.1 功能描述

每个 Bank 有独立的 `bank_ctrl` 实例（共 8 个），负责：
1. 跟踪该 bank 当前状态（空闲/激活/关闭中）
2. 维护各类时序计数器，确保命令间隔满足 DDR3 规范
3. 向调度器报告该 bank 是否准备好接收新命令

### 10.2 Bank FSM 状态图

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> ACTIVATING : 收到 ACT 命令
    ACTIVATING --> ACTIVE : tRCD 计数完成
    ACTIVE --> READING : 收到 RD 命令（page hit）
    ACTIVE --> WRITING : 收到 WR 命令（page hit）
    ACTIVE --> PRECHARGING : 收到 PRE 命令
    READING --> ACTIVE : tRTP 计数完成（可继续）
    READING --> PRECHARGING : 收到 PRE（tRTP 后）
    WRITING --> ACTIVE : tWR 计数完成（可继续）
    WRITING --> PRECHARGING : 收到 PRE（tWR 后）
    PRECHARGING --> IDLE : tRP 计数完成
    IDLE --> REFRESHING : 收到 REF 命令
    REFRESHING --> IDLE : tRFC 计数完成
```

### 10.3 时序计数器说明

| 计数器 | 起始状态 | 结束条件 | 作用 |
|---|---|---|---|
| tRCD 计数器 | ACT 命令后 | 计数到 11 | 限制 ACT→CAS 最小间隔 |
| tRAS 计数器 | ACT 命令后 | 计数到 28 | 限制 ACT→PRE 最小间隔 |
| tRP 计数器 | PRE 命令后 | 计数到 11 | 限制 PRE→ACT 最小间隔 |
| tRC 计数器 | ACT 命令后 | 计数到 39 | 限制同 bank 连续 ACT 间隔 |
| tFAW 计数器 | 任意 ACT 后 | 窗口内 ACT≤4 | 限制 4 激活窗口 |
| tWTR 计数器 | WR 命令后 | 计数到 6 | 限制 WR→RD 最小间隔 |
| tRTP 计数器 | RD 命令后 | 计数到 5 | 限制 RD→PRE 最小间隔 |

### 10.4 关键 Verilog 实现

```verilog
// bank_ctrl.v 片段：tRCD 计数器
reg [3:0] trcd_cnt;
reg       trcd_done;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        trcd_cnt  <= 4'd0;
        trcd_done <= 1'b0;
    end else if (act_cmd_recv) begin
        trcd_cnt  <= T_RCD;     // 加载初值 11
        trcd_done <= 1'b0;
    end else if (trcd_cnt > 0) begin
        trcd_cnt  <= trcd_cnt - 1;
        trcd_done <= (trcd_cnt == 4'd1);
    end
end

// tFAW：滑动窗口计数（记录最近4次ACT的时间戳）
reg [5:0] act_time [0:3];  // 记录最近4次ACT的时刻
reg [1:0] act_ptr;

always @(posedge clk) begin
    if (act_cmd_recv) begin
        act_time[act_ptr] <= current_time[5:0];
        act_ptr <= act_ptr + 1;
    end
end

// tFAW 检查：最早的ACT是否超出22周期窗口
wire tfaw_ok = (current_time - act_time[act_ptr] >= T_FAW) || 
               (act_count_in_window < 4);
```

### 10.5 Bank 状态上报接口

```verilog
// bank_ctrl 输出信号
output reg  bank_idle;       // bank 未激活
output reg  bank_active;     // bank 已激活
output reg [14:0] open_row;  // 当前激活行地址
output reg  cas_rdy;         // tRCD 满足，可发 CAS
output reg  pre_rdy;         // tRAS/tRTP/tWR 满足，可发 PRE
output reg  act_rdy;         // tRP/tRC 满足，可发 ACT
output reg  ref_rdy;         // 可接受刷新命令
```

---

## 11. Refresh Controller

### 11.1 功能

DDR3 DRAM 中的存储单元为电容，电荷会随时间泄漏，必须定期刷新以保持数据完整性。JEDEC 规定：
- **tREFI = 7.8 µs**（64ms / 8192 行 ≈ 7.8 µs/行）
- 等效控制器时钟周期：7.8 µs × 400 MHz = 3120 周期（标准）
- 本项目使用 **tREFI = 6240 周期**（约 15.6 µs，较保守，或针对工业级温度范围使用 3.9 µs → 1560 周期）

> 注：本项目配置为 6240 周期，实际部署需根据 DRAM 型号和工作温度范围调整。

### 11.2 刷新计时器

```verilog
// refresh_ctrl.v
parameter T_REFI = 6240;
parameter T_RFC  = 88;

reg [12:0] refi_cnt;   // 13位，最大8191
reg [6:0]  rfc_cnt;    // 7位，最大127

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        refi_cnt <= T_REFI;
        refresh_req <= 1'b0;
    end else begin
        if (refi_cnt == 13'd0) begin
            refresh_req <= 1'b1;
            refi_cnt <= T_REFI;  // 重载
        end else begin
            refi_cnt <= refi_cnt - 1;
        end
        // 刷新命令被接受后清除请求
        if (refresh_ack)
            refresh_req <= 1'b0;
    end
end
```

### 11.3 刷新优先级

刷新请求（`refresh_req`）在 L2 重排序模块中具有**最高优先级**，会中断正在进行的读写组调度。这确保了刷新不会延误超过一个 tREFI 周期。

### 11.4 延迟刷新（Deferred Refresh）

在某些高负载场景中，允许积累最多 8 笔延迟刷新（JEDEC 规定），通过 refresh 计数器实现：

```verilog
reg [3:0] refresh_pending;  // 未处理的刷新请求数
// 每次 tREFI 到期 +1，每次刷新命令发出 -1
// 若 refresh_pending >= 8，强制暂停所有访问
```

---

## 12. Initialization FSM

### 12.1 DDR3 初始化序列

DDR3 JEDEC 标准（JESD79-3F）规定了严格的上电初始化序列。本项目实现完整 14 状态 FSM：

```mermaid
stateDiagram-v2
    [*] --> CKE_LOW_WAIT : 上电复位
    CKE_LOW_WAIT --> CKE_DEASSERT : 等待200周期（tCKE）
    CKE_DEASSERT --> CKE_HIGH_WAIT : CKE置高（1周期）
    CKE_HIGH_WAIT --> MRS2 : 等待tXPR=5周期
    MRS2 --> WAIT_MRS2 : 发送MR2命令
    WAIT_MRS2 --> MRS3 : 等待tMRD=4周期
    MRS3 --> WAIT_MRS3 : 发送MR3命令
    WAIT_MRS3 --> MRS1 : 等待tMRD=4周期
    MRS1 --> WAIT_MRS1 : 发送MR1命令
    WAIT_MRS1 --> MRS0 : 等待tMRD=4周期
    MRS0 --> WAIT_MRS0 : 发送MR0命令
    WAIT_MRS0 --> ZQCL : 等待tMOD=12周期
    ZQCL --> WAIT_ZQINIT : 发送ZQCL命令
    WAIT_ZQINIT --> DONE : 等待tZQinit=64周期
    DONE --> [*] : init_done=1
```

### 12.2 MR 寄存器位域说明

#### MR0（Bank 0）= 0x0650

| 位域 | [1:0] | [3] | [6:4] | [7] | [11:9] | [8] | [12] |
|---|---|---|---|---|---|---|---|
| 名称 | BL | BT | CL[2:0] | TM | WR[2:0] | DLL Reset | PPD |
| 值 | 00（BL8） | 0（顺序） | 110（CL=11） | 0 | 010（WR=12） | 1（复位DLL） | 0 |

计算：BL=00，BT=0，CL=0110→11，DLL_reset=1，WR=010→12
→ 0x0650 = 0000_0110_0101_0000（二进制验证：bit12-bit9=0010=WR12，bit6-4=110=CL11，bit8=1=DLL reset，bit1-0=00=BL8）

#### MR1（Bank 1）= 0x0004

| 位域 | [0] | [1] | [5:3] | [7] | [9:8] |
|---|---|---|---|---|---|
| 名称 | DLL Enable | Output Drive | Rtt_Nom | Write Leveling | Additive Latency |
| 值 | 0（使能DLL） | 0（全驱动） | 001（RZQ/4=60Ω） | 0 | 00 |

注：bit[2]=0, bit[1]=0, bit[0]=0（DLL enable），bit[3:5]=001→Rtt_Nom=RZQ/4
→ 0x0004 表示 Rtt_Nom=RZQ/6 实际 bit[5:3]=010 → 0x0008... 
实际本项目 MR1=0x0004 对应 bit2=1 → Rtt_Nom=RZQ/6（Rtt_Nom[2:0]=bit[9,6,2]）

#### MR2（Bank 2）= 0x0018

| 位域 | [2:0] | [5:3] | [8:7] | [10:9] |
|---|---|---|---|---|
| 名称 | Partial Array | CWL | Auto Self Refresh | Rtt_WR |
| 值 | 000 | 011（CWL=8） | 00 | 00（关闭） |

CWL 编码：000=5，001=6，010=7，011=8 → 0x0018 = bit[5:3]=011（CWL=8）✓

#### MR3（Bank 3）= 0x0000

| 位域 | [1:0] | [2] |
|---|---|---|
| 名称 | MPR Location | MPR Enable |
| 值 | 00 | 0（正常模式） |

所有位为 0，禁用 MPR（多用途寄存器）功能，进入正常工作模式。

### 12.3 初始化计时器配置

```verilog
// ddr3_params.vh
`define T_SIM_INIT_CKE_LOW  200   // 真实值：200us × 400MHz = 80000周期
`define T_SIM_TXPR          5     // 真实值：tXPR ≥ max(5nCK, tRFC+10ns)
`define T_INIT_TMRD         4     // tMRD = 4 nCK
`define T_SIM_TMOD          12    // tMOD = max(12nCK, 15ns)
`define T_SIM_ZQINIT        64    // 真实值：512 nCK
```

---

## 13. DFI 接口生成方法

### 13.1 DFI 简介

DFI（DDR PHY Interface）是一种标准化的控制器-PHY 接口规范，将控制器逻辑与 PHY 模拟电路解耦，简化跨厂商的 PHY 复用。

### 13.2 DFI 信号列表

```verilog
// dfi_if.v 输出信号
output reg        dfi_cke;       // Clock Enable
output reg        dfi_cs_n;      // Chip Select（低有效）
output reg        dfi_ras_n;     // Row Address Strobe
output reg        dfi_cas_n;     // Column Address Strobe
output reg        dfi_we_n;      // Write Enable
output reg [2:0]  dfi_bank;      // Bank 地址
output reg [14:0] dfi_address;   // 行/列地址复用
output reg [31:0] dfi_wrdata;    // 写数据
output reg [3:0]  dfi_wrdata_mask; // 写数据掩码（低有效）
output reg        dfi_wrdata_en; // 写数据使能
input  [31:0]     dfi_rddata;    // 读数据（来自PHY）
input             dfi_rddata_valid; // 读数据有效
output            phy_clk;       // PHY 时钟（~aclk）
```

### 13.3 命令编码

DDR3 命令由 {CS_n, RAS_n, CAS_n, WE_n} 四位编码：

| 命令 | CS_n | RAS_n | CAS_n | WE_n | 说明 |
|---|---|---|---|---|---|
| NOP | 0 | 1 | 1 | 1 | 无操作 |
| ACTIVATE | 0 | 0 | 1 | 1 | 激活行（addr=RA，bank=BA） |
| READ | 0 | 1 | 0 | 1 | 读列（addr=CA，A10=AP） |
| WRITE | 0 | 1 | 0 | 0 | 写列 |
| PRECHARGE | 0 | 0 | 1 | 0 | 预充电（A10=all） |
| REFRESH | 0 | 0 | 0 | 1 | 自动刷新 |
| MRS | 0 | 0 | 0 | 0 | 模式寄存器设置 |
| DESELECT | 1 | x | x | x | 取消选择 |

```verilog
// dfi_if.v 命令发送
always @(posedge clk) begin
    case (cmd_in)
        CMD_NOP:  {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0111;
        CMD_ACT:  {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0011;
        CMD_RD:   {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0101;
        CMD_WR:   {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0100;
        CMD_PRE:  {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0010;
        CMD_REF:  {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0001;
        CMD_MRS:  {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b0000;
        default:  {dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n} <= 4'b1111;
    endcase
end
```

### 13.4 写路径时序

```
周期   命令/数据
 T0    WR 命令（dfi_cs_n=0, cas_n=0, we_n=0）
 T1    NOP
 T2    NOP
 ...   ...（CWL-1 个 NOP）
 T8    dfi_wrdata_en=1，dfi_wrdata=D0（CWL=8）
 T9    dfi_wrdata=D1（第2个 beat）
 ...   （BL=8，持续8个周期）
 T15   dfi_wrdata=D7（最后一个 beat）
 T16   dfi_wrdata_en=0
```

**CWL 对齐写使能流水线实现：**

```verilog
// 16 位移位寄存器（足够覆盖 CWL 最大 12）
reg [15:0] wr_en_pipe;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_en_pipe <= 16'b0;
    end else begin
        // 右移
        wr_en_pipe <= {1'b0, wr_en_pipe[15:1]};
        // WR 命令时，在 bit[CWL-1] 设置标志
        if (wr_cmd_sent)
            wr_en_pipe[CWL-1] <= 1'b1;
    end
end

// bit0 为 1 时断言写使能
assign dfi_wrdata_en = wr_en_pipe[0];
```

### 13.5 读路径时序

```
周期   命令/数据
 T0    RD 命令（dfi_cs_n=0, cas_n=0, we_n=1）
 T1-T10 NOP
 T11   dfi_rddata_valid=1，dfi_rddata=D0（CL=11，来自PHY）
 T12   dfi_rddata=D1
 ...
 T18   dfi_rddata=D7（BL=8）
 T19   dfi_rddata_valid=0
```

读延迟由 PHY 内部处理，控制器通过 `dfi_rddata_valid` 信号识别有效数据窗口。

---

## 14. 仲裁与调度

### 14.1 关键术语说明

| 术语 | 英文 | 说明 |
|---|---|---|
| chunk | chunk | cmd_split 拆分后的最小服务单元，不跨行/4KB边界 |
| page hit | Page Hit | Bank 已激活且行地址匹配，可直接 CAS |
| page miss | Page Miss | Bank 已激活但行不匹配，需 PRE+ACT |
| page empty | Page Empty | Bank 未激活，需 ACT |
| tFAW | Four Activate Window | 任意 4 行激活命令窗口不超过 tFAW 时间 |
| outstanding | Outstanding | AXI 总线上已发出但未完成的事务数量 |
| starvation | Starvation | 低优先级命令长期得不到服务的饥饿状态 |

### 14.2 完整调度优先级

| 优先级 | 条件 | 说明 |
|---|---|---|
| P0（最高） | init_done=0 | 初始化命令绝对优先 |
| P1 | refresh_req && all_banks_idle | 刷新命令 |
| P2 | starve_cnt==255 | 饥饿强制（任意 L1 队列项） |
| P3 | page_hit && same_group | 同组类型的页命中命令 |
| P4 | same_group（读/写组） | 同组类型但非页命中 |
| P5 | group_switch | 读写组切换 |
| P6（最低） | IDLE | 所有队列空，发 NOP |

### 14.3 调度器状态机

```verilog
// scheduler 主 FSM（简化）
typedef enum {
    S_IDLE,
    S_ACTIVATE,    // 发 ACT 命令
    S_WAIT_RCD,    // 等待 tRCD
    S_CAS,         // 发 RD/WR 命令
    S_WAIT_DATA,   // 等待读数据返回
    S_PRECHARGE,   // 发 PRE 命令
    S_WAIT_RP,     // 等待 tRP
    S_REFRESH      // 发 REF 命令
} sched_state_t;
```

### 14.4 调度示例

**场景：** 4 笔并发读事务，地址分布在不同 bank

```
事务1：bank=0, row=100, col=0（读 8beat）
事务2：bank=1, row=200, col=0（读 8beat）
事务3：bank=0, row=100, col=8（读 8beat） ← 与事务1同行，page hit 候选
事务4：bank=2, row=300, col=0（写 8beat）

调度序列（L2 处于 READ_GROUP）：
T0:  事务1 → ACT bank0 row100
T11: 事务1 → RD bank0 col0（tRCD满足）
T11: 事务2 → ACT bank1 row200（与bank0 ACT并行）
T12: 事务3 → L1 page-hit，优先排队
T19: 事务3 → RD bank0 col8（事务1结束后立即服务，page hit）
T22: 事务2 → RD bank1 col0（tRCD满足）
... L2 group_cnt=3（READ_GROUP，已服务3笔读）
T40: 事务4 → L2 切换至 WRITE_GROUP → ACT bank2 row300 → WR
```

---

## 15. 完整工作流程举例

### 15.1 例1：单笔 AXI 写事务

```mermaid
sequenceDiagram
    participant M as AXI Master
    participant AIF as axi_slave_if
    participant CS as cmd_split
    participant L1 as reorder_l1
    participant SC as scheduler
    participant BC as bank_ctrl
    participant DFI as dfi_if
    participant DDR as DDR3

    M->>AIF: AW(addr=0x100, len=7, INCR)
    AIF->>M: AWREADY=1
    M->>AIF: W(D0..D7, wlast)
    AIF->>CS: cmd(bank=0,row=1,col=4, wr, len=8)
    CS->>L1: chunk(bank=0,row=1,col=4, wr, len=8)
    L1->>SC: cmd(page_empty, bank=0)
    SC->>BC: check_timing(bank=0)
    BC->>SC: act_rdy=1
    SC->>DFI: ACT(bank=0, row=1)
    DFI->>DDR: RAS_n=0, addr=row1
    Note over DDR: tRCD=11周期
    SC->>DFI: WR(bank=0, col=4)
    DFI->>DDR: CAS_n=0,WE_n=0
    Note over DFI: CWL=8周期后
    DFI->>DDR: wrdata=D0..D7
    DDR-->>DFI: 写完成
    AIF->>M: B(BRESP=OKAY)
```

### 15.2 例2：读写交替（含 tWTR）

```mermaid
sequenceDiagram
    participant SC as scheduler
    participant BC as bank_ctrl
    participant DFI as dfi_if
    participant DDR as DDR3

    SC->>DFI: WR(bank=0, col=0)
    DFI->>DDR: Write Data(D0..D7)
    Note over BC: tWTR计数=6
    Note over BC: 6周期内禁止RD命令（同bank）
    SC->>DFI: NOP × 6（等待tWTR）
    SC->>DFI: RD(bank=0, col=8)
    DFI->>DDR: READ命令
    Note over DDR: CL=11周期
    DDR-->>DFI: rddata=D0..D7（rddata_valid=1）
```

### 15.3 例3：刷新中断读操作

```mermaid
sequenceDiagram
    participant RF as refresh_ctrl
    participant L2 as reorder_l2
    participant SC as scheduler
    participant DFI as dfi_if
    participant DDR as DDR3

    Note over RF: tREFI=6240周期到期
    RF->>L2: refresh_req=1（最高优先级）
    L2->>SC: 暂停当前读组，发刷新命令
    SC->>DFI: PRE ALL（预充电所有bank）
    Note over DDR: 等待所有bank空闲
    SC->>DFI: REF（REFRESH命令）
    DFI->>DDR: RAS_n=0, CAS_n=0, WE_n=1
    Note over DDR: tRFC=88周期
    RF->>L2: refresh_done=1
    L2->>SC: 恢复读组调度
```

### 15.4 例4：4KB 边界拆分

```mermaid
sequenceDiagram
    participant M as AXI Master
    participant AIF as axi_slave_if
    participant CS as cmd_split
    participant L1 as reorder_l1

    M->>AIF: AW(addr=0xFFC, len=15, INCR)
    Note over CS: 地址0xFFC，16beats=64B
    Note over CS: 4KB边界：0x1000-0xFFC=4B=1beat
    CS->>L1: chunk1(addr=0xFFC, bank=0, row=63, col=255, len=1)
    Note over CS: 跨越4KB边界，切换行地址
    CS->>L1: chunk2(addr=0x1000, bank=0, row=64, col=0, len=15)
    Note over L1: 两个chunk分别调度
```

---

## 16. APB/AHB/AXI 全面对比

### 16.1 协议对比总览

| 特性 | APB | AHB | AXI4 |
|---|---|---|---|
| 全称 | Advanced Peripheral Bus | Advanced High-performance Bus | Advanced eXtensible Interface 4 |
| 主要用途 | 低速外设（GPIO, UART） | 中速总线（片上高速互联） | 高性能存储和数据流 |
| 通道数 | 2（请求/响应） | 共享总线 | 5个独立通道 |
| Outstanding | 不支持 | 有限支持 | 支持（ID机制） |
| burst 传输 | 不支持 | 支持 | 支持（256 beats） |
| 传输宽度 | 8/16/32bit | 8~1024bit | 8~1024bit |
| 时钟周期/事务 | 2+ cycles | 1+ cycles | 1 cycle（理论） |
| 乱序完成 | 不支持 | 不支持 | 支持（ID匹配） |
| QoS | 无 | 无 | 支持（4bit QoS） |
| 安全扩展 | TrustZone（APB4） | TrustZone | TrustZone（PROT信号） |

### 16.2 APB 时序特点

```
APB 协议（2 阶段）：
周期1（SETUP 阶段）：PSEL=1, PENABLE=0，地址/控制稳定
周期2（ACCESS 阶段）：PENABLE=1，等待 PREADY，数据传输

优点：简单，面积小，适合低带宽外设
缺点：每次传输至少 2 个周期，不支持 burst
```

### 16.3 AHB 时序特点

```
AHB 协议（流水线）：
周期1（地址阶段）：发送地址和控制信号，同时上一笔数据传输
周期2（数据阶段）：数据传输，HREADY 控制等待
支持 burst（INCR, WRAP），但为单主端共享总线

关键信号：HSEL, HADDR, HBURST, HSIZE, HTRANS, HWDATA, HRDATA
缺点：无法乱序完成，ID机制有限
```

### 16.4 AXI4 优势分析

```
AXI4 设计哲学：
1. 地址/数据分离（独立握手通道）→ 允许 outstanding
2. 写地址+写数据+写响应分离 → 灵活流控
3. 读地址+读数据分离 → 多笔读并行
4. ID 机制 → 支持乱序完成、交织
5. QoS → 服务质量差异化

DDR3 控制器选择 AXI4 的原因：
- DDR3 读延迟大（CL=11），outstanding 可隐藏延迟
- DRAM 调度需要命令重排，AXI ID 允许乱序响应
- 高带宽需求与 AXI4 burst 天然匹配
```

---

## 17. 前端流程：Lint→综合→形式→STA

### 17.1 前端流程概览

```mermaid
graph LR
    RTL["RTL 代码\n（Verilog-2012）"]
    LINT["Lint 检查\n（Spyglass/Verilator）"]
    SYN["逻辑综合\n（Design Compiler）"]
    FV["形式验证\n（Conformal/Formality）"]
    STA["静态时序分析\n（PrimeTime）"]
    NETLIST["门级网表\n（.v）"]
    REPORTS["时序报告\n（.rpt）"]

    RTL --> LINT
    LINT --> SYN
    SYN --> NETLIST
    SYN --> FV
    RTL --> FV
    NETLIST --> STA
    STA --> REPORTS
```

### 17.2 Lint 检查

Lint 是RTL代码的静态分析，检查潜在的编码错误：

```tcl
# Spyglass Lint 关键规则
set_option run_app lint/rtl
set_option enabling_rule STARC  ;# 标准规则集
# 常见问题类别：
# - 组合逻辑敏感列表不完整（W1, W2）
# - 锁存器推断（W3）
# - 悬浮信号（W4）
# - 位宽不匹配（W5）
# - 时钟/复位使用规范（W6）
```

```bash
# Verilator Lint（免费工具）
verilator --lint-only -Wall -I./rtl \
    rtl/ddr3_ctrl_top.v rtl/cmd_split.v rtl/bank_ctrl.v ...
```

常见 Lint 问题及修复：

| 问题类型 | 示例 | 修复方法 |
|---|---|---|
| 锁存器推断 | always @(*) 缺少 else | 补全所有分支或转为 always_ff |
| 多驱动 | 两个 always 驱动同一信号 | 合并到单一 always 块 |
| 位宽不匹配 | 8bit 赋值给 4bit | 显式截断/扩展 |
| 组合环路 | a = b; b = a | 重构逻辑，消除组合环 |

### 17.3 逻辑综合

```tcl
# syn/scripts/run_syn.tcl
# 设置目标工艺库
set target_library [list slow.db fast.db]
set link_library   [concat * $target_library]

# 读入 RTL
read_verilog [glob ../rtl/*.v]
current_design ddr3_ctrl_top

# 设置时钟
create_clock -period 2.5 -name aclk [get_ports aclk]
set_clock_uncertainty 0.1 [get_clocks aclk]
set_clock_transition  0.05 [get_clocks aclk]

# 设置输入/输出延迟
set_input_delay  0.5 -clock aclk [all_inputs]
set_output_delay 0.5 -clock aclk [all_outputs]

# 编译（使用 ultra 优化）
compile_ultra -no_autoungroup

# 输出网表和报告
write -format verilog -output ../syn/results/ddr3_ctrl_top.vg
report_timing -max_paths 10 > ../syn/reports/timing.rpt
report_area > ../syn/reports/area.rpt
report_power > ../syn/reports/power.rpt
```

### 17.4 形式验证

形式验证证明综合网表与 RTL 功能等价：

```tcl
# Cadence Conformal LEC
read design -golden -verilog rtl/ddr3_ctrl_top.v
read design -revised -verilog syn/results/ddr3_ctrl_top.vg

set root design ddr3_ctrl_top -golden
set root design ddr3_ctrl_top -revised

map points
verify
# 期望结果：Verification SUCCEEDED. 0 points failed.
```

形式验证注意事项：
- 综合时禁止 `dont_touch` 约束影响关键对应关系
- Black Box 模块（PHY）需单独处理
- DFI 流水线移位寄存器需声明等价点

### 17.5 静态时序分析（STA）

```tcl
# PrimeTime STA 关键步骤
read_verilog syn/results/ddr3_ctrl_top.vg
link_design ddr3_ctrl_top
read_sdc syn/constraints/ddr3_ctrl_top.sdc

# 检查时序
report_timing -path_type full -delay_type max -max_paths 20
report_timing -path_type full -delay_type min -max_paths 20  ;# hold check

# 关键时序路径示例（需满足）：
# 路径：cmd_reorder_l1/q_starve[7] → bank_ctrl/cas_rdy
# 要求：在 2.5ns 内完成（400 MHz）
```

SDC 约束关键条目：

```tcl
# 多周期路径（地址映射）
set_multicycle_path 2 -setup \
    -from [get_pins cmd_split/*/bank_addr*] \
    -to   [get_pins cmd_reorder_l1/q_bank*]

# 虚假路径（初始化状态机到正常操作路径）
set_false_path -from [get_cells init_fsm/S_DONE] \
               -to   [get_cells dfi_if/dfi_cs_n]
```

---

## 18. 验证方案与覆盖率

### 18.1 验证架构

```mermaid
graph TB
    TB["TestBench 顶层\nddr3_ctrl_tb.v"]
    DRV["AXI Driver\n生成读写事务"]
    MON["AXI Monitor\n捕获所有通道"]
    SB["Scoreboard\n功能检验+性能统计"]
    COV["Coverage\n功能/代码/断言"]
    REF["DDR3 Model\n行为级参考模型"]
    DUT["DUT\nddr3_ctrl_top"]

    TB --> DRV
    TB --> MON
    TB --> SB
    DRV -->|AXI事务| DUT
    DUT -->|DFI信号| REF
    REF -->|读数据| DUT
    MON --> SB
    SB --> COV
```

### 18.2 测试用例列表

| 测试名称 | 测试内容 | 覆盖要点 |
|---|---|---|
| test_basic_rw | 单笔读写 | 基本功能正确性 |
| test_burst_rd | 连续 burst 读（BL=8） | 读路径完整性 |
| test_burst_wr | 连续 burst 写 | 写路径完整性 |
| test_page_hit | 同行多次读 | L1 page-hit 优先 |
| test_page_miss | 行切换 | PRE+ACT 时序 |
| test_4k_boundary | 跨 4KB 边界 burst | cmd_split 拆分 |
| test_outstanding | 4笔并发读 | outstanding=4 |
| test_starvation | 100+笔写后读 | 饥饿防护触发 |
| test_refresh | 长时运行 | 刷新不遗漏 |
| test_multibank | 8个 bank 并发 | bank 并行化 |
| test_init | 上电初始化 | 14态 FSM 正确 |
| test_random | 随机地址/长度 | 随机化回归 |

### 18.3 功能覆盖率模型

```systemverilog
// covergroup：AXI burst 长度分布
covergroup axi_burst_len_cg @(posedge clk);
    cp_awlen: coverpoint s_awlen {
        bins single = {0};           // 单 beat
        bins short  = {[1:3]};       // 2~4 beats
        bins medium = {[4:15]};      // 5~16 beats
        bins long   = {[16:255]};    // 17~256 beats
    }
    cp_awburst: coverpoint s_awburst {
        bins fixed = {0};   // FIXED
        bins incr  = {1};   // INCR（主要）
        bins wrap  = {2};   // WRAP
    }
endgroup

// covergroup：Bank 访问分布
covergroup bank_access_cg;
    cp_bank: coverpoint bank_addr {
        bins bank[8] = {[0:7]};  // 8个bank各覆盖
    }
endgroup

// 断言：tRCD 时序约束
property p_trcd;
    @(posedge clk) $rose(dfi_ras_n == 0) |-> 
        ##[T_RCD:T_RCD+1] (dfi_cas_n == 0);
endproperty
assert property (p_trcd) else $error("tRCD violation!");
```

### 18.4 覆盖率目标

| 覆盖率类型 | 目标 | 当前状态 |
|---|---|---|
| 代码行覆盖率 | > 90% | 待测试 |
| 分支覆盖率 | > 85% | 待测试 |
| FSM 状态覆盖率 | 100% | 待测试 |
| FSM 转换覆盖率 | > 95% | 待测试 |
| 功能覆盖率 | > 95% | 待测试 |
| 断言触发覆盖率 | > 85% | 待测试 |

---

## 19. 性能分析

### 19.1 理论峰值带宽

```
DDR3-1600（×8 器件）：
数据速率 = 1600 Mbps（双倍数据率，等效每 clk 2 byte）
峰值带宽 = 1600 × 10^6 × 8 bit / 8 = 1.6 GB/s

AXI 接口（32bit @ 400MHz）：
峰值写带宽 = 400 × 10^6 × 4 byte = 1.6 GB/s
峰值读带宽 = 同上

实际可达带宽（考虑 overhead）：
- 初始化 ACT 命令：每次访问需 ACT，消耗 tRCD=11 周期
- BL=8 传输：8 周期数据传输
- 效率（page hit）= 8 / (8 + 0) ≈ 100%（连续 page hit）
- 效率（page miss）= 8 / (8 + tRP + tRCD) = 8 / (8+11+11) ≈ 26.7%
- 刷新 overhead：tRFC/tREFI = 88/6240 ≈ 1.4%
```

### 19.2 不同场景性能对比

| 访问模式 | page-hit 率 | 预估带宽效率 | 备注 |
|---|---|---|---|
| 顺序读（同行） | ~95% | ~85% | 刷新+初激活 overhead |
| 顺序写（同行） | ~95% | ~83% | 需考虑 tWR |
| 随机读（多bank） | ~30% | ~35% | 大量 PRE+ACT |
| 视频帧扫描 | ~90% | ~80% | 行优先扫描 |
| AI推理权重加载 | ~85% | ~75% | 块状顺序访问 |

### 19.3 Outstanding 对延迟的影响

```
读延迟（CL=11）下，单笔 outstanding：
  - 每笔读事务耗时 ≈ tRCD + CL + BL = 11 + 11 + 8 = 30 周期
  - 读带宽 = 8 beats / 30 周期 = 26.7%

4笔 outstanding 流水化：
  - 多笔读同时进行，DDR3 pipeline 填充
  - 有效带宽提升 ≈ min(4, 30/8) ≈ 3.75×
  - 实际带宽效率提升至 ~75%
```

### 19.4 调度开销分析

| 调度层次 | 延迟开销 | 说明 |
|---|---|---|
| cmd_split | 0~2 周期 | 拆分计算，寄存器流水 |
| L1 重排序 | 1 周期 | 组合选择 + 寄存器输出 |
| L2 重排序 | 1 周期 | 组合选择 + 寄存器输出 |
| bank_ctrl 检查 | 0 周期 | 并行时序检查 |
| DFI 流水 | CWL=8 周期 | 写数据延迟（不可避免） |

---

## 20. 可扩展方向

### 20.1 容量扩展

```
当前：1Gb × 8（单片）
扩展方案：
  1. 多片并联（×16/×32）：DQ 位宽扩展
  2. 多 rank：CS_n[1:0]，行地址高位选 rank
  3. LPDDR4/5 支持：协议适配层
```

### 20.2 接口扩展

| 扩展方向 | 改动点 | 复杂度 |
|---|---|---|
| AXI 宽度从 32→64bit | 数据路径加宽，命令合并 | 中 |
| 多 AXI 端口（NIC） | 增加仲裁层 | 高 |
| AXI QoS 支持 | L2 调度加入优先级域 | 中 |
| PCIe 直接映射 | 地址转换层 | 高 |

### 20.3 功能增强

```
1. ECC（Error Correction Code）：
   - 72bit 数据总线（64bit数据 + 8bit 校验）
   - SECDED（单错误纠正，双错误检测）
   - 需 ECC 编解码器 + 错误注入测试

2. 加密（DRAM Encryption）：
   - AES-128/256 加密引擎插入读写路径
   - 密钥管理接口

3. 带宽监控：
   - AXI 总线监控器（APM）
   - 计数器寄存器（APB 接口读取）
   - 带宽限制（QoS throttle）

4. 低功耗模式：
   - Self-Refresh：长期空闲时进入
   - Power-Down：短期空闲时进入
   - Clock Gating：精细化门控时钟
```

### 20.4 验证平台扩展

```
1. UVM 验证环境：
   - 参数化 AXI VIP
   - 覆盖率驱动验证（CDV）
   - 约束随机测试（CRT）

2. 形式验证增强：
   - 属性验证（JasperGold）
   - 死锁/活锁检查
   - 安全属性验证

3. 后端协同验证：
   - PR（Physical Residual）时序仿真
   - SPICE 信号完整性分析
```

---

## 21. Q&A 30+ 题

### Part A：DDR 协议问题

**Q1. DDR3 与 DDR4 的主要区别是什么？**

A: 主要区别如下：
- **电压**：DDR3 1.5V（低功耗版1.35V）；DDR4 1.2V，功耗更低
- **速率**：DDR3 最高 DDR3-2133；DDR4 从 DDR4-1600 起，最高 DDR4-3200+
- **Bank 架构**：DDR3 最多 8 banks；DDR4 引入 Bank Group（4组×4bank=16banks），提升并发
- **突发长度**：DDR3 BL=8（固定，BC4可选）；DDR4 BL=8/16
- **信号完整性**：DDR4 引入 DBI（Data Bus Inversion），降低 SSO 噪声
- **ODT**：DDR4 支持更灵活的 ODT 拓扑

**Q2. 什么是 tFAW？为什么需要这个参数？**

A: tFAW（Four Activate Window）是一个滑动时间窗口约束：在任意 tFAW 时间内，发给同一 DRAM 器件的 ACTIVATE 命令不得超过 4 条。

原因：每次 ACT 命令都会对行选线（Word Line）充电，消耗峰值电流。如果连续 ACT 过多，会导致电源轨电压骤降，影响信号完整性。tFAW 限制 ACT 命令的时间密度，保证电源稳定。

**Q3. 为什么 DDR3 读命令后不能立即发预充电（PRE）？**

A: 需要等待 tRTP（Read to Precharge Time）。在 READ 命令发出后，DRAM 内部已经开始读取传感放大器的数据，此时若立即 PRE，会在传感放大器完成工作前关闭 bit line，导致读数据损坏或下次写入错误。tRTP 保证传感器完成感应，数据安全后再允许 PRE。

**Q4. CWL（CAS Write Latency）和 CL（CAS Latency）有何区别？**

A:
- **CL**（也称 RL，Read Latency）：从 READ 命令发出到**第一个有效读数据**出现在 DQ 总线的时钟周期数。DDR3-1600 CL=11。
- **CWL**（也称 WL，Write Latency）：从 WRITE 命令发出到**第一个写数据**需要出现在 DQ 总线的时钟周期数。DDR3-1600 CWL=8。
- CWL < CL 是因为写操作不需要等待传感放大器，内部路径更短。

**Q5. DDR3 自刷新（Self-Refresh）的工作原理？**

A: 自刷新（Self-Refresh，SR）是 DDR3 的低功耗模式：
1. 控制器发送 Self-Refresh Entry 命令（CKE=0，同时 REF 命令编码）
2. DRAM 进入 SR 状态，**内部自主**按 tREFI 周期刷新所有行
3. 控制器可以关闭时钟（CKE=0），进入待机
4. 退出时控制器重新使能 CKE=1，等待 tXSR 后 DRAM 恢复正常

优点：数据保持，主控时钟可关闭，功耗极低（µW 级）。

**Q6. tRAS 和 tRC 的关系？**

A:
- **tRAS**（Row Active Strobe）：ACT 命令后，行必须保持激活的最短时间，即 ACT→PRE 的最小间隔。目的是保证传感放大器完成读取/恢复操作。
- **tRC**（Row Cycle Time）：同一 bank 连续两次 ACT 命令的最小间隔，即 ACT→PRE→ACT 的总时间下限。
- 关系：tRC = tRAS + tRP，是行周期的总时间。

**Q7. DDR3 的 ZQ 校准有什么作用？**

A: DDR3 的驱动强度和 ODT 阻抗通过片上电阻网络实现，这些电阻受温度、电压影响会漂移。ZQCL（ZQ Calibration Long）在初始化时发出，ZQCS（ZQ Calibration Short）在运行时定期发出，触发 DDR3 内部校准逻辑，将驱动阻抗和 ODT 阻抗重新调整到目标值（通常 ZQ 引脚外接 240Ω 参考电阻）。校准确保信号完整性。

**Q8. 什么是 DDR3 的 Write Leveling？**

A: Write Leveling 是 DDR3 引入的 PHY 训练机制，用于补偿 DQS 信号相对于 CK 的传输延迟差异（由 PCB 走线、封装等引起）：
1. 控制器通过 MR1 进入 Write Leveling 模式（WL=1）
2. PHY 调整每条 DQS 的延迟，直到 DQS 上升沿与 CK 上升沿对齐
3. 完成后退出 WL 模式，后续写操作 DQS 对齐 CK

### Part B：AXI 协议问题

**Q9. AXI4 五通道握手机制中，哪些通道可以独立流控？**

A: AXI4 的五个通道（AW、W、B、AR、R）均可**独立**流控，每个通道有独立的 VALID/READY 握手。这意味着：
- 写地址（AW）和写数据（W）可以乱序到达从端（从端必须能处理）
- 读地址（AR）发出后，控制器无需等待 AR 完成就能发下一笔 AR（outstanding）
- B 通道响应可以在所有写数据传输完成后再发

**Q10. 为什么 AXI 需要 4KB 边界限制？**

A: 出于系统安全性和互操作性考虑：
1. **地址解码**：系统地址映射通常以 4KB 为粒度，不同 4KB 区域可能映射到不同从端。若一笔 burst 跨越 4KB 边界，低地址部分由 slave0 处理，高地址部分由 slave1 处理，互联矩阵（crossbar）无法同时路由给两个 slave，导致协议违规。
2. **MMU/MPU**：页面保护以 4KB 为单位，跨页 burst 可能跨越权限边界。
3. **规范简化**：限制了地址包裹（address wrap）的复杂性。

**Q11. AXI WRAP burst 和 INCR burst 有什么区别？**

A:
- **INCR（Incrementing）**：地址单调递增，最常用，DDR3 控制器主要使用此类型
- **WRAP（Wrapping）**：地址在 2^n 对齐的边界内循环，用于 cache line 填充（例如 cache miss 后先取缺失 word，再取 wrap 内其他 word）
- 本 DDR3 控制器仅支持 INCR burst，WRAP 和 FIXED 可返回 SLVERR 错误响应

**Q12. AXI ID 机制如何支持乱序完成？**

A: AXI 中相同 ID 的事务必须按序完成，不同 ID 的事务可以乱序：
- Master 发出 AR(ID=0), AR(ID=1), AR(ID=2)
- Slave 可以先返回 R(ID=2)，再返回 R(ID=0)，再返回 R(ID=1)
- Master 内部有 reorder buffer，按 ID 匹配排列数据

本控制器支持 4-bit ARID/AWID，最多 16 个独立事务 ID，允许 MAX_OUTSTANDING=4 笔并发读，不同 ID 的读数据可以乱序返回。

**Q13. AXI WSTRB（写字节使能）的作用？**

A: WSTRB 是每个 beat 的字节使能信号，宽度 = 数据宽度 / 8。对于 32bit 数据总线，WSTRB=4bit。
- bit0=1：WDATA[7:0] 写入 DRAM
- bit0=0：WDATA[7:0] 对应字节不写入，保持原值

DDR3 通过 DM（Data Mask）信号实现字节掩码，控制器将 AXI WSTRB 取反后映射到 DFI dfi_wrdata_mask（DDR DM 低有效）。

### Part C：综合相关问题

**Q14. 什么是综合约束文件（SDC），主要包含哪些内容？**

A: SDC（Synopsys Design Constraints）是工业标准约束格式，主要包含：
1. **时钟定义**：`create_clock`，频率、占空比、波形
2. **时钟关系**：`set_clock_groups`，异步/同步关系
3. **输入输出延迟**：`set_input_delay`/`set_output_delay`
4. **路径例外**：`set_false_path`（虚假路径）、`set_multicycle_path`（多周期路径）
5. **面积/功耗约束**：`set_max_area`、`set_max_dynamic_power`
6. **负载/驱动强度**：`set_load`、`set_driving_cell`

**Q15. 什么情况下需要声明多周期路径（Multi-Cycle Path）？**

A: 当信号的逻辑路径超过一个时钟周期才能稳定（设计上允许多周期），需声明 MCP 避免工具错误地报 timing violation：
1. **数据路径**：如配置寄存器到数据路径，写频率低，允许 2~4 周期稳定
2. **重排序队列**：cmd_split 的地址映射计算，逻辑较深，允许 2 周期
3. **模式切换**：如从 NORMAL 切到 LOW_POWER 模式，路径较长但切换慢

本项目中 cmd_split → cmd_reorder_l1 的地址比较路径应声明为 2 周期 MCP。

**Q16. 综合时 dont_touch 和 dont_use 属性有什么区别？**

A:
- **dont_touch**：告诉综合工具**不要优化**标记的实例或网络，保留其结构不变。常用于时钟缓冲树、特定结构的状态机、手工优化的关键路径。
- **dont_use**：告诉综合工具**不要使用**标记的单元（来自库），但不影响已有实例，主要用于排除有问题的工艺单元或在特定约束下限制单元选择。

**Q17. 什么是综合中的面积-时序权衡（Area-Timing Trade-off）？**

A: 综合工具通过以下手段平衡面积和时序：
- **逻辑复制（Logic Duplication）**：在多条路径上各复制一份驱动单元，减少扇出，改善时序，但增大面积
- **门尺寸调整（Gate Sizing）**：用更大（更快）的单元替换关键路径上的单元，改善时序，增大面积和功耗
- **流水线（Retiming）**：在组合路径中插入寄存器，允许更高时钟频率，增加寄存器面积和延迟

对于本 DDR3 控制器的 400MHz 目标，L1 重排序的优先级逻辑（8路比较器）是潜在关键路径，可通过树形结构优化或 2 级流水降低时序压力。

### Part D：时序/STA 问题

**Q18. 什么是建立时间（Setup Time）和保持时间（Hold Time）违规？**

A:
- **建立时间（Setup）**：触发器在时钟有效沿**之前**，数据必须保持稳定的最短时间。若数据到得太晚（传播延迟太长），称为 setup violation（时序违例），修复方法：减少逻辑深度、提高驱动、重新流水。
- **保持时间（Hold）**：触发器在时钟有效沿**之后**，数据必须继续保持稳定的最短时间。若数据变化太快（传播延迟太短），称为 hold violation（保持违例），修复方法：在路径上插入 buffer 增加延迟。

Setup violation 可通过降频解决，Hold violation 不能降频解决，必须修改路径延迟。

**Q19. 什么是时钟偏斜（Clock Skew）和时钟抖动（Clock Jitter）？**

A:
- **时钟偏斜（Skew）**：同一时钟网络中，不同触发器接收到时钟信号的时间差（由布线延迟差异引起）。正偏斜可放宽 setup，但加剧 hold；负偏斜相反。
- **时钟抖动（Jitter）**：时钟边沿相对于理想位置的随机偏移（由电源噪声、PLL 噪声等引起）。分为周期抖动（Cycle-to-Cycle）和相位噪声。

在 STA 中：
- `set_clock_uncertainty` 通常包含 skew 和 jitter 的综合余量
- PrimeTime 中可通过 `set_clock_latency` 精细建模 skew

**Q20. 什么是 MCMM（Multi-Corner Multi-Mode）分析？**

A: MCMM 是现代 STA 的必要步骤：
- **Multi-Corner**：在不同工艺/电压/温度（PVT）角下验证时序。常见角：SS（慢角，最差 setup），FF（快角，最差 hold），TT（典型）。
- **Multi-Mode**：不同工作模式（功能模式、测试模式、低功耗模式）下的不同约束集合。

DDR3 控制器应至少在以下角下通过时序：
- Slow Corner（SS, 0.9V, 125°C）：建立时间检查
- Fast Corner（FF, 1.1V, -40°C）：保持时间检查

**Q21. OCV（On-Chip Variation）分析的目的是什么？**

A: OCV 建模芯片内部不同位置的工艺偏差：同一芯片上不同区域的晶体管速度略有差异（由光刻、掺杂均匀性等决定）。

在时序分析中：
- **launch path**（发射路径）可以用较慢的偏差
- **capture path**（捕获路径）可以用较快的偏差
- 这进一步收紧了时序裕量

高级方法：POCV（Statistical OCV）用概率分布建模，比保守的固定 derate 更精确，避免过度悲观。

### Part E：CDC（跨时钟域）问题

**Q22. 什么情况下会产生亚稳态（Metastability）？**

A: 当一个触发器的数据输入在时钟有效沿前后的窗口（setup + hold 时间）内发生变化时，触发器输出会进入亚稳态：输出既不是 0 也不是 1，处于中间不确定状态，并以指数衰减的概率在某个时间后稳定到 0 或 1。

在 CDC 路径中，异步信号跨时钟域时必然可能违反目标时钟的 setup/hold，因此必须使用同步器（2FF Synchronizer）处理。

**Q23. 单 bit CDC 如何使用 2FF 同步器？**

A:
```verilog
// 2FF 同步器（CDC 标准单元）
module sync_2ff #(parameter WIDTH=1) (
    input  clk_dst,     // 目标时钟域时钟
    input  rst_n,
    input  [WIDTH-1:0] d_src,  // 源时钟域信号
    output [WIDTH-1:0] q_dst   // 目标时钟域同步后信号
);
    reg [WIDTH-1:0] ff1, ff2;
    
    always @(posedge clk_dst or negedge rst_n) begin
        if (!rst_n) {ff2, ff1} <= '0;
        else        {ff2, ff1} <= {ff1, d_src};
    end
    
    assign q_dst = ff2;
endmodule
```

第一级 FF 捕获可能亚稳态的信号，给予一个完整的时钟周期让亚稳态衰减；第二级 FF 捕获已基本稳定的信号。2FF 对于大多数应用已足够；高频或低 MTBF 要求可用 3FF。

**Q24. 多 bit CDC 如何安全处理？**

A: 多 bit 信号不能直接用多个 2FF 同步器（因为每个 bit 同步延迟可能不一致，导致采样到中间状态）：

1. **格雷码（Gray Code）**：对于递增计数器，转换为格雷码再同步（每次仅一位变化），适用于 FIFO 读写指针。
2. **握手协议（Handshake）**：发送端发出 REQ（单 bit），接收端确认 ACK 后再发下一组数据；慢速但安全。
3. **FIFO**：异步 FIFO 是最通用的多 bit CDC 方案，内部用格雷码指针，适合高带宽数据流。
4. **Enable 同步**：数据路径用寄存器保持稳定，仅同步使能信号（单 bit），采样时刻数据已稳定。

本 DDR3 控制器为单时钟域设计，规避了 CDC 复杂性。

### Part F：低功耗设计问题

**Q25. ASIC 中有哪几类功耗？如何降低？**

A: ASIC 功耗分为：

| 功耗类型 | 来源 | 占比（典型） | 降低方法 |
|---|---|---|---|
| 动态功耗（开关） | CMOS 翻转 α·C·V²·f | ~70% | 降频、门控时钟、数据编码 |
| 短路功耗 | PMOS/NMOS 同时导通 | ~5% | 优化翻转斜率 |
| 漏电功耗（静态） | 亚阈值漏电 | ~25% | 多阈值库（HVT/SVT/LVT）、电源门控 |

**Q26. 时钟门控（Clock Gating）如何降低功耗？**

A: 时钟门控通过在时钟路径插入门控单元（ICG，Integrated Clock Gating cell），当子模块不活跃时关闭其时钟，消除空翻转（无效的 0→1→0 触发器翻转）：

```verilog
// 综合工具自动推断，或手动插入
// ICG 内部结构：
// clk_en 需要用 latch 锁存（避免毛刺）
// latch: LE=clk_inv, D=en_d → Q
// AND: clk & Q → clk_gated
```

时钟门控可降低 20~40% 的动态功耗，是低功耗设计的首要手段。综合工具（如 DC）可以自动识别并插入 ICG。

**Q27. 多阈值电压（Multi-Vt）设计策略？**

A:
- **LVT（Low Vt）**：低阈值，速度快，漏电大。用于关键时序路径。
- **SVT（Standard Vt）**：中间值，平衡。用于普通路径。
- **HVT（High Vt）**：高阈值，速度慢，漏电小。用于非关键路径，降低静态功耗。

策略：默认使用 HVT，综合工具在时序不满足时自动将关键路径升级为 SVT/LVT，以最小代价满足时序。通常关键路径占 5~10% 的逻辑，其余 90% 可保持 HVT，大幅降低漏电。

**Q28. 什么是电源门控（Power Gating）？**

A: 电源门控通过在模块电源轨上插入 MTCMOS（Multi-Threshold CMOS）开关管（Header for PMOS，Footer for NMOS），完全切断非活跃模块的电源，将漏电降为接近零：

工作流程：
1. 软件发出关闭请求 → 模块保存状态（Retention Flop）
2. 时钟停止（Clock Gating）
3. 等待一段时间确保静止
4. Power Switch 关闭
5. 唤醒时反向操作，重新上电、恢复状态

本 DDR3 控制器未实现电源门控，这是后续优化方向之一。

### Part G：综合与实现补充

**Q29. 什么是逻辑等价检查（LEC）？与仿真有什么区别？**

A: LEC（Logic Equivalence Checking）是形式验证的一种，数学上证明两个设计在所有可能输入下逻辑功能完全相同：

- **与仿真对比**：仿真只能覆盖有限个测试向量（即使随机也不完全）；LEC 枚举所有可能输入状态（通过 BDD/SAT 求解器），提供**形式上的等价保证**。
- **应用场景**：综合前 RTL ↔ 综合后网表；ECO 修改后的网表 ↔ 修改前网表；布局布线后网表 ↔ 综合后网表。
- **工具**：Cadence Conformal LEC，Synopsys Formality。

**Q30. 请解释 DDR3 控制器中的关键路径，并说明优化策略。**

A: DDR3 控制器的潜在关键路径（400MHz，2.5ns 预算）：

| 路径 | 深度估算 | 优化策略 |
|---|---|---|
| L1 饥饿计数器比较（8路255） | 8-input OR → 选择器 | 树形结构，减少扇出 |
| cmd_split 行边界计算 | 减法器 + 比较器 | 声明 2 周期 MCP |
| bank_ctrl tFAW 窗口检查 | 4路减法器 + AND | 流水线，或简化算法 |
| DFI 地址/数据多路选择 | 宽 MUX（16路） | 二级树形 MUX |
| AXI outstanding 计数 | 加减计数器 + 比较 | 编码优化（one-hot）|

**Q31. 什么是扫描链（Scan Chain）？为什么需要它？**

A: 扫描链是数字 IC 可测试性设计（DFT）的核心技术：将电路中的所有（或部分）触发器连接成一条移位寄存器链：
- **测试模式**：通过 scan_in 串行移入测试向量，施加到组合逻辑；捕获结果后串行移出到 scan_out，与期望值比较
- **工作模式**：触发器正常工作，扫描链不影响功能

目的：测试流片后芯片的制造缺陷（桥接、开路等），实现高故障覆盖率（通常 > 95%）。DDR3 控制器在综合时需插入 scan 端口（`set_scan_configuration`）。

**Q32. 什么是时序借用（Time Borrowing）？适用哪些场景？**

A: 时序借用（Time Borrowing 或 Cycle Stealing）是指利用电平敏感锁存器（Latch）而非触发器（Flip-Flop）的特性，允许当前周期的数据在锁存器打开期间"借用"下一周期的时间窗口：

适用场景：
- 流水线中某一级逻辑深度不均匀，某级偶尔超时
- 时钟相位优化困难时的补救措施

注意：时序借用引入分析复杂性，大多数现代设计规范不推荐使用，应优先通过逻辑优化或流水线重划分解决时序问题。

---

## 22. 目录与文件清单

### 22.1 项目目录结构

```
DIC-DDR/
├── README.md                    # 项目简介
├── rtl/                         # RTL 源文件
│   ├── ddr3_ctrl_top.v          # 顶层模块
│   ├── axi_slave_if.v           # AXI4 从端接口（含 outstanding）
│   ├── cmd_split.v              # 命令拆分（行边界+4KB边界）
│   ├── cmd_reorder_l1.v         # L1 重排序（页命中+饥饿防护）
│   ├── cmd_reorder_l2.v         # L2 重排序（读写分组+刷新优先）
│   ├── bank_ctrl.v              # Bank 控制器 FSM
│   ├── refresh_ctrl.v           # 刷新控制器
│   ├── init_fsm.v               # DDR3 初始化状态机（14态）
│   ├── dfi_if.v                 # DFI 接口（CWL流水线+phy_clk）
│   └── ddr3_params.vh           # 全局参数定义
├── tb/                          # 验证环境
│   ├── ddr3_ctrl_tb.v           # TestBench 顶层
│   ├── axi_driver.sv            # AXI 驱动
│   ├── axi_monitor.sv           # AXI 监控
│   ├── scoreboard.sv            # 计分板（功能验证+性能统计）
│   ├── ddr3_model.v             # DDR3 行为级模型
│   └── tests/                   # 各测试用例
│       ├── test_basic_rw.sv
│       ├── test_4k_boundary.sv
│       ├── test_outstanding.sv
│       ├── test_starvation.sv
│       ├── test_refresh.sv
│       ├── test_multibank.sv
│       └── test_init.sv
├── sim/                         # 仿真脚本
│   ├── Makefile                 # 仿真自动化（iverilog/VCS/Questa）
│   └── run_sim.sh               # 快速仿真脚本
├── syn/                         # 综合脚本
│   ├── scripts/
│   │   └── run_syn.tcl          # Synopsys DC 综合脚本
│   ├── constraints/
│   │   └── ddr3_ctrl_top.sdc    # 时序约束（400 MHz）
│   └── reports/                 # 综合报告（待生成）
├── tools/                       # 辅助工具
│   └── addr_calc.py             # 地址映射计算工具
├── constraints/                 # 约束目录
│   └── timing.sdc               # 额外时序约束
└── docs/                        # 文档
    ├── project_report_v2.md     # 本文件
    └── ddr3_timing_params.xlsx  # 时序参数表（可选）
```

### 22.2 RTL 模块接口汇总

| 模块名 | 主要输入 | 主要输出 | 功能 |
|---|---|---|---|
| ddr3_ctrl_top | AXI 五通道 | DFI 信号集 | 顶层集成 |
| axi_slave_if | AXI 总线 | cmd+data FIFO | AXI 协议处理 |
| cmd_split | AXI cmd | chunk 流 | 地址拆分 |
| cmd_reorder_l1 | chunk 流 | 重排后 chunk | 页命中优先 |
| cmd_reorder_l2 | 重排 chunk | 调度 cmd | 读写分组 |
| bank_ctrl | cmd | timing 信号 | 每 bank 时序 |
| refresh_ctrl | clk | refresh_req | 刷新计时 |
| init_fsm | rst_n | init_cmd | 初始化序列 |
| dfi_if | 内部 cmd | DFI 总线 | DFI 编码 |

---

## 23. 修订记录

| 版本 | 日期 | 修订内容 | 修订人 |
|---|---|---|---|
| v1.0 | 2025-01 | 初始版本，基本 DDR3 控制器框架 | 设计组 |
| v1.1 | 2025-02 | 添加 L1 重排序、刷新控制器 | 设计组 |
| v1.2 | 2025-03 | 添加 init_fsm（11步，MR0~MR3） | 设计组 |
| v1.5 | 2025-04 | 添加 DFI 接口、phy_clk | 设计组 |
| v2.0 | 2025-07 | **重大更新：**<br>• AXI outstanding=4（MAX_OUTSTANDING）<br>• cmd_split 4KB 边界保护<br>• L1 饥饿计数器（255周期阈值）<br>• L2 读写分组（GROUP_MAX=8）<br>• DFI CWL 写使能流水线（16bit移位寄存器）<br>• init_fsm 扩展至14态<br>• MR 寄存器值修订（MR1=0x0004 Rtt_Nom=RZQ/6）<br>• 完整前端流程文档<br>• 验证方案与覆盖率规划<br>• 30+题 Q&A 库 | 设计组 |

---

*本报告版权所有 © 2025 数字 IC 设计组。仅供学习参考。*
*DDR3 Controller Project Implementation Report v2.0*
"""

with open('/home/runner/work/DIC-DDR/DIC-DDR/docs/project_report_v2.md', 'w', encoding='utf-8') as f:
    f.write(content)

print(f"Written {len(content.encode('utf-8'))} bytes")
