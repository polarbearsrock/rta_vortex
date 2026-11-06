// s2chitni & Claude (AI-generated)
//
// The UCC FU's FP min, max, neg, abs and compares (ucc_pkg's FP_MIN to FP_GE), in one cycle: FPnew's fpnew_noncomp,
// unmodified, once in FP64 and once in FP32, combinational. Its operations are selected as FPnew encodes them in the
// rounding mode: MINMAX (RNE min, RTZ max); SGNJ with b = a (RTZ sgnjn = neg, RDN sgnjx = abs); CMP (RNE le, RTZ lt,
// RDN eq), op_mod negating the result unless an operand is a NaN, so GT is not-LE, GE not-LT and NE not-EQ (true for
// NaNs). FP32 reads bits 31-0 of a and b; its values come back NaN-boxed, and a compare's 0 or 1 zero-extended in
// either format. status_o is FPnew's flags.
module ucc_fp_noncomp (
  input  logic               clk_i,  // FPnew's ports; with no pipeline registers the unit is combinational
  input  logic               rst_ni,
  input  logic [63:0]        a_i,
  input  logic [63:0]        b_i,
  input  logic               fp32_i,
  input  logic [4:0]         func_i,
  output logic [63:0]        result_o,
  output fpnew_pkg::status_t status_o
);
  import ucc_pkg::*;

  fpnew_pkg::operation_e op;
  fpnew_pkg::roundmode_e rnd;
  logic                  op_mod, unary, compare;

  always_comb begin : select
    op      = fpnew_pkg::CMP;
    rnd     = fpnew_pkg::RNE;
    op_mod  = 1'b0;
    unary   = 1'b0;
    compare = 1'b1;
    unique case (func_i)
      FP_MIN:  begin op = fpnew_pkg::MINMAX; rnd = fpnew_pkg::RNE; compare = 1'b0; end
      FP_MAX:  begin op = fpnew_pkg::MINMAX; rnd = fpnew_pkg::RTZ; compare = 1'b0; end
      FP_NEG:  begin op = fpnew_pkg::SGNJ;   rnd = fpnew_pkg::RTZ; compare = 1'b0; unary = 1'b1; end
      FP_ABS:  begin op = fpnew_pkg::SGNJ;   rnd = fpnew_pkg::RDN; compare = 1'b0; unary = 1'b1; end
      FP_EQ:   rnd = fpnew_pkg::RDN;
      FP_NE:   begin rnd = fpnew_pkg::RDN; op_mod = 1'b1; end
      FP_LT:   rnd = fpnew_pkg::RTZ;
      FP_LE:   rnd = fpnew_pkg::RNE;
      FP_GT:   begin rnd = fpnew_pkg::RNE; op_mod = 1'b1; end
      FP_GE:   begin rnd = fpnew_pkg::RTZ; op_mod = 1'b1; end
      default: ;
    endcase
  end

  logic [1:0][63:0]         operands;
  logic [63:0]              result64;
  logic [31:0]              result32;
  fpnew_pkg::status_t       status64, status32;

  assign operands = {unary ? a_i : b_i, a_i};

  fpnew_noncomp #(
    .FpFormat ( fpnew_pkg::FP64 )
  ) i_fp64 (
    .clk_i,
    .rst_ni,
    .operands_i      ( operands                   ),
    .is_boxed_i      ( 2'b11                      ),
    .rnd_mode_i      ( rnd                        ),
    .op_i            ( op                         ),
    .op_mod_i        ( op_mod                     ),
    .tag_i           ( 1'b0                       ),
    .mask_i          ( 1'b1                       ),
    .aux_i           ( 1'b0                       ),
    .in_valid_i      ( 1'b1                       ),
    .in_ready_o      (                            ),
    .flush_i         ( 1'b0                       ),
    .result_o        ( result64                   ),
    .status_o        ( status64                   ),
    .extension_bit_o (                            ),
    .class_mask_o    (                            ),
    .is_class_o      (                            ),
    .tag_o           (                            ),
    .mask_o          (                            ),
    .aux_o           (                            ),
    .out_valid_o     (                            ),
    .out_ready_i     ( 1'b1                       ),
    .busy_o          (                            ),
    .reg_ena_i       ( 1'b0                       ),
    .early_out_valid_o (                          )
  );

  fpnew_noncomp #(
    .FpFormat ( fpnew_pkg::FP32 )
  ) i_fp32 (
    .clk_i,
    .rst_ni,
    .operands_i      ( {operands[1][31:0], operands[0][31:0]} ),
    .is_boxed_i      ( 2'b11                      ),
    .rnd_mode_i      ( rnd                        ),
    .op_i            ( op                         ),
    .op_mod_i        ( op_mod                     ),
    .tag_i           ( 1'b0                       ),
    .mask_i          ( 1'b1                       ),
    .aux_i           ( 1'b0                       ),
    .in_valid_i      ( 1'b1                       ),
    .in_ready_o      (                            ),
    .flush_i         ( 1'b0                       ),
    .result_o        ( result32                   ),
    .status_o        ( status32                   ),
    .extension_bit_o (                            ),
    .class_mask_o    (                            ),
    .is_class_o      (                            ),
    .tag_o           (                            ),
    .mask_o          (                            ),
    .aux_o           (                            ),
    .out_valid_o     (                            ),
    .out_ready_i     ( 1'b1                       ),
    .busy_o          (                            ),
    .reg_ena_i       ( 1'b0                       ),
    .early_out_valid_o (                          )
  );

  assign result_o = fp32_i ? (compare ? 64'(result32) : {32'hffff_ffff, result32}) : result64;
  assign status_o = fp32_i ? status32 : status64;
endmodule
