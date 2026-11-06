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
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from TransDot 599aaa5 src/fpnew_fma.sv: the module
// is renamed ucc_fma and is the UCC FU's datapath, FpFormat must be FP64, ucc_op_i is the FU's global opcode
// (ucc_pkg's map) and rnd_mode_i the rounding mode of the operations that round: RNE, RTZ, RDN, RUP or RMM, and codes
// 5-7, which FPnew would round with a don't-care, to nearest even (DPA-16 reads its bits 1-0 as given).
//
// FMA, ADD, SUB and MUL run on fpnew_fma's datapath, one operation per cycle, in FP64 or FP32. ADD and SUB are
// FPnew's ADD (1.0 * b +/- c), so a and b move to the b and c operands. An FP32 operation reads bits 31-0 of each
// operand and returns its result NaN-boxed, the result of fpnew_fma in FP32, on the FP64 datapath:
// - the significand product comes from DPA-16's 16 multiplier tiles (ucc_tiles, ucc_tilemul) instead of `*`, and
//   the FP32 significands go to bits 23-0 of its operands. Its operands are formed before the input register;
// - the FP32 operation's frame in the 3p+4-bit addition is an FP32 FMA's (3p'+4 = 76 bits), at bits 75-0 with zeros
//   above it, so the FP64 path's addend inversion, carry, sum selection and sign serve it unchanged;
// - its own control (ucc_fp32_ctrl, ucc_fp32_norm with its leading-zero counter, ucc_fp32_preround and
//   ucc_fp32_round, in FP32) handles FP32's exponents, special cases, normalization amount and rounding, and its
//   first cycle's results cross the middle register in the FP64 path's fields. The FP64 path has the same modules in
//   FP64.
//
// For an SFU opcode, operand a's low 32 bits are an FP32 x and the operation is one of the Vortex MUFU's approximate
// functions, in the opcode's low bits (rcp, rsqrt, ex2, lg2, sinpi, cospi, tanh). Its front end, ucc_sfu (the MUFU's
// range reduction and coefficient ROM), takes two cycles and then hands the input register one FMA in place of the
// operation issued that cycle (which is lost unless it is an SFU function too, whose own front end takes it; issue
// no other operation two cycles after an SFU function, and in_ready_o is clear for one then). The FP64 path
// evaluates the MUFU's quadratic: the tiles across the halves of a and b give 2^28 (a1 xl + a2 xl^2), with
// corrections for the coefficients' signs; the two's complement product is sign-extended into the adder, and c has
// no implicit bit. The FP64-normalized sum is rounded to FP32 (to nearest even) in the output cycle, and the result
// is that FP32 value NaN-boxed, five cycles after issue (FMAs: three).
//
// An INT32 opcode (0x00-0x3F) is an ALU operation or a multiply, of bits 31-0, and its result is zero-extended. The
// ALU's (ucc_int_alu, after the input register) read a and b from the operand register, which holds them unchanged
// for it. A multiply:
// it places a and b at bits 52-21 of the multiplier's operands, signed or not (ucc_tilemul corrects for the signs), and
// c as an addend whose exponents put its bit 0 at the product's bit 42 or 74; the result is bits 75-44, 107-76 or
// 107-44 of the sum, zero-extended (a wide product fills all 64 bits).
//
// FP min, max, neg, abs and compares (ucc_fp_noncomp) and conversions (ucc_fp_cast) are FPnew's own units, after the
// input register, and status_o carries their flags. DPA-16, the INT32 operations and the SFU's functions raise none.
// The FU has no divider.
//
// A DPA-16 opcode runs on TransDot's dpa16_core (ucc_dpa16), after the input register, whose operand register also
// holds bits 63-0 of DPA-16's a and b and its c: the rest of a and b (dpa_hi_i: the vectors' bits 255-64 and the
// block scales) has its own register, which nothing else reads. That register, the registered format and the core's
// three stage registers load only with a DPA-16 operation, so the FU's other operations do not toggle them. The
// multiplier's operand registers likewise load only with an operation that uses the product (the FMA path's, the
// SFU's FMA and INT32 multiplies), so the tiles stay still under the other operations.
//
// The FMA path's three cycles are split differently from fpnew_fma's, at the same latency: the input stage forms the
// product and aligns the addend, and the middle register holds both; the middle stage adds them (fpnew_fma's two
// sums), normalizes, and assembles the value before rounding, which the output register holds; the output cycle
// rounds it and assembles the result on its way to result_o. So the tiles and the tiled product have the whole input
// stage, and the rounding uses the cycle after the output register, which used to hold only the bypass mux.
//
// Every result skips the stages it does not need through a bypass mux in front of result_o: ALU and FP compare-unit
// results one cycle after issue, combinationally from the input register; multiplies and conversions two, from the
// middle stage's sum and the middle register's special result; FMAs three and SFU functions five, rounded from the
// output register; DPA-16 four, from the core's own output register. Only the operations that use the middle stage
// (the FMA path's, the SFU's FMA, multiplies and conversions) enter the middle register. When two results are due in
// the same cycle the younger operation's is returned and the older one's is lost. tag_o, mask_o and aux_o are the
// returned result's operation's. The bypass assumes out_ready_i stays set.
//
// Defining UCC_CHECK_ISSUE makes a breach of either issue rule a simulation error: an operation issued while
// in_ready_o is clear (the SFU's slot), and two results due in the same cycle (issue_lost and result_hidden).
//
// flush_i drops every operation in flight, the SFU front end's and DPA-16's included: no operation issued in or before
// the cycle flush_i is set returns a result after that cycle.

`include "common_cells/registers.svh"

module ucc_fma #(
  // The only configuration the FU's pipeline supports (one register per stage), checked below
  parameter fpnew_pkg::fp_format_e   FpFormat    = fpnew_pkg::FP64,
  parameter int unsigned             NumPipeRegs = 3,
  parameter fpnew_pkg::pipe_config_t PipeConfig  = fpnew_pkg::DISTRIBUTED,
  parameter type                     TagType     = logic,
  parameter type                     AuxType     = logic,
  // Do not change
  localparam int unsigned WIDTH = fpnew_pkg::fp_width(FpFormat),
  localparam int unsigned ExtRegEnaWidth = NumPipeRegs == 0 ? 1 : NumPipeRegs
) (
  input logic                      clk_i,
  input logic                      rst_ni,
  // Input signals
  input logic [2:0][WIDTH-1:0]     operands_i, // 3 operands
  input logic [1:0][ucc_pkg::DPA_HI-1:0] dpa_hi_i, // a's and b's {scales, vector bits 255-64}: only DPA-16 reads them
  input logic [2:0]                is_boxed_i, // 3 operands
  input fpnew_pkg::roundmode_e     rnd_mode_i,
  input logic [6:0]                ucc_op_i,   // the FU's global opcode (ucc_pkg)
  input TagType                    tag_i,
  input logic                      mask_i,
  input AuxType                    aux_i,
  // Input Handshake
  input  logic                     in_valid_i,
  output logic                     in_ready_o,
  input  logic                     flush_i,
  // Output signals
  output logic [WIDTH-1:0]         result_o,
  output fpnew_pkg::status_t       status_o,
  output logic                     extension_bit_o,
  output TagType                   tag_o,
  output logic                     mask_o,
  output AuxType                   aux_o,
  // Output handshake
  output logic                     out_valid_o,
  input  logic                     out_ready_i,
  // Indication of valid data in flight
  output logic                     busy_o,
  // External register enable override
  input  logic [ExtRegEnaWidth-1:0] reg_ena_i
);

  // ----------
  // Constants
  // ----------
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);
  localparam int unsigned BIAS     = fpnew_pkg::bias(FpFormat);
  // Precision bits 'p' include the implicit bit
  localparam int unsigned PRECISION_BITS = MAN_BITS + 1;
  // The lower 2p+3 bits of the internal FMA result will be needed for leading-zero detection
  localparam int unsigned LOWER_SUM_WIDTH  = 2 * PRECISION_BITS + 3;
  localparam int unsigned LZC_RESULT_WIDTH = $clog2(LOWER_SUM_WIDTH);
  // Internal exponent width of FMA must accomodate all meaningful exponent values in order to avoid
  // datapath leakage. This is either given by the exponent bits or the width of the LZC result.
  // In most reasonable FP formats the internal exponent will be wider than the LZC result.
  localparam int unsigned EXP_WIDTH = unsigned'(fpnew_pkg::maximum(EXP_BITS + 2, LZC_RESULT_WIDTH));
  // Shift amount width: maximum internal mantissa size is 3p+4 bits
  localparam int unsigned SHIFT_AMOUNT_WIDTH = $clog2(3 * PRECISION_BITS + 5);
  // Pipelines
  localparam NUM_INP_REGS = PipeConfig == fpnew_pkg::BEFORE
                            ? NumPipeRegs
                            : (PipeConfig == fpnew_pkg::DISTRIBUTED
                               ? ((NumPipeRegs + 1) / 3) // Second to get distributed regs
                               : 0); // no regs here otherwise
  localparam NUM_MID_REGS = PipeConfig == fpnew_pkg::INSIDE
                          ? NumPipeRegs
                          : (PipeConfig == fpnew_pkg::DISTRIBUTED
                             ? ((NumPipeRegs + 2) / 3) // First to get distributed regs
                             : 0); // no regs here otherwise
  localparam NUM_OUT_REGS = PipeConfig == fpnew_pkg::AFTER
                            ? NumPipeRegs
                            : (PipeConfig == fpnew_pkg::DISTRIBUTED
                               ? (NumPipeRegs / 3) // Last to get distributed regs
                               : 0); // no regs here otherwise
  // FP32: the precision and the adder frame (3p'+4 bits)
  localparam int unsigned P32   = ucc_pkg::PRECISION_BITS;
  localparam int unsigned FRAME = ucc_pkg::FRAME;
  // The FP32 frame sits this far up in the addend shifter, which keeps p sticky bits below the 3p+4-bit frame where an
  // FP32 FMA keeps p'
  localparam int unsigned HI32  = PRECISION_BITS - P32;
  // INT32: the integers' bit 0 in the multiplier's operands, their product's bit 0 in the sum, and the addend
  // exponents that put c's bit 0 at the product's bit 2 * INT_SHIFT (INT_LO, INT_WIDE) or 32 above it (INT_HI); with a
  // and b at exponent BIAS, c's bit 0 lands at the product's bit MAN_BITS + (c's exponent - BIAS)
  localparam int unsigned INT_SHIFT  = PRECISION_BITS - 32;
  localparam int unsigned INT_LSB    = 2 * INT_SHIFT + 2;
  localparam int unsigned INT_EXP_LO = BIAS + 2 * INT_SHIFT - MAN_BITS;
  localparam int unsigned INT_EXP_HI = INT_EXP_LO + 32;

  // The bypass latencies (ucc_pkg::unit_e), the SFU's slot and DPA-16's three stages assume one register per stage,
  // and the FP32, INT32 and SFU placements an FP64 datapath
  if (FpFormat != fpnew_pkg::FP64 || NumPipeRegs != 3 || PipeConfig != fpnew_pkg::DISTRIBUTED) begin : gen_config_check
    $fatal(1, "ucc_fma: FpFormat must be FP64, NumPipeRegs 3 and PipeConfig DISTRIBUTED");
  end

  // ----------------
  // Type definition
  // ----------------
  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;

  // --------------------
  // Multiplier operands
  // --------------------
  // The multiplier's operands are formed from the inputs and registered with them, so that in every mode only the
  // tiles' operand select (ucc_tiles) lies between the flip-flops and the tiles. Each holds the significand
  // fpnew_fma forms after its input register: the implicit bit of a normal value, and +1.0 for multiplicand a in ADD
  // operations. FP32: the significands at bits 23-0 of a and b, zeros above, so the product is at bits 47-0 and the
  // tiles above bit 23 multiply zeros.
  function automatic logic [PRECISION_BITS-1:0] significand(fp_t value, logic is_boxed);
    return {is_boxed && (value.exponent != '0) && (value.exponent != '1), value.mantissa};
  endfunction

  function automatic logic [P32-1:0] significand32(logic [ucc_pkg::WIDTH-1:0] value);
    logic [ucc_pkg::EXP_BITS-1:0] exponent;
    exponent = value[ucc_pkg::MAN_BITS +: ucc_pkg::EXP_BITS];
    return {(exponent != '0) && (exponent != '1), value[ucc_pkg::MAN_BITS-1:0]};
  endfunction

  // --------------
  // Opcode decode
  // --------------
  // The FMA datapath's controls, as fpnew_fma and the earlier modes take them. Every opcode also runs through that
  // datapath (an FMA where it is not an FMA-path operation), whose result is then not returned.
  ucc_pkg::unit_e        unit_d;
  fpnew_pkg::operation_e op_i;
  logic                  op_mod_i;
  logic                  fp32_i;   // an FP32 FMA-path operation of bits 31-0
  logic                  sfu_i;    // an SFU function of operands_i[0][31:0] (FP32)
  logic [2:0]            sfu_fn_i; // Vortex's INST_MUFU_* encoding
  logic                  int_i;    // an INT32 operation of bits 31-0 (ALU or multiply)
  logic [5:0]            int_op_i; // ucc_pkg's INT_* encoding
  logic                  dpa_mx8_d, dpa_fp4_d; // DPA-16's MXFP8 and FP4 (the opcode's bits 2-0)
  logic [1:0][ucc_pkg::DPA_HI-1:0] dpa_hi_d;   // a's and b's bits above 63, FP4's scales forced to 2^0
  logic [2:0][WIDTH-1:0] fma_operands;

  always_comb begin : dpa_scales
    dpa_hi_d = dpa_hi_i;
    if (dpa_fp4_d) for (int s = 0; s < 2; s++) dpa_hi_d[s][ucc_pkg::DPA_HI-1 -: 32] = {4{8'd127}};
  end

  always_comb begin : decode
    unit_d       = ucc_pkg::unit_of(ucc_op_i);
    fp32_i       = (unit_d == ucc_pkg::UNIT_FMA) & ucc_op_i[5];
    sfu_i        = (unit_d == ucc_pkg::UNIT_SFU);
    sfu_fn_i     = ucc_op_i[2:0];
    // Opcodes the map does not name are the ALU's reserved code 31, which returns 0
    int_i        = (unit_d inside {ucc_pkg::UNIT_ALU, ucc_pkg::UNIT_IMUL, ucc_pkg::UNIT_NONE});
    int_op_i     = (unit_d == ucc_pkg::UNIT_NONE) ? 6'd31 : ucc_op_i[5:0];
    op_i         = fpnew_pkg::FMADD;
    op_mod_i     = 1'b0;
    fma_operands = operands_i;
    if (unit_d == ucc_pkg::UNIT_FMA) begin
      unique case (ucc_op_i[4:0])
        ucc_pkg::FP_ADD: op_i = fpnew_pkg::ADD;
        ucc_pkg::FP_SUB: begin op_i = fpnew_pkg::ADD; op_mod_i = 1'b1; end
        ucc_pkg::FP_MUL: op_i = fpnew_pkg::MUL;
        default:         ;
      endcase
      // ADD and SUB: 1.0 * a +/- b
      if (op_i == fpnew_pkg::ADD) fma_operands = {operands_i[1], operands_i[0], operands_i[0]};
    end
  end

  // The rounding modes FPnew names for the FMA path and the conversions, RNE to RMM; 5-7 (ROD, an unnamed code and
  // DYN) round to nearest even. DPA-16 reads bits 1-0 as its FP8 subtypes, so it takes the input as given.
  fpnew_pkg::roundmode_e rnd_mode_d;

  assign rnd_mode_d = (rnd_mode_i <= fpnew_pkg::RMM || unit_d == ucc_pkg::UNIT_DPA) ? rnd_mode_i : fpnew_pkg::RNE;

  logic [PRECISION_BITS-1:0] mul_a_d, mul_b_d;

  always_comb begin : mul_operands
    logic                      one_a; // ADD and ADDS set multiplicand a to +1.0
    logic [PRECISION_BITS-1:0] a64, b64;
    logic [P32-1:0]            a32, b32;
    one_a   = (op_i == fpnew_pkg::ADD) || (op_i == fpnew_pkg::ADDS);
    a64     = one_a ? PRECISION_BITS'(1) << MAN_BITS : significand(fma_operands[0], is_boxed_i[0]);
    b64     = significand(fma_operands[1], is_boxed_i[1]);
    a32     = one_a ? P32'(1) << ucc_pkg::MAN_BITS : significand32(fma_operands[0][ucc_pkg::WIDTH-1:0]);
    b32     = significand32(fma_operands[1][ucc_pkg::WIDTH-1:0]);
    mul_a_d = fp32_i ? PRECISION_BITS'(a32) : a64;
    mul_b_d = fp32_i ? PRECISION_BITS'(b32) : b64;
    // INT32 multiplies: the integers at bits 52-21, their sign bits at bit 52
    if (unit_d == ucc_pkg::UNIT_IMUL) begin
      mul_a_d = {operands_i[0][31:0], {INT_SHIFT{1'b0}}};
      mul_b_d = {operands_i[1][31:0], {INT_SHIFT{1'b0}}};
    end
  end

  // INT32: a and b take 1.0's exponent (their significands are the multiplier's operands), and c the exponent that
  // aligns it with the result's bit 0 (bit 32 for INT_HI) and, with bit 2 of int_op_i, its bits 31-0 as significand
  logic [2:0][WIDTH-1:0] int_operands;

  always_comb begin : int_operand_placement
    logic add_c;
    add_c           = int_op_i[5] & int_op_i[2];
    int_operands[0] = {1'b0, EXP_BITS'(BIAS), MAN_BITS'(0)};
    int_operands[1] = {1'b0, EXP_BITS'(BIAS), MAN_BITS'(0)};
    int_operands[2] = {1'b0, EXP_BITS'((int_op_i[4:3] == ucc_pkg::INT_HI) ? INT_EXP_HI : INT_EXP_LO),
                       MAN_BITS'(add_c ? operands_i[2][31:0] : 32'd0)};
  end

  // -------------
  // SFU front end
  // -------------
  // Two cycles after an SFU operation is issued, its FMA takes the input register.
  logic                      sfu_valid, sfu_special, sfu_zero_sign;
  logic [2:0][WIDTH-1:0]     sfu_operands;
  logic [PRECISION_BITS-1:0] sfu_mul_a, sfu_mul_b;
  logic [31:0]               sfu_special_result;

  ucc_sfu i_sfu (
    .clk_i,
    .rst_ni,
    .flush_i,
    .valid_i          ( in_valid_i & sfu_i       ),
    .fn_i             ( sfu_fn_i                 ),
    .x_i              ( operands_i[0][31:0]      ),
    .valid_o          ( sfu_valid                ),
    .operands_o       ( sfu_operands             ),
    .mul_a_o          ( sfu_mul_a                ),
    .mul_b_o          ( sfu_mul_b                ),
    .special_o        ( sfu_special              ),
    .special_result_o ( sfu_special_result       ),
    .zero_sign_o      ( sfu_zero_sign            )
  );

  // The SFU function's tag, mask and aux, delayed with its front end so that its FMA carries them
  TagType [1:0] sfu_tag_q;
  logic   [1:0] sfu_mask_q;
  AuxType [1:0] sfu_aux_q;

  `FF(sfu_tag_q,  {sfu_tag_q[0], tag_i},   '0)
  `FF(sfu_mask_q, {sfu_mask_q[0], mask_i}, '0)
  `FF(sfu_aux_q,  {sfu_aux_q[0], aux_i},   '0)

  // ---------------
  // Input pipeline
  // ---------------
  // Input pipeline signals, index i holds signal after i register stages
  logic                  [0:NUM_INP_REGS][2:0][WIDTH-1:0] inp_pipe_operands_q;
  logic                  [0:NUM_INP_REGS][2:0]            inp_pipe_is_boxed_q;
  fpnew_pkg::roundmode_e [0:NUM_INP_REGS]                 inp_pipe_rnd_mode_q;
  fpnew_pkg::operation_e [0:NUM_INP_REGS]                 inp_pipe_op_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_op_mod_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_fp32_q;
  logic         [0:NUM_INP_REGS][PRECISION_BITS-1:0]      inp_pipe_mul_a_q, inp_pipe_mul_b_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_sfu_q, inp_pipe_sfu_special_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_dpa_q; // DPA-16: the tiles take its operands
  logic                  [0:NUM_INP_REGS]                 inp_pipe_prod_q; // the operation uses the product
  logic                  [0:NUM_INP_REGS]                 inp_pipe_sfu_zero_sign_q;
  logic                  [0:NUM_INP_REGS][31:0]           inp_pipe_sfu_result_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_int_q;
  logic                  [0:NUM_INP_REGS][5:0]            inp_pipe_int_op_q;
  logic                  [0:NUM_INP_REGS][6:0]            inp_pipe_ucc_op_q;
  ucc_pkg::unit_e        [0:NUM_INP_REGS]                 inp_pipe_unit_q;
  logic         [0:NUM_INP_REGS][1:0][ucc_pkg::DPA_HI-1:0] inp_pipe_dpa_hi_q;
  logic                  [0:NUM_INP_REGS][2:0]            inp_pipe_dpa_fmt_q; // DPA-16: the core's format
  logic                  [0:NUM_INP_REGS]                 inp_pipe_dpa_mx8_q; // DPA-16: MXFP8's scales
  TagType                [0:NUM_INP_REGS]                 inp_pipe_tag_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_mask_q;
  AuxType                [0:NUM_INP_REGS]                 inp_pipe_aux_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_valid_q;
  // Ready signal is combinatorial for all stages
  logic [0:NUM_INP_REGS] inp_pipe_ready;

  // Input stage: First element of pipeline is taken from inputs (or the SFU front end's FMA; INT32 multiply operands
  // placed). An INT32 ALU operation registers a and b unchanged, for the ALU.
  assign inp_pipe_operands_q[0]       = sfu_valid ? sfu_operands : ((int_i & int_op_i[5]) ? int_operands : fma_operands);
  assign inp_pipe_is_boxed_q[0]       = (sfu_valid | int_i) ? 3'b111 : is_boxed_i;
  assign inp_pipe_rnd_mode_q[0]       = (sfu_valid | int_i) ? fpnew_pkg::RNE : rnd_mode_d;
  assign inp_pipe_op_q[0]             = (sfu_valid | int_i) ? fpnew_pkg::FMADD : op_i;
  assign inp_pipe_op_mod_q[0]         = op_mod_i & ~sfu_valid & ~int_i;
  assign inp_pipe_fp32_q[0]           = fp32_i & ~sfu_valid & ~int_i;
  assign inp_pipe_mul_a_q[0]          = sfu_valid ? sfu_mul_a : mul_a_d;
  assign inp_pipe_mul_b_q[0]          = sfu_valid ? sfu_mul_b : mul_b_d;
  assign inp_pipe_sfu_q[0]            = sfu_valid;
  // registered, so that the tiles' operand select does not wait for the opcode's decode after the register
  assign inp_pipe_dpa_q[0]            = (unit_d == ucc_pkg::UNIT_DPA) & ~sfu_valid;
  // The FMA path's operations, the SFU's FMA and INT32 multiplies: only these load the multiplier's operands
  assign inp_pipe_prod_q[0]           = sfu_valid | (unit_d inside {ucc_pkg::UNIT_FMA, ucc_pkg::UNIT_IMUL});
  assign inp_pipe_sfu_special_q[0]    = sfu_special;
  assign inp_pipe_sfu_zero_sign_q[0]  = sfu_zero_sign;
  assign inp_pipe_sfu_result_q[0]     = sfu_special_result;
  assign inp_pipe_int_q[0]            = int_i & ~sfu_valid;
  assign inp_pipe_int_op_q[0]         = int_op_i;
  // The SFU's FMA is an FP64 FMA to the units after the input register; its unit is registered with the opcode, so
  // that nothing after the register decodes the opcode again
  assign inp_pipe_ucc_op_q[0]         = sfu_valid ? {2'b10, ucc_pkg::FP_FMA} : ucc_op_i;
  assign inp_pipe_unit_q[0]           = sfu_valid ? ucc_pkg::UNIT_FMA : unit_d;
  // DPA-16's two formats of the FU's own, mapped onto the core's paths before the register, so that the core and its
  // tiles see a registered format: MXFP8 (6) is the core's FP8 with its scale flag, FP4 (7) its MXFP4 with every
  // scale forced to 2^0 (E8M0 127). Only DPA-16 reads these, and their registers load only with it.
  assign dpa_mx8_d                    = ucc_op_i[2:0] == 3'd6;
  assign dpa_fp4_d                    = ucc_op_i[2:0] == 3'd7;
  assign inp_pipe_dpa_fmt_q[0]        = dpa_mx8_d ? 3'd3 : (dpa_fp4_d ? 3'd5 : ucc_op_i[2:0]);
  assign inp_pipe_dpa_mx8_q[0]        = dpa_mx8_d;
  assign inp_pipe_dpa_hi_q[0]         = dpa_hi_d;
  assign inp_pipe_tag_q[0]            = sfu_valid ? sfu_tag_q[1]  : tag_i;
  assign inp_pipe_mask_q[0]           = sfu_valid ? sfu_mask_q[1] : mask_i;
  assign inp_pipe_aux_q[0]            = sfu_valid ? sfu_aux_q[1]  : aux_i;
  assign inp_pipe_valid_q[0]          = in_valid_i | sfu_valid;
  // Input stage: Propagate pipeline ready signal to updtream circuitry. The SFU's FMA takes the input register in
  // its slot, so the input is not ready then for any operation but an SFU function (whose own front end takes it).
  assign in_ready_o = inp_pipe_ready[0] & ~(sfu_valid & ~sfu_i);
  // Generate the register stages
  for (genvar i = 0; i < NUM_INP_REGS; i++) begin : gen_input_pipeline
    // Internal register enable for this stage
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline:
    // 1. if the next stage is ready for our data
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it
    assign inp_pipe_ready[i] = inp_pipe_ready[i+1] | ~inp_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal
    `FFLARNC(inp_pipe_valid_q[i+1], inp_pipe_valid_q[i], inp_pipe_ready[i], flush_i, 1'b0, clk_i, rst_ni)
    // Enable register if pipleine ready and a valid data item is present
    assign reg_ena = (inp_pipe_ready[i] & inp_pipe_valid_q[i]) | reg_ena_i[i];
    // Generate the pipeline registers within the stages, use enable-registers
    `FFL(inp_pipe_operands_q[i+1], inp_pipe_operands_q[i], reg_ena, '0)
    `FFL(inp_pipe_is_boxed_q[i+1], inp_pipe_is_boxed_q[i], reg_ena, '0)
    `FFL(inp_pipe_rnd_mode_q[i+1], inp_pipe_rnd_mode_q[i], reg_ena, fpnew_pkg::RNE)
    `FFL(inp_pipe_op_q[i+1],       inp_pipe_op_q[i],       reg_ena, fpnew_pkg::FMADD)
    `FFL(inp_pipe_op_mod_q[i+1],   inp_pipe_op_mod_q[i],   reg_ena, '0)
    `FFL(inp_pipe_fp32_q[i+1],     inp_pipe_fp32_q[i],     reg_ena, '0)
    // Load with an operation that uses the product only, so that the tiles do not toggle under the others
    `FFL(inp_pipe_mul_a_q[i+1],    inp_pipe_mul_a_q[i],    reg_ena & inp_pipe_prod_q[i], '0)
    `FFL(inp_pipe_mul_b_q[i+1],    inp_pipe_mul_b_q[i],    reg_ena & inp_pipe_prod_q[i], '0)
    `FFL(inp_pipe_prod_q[i+1],     inp_pipe_prod_q[i],     reg_ena, '0)
    `FFL(inp_pipe_sfu_q[i+1],            inp_pipe_sfu_q[i],            reg_ena, '0)
    `FFL(inp_pipe_dpa_q[i+1],            inp_pipe_dpa_q[i],            reg_ena, '0)
    `FFL(inp_pipe_sfu_special_q[i+1],    inp_pipe_sfu_special_q[i],    reg_ena, '0)
    `FFL(inp_pipe_sfu_zero_sign_q[i+1],  inp_pipe_sfu_zero_sign_q[i],  reg_ena, '0)
    `FFL(inp_pipe_sfu_result_q[i+1],     inp_pipe_sfu_result_q[i],     reg_ena, '0)
    `FFL(inp_pipe_int_q[i+1],            inp_pipe_int_q[i],            reg_ena, '0)
    `FFL(inp_pipe_int_op_q[i+1],         inp_pipe_int_op_q[i],         reg_ena, '0)
    `FFL(inp_pipe_ucc_op_q[i+1],         inp_pipe_ucc_op_q[i],         reg_ena, '0)
    `FFL(inp_pipe_unit_q[i+1],           inp_pipe_unit_q[i],           reg_ena, ucc_pkg::UNIT_NONE)
    // Load with a DPA-16 operation only: nothing else reads them
    `FFL(inp_pipe_dpa_fmt_q[i+1],        inp_pipe_dpa_fmt_q[i],        reg_ena & inp_pipe_dpa_q[i], '0)
    `FFL(inp_pipe_dpa_mx8_q[i+1],        inp_pipe_dpa_mx8_q[i],        reg_ena & inp_pipe_dpa_q[i], '0)
    `FFL(inp_pipe_dpa_hi_q[i+1],         inp_pipe_dpa_hi_q[i],         reg_ena & inp_pipe_dpa_q[i], '0)
    `FFL(inp_pipe_tag_q[i+1],      inp_pipe_tag_q[i],      reg_ena, TagType'('0))
    `FFL(inp_pipe_mask_q[i+1],     inp_pipe_mask_q[i],     reg_ena, '0)
    `FFL(inp_pipe_aux_q[i+1],      inp_pipe_aux_q[i],      reg_ena, AuxType'('0))
  end

  // -----------------
  // Input processing
  // -----------------
  logic [2:0][WIDTH-1:0]     operands_q;
  logic                      sfu;      // this cycle's operation is an SFU operation's FMA
  logic                      int_mode; // this cycle's operation is an INT32 operation
  logic [5:0]                int_op;

  assign sfu      = inp_pipe_sfu_q[NUM_INP_REGS];
  assign int_mode = inp_pipe_int_q[NUM_INP_REGS];
  assign int_op   = inp_pipe_int_op_q[NUM_INP_REGS];

  // The registered opcode and its unit, for the units after the input register
  logic [6:0]     ucc_op_q;
  ucc_pkg::unit_e unit_q;

  assign ucc_op_q = inp_pipe_ucc_op_q[NUM_INP_REGS];
  assign unit_q   = inp_pipe_unit_q[NUM_INP_REGS];

  // The operands as fpnew_fma registers them: signs and exponents as registered, mantissas from the multiplier's
  // operands (ADD replaces a anyway)
  assign operands_q[0] = {inp_pipe_operands_q[NUM_INP_REGS][0][WIDTH-1:MAN_BITS],
                          inp_pipe_mul_a_q[NUM_INP_REGS][MAN_BITS-1:0]};
  assign operands_q[1] = {inp_pipe_operands_q[NUM_INP_REGS][1][WIDTH-1:MAN_BITS],
                          inp_pipe_mul_b_q[NUM_INP_REGS][MAN_BITS-1:0]};
  assign operands_q[2] = inp_pipe_operands_q[NUM_INP_REGS][2];

  // ------------
  // FP64 control
  // ------------
  // fpnew_fma's input processing in FP64, as FP32's (ucc_fp32_ctrl): classification, operation selection, special
  // cases, exponents, the addend's shift amount and the normalization's case. The addend's sticky bit comes from the
  // shifter, in both formats.
  logic                          effective_subtraction, tentative_sign, use_lzc;
  logic signed [EXP_WIDTH-1:0]   exponent; // the product's if use_lzc, else the tentative exponent
  logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt;
  logic [PRECISION_BITS-1:0]     ctrl_mantissa_c, mantissa_c;
  logic                          result_is_special;
  fp_t                           special_result;
  fpnew_pkg::status_t            special_status;

  ucc_fp32_ctrl #(
    .FpFormat ( FpFormat )
  ) i_ctrl (
    .operands_i              ( operands_q                        ),
    .is_boxed_i              ( inp_pipe_is_boxed_q[NUM_INP_REGS] ),
    .rnd_mode_i              ( inp_pipe_rnd_mode_q[NUM_INP_REGS] ),
    .op_i                    ( inp_pipe_op_q[NUM_INP_REGS]       ),
    .op_mod_i                ( inp_pipe_op_mod_q[NUM_INP_REGS]   ),
    .mantissa_c_o            ( ctrl_mantissa_c                   ),
    .effective_subtraction_o ( effective_subtraction             ),
    .tentative_sign_o        ( tentative_sign                    ),
    .use_lzc_o               ( use_lzc                           ),
    .exponent_o              ( exponent                          ),
    .addend_shamt_o          ( addend_shamt                      ),
    .result_is_special_o     ( result_is_special                 ),
    .special_result_o        ( special_result                    ),
    .special_status_o        ( special_status                    )
  );

  // The addend's significand (the SFU's and INT32's c have no implicit bit)
  assign mantissa_c = {ctrl_mantissa_c[MAN_BITS] & ~sfu & ~int_mode, ctrl_mantissa_c[MAN_BITS-1:0]};

  // ------------
  // FP32 control
  // ------------
  // fpnew_fma's input processing in FP32, for an FP32 operation's bits 31-0. Its results cross the middle register in
  // the FP64 path's fields, so the middle stage's adder, sum selection and sign serve both formats.
  logic                                   fp32;
  logic [2:0][ucc_pkg::WIDTH-1:0]         fp32_operands;
  logic [P32-1:0]                         fp32_mantissa_c;
  logic                                   fp32_eff_sub, fp32_tentative_sign, fp32_use_lzc, fp32_special;
  logic signed [ucc_pkg::EXP_WIDTH-1:0]   fp32_exponent;
  logic [ucc_pkg::SHIFT_AMOUNT_WIDTH-1:0] fp32_addend_shamt;
  logic [ucc_pkg::WIDTH-1:0]              fp32_special_result;
  fpnew_pkg::status_t                     fp32_special_status;

  assign fp32 = inp_pipe_fp32_q[NUM_INP_REGS];

  // a and b: sign and exponent as registered, mantissa from the multiplier's operands
  assign fp32_operands[0] = {inp_pipe_operands_q[NUM_INP_REGS][0][ucc_pkg::WIDTH-1:ucc_pkg::MAN_BITS],
                             inp_pipe_mul_a_q[NUM_INP_REGS][ucc_pkg::MAN_BITS-1:0]};
  assign fp32_operands[1] = {inp_pipe_operands_q[NUM_INP_REGS][1][ucc_pkg::WIDTH-1:ucc_pkg::MAN_BITS],
                             inp_pipe_mul_b_q[NUM_INP_REGS][ucc_pkg::MAN_BITS-1:0]};
  assign fp32_operands[2] = inp_pipe_operands_q[NUM_INP_REGS][2][ucc_pkg::WIDTH-1:0];

  ucc_fp32_ctrl i_ctrl32 (
    .operands_i              ( fp32_operands                     ),
    .is_boxed_i              ( '1                                ),
    .rnd_mode_i              ( inp_pipe_rnd_mode_q[NUM_INP_REGS] ),
    .op_i                    ( inp_pipe_op_q[NUM_INP_REGS]       ),
    .op_mod_i                ( inp_pipe_op_mod_q[NUM_INP_REGS]   ),
    .mantissa_c_o            ( fp32_mantissa_c                   ),
    .effective_subtraction_o ( fp32_eff_sub                      ),
    .tentative_sign_o        ( fp32_tentative_sign               ),
    .use_lzc_o               ( fp32_use_lzc                      ),
    .exponent_o              ( fp32_exponent                     ),
    .addend_shamt_o          ( fp32_addend_shamt                 ),
    .result_is_special_o     ( fp32_special                      ),
    .special_result_o        ( fp32_special_result               ),
    .special_status_o        ( fp32_special_status               )
  );

  // ------------------
  // Product data path
  // ------------------
  // Mantissa multiplier (a*b) from the registered operands, on DPA-16's 16 tiles (ucc_tiles), which every operation but
  // DPA-16 lends to this product (ucc_tilemul: the tiles' products, two strips and the sign corrections). SFU:
  // a = xl^2 * 2^24 + xl * 2^4, b = a1 * 2^24 + a2 * 2^4, and only the tiles across the halves are on. INT32: a and b
  // are signed as int_op's bits 0 and 1 say.
  logic [PRECISION_BITS-1:0]   mul_a;
  logic [2*PRECISION_BITS-1:0] product; // the p*p product is 2p bits wide
  logic [15:0][15:0]           dpa_ta, dpa_tb;
  logic                        dpa_full, dpa_fp8, dpa_fp4;
  logic [15:0][23:0]           tile_prod;
  logic [15:0][3:0][7:0]       tile_dprod;

  assign mul_a = inp_pipe_mul_a_q[NUM_INP_REGS];

  ucc_tiles i_tiles (
    .dpa_i      ( inp_pipe_dpa_q[NUM_INP_REGS]     ),
    .dpa_ta_i   ( dpa_ta                           ),
    .dpa_tb_i   ( dpa_tb                           ),
    .dpa_full_i ( dpa_full                         ),
    .dpa_fp8_i  ( dpa_fp8                          ),
    .dpa_fp4_i  ( dpa_fp4                          ),
    .a_i        ( mul_a                            ),
    .b_i        ( inp_pipe_mul_b_q[NUM_INP_REGS]   ),
    .sfu_i      ( sfu                              ),
    .prod_o     ( tile_prod                        ),
    .dprod_o    ( tile_dprod                       )
  );

  ucc_tilemul i_mul (
    .tile_p_i   ( tile_prod                         ),
    .a_i        ( mul_a                             ),
    .b_i        ( inp_pipe_mul_b_q[NUM_INP_REGS]    ),
    .sfu_i      ( sfu                               ),
    .a_signed_i ( int_mode & int_op[5] & int_op[0]  ),
    .b_signed_i ( int_mode & int_op[5] & int_op[1]  ),
    .p_o        ( product                           )
  );

  // INT32 ALU, from the operand register's bits 31-0
  logic [31:0] int_alu_result;

  ucc_int_alu i_int_alu (
    .a_i  ( inp_pipe_operands_q[NUM_INP_REGS][0][31:0] ),
    .b_i  ( inp_pipe_operands_q[NUM_INP_REGS][1][31:0] ),
    .op_i ( int_op[4:0]                                ),
    .y_o  ( int_alu_result                             )
  );

  // FP min, max, neg, abs and compares and conversions, from the registered operands a and b, with FPnew's flags
  logic [WIDTH-1:0]   noncomp_result, cast_result;
  fpnew_pkg::status_t noncomp_status, cast_status;

  ucc_fp_noncomp i_fp_noncomp (
    .clk_i,
    .rst_ni,
    .a_i      ( inp_pipe_operands_q[NUM_INP_REGS][0] ),
    .b_i      ( inp_pipe_operands_q[NUM_INP_REGS][1] ),
    .fp32_i   ( ucc_op_q[5]                          ),
    .func_i   ( ucc_op_q[4:0]                        ),
    .result_o ( noncomp_result                       ),
    .status_o ( noncomp_status                       )
  );

  ucc_fp_cast i_fp_cast (
    .clk_i,
    .rst_ni,
    .a_i        ( inp_pipe_operands_q[NUM_INP_REGS][0] ),
    .fp32_i     ( ucc_op_q[5]                          ),
    .func_i     ( ucc_op_q[4:0]                        ),
    .rnd_mode_i ( inp_pipe_rnd_mode_q[NUM_INP_REGS]    ),
    .result_o   ( cast_result                          ),
    .status_o   ( cast_status                          )
  );

  // DPA-16, from the registered operands: bits 63-0 of a and b and c's bits 31-0 in the operand register, the rest of
  // a and b in their own. Its result leaves the core's output register three cycles later (dpa_valid_q[2]), and each
  // of the core's stage registers loads only with the operation in it.
  logic [31:0] dpa_result;
  logic [2:0]  dpa_rm, dpa_valid_q;
  logic        dpa_in; // a DPA-16 operation in the input register

  assign dpa_rm = inp_pipe_rnd_mode_q[NUM_INP_REGS];
  assign dpa_in = inp_pipe_valid_q[NUM_INP_REGS] & (unit_q == ucc_pkg::UNIT_DPA);

  ucc_dpa16 i_dpa16 (
    .clk_i,
    .rst_ni,
    .en_i   ( {dpa_valid_q[1:0], dpa_in}                                                ),
    .fmt_i  ( inp_pipe_dpa_fmt_q[NUM_INP_REGS]                                          ),
    .mx8_i  ( inp_pipe_dpa_mx8_q[NUM_INP_REGS]                                          ),
    .e5m2_i ( dpa_rm[1:0]                                                               ),
    .a_i    ( {inp_pipe_dpa_hi_q[NUM_INP_REGS][0], inp_pipe_operands_q[NUM_INP_REGS][0]} ),
    .b_i    ( {inp_pipe_dpa_hi_q[NUM_INP_REGS][1], inp_pipe_operands_q[NUM_INP_REGS][1]} ),
    .c_i    ( inp_pipe_operands_q[NUM_INP_REGS][2][31:0]                                 ),
    .d_o    ( dpa_result                                                                ),
    .ta_o     ( dpa_ta     ),
    .tb_o     ( dpa_tb     ),
    .m_full_o ( dpa_full   ),
    .m_fp8_o  ( dpa_fp8    ),
    .m_fp4_o  ( dpa_fp4    ),
    .tprod_i  ( tile_prod  ),
    .dprod_i  ( tile_dprod )
  );

  // flush_i drops the DPA-16 operations in flight, as it does the other stages' (the core's registers hold data only)
  `FF(dpa_valid_q, {dpa_valid_q[1:0], dpa_in} & {3{~flush_i}}, '0)

  // DPA-16's tag, mask and aux, which travel with its result
  TagType [2:0] dpa_tag_q;
  logic   [2:0] dpa_mask_q;
  AuxType [2:0] dpa_aux_q;

  `FF(dpa_tag_q,  {dpa_tag_q[1:0],  inp_pipe_tag_q[NUM_INP_REGS]},  '0)
  `FF(dpa_mask_q, {dpa_mask_q[1:0], inp_pipe_mask_q[NUM_INP_REGS]}, '0)
  `FF(dpa_aux_q,  {dpa_aux_q[1:0],  inp_pipe_aux_q[NUM_INP_REGS]},  '0)

  // The product crosses the middle register as it is; the middle stage places it in the adder's frame.

  // -----------------
  // Addend data path
  // -----------------
  logic [3*PRECISION_BITS+3:0] addend_after_shift;  // upper 3p+4 bits are needed to go on
  logic [PRECISION_BITS-1:0]   addend_sticky_bits;  // up to p bit of shifted addend are sticky
  logic                        sticky_before_add;   // they are compressed into a single sticky bit

  // In parallel, the addend is right-shifted according to the exponent difference. Up to p bits
  // are shifted out and compressed into a sticky bit.
  // BEFORE THE SHIFT:
  // | mantissa_c | 000..000 |
  //  <-    p   -> <- 3p+4 ->
  // AFTER THE SHIFT:
  // | 000..........000 | mantissa_c | 000...............0GR |  sticky bits  |
  //  <- addend_shamt -> <-    p   -> <- 2p+4-addend_shamt -> <-  up to p  ->
  //
  // FP32: the addend is shifted the same way in its own frame, which sits HI32 bits higher in the shifter than in the
  // adder, so that the bits it shifts out (up to p') land in the FP64 path's sticky bits, which are 0 below them.
  logic [4*PRECISION_BITS+3:0] addend_placed, addend_aligned;

  always_comb begin : addend_placement
    addend_placed = (4*PRECISION_BITS+4)'(mantissa_c) << (3 * PRECISION_BITS + 4);
    if (fp32) begin
      addend_placed                      = '0;
      addend_placed[HI32 + FRAME +: P32] = fp32_mantissa_c;
    end
  end

  ucc_shift #(
    .WIDTH       ( 4 * PRECISION_BITS + 4 ),
    .SHAMT_WIDTH ( SHIFT_AMOUNT_WIDTH     ),
    .LEFT        ( 1'b0                   )
  ) i_addend_shift (
    .data_i  ( addend_placed                                                   ),
    .shamt_i ( fp32 ? SHIFT_AMOUNT_WIDTH'(fp32_addend_shamt) : addend_shamt ),
    .data_o  ( addend_aligned                                                  )
  );

  assign {addend_after_shift, addend_sticky_bits} = addend_aligned;

  assign sticky_before_add     = (| addend_sticky_bits);
  // assign addend_after_shift[0] = sticky_before_add;

  // The aligned addend crosses the middle register; the middle stage inverts it for subtractions and adds.

  // ---------------
  // Internal pipeline
  // ---------------
  // Pipeline output signals as non-arrays
  logic                          effective_subtraction_q;
  logic                          use_lzc_q;
  logic signed [EXP_WIDTH-1:0]   exponent_q;
  logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt_q;
  logic                          sticky_before_add_q;
  logic [2*PRECISION_BITS-1:0]   product_q;
  logic [3*PRECISION_BITS+3:0]   addend_after_shift_q;
  logic                          tentative_sign_q;
  fpnew_pkg::roundmode_e         rnd_mode_q;
  logic                          result_is_special_q;
  fp_t                           special_result_q;
  fpnew_pkg::status_t            special_status_q;
  // Internal pipeline signals, index i holds signal after i register stages
  logic                  [0:NUM_MID_REGS]                         mid_pipe_eff_sub_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_use_lzc_q;
  logic signed           [0:NUM_MID_REGS][EXP_WIDTH-1:0]          mid_pipe_exponent_q;
  logic                  [0:NUM_MID_REGS][SHIFT_AMOUNT_WIDTH-1:0] mid_pipe_add_shamt_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_sticky_q;
  logic                  [0:NUM_MID_REGS][2*PRECISION_BITS-1:0]   mid_pipe_product_q;
  logic                  [0:NUM_MID_REGS][3*PRECISION_BITS+3:0]   mid_pipe_addend_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_tent_sign_q;
  fpnew_pkg::roundmode_e [0:NUM_MID_REGS]                         mid_pipe_rnd_mode_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_res_is_spec_q;
  fp_t                   [0:NUM_MID_REGS]                         mid_pipe_spec_res_q;
  fpnew_pkg::status_t    [0:NUM_MID_REGS]                         mid_pipe_spec_stat_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_fp32_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_sfu_q, mid_pipe_sfu_zero_sign_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_int_q;
  logic                  [0:NUM_MID_REGS][2:0]                    mid_pipe_int_sel_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_cvt_q, mid_pipe_fma_q;
  TagType                [0:NUM_MID_REGS]                         mid_pipe_tag_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_mask_q;
  AuxType                [0:NUM_MID_REGS]                         mid_pipe_aux_q;
  logic                  [0:NUM_MID_REGS]                         mid_pipe_valid_q;
  // Ready signal is combinatorial for all stages
  logic [0:NUM_MID_REGS] mid_pipe_ready;

  // Input stage: First element of pipeline is taken from upstream logic. An FP32 operation's control takes the FP64
  // path's fields: its exponent (signed) and shift amount widened, which the middle stage narrows again, and its
  // special result in the low 32 bits.
  assign mid_pipe_eff_sub_q[0]     = fp32 ? fp32_eff_sub : effective_subtraction;
  assign mid_pipe_use_lzc_q[0]     = fp32 ? fp32_use_lzc : use_lzc;
  assign mid_pipe_exponent_q[0]    = fp32 ? EXP_WIDTH'(fp32_exponent) : exponent;
  assign mid_pipe_add_shamt_q[0]   = fp32 ? SHIFT_AMOUNT_WIDTH'(fp32_addend_shamt) : addend_shamt;
  assign mid_pipe_sticky_q[0]      = sticky_before_add;
  assign mid_pipe_product_q[0]     = product;
  assign mid_pipe_addend_q[0]      = addend_after_shift;
  assign mid_pipe_tent_sign_q[0]   = fp32 ? fp32_tentative_sign : tentative_sign;
  assign mid_pipe_rnd_mode_q[0]    = inp_pipe_rnd_mode_q[NUM_INP_REGS];
  // SFU: the front end's special value goes in the low 32 bits of the FP64 special result
  assign mid_pipe_res_is_spec_q[0] = sfu ? inp_pipe_sfu_special_q[NUM_INP_REGS] : fp32 ? fp32_special : result_is_special;
  // A conversion's result and flags also cross the middle register here
  assign mid_pipe_spec_res_q[0]    = (unit_q == ucc_pkg::UNIT_CVT) ? fp_t'(cast_result)
                                   : sfu  ? fp_t'(WIDTH'(inp_pipe_sfu_result_q[NUM_INP_REGS]))
                                   : fp32 ? fp_t'(WIDTH'(fp32_special_result)) : special_result;
  assign mid_pipe_spec_stat_q[0]   = (unit_q == ucc_pkg::UNIT_CVT) ? cast_status
                                   : sfu  ? '0 : fp32 ? fp32_special_status : special_status;
  assign mid_pipe_fp32_q[0]        = fp32;
  assign mid_pipe_sfu_q[0]           = sfu;
  assign mid_pipe_sfu_zero_sign_q[0] = inp_pipe_sfu_zero_sign_q[NUM_INP_REGS];
  assign mid_pipe_int_q[0]           = int_mode;
  assign mid_pipe_int_sel_q[0]       = int_op[5:3];
  assign mid_pipe_cvt_q[0]           = (unit_q == ucc_pkg::UNIT_CVT);
  assign mid_pipe_fma_q[0]           = (unit_q == ucc_pkg::UNIT_FMA); // the FMA path's own result (and the SFU's)
  assign mid_pipe_tag_q[0]         = inp_pipe_tag_q[NUM_INP_REGS];
  assign mid_pipe_mask_q[0]        = inp_pipe_mask_q[NUM_INP_REGS];
  assign mid_pipe_aux_q[0]         = inp_pipe_aux_q[NUM_INP_REGS];
  // Only the operations that use the middle stage enter the middle register: ALU and compare-unit results leave
  // from the input register, and DPA-16 has its own registers
  assign mid_pipe_valid_q[0]       = inp_pipe_valid_q[NUM_INP_REGS] &
                                     (unit_q inside {ucc_pkg::UNIT_FMA, ucc_pkg::UNIT_IMUL, ucc_pkg::UNIT_CVT});
  // Input stage: Propagate pipeline ready signal to input pipe
  assign inp_pipe_ready[NUM_INP_REGS] = mid_pipe_ready[0];

  // Generate the register stages
  for (genvar i = 0; i < NUM_MID_REGS; i++) begin : gen_inside_pipeline
    // Internal register enable for this stage
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline:
    // 1. if the next stage is ready for our data
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it
    assign mid_pipe_ready[i] = mid_pipe_ready[i+1] | ~mid_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal
    `FFLARNC(mid_pipe_valid_q[i+1], mid_pipe_valid_q[i], mid_pipe_ready[i], flush_i, 1'b0, clk_i, rst_ni)
    // Enable register if pipleine ready and a valid data item is present
    assign reg_ena = (mid_pipe_ready[i] & mid_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers
    `FFL(mid_pipe_eff_sub_q[i+1],     mid_pipe_eff_sub_q[i],     reg_ena, '0)
    `FFL(mid_pipe_use_lzc_q[i+1],     mid_pipe_use_lzc_q[i],     reg_ena, '0)
    `FFL(mid_pipe_exponent_q[i+1],    mid_pipe_exponent_q[i],    reg_ena, '0)
    `FFL(mid_pipe_add_shamt_q[i+1],   mid_pipe_add_shamt_q[i],   reg_ena, '0)
    `FFL(mid_pipe_sticky_q[i+1],      mid_pipe_sticky_q[i],      reg_ena, '0)
    `FFL(mid_pipe_product_q[i+1],     mid_pipe_product_q[i],     reg_ena, '0)
    `FFL(mid_pipe_addend_q[i+1],      mid_pipe_addend_q[i],      reg_ena, '0)
    `FFL(mid_pipe_tent_sign_q[i+1],   mid_pipe_tent_sign_q[i],   reg_ena, '0)
    `FFL(mid_pipe_rnd_mode_q[i+1],    mid_pipe_rnd_mode_q[i],    reg_ena, fpnew_pkg::RNE)
    `FFL(mid_pipe_res_is_spec_q[i+1], mid_pipe_res_is_spec_q[i], reg_ena, '0)
    `FFL(mid_pipe_spec_res_q[i+1],    mid_pipe_spec_res_q[i],    reg_ena, '0)
    `FFL(mid_pipe_spec_stat_q[i+1],   mid_pipe_spec_stat_q[i],   reg_ena, '0)
    `FFL(mid_pipe_fp32_q[i+1],        mid_pipe_fp32_q[i],        reg_ena, '0)
    `FFL(mid_pipe_sfu_q[i+1],           mid_pipe_sfu_q[i],           reg_ena, '0)
    `FFL(mid_pipe_sfu_zero_sign_q[i+1], mid_pipe_sfu_zero_sign_q[i], reg_ena, '0)
    `FFL(mid_pipe_int_q[i+1],           mid_pipe_int_q[i],           reg_ena, '0)
    `FFL(mid_pipe_int_sel_q[i+1],       mid_pipe_int_sel_q[i],       reg_ena, '0)
    `FFL(mid_pipe_cvt_q[i+1],           mid_pipe_cvt_q[i],           reg_ena, '0)
    `FFL(mid_pipe_fma_q[i+1],           mid_pipe_fma_q[i],           reg_ena, '0)
    `FFL(mid_pipe_tag_q[i+1],         mid_pipe_tag_q[i],         reg_ena, TagType'('0))
    `FFL(mid_pipe_mask_q[i+1],        mid_pipe_mask_q[i],        reg_ena, '0)
    `FFL(mid_pipe_aux_q[i+1],         mid_pipe_aux_q[i],         reg_ena, AuxType'('0))
  end
  // Output stage: assign selected pipe outputs to signals for later use
  assign effective_subtraction_q = mid_pipe_eff_sub_q[NUM_MID_REGS];
  assign use_lzc_q               = mid_pipe_use_lzc_q[NUM_MID_REGS];
  assign exponent_q              = mid_pipe_exponent_q[NUM_MID_REGS];
  assign addend_shamt_q          = mid_pipe_add_shamt_q[NUM_MID_REGS];
  assign sticky_before_add_q     = mid_pipe_sticky_q[NUM_MID_REGS];
  assign product_q               = mid_pipe_product_q[NUM_MID_REGS];
  assign addend_after_shift_q    = mid_pipe_addend_q[NUM_MID_REGS];
  assign tentative_sign_q        = mid_pipe_tent_sign_q[NUM_MID_REGS];
  assign rnd_mode_q              = mid_pipe_rnd_mode_q[NUM_MID_REGS];
  assign result_is_special_q     = mid_pipe_res_is_spec_q[NUM_MID_REGS];
  assign special_result_q        = mid_pipe_spec_res_q[NUM_MID_REGS];
  assign special_status_q        = mid_pipe_spec_stat_q[NUM_MID_REGS];

  logic fp32_q, sfu_q;

  assign fp32_q = mid_pipe_fp32_q[NUM_MID_REGS];
  assign sfu_q  = mid_pipe_sfu_q[NUM_MID_REGS];

  // Product is placed into a 3p+4 bit wide vector, padded with 2 bits for round and sticky:
  // | 000...000 | product | RS |
  //  <-  p+2  -> <-  2p -> < 2>
  // FP32: the product is at bits 47-0, so it lands at the bottom of the FP32 frame, as an FP32 FMA places it.
  // SFU: the product is two's complement, so its sign fills the bits above it.
  logic [3*PRECISION_BITS+3:0] product_shifted;     // addends are 3p+4 bit wide (including G/R)
  logic [3*PRECISION_BITS+3:0] addend_shifted;      // addends are 3p+4 bit wide (including G/R)
  logic                        inject_carry_in;     // inject carry for subtractions if needed

  always_comb begin : product_placement
    product_shifted = product_q << 2; // constant shift
    if (sfu_q) product_shifted[3*PRECISION_BITS+3:2*PRECISION_BITS+2] = '{default: product_q[2*PRECISION_BITS-1]};
  end

  // In case of a subtraction, the addend is inverted. FP32 too, across the whole width: above the FP32 frame the
  // product and the addend are 0, so the carry out of the frame runs to the top, and sum_carry, the sum's selection
  // and the final sign are those of the frame (fpnew_fma's in FP32), with zeros above it in the sum.
  assign addend_shifted  = (effective_subtraction_q) ? ~addend_after_shift_q : addend_after_shift_q;
  assign inject_carry_in = effective_subtraction_q & ~sticky_before_add_q;

  // ------
  // Adder
  // ------
  logic [3*PRECISION_BITS+4:0] sum_raw;   // added one bit for the carry
  logic                        sum_carry; // observe carry bit from raw sum for sign fixing
  logic [3*PRECISION_BITS+3:0] sum;       // discard carry as sum won't overflow
  logic                        final_sign;

  //Mantissa adder (ab+c). In normal addition, it cannot overflow.
  assign sum_raw   = product_shifted + addend_shifted + inject_carry_in;
  assign sum_carry = sum_raw[3*PRECISION_BITS+4];

  // Complement negative sum (can only happen in subtraction -> overflows for positive results).
  // Note: inject_carry_in is used to complete the negation of the addend in the raw sum but for the negative sum the
  // addend is not negated, so no carry needs to be injected.
  logic [3*PRECISION_BITS+4:0] sum_neg;

  assign sum_neg = addend_after_shift_q - product_shifted;
  assign sum     = (effective_subtraction_q && ~sum_carry) ? sum_neg[3*PRECISION_BITS+3:0]
                                                           : sum_raw[3*PRECISION_BITS+3:0];

  // In case of a mispredicted subtraction result, do a sign flip
  assign final_sign = (effective_subtraction_q && (sum_carry == tentative_sign_q))
                      ? 1'b1
                      : (effective_subtraction_q ? 1'b0 : tentative_sign_q);

  // --------------
  // Normalization
  // --------------
  logic        [SHIFT_AMOUNT_WIDTH-1:0] norm_shamt; // Normalization shift amount
  logic signed [EXP_WIDTH-1:0]          normalized_exponent;
  logic                                 sum_zero;   // the sum's lower 2p+3 bits are zero (the SFU's zero sum)

  logic [3*PRECISION_BITS+4:0] sum_shifted;       // result after first normalization shift
  logic [PRECISION_BITS:0]     final_mantissa;    // final mantissa before rounding with round bit
  logic [2*PRECISION_BITS+2:0] sum_sticky_bits;   // remaining 2p+3 sticky bits after normalization
  logic                        sticky_after_norm; // sticky bit after normalization

  logic signed [EXP_WIDTH-1:0] final_exponent;

  // The normalization amount and exponent from the leading-zero count of the sum's lower 2p+3 bits, or the
  // addend's shift, as FP32's
  ucc_fp32_norm #(
    .FpFormat ( FpFormat )
  ) i_norm (
    .sum_lower_i           ( sum[LOWER_SUM_WIDTH-1:0] ),
    .use_lzc_i             ( use_lzc_q                ),
    .exponent_i            ( exponent_q               ),
    .addend_shamt_i        ( addend_shamt_q           ),
    .norm_shamt_o          ( norm_shamt               ),
    .normalized_exponent_o ( normalized_exponent      ),
    .zero_o                ( sum_zero                 )
  );

  // FP32: the same from the FP32 frame, with the FP32 exponent and shift amount in the low bits of the FP64 fields
  logic [ucc_pkg::SHIFT_AMOUNT_WIDTH-1:0] fp32_norm_shamt;
  logic signed [ucc_pkg::EXP_WIDTH-1:0]   fp32_normalized_exponent, fp32_final_exponent;

  ucc_fp32_norm i_norm32 (
    .sum_lower_i           ( sum[ucc_pkg::LOWER_SUM_WIDTH-1:0]               ),
    .use_lzc_i             ( use_lzc_q                                       ),
    .exponent_i            ( exponent_q[ucc_pkg::EXP_WIDTH-1:0]              ),
    .addend_shamt_i        ( addend_shamt_q[ucc_pkg::SHIFT_AMOUNT_WIDTH-1:0] ),
    .norm_shamt_o          ( fp32_norm_shamt                                 ),
    .normalized_exponent_o ( fp32_normalized_exponent                        ),
    .zero_o                (                                                 )
  );

  typedef enum logic [1:0] {NORM_KEEP, NORM_RIGHT, NORM_LEFT} norm_dir_e;

  norm_dir_e                   norm_dir, fp32_norm_dir;
  logic [3*PRECISION_BITS+3:0] sum_normalized;

  // Do the large normalization shift
  ucc_shift #(
    .WIDTH       ( 3 * PRECISION_BITS + 5 ),
    .SHAMT_WIDTH ( SHIFT_AMOUNT_WIDTH     ),
    .LEFT        ( 1'b1                   )
  ) i_norm_shift (
    .data_i  ( {1'b0, sum}                                                   ),
    .shamt_i ( fp32_q ? SHIFT_AMOUNT_WIDTH'(fp32_norm_shamt) : norm_shamt ),
    .data_o  ( sum_shifted                                                   )
  );

  // The addend-anchored case needs a 1-bit normalization since the leading-one can be to the left
  // or right of the (non-carry) MSB of the sum.
  always_comb begin : small_norm
    // Default: discard the carry bit
    norm_dir       = NORM_KEEP;
    final_exponent = normalized_exponent;

    // The normalized sum has overflown, align right and fix exponent
    if (sum_shifted[3*PRECISION_BITS+4]) begin // check the carry bit
      norm_dir       = NORM_RIGHT;
      final_exponent = normalized_exponent + 1;
    // The normalized sum is normal, nothing to do
    end else if (sum_shifted[3*PRECISION_BITS+3]) begin // check the sum MSB
      // do nothing
    // The normalized sum is still denormal, align left - unless the result is not already subnormal
    end else if (normalized_exponent > 1) begin
      norm_dir       = NORM_LEFT;
      final_exponent = normalized_exponent - 1;
    // Otherwise we're denormal
    end else begin
      final_exponent = '0;
    end
  end

  // FP32: the same decision from the FP32 frame's carry bit and MSB
  always_comb begin : small_norm32
    fp32_norm_dir       = NORM_KEEP;
    fp32_final_exponent = fp32_normalized_exponent;
    if (sum_shifted[FRAME]) begin
      fp32_norm_dir       = NORM_RIGHT;
      fp32_final_exponent = fp32_normalized_exponent + 1;
    end else if (sum_shifted[FRAME-1]) begin
      // do nothing
    end else if (fp32_normalized_exponent > 1) begin
      fp32_norm_dir       = NORM_LEFT;
      fp32_final_exponent = fp32_normalized_exponent - 1;
    end else begin
      fp32_final_exponent = '0;
    end
  end

  // The 1-bit normalization itself
  always_comb begin : small_norm_shift
    unique case (fp32_q ? fp32_norm_dir : norm_dir)
      NORM_RIGHT: sum_normalized = sum_shifted[3*PRECISION_BITS+4:1];
      NORM_LEFT:  sum_normalized = {sum_shifted[3*PRECISION_BITS+2:0], 1'b0};
      default:    sum_normalized = sum_shifted[3*PRECISION_BITS+3:0];
    endcase
  end

  assign {final_mantissa, sum_sticky_bits} = sum_normalized;

  // FP32: the value before rounding (or the special result) and what the rounding needs, from the FP32 frame of the
  // normalized sum
  logic [ucc_pkg::WIDTH-1:0] fp32_value;
  ucc_pkg::round_t           fp32_round;

  ucc_fp32_preround i_preround32 (
    .final_mantissa_i        ( sum_normalized[ucc_pkg::LOWER_SUM_WIDTH +: P32+1] ),
    .sum_sticky_bits_i       ( sum_normalized[ucc_pkg::LOWER_SUM_WIDTH-1:0]      ),
    .sticky_before_add_i     ( sticky_before_add_q                               ),
    .final_exponent_i        ( fp32_final_exponent                               ),
    .final_sign_i            ( final_sign                                        ),
    .effective_subtraction_i ( effective_subtraction_q                           ),
    .result_is_special_i     ( result_is_special_q                               ),
    .special_result_i        ( special_result_q[ucc_pkg::WIDTH-1:0]              ),
    .special_status_i        ( special_status_q                                  ),
    .value_o                 ( fp32_value                                        ),
    .round_o                 ( fp32_round                                        )
  );

  // Update the sticky bit with the shifted-out bits
  assign sticky_after_norm = (| {sum_sticky_bits}) | sticky_before_add_q;

  // ----------------------------------------
  // The value before rounding (FP64 and SFU)
  // ----------------------------------------
  // FP64: the value before rounding (or the special result) and what the rounding needs, as FP32's
  logic [WIDTH-1:0] fp64_value;
  ucc_pkg::round_t  fp64_round;

  ucc_fp32_preround #(
    .FpFormat ( FpFormat )
  ) i_preround (
    .final_mantissa_i        ( final_mantissa          ),
    .sum_sticky_bits_i       ( sum_sticky_bits         ),
    .sticky_before_add_i     ( sticky_before_add_q     ),
    .final_exponent_i        ( final_exponent          ),
    .final_sign_i            ( final_sign              ),
    .effective_subtraction_i ( effective_subtraction_q ),
    .result_is_special_i     ( result_is_special_q     ),
    .special_result_i        ( special_result_q        ),
    .special_status_i        ( special_status_q        ),
    .value_o                 ( fp64_value              ),
    .round_o                 ( fp64_round              )
  );

  // SFU: the FP64 path normalized its sum exactly, and the output cycle rounds it to FP32 from these fields: {zero
  // sign, zero sum, sign, FP32-biased exponent before the rounding's carry, round bit, sticky bit, significand}
  localparam int unsigned SFU_ROUND = PRECISION_BITS - ucc_pkg::PRECISION_BITS; // final_mantissa's round bit
  localparam int unsigned SFU_PRE   = 5 + EXP_WIDTH + ucc_pkg::PRECISION_BITS;

  logic [SFU_PRE-1:0] sfu_pre;

  assign sfu_pre = {mid_pipe_sfu_zero_sign_q[NUM_MID_REGS], sum_zero, final_sign,
                    EXP_WIDTH'(final_exponent - signed'(BIAS - ucc_pkg::BIAS)),
                    final_mantissa[SFU_ROUND], (| final_mantissa[SFU_ROUND-1:0]) | sticky_after_norm,
                    final_mantissa[PRECISION_BITS -: ucc_pkg::PRECISION_BITS]};

  // The output register's value: FP32 its value before rounding in the low 32 bits, SFU its fields (or its special
  // value NaN-boxed), FP64 the value before rounding (or the special result); and what the rounding needs
  fp_t             value_d;
  ucc_pkg::round_t round_d;

  assign value_d = fp32_q ? fp_t'(WIDTH'(fp32_value))
                 : sfu_q  ? fp_t'(result_is_special_q ? {32'hffff_ffff, special_result_q[31:0]} : WIDTH'(sfu_pre))
                          : fp_t'(fp64_value);
  assign round_d = fp32_q ? fp32_round : fp64_round;

  // ------
  // Bypass
  // ------
  // An ALU or FP compare-unit result is final after the input register and leaves from there, combinationally
  // (alu_bypass). A multiply's is final in the middle stage's sum (lo bits 75-44, hi 107-76, wide 107-44), from the
  // middle register's product and addend, and a conversion's in the middle register's special result, and they leave
  // from there (int_bypass). None enters the output register, which returns only the FMA path's results.
  logic             alu_bypass, int_bypass;
  logic [2:0]       int_sel_q;
  logic [WIDTH-1:0] alu_result, int_result;

  assign alu_bypass = inp_pipe_valid_q[NUM_INP_REGS] & ((int_mode & ~int_op[5]) | (unit_q == ucc_pkg::UNIT_CMP));
  assign alu_result = (unit_q == ucc_pkg::UNIT_CMP) ? noncomp_result : WIDTH'(int_alu_result);
  assign int_sel_q  = mid_pipe_int_sel_q[NUM_MID_REGS];
  assign int_bypass = mid_pipe_valid_q[NUM_MID_REGS] &
                      ((mid_pipe_int_q[NUM_MID_REGS] & int_sel_q[2]) | mid_pipe_cvt_q[NUM_MID_REGS]);

  always_comb begin : int_result_select
    if (mid_pipe_cvt_q[NUM_MID_REGS])
      int_result = special_result_q;
    else if (int_sel_q[1])
      int_result = sum[INT_LSB +: 64];
    else
      int_result = WIDTH'(sum[INT_LSB + 32 * int_sel_q[0] +: 32]);
  end

  // ----------------
  // Output Pipeline
  // ----------------
  // Output pipeline signals, index i holds signal after i register stages
  fp_t                   [0:NUM_OUT_REGS]      out_pipe_result_q; // the value before rounding
  ucc_pkg::round_t       [0:NUM_OUT_REGS]      out_pipe_round_q;
  fpnew_pkg::roundmode_e [0:NUM_OUT_REGS]      out_pipe_rnd_mode_q;
  logic                  [0:NUM_OUT_REGS]      out_pipe_fp32_q;
  TagType             [0:NUM_OUT_REGS] out_pipe_tag_q;
  logic               [0:NUM_OUT_REGS] out_pipe_mask_q;
  AuxType             [0:NUM_OUT_REGS] out_pipe_aux_q;
  logic               [0:NUM_OUT_REGS] out_pipe_sfu_q; // an SFU function's result (older than a DPA-16's due with it)
  logic               [0:NUM_OUT_REGS] out_pipe_valid_q;
  // Ready signal is combinatorial for all stages
  logic [0:NUM_OUT_REGS] out_pipe_ready;

  // Input stage: First element of pipeline is taken from inputs
  assign out_pipe_result_q[0]   = value_d;
  assign out_pipe_round_q[0]    = round_d;
  assign out_pipe_rnd_mode_q[0] = rnd_mode_q;
  assign out_pipe_fp32_q[0]     = fp32_q;
  assign out_pipe_tag_q[0]    = mid_pipe_tag_q[NUM_MID_REGS];
  assign out_pipe_mask_q[0]   = mid_pipe_mask_q[NUM_MID_REGS];
  assign out_pipe_aux_q[0]    = mid_pipe_aux_q[NUM_MID_REGS];
  assign out_pipe_sfu_q[0]    = sfu_q;
  assign out_pipe_valid_q[0]  = mid_pipe_valid_q[NUM_MID_REGS] & mid_pipe_fma_q[NUM_MID_REGS];
  // Input stage: Propagate pipeline ready signal to inside pipe
  assign mid_pipe_ready[NUM_MID_REGS] = out_pipe_ready[0];
  // Generate the register stages
  for (genvar i = 0; i < NUM_OUT_REGS; i++) begin : gen_output_pipeline
    // Internal register enable for this stage
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline:
    // 1. if the next stage is ready for our data
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it
    assign out_pipe_ready[i] = out_pipe_ready[i+1] | ~out_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal
    `FFLARNC(out_pipe_valid_q[i+1], out_pipe_valid_q[i], out_pipe_ready[i], flush_i, 1'b0, clk_i, rst_ni)
    // Enable register if pipleine ready and a valid data item is present
    assign reg_ena = (out_pipe_ready[i] & out_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + NUM_MID_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers
    `FFL(out_pipe_result_q[i+1],   out_pipe_result_q[i],   reg_ena, '0)
    `FFL(out_pipe_round_q[i+1],    out_pipe_round_q[i],    reg_ena, '0)
    `FFL(out_pipe_rnd_mode_q[i+1], out_pipe_rnd_mode_q[i], reg_ena, fpnew_pkg::RNE)
    `FFL(out_pipe_fp32_q[i+1],     out_pipe_fp32_q[i],     reg_ena, '0)
    `FFL(out_pipe_tag_q[i+1],    out_pipe_tag_q[i],    reg_ena, TagType'('0))
    `FFL(out_pipe_mask_q[i+1],   out_pipe_mask_q[i],   reg_ena, '0)
    `FFL(out_pipe_aux_q[i+1],    out_pipe_aux_q[i],    reg_ena, AuxType'('0))
    `FFL(out_pipe_sfu_q[i+1],    out_pipe_sfu_q[i],    reg_ena, '0)
  end
  // Output stage: Ready travels backwards from output side, driven by downstream circuitry
  assign out_pipe_ready[NUM_OUT_REGS] = out_ready_i;

  // ----------------------------------------------------------------
  // Rounding and classification, in the output cycle (fpnew_fma's)
  // ----------------------------------------------------------------
  fp_t                   value_q;
  ucc_pkg::round_t       round_q;
  fpnew_pkg::roundmode_e out_rnd_mode;
  logic                  out_fp32, out_sfu;

  assign value_q      = out_pipe_result_q[NUM_OUT_REGS];
  assign round_q      = out_pipe_round_q[NUM_OUT_REGS];
  assign out_rnd_mode = out_pipe_rnd_mode_q[NUM_OUT_REGS];
  assign out_fp32     = out_pipe_fp32_q[NUM_OUT_REGS];
  assign out_sfu      = out_pipe_sfu_q[NUM_OUT_REGS];

  // FP64's rounding, as FP32's
  logic [WIDTH-1:0]   fp64_result;
  fpnew_pkg::status_t fp64_status;

  ucc_fp32_round #(
    .FpFormat ( FpFormat )
  ) i_round (
    .value_i    ( value_q      ),
    .round_i    ( round_q      ),
    .rnd_mode_i ( out_rnd_mode ),
    .result_o   ( fp64_result  ),
    .status_o   ( fp64_status  )
  );

  // FP32's rounding, of the value's low 32 bits
  logic [ucc_pkg::WIDTH-1:0] fp32_result;
  fpnew_pkg::status_t        fp32_status;

  ucc_fp32_round i_round32 (
    .value_i    ( value_q[ucc_pkg::WIDTH-1:0] ),
    .round_i    ( round_q                     ),
    .rnd_mode_i ( out_rnd_mode                ),
    .result_o   ( fp32_result                 ),
    .status_o   ( fp32_status                 )
  );

  // -------------------------
  // SFU: rounding to FP32
  // -------------------------
  // To nearest even. As in the MUFU, an exactly zero sum is a zero of the front end's sign, and results beyond FP32's
  // normal range are an infinity or a zero of the result's sign.
  logic                             sfu_out_zero_sign, sfu_zero, sfu_sign, sfu_round_bit, sfu_sticky;
  logic signed [EXP_WIDTH-1:0]      sfu_exponent_pre, sfu_exponent;
  logic [ucc_pkg::PRECISION_BITS-1:0] sfu_mantissa;
  logic [ucc_pkg::PRECISION_BITS:0] sfu_significand; // with the rounding's carry
  logic                             sfu_round_up;
  logic [31:0]                      sfu_result;

  assign {sfu_out_zero_sign, sfu_zero, sfu_sign, sfu_exponent_pre, sfu_round_bit, sfu_sticky, sfu_mantissa} =
         value_q[SFU_PRE-1:0];
  assign sfu_round_up    = sfu_round_bit & (sfu_sticky | sfu_mantissa[0]);
  assign sfu_significand = {1'b0, sfu_mantissa} + sfu_round_up;
  assign sfu_exponent    = sfu_exponent_pre + signed'(EXP_WIDTH'(sfu_significand[ucc_pkg::PRECISION_BITS]));

  always_comb begin : sfu_rounding
    if (sfu_zero)
      sfu_result = {sfu_out_zero_sign, 31'd0};
    else if (sfu_exponent >= signed'(EXP_WIDTH'(2**ucc_pkg::EXP_BITS - 1)))
      sfu_result = {sfu_sign, {ucc_pkg::EXP_BITS{1'b1}}, {ucc_pkg::MAN_BITS{1'b0}}};
    else if (sfu_exponent <= 0)
      sfu_result = {sfu_sign, 31'd0};
    else
      sfu_result = {sfu_sign, sfu_exponent[ucc_pkg::EXP_BITS-1:0],
                    sfu_significand[ucc_pkg::PRECISION_BITS] ? ucc_pkg::MAN_BITS'(0)
                                                             : sfu_significand[ucc_pkg::MAN_BITS-1:0]};
  end

  // Select output depending on special case detection (FP32: its result NaN-boxed; SFU: its FP32 result NaN-boxed, no
  // flags, as the MUFU)
  fp_t                fma_result;
  fpnew_pkg::status_t fma_status;

  assign fma_result = out_fp32 ? fp_t'({32'hffff_ffff, fp32_result})
                    : out_sfu  ? fp_t'({32'hffff_ffff, round_q.special ? value_q[31:0] : sfu_result})
                               : fp_t'(fp64_result);
  assign fma_status = out_fp32 ? fp32_status
                    : out_sfu  ? '0
                               : fp64_status;
  // Output stage: assign module outputs (the bypassed results, the youngest operation's first, then the output
  // register's FMA result, DPA-16's, the output register's SFU result)
  logic out_valid, out_fma, dpa_out;

  assign out_valid       = out_pipe_valid_q[NUM_OUT_REGS];
  assign out_fma         = out_valid & ~out_pipe_sfu_q[NUM_OUT_REGS];
  assign dpa_out         = dpa_valid_q[2] & ~out_fma;
  assign result_o        = alu_bypass ? fp_t'(alu_result)
                         : int_bypass ? fp_t'(int_result)
                         : dpa_out    ? fp_t'({32'hffff_ffff, dpa_result}) : fma_result;
  // Flags: the compare unit's and the conversions' (FPnew's), the FMA path's; none from the ALU, the multiplies,
  // DPA-16 or the SFU
  assign status_o        = alu_bypass ? ((unit_q == ucc_pkg::UNIT_CMP) ? noncomp_status : '0)
                         : int_bypass ? (mid_pipe_cvt_q[NUM_MID_REGS] ? special_status_q : '0)
                         : dpa_out    ? '0 : fma_status;
  assign extension_bit_o = 1'b1; // always NaN-Box result
  assign tag_o           = alu_bypass ? inp_pipe_tag_q[NUM_INP_REGS]
                         : int_bypass ? mid_pipe_tag_q[NUM_MID_REGS]
                         : dpa_out    ? dpa_tag_q[2] : out_pipe_tag_q[NUM_OUT_REGS];
  assign mask_o          = alu_bypass ? inp_pipe_mask_q[NUM_INP_REGS]
                         : int_bypass ? mid_pipe_mask_q[NUM_MID_REGS]
                         : dpa_out    ? dpa_mask_q[2] : out_pipe_mask_q[NUM_OUT_REGS];
  assign aux_o           = alu_bypass ? inp_pipe_aux_q[NUM_INP_REGS]
                         : int_bypass ? mid_pipe_aux_q[NUM_MID_REGS]
                         : dpa_out    ? dpa_aux_q[2] : out_pipe_aux_q[NUM_OUT_REGS];
  assign out_valid_o     = out_valid | int_bypass | alu_bypass | dpa_valid_q[2];
  assign busy_o          = (| {inp_pipe_valid_q, mid_pipe_valid_q, out_pipe_valid_q, dpa_valid_q});

  // The issue rules' breaches: an operation issued while in_ready_o is clear (the SFU's slot) is lost, and so is the
  // older of two results due in the same cycle. Nothing in the FU reads these; the regression checks them, and
  // UCC_CHECK_ISSUE makes each a simulation error.
  logic issue_lost, result_hidden;

  assign issue_lost    = in_valid_i & ~in_ready_o;
  assign result_hidden = 3'(alu_bypass) + 3'(int_bypass) + 3'(out_valid) + 3'(dpa_valid_q[2]) > 3'd1;

`ifdef UCC_CHECK_ISSUE
  // For an issuer that keeps the rules. Off by default: the regression's mixed streams break both on purpose.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (rst_ni) begin
      if (issue_lost)    $error("ucc_fma: an operation issued in the SFU's slot is lost");
      if (result_hidden) $error("ucc_fma: two results are due in the same cycle, and the older one is lost");
    end
  end
`endif
endmodule
