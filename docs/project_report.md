# DDR3 控制器项目报告书

## 1. 项目背景与意义
DDR 控制器是高速存储系统中的关键桥接模块。通过将 AXI 事务高效映射为 DDR3 命令序列，可显著提升带宽利用率并降低平均访问延迟。

## 2. 需求与设计目标
- 带宽：减少 page conflict 与 R/W 频繁切换造成的损失
- 延迟：提升 row hit 概率，减少 PRE/ACT 开销
- 面积与可配置：参数化数据宽度、时序参数、映射策略

## 3. 顶层架构图
见 `docs/arch_diagram.md`。

## 4. 模块详细设计
### 4.1 AXI 接口
实现 AW/AR/W/R/B 全握手，AW/AR/W 使用同步 FIFO 解耦。

### 4.2 命令拆分
算法：
```text
beats = AxLEN + 1
while beats > 0:
  计算当前 col 到行尾剩余 room
  chunk = min(beats, room)
  输出 chunk 子命令
  addr += chunk * beat_bytes
  beats -= chunk
```

### 4.3 地址映射
默认：`{row,bank,col,byte}`；备选 bank-interleave：`bank ^= col[2:0]`。

### 4.4 两级重排
- L1：page-hit 插队
- L2：读写分组、urgent read、refresh 前置、auto-precharge

调度优先级：
```text
P = refresh > urgent_read > write_group > read_group
```

### 4.5 Bank 控制
每 bank 维护 `row_open/open_row` 与计数器 `tRCD/tRP/tRAS/tRC/tWR/tRTP/tCCD`，
全局维护 `tRRD/tFAW` 以限制 ACT 密度。

### 4.6 Refresh
`tREFI` 计数到期置位 `refresh_pending`；超期至 `8*tREFI` 触发 `urgent_refresh`。

### 4.7 初始化
序列：CKE低等待 -> CKE高等待 -> MRS2/3/1/0 -> ZQCL -> normal。

### 4.8 DFI
将内部命令映射到 `{CS#,RAS#,CAS#,WE#}`，并透传读写数据。

## 5. 关键技术解析
1) AXI burst 拆分：按 row 边界切片，防止命令跨行。
2) 地址映射与命中率：
- 命中率近似：`HitRate = N_hit / N_total`
- bank-interleave 在随机流量下可降低热点 bank 冲突。
3) L1/L2 重排：L1 做局部 page-hit；L2 做全局读写分组与优先级。
4) 计数器法满足时序：每发命令装载对应计数器，减到 0 才允许下一命令。
5) Refresh 抢占：超期时强制提高优先级，避免违反刷新窗口。

## 6. 工作流程图
见 `docs/workflow_diagram.md`。

## 7. 信号清单
见 `docs/signal_list.md`。

## 8. 使用示例
见 `docs/examples.md`，覆盖 page hit/page miss/refresh 抢占。

## 9. 验证方案
- TB 架构：AXI BFM + DUT + DDR3 Model + Scoreboard
- 用例矩阵：basic_rw / burst / page_hit / reorder / refresh
- 自检方式：写后读比对 + PASS/FAIL 输出

## 10. 性能分析（TB 统计方法）
- 理论带宽：`BW = data_width * freq * efficiency`
- 可在 TB 中统计 row hit、rw_switch、refresh stall，比较重排前后效率。

## 11. 可扩展性与改进
- 多 AXI 端口仲裁
- QoS 与延迟上限保障
- ECC（SECDED）
- 更完整的 JEDEC 初始化/时序覆盖

## 12. 文件清单与作用
- `rtl/`：控制器 RTL
- `tb/`：验证环境
- `constraints/`：约束示例
- `sim/Makefile`：一键编译/运行
- `docs/`：规格、报告、图与示例
