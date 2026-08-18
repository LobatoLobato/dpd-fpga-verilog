`resetall
`timescale 1ns / 1ps
`default_nettype none

// SPDX-License-Identifier: MIT
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

interface taxi_axis_if #(
    // Width of AXI stream interfaces in bits
    parameter DATA_W = 64,
    // tkeep signal width (bytes per cycle)
    parameter KEEP_W = ((DATA_W+7)/8),
    // Use tkeep signal
    parameter logic KEEP_EN = KEEP_W > 1,
    // Use tstrb signal
    parameter logic STRB_EN = 1'b0,
    // Use tlast signal
    parameter logic LAST_EN = 1'b1,
    // Use tid signal
    parameter logic ID_EN = 0,
    // tid signal width
    parameter ID_W = 8,
    // Use tdest signal
    parameter logic DEST_EN = 0,
    // tdest signal width
    parameter DEST_W = 8,
    // Use tuser signal
    parameter logic USER_EN = 0,
    // tuser signal width
    parameter USER_W = 2
)
(input wire tb_clk = 1'b0);
    logic [DATA_W-1:0] tdata;
    logic [KEEP_W-1:0] tkeep;
    logic [KEEP_W-1:0] tstrb;
    logic [ID_W-1:0] tid;
    logic [DEST_W-1:0] tdest;
    logic [USER_W-1:0] tuser;
    logic tlast;
    logic tvalid;
    logic tready;

    modport src (
        output tdata,
        output tkeep,
        output tstrb,
        output tid,
        output tdest,
        output tuser,
        output tlast,
        output tvalid,
        input  tready
    );

    modport snk (
        input  tdata,
        input  tkeep,
        input  tstrb,
        input  tid,
        input  tdest,
        input  tuser,
        input  tlast,
        input  tvalid,
        output tready
    );

    modport mon (
        input  tdata,
        input  tkeep,
        input  tstrb,
        input  tid,
        input  tdest,
        input  tuser,
        input  tlast,
        input  tvalid,
        input  tready
    );

    task automatic send(input logic [DATA_W-1:0] data, input logic [USER_W-1:0] user = '0, input logic last = 1'b0);
        tdata  <= data;
        tuser  <= user;
        tlast  <= last;
        tvalid <= 1'b1;
        @(posedge tb_clk);
        while (!tready) @(posedge tb_clk);
        tvalid <= 1'b0;
    endtask

    task automatic recv(output logic [DATA_W-1:0] data, output logic [USER_W-1:0] user, output logic last);
        tready <= 1'b1;
        while (!tvalid) @(posedge tb_clk);
        data = tdata;
        user = tuser;
        last = tlast;
        @(posedge tb_clk);
        tready <= 1'b0;
    endtask

endinterface
