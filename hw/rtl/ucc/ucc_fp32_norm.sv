// Copyright 2019 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// SPDX-License-Identifier: SHL-0.51

// Author: Stefan Mach <smach@iis.ee.ethz.ch>
//
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from TransDot 599aaa5 src/fpnew_fma.sv: the
// normalization shift amount and exponent of ucc_fma's FMA path in format FpFormat, which is fpnew_fma's
// (leading-zero count of the sum's lower 2p+3 bits): an FP32 operation's in FP32, and in FP64 the FP64 path's.
// The shift itself is ucc_fma's, shared by both modes, and ucc_fp32_ctrl chose the case and its exponent in the
// first cycle.

module ucc_fp32_norm #(
  parameter fpnew_pkg::fp_format_e FpFormat = fpnew_pkg::FP32,
  // Do not change
  localparam int unsigned LOWER_SUM_WIDTH    = ucc_pkg::lower_sum_width(FpFormat),
  localparam int unsigned EXP_WIDTH          = ucc_pkg::exp_width(FpFormat),
  localparam int unsigned SHIFT_AMOUNT_WIDTH = ucc_pkg::shift_amount_width(FpFormat)
) (
  input  logic [LOWER_SUM_WIDTH-1:0]    sum_lower_i,
  input  logic                          use_lzc_i,
  input  logic signed [EXP_WIDTH-1:0]   exponent_i, // product's if use_lzc_i, else tentative
  input  logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt_i,
  output logic [SHIFT_AMOUNT_WIDTH-1:0] norm_shamt_o,
  output logic signed [EXP_WIDTH-1:0]   normalized_exponent_o,
  output logic                          zero_o // sum_lower_i is zero (the SFU's sum, which is product-anchored)
);
  localparam int unsigned PRECISION_BITS   = fpnew_pkg::man_bits(FpFormat) + 1;
  localparam int unsigned LZC_RESULT_WIDTH = $clog2(LOWER_SUM_WIDTH);

  logic        [LZC_RESULT_WIDTH-1:0] leading_zero_count;     // the number of leading zeroes
  logic signed [LZC_RESULT_WIDTH:0]   leading_zero_count_sgn; // signed leading-zero count
  logic                               lzc_zeroes;             // in case only zeroes found

  // Leading zero counter for cancellations
  lzc #(
    .WIDTH ( LOWER_SUM_WIDTH ),
    .MODE  ( 1               ) // MODE = 1 counts leading zeroes
  ) i_lzc (
    .in_i    ( sum_lower_i        ),
    .cnt_o   ( leading_zero_count ),
    .empty_o ( lzc_zeroes         )
  );

  assign leading_zero_count_sgn = signed'({1'b0, leading_zero_count});
  assign zero_o                 = lzc_zeroes;

  // Normalization shift amount based on exponents and LZC (unsigned as only left shifts)
  always_comb begin : norm_shift_amount
    // Product-anchored case or cancellations require LZC
    if (use_lzc_i) begin
      // Normal result (biased exponent > 0 and not a zero)
      if ((exponent_i - leading_zero_count_sgn + 1 >= 0) && !lzc_zeroes) begin
        // Undo initial product shift, remove the counted zeroes
        norm_shamt_o          = PRECISION_BITS + 2 + leading_zero_count;
        normalized_exponent_o = exponent_i - leading_zero_count_sgn + 1; // account for shift
      // Subnormal result
      end else begin
        // Cap the shift distance to align mantissa with minimum exponent
        norm_shamt_o          = unsigned'(signed'(PRECISION_BITS) + 2 + exponent_i);
        normalized_exponent_o = 0; // subnormals encoded as 0
      end
    // Addend-anchored case
    end else begin
      norm_shamt_o          = addend_shamt_i; // Undo the initial shift
      normalized_exponent_o = exponent_i;
    end
  end
endmodule
