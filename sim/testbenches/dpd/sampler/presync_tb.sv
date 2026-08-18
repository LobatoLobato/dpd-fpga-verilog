`resetall
`timescale 1ns/1ps
`default_nettype none

module presync_tb;
    parameter int unsigned DATA_WIDTH    = 16;
    parameter int unsigned DELAY_LEN_MAX = 16;
    parameter int unsigned BATCH_LEN_MAX = 512;
    parameter int unsigned CLK_PERIOD    = 10;
    parameter int unsigned TIMEOUT_LIMIT = 300;

    logic passed = 1;

    logic clk;
    logic rst;
    logic we;
    logic start;
    logic [3:0] delay_length;
    logic [9:0] batch_length;

    taxi_axis_if #(.DATA_W(DATA_WIDTH), .USER_W(2)) ref_axis(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(DATA_WIDTH), .USER_W(2)) fb_axis(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(DATA_WIDTH*2), .USER_W(2)) presynced_axis(.tb_clk(clk));

    presync #(
        .DELAY_LEN_MAX(DELAY_LEN_MAX),
        .BATCH_LEN_MAX(BATCH_LEN_MAX)
    ) dut (
        .clk, .rst, .we, .start,
        .delay_length, .batch_length,
        .ref_axis, .fb_axis, .presynced_axis
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task cleanup();
        rst = 1'b1;
        we = 1'b0;
        start = 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
    endtask

    task start_batch();
        @(posedge clk);
        we    = 1'b1;
        start = 1'b1;
        @(posedge clk);
        we    = 1'b0;
        start = 1'b0;
    endtask

    task run_batch(input int unsigned delay, input int unsigned batch, input int unsigned count);
        $display("  Batch: delay=%0d, batch=%0d, count=%0d", delay, batch, count);

        delay_length = delay;
        batch_length = batch;

        start_batch();

        fork
            for (int unsigned n = 1; n <= count; n++) ref_axis.send(n * 100);
            for (int unsigned n = 1; n <= count; n++) fb_axis.send(n * 10);
        join
        await_batch_done();
    endtask

    task await_batch_done();
        int unsigned timeout;
        timeout = '0;
        while (dut.running && timeout < TIMEOUT_LIMIT) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= TIMEOUT_LIMIT) begin
            $error("  FAIL: timeout waiting for batch to complete");
            passed = 0;
        end else begin
            $display("  PASS: batch complete");
        end
    endtask

    // output checker
    always @(posedge clk) begin
        if (!rst && presynced_axis.tvalid && presynced_axis.tready && dut.running) begin
            logic [1:0] exp_tuser;
            logic        exp_tlast;

            exp_tuser[1] = dut.running && dut.capturing_fb;
            exp_tuser[0] = dut.running && dut.capturing_ref;
            exp_tlast    = dut.running && (
                (dut.capturing_fb  && (dut.fb_batch_cnt == batch_length - 1) && (dut.ref_batch_cnt == batch_length)) ||
                (dut.capturing_ref && (dut.ref_batch_cnt == batch_length - 1) && (dut.fb_batch_cnt == batch_length)) ||
                (dut.capturing_ref && (dut.ref_batch_cnt == batch_length - 1) &&
                 dut.capturing_fb  && (dut.fb_batch_cnt == batch_length - 1))
            );

            if (presynced_axis.tuser !== exp_tuser) begin
                $error("  FAIL: tuser mismatch: got %b, exp %b (ref=%0d fb=%0d capture=%0d run=%b)",
                    presynced_axis.tuser, exp_tuser,
                    dut.ref_batch_cnt, dut.fb_batch_cnt, dut.capture_cnt, dut.running);
                passed = 0;
            end
            if (presynced_axis.tlast !== exp_tlast) begin
                $error("  FAIL: tlast mismatch: got %b, exp %b (ref=%0d fb=%0d batch=%0d)",
                    presynced_axis.tlast, exp_tlast,
                    dut.ref_batch_cnt, dut.fb_batch_cnt, batch_length);
                passed = 0;
            end
        end
    end

    // test cases
    initial begin
        rst = 1'b1;
        we  = 1'b0;
        start = 1'b0;
        delay_length = '0;
        batch_length = '0;
        presynced_axis.tready = 1'b1;

        #(CLK_PERIOD * 5);
        rst = 1'b0;
        #(CLK_PERIOD * 2);

        // basic: delay=3 batch=5
        $display("\nBasic: delay=3, batch=5");
        run_batch(.delay(3), .batch(5), .count(8));

        // zero delay
        $display("\nDelay=0");
        cleanup();
        run_batch(.delay(0), .batch(5), .count(8));
        if (dut.ref_batch_cnt == 5 && dut.fb_batch_cnt == 5)
            $display("  PASS: capture counts correct (5/5)");
        else begin
            $error("  FAIL: capture counts ref=%0d fb=%0d", dut.ref_batch_cnt, dut.fb_batch_cnt);
            passed = 0;
        end

        // single-element batch
        $display("\nBatch=1");
        cleanup();
        run_batch(.delay(2), .batch(1), .count(3));
        if (dut.ref_batch_cnt == 1 && dut.fb_batch_cnt == 1)
            $display("  PASS: single-element batch captured 1 element each");
        else begin
            $error("  FAIL: batch=1 counts ref=%0d fb=%0d", dut.ref_batch_cnt, dut.fb_batch_cnt);
            passed = 0;
        end

        // start/we gating
        $display("\nStart/we gating");
        test_start_we_gating();

        // reset during capture
        $display("\nReset during capture");
        test_reset_during_capture();

        // backpressure on presynced_axis
        $display("\nSync-axis backpressure");
        test_backpressure();

        // ref input stall
        $display("\nRef input stall");
        test_ref_stall();

        // fb input stall
        $display("\nFB input stall");
        test_fb_stall();

        // large batch
        $display("\nLarge batch: batch=100");
        cleanup();
        run_batch(.delay(3), .batch(100), .count(150));
        if (dut.ref_batch_cnt == 100 && dut.fb_batch_cnt == 100)
            $display("  PASS: large batch captured 100 elements each");
        else begin
            $error("  FAIL: large batch counts ref=%0d fb=%0d", dut.ref_batch_cnt, dut.fb_batch_cnt);
            passed = 0;
        end

        // fewer inputs than batch (DUT should hang)
        $display("\nFewer inputs than batch (DUT should hang)");
        test_fewer_inputs();

        repeat (10) @(posedge clk);

        $display("");
        if (passed) $display("Testbench Result: OK");
        else           $display("Testbench Result: FAILED");
        $display("--- End of Simulation ---");
        $finish;
    end

    task test_start_we_gating();
        cleanup();
        delay_length = 2;
        batch_length = 5;

        // start only, no we
        @(posedge clk); start = 1'b1; we = 1'b0;
        @(posedge clk); start = 1'b0;
        repeat (3) @(posedge clk);
        if (dut.running) begin
            $error("  FAIL: running went high with start only");
            passed = 0;
        end else $display("  PASS: start without we, running stays 0");

        // we only, no start
        @(posedge clk); we = 1'b1; start = 1'b0;
        @(posedge clk); we = 1'b0;
        repeat (3) @(posedge clk);
        if (dut.running) begin
            $error("  FAIL: running went high with we only");
            passed = 0;
        end else $display("  PASS: we without start, running stays 0");

        // both set
        cleanup();
        run_batch(.delay(2), .batch(5), .count(8));
    endtask

    task test_reset_during_capture();
        cleanup();
        delay_length = 2;
        batch_length = 8;

        start_batch();

        // send first few elements
        fork
            for (int unsigned n = 1; n <= 4; n++) ref_axis.send(n * 100);
            for (int unsigned n = 1; n <= 4; n++) fb_axis.send(n * 10);
        join

        @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        @(posedge clk);
        if (dut.running) begin
            $error("  FAIL: running should be 0 after reset");
            passed = 0;
        end else if (dut.ref_batch_cnt != 0 || dut.fb_batch_cnt != 0 || dut.capture_cnt != 0) begin
            $error("  FAIL: counters not cleared after reset");
            passed = 0;
        end else $display("  PASS: reset clears running and counters");

        // start a new batch after reset
        rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
        run_batch(.delay(1), .batch(5), .count(8));
    endtask

    task test_backpressure();
        cleanup();
        delay_length = 1;
        batch_length = 4;
        presynced_axis.tready = 1'b1;

        start_batch();

        fork
            begin
                ref_axis.send(100); ref_axis.send(200);
                presynced_axis.tready = 1'b0;
                repeat (5) @(posedge clk);
                presynced_axis.tready = 1'b1;
                ref_axis.send(300); ref_axis.send(400);
                ref_axis.send(500); ref_axis.send(600); // extra to cover delay
            end
            begin
                fb_axis.send(10); fb_axis.send(20);
                repeat (5) @(posedge clk);
                fb_axis.send(30); fb_axis.send(40);
                fb_axis.send(50); fb_axis.send(60);
            end
        join
        await_batch_done();
    endtask

    task test_ref_stall();
        cleanup();
        delay_length = 1;
        batch_length = 5;
        presynced_axis.tready = 1'b1;

        start_batch();

        fork
            begin
                ref_axis.send(100); ref_axis.send(200);
                repeat (10) @(posedge clk);
                ref_axis.send(300); ref_axis.send(400); ref_axis.send(500);
            end
            begin
                // send enough to cover ref stall + delay
                for (int unsigned n = 1; n <= 12; n++) fb_axis.send(n * 10);
            end
        join
        await_batch_done();
    endtask

    task test_fb_stall();
        cleanup();
        delay_length = 0;
        batch_length = 5;
        presynced_axis.tready = 1'b1;

        start_batch();

        fork
            begin
                for (int unsigned n = 1; n <= 8; n++) ref_axis.send(n * 100);
            end
            begin
                fb_axis.send(10); fb_axis.send(20);
                repeat (10) @(posedge clk);
                fb_axis.send(30); fb_axis.send(40); fb_axis.send(50);
            end
        join
        await_batch_done();
    endtask

    task test_fewer_inputs();
        cleanup();
        delay_length = 0;
        batch_length = 10;
        presynced_axis.tready = 1'b1;

        start_batch();

        fork
            for (int unsigned n = 1; n <= 4; n++) ref_axis.send(n * 100);
            for (int unsigned n = 1; n <= 4; n++) fb_axis.send(n * 10);
        join

        repeat (20) @(posedge clk);
        if (!dut.running) begin
            $error("  FAIL: DUT should hang (running=1) with fewer inputs (ref=%0d fb=%0d batch=%0d)",
                dut.ref_batch_cnt, dut.fb_batch_cnt, batch_length);
            passed = 0;
        end else $display("  PASS: DUT hangs (running stays high)");

        @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
    endtask

    initial begin
        $dumpfile("sim/waveforms/dpd/sampler/presync.vcd");
        $dumpvars(0, presync_tb);
    end

endmodule
