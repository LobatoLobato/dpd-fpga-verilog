# ============================================================
# Vivado Simulator (xsim) script
# Description: UVM testbench configuration for the DPD top-level
# (filter + sampler loopback via configctl/tddctl), modeled after
# the "UVM - Reference" UART project.
#
# Author: based on Elivander Judas Tadeu Pereira - Inatel
# Date: 2026-03-20
# Version: 1.0
#
# ============================================================

# ===================== UVM controls =========================
# Comment these 2 lines to allow changing parameter in runtime
set SCRIPT_TARGET   "all"
set GUI_MODE        "no-gui"

# UVM controls
set UVM_TEST        "dpd_test"
set UVM_VERBOSITY   "UVM_MEDIUM"
set UVM_ARGS        [list ]
set RND_SEED        1

# ================== Project definitions =====================
# Main directories
set ROOT_DIR        [file normalize [file dirname [info script]]]
set RUN_DIR         "$ROOT_DIR/work/sim"
set REPO_DIR        [file normalize "$ROOT_DIR/../../.."]

# Design (DUT) and Testbench (simulation) directories
set RTL_PATHS       "$REPO_DIR/rtl"
set TB_PATHS        "$ROOT_DIR"

# Shared UVM library (axis/axil agents, BFM task helpers)
set LIB_PATHS       "$ROOT_DIR/../lib"

# Design (DUT) file list (VHDL and Verilog/SV separated)
set XVHDL_RTL_FILES [list ]
set XVLOG_RTL_FILES [list "$RTL_PATHS/interfaces/taxi_axis_if.sv" \
                          "$RTL_PATHS/interfaces/taxi_axil_if.sv" \
                          "$RTL_PATHS/datapath/configctl.sv" \
                          "$RTL_PATHS/dpd/tddctl.sv" \
                          "$RTL_PATHS/dpd/sampler.sv" \
                          "$RTL_PATHS/dpd/filter.sv" \
                          "$RTL_PATHS/top/top.sv" ]

# Testbench (simulation) file list (VHDL and Verilog/SV separated)
# Note: items/agents/scoreboard/coverage/sequences are pulled in via
# `include chains from dpd_test.sv (reference-style), so only the
# BFM, the tests, and the top module are listed here.
set XVHDL_TB_FILES  [list ]
set XVLOG_TB_FILES  [list "$TB_PATHS/dpd_bfm.sv" \
                          "$TB_PATHS/dpd_test.sv" \
                          "$TB_PATHS/testbench.sv" ]

# Name of the top level simulation module
set TOP_NAME        "testbench"
