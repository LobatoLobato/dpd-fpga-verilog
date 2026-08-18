`resetall
`timescale 1ns / 1ps
`default_nettype none

module sync_buffer_tb;
    parameter int unsigned DATA_WIDTH    = 16;
    parameter int unsigned BATCH_LEN_MAX = 512;
    parameter int unsigned CLK_PERIOD    = 10;
    parameter int unsigned TIMEOUT_CYCLES = 10000;

    int unsigned error_count;

    logic clk;
    logic rst;
    logic we;
    logic start;

    logic [DATA_WIDTH-1:0] exp_ref_data [BATCH_LEN_MAX];
    logic [DATA_WIDTH-1:0] exp_fb_data  [BATCH_LEN_MAX];
    int unsigned exp_count;
    int unsigned rd_count;

    taxi_axis_if #(.DATA_W(DATA_WIDTH*2), .USER_W(2)) presynced_axis();
    taxi_axis_if #(.DATA_W(DATA_WIDTH*2), .USER_W(2)) buffered_axis();

    sync_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX)
    ) dut (
        .clk, .rst, .we, .start,
        .presynced_axis,
        .buffered_axis,
        .rd_en(buffered_axis.tready)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES);
        $display("Testbench Result: TIMEOUT");
        $fatal(1, "Simulation timed out after %0d cycles", TIMEOUT_CYCLES);
    end

    always @(posedge clk) begin
        if (buffered_axis.tvalid && buffered_axis.tready) begin
            logic [DATA_WIDTH-1:0] got_ref, got_fb;
            got_ref = buffered_axis.tdata[DATA_WIDTH-1:0];
            got_fb  = buffered_axis.tdata[DATA_WIDTH*2-1:DATA_WIDTH];

            if (rd_count < exp_count) begin
                if (got_ref !== exp_ref_data[rd_count] || got_fb !== exp_fb_data[rd_count]) begin
                    $error("  output[%0d]: MISMATCH ref=%4d (exp %4d), fb=%4d (exp %4d) [tlast=%b]",
                        rd_count, got_ref, exp_ref_data[rd_count],
                        got_fb, exp_fb_data[rd_count], buffered_axis.tlast);
                    error_count <= error_count + 1;
                end else begin
                    $display("  output[%0d]: OK ref=%4d fb=%4d%s",
                        rd_count, got_ref, got_fb,
                        buffered_axis.tlast ? " (last)" : "");
                end
            end else begin
                $error("  output[%0d]: unexpected extra element ref=%4d fb=%4d",
                    rd_count, got_ref, got_fb);
                error_count <= error_count + 1;
            end
            rd_count <= rd_count + 1;
        end
    end

    initial begin
        rst = 1;
        we = 0;
        start = 0;
        presynced_axis.tvalid = 1'b0;
        presynced_axis.tdata  = '0;
        presynced_axis.tuser  = '0;
        presynced_axis.tlast  = 1'b0;
        buffered_axis.tready = 1'b1;

        #(CLK_PERIOD * 5);
        @(negedge clk);
        rst = 0;
        #(CLK_PERIOD * 2);

        // basic: delay=2, batch=3
        $display("\nBasic: delay=2, batch=3");
        run_capture(.delay(2), .batch_len(3),
                    .ref_start(100), .ref_step(100),
                    .fb_start(10), .fb_step(10));

        // zero delay
        #(CLK_PERIOD * 10);
        $display("\nDelay=0, batch=4");
        run_capture(.delay(0), .batch_len(4),
                    .ref_start(1000), .ref_step(100),
                    .fb_start(40), .fb_step(10));

        // larger delay
        #(CLK_PERIOD * 10);
        $display("\nDelay=5, batch=2");
        run_capture(.delay(5), .batch_len(2),
                    .ref_start(1), .ref_step(1),
                    .fb_start(100), .fb_step(100));

        // backpressure
        #(CLK_PERIOD * 10);
        $display("\nBackpressure: delay=1, batch=3");
        run_capture(.delay(1), .batch_len(3),
                    .ref_start(5), .ref_step(5),
                    .fb_start(50), .fb_step(50),
                    .backpressure(1));

        // start=1, we=0
        #(CLK_PERIOD * 10);
        $display("\nStart=1, we=0 (no capture)");
        test_gate(.assert_we(0), .assert_start(1));

        // we=1, start=0
        #(CLK_PERIOD * 10);
        $display("\nWe=1, start=0 (no capture)");
        test_gate(.assert_we(1), .assert_start(0));

        // reset during capture
        #(CLK_PERIOD * 10);
        $display("\nReset during capture");
        test_reset_during_capture();

        // input stall
        #(CLK_PERIOD * 10);
        $display("\nInput stall");
        test_input_stall();

        // tlast early
        #(CLK_PERIOD * 10);
        $display("\nTlast early");
        test_tlast_early();

        // large batch
        #(CLK_PERIOD * 10);
        $display("\nLarge batch (100 elements)");
        test_large_batch();

        // tready deasserted on last read
        #(CLK_PERIOD * 10);
        $display("\nTready deasserted on last read");
        test_tready_last_read();

        #(CLK_PERIOD * 10);
        if (error_count > 0) begin
            $display("Testbench Result: FAILED (%0d errors)", error_count);
        end else begin
            $display("Testbench Result: OK");
        end
        $display("Simulation done");
        $finish;
    end

    // Drive one batch of {fb, ref} pairs on presynced_axis.
    // delay: cycles the fb stream lags the ref stream
    // stall_cycles: idle cycles inserted after the first beat
    task drive_batch(
        input int unsigned delay,
        input int unsigned batch_len,
        input int unsigned ref_start,
        input int unsigned ref_step,
        input int unsigned fb_start,
        input int unsigned fb_step,
        input int unsigned stall_cycles = 0
    );
        int unsigned cycle;
        int unsigned ref_idx, fb_idx;

        @(negedge clk);
        we = 1;
        start = 1;

        ref_idx = 0;
        fb_idx  = 0;
        cycle = 0;

        while (ref_idx < batch_len || fb_idx < batch_len) begin
            logic [1:0] tuser_val;
            logic [DATA_WIDTH-1:0] cur_ref, cur_fb;

            tuser_val[0] = (ref_idx < batch_len) ? 1'b1 : 1'b0;
            tuser_val[1] = (fb_idx < batch_len && cycle >= delay) ? 1'b1 : 1'b0;

            cur_ref = ref_start + ref_idx * ref_step;
            cur_fb  = fb_start + fb_idx * fb_step;

            @(negedge clk);

            if (cycle == 0) begin
                we = 0;
                start = 0;
            end

            presynced_axis.tvalid = 1'b1;
            presynced_axis.tdata  = {cur_fb, cur_ref};
            presynced_axis.tuser  = tuser_val;
            begin
                int unsigned incr0, incr1;
                incr0 = tuser_val[0];
                incr1 = tuser_val[1];
                presynced_axis.tlast = ((ref_idx + incr0) >= batch_len &&
                                      (fb_idx  + incr1) >= batch_len);
            end

            if (tuser_val[0]) ref_idx++;
            if (tuser_val[1]) fb_idx++;
            cycle++;

            if (stall_cycles > 0 && cycle == 1) begin
                repeat (stall_cycles) begin
                    @(negedge clk);
                    presynced_axis.tvalid = 1'b0;
                end
            end
        end

        @(negedge clk);
        presynced_axis.tvalid = 1'b0;
        presynced_axis.tlast  = 1'b0;
    endtask

    task run_capture(
        input int unsigned delay,
        input int unsigned batch_len,
        input int unsigned ref_start,
        input int unsigned ref_step,
        input int unsigned fb_start,
        input int unsigned fb_step,
        input bit backpressure = 0,
        input int unsigned stall_cycles = 0
    );
        $display("  Starting capture: delay=%0d, batch=%0d (backpressure=%0d, stall=%0d)",
                 delay, batch_len, backpressure, stall_cycles);

        exp_count = batch_len;
        for (int unsigned i = 0; i < batch_len; i++) begin
            exp_ref_data[i] = ref_start + i * ref_step;
            exp_fb_data[i]  = fb_start + i * fb_step;
        end
        rd_count = 0;

        if (backpressure) begin
            fork
                begin
                    buffered_axis.tready = 1'b1;
                    while (rd_count < batch_len + 10) begin
                        @(negedge clk);
                        @(negedge clk);
                        buffered_axis.tready = 1'b0;
                        @(negedge clk);
                        buffered_axis.tready = 1'b1;
                    end
                    buffered_axis.tready = 1'b1;
                end
            join_none
        end

        drive_batch(.delay(delay), .batch_len(batch_len),
                    .ref_start(ref_start), .ref_step(ref_step),
                    .fb_start(fb_start), .fb_step(fb_step),
                    .stall_cycles(stall_cycles));

        repeat (batch_len + 40) @(posedge clk);

        if (rd_count != exp_count) begin
            $error("  Only read %0d of %0d expected elements", rd_count, exp_count);
            error_count <= error_count + 1;
        end else begin
            $display("  Read all %0d elements OK", rd_count);
        end

        if (backpressure) begin
            disable fork;
            buffered_axis.tready = 1'b1;
        end
    endtask

    task test_gate(input bit assert_we, input bit assert_start);
        $display("  Asserting we=%0d, start=%0d, capture should NOT start", assert_we, assert_start);

        exp_count = 0;
        rd_count = 0;

        @(negedge clk);
        we = assert_we;
        start = assert_start;

        @(negedge clk);
        we = 0;
        start = 0;

        // Drive a few data cycles; nothing should slip through
        repeat (5) begin
            @(negedge clk);
            presynced_axis.tvalid = 1'b1;
            presynced_axis.tdata  = '1;
            presynced_axis.tuser  = 2'b11;
        end
        @(negedge clk);
        presynced_axis.tvalid = 1'b0;

        repeat (20) @(posedge clk);

        if (rd_count != 0) begin
            $error("  ERROR: %0d unexpected reads while capture was gated", rd_count);
            error_count <= error_count + 1;
        end else begin
            $display("  No reads, OK");
        end

        // Verify a subsequent normal capture works
        run_capture(.delay(0), .batch_len(3),
                    .ref_start(1), .ref_step(10),
                    .fb_start(100), .fb_step(100));
    endtask

    task test_reset_during_capture();
        $display("  Starting capture, then resetting mid-way...");

        exp_count = 3;
        for (int unsigned i = 0; i < 3; i++) begin
            exp_ref_data[i] = 100 + i * 10;
            exp_fb_data[i]  = 1 + i;
        end
        rd_count = 0;

        @(negedge clk);
        we = 1;
        start = 1;

        // Write element 0
        @(negedge clk);
        we = 0;
        start = 0;
        presynced_axis.tvalid = 1'b1;
        presynced_axis.tdata  = {16'd1, 16'd100};
        presynced_axis.tuser  = 2'b11;

        // Write element 1 (then assert reset)
        @(negedge clk);
        presynced_axis.tvalid = 1'b1;
        presynced_axis.tdata  = {16'd2, 16'd110};
        presynced_axis.tuser  = 2'b11;

        // Assert reset
        @(negedge clk);
        rst = 1;
        presynced_axis.tvalid = 1'b0;

        // Hold reset for 5 cycles
        repeat (5) @(negedge clk);
        rst = 0;

        @(negedge clk);
        presynced_axis.tvalid = 1'b0;

        repeat (30) @(posedge clk);

        // Capture was aborted by reset; a new capture must work cleanly.
        $display("  Reads after reset: %0d (capture was aborted, expecting 0 reads of original batch)", rd_count);

        $display("  Verifying new capture after reset...");
        run_capture(.delay(0), .batch_len(3),
                    .ref_start(10), .ref_step(1),
                    .fb_start(50), .fb_step(10));
    endtask

    task test_input_stall();
        $display("  Running capture with input stall after first element...");

        // Use run_capture with stall_cycles to inject idle cycles
        run_capture(.delay(0), .batch_len(4),
                    .ref_start(100), .ref_step(25),
                    .fb_start(7), .fb_step(7),
                    .stall_cycles(3));
    endtask

    task test_tlast_early();
        $display("  Driving tlast early after 2 elements...");

        exp_count = 2;
        for (int unsigned i = 0; i < 2; i++) begin
            exp_ref_data[i] = 200 + i * 100;
            exp_fb_data[i]  = 20 + i * 20;
        end
        rd_count = 0;

        @(negedge clk);
        we = 1;
        start = 1;

        // Drive 2 elements, then tlast
        // Element 0
        @(negedge clk);
        we = 0;
        start = 0;
        presynced_axis.tvalid = 1'b1;
        presynced_axis.tdata  = {16'd20, 16'd200};
        presynced_axis.tuser  = 2'b11;
        presynced_axis.tlast  = 1'b0;

        // Element 1, assert tlast
        @(negedge clk);
        presynced_axis.tvalid = 1'b1;
        presynced_axis.tdata  = {16'd40, 16'd300};
        presynced_axis.tuser  = 2'b11;
        presynced_axis.tlast  = 1'b1;

        @(negedge clk);
        presynced_axis.tvalid = 1'b0;
        presynced_axis.tlast  = 1'b0;

        repeat (40) @(posedge clk);

        if (rd_count != 2) begin
            $error("  Expected 2 reads, got %0d", rd_count);
            error_count <= error_count + 1;
        end else begin
            $display("  Read all %0d elements OK", rd_count);
        end
    endtask

    task test_large_batch();
        $display("  Running capture with batch of 100 elements...");
        run_capture(.delay(0), .batch_len(100),
                    .ref_start(1), .ref_step(1),
                    .fb_start(1000), .fb_step(10));
    endtask

    task automatic test_tready_last_read();
        int unsigned batch_len = 4;

        $display("  Deasserting tready right before the last read...");

        exp_count = batch_len;
        for (int unsigned i = 0; i < batch_len; i++) begin
            exp_ref_data[i] = 500 + i;
            exp_fb_data[i]  = 900 + i;
        end
        rd_count = 0;

        // Deassert tready for a couple cycles when only the last read is pending
        fork
            begin
                int unsigned reads;
                reads = 0;
                while (reads < batch_len - 1) begin
                    @(posedge clk);
                    if (buffered_axis.tvalid && buffered_axis.tready) begin
                        reads++;
                    end
                end
                @(negedge clk);
                buffered_axis.tready = 1'b0;
                @(negedge clk);
                @(negedge clk);
                buffered_axis.tready = 1'b1;
            end
        join_none

        drive_batch(.delay(0), .batch_len(batch_len),
                    .ref_start(500), .ref_step(1),
                    .fb_start(900), .fb_step(1));

        repeat (batch_len + 30) @(posedge clk);

        disable fork;
        buffered_axis.tready = 1'b1;

        if (rd_count != batch_len) begin
            $error("  Only read %0d of %0d expected elements", rd_count, batch_len);
            error_count <= error_count + 1;
        end else begin
            $display("  Read all %0d elements OK (last read was stalled by tready)", rd_count);
        end
    endtask

    initial begin
        $dumpfile("sim/waveforms/dpd/sampler/sync_buffer.vcd");
        $dumpvars(0, sync_buffer_tb);
    end
endmodule
