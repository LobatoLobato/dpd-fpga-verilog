`timescale 1ns/1ps

module tddctl_tb();
    parameter integer CLK_PERIOD = 10;
    parameter reg PRINT = 1;
    logic tb_result = 1;
    
    reg clk, rst;
    reg tdd_tx;
    reg tdd_en;
    reg trigger;
    wire we;
    wire start;
    
    tddctl tddctl (
    	.clk(clk), .rst(rst),
    	.tdd_tx (tdd_tx),
    	.tdd_en (tdd_en),
    	.trigger(trigger),
    	.we     (we),
    	.start  (start)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    task print_uut();
        $display("  tdd_en = %b; tdd_tx = %b; trigger = %b; we: %b; start: %b;", 
            tdd_en, tdd_tx, trigger, we, start
        );
    endtask
    task set_uut(input en, tx, trig, input print = 0);
        
        tdd_en = en; tdd_tx = tx; trigger = trig;
        if (print) print_uut();
    endtask

    task test_truth_table_row(input en, input tx, input e_we, input e_start);
        @(negedge clk) set_uut(en, tx, 1);
        @(posedge clk);
        @(negedge clk) set_uut(0, 0, 0);
        
        tb_result &= (we == e_we) && (start == e_start);

        if (we == e_we && start == e_start) begin
            $display("||   %b    |   %b    ||  %b  |   %b   |: OK", en, tx, we, start);
        end else begin
            $display("||   %b    |   %b    ||  %b  |   %b   |: FAILED(Expected: we == %b && start == %b)", 
                en, tx, we, start, e_we, e_start
            );
        end
    endtask
    
    task test_trigger_delegation (
        string s0, s1,
        reg end_state [2]
    );
        $display("--%s -> %s--", s0, s1);
        @(negedge clk) set_uut(1, 0, 1, PRINT); // Actiavting trigger
        @(negedge clk) set_uut(1, 0, 0, PRINT); // Releasing trigger
        
        $display("  Delaying for a few cycles...");
        repeat(5) @(negedge clk) tb_result &= ~start;
        
        $display("  Setting %s", s1);
        @(negedge clk) set_uut(end_state[0], end_state[1], 0, PRINT);
        
        $display("  Result:");
        @(negedge clk) set_uut(0, 0, 0, PRINT);
        
        tb_result &= start;
    endtask
    
    
    initial begin
        tdd_en = 0; tdd_tx = 0; trigger = 0;
        rst = 1;
        @(posedge clk)
        rst = 0;
        @(posedge clk)

        $display("Testing truth table");
        $display("|| tdd_en | tdd_tx || we  | start ||");
        test_truth_table_row(0, 0, 1, 1);
        test_truth_table_row(0, 1, 1, 1);
        test_truth_table_row(1, 0, 0, 0);
        test_truth_table_row(1, 1, 1, 1);
        @(posedge clk);

        $display("Testing trigger delegation");
        test_trigger_delegation("tdd_tx=off", "tdd_tx=on", {1, 1});
        test_trigger_delegation("tdd_en=on", "tdd_en=off", {0, 0});
        @(posedge clk);
        
        if (tb_result) $display("Testbench Result: OK");
        else           $display("Testbench Result: FAILED");
        $stop;
    end

    initial begin
        $dumpfile("sim/waveforms/dpd/tddctl.vcd");
        $dumpvars(0, tddctl_tb);
    end

endmodule
