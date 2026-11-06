// One multiplier tile of the DPA-16 PE: a 12x12 significand multiplier built from a 3x3 grid of 4x4 blocks
// (TransDot-style decomposition). Block (j,k) multiplies nibble j of a by nibble k of b.
//   full (FP16 / BF16 / TF32): prod = sum_jk P[j][k] << 4(j+k)            = a[11:0] * b[11:0]
//   fp8  (2 products)        : only blocks (0,0), (1,1) enabled            -> prod = P00 | P11 << 8
//   fp4  (4 products)        : blocks (0,0), (1,1), (2,2) in the sum       -> prod = P00 | P11 << 8 | P22 << 16
//                              block (0,1) takes nibble 3 of a and b
// Disabled blocks get zero operands (operand isolation), so the diagonal products land in disjoint fields.
// The FP8 / FP4 products are also taken straight from the blocks (dprod = {P01', P22, P11, P00}), so those modes
// do not go through the 24-bit carry-propagate adder of the full product.
module dpa16_mul12 (
  input  logic [15:0] a_i,       // nibbles 0..2 = significand, nibble 3 only in fp4 mode
  input  logic [15:0] b_i,
  input  logic        m_full_i,
  input  logic        m_fp8_i,
  input  logic        m_fp4_i,
  output logic [23:0]     prod_o,
  output logic [3:0][7:0] dprod_o
);
  logic [7:0] p [3][3];

  always_comb begin
    for (int j = 0; j < 3; j++) begin
      for (int k = 0; k < 3; k++) begin
        logic       en;
        logic [3:0] x, y;
        en = m_full_i || (j == k && (m_fp4_i || (m_fp8_i && j < 2)));
        x  = a_i[4*j +: 4];
        y  = b_i[4*k +: 4];
        if (j == 0 && k == 1 && m_fp4_i) begin
          en = 1'b1;
          x  = a_i[15:12];
          y  = b_i[15:12];
        end
        p[j][k] = (en ? x : 4'd0) * (en ? y : 4'd0);
      end
    end
  end

  always_comb begin
    prod_o = '0;
    for (int j = 0; j < 3; j++)
      for (int k = 0; k < 3; k++)
        if (!(j == 0 && k == 1 && m_fp4_i))
          prod_o = prod_o + (24'(p[j][k]) << (4 * (j + k)));
  end
  assign dprod_o = {p[0][1], p[2][2], p[1][1], p[0][0]};
endmodule
