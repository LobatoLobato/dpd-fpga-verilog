`ifndef DPD_SCOREBOARD_SV
`define DPD_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "filter_model.svh"

class dpd_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(dpd_scoreboard)

    localparam int DATA_WIDTH      = 16;
    localparam int PACKED_IQ_WIDTH = 2 * DATA_WIDTH;   // {Q, I}
    localparam int FILTER_LATENCY  = 4;                // mirrors dpd_config_seq::FILTER_LATENCY

    int match_count;
    int mismatch_count;

    logic signed [11:0] wi [4] = '{ 12'sd1229, -12'sd614, 12'sd410, -12'sd307 };  // +0.60, -0.30, +0.20, -0.15
    logic signed [11:0] wq [4] = '{ 12'sd0,    12'sd0,    12'sd0,    12'sd0 };   // no cross-Q predistortion
    bit bypass_mode = 0;

    uvm_tlm_analysis_fifo #(bit [PACKED_IQ_WIDTH-1:0])   command_fifo; // {q, i} of every accepted ref
    uvm_tlm_analysis_fifo #(bit [2*PACKED_IQ_WIDTH-1:0]) result_fifo;  // {fb_q, fb_i, ref_q, ref_i}

    bit [PACKED_IQ_WIDTH-1:0] expected_fb_q [$]; // {fb_q, fb_i} per driven sample
    bit [PACKED_IQ_WIDTH-1:0] sent_ref_q [$];    // {q, i} per driven sample
    bit signed [DATA_WIDTH-1:0] model_i_prev = 0;
    bit signed [DATA_WIDTH-1:0] model_q_prev = 0;

    function new(string name = "dpd_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        match_count = 0;
        mismatch_count = 0;
        command_fifo = new("command_fifo", this);
        result_fifo  = new("result_fifo", this);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_config_db#(bit)::get(this, "", "bypass_mode", bypass_mode));
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        bit [PACKED_IQ_WIDTH-1:0]   cmd;    // {q, i}
        bit [2*PACKED_IQ_WIDTH-1:0] res;    // {fb_q, fb_i, ref_q, ref_i}
        bit [PACKED_IQ_WIDTH-1:0]   res_ref, res_fb, exp_ref, exp_fb;
        logic signed [DATA_WIDTH-1:0] y_i, y_q;
        int checked = 0;

        fork
            forever begin
                command_fifo.get(cmd);
                if (bypass_mode) begin
                    expected_fb_q.push_back(cmd);
                end else begin
                    filter_ref($signed(cmd[DATA_WIDTH-1:0]),
                               $signed(cmd[PACKED_IQ_WIDTH-1:DATA_WIDTH]),
                               model_i_prev, model_q_prev, wi, wq, y_i, y_q);
                    expected_fb_q.push_back({y_q, y_i});
                end
                sent_ref_q.push_back(cmd);
                model_i_prev = cmd[DATA_WIDTH-1:0];
                model_q_prev = cmd[PACKED_IQ_WIDTH-1:DATA_WIDTH];
            end
            forever begin
                result_fifo.get(res);
                res_ref = res[PACKED_IQ_WIDTH-1:0];
                res_fb  = res[2*PACKED_IQ_WIDTH-1:PACKED_IQ_WIDTH];

                if (checked >= sent_ref_q.size() ||
                    checked + FILTER_LATENCY >= expected_fb_q.size()) begin
                    `uvm_error(get_full_name(), $sformatf(
                        "Captured pair %0d (ref=%0d) arrived before the model queues covered it.",
                        checked, $signed(res_ref[DATA_WIDTH-1:0])))
                    mismatch_count++;
                end else begin
                    exp_ref = sent_ref_q[checked];
                    exp_fb  = expected_fb_q[checked + FILTER_LATENCY];
                    checked++;

                    if (res_ref !== exp_ref) begin
                        `uvm_error(get_full_name(), $sformatf(
                            "MISMATCH ref for pair %0d: expected (%0d,%0d), got (%0d,%0d)",
                            checked - 1,
                            $signed(exp_ref[PACKED_IQ_WIDTH-1:DATA_WIDTH]), $signed(exp_ref[DATA_WIDTH-1:0]),
                            $signed(res_ref[PACKED_IQ_WIDTH-1:DATA_WIDTH]),  $signed(res_ref[DATA_WIDTH-1:0])))
                        mismatch_count++;
                    end else if (res_fb !== exp_fb) begin
                        `uvm_error(get_full_name(), $sformatf(
                            "MISMATCH fb for ref (%0d,%0d): expected (%0d,%0d), got (%0d,%0d)",
                            $signed(exp_ref[PACKED_IQ_WIDTH-1:DATA_WIDTH]), $signed(exp_ref[DATA_WIDTH-1:0]),
                            $signed(exp_fb[PACKED_IQ_WIDTH-1:DATA_WIDTH]),   $signed(exp_fb[DATA_WIDTH-1:0]),
                            $signed(res_fb[PACKED_IQ_WIDTH-1:DATA_WIDTH]),   $signed(res_fb[DATA_WIDTH-1:0])))
                        mismatch_count++;
                    end else begin
                        `uvm_info(get_full_name(), $sformatf(
                            "MATCH ref (%0d,%0d) fb (%0d,%0d)",
                            $signed(res_ref[PACKED_IQ_WIDTH-1:DATA_WIDTH]), $signed(res_ref[DATA_WIDTH-1:0]),
                            $signed(res_fb[PACKED_IQ_WIDTH-1:DATA_WIDTH]),   $signed(res_fb[DATA_WIDTH-1:0])), UVM_LOW)
                        match_count++;
                    end
                end
            end
        join_none
    endtask : run_phase

    function void report_phase(uvm_phase phase);
        int total = match_count + mismatch_count;
        real match_percentage = (total > 0) ? (match_count * 100.0 / total) : 0.0;

        `uvm_info(get_full_name(), $sformatf("\n--- DPD SCOREBOARD SUMMARY ---\n Total Pairs Checked: %0d\n Matches: %0d (%0.2f%%)\n Mismatches: %0d\n",
            total, match_count, match_percentage, mismatch_count), UVM_LOW)

        if (mismatch_count > 0) begin
            `uvm_error(get_full_name(), "TEST FAILED: Scoreboard reported mismatches.")
        end else begin
            `uvm_info(get_full_name(), "TEST PASSED: All captured pairs matched the Memory Polynomial model.", UVM_LOW)
        end
    endfunction : report_phase

endclass : dpd_scoreboard

`endif // DPD_SCOREBOARD_SV
