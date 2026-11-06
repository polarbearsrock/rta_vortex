// s2chitni & Claude (AI-generated)
//
// The UCC FU's one set of multipliers: DPA-16's 16 tiles (TransDot's dpa16_mul12, 599aaa5, unmodified), shared by
// DPA-16 and the FU's other products, after the input register. A DPA-16 operation (dpa_i) gives the tiles the
// operands and modes ucc_dpa16_core sends out. Any other gives tile t = 4i + j the 12-bit chunk i of the FU's
// multiplicand a_i and chunk j of b_i, in full 12 x 12 mode; ucc_tilemul then adds the tiles' products at 2^(12 (i + j))
// to its two strips into the 53 x 53 product. The SFU's mode (sfu_i) turns tiles off (zero operands): a holds xl^2
// (truncated) at bits 47-24 and xl * 2^4 at bits 23-0, b a1 at bits 50-24 and a2 * 2^4 at bits 23-0, and only the
// tiles that multiply one half by the other are on, xl * a1 and xl^2 * a2. An FP32 product's significands are at
// bits 23-0, so chunks 2-3 are zero and their tiles' products 0.
module ucc_tiles (
  input  logic                    dpa_i,
  input  logic [15:0][15:0]       dpa_ta_i,
  input  logic [15:0][15:0]       dpa_tb_i,
  input  logic                    dpa_full_i,
  input  logic                    dpa_fp8_i,
  input  logic                    dpa_fp4_i,
  input  logic [52:0]             a_i,
  input  logic [52:0]             b_i,
  input  logic                    sfu_i,
  output logic [15:0][23:0]       prod_o,
  output logic [15:0][3:0][7:0]   dprod_o
);
  for (genvar t = 0; t < 16; t++) begin : gen_tile
    localparam int unsigned I = t / 4;
    localparam int unsigned J = t % 4;
    // the tile multiplies within one half of a and b ((I < 2) == (J < 2)) or across the halves
    localparam bit SAME_HALF = (I < 2) == (J < 2);
    logic        on;
    logic [15:0] ta, tb;
    assign on = !(sfu_i && SAME_HALF);
    assign ta = dpa_i ? dpa_ta_i[t] : {4'd0, on ? a_i[12*I +: 12] : 12'd0};
    assign tb = dpa_i ? dpa_tb_i[t] : {4'd0, on ? b_i[12*J +: 12] : 12'd0};
    dpa16_mul12 i_tile (
      .a_i      ( ta                       ),
      .b_i      ( tb                       ),
      .m_full_i ( dpa_i ? dpa_full_i : 1'b1 ),
      .m_fp8_i  ( dpa_i & dpa_fp8_i        ),
      .m_fp4_i  ( dpa_i & dpa_fp4_i        ),
      .prod_o   ( prod_o[t]                ),
      .dprod_o  ( dprod_o[t]               )
    );
  end
endmodule
