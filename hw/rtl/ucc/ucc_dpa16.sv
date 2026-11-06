// s2chitni & Claude (AI-generated)
//
// The UCC FU's DPA-16 (ucc_pkg's FP_DPA opcodes): d = c + sum of a_i * b_i in FP32, on TransDot's dpa16_core at 599aaa5
// with its tiles taken out (ucc_dpa16_core), every format selectable per operation (M=0, PIPE=1, ONLY=-1, SHARE=0,
// RND=0, the configuration of dora-lab's rta_dpa16 array). The 16 tiles are the
// FU's (ucc_tiles): the core sends their operands and modes out and takes their products back in the same cycle. Its
// numerics are TransDot's (dpa16_ref.py): exact products, every term aligned to the largest anchor in a 27-bit window
// with truncation, one sum, FP32 by truncation, the canonical NaN for any NaN or infinity among the active inputs. The
// inputs are the FU's input register; the core's three stages return d three cycles later, four after issue.
// The FU's own two formats arrive mapped onto the core's paths (ucc_fma, before the input register): MXFP8 as FP8 with
// mx8_i, which applies one E8M0 scale per side from byte 0 of the scales, and FP4 as MXFP4 with every scale 2^0. en_i
// says which of the core's stages a DPA-16 operation enters (bit 0 the first), and only those registers load.
module ucc_dpa16 (
  input  logic                             clk_i,
  input  logic                             rst_ni,
  input  logic [2:0]                       en_i,   // a DPA-16 operation enters S1's, S2's, S3's register
  input  logic [2:0]                       fmt_i,  // dpa16_pkg::fmt_e
  input  logic                             mx8_i,  // MXFP8 (with fmt_i FP8)
  input  logic [1:0]                       e5m2_i, // FP8 subtypes: bit 0 a's, bit 1 b's (1: E5M2)
  input  logic [ucc_pkg::DPA_OPERAND-1:0]  a_i,    // {four 8-bit block scales, 256-bit operand}
  input  logic [ucc_pkg::DPA_OPERAND-1:0]  b_i,
  input  logic [31:0]                      c_i,
  output logic [31:0]                      d_o,
  // the tiles (ucc_tiles)
  output logic [15:0][15:0]                ta_o,
  output logic [15:0][15:0]                tb_o,
  output logic                             m_full_o,
  output logic                             m_fp8_o,
  output logic                             m_fp4_o,
  input  logic [15:0][23:0]                tprod_i,
  input  logic [15:0][3:0][7:0]            dprod_i
);
  logic [0:0][31:0] vd_unused;

  ucc_dpa16_core #(
    .M     ( 0    ),
    .PIPE  ( 1'b1 ),
    .ONLY  ( -1   ),
    .SHARE ( 0    ),
    .RND   ( 0    )
  ) i_core (
    .clk_i,
    .rst_ni,
    .en_i,
    .fmt_i    ( dpa16_pkg::fmt_e'(fmt_i) ),
    .a_e5m2_i ( e5m2_i[0]                ),
    .b_e5m2_i ( e5m2_i[1]                ),
    .a_i      ( a_i[255:0]               ),
    .b_i      ( b_i[255:0]               ),
    .sa_i     ( a_i[287:256]             ),
    .sb_i     ( b_i[287:256]             ),
    .mx8_i,
    .c_i,
    .d_o,
    .vec_i    ( 1'b0                     ),
    .va_i     ( '0                       ),
    .vb_i     ( '0                       ),
    .vc_i     ( '0                       ),
    .vd_o     ( vd_unused                ),
    .ta_o,
    .tb_o,
    .m_full_o,
    .m_fp8_o,
    .m_fp4_o,
    .tprod_i,
    .dprod_i
  );
endmodule
