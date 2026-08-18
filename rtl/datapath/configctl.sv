`resetall
`timescale 1ns / 1ps
`default_nettype none

package configctl_defs;
    localparam int ADDR_W = 4;

    typedef enum logic [ADDR_W - 1:0] {
        REG_CTRL      = 'h0,
        REG_BATCH_LEN = 'h1,
        REG_DELAY_LEN = 'h2,
        REG_WEIGHT_I0 = 'h3,
        REG_WEIGHT_I1 = 'h4,
        REG_WEIGHT_I2 = 'h5,
        REG_WEIGHT_I3 = 'h6,
        REG_WEIGHT_Q0 = 'h7,
        REG_WEIGHT_Q1 = 'h8,
        REG_WEIGHT_Q2 = 'h9,
        REG_WEIGHT_Q3 = 'hA
    } reg_addr_t;
endpackage

module configctl
    import configctl_defs::*;
#(
    parameter integer DATA_W = 32,
    parameter integer BATCH_LEN_MAX = 512,
    parameter integer DELAY_LEN_MAX = 16,
    parameter integer WEIGHT_W      = 12,

    localparam integer BATCH_LEN_WIDTH = $clog2(BATCH_LEN_MAX + 1),
    localparam integer DELAY_LEN_WIDTH = $clog2(DELAY_LEN_MAX),
    localparam integer STRB_W          = DATA_W / 8,
    localparam integer BATCH_LEN_BYTES = (BATCH_LEN_WIDTH + 7) / 8,
    localparam integer DELAY_LEN_BYTES = (DELAY_LEN_WIDTH + 7) / 8,
    localparam integer WEIGHT_BYTES    = (WEIGHT_W + 7) / 8
)(
    input wire clk,
    input wire rst,

    taxi_axil_if.wr_slv axil_wr,
    taxi_axil_if.rd_slv axil_rd,

    output wire        start,
    output reg         tdd_en,
    output reg  [BATCH_LEN_WIDTH - 1:0] batch_length,
    output reg  [DELAY_LEN_WIDTH - 1:0] delay_length,

    output reg  [WEIGHT_W - 1:0] weights_i [4],
    output reg  [WEIGHT_W - 1:0] weights_q [4],
    output reg         bypass
);
    reg start_reg;
    reg bvalid_reg;

    function automatic logic [BATCH_LEN_WIDTH-1:0] merge_batch(
        input logic [BATCH_LEN_WIDTH-1:0] cur,
        input logic [DATA_W-1:0] wdata,
        input logic [STRB_W-1:0] wstrb
    );
        logic [DATA_W-1:0] wide;
        wide = cur;
        for (int b = 0; b < BATCH_LEN_BYTES; b++)
            if (wstrb[b])
                wide[b*8 +: 8] = wdata[b*8 +: 8];
        merge_batch = wide;
    endfunction

    function automatic logic [DELAY_LEN_WIDTH-1:0] merge_delay(
        input logic [DELAY_LEN_WIDTH-1:0] cur,
        input logic [DATA_W-1:0] wdata,
        input logic [STRB_W-1:0] wstrb
    );
        logic [DATA_W-1:0] wide;
        wide = cur;
        for (int b = 0; b < DELAY_LEN_BYTES; b++)
            if (wstrb[b])
                wide[b*8 +: 8] = wdata[b*8 +: 8];
        merge_delay = wide;
    endfunction

    function automatic logic [WEIGHT_W-1:0] merge_weight(
        input logic [WEIGHT_W-1:0] cur,
        input logic [DATA_W-1:0] wdata,
        input logic [STRB_W-1:0] wstrb
    );
        logic [DATA_W-1:0] wide;
        wide = cur;
        for (int b = 0; b < WEIGHT_BYTES; b++)
            if (wstrb[b])
                wide[b*8 +: 8] = wdata[b*8 +: 8];
        merge_weight = wide;
    endfunction

    assign start = start_reg;

    assign axil_wr.awready = ~bvalid_reg;
    assign axil_wr.wready  = ~bvalid_reg;
    assign axil_wr.bvalid  = bvalid_reg;
    assign axil_wr.bresp   = 2'b00;

    always @(posedge clk) begin
        start_reg <= 1'b0;

        if (rst) begin
            bvalid_reg   <= 1'b0;
            tdd_en       <= 1'b0;
            bypass       <= 1'b0;
            batch_length <= BATCH_LEN_WIDTH'(1);
            delay_length <= '0;
            for (int k = 0; k < 4; k++) begin
                weights_i[k] <= '0;
                weights_q[k] <= '0;
            end
        end else begin
            if (bvalid_reg && axil_wr.bready)
                bvalid_reg <= 1'b0;

            if (axil_wr.awvalid && axil_wr.wvalid && !bvalid_reg) begin
                bvalid_reg <= 1'b1;

                case (reg_addr_t'(axil_wr.awaddr))
                REG_CTRL: if (axil_wr.wstrb[0]) begin
                    start_reg <= axil_wr.wdata[0];
                    tdd_en    <= axil_wr.wdata[1];
                    bypass    <= axil_wr.wdata[2];
                end
                REG_BATCH_LEN: batch_length <= merge_batch(batch_length, axil_wr.wdata, axil_wr.wstrb);
                REG_DELAY_LEN: delay_length <= merge_delay(delay_length, axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_I0: weights_i[0] <= merge_weight(weights_i[0], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_I1: weights_i[1] <= merge_weight(weights_i[1], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_I2: weights_i[2] <= merge_weight(weights_i[2], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_I3: weights_i[3] <= merge_weight(weights_i[3], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_Q0: weights_q[0] <= merge_weight(weights_q[0], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_Q1: weights_q[1] <= merge_weight(weights_q[1], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_Q2: weights_q[2] <= merge_weight(weights_q[2], axil_wr.wdata, axil_wr.wstrb);
                REG_WEIGHT_Q3: weights_q[3] <= merge_weight(weights_q[3], axil_wr.wdata, axil_wr.wstrb);
                default: ;
                endcase
            end
        end
    end

    reg [DATA_W-1:0] rdata_reg;
    reg              rvalid_reg;

    assign axil_rd.arready = ~rvalid_reg;
    assign axil_rd.rvalid  = rvalid_reg;
    assign axil_rd.rdata   = rdata_reg;
    assign axil_rd.rresp   = 2'b00;

    always @(posedge clk) begin
        if (rst) begin
            rvalid_reg <= 1'b0;
            rdata_reg  <= '0;
        end else begin
            if (rvalid_reg && axil_rd.rready)
                rvalid_reg <= 1'b0;

            if (axil_rd.arvalid && !rvalid_reg) begin
                rvalid_reg <= 1'b1;

                case (reg_addr_t'(axil_rd.araddr))
                REG_CTRL:      rdata_reg <= {29'b0, bypass, tdd_en, 1'b0};
                REG_BATCH_LEN: rdata_reg <= {{(DATA_W - BATCH_LEN_WIDTH){1'b0}}, batch_length};
                REG_DELAY_LEN: rdata_reg <= {{(DATA_W - DELAY_LEN_WIDTH){1'b0}}, delay_length};
                REG_WEIGHT_I0:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_i[0]};
                REG_WEIGHT_I1:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_i[1]};
                REG_WEIGHT_I2:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_i[2]};
                REG_WEIGHT_I3:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_i[3]};
                REG_WEIGHT_Q0:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_q[0]};
                REG_WEIGHT_Q1:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_q[1]};
                REG_WEIGHT_Q2:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_q[2]};
                REG_WEIGHT_Q3:  rdata_reg <= {{(DATA_W - WEIGHT_W){1'b0}}, weights_q[3]};
                default:       rdata_reg <= '0;
                endcase
            end
        end
    end

endmodule
