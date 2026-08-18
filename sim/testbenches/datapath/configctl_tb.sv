`timescale 1ns/1ps

`define TESTBENCH 1
module configctl_tb();
    parameter integer CLK_PERIOD = 10;
    parameter integer AXIL_DATA_W = 32;
    parameter integer AXIL_ADDR_W = configctl_defs::ADDR_W;
    parameter integer BATCH_LEN_MAX = 512;
    parameter integer DELAY_LEN_MAX = 16;
    parameter integer WEIGHT_W = 12;
    localparam integer BATCH_LEN_WIDTH = $clog2(BATCH_LEN_MAX + 1);
    localparam integer DELAY_LEN_WIDTH = $clog2(DELAY_LEN_MAX);

    reg clk, rst;
    wire start, tdd_en, bypass;
    wire [BATCH_LEN_WIDTH-1:0] batch_length;
    wire [DELAY_LEN_WIDTH-1:0] delay_length;
    wire [WEIGHT_W-1:0] weights_i [4];
    wire [WEIGHT_W-1:0] weights_q [4];

    taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)) axil(.tb_clk(clk));

    configctl #(
        .DATA_W        (AXIL_DATA_W),
        .WEIGHT_W      (WEIGHT_W),
        .BATCH_LEN_MAX (BATCH_LEN_MAX),
        .DELAY_LEN_MAX (DELAY_LEN_MAX)
     ) configctl (
        .clk          (clk),
        .rst          (rst),
        .axil_wr      (axil),
        .axil_rd      (axil),
        .start        (start),
        .tdd_en       (tdd_en),
        .batch_length (batch_length),
        .delay_length (delay_length),
        .weights_i    (weights_i),
        .weights_q    (weights_q),
        .bypass       (bypass)
    );

    function automatic logic [AXIL_DATA_W-1:0] read_output(configctl_defs::reg_addr_t addr);
        case (addr)
        configctl_defs::REG_CTRL:      return {29'b0, bypass, tdd_en, start};
        configctl_defs::REG_BATCH_LEN: return {{(AXIL_DATA_W - BATCH_LEN_WIDTH){1'b0}}, batch_length};
        configctl_defs::REG_DELAY_LEN: return {{(AXIL_DATA_W - DELAY_LEN_WIDTH){1'b0}}, delay_length};
        configctl_defs::REG_WEIGHT_I0: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_i[0]};
        configctl_defs::REG_WEIGHT_I1: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_i[1]};
        configctl_defs::REG_WEIGHT_I2: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_i[2]};
        configctl_defs::REG_WEIGHT_I3: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_i[3]};
        configctl_defs::REG_WEIGHT_Q0: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_q[0]};
        configctl_defs::REG_WEIGHT_Q1: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_q[1]};
        configctl_defs::REG_WEIGHT_Q2: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_q[2]};
        configctl_defs::REG_WEIGHT_Q3: return {{(AXIL_DATA_W - WEIGHT_W){1'b0}}, weights_q[3]};
        default: return '0;
        endcase
    endfunction

    task automatic test_reg_wr(configctl_defs::reg_addr_t addr, input reg [AXIL_DATA_W-1:0] wdata);
        reg [AXIL_DATA_W-1:0] odata;
        begin
            axil.write(addr, wdata);
            odata = read_output(addr);

            assert(odata == wdata) else $fatal(1, "Register value differs from write data [%s] exp: %b, got: %b", addr.name(), wdata, odata);
            $display("Write to %s: OK", addr.name());
        end
    endtask

    task automatic test_reg_rd(configctl_defs::reg_addr_t addr, input reg [AXIL_DATA_W-1:0] edata);
        reg [AXIL_DATA_W-1:0] rdata;
        begin
            axil.read(addr, rdata);

            assert(rdata == edata) else $fatal(1, "Read value differs from expected data [%s] exp: %b, got: %b", addr.name(), edata, rdata);
            $display("Read  to %s: OK", addr.name());
        end

    endtask

    task automatic test_reg_all(configctl_defs::reg_addr_t addr, input reg [AXIL_DATA_W-1:0] wdata);
        test_reg_wr(addr, wdata);
        test_reg_rd(addr, wdata);
    endtask

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        @(posedge clk); rst = 0;
        @(posedge clk); rst = 1;
        @(posedge clk); rst = 0;

        $display("Starting simulation");
        $display("Testing register read/write over AXI4-Lite");
        // CTRL: writes start: 1, tdd_en: 1, bypass: 0
        //       reads  start: 0, tdd_en: 1, bypass: 0
        test_reg_wr(configctl_defs::REG_CTRL, 32'({1'b0, 1'b1, 1'b1}));
        test_reg_rd(configctl_defs::REG_CTRL, 32'({1'b0, 1'b1, 1'b0}));

        test_reg_all(configctl_defs::REG_BATCH_LEN, {BATCH_LEN_WIDTH{1'b1}});
        test_reg_all(configctl_defs::REG_DELAY_LEN, {DELAY_LEN_WIDTH{1'b1}});

        test_reg_all(configctl_defs::REG_WEIGHT_I0, 32'd1);
        test_reg_all(configctl_defs::REG_WEIGHT_I1, 32'd2);
        test_reg_all(configctl_defs::REG_WEIGHT_I2, 32'd3);
        test_reg_all(configctl_defs::REG_WEIGHT_I3, 32'd4);
        test_reg_all(configctl_defs::REG_WEIGHT_Q0, 32'd1);
        test_reg_all(configctl_defs::REG_WEIGHT_Q1, 32'd2);
        test_reg_all(configctl_defs::REG_WEIGHT_Q2, 32'd3);
        test_reg_all(configctl_defs::REG_WEIGHT_Q3, 32'd4);

        $display("Testbench Result: OK");
        $display("Simulation done");
        $finish;
    end

    initial begin
        $dumpfile("sim/waveforms/datapath/configctl.vcd");
        $dumpvars(0, configctl_tb);
    end

endmodule
