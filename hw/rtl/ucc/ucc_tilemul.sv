// s2chitni & Claude (AI-generated)
//
// The FU's 53 x 53 significand product, on DPA-16's tiles: the 16 tile products (ucc_tiles; tile 4i + j is a's 12-bit
// chunk i times b's chunk j, weighing 2^(12 (i + j)), or 0 where its mode turns it off) cover a[47:0] * b[47:0], and
// two strips above bit 47 complete them, a[52:48] * b and a[47:0] * b[52:48], both at bit 48. One sum, modulo 2^106:
// - FP64 and FP32 (significands at bits 23-0): p_o = a_i * b_i;
// - INT32: a 32-bit integer at bits 52-21 of a and of b; with a_signed_i (b_signed_i) a (b) is two's complement, and
//   a correction subtracts 2^53 times the other operand when its sign bit is set, so p_o = a * b;
// - SFU (sfu_i): a = sq * 2^24 + xl * 2^4 and b = a1 * 2^24 + a2 * 2^4, xl and sq (the MUFU's xl^2, truncated) 18
//   bits, a1 (27 bits) and a2 (20 bits) two's complement; the tiles give the two cross products of the halves, the
//   b strip a1's top bits, and two corrections a1's and a2's signs, so p_o = 2^28 (a1 xl + a2 sq), the same sum the
//   Booth multiplier's two row groups formed.
module ucc_tilemul (
  input  logic [15:0][23:0] tile_p_i,
  input  logic [52:0]       a_i,
  input  logic [52:0]       b_i,
  input  logic              sfu_i,
  input  logic              a_signed_i,
  input  logic              b_signed_i,
  output logic [105:0]      p_o
);
  // The b strip's other operand: in the SFU only xl's half of a (a[52:48] is 0 there)
  logic [47:0] strip_b_a;
  logic [57:0] strip_a;
  logic [52:0] strip_b;

  assign strip_b_a = sfu_i ? {24'd0, a_i[23:0]} : a_i[47:0];
  assign strip_a   = a_i[52:48] * b_i;
  assign strip_b   = strip_b_a * b_i[52:48];

  // Subtracted corrections: INT32's two's complement operands, and the SFU's coefficients a1 (sign at b bit 50,
  // weight 2^27 times xl * 2^28) and a2 (sign at b bit 23, weight 2^20 times sq * 2^28)
  logic [105:0] k_a, k_b;

  always_comb begin
    k_a = '0;
    k_b = '0;
    if (sfu_i) begin
      if (b_i[50]) k_a = 106'(a_i[23:0]) << 51;
      if (b_i[23]) k_b = 106'(a_i[47:24]) << 48;
    end else begin
      if (a_signed_i & a_i[52]) k_a = 106'(b_i) << 53;
      if (b_signed_i & b_i[52]) k_b = 106'(a_i) << 53;
    end
  end

  always_comb begin
    p_o = (106'(strip_a) << 48) + (106'(strip_b) << 48) - k_a - k_b;
    for (int t = 0; t < 16; t++) p_o += 106'(tile_p_i[t]) << (12 * (t / 4 + t % 4));
  end
endmodule
