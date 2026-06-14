interface capture_cfg_if #(
    parameter integer DATA_WIDTH
)();
    logic [(DATA_WIDTH*2)-1:0] data;
    logic [3:0] err_code;
    
    logic [11:0] batch_length;
    logic [11:0] delay_length;

    logic tdd_en;
    logic start;
    logic done;

    modport master (
        output start, tdd_en, batch_length, delay_length,
        input done
    );

    modport slave (
        input start, tdd_en, batch_length, delay_length,
        output done
    );
endinterface

interface filter_cfg_if ();
    logic [11:0] weights [4];
    logic bypass;
    
    modport master (
        output weights, bypass
    );

    modport slave (
        input weights, bypass
    );
endinterface