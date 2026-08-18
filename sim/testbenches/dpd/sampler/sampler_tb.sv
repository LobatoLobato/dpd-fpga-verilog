`resetall
`timescale 1ns/1ps
`default_nettype none

module sampler_tb;
    parameter int unsigned DATA_WIDTH    = 16;
    parameter int unsigned DELAY_LEN_MAX = 16;
    parameter int unsigned BATCH_LEN_MAX = 512;
    parameter int unsigned CLK_PERIOD    = 10;
    parameter int unsigned TIMEOUT_LIMIT = 500;

    logic passed = 1;

    logic clk;
    logic rst;
    logic we;
    logic start;
    logic [3:0] delay_length;
    logic [9:0] batch_length;

    taxi_axis_if #(.DATA_W(DATA_WIDTH), .USER_W(2)) ref_axis(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(DATA_WIDTH), .USER_W(2)) fb_axis(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(DATA_WIDTH*2), .USER_W(2)) cap_axis(.tb_clk(clk));

    sampler #(
        .DATA_WIDTH   (DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX),
        .DELAY_LEN_MAX(DELAY_LEN_MAX)
    ) dut (
        .clk, .rst, .we, .start,
        .delay_length, .batch_length,
        .ref_axis, .fb_axis, .cap_axis
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task cleanup();
        rst = 1'b1;
        we = 1'b0;
        start = 1'b0;
        cap_axis.tready = 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
    endtask

    task start_capture();
        @(posedge clk);
        we    = 1'b1;
        start = 1'b1;
        @(posedge clk);
        we    = 1'b0;
        start = 1'b0;
    endtask

    task await_capture_done();
        int unsigned timeout;
        timeout = '0;
        while (dut.presync.running && timeout < TIMEOUT_LIMIT) begin
            @(posedge clk);
            timeout++;
        end
        if (timeout >= TIMEOUT_LIMIT) begin
            $error("  FAIL: timeout waiting for capture");
            passed = 0;
        end
    endtask

    initial begin
        rst = 1'b1;
        we  = 1'b0;
        start = 1'b0;
        delay_length = '0;
        batch_length = '0;
        cap_axis.tready = 1'b0;

        #(CLK_PERIOD * 5);
        rst = 1'b0;
        #(CLK_PERIOD * 2);

        // basic capture, delay=2 batch=4
        $display("\nBasic capture: delay=2, batch=4");
        test_basic(.delay(2), .batch(4));

        // zero delay
        $display("\nDelay=0");
        cleanup();
        test_basic(.delay(0), .batch(5));

        // single-element batch
        $display("\nBatch=1");
        cleanup();
        test_basic(.delay(3), .batch(1));

        // start/we gating
        $display("\nStart/we gating");
        test_start_we_gating();

        // reset during capture
        $display("\nReset during capture");
        test_reset();

        // backpressure on cap_axis
        $display("\ncap_axis backpressure");
        test_backpressure();

        // ref input stall
        $display("\nRef input stall");
        test_ref_stall();

        // fb input stall
        $display("\nFB input stall");
        test_fb_stall();

        // large batch
        $display("\nLarge batch: batch=100, delay=3");
        cleanup();
        test_basic(.delay(3), .batch(100));

        repeat (20) @(posedge clk);

        $display("");
        if (passed) $display("Testbench Result: OK");
        else           $display("Testbench Result: FAILED");
        $display("Simulation done");
        $finish;
    end

    task test_basic(input int unsigned delay, input int unsigned batch);
        delay_length = delay;
        batch_length = batch;

        start_capture();

        // feed enough samples to cover the capture window
        begin
            automatic int unsigned count = batch + delay + 2;
            fork
                for (int unsigned n = 1; n <= count; n++) ref_axis.send(n * 100);
                for (int unsigned n = 1; n <= count; n++) fb_axis.send(n * 10);
            join
        end

        await_capture_done();
        read_and_check(.delay(delay), .batch(batch));
    endtask

    task read_and_check(input int unsigned delay, input int unsigned batch);
        logic [DATA_WIDTH-1:0] got_ref, got_fb, exp_ref, exp_fb;
        automatic int unsigned           idx = 0;
        automatic int unsigned           rd_timeout = 0;

        cap_axis.tready = 1'b1;
        @(posedge clk);
        while (idx < batch && rd_timeout < 500) begin
            if (cap_axis.tvalid && cap_axis.tready) begin
                got_ref = cap_axis.tdata[DATA_WIDTH-1:0];
                got_fb  = cap_axis.tdata[DATA_WIDTH*2-1:DATA_WIDTH];

                exp_ref = (idx + 1) * 100;
                exp_fb  = (delay + idx + 1) * 10;

                if (got_ref !== exp_ref) begin
                    $error("  FAIL: idx=%0d ref mismatch: got %0d, exp %0d", idx, got_ref, exp_ref);
                    passed = 0;
                end
                if (got_fb !== exp_fb) begin
                    $error("  FAIL: idx=%0d fb mismatch: got %0d, exp %0d (delay=%0d)", idx, got_fb, exp_fb, delay);
                    passed = 0;
                end

                idx++;
            end
            rd_timeout++;
            @(posedge clk);
        end

        if (rd_timeout >= 500) begin
            $error("  FAIL: timeout reading cap_axis (tvalid=%b tready=%b tdata=%h)",
                   cap_axis.tvalid, cap_axis.tready, cap_axis.tdata);
            $error("        capturing=%b ref_wr_ptr=%0d fb_wr_ptr=%0d rd_ptr=%0d",
                   dut.sync_buffer.capturing,
                   dut.sync_buffer.ref_wr_ptr, dut.sync_buffer.fb_wr_ptr,
                   dut.sync_buffer.rd_ptr);
            $error("        fills: ref=%0d fb=%0d",
                   dut.sync_buffer.ref_wr_ptr - dut.sync_buffer.rd_ptr,
                   dut.sync_buffer.fb_wr_ptr - dut.sync_buffer.rd_ptr);
            passed = 0;
        end

        cap_axis.tready = 1'b0;

        if (passed && idx == batch)
            $display("  PASS: all %0d output pairs verified", batch);
    endtask

    task test_start_we_gating();
        cleanup();
        delay_length = 2;
        batch_length = 5;

        // start only, no we
        @(posedge clk); start = 1'b1; we = 1'b0;
        @(posedge clk); start = 1'b0;
        repeat (3) @(posedge clk);
        if (dut.presync.running) begin
            $error("  FAIL: running went high with start only");
            passed = 0;
        end else $display("  PASS: start without we not capturing");

        // we only, no start
        @(posedge clk); we = 1'b1; start = 1'b0;
        @(posedge clk); we = 1'b0;
        repeat (3) @(posedge clk);
        if (dut.presync.running) begin
            $error("  FAIL: running went high with we only");
            passed = 0;
        end else $display("  PASS: we without start not capturing");

        // both set
        cleanup();
        test_basic(.delay(2), .batch(5));
        $display("  PASS: start+we capture completes");
    endtask

    task test_reset();
        cleanup();
        delay_length = 2;
        batch_length = 8;

        start_capture();

        // send a few elements
        fork
            for (int unsigned n = 1; n <= 4; n++) ref_axis.send(n * 100);
            for (int unsigned n = 1; n <= 4; n++) fb_axis.send(n * 10);
        join

        @(posedge clk);
        rst = 1'b1;
        @(posedge clk);
        @(posedge clk);
        if (dut.presync.running) begin
            $error("  FAIL: running should be 0 after reset");
            passed = 0;
        end else $display("  PASS: reset clears running");

        // new batch after reset
        rst = 1'b0;
        @(posedge clk);
        @(posedge clk);
        test_basic(.delay(1), .batch(5));
        $display("  PASS: capture after reset completes");
    endtask

    task test_backpressure();
        cleanup();
        delay_length = 1;
        batch_length = 4;

        start_capture();

        // send data
        fork
            for (int unsigned n = 1; n <= 8; n++) ref_axis.send(n * 100);
            for (int unsigned n = 1; n <= 8; n++) fb_axis.send(n * 10);
        join

        await_capture_done();

        // read first half with backpressure
        cap_axis.tready = 1'b0;
        repeat (5) @(posedge clk);
        cap_axis.tready = 1'b1;

        read_and_check(.delay(1), .batch(4));
    endtask

    task test_ref_stall();
        cleanup();
        delay_length = 1;
        batch_length = 5;

        start_capture();

        fork
            begin
                for (int unsigned n = 1; n <= 2; n++) ref_axis.send(n * 100);
                repeat (10) @(posedge clk);
                for (int unsigned n = 3; n <= 8; n++) ref_axis.send(n * 100);
            end
            begin
                for (int unsigned n = 1; n <= 13; n++) fb_axis.send(n * 10);
            end
        join

        await_capture_done();
        read_and_check(.delay(1), .batch(5));
    endtask

    task test_fb_stall();
        cleanup();
        delay_length = 0;
        batch_length = 5;

        start_capture();

        fork
            begin
                for (int unsigned n = 1; n <= 8; n++) ref_axis.send(n * 100);
            end
            begin
                for (int unsigned n = 1; n <= 2; n++) fb_axis.send(n * 10);
                repeat (10) @(posedge clk);
                for (int unsigned n = 3; n <= 8; n++) fb_axis.send(n * 10);
            end
        join

        await_capture_done();
        read_and_check(.delay(0), .batch(5));
    endtask

    initial begin
        $dumpfile("sim/waveforms/dpd/sampler/sampler.vcd");
        $dumpvars(0, sampler_tb);
    end

endmodule
