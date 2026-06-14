module filter #(
    parameter integer DATA_WIDTH = 14
) (
    input wire clk, input wire rst,
    input wire [11:0] weights [4],
    input wire bypass,
    axis_if.slave  input_axis,
    axis_if.master output_axis
);
    assign output_axis.tdata = input_axis.tdata << 1;
    assign output_axis.tvalid = 1;
endmodule