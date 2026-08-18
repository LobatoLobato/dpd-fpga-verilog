`ifndef TDDCTL_MODEL_SVH
`define TDDCTL_MODEL_SVH

// Cycle-accurate reference model for the DPD tddctl.
//
// Mirrors rtl/dpd/tddctl.sv: we is combinational, start/state are registered,
// and trigger is registered one cycle (trigger_r) so a rising trigger is acted
// on at the next clock edge. The BFM drives inputs on the negedge and the
// monitor samples one time step after the posedge (post-NBA), so at each
// sample:
//   - we, tdd_en, tdd_tx, trigger are the current-cycle values, and
//   - trigger_posedge = ~prev_trig && trigger  (prev_trig from last cycle).
//
// The model is stepped once per clock cycle with the values sampled by the
// monitor and returns the expected combinational we and the expected start
// that the DUT drives for that cycle.
class tddctl_model;
    typedef enum logic {IDLE = 1'b0, WAIT_TDD = 1'b1} state_t;

    state_t state;
    logic   prev_trig;

    int exp_start_count;   // start pulses predicted by the model

    function new(string name = "tddctl_model");
        state       = IDLE;
        prev_trig   = 1'b0;
        exp_start_count = 0;
    endfunction : new

    // Clears model state on a DUT reset (state machine and trigger pipeline).
    function void reset();
        state     = IDLE;
        prev_trig = 1'b0;
    endfunction : reset

    function int start_count();
        return exp_start_count;
    endfunction : start_count

    function void step(
        input  logic en,
        input  logic tx,
        input  logic trig,
        input  logic rst,
        output logic exp_we,
        output bit   exp_start
    );
        logic trigger_posedge;

        exp_we = (en & tx) | ~en;

        if (rst) begin
            reset();
            exp_start = 1'b0;
            return;
        end

        trigger_posedge = ~prev_trig && trig;

        case (state)
            IDLE: begin
                if (trigger_posedge) begin
                    if (en && ~tx) state = WAIT_TDD;
                    else exp_start = 1'b1;
                end else exp_start = 1'b0;
            end
            WAIT_TDD: begin
                if (tx || ~en) begin
                    state     = IDLE;
                    exp_start = 1'b1;
                end else exp_start = 1'b0;
            end
            default: begin
                state     = IDLE;
                exp_start = 1'b0;
            end
        endcase

        prev_trig = trig;
        if (exp_start) exp_start_count++;
    endfunction : step

endclass : tddctl_model

`endif // TDDCTL_MODEL_SVH
