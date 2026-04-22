# DDR3 控制器伪 SDC（教学示例）
create_clock -name aclk -period 2.5 [get_ports aclk]

# AXI 输入输出延迟约束（示意）
set_input_delay  0.5 -clock aclk [all_inputs]
set_output_delay 0.5 -clock aclk [all_outputs]

# 异步复位路径（示意）
set_false_path -from [get_ports aresetn]

# DFI 关键路径（示意）
set_max_delay 2.0 -from [get_ports {s_axi_*}] -to [get_ports {dfi_*}]
