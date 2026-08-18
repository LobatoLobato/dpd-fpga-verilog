# ============================================================
# Vivado Simulator (xsim) script
# Description: Waveform setup for the DPD top-level UVM testbench.
#
# Author: based on Elivander Judas Tadeu Pereira - Inatel
# Date: 2026-03-20
# Version: 1.0
#
# ============================================================

# ===================== WAVE =================================
# Log everything to waveform:
log_wave -recursive *

# Light option, define which signals to log into waveform:
# log_wave /testbench/*

# --------------------- bfm_clk0 -----------------------------
#=== Divider for visual separation or group for packaging signals:
add_wave_divider "bfm_clk0_div" -color #0000FF
add_wave_group "bfm_clk0"

#=== Add all signals (*) or list them one by one:
#add_wave {{/testbench/bfm_clk0/*}}
add_wave /testbench/bfm_clk0/clk -at_wave "bfm_clk0"
add_wave /testbench/bfm_clk0/rst -at_wave "bfm_clk0"

# --------------------- ref_axis -----------------------------
#=== Divider for visual separation or group for packaging signals.
add_wave_divider "ref_axis_div" -color #FF0000
add_wave_group "ref_axis"

add_wave /testbench/ref_axis/tdata -at_wave "ref_axis"
add_wave /testbench/ref_axis/tuser -at_wave "ref_axis"
add_wave /testbench/ref_axis/tlast -at_wave "ref_axis"
add_wave /testbench/ref_axis/tvalid -at_wave "ref_axis"
add_wave /testbench/ref_axis/tready -at_wave "ref_axis"

# --------------------- predistorted_axis --------------------
#=== Divider for visual separation or group for packaging signals.
add_wave_divider "predistorted_axis_div" -color #00FF00
add_wave_group "predistorted_axis"

add_wave /testbench/predistorted_axis/tdata -at_wave "predistorted_axis"
add_wave /testbench/predistorted_axis/tuser -at_wave "predistorted_axis"
add_wave /testbench/predistorted_axis/tlast -at_wave "predistorted_axis"
add_wave /testbench/predistorted_axis/tvalid -at_wave "predistorted_axis"
add_wave /testbench/predistorted_axis/tready -at_wave "predistorted_axis"

# --------------------- cap_axis -----------------------------
#=== Divider for visual separation or group for packaging signals.
add_wave_divider "cap_axis_div" -color #FF00FF
add_wave_group "cap_axis"

add_wave /testbench/cap_axis/tdata -at_wave "cap_axis"
add_wave /testbench/cap_axis/tuser -at_wave "cap_axis"
add_wave /testbench/cap_axis/tlast -at_wave "cap_axis"
add_wave /testbench/cap_axis/tvalid -at_wave "cap_axis"
add_wave /testbench/cap_axis/tready -at_wave "cap_axis"

# ===================== RUN ==================================
run all

# ===================== DEBUG ================================
puts "Simulation finished at time [current_time]"
