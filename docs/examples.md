# 访问示例

## 示例1：Page Hit 读
1. AXI 发起 AR（同 bank 同 row）
2. 控制器直接发 RD（无 PRE/ACT）
3. CL 后返回 R burst

## 示例2：Page Miss 写
1. AXI 发起 AW/W
2. 控制器先 PRE（若冲突）再 ACT
3. 连续 WR，结束后 B 响应

## 示例3：Refresh 抢占
1. refresh_pending 拉高
2. 调度器在允许窗口插入 REF
3. refresh_ack 复位计数，恢复普通读写
