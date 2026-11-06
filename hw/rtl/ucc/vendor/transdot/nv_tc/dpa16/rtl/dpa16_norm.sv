// DPA-16 stage 3: normalise the window sum (value = sum * 2^(emax - 25 - RND)) and truncate to FP32.
//   normal    : MSB of |sum| to bit 32 + RND, take the 23 bits below it    exponent field = emax + 134 - lz
//   subnormal : left shift limited to emax + 133 (exponent field 0); below that the result is 0
//   overflow  : exponent field >= 255 -> infinity;  NaN / Inf input -> canonical NaN
// RND = 1 (the sum carries one more bit, see dpa16_align_sum): with rne_i the result is rounded to nearest even on
// the bits below its lsb (an increment of {exponent, fraction}: carries into the exponent, 254 + all ones -> inf).
module dpa16_norm import dpa16_pkg::*; #(
  parameter int RND = 0
) (
  input  logic signed [SUMW+RND-1:0] sum_i,
  input  logic signed [AW-1:0]       emax_i,
  input  logic                       zero_i,
  input  logic                       special_i,
  input  logic                       rne_i,
  output logic [31:0]                d_o
);
  localparam int MW = 33 + RND;
  logic          sgn;
  logic [MW-1:0] mag;
  assign sgn = sum_i[SUMW+RND-1];
  assign mag = sgn ? MW'(-sum_i) : sum_i[MW-1:0];

  logic [5:0] lz;
  always_comb begin
    lz = 6'(MW);
    for (int i = 0; i < MW; i++)
      if (mag[i]) lz = 6'(MW - 1 - i);
  end

  always_comb begin
    logic signed [AW:0] e_norm, e_sub;
    logic [5:0]         sh;
    logic [MW-1:0]      m;
    logic [7:0]         ef;
    logic [30:0]        r;
    logic               zero, up;
    e_norm = (AW+1)'(emax_i) + (AW+1)'(134) - (AW+1)'(lz);
    e_sub  = (AW+1)'(emax_i) + (AW+1)'(133);
    zero   = zero_i || mag == 0;
    if (e_norm >= 1) begin
      sh = lz;
      ef = e_norm[7:0];
    end else if (e_sub >= 0) begin
      sh = e_sub[5:0];
      ef = 8'd0;
    end else begin
      sh   = '0;
      ef   = 8'd0;
      zero = 1'b1;
    end
    m  = mag << sh;
    r  = {ef, m[MW-2 -: 23]};
    up = (RND > 0) && rne_i && m[MW-25] && (m[MW-24] || |m[MW-26:0]);
    if (special_i)          d_o = QNAN;
    else if (zero)          d_o = 32'd0;
    else if (e_norm >= 255) d_o = {sgn, 8'hFF, 23'd0};
    else                    d_o = {sgn, r + 31'(up)};
  end
endmodule
