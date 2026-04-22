# DDR3 控制器仿真 Makefile（iverilog）
TOP      := tb_top
BUILD_DIR:= build
VVP      := $(BUILD_DIR)/sim.vvp

RTL_SRCS := \
  ../rtl/ddr3_ctrl_top.v \
  ../rtl/axi/sync_fifo.v \
  ../rtl/axi/axi_slave_if.v \
  ../rtl/cmd/addr_map.v \
  ../rtl/cmd/cmd_split.v \
  ../rtl/cmd/cmd_reorder_l1.v \
  ../rtl/cmd/cmd_reorder_l2.v \
  ../rtl/buffer/write_buffer.v \
  ../rtl/buffer/read_buffer.v \
  ../rtl/bank/bank_ctrl.v \
  ../rtl/bank/bank_ctrl_top.v \
  ../rtl/refresh/refresh_ctrl.v \
  ../rtl/init/init_fsm.v \
  ../rtl/dfi/dfi_if.v

TB_SRCS := \
  ../tb/ddr3_model.v \
  ../tb/axi_master_bfm.sv \
  ../tb/scoreboard.sv \
  ../tb/tb_top.sv

all: compile

compile:
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -Wall -I../rtl -I../tb/tests -o $(VVP) $(RTL_SRCS) $(TB_SRCS)

run: compile
	vvp $(VVP) +TESTNAME=$(TEST)

clean:
	rm -rf $(BUILD_DIR) *.vvp *.vcd *.log
