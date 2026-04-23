# 面向高速存储系统的 DDR3 控制器与调度机制设计

本仓库实现一个教学友好的 DDR3 控制器参考工程，包含：

- RTL（Verilog-2001 风格，可综合子集）
- 测试平台（SystemVerilog + iverilog -g2012）
- 简化 DDR3 行为模型
- 时序约束（伪 SDC）
- 设计文档与详细项目报告（中文）

## 快速开始

```bash
cd sim
make compile
make run TEST=test_basic_rw
```

运行成功后控制台应出现 `PASS`。

## 目录

详见 `docs/project_report.md` 与 `docs/design_spec.md`。
