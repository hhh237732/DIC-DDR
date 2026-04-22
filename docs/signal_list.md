# 模块信号清单（摘要）

## ddr3_ctrl_top
- AXI: AW/AR/W/R/B 全接口
- DFI: `dfi_cke/cs_n/ras_n/cas_n/we_n/bank/addr/wrdata/wrdata_en/rddata/rddata_valid`

## axi_slave_if
- 请求输出：`req_valid/ready/rw/id/addr/len/size/burst`
- 写缓存输出：`wbuf_*`
- 读缓存输入：`rbuf_*`
- 写完成输入：`wr_done_*`

## cmd_split
- 输入 AXI 请求描述符
- 输出 DDR 子命令描述符（不跨 row）

## cmd_reorder_l1 / l2
- 输入：命令流
- 输出：重排后的命令流
- L2 额外输出：`out_auto_pre`

## bank_ctrl_top
- 输入：issue_act/rd/wr/pre + bank/row
- 输出：每 bank 开行状态与 can_issue 向量

## dfi_if
- 输入：内部命令与写数据
- 输出：DFI 控制脚与写数据信号
- 输入：DFI 读数据返回
