`timescale 1ns/1ps

module filter_tb();
    parameter integer DATA_WIDTH = 16;
    parameter integer CLK_PERIOD = 10;

    localparam integer SAMPLE_FRAC = 12;
    localparam integer WEIGHT_FRAC = 10;

    logic tb_result = 1;
    integer tb_sent = 0;
    integer tb_checked = 0;

    reg signed [11:0] wiA [4], wqA [4];   // asymmetric complex weights
    reg signed [11:0] wi_hi [4], wq_hi [4]; // full-scale positive (saturation)
    reg signed [11:0] wi_lo [4], wq_lo [4]; // full-scale negative (saturation)
    reg signed [11:0] wi_bp [4], wq_bp [4]; // backpressure-test weights

    reg clk, rst;
    reg signed [11:0] wi [4];
    reg signed [11:0] wq [4];
    reg bypass;

    taxi_axis_if #(.DATA_W(DATA_WIDTH * 2)) input_axis();
    taxi_axis_if #(.DATA_W(DATA_WIDTH * 2)) output_axis();

    filter #(
        .DATA_WIDTH(DATA_WIDTH)
    ) filter (
        .clk(clk), .rst(rst),
        .weights_i(wi), .weights_q(wq), .bypass(bypass),
        .input_axis (input_axis),
        .output_axis(output_axis)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    `include "../../uvm/lib/filter_model.svh"

    // Bit-exact complex model, reusing the same filter_ref() as the UVM
    // scoreboard: result is packed {y_q, y_i}; bypass passes {q0, i0} through.
    function automatic logic [DATA_WIDTH * 2 - 1:0] model(
        input logic signed [DATA_WIDTH - 1:0] i0, q0, i1, q1,
        input logic signed [11:0] mi [4], mq [4],
        input logic byp
    );
        logic signed [DATA_WIDTH - 1:0] y_i, y_q;
        begin
            if (byp) begin
                model = {q0, i0};
            end else begin
                filter_ref(i0, q0, i1, q1, mi, mq, y_i, y_q);
                model = {y_q, y_i};
            end
        end
    endfunction

    function automatic signed [11:0] to_q11(input real val);
        to_q11 = signed'(int'($floor(val * (2.0 ** WEIGHT_FRAC) + 0.5)));
    endfunction

    function automatic signed [DATA_WIDTH - 1:0] to_qs(input real val);
        to_qs = signed'(int'($floor(val * (2.0 ** SAMPLE_FRAC) + 0.5)));
    endfunction

    reg [DATA_WIDTH * 2 - 1:0] expected_q [$];
    reg signed [DATA_WIDTH - 1:0] prev_i = 0;
    reg signed [DATA_WIDTH - 1:0] prev_q = 0;

    reg [DATA_WIDTH * 2 - 1:0] exp_val;
    always @(posedge clk) begin
        if (!rst && output_axis.tvalid && output_axis.tready) begin
            exp_val = expected_q.pop_front();
            tb_checked += 1;
            if (exp_val !== output_axis.tdata) begin
                tb_result = 0;
                $display("MISMATCH #%0d: exp={%0d,%0d} got={%0d,%0d}",
                    tb_checked, $signed(exp_val[31:16]), $signed(exp_val[15:0]),
                    $signed(output_axis.tdata[31:16]), $signed(output_axis.tdata[15:0]));
            end
        end
    end

    task automatic send_val(input logic signed [DATA_WIDTH - 1:0] i,
                            input logic signed [DATA_WIDTH - 1:0] q,
                            input logic b,
                            input logic signed [11:0] mi [4],
                            input logic signed [11:0] mq [4]);
        begin
            expected_q.push_back(model(i, q, prev_i, prev_q, mi, mq, b));
            prev_i = i;
            prev_q = q;
            tb_sent += 1;

            bypass <= b;
            foreach (wi[k]) wi[k] <= mi[k];
            foreach (wq[k]) wq[k] <= mq[k];
            input_axis.tdata  <= {q, i};
            input_axis.tvalid <= 1'b1;
            @(posedge clk);
            while (!input_axis.tready) @(posedge clk);
            input_axis.tvalid <= 1'b0;
        end
    endtask

    initial begin
        rst = 1;
        bypass = 0;
        foreach (wi[k]) wi[k] = 0;
        foreach (wq[k]) wq[k] = 0;
        output_axis.tready = 1;

        wiA  = '{to_q11(0.60), to_q11(-0.30), to_q11(0.20), to_q11(-0.15)};
        wqA  = '{to_q11(0.25), to_q11(0.10), to_q11(-0.40), to_q11(0.35)};
        wi_hi = '{12'sh7FF, 12'sh7FF, 12'sh7FF, 12'sh7FF};
        wq_hi = '{12'sh7FF, 12'sh7FF, 12'sh7FF, 12'sh7FF};
        wi_lo = '{12'sh800, 12'sh800, 12'sh800, 12'sh800};
        wq_lo = '{12'sh800, 12'sh800, 12'sh800, 12'sh800};
        wi_bp = '{to_q11(0.40), to_q11(0.10), to_q11(-0.20), to_q11(0.05)};
        wq_bp = '{to_q11(0.30), to_q11(-0.10), to_q11(0.15), to_q11(-0.35)};

        #(CLK_PERIOD * 5);
        rst = 0;
        #(CLK_PERIOD * 2);

        $display("--- Starting Simulation ---");

        // Basic sweep: asymmetric complex weights exercise the full complex multiply (I path mixes in Q, and vice versa)
        send_val(to_qs(0.00),  to_qs(0.00),  1'b0,
            wiA,
            wqA);
        send_val(to_qs(0.50),  to_qs(0.30),  1'b0,
            wiA,
            wqA);
        send_val(to_qs(-0.50), to_qs(-0.20), 1'b0,
            wiA,
            wqA);
        send_val(to_qs(0.90),  to_qs(-0.40), 1'b0,
            wiA,
            wqA);
        send_val(to_qs(-0.90), to_qs(0.80),  1'b0,
            wiA,
            wqA);
        send_val(to_qs(0.10),  to_qs(0.10),  1'b0,
            wiA,
            wqA);
        send_val(to_qs(-0.10), to_qs(-0.10), 1'b0,
            wiA,
            wqA);
        send_val(to_qs(0.25),  to_qs(-0.60), 1'b0,
            wiA,
            wqA);
        send_val(to_qs(-0.25), to_qs(0.60),  1'b0,
            wiA,
            wqA);
        send_val(to_qs(0.75),  to_qs(0.75),  1'b0,
            wiA,
            wqA);
        send_val(to_qs(-0.75), to_qs(-0.75), 1'b0,
            wiA,
            wqA);

        // bypass: output must equal input unmodified
        send_val(to_qs(0.42),  to_qs(-0.42), 1'b1,
            wiA,
            wqA);
        send_val(to_qs(-0.42), to_qs(0.42),  1'b1,
            wiA,
            wqA);

        // saturation stress: extreme weights + near full-scale samples
        send_val(to_qs(0.999), to_qs(0.999), 1'b0,
            wi_hi,
            wq_hi);
        send_val(-(1 <<< (DATA_WIDTH - 1)), -(1 <<< (DATA_WIDTH - 1)), 1'b0,
            wi_hi,
            wq_hi);

        send_val(to_qs(0.999), to_qs(-0.999), 1'b0,
            wi_lo,
            wq_lo);
        send_val(-(1 <<< (DATA_WIDTH - 1)), (1 <<< (DATA_WIDTH - 1)) - 1, 1'b0,
            wi_lo,
            wq_lo);

        // backpressure: hold output_axis.tready low mid-burst
        output_axis.tready <= 0;
        fork
            begin
                send_val(to_qs(0.30),  to_qs(-0.30), 1'b0,
                    wi_bp,
                    wq_bp);
                send_val(to_qs(-0.30), to_qs(0.30), 1'b0,
                    wi_bp,
                    wq_bp);
                send_val(to_qs(0.60),  to_qs(0.20), 1'b0,
                    wi_bp,
                    wq_bp);
                send_val(to_qs(-0.60), to_qs(-0.20), 1'b0,
                    wi_bp,
                    wq_bp);
            end
            begin
                #(CLK_PERIOD * 20);
                output_axis.tready <= 1;
            end
        join

        repeat (20) @(posedge clk);

        tb_result &= (tb_checked == tb_sent);
        tb_result &= (expected_q.size() == 0);

        if (tb_result) $display("Testbench Result: OK (%0d/%0d samples checked)", tb_checked, tb_sent);
        else            $display("Testbench Result: FAILED (%0d/%0d samples checked)", tb_checked, tb_sent);
        $display("--- End of Simulation ---");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveforms/dpd/filter.vcd");
        $dumpvars(0, filter_tb);
    end

endmodule
