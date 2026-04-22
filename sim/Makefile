# DDR3 控制器仿真 Makefile（iverilog）
TOP      := tb_top
BUILD_DIR:= build
VVP      := $(BUILD_DIR)/sim.vvp
ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

RTL_SRCS := \
  $(ROOT)/rtl/ddr3_ctrl_top.v \
  $(ROOT)/rtl/axi/sync_fifo.v \
  $(ROOT)/rtl/axi/axi_slave_if.v \
  $(ROOT)/rtl/cmd/addr_map.v \
  $(ROOT)/rtl/cmd/cmd_split.v \
  $(ROOT)/rtl/cmd/cmd_reorder_l1.v \
  $(ROOT)/rtl/cmd/cmd_reorder_l2.v \
  $(ROOT)/rtl/buffer/write_buffer.v \
  $(ROOT)/rtl/buffer/read_buffer.v \
  $(ROOT)/rtl/bank/bank_ctrl.v \
  $(ROOT)/rtl/bank/bank_ctrl_top.v \
  $(ROOT)/rtl/refresh/refresh_ctrl.v \
  $(ROOT)/rtl/init/init_fsm.v \
  $(ROOT)/rtl/dfi/dfi_if.v

TB_SRCS := \
  $(ROOT)/tb/ddr3_model.v \
  $(ROOT)/tb/axi_master_bfm.sv \
  $(ROOT)/tb/scoreboard.sv \
  $(ROOT)/tb/tb_top.sv

all: compile

compile:
	@mkdir -p $(BUILD_DIR)
	iverilog -g2012 -Wall -I$(ROOT)/rtl -I$(ROOT)/tb/tests -o $(VVP) $(RTL_SRCS) $(TB_SRCS)

run: compile
	vvp $(VVP) +TESTNAME=$(TEST)

clean:
	rm -rf $(BUILD_DIR) *.vvp *.vcd *.log
