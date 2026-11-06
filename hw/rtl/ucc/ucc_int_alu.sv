// s2chitni & Claude (AI-generated)
//
// The UCC's INT32 ALU: the integer operations that do not multiply (ucc_pkg's INT_* codes 0-25; 26-31 return 0).
// One adder serves add, sub, the compares, min, max and abs (0 - a); shifts take b's bits 4-0, as RISC-V's and the
// DICE PE's do. It sits after ucc_fma's input register, and its result goes to ucc_fma's result in the same cycle,
// one cycle after issue.
module ucc_int_alu (
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  input  logic [4:0]  op_i,
  output logic [31:0] y_o
);
  import ucc_pkg::*;

  logic        sub, abs_op, signed_op, eq, lt, b_zero;
  logic [31:0] x, y;
  logic [32:0] sum;

  // Everything but add subtracts: the compares, min and max compute a - b, and abs computes 0 - a
  assign abs_op    = (op_i == INT_ABS);
  assign sub       = (op_i != INT_ADD);
  assign x         = abs_op ? 32'd0 : a_i;
  assign y         = abs_op ? a_i : b_i;
  assign sum       = {1'b0, x} + {1'b0, sub ? ~y : y} + 33'(sub);
  assign signed_op = (op_i inside {INT_LT_S, INT_LE_S, INT_GT_S, INT_GE_S, INT_MIN_S, INT_MAX_S});
  assign eq        = (a_i == b_i);
  // a < b: unsigned, no carry out of a + ~b + 1; signed, a's sign if the signs differ, else the difference's sign
  assign lt        = signed_op ? ((a_i[31] ^ b_i[31]) ? a_i[31] : sum[31]) : ~sum[32];
  assign b_zero    = (b_i == '0);

  always_comb begin
    unique case (op_i)
      INT_ADD, INT_SUB:           y_o = sum[31:0];
      INT_AND:                    y_o = a_i & b_i;
      INT_OR:                     y_o = a_i | b_i;
      INT_XOR:                    y_o = a_i ^ b_i;
      INT_NOT:                    y_o = ~a_i;
      INT_SHL:                    y_o = a_i << b_i[4:0];
      INT_SHR_U:                  y_o = a_i >> b_i[4:0];
      INT_SHR_S:                  y_o = 32'($signed(a_i) >>> b_i[4:0]);
      INT_EQ:                     y_o = {31'd0, eq};
      INT_NE:                     y_o = {31'd0, ~eq};
      INT_LT_S, INT_LT_U:         y_o = {31'd0, lt};
      INT_LE_S, INT_LE_U:         y_o = {31'd0, lt | eq};
      INT_GT_S, INT_GT_U:         y_o = {31'd0, ~(lt | eq)};
      INT_GE_S, INT_GE_U:         y_o = {31'd0, ~lt};
      INT_MIN_S, INT_MIN_U:       y_o = lt ? a_i : b_i;
      INT_MAX_S, INT_MAX_U:       y_o = lt ? b_i : a_i;
      INT_ABS:                    y_o = a_i[31] ? sum[31:0] : a_i;
      INT_CZERO_EQZ:              y_o = b_zero ? '0 : a_i;
      INT_CZERO_NEZ:              y_o = b_zero ? a_i : '0;
      default:                    y_o = '0;
    endcase
  end
endmodule
