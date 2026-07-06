`timescale 1ns/1ps

module configctl_tb();
    parameter integer CLK_PERIOD = 10;
    parameter integer AXIL_DATA_W = 32;
    parameter integer AXIL_ADDR_W = configctl_defs::ADDR_W;
    
    reg clk, rst;
    wire start, tdd_en, bypass;
    wire [11:0] batch_length, delay_length;
    wire [11:0] weights [4];
    
    taxi_axil_if #(.DATA_W(AXIL_DATA_W), .ADDR_W(AXIL_ADDR_W)) axil(.tb_clk(clk));
    
    configctl #(
        .DATA_W(AXIL_DATA_W)
     ) configctl (
    	.clk         (clk),
    	.rst         (rst),
    	.axil_wr     (axil),
    	.axil_rd     (axil),
    	.start       (start),
    	.tdd_en      (tdd_en),
    	.batch_length(batch_length),
    	.delay_length(delay_length),
    	.weights     (weights),
    	.bypass      (bypass)
    );
    
    function automatic logic [AXIL_DATA_W-1:0] read_output(configctl_defs::reg_addr_t addr);
        case (addr)
        configctl_defs::REG_CTRL:      return {29'b0, bypass, tdd_en, start};
        configctl_defs::REG_BATCH_LEN: return {20'b0, batch_length};
        configctl_defs::REG_DELAY_LEN: return {20'b0, delay_length};
        configctl_defs::REG_WEIGHT_0:  return {20'b0, weights[0]};
        configctl_defs::REG_WEIGHT_1:  return {20'b0, weights[1]};
        configctl_defs::REG_WEIGHT_2:  return {20'b0, weights[2]};
        configctl_defs::REG_WEIGHT_3:  return {20'b0, weights[3]};
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

        $display("--- Starting Simulation ---");
        $display("Testing if registers are writable and readable with AXI4-Lite");
        // CTRL: writes start: 1, tdd_en: 1, bypass: 0
        //       reads  start: 0, tdd_en: 1, bypass: 0
        test_reg_wr(configctl_defs::REG_CTRL, 32'({1'b0, 1'b1, 1'b1}));
        test_reg_rd(configctl_defs::REG_CTRL, 32'({1'b0, 1'b1, 1'b0}));
        
        test_reg_all(configctl_defs::REG_BATCH_LEN, 12'd1024);
        test_reg_all(configctl_defs::REG_DELAY_LEN, 12'd7);
        
        test_reg_all(configctl_defs::REG_WEIGHT_0, 12'd1);
        test_reg_all(configctl_defs::REG_WEIGHT_1, 12'd2);
        test_reg_all(configctl_defs::REG_WEIGHT_2, 12'd3);
        test_reg_all(configctl_defs::REG_WEIGHT_3, 12'd4);
        
        $display("Testbench Result: OK");
        $display("--- End of Simulation ---");
        $stop;
    end

    initial begin
        $dumpfile("sim/waveforms/datapath/configctl.vcd");
        $dumpvars(0, configctl_tb);
    end

endmodule
