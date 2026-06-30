`timescale 1ns/1ps

module sampler_tb();
    parameter integer DATA_WIDTH = 14;
    parameter reg [11:0] DELAY      = 7;
    parameter integer FIFO_DEPTH = 16;
    parameter reg [11:0] BATCH_LEN  = 3;
    parameter integer CLK_PERIOD = 10;
    
    logic tb_result = 1;
    integer tb_sample_count = 0;
    integer tb_batch_count = 0;
    
    reg clk;
    reg rst;
    reg we;
    reg start;
    
    axis_if #(.DATA_WIDTH(DATA_WIDTH))   ref_axis();
    axis_if #(.DATA_WIDTH(DATA_WIDTH))   fb_axis ();
    axis_if #(.DATA_WIDTH(DATA_WIDTH*2)) cap_axis();

    wire [DATA_WIDTH-1:0] ref_capture;
    wire [DATA_WIDTH-1:0] fb_capture;
    
    sampler #(
    	.DATA_WIDTH(DATA_WIDTH),
    	.FIFO_DEPTH(FIFO_DEPTH)
     ) sampler (
    	.clk(clk), .rst(rst), .we(we), .start(start),
        .delay_length(DELAY), .batch_length(BATCH_LEN),
    	.ref_axis(ref_axis),
    	.fb_axis (fb_axis),
        .cap_axis(cap_axis)
    );

    assign ref_capture = cap_axis.tdata[DATA_WIDTH-1:0];
    assign fb_capture = cap_axis.tdata[(DATA_WIDTH*2)-1:DATA_WIDTH];
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        start = 0;
        we = 1;
        rst = 1;
        ref_axis.init();
        fb_axis.init();
        cap_axis.init();
        
        #(CLK_PERIOD * 5);
        rst = 0;
        #(CLK_PERIOD * 2);
        
        $display("--- Starting Simulation ---");
        $display("Sending values: 500, 200, 300");
        $display("The \"filter\" should output value * 2: 1000, 400, 600");

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        fork
            begin
                ref_axis.send(clk, 500);
                ref_axis.send(clk, 200);
                ref_axis.send(clk, 300);
                ref_axis.send(clk, 45);
            end
            begin
                fb_axis.send(clk, 10);
                fb_axis.send(clk, 20);
                fb_axis.send(clk, 30);
                fb_axis.send(clk, 40);
                fb_axis.send(clk, 50);
                fb_axis.send(clk, 60);
                fb_axis.send(clk, 70);

                // Actual filtered values
                fb_axis.send(clk, 1000);
                fb_axis.send(clk, 400);
                fb_axis.send(clk, 600);
                fb_axis.send(clk, 90);
            end
        join
        
        repeat (10) @(posedge clk);

        tb_result &= tb_batch_count == 1;
        
        if (tb_result) $display("Testbench Result: OK");
        else           $display("Testbench Result: FAILED");
        $display("--- End of Simulation ---");
        $stop;
    end

    always @(posedge cap_axis.tlast) begin
        tb_result &= tb_sample_count == 3;
        tb_batch_count += 1;
    end
    always @(posedge clk) begin
        if (cap_axis.tvalid) begin
            $display("Capture Ready: expected{%4d, %0d}, got{%4d, %0d}: %s",
                28'(ref_capture * 2), ref_capture,
                fb_capture, ref_capture,
                (ref_capture * 2) == fb_capture ? "OK" : "FAILED"
            );

            tb_result &= (ref_capture * 2) == fb_capture;
            tb_sample_count += 1;
        end
    end

    initial begin
        $dumpfile("sim/waveforms/dpd/sampler.vcd");
        $dumpvars(0, sampler_tb);
    end

endmodule
