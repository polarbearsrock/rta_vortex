// s2chitni & Claude (AI-generated)
//
// The UCC FU's conversions (ucc_pkg's FP_CVT_F to FP_TO_U32): FPnew's fpnew_cast_multi, unmodified, with FP32, FP64
// and INT32 enabled and no pipeline registers. The opcode's format bit names the FP format the conversion produces
// or reads: FP_CVT_F converts from the other format, FP_CVT_S32/U32 from an int32, FP_TO_S32/U32 to one (op_mod is
// FPnew's unsigned flag). FP32 operands are bits 31-0; FP32 results come back NaN-boxed, int32 results
// zero-extended. FPnew follows RISC-V: a NaN converts to the largest int32, and out-of-range values saturate.
// status_o is FPnew's flags.
module ucc_fp_cast (
  input  logic                  clk_i,  // FPnew's ports; with no pipeline registers the unit is combinational
  input  logic                  rst_ni,
  input  logic [63:0]           a_i,
  input  logic                  fp32_i,
  input  logic [4:0]            func_i,
  input  fpnew_pkg::roundmode_e rnd_mode_i,
  output logic [63:0]           result_o,
  output fpnew_pkg::status_t    status_o
);
  import ucc_pkg::*;

  // FPnew's format masks are ascending ([0:N-1]), so each format's bit is set by its index
  function automatic fpnew_pkg::fmt_logic_t fp_formats();
    fpnew_pkg::fmt_logic_t mask;
    mask                  = '0;
    mask[fpnew_pkg::FP32] = 1'b1;
    mask[fpnew_pkg::FP64] = 1'b1;
    return mask;
  endfunction

  function automatic fpnew_pkg::ifmt_logic_t int_formats();
    fpnew_pkg::ifmt_logic_t mask;
    mask                   = '0;
    mask[fpnew_pkg::INT32] = 1'b1;
    return mask;
  endfunction

  localparam fpnew_pkg::fmt_logic_t  FORMATS     = fp_formats();
  localparam fpnew_pkg::ifmt_logic_t INT_FORMATS = int_formats();

  fpnew_pkg::operation_e op;
  fpnew_pkg::fp_format_e fmt, other;
  logic                  op_mod, to_int;
  logic [63:0]           result;

  assign fmt   = fp32_i ? fpnew_pkg::FP32 : fpnew_pkg::FP64;
  assign other = fp32_i ? fpnew_pkg::FP64 : fpnew_pkg::FP32;

  always_comb begin : select
    op     = fpnew_pkg::F2F;
    op_mod = 1'b0;
    unique case (func_i)
      FP_CVT_S32: op = fpnew_pkg::I2F;
      FP_CVT_U32: begin op = fpnew_pkg::I2F; op_mod = 1'b1; end
      FP_TO_S32:  op = fpnew_pkg::F2I;
      FP_TO_U32:  begin op = fpnew_pkg::F2I; op_mod = 1'b1; end
      default:    ;
    endcase
    to_int = (op == fpnew_pkg::F2I);
  end

  fpnew_cast_multi #(
    .FpFmtConfig  ( FORMATS     ),
    .IntFmtConfig ( INT_FORMATS )
  ) i_cast (
    .clk_i,
    .rst_ni,
    .operands_i      ( a_i                                   ),
    .is_boxed_i      ( '1                                    ),
    .rnd_mode_i,
    .op_i            ( op                                    ),
    .op_mod_i        ( op_mod                                ),
    .src_fmt_i       ( (op == fpnew_pkg::F2F) ? other : fmt  ),
    .dst_fmt_i       ( fmt                                   ),
    .int_fmt_i       ( fpnew_pkg::INT32                      ),
    .tag_i           ( 1'b0                                  ),
    .mask_i          ( 1'b1                                  ),
    .aux_i           ( 1'b0                                  ),
    .in_valid_i      ( 1'b1                                  ),
    .in_ready_o      (                                       ),
    .flush_i         ( 1'b0                                  ),
    .result_o        ( result                                ),
    .status_o        ( status_o                              ),
    .extension_bit_o (                                       ),
    .tag_o           (                                       ),
    .mask_o          (                                       ),
    .aux_o           (                                       ),
    .out_valid_o     (                                       ),
    .out_ready_i     ( 1'b1                                  ),
    .busy_o          (                                       ),
    .reg_ena_i       ( 1'b0                                  ),
    .early_out_valid_o (                                     )
  );

  assign result_o = to_int ? {32'd0, result[31:0]} : result;
endmodule
