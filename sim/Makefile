# Makefile

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
WAVES = 1

VERILOG_SOURCES += $(PWD)/../hdl/proc/proc_bridge.sv $(PWD)/../hdl/cursor.sv $(PWD)/../hdl/proc/*.v
# VERILOG_SOURCES += $(PWD)/../hdl/parse_asm.sv $(PWD)/../hdl/cursor.sv
# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = wrapped_processor

# MODULE is the basename of the Python test file
MODULE = proc_context_tb

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
