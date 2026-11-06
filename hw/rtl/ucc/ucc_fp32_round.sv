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
// rounding, classification and result selection of ucc_fma's FMA path in format FpFormat, which are fpnew_fma's,
// in two parts: an FP32 operation's in FP32, and in FP64 the FP64 path's. ucc_fp32_preround, in ucc_fma's
// middle stage, assembles the value before rounding from the normalized sum (ucc_fma's normalization, shared by
// both modes), or takes the special result; ucc_fp32_round, in the output cycle, rounds that value and classifies
// the result.

module ucc_fp32_preround #(
  parameter fpnew_pkg::fp_format_e FpFormat = fpnew_pkg::FP32,
  // Do not change
  localparam int unsigned WIDTH           = fpnew_pkg::fp_width(FpFormat),
  localparam int unsigned PRECISION_BITS  = fpnew_pkg::man_bits(FpFormat) + 1,
  localparam int unsigned LOWER_SUM_WIDTH = ucc_pkg::lower_sum_width(FpFormat),
  localparam int unsigned EXP_WIDTH       = ucc_pkg::exp_width(FpFormat)
) (
  input  logic [PRECISION_BITS:0]     final_mantissa_i,  // with the round bit
  input  logic [LOWER_SUM_WIDTH-1:0]  sum_sticky_bits_i, // the 2p+3 bits below it
  input  logic                        sticky_before_add_i,
  input  logic signed [EXP_WIDTH-1:0] final_exponent_i,
  input  logic                        final_sign_i,
  input  logic                        effective_subtraction_i,
  input  logic                        result_is_special_i,
  input  logic [WIDTH-1:0]            special_result_i,
  input  fpnew_pkg::status_t          special_status_i,
  output logic [WIDTH-1:0]            value_o, // the sign and value before rounding, or the special result
  output ucc_pkg::round_t             round_o
);
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);

  logic sticky_after_norm; // sticky bit after normalization

  // Update the sticky bit with the shifted-out bits
  assign sticky_after_norm = (| {sum_sticky_bits_i}) | sticky_before_add_i;

  logic [EXP_BITS-1:0] pre_round_exponent;
  logic [MAN_BITS-1:0] pre_round_mantissa;
  logic [1:0]          round_sticky_bits;
  logic                of_before_round; // overflow

  // Classification before round. RISC-V mandates checking underflow AFTER rounding!
  assign of_before_round = final_exponent_i >= 2**(EXP_BITS)-1; // infinity exponent is all ones

  // Assemble result before rounding. In case of overflow, the largest normal value is set.
  assign pre_round_exponent = (of_before_round) ? 2**EXP_BITS-2 : unsigned'(final_exponent_i[EXP_BITS-1:0]);
  assign pre_round_mantissa = (of_before_round) ? '1 : final_mantissa_i[MAN_BITS:1]; // bit 0 is R bit

  // In case of overflow, the round and sticky bits are set for proper rounding
  assign round_sticky_bits  = (of_before_round) ? 2'b11 : {final_mantissa_i[0], sticky_after_norm};

  assign value_o = result_is_special_i ? special_result_i : {final_sign_i, pre_round_exponent, pre_round_mantissa};
  assign round_o = '{special: result_is_special_i, round_sticky: round_sticky_bits,
                     effective_subtraction: effective_subtraction_i, of_before_round: of_before_round,
                     uf_sticky: sum_sticky_bits_i[MAN_BITS*2 + 4], special_status: special_status_i};
endmodule

module ucc_fp32_round #(
  parameter fpnew_pkg::fp_format_e FpFormat = fpnew_pkg::FP32,
  // Do not change
  localparam int unsigned WIDTH = fpnew_pkg::fp_width(FpFormat)
) (
  input  logic [WIDTH-1:0]      value_i, // ucc_fp32_preround's, registered
  input  ucc_pkg::round_t       round_i,
  input  fpnew_pkg::roundmode_e rnd_mode_i,
  output logic [WIDTH-1:0]      result_o,
  output fpnew_pkg::status_t    status_o
);
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);

  // ----------------------------
  // Rounding and classification
  // ----------------------------
  logic [EXP_BITS+MAN_BITS-1:0] pre_round_abs; // absolute value of result before rounding

  logic of_after_round; // overflow
  logic uf_after_round; // underflow
  logic result_zero;

  logic                         rounded_sign;
  logic [EXP_BITS+MAN_BITS-1:0] rounded_abs; // absolute value of result after rounding

  assign pre_round_abs = value_i[EXP_BITS+MAN_BITS-1:0];

  // Perform the rounding
  fpnew_rounding #(
    .AbsWidth ( EXP_BITS + MAN_BITS )
  ) i_fpnew_rounding (
    .abs_value_i             ( pre_round_abs                  ),
    .sign_i                  ( value_i[WIDTH-1]               ),
    .round_sticky_bits_i     ( round_i.round_sticky           ),
    .rnd_mode_i              ( rnd_mode_i                     ),
    .effective_subtraction_i ( round_i.effective_subtraction  ),
    .abs_rounded_o           ( rounded_abs                    ),
    .sign_o                  ( rounded_sign                   ),
    .exact_zero_o            ( result_zero                    )
  );

  // Classification after rounding
  assign uf_after_round = (rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '0) // denormal
        || ((pre_round_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '0) && (rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == 1) &&
           ((round_i.round_sticky != 2'b11) || (!round_i.uf_sticky && ((rnd_mode_i == fpnew_pkg::RNE) || (rnd_mode_i == fpnew_pkg::RMM)))));
  assign of_after_round = rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '1; // exponent all ones

  // -----------------
  // Result selection
  // -----------------
  logic [WIDTH-1:0]     regular_result;
  fpnew_pkg::status_t   regular_status;

  // Assemble regular result
  assign regular_result    = {rounded_sign, rounded_abs};
  assign regular_status.NV = 1'b0; // only valid cases are handled in regular path
  assign regular_status.DZ = 1'b0; // no divisions
  assign regular_status.OF = round_i.of_before_round | of_after_round;   // rounding can introduce overflow
  assign regular_status.UF = uf_after_round & regular_status.NX; // only inexact results raise UF
  assign regular_status.NX = (| round_i.round_sticky) | round_i.of_before_round | of_after_round;

  // Select output depending on special case detection
  assign result_o = round_i.special ? value_i : regular_result;
  assign status_o = round_i.special ? round_i.special_status : regular_status;
endmodule
