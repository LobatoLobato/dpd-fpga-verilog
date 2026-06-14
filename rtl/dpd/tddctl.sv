module tddctl(
    input tdd_sig,
    input tdd_en,
    output we
);
    assign we = (tdd_en & tdd_sig) | !tdd_en;
endmodule