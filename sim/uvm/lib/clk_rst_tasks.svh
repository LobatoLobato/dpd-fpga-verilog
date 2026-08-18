`ifndef CLK_RST_TASKS_SVH
`define CLK_RST_TASKS_SVH

    // Free-running clock; clk_pol selects the idle level.
    task automatic generate_clock(
        input   real    freq    = 100_000_000.0,
        input   bit     clk_pol = 0,
        input   real    delay   = 0.0
    );
        clk = ~clk_pol;
        #(delay);
        forever begin
            clk = ~clk;
            #(1.0 / (2.0 * freq) * 1e9);
        end
    endtask : generate_clock

    // Active-high reset pulse (rst_pol selects the polarity).
    task automatic reset_pulse(
        input   bit     rst_pol     = 1,
        input   int     rst_width   = 4,
        input   string  rst_type    = "Sync",
        input   bit     rst_edge    = 1
    );
        if (rst_type == "Sync") begin
            if (rst_edge)
                @(posedge clk);
            else
                @(negedge clk);
        end
        rst = rst_pol;

        if (rst_type == "Async") begin
            #(rst_width);
        end else begin
            repeat (rst_width) begin
                if (rst_edge)
                @(posedge clk);
                else
                @(negedge clk);
            end
        end
        rst = ~rst_pol;
    endtask : reset_pulse

`endif // CLK_RST_TASKS_SVH
