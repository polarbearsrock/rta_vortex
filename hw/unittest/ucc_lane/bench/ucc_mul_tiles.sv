// s2chitni & Claude (AI-generated)
//
// The FU's tiled 53 x 53 product alone, for the regression: ucc_tiles in the FU's modes (never DPA-16's) feeding
// ucc_tilemul, combinational.
module ucc_mul_tiles (
  input  logic [52:0]  a_i,
  input  logic [52:0]  b_i,
  input  logic         sfu_i,
  input  logic         a_signed_i,
  input  logic         b_signed_i,
  output logic [105:0] p_o
);
  logic [15:0][23:0]     prod;
  logic [15:0][3:0][7:0] dprod;

  ucc_tiles i_tiles (
    .dpa_i      ( 1'b0   ),
    .dpa_ta_i   ( '0     ),
    .dpa_tb_i   ( '0     ),
    .dpa_full_i ( 1'b0   ),
    .dpa_fp8_i  ( 1'b0   ),
    .dpa_fp4_i  ( 1'b0   ),
    .a_i,
    .b_i,
    .sfu_i,
    .prod_o     ( prod   ),
    .dprod_o    ( dprod  )
  );

  ucc_tilemul i_mul (
    .tile_p_i   ( prod   ),
    .a_i,
    .b_i,
    .sfu_i,
    .a_signed_i,
    .b_signed_i,
    .p_o
  );
endmodule
