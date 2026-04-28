# 面向高速存储系统的 DDR3 控制器与调度机制设计

本仓库实现一个教学友好的 DDR3 控制器参考工程（v2），包含：

- RTL（Verilog-2001/2012 风格，可综合子集）
- 测试平台（SystemVerilog + iverilog -g2012）
- 简化 DDR3 行为模型
- 综合约束模板（SDC/Tcl）
- 设计文档与详细项目报告（中文）

## 新增功能（v2）

| 功能 | 说明 |
|---|---|
| 4KB 地址边界保护 | cmd_split 自动拆分跨 4KB 的 AXI burst |
| Outstanding 读事务 | 最多 4 笔并发读，提升带宽利用率 |
| 饥饿防护调度 | 防止 page-miss 命令被无限期推迟 |
| CWL 写使能流水线 | dfi_wrdata_en 精确对齐 CWL=8 周期 |
| phy_clk 输出 | DFI 接口提供 PHY 所需 180° 相位时钟 |
| 完整初始化序列 | 11步 DDR3 JEDEC 初始化（MRS2/3/1/0 + ZQCL） |
| 性能统计 Scoreboard | 带宽、事务计数、延迟统计 |

## 目录结构

```
rtl/               RTL 源文件
  axi/             AXI Slave 接口
  cmd/             命令拆分与重排序
  bank/            Bank 状态控制
  buffer/          读写数据缓冲
  refresh/         刷新控制
  init/            初始化状态机
  dfi/             DFI 接口
tb/                仿真测试平台
  tests/           测试用例（含新增4KB/outstanding/starvation测试）
sim/               仿真Makefile
syn/               综合脚本与约束
  scripts/         DC/Genus TCL 脚本
  constraints/     SDC 时序约束
docs/              设计文档
  project_report_v2.md  完整项目报告（v2）
  source_extracts/ 文档摘录
tools/             辅助工具
  extract_docs.py  文档内容提取工具
```

## 快速开始

```bash
# 编译
cd sim
make compile

# 运行基础测试
make run TEST=test_basic_rw

# 运行新增测试
make run TEST=test_4k_boundary
make run TEST=test_outstanding
make run TEST=test_starvation
```

运行成功后控制台应出现 `PASS`。

## 参数配置

主要参数在 `rtl/ddr3_params.vh`：

```verilog
`define CL               11    // CAS Latency
`define CWL              8     // CAS Write Latency
`define MAX_OUTSTANDING  4     // 最大并发读事务数
`define T_SIM_ZQINIT     64    // 仿真加速：ZQCL等待周期
```

## 文档

- 项目报告：`docs/project_report_v2.md`
- 文档提取：`python3 tools/extract_docs.py <file> -o <output>`
