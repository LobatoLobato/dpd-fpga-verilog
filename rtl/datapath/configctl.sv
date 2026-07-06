`resetall
`timescale 1ns / 1ps
`default_nettype none

package configctl_defs;
    localparam int ADDR_W = 3;

    typedef enum logic [ADDR_W - 1:0] {
        REG_CTRL      = 'h0,
        REG_BATCH_LEN = 'h1,
        REG_DELAY_LEN = 'h2,
        REG_WEIGHT_0  = 'h3,
        REG_WEIGHT_1  = 'h4,
        REG_WEIGHT_2  = 'h5,
        REG_WEIGHT_3  = 'h7
    } reg_addr_t;
endpackage

module configctl 
    import configctl_defs::*;
#(
    parameter integer DATA_W = 32
)(
    input wire clk,
    input wire rst,

    taxi_axil_if.wr_slv axil_wr,
    taxi_axil_if.rd_slv axil_rd,
    
    output wire        start,
    output reg         tdd_en,
    output reg  [11:0] batch_length,
    output reg  [11:0] delay_length,

    output reg  [11:0] weights [4],
    output reg         bypass
);
    reg start_reg;
    reg bvalid_reg;
    
    assign start = start_reg;

    assign axil_wr.awready = ~bvalid_reg;
    assign axil_wr.wready  = ~bvalid_reg;
    assign axil_wr.bvalid  = bvalid_reg;
    assign axil_wr.bresp   = 2'b00;

    // AXI write interface
    always @(posedge clk) begin
        start_reg <= 1'b0;

        if (rst) begin
            bvalid_reg   <= 1'b0;
            tdd_en       <= 1'b0;
            bypass       <= 1'b0;
            batch_length <= 12'd1;
            delay_length <= 12'd0;
            weights[0]   <= 12'd0;
            weights[1]   <= 12'd0;
            weights[2]   <= 12'd0;
            weights[3]   <= 12'd0;
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
                REG_BATCH_LEN: begin
                    if (axil_wr.wstrb[0]) batch_length[7:0]  <= axil_wr.wdata[7:0];
                    if (axil_wr.wstrb[1]) batch_length[11:8] <= axil_wr.wdata[11:8];
                end
                REG_DELAY_LEN: begin
                    if (axil_wr.wstrb[0]) delay_length[7:0]  <= axil_wr.wdata[7:0];
                    if (axil_wr.wstrb[1]) delay_length[11:8] <= axil_wr.wdata[11:8];
                end
                REG_WEIGHT_0: begin
                    if (axil_wr.wstrb[0]) weights[0][7:0]  <= axil_wr.wdata[7:0];
                    if (axil_wr.wstrb[1]) weights[0][11:8] <= axil_wr.wdata[11:8];
                end
                REG_WEIGHT_1: begin
                    if (axil_wr.wstrb[0]) weights[1][7:0]  <= axil_wr.wdata[7:0];
                    if (axil_wr.wstrb[1]) weights[1][11:8] <= axil_wr.wdata[11:8];
                end
                REG_WEIGHT_2: begin
                    if (axil_wr.wstrb[0]) weights[2][7:0]  <= axil_wr.wdata[7:0];
                    if (axil_wr.wstrb[1]) weights[2][11:8] <= axil_wr.wdata[11:8];
                end
                REG_WEIGHT_3: begin
                    if (axil_wr.wstrb[0]) weights[3][7:0]  <= axil_wr.wdata[7:0];
                    if (axil_wr.wstrb[1]) weights[3][11:8] <= axil_wr.wdata[11:8];
                end
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
                REG_BATCH_LEN: rdata_reg <= {20'b0, batch_length};
                REG_DELAY_LEN: rdata_reg <= {20'b0, delay_length};
                REG_WEIGHT_0:  rdata_reg <= {20'b0, weights[0]};
                REG_WEIGHT_1:  rdata_reg <= {20'b0, weights[1]};
                REG_WEIGHT_2:  rdata_reg <= {20'b0, weights[2]};
                REG_WEIGHT_3:  rdata_reg <= {20'b0, weights[3]};
                default:       rdata_reg <= '0;
                endcase
            end
        end
    end

endmodule
