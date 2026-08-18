`timescale 1ns/1ps
`include "filter_model.svh"

module fb_emulator #(
    parameter integer DATA_W = 32,
    parameter integer FB_DELAY_CYCLES = 8
)(
    input wire clk,
    input wire rst,
    taxi_axis_if.snk in_axis,
    taxi_axis_if.src out_axis
);
    localparam integer DEPTH = (FB_DELAY_CYCLES > 0) ? FB_DELAY_CYCLES : 1;

    logic [DEPTH-1:0] valid;
    logic [DATA_W-1:0] data [DEPTH];
    logic tlast [DEPTH];

    logic [DEPTH-1:0] move;
    always_comb begin
        move[DEPTH-1] = out_axis.tready;
        for (int k = DEPTH-2; k >= 0; k--)
            move[k] = move[k+1] | ~valid[k+1];
    end

    assign in_axis.tready  = move[0];
    assign out_axis.tvalid = valid[DEPTH-1];
    assign out_axis.tdata  = data[DEPTH-1];
    assign out_axis.tlast  = tlast[DEPTH-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int k = 0; k < DEPTH; k++) valid[k] <= 1'b0;
        end else begin
            for (int k = DEPTH-1; k > 0; k--) begin
                if (move[k]) begin
                    data[k]  <= data[k-1];
                    tlast[k] <= tlast[k-1];
                    valid[k] <= valid[k-1];
                end
            end
            if (move[0]) begin
                data[0]  <= in_axis.tdata;
                tlast[0] <= in_axis.tlast;
                valid[0] <= in_axis.tvalid;
            end
        end
    end
endmodule

module top_tb();
    parameter integer DATA_WIDTH = 16;
    parameter integer PACKED_IQ_DATA_WIDTH = DATA_WIDTH * 2;
    parameter integer BATCH_LEN_MAX  = 64;
    parameter integer DELAY_LEN_MAX  = 32;
    parameter integer WEIGHT_W       = 12;
    parameter integer AXIL_DATA_W = 32;
    parameter integer AXIL_ADDR_W = configctl_defs::ADDR_W;
    parameter integer CLK_PERIOD  = 10;
    parameter integer FB_DELAY_CYCLES = 8;
    parameter integer FILTER_LATENCY = 4;
    parameter integer N_WEIGHTS = 4;

    localparam integer STRB_W = AXIL_DATA_W / 8;

    reg clk, rst, tdd_sig;

    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) ref_axis(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) predistorted_axis(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) fb_axis_int(.tb_clk(clk));
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH * 2)) cap_axis(.tb_clk(clk));
    taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)) axil(.tb_clk(clk));

    // Emulated PA feedback path: predistorted_axis -> (latency) -> fb_axis_int
    fb_emulator #(
        .DATA_W(PACKED_IQ_DATA_WIDTH),
        .FB_DELAY_CYCLES(FB_DELAY_CYCLES)
    ) fb_emu (
        .clk(clk), .rst(rst),
        .in_axis(predistorted_axis),
        .out_axis(fb_axis_int)
    );

    top #(
        .DATA_WIDTH   (DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX),
        .DELAY_LEN_MAX(DELAY_LEN_MAX),
        .WEIGHT_W     (WEIGHT_W),
        .AXIL_DATA_W  (AXIL_DATA_W),
        .AXIL_ADDR_W  (AXIL_ADDR_W)
    ) dut (
        .clk(clk), .rst(rst), .tdd_sig(tdd_sig),
        .ref_axis(ref_axis),
        .fb_axis(fb_axis_int),
        .predistorted_axis(predistorted_axis),
        .cap_axis(cap_axis),
        .axil(axil)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Model state / scoreboard
    logic signed [DATA_WIDTH-1:0] model_i0 = 0, model_q0 = 0;
    logic signed [DATA_WIDTH-1:0] model_i1 = 0, model_q1 = 0;
    logic signed [WEIGHT_W-1:0] wi_m [N_WEIGHTS];
    logic signed [WEIGHT_W-1:0] wq_m [N_WEIGHTS];
    logic [DATA_WIDTH*2-1:0] expected_fb_q [$]; // {fb_q, fb_i}
    logic [DATA_WIDTH*2-1:0] sent_ref_q [$];    // {q, i}
    logic bypass_mode = 0; // expected_fb = ref itself (filter bypass)

    int pass_cnt = 0;
    int fail_cnt = 0;

    function automatic logic [15:0] lfsr_next();
        static logic [31:0] state = 32'hdead_beef;
        state = {state[30:0], state[31] ^ state[21] ^ state[1] ^ state[0]};
        lfsr_next = state[15:0];
    endfunction

    task automatic check_eq(input logic [AXIL_DATA_W-1:0] got,
                            input logic [AXIL_DATA_W-1:0] exp,
                            input string what);
        if (got === exp) begin
            $display("    PASS: %s (got=%0d)", what, got);
            pass_cnt++;
        end else begin
            $error("    FAIL: %s got=%0d exp=%0d", what, got, exp);
            fail_cnt++;
        end
    endtask

    // Configuration / control helpers
    task automatic reset_system();
        rst = 1'b1;
        tdd_sig = 1'b0;
        cap_axis.tready = 1'b0;
        axil.awaddr = 0; axil.awvalid = 0; axil.wdata = 0; axil.wstrb = 0;
        axil.wvalid = 0; axil.bready = 0;
        axil.araddr = 0; axil.arvalid = 0; axil.rready = 0;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        model_i0 = 0; model_q0 = 0; model_i1 = 0; model_q1 = 0;
        expected_fb_q.delete();
        sent_ref_q.delete();
        bypass_mode = 0;
        repeat (2) @(posedge clk);
    endtask

    task automatic cfg_write_all(input int batch,
                                 input int delay,
                                 input logic signed [WEIGHT_W-1:0] wi_in [N_WEIGHTS],
                                 input logic signed [WEIGHT_W-1:0] wq_in [N_WEIGHTS]);
        for (int k = 0; k < N_WEIGHTS; k++) begin
            axil.write(configctl_defs::reg_addr_t'(int'(configctl_defs::REG_WEIGHT_I0) + k),
                       {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, wi_in[k]});
            axil.write(configctl_defs::reg_addr_t'(int'(configctl_defs::REG_WEIGHT_Q0) + k),
                       {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, wq_in[k]});
            wi_m[k] = $signed(wi_in[k]);
            wq_m[k] = $signed(wq_in[k]);
        end
        axil.write(configctl_defs::REG_BATCH_LEN, {16'b0, batch[15:0]});
        axil.write(configctl_defs::REG_DELAY_LEN, {20'b0, delay[11:0]});
    endtask

    task automatic ctrl_write(input logic tdd_en, input logic bypass, input logic start);
        axil.write(configctl_defs::REG_CTRL, {29'b0, bypass, tdd_en, start});
    endtask

    task automatic axil_write_strobe(input logic [AXIL_ADDR_W-1:0] addr,
                                     input logic [AXIL_DATA_W-1:0] data,
                                     input logic [STRB_W-1:0] wstrb);
        @(posedge clk);
        axil.wdata   <= data;
        axil.awaddr  <= addr;
        axil.wstrb   <= wstrb;
        axil.awvalid <= 1;
        axil.wvalid  <= 1;
        axil.bready  <= 1;
        fork
            begin while (~axil.awready) @(posedge clk); end
            begin while (~axil.wready)  @(posedge clk); end
        join
        while (~axil.bvalid) @(posedge clk);
        axil.awvalid <= 0;
        axil.wvalid  <= 0;
        axil.awaddr  <= 0;
        axil.wdata   <= 0;
        axil.wstrb   <= 0;
        axil.bready  <= 0;
        @(posedge clk);
    endtask

    // ref_axis driver — sends packed {Q, I}, updates the bit-exact model
    task automatic send_ref(input signed [DATA_WIDTH-1:0] i_val,
                            input signed [DATA_WIDTH-1:0] q_val);
        logic signed [DATA_WIDTH-1:0] y_i, y_q;
        if (bypass_mode) begin
            expected_fb_q.push_back({q_val, i_val});
        end else begin
            filter_ref(i_val, q_val, model_i0, model_q0, wi_m, wq_m, y_i, y_q);
            expected_fb_q.push_back({y_q, y_i});
        end
        sent_ref_q.push_back({q_val, i_val});
        {model_i1, model_q1} <= {model_i0, model_q0};
        {model_i0, model_q0} <= {i_val, q_val};

        ref_axis.tdata  <= {q_val, i_val};
        ref_axis.tvalid <= 1'b1;
        @(posedge clk);
        while (!ref_axis.tready) @(posedge clk);
        ref_axis.tvalid <= 1'b0;
    endtask

    task automatic send_n_samples(input int count);
        for (int k = 0; k < count; k++) begin
            logic [15:0] i, q;
            i = lfsr_next();
            q = lfsr_next() ^ {i[7:0], i[15:8]};
            send_ref($signed(i), $signed(q));
        end
    endtask

    // cap_axis checker: collects n pairs, compares against the model.
    task automatic collect_capture(input int n, input int fb_off, output int mism,
                                   input int stall_after = -1,
                                   input int stall_cycles = 0);
        int got = 0, guard = 0;
        logic [DATA_WIDTH*2-1:0] exp;
        logic [DATA_WIDTH-1:0] ri, rq, fi, fq;
        mism = 0;
        cap_axis.tready = 1'b1;
        while (got < n) begin
            @(posedge clk);
            guard++;
            if (guard > 3000) begin
                $error("    FAIL: timeout waiting for capture (%0d/%0d pairs)", got, n);
                mism = -1;
                fail_cnt++;
                return;
            end
            if (cap_axis.tvalid && cap_axis.tready) begin
                ri = cap_axis.tdata[DATA_WIDTH-1:0];
                rq = cap_axis.tdata[2*DATA_WIDTH-1:DATA_WIDTH];
                fi = cap_axis.tdata[3*DATA_WIDTH-1:2*DATA_WIDTH];
                fq = cap_axis.tdata[4*DATA_WIDTH-1:3*DATA_WIDTH];
                exp = expected_fb_q[fb_off + got];
                if ({fq, fi} !== exp) begin
                    $error("    FAIL: pair %0d fb mismatch: got (%0d,%0d) exp (%0d,%0d)",
                        got, fi, fq, exp[DATA_WIDTH-1:0], exp[2*DATA_WIDTH-1:DATA_WIDTH]);
                    mism++;
                end
                if ({rq, ri} !== sent_ref_q[got]) begin
                    $error("    FAIL: pair %0d ref mismatch: got (%0d,%0d) exp (%0d,%0d)",
                        got, ri, rq, sent_ref_q[got][DATA_WIDTH-1:0],
                        sent_ref_q[got][2*DATA_WIDTH-1:DATA_WIDTH]);
                    mism++;
                end
                if (got == n-1 && !cap_axis.tlast) begin
                    $error("    FAIL: tlast not asserted on final pair");
                    mism++;
                end
                got++;
                if (got == stall_after) begin
                    cap_axis.tready = 1'b0;
                    repeat (stall_cycles) @(posedge clk);
                    cap_axis.tready = 1'b1;
                end
            end
        end
        if (mism == 0) begin
            $display("    PASS: captured %0d pairs, all fb/ref/tlast match", n);
            pass_cnt++;
        end else begin
            $display("    %0d mismatch(es)", mism);
            fail_cnt++;
        end
        cap_axis.tready = 1'b0;
    endtask

    // Test sequence
    logic signed [WEIGHT_W-1:0] wi_t [N_WEIGHTS];
    logic signed [WEIGHT_W-1:0] wq_t [N_WEIGHTS];
    logic [AXIL_DATA_W-1:0] rd;

    initial begin
        int mism;
        rst = 1'b1;
        tdd_sig = 1'b0;
        cap_axis.tready = 1'b0;
        axil.awaddr = 0; axil.awvalid = 0; axil.wdata = 0; axil.wstrb = 0;
        axil.wvalid = 0; axil.bready = 0;
        axil.araddr = 0; axil.arvalid = 0; axil.rready = 0;
        wi_t = '{1229, -614, 410, -307};
        wq_t = '{-1229, 614, -410, 307};
        for (int k = 0; k < N_WEIGHTS; k++) begin
            wi_m[k] = wi_t[k];
            wq_m[k] = wq_t[k];
        end

        #(CLK_PERIOD * 5);
        rst = 1'b0;
        #(CLK_PERIOD * 2);

        $display("=== top_tb: FB_DELAY_CYCLES=%0d BATCH_LEN_MAX=%0d DELAY_LEN_MAX=%0d ===",
            FB_DELAY_CYCLES, BATCH_LEN_MAX, DELAY_LEN_MAX);

        // Test 0: configctl reset defaults
        $display("\n--- Test 0: configctl reset defaults ---");
        begin
            axil.read(configctl_defs::REG_BATCH_LEN, rd);
            check_eq(rd, 32'd1, "reset batch_length == 1");
            axil.read(configctl_defs::REG_DELAY_LEN, rd);
            check_eq(rd, 32'd0, "reset delay_length == 0");
            axil.read(configctl_defs::REG_CTRL, rd);
            check_eq(rd, 32'd0, "reset ctrl == 0");
            axil.read(configctl_defs::REG_WEIGHT_I0, rd);
            check_eq(rd, 32'd0, "reset weight_i0 == 0");
            axil.read(configctl_defs::REG_WEIGHT_Q0, rd);
            check_eq(rd, 32'd0, "reset weight_q0 == 0");
        end

        // Test 1: config read/write round-trip + wstrb
        $display("\n--- Test 1: config read/write round-trip + wstrb ---");
        reset_system();
        begin
            axil.write(configctl_defs::REG_WEIGHT_I0, 32'd1229);
            axil.read(configctl_defs::REG_WEIGHT_I0, rd);
            check_eq(rd, 32'd1229, "weight_i0 roundtrip");
            axil.write(configctl_defs::REG_WEIGHT_Q3, 32'h0000_0D9A); // -614
            axil.read(configctl_defs::REG_WEIGHT_Q3, rd);
            check_eq(rd, 32'h0000_0D9A, "weight_q3 (-614) roundtrip");
            axil.write(configctl_defs::REG_BATCH_LEN, 32'd16);
            axil.read(configctl_defs::REG_BATCH_LEN, rd);
            check_eq(rd, 32'd16, "batch roundtrip");
            axil.write(configctl_defs::REG_DELAY_LEN, 32'd4);
            axil.read(configctl_defs::REG_DELAY_LEN, rd);
            check_eq(rd, 32'd4, "delay roundtrip");
            ctrl_write(1'b1, 1'b1, 1'b0);
            axil.read(configctl_defs::REG_CTRL, rd);
            check_eq(rd, {29'b0, 1'b1, 1'b1, 1'b0}, "ctrl roundtrip (tdd_en+bypass)");

            // partial-wstrb merge on a 12-bit weight (2 byte lanes)
            axil_write_strobe(configctl_defs::REG_WEIGHT_I0, 32'h0000_000A, 4'b0011);
            axil.read(configctl_defs::REG_WEIGHT_I0, rd);
            check_eq(rd, 32'h0000_000A, "weight wstrb byte0");
            axil_write_strobe(configctl_defs::REG_WEIGHT_I0, 32'h0000_0A00, 4'b0010);
            axil.read(configctl_defs::REG_WEIGHT_I0, rd);
            check_eq(rd, 32'h0000_0A0A, "weight wstrb byte1 merge (0xA0A)");

            // wstrb == 0 on ctrl must be a no-op
            axil_write_strobe(configctl_defs::REG_CTRL, {29'b0, 1'b1, 1'b0, 1'b1}, 4'b0000);
            axil.read(configctl_defs::REG_CTRL, rd);
            check_eq(rd, {29'b0, 1'b1, 1'b1, 1'b0}, "ctrl wstrb=0 no-op");

            // strobe on a byte lane beyond the register width: no change
            axil_write_strobe(configctl_defs::REG_BATCH_LEN, 32'h0000_0100, 4'b0010);
            axil.read(configctl_defs::REG_BATCH_LEN, rd);
            check_eq(rd, 32'd16, "batch wstrb beyond width no-op");
        end

        // Test 2: bypass passthrough
        $display("\n--- Test 2: bypass passthrough (fb == ref) ---");
        reset_system();
        cfg_write_all(16, 0, wi_t, wq_t);
        bypass_mode = 1;
        ctrl_write(1'b0, 1'b1, 1'b1); // bypass=1, trigger
        repeat (5) @(posedge clk);
        send_n_samples(16);
        bypass_mode = 0;
        collect_capture(16, 0, mism);

        // Test 3: filter path, delay_length=0 (compensated)
        $display("\n--- Test 3: filter path through %0d-cycle emulated FB delay, delay_length=0 ---",
            FB_DELAY_CYCLES);
        reset_system();
        cfg_write_all(16, 0, wi_t, wq_t);
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger
        repeat (5) @(posedge clk);
        send_n_samples(16);
        collect_capture(16, 0, mism);

        // Test 4: delay_length shift       
        $display("\n--- Test 4: delay_length=4 shifts the fb window ---");
        reset_system();
        cfg_write_all(16, 4, wi_t, wq_t);
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger
        repeat (5) @(posedge clk);
        // The presync's capture_cnt counts both-valid cycles up to delay_length,
        // so ref must keep flowing until fb has arrived (latency) plus the
        // delay window has elapsed. Send extra samples well past the capture.
        send_n_samples(16 + 4 + FILTER_LATENCY + FB_DELAY_CYCLES + 4);
        collect_capture(16, 4, mism);

        // Test 5: multi-batch back to back
        $display("\n--- Test 5: multi-batch capture ---");
        reset_system();
        cfg_write_all(16, 0, wi_t, wq_t);
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger batch 1
        repeat (5) @(posedge clk);
        send_n_samples(16);
        collect_capture(16, 0, mism);
        sent_ref_q.delete();
        expected_fb_q.delete();
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger batch 2
        repeat (5) @(posedge clk);
        send_n_samples(16);
        collect_capture(16, 0, mism);

        // Test 6: cap_axis backpressure
        $display("\n--- Test 6: cap_axis backpressure ---");
        reset_system();
        cfg_write_all(16, 0, wi_t, wq_t);
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger
        repeat (5) @(posedge clk);
        send_n_samples(16);
        collect_capture(16, 0, mism, 6, 10);

        // Test 7: reset mid-capture, then recapture
        $display("\n--- Test 7: reset mid-capture ---");
        reset_system();
        cfg_write_all(16, 0, wi_t, wq_t);
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger
        repeat (5) @(posedge clk);
        send_n_samples(8); // partial batch
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        model_i0 = 0; model_q0 = 0; model_i1 = 0; model_q1 = 0;
        expected_fb_q.delete();
        sent_ref_q.delete();
        repeat (2) @(posedge clk);
        cfg_write_all(16, 0, wi_t, wq_t); // reset cleared config
        ctrl_write(1'b0, 1'b0, 1'b1); // retrigger
        repeat (5) @(posedge clk);
        send_n_samples(16);
        collect_capture(16, 0, mism);

        // Test 8: tddctl windowing
        $display("\n--- Test 8: tdd gating (wait for TX window) ---");
        reset_system();
        cfg_write_all(16, 0, wi_t, wq_t);
        ctrl_write(1'b1, 1'b0, 1'b1); // tdd_en=1, trigger while tdd_tx=0
        repeat (5) @(posedge clk);
        // WaitTdd is the second member of the tddctl state enum (Idle=0, WaitTdd=1)
        if (dut.tdd_controller.state !== 1) begin
            $error("    FAIL: tddctl not in WaitTdd after trigger with tdd_tx=0");
            fail_cnt++;
        end else begin
            $display("    PASS: tddctl holds trigger in WaitTdd");
            pass_cnt++;
        end
        // send pre-window samples; they must be rejected (no capture output)
        send_n_samples(4);
        begin
            automatic int rejects = 0;
            repeat (FILTER_LATENCY + FB_DELAY_CYCLES + 4) begin
                @(posedge clk);
                if (cap_axis.tvalid) rejects++;
            end
            if (rejects != 0) begin
                $error("    FAIL: capture output appeared while gated (%0d beats)", rejects);
                fail_cnt++;
            end else begin
                $display("    PASS: no capture output while tdd_tx=0");
                pass_cnt++;
            end
        end
        // let the pre-window residue drain fully so the fb stream is clean
        repeat (FILTER_LATENCY + FB_DELAY_CYCLES + 4) @(posedge clk);
        tdd_sig = 1'b1; // open the TX window
        repeat (FILTER_LATENCY + 4) @(posedge clk);
        sent_ref_q.delete();
        expected_fb_q.delete();
        // model delay line still carries the last pre-window sample, matching
        // the filter's own delay line
        send_n_samples(16);
        collect_capture(16, 0, mism);
        tdd_sig = 1'b0;

        // Test 9: single-element batch
        $display("\n--- Test 9: single-element batch ---");
        reset_system();
        cfg_write_all(1, 0, wi_t, wq_t);
        ctrl_write(1'b0, 1'b0, 1'b1); // trigger
        repeat (5) @(posedge clk);
        send_n_samples(1);
        collect_capture(1, 0, mism);

        $display("\n=== Summary: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("Testbench Result: OK");
        else               $display("Testbench Result: FAILED");
        $display("--- End of Simulation ---");
        $finish;
    end

endmodule
