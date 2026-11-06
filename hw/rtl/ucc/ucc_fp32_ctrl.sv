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
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from TransDot 599aaa5 src/fpnew_fma.sv: the first
// cycle's control of ucc_fma's FMA path in format FpFormat, which is fpnew_fma's input processing (classification,
// operation selection, special cases, exponents, addend shift amount): an FP32 operation's in FP32, and in FP64 the
// FP64 path's. ucc_fma forms the multiplier's operands before its input register, and takes the addend's sticky bit
// from its shifter, so only the addend's significand comes out of here. The normalization's choice between the
// leading-zero count and the addend's shift is made here too, from the exponent difference, so only one exponent
// crosses the middle register.

module ucc_fp32_ctrl #(
  parameter fpnew_pkg::fp_format_e FpFormat = fpnew_pkg::FP32,
  // Do not change
  localparam int unsigned WIDTH              = fpnew_pkg::fp_width(FpFormat),
  localparam int unsigned PRECISION_BITS     = fpnew_pkg::man_bits(FpFormat) + 1,
  localparam int unsigned EXP_WIDTH          = ucc_pkg::exp_width(FpFormat),
  localparam int unsigned SHIFT_AMOUNT_WIDTH = ucc_pkg::shift_amount_width(FpFormat)
) (
  input  logic [2:0][WIDTH-1:0]         operands_i, // a, b, c
  input  logic [2:0]                    is_boxed_i,
  input  fpnew_pkg::roundmode_e         rnd_mode_i,
  input  fpnew_pkg::operation_e         op_i,
  input  logic                          op_mod_i,
  output logic [PRECISION_BITS-1:0]     mantissa_c_o,
  output logic                          effective_subtraction_o,
  output logic                          tentative_sign_o,
  output logic                          use_lzc_o,  // normalize by the leading-zero count
  output logic signed [EXP_WIDTH-1:0]   exponent_o, // product's if use_lzc_o, else tentative
  output logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt_o,
  output logic                          result_is_special_o,
  output logic [WIDTH-1:0]              special_result_o,
  output fpnew_pkg::status_t            special_status_o
);
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);
  localparam int unsigned BIAS     = fpnew_pkg::bias(FpFormat);

  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;

  // -----------------
  // Input processing
  // -----------------
  fpnew_pkg::fp_info_t [2:0] info_q;

  // Classify input
  fpnew_classifier #(
    .FpFormat    ( FpFormat ),
    .NumOperands ( 3        )
    ) i_class_inputs (
    .operands_i ( operands_i ),
    .is_boxed_i ( is_boxed_i ),
    .info_o     ( info_q     )
  );

  fp_t                 operand_a, operand_b, operand_c;
  fpnew_pkg::fp_info_t info_a,    info_b,    info_c;

  // Operation selection and operand adjustment, as in fpnew_fma
  always_comb begin : op_select

    // Default assignments - packing-order-agnostic
    operand_a = operands_i[0];
    operand_b = operands_i[1];
    operand_c = operands_i[2];
    info_a    = info_q[0];
    info_b    = info_q[1];
    info_c    = info_q[2];

    // op_mod_q inverts sign of operand C
    operand_c.sign = operand_c.sign ^ op_mod_i;

    unique case (op_i)
      fpnew_pkg::FMADD:  ; // do nothing
      fpnew_pkg::FNMSUB: operand_a.sign = ~operand_a.sign; // invert sign of product
      fpnew_pkg::ADD,
      fpnew_pkg::ADDS: begin // Set multiplicand to +1
        operand_a = '{sign: 1'b0, exponent: BIAS, mantissa: '0};
        info_a    = '{is_normal: 1'b1, is_boxed: 1'b1, default: 1'b0}; //normal, boxed value.
      end
      fpnew_pkg::MUL: begin // Set addend to +0 or -0, depending whether the rounding mode is RDN
        if (rnd_mode_i == fpnew_pkg::RDN)
          operand_c = '{sign: 1'b0, exponent: '0, mantissa: '0};
        else
          operand_c = '{sign: 1'b1, exponent: '0, mantissa: '0};
        info_c    = '{is_zero: 1'b1, is_boxed: 1'b1, default: 1'b0}; //zero, boxed value.
      end
      default: begin // propagate don't cares
        operand_a  = '{default: fpnew_pkg::DONT_CARE};
        operand_b  = '{default: fpnew_pkg::DONT_CARE};
        operand_c  = '{default: fpnew_pkg::DONT_CARE};
        info_a     = '{default: fpnew_pkg::DONT_CARE};
        info_b     = '{default: fpnew_pkg::DONT_CARE};
        info_c     = '{default: fpnew_pkg::DONT_CARE};
      end
    endcase
  end

  // ---------------------
  // Input classification
  // ---------------------
  logic any_operand_inf;
  logic any_operand_nan;
  logic signalling_nan;
  logic effective_subtraction;

  // Reduction for special case handling
  assign any_operand_inf = (| {info_a.is_inf,        info_b.is_inf,        info_c.is_inf});
  assign any_operand_nan = (| {info_a.is_nan,        info_b.is_nan,        info_c.is_nan});
  assign signalling_nan  = (| {info_a.is_signalling, info_b.is_signalling, info_c.is_signalling});
  // Effective subtraction in FMA occurs when product and addend signs differ
  assign effective_subtraction = operand_a.sign ^ operand_b.sign ^ operand_c.sign;
  // The tentative sign of the FMA shall be the sign of the product
  assign tentative_sign_o = operand_a.sign ^ operand_b.sign;
  assign effective_subtraction_o = effective_subtraction;

  // ----------------------
  // Special case handling
  // ----------------------
  fp_t special_result;

  always_comb begin : special_cases
    // Default assignments
    special_result      = '{sign: 1'b0, exponent: '1, mantissa: 2**(MAN_BITS-1)}; // canonical qNaN
    special_status_o    = '0;
    result_is_special_o = 1'b0;

    // Handle potentially mixed nan & infinity input => important for the case where infinity and
    // zero are multiplied and added to a qnan.
    // RISC-V mandates raising the NV exception in these cases:
    // (inf * 0) + c or (0 * inf) + c INVALID, no matter c (even quiet NaNs)
    if ((info_a.is_inf && info_b.is_zero) || (info_a.is_zero && info_b.is_inf)) begin
      result_is_special_o = 1'b1; // bypass FMA, output is the canonical qNaN
      special_status_o.NV = 1'b1; // invalid operation
    // NaN Inputs cause canonical quiet NaN at the output and maybe invalid OP
    end else if (any_operand_nan) begin
      result_is_special_o = 1'b1;           // bypass FMA, output is the canonical qNaN
      special_status_o.NV = signalling_nan; // raise the invalid operation flag if signalling
    // Special cases involving infinity
    end else if (any_operand_inf) begin
      result_is_special_o = 1'b1; // bypass FMA
      // Effective addition of opposite infinities (±inf - ±inf) is invalid!
      if ((info_a.is_inf || info_b.is_inf) && info_c.is_inf && effective_subtraction)
        special_status_o.NV = 1'b1; // invalid operation
      // Handle cases where output will be inf because of inf product input
      else if (info_a.is_inf || info_b.is_inf) begin
        // Result is infinity with the sign of the product
        special_result    = '{sign: operand_a.sign ^ operand_b.sign, exponent: '1, mantissa: '0};
      // Handle cases where the addend is inf
      end else if (info_c.is_inf) begin
        // Result is inifinity with sign of the addend (= operand_c)
        special_result    = '{sign: operand_c.sign, exponent: '1, mantissa: '0};
      end
    end
  end

  assign special_result_o = special_result;

  // ---------------------------
  // Initial exponent data path
  // ---------------------------
  logic signed [EXP_WIDTH-1:0] exponent_a, exponent_b, exponent_c;
  logic signed [EXP_WIDTH-1:0] exponent_addend, exponent_product, exponent_difference, tentative_exponent;

  // Zero-extend exponents into signed container - implicit width extension
  assign exponent_a = signed'({1'b0, operand_a.exponent});
  assign exponent_b = signed'({1'b0, operand_b.exponent});
  assign exponent_c = signed'({1'b0, operand_c.exponent});

  // Calculate internal exponents from encoded values. Real exponents are (ex = Ex - bias + 1 - nx)
  // with Ex the encoded exponent and nx the implicit bit. Internal exponents stay biased.
  assign exponent_addend = signed'(exponent_c + $signed({1'b0, ~info_c.is_normal})); // 0 as subnorm
  // Biased product exponent is the sum of encoded exponents minus the bias.
  assign exponent_product = (info_a.is_zero || info_b.is_zero)
                            ? 2 - signed'(BIAS) // in case the product is zero, set minimum exp.
                            : signed'(exponent_a + info_a.is_subnormal
                                      + exponent_b + info_b.is_subnormal
                                      - signed'(BIAS));
  // Exponent difference is the addend exponent minus the product exponent
  assign exponent_difference = exponent_addend - exponent_product;
  // The tentative exponent will be the larger of the product or addend exponent
  assign tentative_exponent = (exponent_difference > 0) ? exponent_addend : exponent_product;

  // fpnew_fma's normalization case: product-anchored sums and cancellations need the leading-zero count and the
  // product's exponent, addend-anchored ones the addend's shift and the tentative exponent
  assign use_lzc_o  = (exponent_difference <= 0) || (effective_subtraction && (exponent_difference <= 2));
  assign exponent_o = use_lzc_o ? exponent_product : tentative_exponent;

  // Shift amount for addend based on exponents (unsigned as only right shifts)
  always_comb begin : addend_shift_amount
    // Product-anchored case, saturated shift (addend is only in the sticky bit)
    if (exponent_difference <= signed'(-2 * PRECISION_BITS - 1))
      addend_shamt_o = 3 * PRECISION_BITS + 4;
    // Addend and product will have mutual bits to add
    else if (exponent_difference <= signed'(PRECISION_BITS + 2))
      addend_shamt_o = unsigned'(signed'(PRECISION_BITS) + 3 - exponent_difference);
    // Addend-anchored case, saturated shift (product is only in the sticky bit)
    else
      addend_shamt_o = 0;
  end

  // Add the implicit bit to the addend's mantissa
  assign mantissa_c_o = {info_c.is_normal, operand_c.mantissa};
endmodule
