// s2chitni & Claude (AI-generated)
//
// ucc_fma's addend and normalization shifters, a module of their own so that synthesis reports them separately: data_i
// shifted left (LEFT) or right by shamt_i, filling with zeros.
module ucc_shift #(
  parameter int unsigned WIDTH       = 8,
  parameter int unsigned SHAMT_WIDTH = 3,
  parameter bit          LEFT        = 1'b0  // 1: shift left, 0: shift right
) (
  input  logic [WIDTH-1:0]       data_i,
  input  logic [SHAMT_WIDTH-1:0] shamt_i,
  output logic [WIDTH-1:0]       data_o
);
  assign data_o = LEFT ? data_i << shamt_i : data_i >> shamt_i;
endmodule
