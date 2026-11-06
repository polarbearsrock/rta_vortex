// Copyright © 2019-2026
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from Vortex 50cb174 hw/rtl/mufu/VX_mufu_pe.sv
// (vendor/vortex): the front end of the UCC lane's SFU mode. It is the MUFU's range reduction (stage 1, VX_mufu_pe's)
// and coefficient ROM (stage 2), and it hands ucc_fma's input register one FP64 FMA that evaluates the MUFU's
// quadratic a0 + a1 xl + a2 xl^2:
// - the multiplier's operands make the FU's tiled product (ucc_tilemul, in SFU mode) 2^28 (a1 xl + a2 xl^2) exactly:
//   a = xl^2 * 2^24 + xl * 2^4 and b = a1 * 2^24 + a2 * 2^4, a1 and a2 in two's complement (27 and 20 bits);
// - c's significand is a0 (lg2: |k * 2^30 + a0|), without an implicit bit;
// - the exponents put a0's lowest bit at the product's bit 46 (exponent difference -6) and give the product
//   exponent 2^(e + 28), e being the MUFU's result scale, so the sum is the MUFU's 2^(e - 30) * (a0 + ...);
// - the signs make it an effective addition with the result's sign, or for a negative lg2 a subtraction.
// The MUFU truncates its two products before adding them and rounds half up; ucc_fma adds them exactly and rounds
// once, to nearest even. Unlike VX_mufu_pe, tanh of |x| < 2^-5 is not a special value carrying x but passes x through
// the datapath (c's significand is x's, the product is zero), which returns x exactly as the MUFU does.
// Each stage's registers (the ROM's read included) load only with an SFU operation entering it, and flush_i drops the
// operations in both stages, as it does ucc_fma's.

`include "common_cells/registers.svh"

module ucc_sfu (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             flush_i,          // drop the operations in both stages
  input  logic             valid_i,          // an SFU operation this cycle
  input  logic [2:0]       fn_i,             // Vortex's INST_MUFU_* encoding
  input  logic [31:0]      x_i,              // FP32
  output logic             valid_o,          // two cycles later: its FMA for ucc_fma's input register
  output logic [2:0][63:0] operands_o,       // a, b, c (a's and b's mantissas are the multiplier's operands)
  output logic [52:0]      mul_a_o,          // xl^2 (truncated) at bits 41-24, xl at bits 21-4
  output logic [52:0]      mul_b_o,          // a1 at bits 50-24, a2 at bits 23-4, both two's complement
  output logic             special_o,        // the result is special_result_o
  output logic [31:0]      special_result_o,
  output logic             zero_sign_o       // sign of an exactly zero result
);
  localparam logic [2:0] FN_RCP   = 3'd0;
  localparam logic [2:0] FN_RSQRT = 3'd1;
  localparam logic [2:0] FN_EX2   = 3'd2;
  localparam logic [2:0] FN_LG2   = 3'd3;
  localparam logic [2:0] FN_SINPI = 3'd4;
  localparam logic [2:0] FN_COSPI = 3'd5;
  localparam logic [2:0] FN_TANH  = 3'd6;

  localparam logic [2:0] TBL_RCP   = 3'd0;
  localparam logic [2:0] TBL_RSQRT = 3'd1;
  localparam logic [2:0] TBL_EX2   = 3'd2;
  localparam logic [2:0] TBL_LG2   = 3'd3;
  localparam logic [2:0] TBL_SIN   = 3'd4;
  localparam logic [2:0] TBL_TANH  = 3'd5;

  localparam logic [31:0] F32_QNAN    = 32'h7fc00000;
  localparam logic [31:0] F32_POS_INF = 32'h7f800000;
  localparam logic [31:0] F32_NEG_INF = 32'hff800000;
  localparam logic [31:0] F32_ONE     = 32'h3f800000;

  // The FP64 exponents of the FMA: the product's is the MUFU's scale plus 28 (the 2^28 of the multiplier operands'
  // layout, xl and a2 at bit 4 and xl^2 and a1 at bit 24, puts the MUFU's 18-bit truncation point at the product's
  // bit 46), c's six lower
  localparam int signed EXP_A = 1023 + 28; // with b's exponent 1023 (1.0)
  localparam int signed EXP_C = EXP_A - 6;

  // ----------------------------------
  // Stage 1: range reduction (the MUFU's)
  // ----------------------------------
  logic        x_s;
  logic [7:0]  x_e;
  logic [22:0] x_m;
  logic [23:0] x_sig;
  logic        x_zero, x_inf, x_nan;
  logic signed [9:0] x_k;

  assign x_s   = x_i[31];
  assign x_e   = x_i[30:23];
  assign x_m   = x_i[22:0];
  assign x_sig = {1'b1, x_m};

  assign x_zero = (x_e == 8'd0);
  assign x_inf  = (x_e == 8'hff) && (x_m == 23'd0);
  assign x_nan  = (x_e == 8'hff) && (x_m != 23'd0);

  assign x_k = 10'($signed({2'b00, x_e})) - 10'sd127;

  logic [3:0]  ex2_lsh;
  logic [7:0]  ex2_rsh;
  logic [37:0] ex2_mag;
  logic [38:0] ex2_x;

  assign ex2_lsh = 4'(x_e - 8'd120);
  assign ex2_rsh = 8'd120 - x_e;
  assign ex2_mag = (x_e >= 8'd120) ? (38'(x_sig) << ex2_lsh)
                 : ((ex2_rsh < 8'd24) ? 38'(x_sig >> ex2_rsh[4:0]) : 38'd0);
  assign ex2_x   = x_s ? -{1'b0, ex2_mag} : {1'b0, ex2_mag};

  logic [7:0]  trig_lsh, trig_rsh;
  logic        is_sin;
  logic [31:0] trig_u0, trig_u;
  logic        trig_odd, trig_neg, trig_one;
  logic [29:0] trig_t;

  assign trig_lsh = x_e - 8'd119;
  assign trig_rsh = 8'd119 - x_e;
  assign is_sin   = (fn_i == FN_SINPI);
  assign trig_u0  = (x_e >= 8'd119) ? ((trig_lsh < 8'd32) ? (32'(x_sig) << trig_lsh[4:0]) : 32'd0)
                  : ((trig_rsh < 8'd24) ? 32'(x_sig >> trig_rsh[4:0]) : 32'd0);
  assign trig_u   = is_sin ? trig_u0 : (trig_u0 + 32'h40000000);
  assign trig_odd = trig_u[30];
  assign trig_t   = trig_odd ? ~trig_u[29:0] : trig_u[29:0];
  assign trig_neg = trig_u[31] ^ (is_sin && x_s);
  assign trig_one = trig_odd && (trig_u[29:0] == 30'd0);

  logic              r_special;
  logic [31:0]       r_sval;
  logic [2:0]        r_tbl;
  logic [6:0]        r_idx;
  logic [17:0]       r_xl;
  logic signed [9:0] r_exp;
  logic              r_neg, r_zsign, r_lg2, r_pass;

  always_comb begin : range_reduction
    r_special = 1'b0;
    r_sval    = 32'd0;
    r_tbl     = TBL_RCP;
    r_idx     = x_m[22:16];
    r_xl      = {x_m[15:0], 2'b00};
    r_exp     = 10'sd0;
    r_neg     = 1'b0;
    r_zsign   = 1'b0;
    r_lg2     = 1'b0;
    r_pass    = 1'b0;
    unique case (fn_i)
      FN_RCP: begin
        r_neg = x_s;
        r_exp = 10'sd127 - 10'($signed({2'b00, x_e}));
        if (x_inf) begin
          r_special = 1'b1;
          r_sval    = {x_s, 31'd0};
        end else if (x_zero) begin
          r_special = 1'b1;
          r_sval    = x_s ? F32_NEG_INF : F32_POS_INF;
        end
      end
      FN_RSQRT: begin
        r_tbl = TBL_RSQRT;
        r_idx = {x_k[0], x_m[22:17]};
        r_xl  = {x_m[16:0], 1'b0};
        r_exp = -(x_k >>> 1);
        if (x_zero) begin
          r_special = 1'b1;
          r_sval    = x_s ? F32_NEG_INF : F32_POS_INF;
        end else if (x_s) begin
          r_special = 1'b1;
          r_sval    = F32_QNAN;
        end else if (x_inf) begin
          r_special = 1'b1;
          r_sval    = 32'd0;
        end
      end
      FN_EX2: begin
        r_tbl = TBL_EX2;
        r_idx = {1'b0, ex2_x[29:24]};
        r_xl  = ex2_x[23:6];
        r_exp = 10'($signed(ex2_x[38:30]));
        if (x_inf) begin
          r_special = 1'b1;
          r_sval    = x_s ? 32'd0 : F32_POS_INF;
        end else if (x_zero) begin
          r_special = 1'b1;
          r_sval    = F32_ONE;
        end else if (x_e >= 8'd134) begin
          r_special = 1'b1;
          r_sval    = x_s ? 32'd0 : F32_POS_INF;
        end
      end
      FN_LG2: begin
        r_tbl = TBL_LG2;
        r_idx = {1'b0, x_m[22:17]};
        r_xl  = {x_m[16:0], 1'b0};
        r_lg2 = 1'b1;
        if (x_zero) begin
          r_special = 1'b1;
          r_sval    = F32_NEG_INF;
        end else if (x_s) begin
          r_special = 1'b1;
          r_sval    = F32_QNAN;
        end else if (x_inf) begin
          r_special = 1'b1;
          r_sval    = F32_POS_INF;
        end
      end
      FN_SINPI, FN_COSPI: begin
        r_tbl   = TBL_SIN;
        r_idx   = {1'b0, trig_t[29:24]};
        r_xl    = trig_t[23:6];
        r_neg   = trig_neg;
        r_zsign = is_sin && x_s;
        if (x_inf) begin
          r_special = 1'b1;
          r_sval    = F32_QNAN;
        end else if (x_zero) begin
          r_special = 1'b1;
          r_sval    = is_sin ? {x_s, 31'd0} : F32_ONE;
        end else if (trig_one) begin
          r_special = 1'b1;
          r_sval    = {trig_neg, F32_ONE[30:0]};
        end
      end
      FN_TANH: begin
        r_tbl = TBL_TANH;
        r_idx = {1'b0, 3'(x_e - 8'd122), x_m[22:20]};
        r_xl  = x_m[19:2];
        r_exp = x_k + 10'sd4;
        r_neg = x_s;
        if (x_e >= 8'd130) begin
          r_special = 1'b1;
          r_sval    = {x_s, F32_ONE[30:0]};
        end else if (x_zero) begin
          r_special = 1'b1;
          r_sval    = {x_s, 31'd0};
        end else if (x_e < 8'd122) begin
          // tanh x = x: x's significand goes to c, through the index and xl registers, at the scale that returns x
          r_pass = 1'b1;
          r_idx  = x_sig[23:17];
          r_xl   = {x_sig[16:0], 1'b0};
          r_exp  = 10'($signed({2'b00, x_e})) - 10'sd120;
        end
      end
      default: begin
        r_special = 1'b1;
        r_sval    = 32'd0;
      end
    endcase
    if (x_nan) begin
      r_special = 1'b1;
      r_sval    = F32_QNAN;
    end
  end

  // Stage 1 register (VX_mufu_pe's s1_reg), loading with an SFU operation only
  logic              s1_valid, s1_special, s1_neg, s1_zsign, s1_lg2, s1_pass;
  logic [31:0]       s1_sval;
  logic signed [9:0] s1_exp, s1_k;
  logic [2:0]        s1_tbl;
  logic [6:0]        s1_idx;
  logic [17:0]       s1_xl;

  `FF(s1_valid, valid_i & ~flush_i, 1'b0)
  `FFLNR(s1_special, r_special, valid_i, clk_i)
  `FFLNR(s1_sval,    r_sval,    valid_i, clk_i)
  `FFLNR(s1_exp,     r_exp,     valid_i, clk_i)
  `FFLNR(s1_neg,     r_neg,     valid_i, clk_i)
  `FFLNR(s1_zsign,   r_zsign,   valid_i, clk_i)
  `FFLNR(s1_lg2,     r_lg2,     valid_i, clk_i)
  `FFLNR(s1_pass,    r_pass,    valid_i, clk_i)
  `FFLNR(s1_k,       x_k,       valid_i, clk_i)
  `FFLNR(s1_tbl,     r_tbl,     valid_i, clk_i)
  `FFLNR(s1_idx,     r_idx,     valid_i, clk_i)
  `FFLNR(s1_xl,      r_xl,      valid_i, clk_i)

  // -------------------------------------
  // Stage 2: coefficients and the operands
  // -------------------------------------
  logic [31:0]        a0;
  logic signed [26:0] a1;
  logic signed [19:0] a2;

  ucc_sfu_rom i_rom (
    .clk_i,
    .en_i  ( s1_valid ),
    .tbl_i ( s1_tbl ),
    .idx_i ( s1_idx ),
    .a0_o  ( a0     ),
    .a1_o  ( a1     ),
    .a2_o  ( a2     )
  );

  logic              s2_special, s2_neg, s2_zsign, s2_lg2, s2_pass;
  logic [31:0]       s2_sval;
  logic signed [9:0] s2_exp, s2_k;
  logic [6:0]        s2_idx;
  logic [17:0]       s2_xl;

  `FF(valid_o, s1_valid & ~flush_i, 1'b0)
  `FFLNR(s2_special, s1_special, s1_valid, clk_i)
  `FFLNR(s2_sval,    s1_sval,    s1_valid, clk_i)
  `FFLNR(s2_exp,     s1_exp,     s1_valid, clk_i)
  `FFLNR(s2_neg,     s1_neg,     s1_valid, clk_i)
  `FFLNR(s2_zsign,   s1_zsign,   s1_valid, clk_i)
  `FFLNR(s2_lg2,     s1_lg2,     s1_valid, clk_i)
  `FFLNR(s2_pass,    s1_pass,    s1_valid, clk_i)
  `FFLNR(s2_k,       s1_k,       s1_valid, clk_i)
  `FFLNR(s2_idx,     s1_idx,     s1_valid, clk_i)
  `FFLNR(s2_xl,      s1_xl,      s1_valid, clk_i)

  // xl^2 truncated to 18 bits, as the MUFU's
  logic [35:0] xl_sq;
  logic [17:0] sq;

  assign xl_sq = 36'(s2_xl) * 36'(s2_xl);
  assign sq    = xl_sq[35:18];

  // lg2 adds the input's exponent k as the integer part: c holds |k * 2^30 + a0|, negative for k < 0
  logic signed [40:0] lg2_sum;
  logic               lg2_neg;
  logic [40:0]        lg2_mag;
  logic [51:0]        addend;

  assign lg2_sum = (41'(s2_k) <<< 30) + 41'(a0);
  assign lg2_neg = lg2_sum[40];
  assign lg2_mag = lg2_neg ? -lg2_sum : lg2_sum;

  always_comb begin : operands
    logic        sign_a, sign_c;
    logic [10:0] exp_a, exp_c;
    if (s2_pass)     addend = 52'({s2_idx, s2_xl[17:1]}); // x's significand
    else if (s2_lg2) addend = 52'(lg2_mag);
    else             addend = 52'(a0);
    sign_a = s2_lg2 ? 1'b0    : s2_neg;
    sign_c = s2_lg2 ? lg2_neg : s2_neg;
    exp_a  = 11'(EXP_A + s2_exp);
    exp_c  = 11'(EXP_C + s2_exp);
    operands_o[0] = {sign_a, exp_a, 52'd0};
    operands_o[1] = {1'b0, 11'd1023, 52'd0};
    operands_o[2] = {sign_c, exp_c, addend};
    mul_a_o = s2_pass ? '0 : {11'd0, sq, 2'd0, s2_xl, 4'd0};
    mul_b_o = {2'd0, a1, 24'd0} | {29'd0, a2, 4'd0};
  end

  assign special_o        = s2_special;
  assign special_result_o = s2_sval;
  assign zero_sign_o      = s2_zsign;
endmodule
