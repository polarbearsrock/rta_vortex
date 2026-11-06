// s2chitni & Claude (AI-generated)
//
// The UCC's 53x53 significand multiplier: radix-4 Booth on b, 27 partial-product rows summed in one carry-save tree
// and a 106-bit carry-propagate adder, the structure synthesis infers for fpnew_fma's `*`. It is written out so that the
// rows can multiply different copies of a: rows 0-13 multiply a_lo_i and rows 14-26 multiply a_hi_i. For any inputs,
//   p_o = a_lo_i * L + a_hi_i * (b - L)  (mod 2^106),  L = b_i[27:0] - b_i[27] * 2^28,
// L being the value of Booth digits 0-13, b the value of b_i and a_lo_i, a_hi_i theirs: unsigned, or with b_signed_i
// (a_signed_i) set two's complement.
//   FP64: a_lo_i = a_hi_i = a, so p_o = a * b.
//   2 x FP32: a and b are packed {x1 at bits 52-29, five zero bits, x0 at bits 23-0}, a_lo_i keeps only a0 (bits 23-0)
//   and a_hi_i only a1 (bits 52-29). With bits 28-24 of b zero, digit 13 is zero, L = b0 and b_i - L = b1 * 2^29, so
//   p_o = a0 * b0 + a1 * b1 * 2^58: lane 0 in bits 47-0, lane 1 in bits 105-58 and zeros between. Rows of the two
//   lanes overlap in the carry-save tree, and the carry-propagate adder resolves them exactly.
//   SFU: b_i = a2 * 2^28 + a1 (signed), a_lo_i = xl * 2^28 and a_hi_i = xl^2, so p_o = 2^28 (a1 xl + a2 xl^2), the
//   MUFU's two products in one sum (two's complement).
//   INT32: a 32-bit integer at bits 52-21 of a and of b (its sign at bit 52), a_lo_i = a_hi_i = a, so the 64-bit
//   product a * b is at bits 105-42; a_signed_i and b_signed_i pick signed or unsigned operands.
module ucc_mul53 (
  input  logic [52:0]  a_lo_i,      // multiplicand of rows 0-13
  input  logic [52:0]  a_hi_i,      // multiplicand of rows 14-26
  input  logic [52:0]  b_i,         // Booth-recoded multiplier
  input  logic         b_signed_i,  // b_i is two's complement: the top digit sees its sign
  input  logic         a_signed_i,  // a_lo_i and a_hi_i are two's complement: a row's sign is also its multiplicand's
  output logic [105:0] p_o
);
  localparam int unsigned ROWS  = 27;  // (53 + 1) / 2 digits, b unsigned or signed
  localparam int unsigned SPLIT = 14;  // the first row of a_hi_i
  localparam int unsigned W     = 106;

  // Row i is d_i * a << 2i with d_i in {-2..2}: 55 bits {~s, m ^ n} << 2i plus n at bit 2i, with m = |d_i| * a (54
  // bits, two's complement if a is signed), n the digit's sign and s the row's: n, flipped if m is negative. The sign
  // bit's weight -s * 2^(54+2i) is written as ~s * 2^(54+2i) - 2^(54+2i), which leaves the constant -sum(2^(54+2i));
  // its bits are 54 and above, the n bits 52 and below, so one operand holds both.
  function automatic logic [W-1:0] sign_constant();
    logic [W-1:0] c;
    c = '0;
    for (int i = 0; i < ROWS; i++) c -= W'(1) << (54 + 2 * i);
    return c;
  endfunction
  localparam logic [W-1:0] SIGN_CONSTANT = sign_constant();

  logic [54:0]            bx;    // {sign, b, 0}: digit i reads bx[2i+2:2i] = {b[2i+1], b[2i], b[2i-1]}
  logic [ROWS-1:0]        neg;
  logic [ROWS-1:0][W-1:0] row;
  logic [W-1:0]           corrections;

  assign bx = {b_signed_i & b_i[52], b_i, 1'b0};

  for (genvar i = 0; i < ROWS; i++) begin : gen_row
    logic [2:0]  d;
    logic        one, two, s;
    logic [52:0] x;
    logic [53:0] a, m;
    assign d      = bx[2*i +: 3];
    assign one    = d[1] ^ d[0];                 // |d_i| = 1
    assign two    = (d[2] ^ d[1]) & ~one;        // |d_i| = 2
    assign neg[i] = d[2] & ~(d[1] & d[0]);       // d_i < 0 (-0 counts as +0)
    assign x      = (i < SPLIT) ? a_lo_i : a_hi_i;
    assign a      = {a_signed_i & x[52], x};
    assign m      = ({54{one}} & a) | ({54{two}} & {a[52:0], 1'b0});
    assign s      = neg[i] ^ (a_signed_i & x[52] & (one | two));
    assign row[i] = W'({~s, m ^ {54{neg[i]}}}) << (2 * i);
  end

  always_comb begin
    corrections = SIGN_CONSTANT;
    for (int i = 0; i < ROWS; i++) corrections[2*i] = neg[i];
  end

  always_comb begin
    p_o = corrections;
    for (int i = 0; i < ROWS; i++) p_o += row[i];
  end
endmodule
