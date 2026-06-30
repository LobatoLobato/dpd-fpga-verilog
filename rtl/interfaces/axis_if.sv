interface axis_if #(
    parameter integer DATA_WIDTH
)();
    logic [DATA_WIDTH-1:0] tdata;
    logic [3:0]            tuser;
    logic                  tvalid;
    logic                  tready;
    logic                  tlast;
    
    task init();
    begin
        tdata  = 0;
        tvalid = 0;
        tready = 0;
        tuser  = 0;
        tlast  = 0;
    end
    endtask

    task automatic send(ref logic clk, input logic [DATA_WIDTH-1:0] data);
    begin
        tvalid = 1;
        tdata = data;
        @(posedge clk);
        while (!tready) @(posedge clk);
        tvalid = 0;
        tdata = 0;
    end
    endtask
    
    modport master (
        input  tready,
        output tvalid, tdata, tuser, tlast
    );

    modport slave (
        output tready,
        input  tvalid, tdata, tuser, tlast
    );
endinterface