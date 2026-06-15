module tddctl(
    input  wire clk, rst,
    input  wire tdd_en, tdd_tx,
    input  wire trigger,
    output wire we,
    output reg start
);
    enum  {Idle, WaitTdd} state = Idle;
    logic trigger_r = 0;
    wire trigger_posedge = ~trigger_r && trigger;

    assign we = (tdd_en & tdd_tx) | ~tdd_en;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) trigger_r <= 1'b0;
        else     trigger_r <= trigger;
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin 
            state        <= Idle;
            start        <= 0;
        end else case (state)
            Idle: if (trigger_posedge) begin
                if (tdd_en && ~tdd_tx) state <= WaitTdd;
                else start <= 1;
            end else start <= 0;
            WaitTdd: if (tdd_tx || ~tdd_en) begin
                start <= 1;
                state <= Idle;
            end else start <= 0;
            default: begin
                state <= Idle;
                start <= 0;
            end
        endcase 
    end
endmodule