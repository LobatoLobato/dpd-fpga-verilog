`timescale 1ns/1ps

module top_integration_tb();
    parameter integer DATA_WIDTH = 16;
    parameter integer PACKED_IQ_DATA_WIDTH = DATA_WIDTH * 2;
    parameter integer BATCH_LEN_MAX  = 20000;
    parameter integer AXIL_DATA_W = 32;
    parameter integer AXIL_ADDR_W = configctl_defs::ADDR_W;
    parameter integer CLK_PERIOD  = 10;

    localparam integer SAMPLE_FRAC    = 12;
    localparam integer WEIGHT_WIDTH   = 12;
    localparam integer WEIGHT_FRAC    = 10;
    localparam integer GUARD_BITS     = 4;
    localparam integer ACC_WIDTH      = DATA_WIDTH + GUARD_BITS;
    localparam integer FILTER_LATENCY = 4;
    localparam integer N_WEIGHTS      = 4;

    string stimulus_file   = "results/reports/ref_stimulus.txt";
    string weights_i_file  = "results/reports/weights_i.txt";
    string weights_q_file  = "results/reports/weights_q.txt";
    string output_file     = "results/reports/cap_export.csv";

    reg clk, rst, tdd_sig;

    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) ref_axis();
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH)) predistorted_axis();
    taxi_axis_if #(.DATA_W(PACKED_IQ_DATA_WIDTH*2)) cap_axis();
    taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)) axil(.tb_clk(clk));

    top #(
        .DATA_WIDTH (DATA_WIDTH),
        .BATCH_LEN_MAX(BATCH_LEN_MAX),
        .AXIL_DATA_W(AXIL_DATA_W),
        .AXIL_ADDR_W(AXIL_ADDR_W)
    ) dut (
        .clk(clk), .rst(rst), .tdd_sig(tdd_sig),
        .ref_axis(ref_axis),
        .fb_axis(predistorted_axis),
        .predistorted_axis(predistorted_axis),
        .cap_axis(cap_axis),
        .axil(axil)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Saturate signed value `v` to `w` bits (w <= 31)
    function automatic logic [31:0] sat(input int w, input longint v);
        longint maxv = (1 << (w-1)) - 1;
        longint minv = -(1 << (w-1));
        logic [31:0] mask;
        begin
            mask = (1 << w) - 1;
            if (v > maxv)      sat = maxv;
            else if (v < minv) sat = minv;
            else               sat = v & mask;
        end
    endfunction

    // Complex MP model of filter.sv: y = sum_t (wi[t]*oi[t] -/+ wq[t]*oq[t]).
    // Tap t operands: t=0,1 are the current/previous samples (order 1);
    // t=2,3 are the re-quantised |x|^2*x terms (order 3). Returns {y_q, y_i}.
    function automatic logic [DATA_WIDTH*2-1:0] model_complex(
        input signed [DATA_WIDTH-1:0] i0, q0, i1, q1,
        input signed [WEIGHT_WIDTH-1:0] wi [N_WEIGHTS],
        input signed [WEIGHT_WIDTH-1:0] wq [N_WEIGHTS]
    );
        reg signed [DATA_WIDTH-1:0] m2_0, m2_1;
        reg signed [DATA_WIDTH-1:0] oi [N_WEIGHTS], oq [N_WEIGHTS];
        reg signed [ACC_WIDTH-1:0] acc_i, acc_q;
        reg signed [DATA_WIDTH-1:0] y_i, y_q;
        begin
            m2_0 = sat(DATA_WIDTH, i0*i0 >>> SAMPLE_FRAC) + sat(DATA_WIDTH, q0*q0 >>> SAMPLE_FRAC);
            m2_1 = sat(DATA_WIDTH, i1*i1 >>> SAMPLE_FRAC) + sat(DATA_WIDTH, q1*q1 >>> SAMPLE_FRAC);

            oi[0] = i0; oq[0] = q0;
            oi[1] = i1; oq[1] = q1;
            oi[2] = sat(DATA_WIDTH, i0 * m2_0 >>> SAMPLE_FRAC);
            oq[2] = sat(DATA_WIDTH, q0 * m2_0 >>> SAMPLE_FRAC);
            oi[3] = sat(DATA_WIDTH, i1 * m2_1 >>> SAMPLE_FRAC);
            oq[3] = sat(DATA_WIDTH, q1 * m2_1 >>> SAMPLE_FRAC);

            acc_i = 0; acc_q = 0;
            for (int t = 0; t < N_WEIGHTS; t++) begin
                acc_i = acc_i + sat(ACC_WIDTH, wi[t]*oi[t] >>> WEIGHT_FRAC)
                              - sat(ACC_WIDTH, wq[t]*oq[t] >>> WEIGHT_FRAC);
                acc_q = acc_q + sat(ACC_WIDTH, wi[t]*oq[t] >>> WEIGHT_FRAC)
                              + sat(ACC_WIDTH, wq[t]*oi[t] >>> WEIGHT_FRAC);
            end
            y_i = sat(DATA_WIDTH, acc_i);
            y_q = sat(DATA_WIDTH, acc_q);
            model_complex = {y_q, y_i};
        end
    endfunction

    // File-driven stimulus / weights
    logic signed [DATA_WIDTH-1:0] stim_i_q [$];
    logic signed [DATA_WIDTH-1:0] stim_q_q [$];
    logic signed [WEIGHT_WIDTH-1:0] wi [N_WEIGHTS], wq [N_WEIGHTS];
    int num_samples;

    task automatic load_inputs();
        integer fd, code_i, code_q, code_w, rc;
        begin
            rc = $value$plusargs("stimulus=%s", stimulus_file);
            rc = $value$plusargs("weights_i=%s", weights_i_file);
            rc = $value$plusargs("weights_q=%s", weights_q_file);
            rc = $value$plusargs("output=%s", output_file);

            fd = $fopen(stimulus_file, "r");
            if (fd == 0) $fatal(1, "Could not open stimulus file: %s", stimulus_file);
            while ($fscanf(fd, "%d %d", code_i, code_q) == 2) begin
                stim_i_q.push_back(code_i[DATA_WIDTH-1:0]);
                stim_q_q.push_back(code_q[DATA_WIDTH-1:0]);
            end
            $fclose(fd);
            num_samples = stim_i_q.size();
            if (num_samples == 0)
                $fatal(1, "Stimulus file %s has no samples", stimulus_file);
            if (num_samples > 65535)
                $fatal(1, "%0d samples exceeds batch_length's 16-bit range (max 65535)", num_samples);

            fd = $fopen(weights_i_file, "r");
            if (fd == 0) $fatal(1, "Could not open I weights file: %s", weights_i_file);
            for (int i = 0; i < N_WEIGHTS; i++) begin
                if ($fscanf(fd, "%d", code_w) != 1)
                    $fatal(1, "I weights file: missing w%0d", i);
                wi[i] = code_w[WEIGHT_WIDTH-1:0];
            end
            $fclose(fd);

            fd = $fopen(weights_q_file, "r");
            if (fd == 0) $fatal(1, "Could not open Q weights file: %s", weights_q_file);
            for (int i = 0; i < N_WEIGHTS; i++) begin
                if ($fscanf(fd, "%d", code_w) != 1)
                    $fatal(1, "Q weights file: missing w%0d", i);
                wq[i] = code_w[WEIGHT_WIDTH-1:0];
            end
            $fclose(fd);

            $display("Loaded %0d stimulus samples from %s", num_samples, stimulus_file);
            $display("Loaded I weights: w0=%0d w1=%0d w2=%0d w3=%0d", wi[0], wi[1], wi[2], wi[3]);
            $display("Loaded Q weights: w0=%0d w1=%0d w2=%0d w3=%0d", wq[0], wq[1], wq[2], wq[3]);
        end
    endtask : load_inputs

    // ref_axis driver — sends packed {Q, I}, tracks model delay line
    logic signed [DATA_WIDTH-1:0] model_i0 = 0, model_q0 = 0;
    logic signed [DATA_WIDTH-1:0] model_i1 = 0, model_q1 = 0;
    // Expected queue: each entry is {fb_q, fb_i}
    logic [DATA_WIDTH*2-1:0] expected_fb_q [$];

    task automatic send_ref(input signed [DATA_WIDTH-1:0] i_val, input signed [DATA_WIDTH-1:0] q_val);
        begin
            expected_fb_q.push_back(model_complex(i_val, q_val, model_i0, model_q0, wi, wq));
            {model_i1, model_q1} <= {model_i0, model_q0};
            {model_i0, model_q0} <= {i_val, q_val};

            ref_axis.tdata  <= {q_val, i_val};
            ref_axis.tvalid <= 1'b1;
            @(posedge clk);
            while (!ref_axis.tready) @(posedge clk);
            ref_axis.tvalid <= 1'b0;
        end
    endtask : send_ref

    // cap_axis -> CSV (4 columns: ref_i, ref_q, fb_i, fb_q)
    integer ofd;
    int pairs_captured = 0;
    int mismatches = 0;
    wire signed [DATA_WIDTH-1:0] cap_ref_i = cap_axis.tdata[DATA_WIDTH-1:0];
    wire signed [DATA_WIDTH-1:0] cap_ref_q = cap_axis.tdata[DATA_WIDTH*2-1:DATA_WIDTH];
    wire signed [DATA_WIDTH-1:0] cap_fb_i  = cap_axis.tdata[DATA_WIDTH*3-1:DATA_WIDTH*2];
    wire signed [DATA_WIDTH-1:0] cap_fb_q  = cap_axis.tdata[DATA_WIDTH*4-1:DATA_WIDTH*3];
    logic [DATA_WIDTH*2-1:0] exp_complex;

    always @(posedge clk) begin
        if (!rst && cap_axis.tvalid) begin
            $fwrite(ofd, "%0d,%0d,%0d,%0d\n", cap_ref_i, cap_ref_q, cap_fb_i, cap_fb_q);
            pairs_captured++;
            exp_complex = expected_fb_q.pop_front();
            if (exp_complex !== {cap_fb_q, cap_fb_i}) begin
                mismatches++;
                $display("INTERNAL CHECK MISMATCH pair #%0d: expected fb_i=%0d got=%0d expected fb_q=%0d got=%0d",
                    pairs_captured,
                    exp_complex[DATA_WIDTH-1:0],        cap_fb_i,
                    exp_complex[DATA_WIDTH*2-1:DATA_WIDTH], cap_fb_q);
            end
        end
    end

    initial begin
        int i;
        rst = 1;
        tdd_sig = 0;
        cap_axis.tready = 1'b1;
        axil.awaddr = 0; axil.awvalid = 0; axil.wdata = 0; axil.wstrb = 0; axil.wvalid = 0; axil.bready = 0;
        axil.araddr = 0; axil.arvalid = 0; axil.rready = 0;

        load_inputs();
        ofd = $fopen(output_file, "w");
        if (ofd == 0) $fatal(1, "Could not open output file: %s", output_file);

        #(CLK_PERIOD * 5);
        rst = 0;
        #(CLK_PERIOD * 2);

        $display("--- Starting export run: %0d samples ---", num_samples);

        for (i = 0; i < N_WEIGHTS; i++) begin
            axil.write(configctl_defs::reg_addr_t'(int'(configctl_defs::REG_WEIGHT_I0) + i), {20'b0, wi[i]});
            axil.write(configctl_defs::reg_addr_t'(int'(configctl_defs::REG_WEIGHT_Q0) + i), {20'b0, wq[i]});
        end
        axil.write(configctl_defs::REG_BATCH_LEN, {16'b0, num_samples[15:0]});
        axil.write(configctl_defs::REG_DELAY_LEN, {20'b0, FILTER_LATENCY[11:0]});
        axil.write(configctl_defs::REG_CTRL, {29'b0, 1'b0, 1'b0, 1'b1});

        repeat (20) @(posedge clk);

        for (i = 0; i < num_samples; i++) begin
            send_ref(stim_i_q[i], stim_q_q[i]);
        end

        repeat (FILTER_LATENCY + 20) @(posedge clk);

        $fclose(ofd);

        $display("--- Export finished ---");
        $display("Samples sent      : %0d", num_samples);
        $display("Pairs captured    : %0d", pairs_captured);
        $display("Internal mismatches: %0d", mismatches);
        if (pairs_captured != num_samples)
            $display("WARNING: captured count != sent count -- check FIFO_DEPTH/batch_length/timing.");
        $display("Output written to : %s", output_file);
        $finish;
    end

endmodule
