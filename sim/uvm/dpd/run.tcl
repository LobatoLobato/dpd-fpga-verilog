# ============================================================
# Vivado Simulator (xsim) script
# Description: This script allows configuration and control of
# the compilation, elaboration and simulation flows with the
# built-in Vivado simulator.
#
# Author: Elivander Judas Tadeu Pereira - Inatel
# Date: 2026-03-20
# Version: 1.0
#
# Version history:
# 1.0 Initial version aiming source code from UVM_PRIMER book.
#
# ============================================================

# ========================== INIT ============================
source config.tcl

# Allow command-line overrides of target, GUI mode, and UVM test class, e.g.
#   vivado -mode tcl -nolog -nojournal -source run.tcl -tclargs run gui sampler_suite
if {[llength $argv] > 0} {
    set SCRIPT_TARGET [lindex $argv 0]
}
if {[llength $argv] > 1} {
    set GUI_MODE [lindex $argv 1]
}
if {[llength $argv] > 2} {
    set UVM_TEST [lindex $argv 2]
}

# ========================== FUNCTIONS =======================
set CUR_DATE [clock format [clock seconds] -format "|%Y/%m/%d %H:%M:%S|"]

proc check_tools {} {
    puts "Checking for installed Xilinx tools..."

    foreach tool {xvlog xelab xsim} {
        if {[catch {exec which $tool}]} {
            puts "ERROR: $tool not found"
            exit 1
        } else {
            puts "$tool OK"
        }
    }
}

proc prepare_dir {} {
    global RUN_DIR
    file mkdir $RUN_DIR
}

proc parse_uvm_args {} {
    global UVM_ARGS UVM_TEST UVM_VERBOSITY RND_SEED
    if {$UVM_TEST ne ""} {
        lappend UVM_ARGS "-testplusarg" "UVM_TESTNAME=$UVM_TEST"
    }

    if {$UVM_VERBOSITY ne ""} {
        lappend UVM_ARGS "-testplusarg" "UVM_VERBOSITY=$UVM_VERBOSITY"
    }

    if {$RND_SEED ne ""} {
        lappend UVM_ARGS "-testplusarg" "seed=$RND_SEED"
    }
}

proc compile {} {
    global RUN_DIR ROOT_DIR RTL_PATHS TB_PATHS LIB_PATHS
    global XVHDL_RTL_FILES XVHDL_TB_FILES
    global XVLOG_RTL_FILES XVLOG_TB_FILES

    puts "Compiling..."
    prepare_dir

    cd $RUN_DIR

    # VHDL
    if {[llength $XVHDL_RTL_FILES] > 0 || [llength $XVHDL_TB_FILES] > 0} {
        exec xvhdl --2008 \
            {*}$XVHDL_RTL_FILES \
            {*}$XVHDL_TB_FILES \
            -log xvhdl_compile.log >@stdout 2>@stderr
    }

    # SV
    exec xvlog -sv \
        -d TESTBENCH \
        --include $ROOT_DIR \
        --include $RTL_PATHS \
        --include $TB_PATHS \
        --include $LIB_PATHS \
        {*}$XVLOG_RTL_FILES \
        {*}$XVLOG_TB_FILES \
        -L uvm \
        -log xvlog_compile.log >@stdout 2>@stderr
}

proc elaborate {} {
    global RUN_DIR TOP_NAME

    puts "Elaborating..."
    cd $RUN_DIR

    exec xelab $TOP_NAME \
        -relax \
        -s "work.$TOP_NAME" \
        -L uvm \
        -L work \
        -debug typical \
        -timescale 1ns/100ps \
        -log elaborate.log
}

proc run {GUI_MODE} {
    global RUN_DIR TOP_NAME UVM_ARGS ROOT_DIR

    puts "Running simulation..."
    cd $RUN_DIR

    if {$GUI_MODE eq "gui"} {
        exec xsim "work.$TOP_NAME" \
            -wdb "work.$TOP_NAME.wdb" \
            -log simulate.log \
            {*}$UVM_ARGS \
            -gui \
            -tclbatch "$ROOT_DIR/wave.tcl" >@stdout 2>@stderr
    } else {
        exec xsim "work.$TOP_NAME" \
            -log simulate.log \
            {*}$UVM_ARGS \
            -tclbatch "$ROOT_DIR/run_coverage.tcl" >@stdout 2>@stderr
    }

    cd ../..
}

proc clean_coverage {} {
    global RUN_DIR
    puts "Cleaning coverage database..."
    file delete -force "$RUN_DIR/xsim.covdb" "$RUN_DIR/xsim_coverage_report"
}

proc clean {} {
    global ROOT_DIR
    puts "Cleaning..."
    file delete -force "$ROOT_DIR/work"
    clean_coverage
}

proc help {} {
    puts ""
    puts "Usage:"
    puts "1. Open Vivado in tcl mode:"
    puts "      vivado -mode tcl"
    puts "2. Change directory to the project folder:"
    puts "      cd <dir_path>"
    puts "3. Set the environment variables as needed:"
    puts "      set UVM_TEST        <uvm_test_name>"
    puts "      set UVM_VERBOSITY   <UVM_LOW|MEDIUM|HIGH>"
    puts "      set UVM_ARGS        <list>"
    puts "      set RND_SEED        <int>"
    puts "      set SCRIPT_TARGET   <target>"
    puts "      set GUI_MODE        <no-gui|gui>"
    puts ""
    puts "Available script targets:"
    puts "      compile             Compile design"
    puts "      elaborate           Elaborate design"
    puts "      run                 Run simulation"
    puts "      all                 Full flow"
    puts "      clean               Clean files"
    puts ""
    puts "4. Run the file: source run.tcl"
    puts ""
}

# ========================== FLOW CONTROL ====================
if {![info exists SCRIPT_TARGET]} {
    set SCRIPT_TARGET "help"
}

if {![info exists GUI_MODE]} {
    set GUI_MODE "no-gui"
}

parse_uvm_args

switch $SCRIPT_TARGET {
    compile {
        check_tools
        compile
    }
    elaborate {
        elaborate
    }
    run {
        run $GUI_MODE
    }
    clean {
        clean
    }
    all {
        check_tools
        compile
        elaborate
        run $GUI_MODE
    }
    default {
        help
    }
}
