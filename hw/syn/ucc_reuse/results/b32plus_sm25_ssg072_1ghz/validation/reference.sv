// Derived combinational measurement snapshot; historical pipeline comments below
// describe the source snapshot. See manifest.json and derivation.patch.
// Copyright 2016 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License.  You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
/// cf_math_pkg: Constant Function Implementations of Mathematical Functions for HDL Elaboration 
/// 
/// This package contains a collection of mathematical functions that are commonly used when defining 
/// the value of constants in HDL code.  These functions are implemented as Verilog constants 
/// functions.  Introduced in Verilog 2001 (IEEE Std 1364-2001), a constant function (§ 10.3.5) is a 
/// function whose value can be evaluated at compile time or during elaboration.  A constant function 
/// must be called with arguments that are constants. 
package cf_math_pkg;
    /// Ceiled Division of Two Natural Numbers 
    /// 
    /// Returns the quotient of two natural numbers, rounded towards plus infinity. 
    function automatic integer ceil_div (input longint dividend, input longint divisor);
        automatic longint remainder;
        // pragma translate_off 
        // pragma translate_on 
        remainder = dividend;
        for (ceil_div = 0; remainder > 0; ceil_div++) begin
            remainder = remainder - divisor;
        end
    endfunction
    /// Index width required to be able to represent up to `num_idx` indices as a binary 
    /// encoded signal. 
    /// Ensures that the minimum width if an index signal is `1`, regardless of parametrization. 
    /// 
    /// Sample usage in type definition: 
    /// As parameter: 
    ///   `parameter type idx_t = logic[cf_math_pkg::idx_width(NumIdx)-1:0]` 
    /// As typedef: 
    ///   `typedef logic [cf_math_pkg::idx_width(NumIdx)-1:0] idx_t` 
    function automatic integer unsigned idx_width (input integer unsigned num_idx);
        return (num_idx > 32'd1) ? unsigned'($clog2(num_idx)) : 32'd1;
    endfunction
endpackage
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
package fpnew_pkg;
  // --------- 
  // FP TYPES 
  // --------- 
  // | Enumerator | Format                | Width  | EXP_BITS | MAN_BITS 
  // |:----------:|-----------------------|-------:|:--------:|:--------: 
  // | FP32       | IEEE binary32         | 32 bit | 8        | 23 
  // | FP64       | IEEE binary64         | 64 bit | 11       | 52 
  // | FP16       | IEEE binary16         | 16 bit | 5        | 10 
  // | FP8        | binary8 (E4M3)        |  8 bit | 4        | 3 
  // | FP16ALT    | binary16alt (BF16)    | 16 bit | 8        | 7 
  // | FP4        | E2M1                  |  4 bit | 2        | 1 
  // | FP8ALT     | binary8alt (E5M2)     |  8 bit | 5        | 2 
  // *NOTE:* Add new formats only at the end of the enumeration for backwards compatibilty! 
  // Encoding for a format 
  typedef struct packed {
    int unsigned exp_bits;
    int unsigned man_bits;
  } fp_encoding_t;
  localparam int unsigned NUM_FP_FORMATS = 7; // change me to add formats 
  localparam int unsigned FP_FORMAT_BITS = $clog2(NUM_FP_FORMATS);
  // FP formats 
  typedef enum logic [FP_FORMAT_BITS-1:0] {
    FP32    = 'd0,
    FP64    = 'd1,
    FP16    = 'd2,
    FP8     = 'd3,
    FP16ALT = 'd4,
    FP4     = 'd5,
    FP8ALT  = 'd6
    // add new formats here 
  } fp_format_e;
  // Encodings for supported FP formats 
  localparam fp_encoding_t [0:NUM_FP_FORMATS-1] FP_ENCODINGS  = '{
    '{8,  23}, // IEEE binary32 (single) 
    '{11, 52}, // IEEE binary64 (double) 
    '{5,  10}, // IEEE binary16 (half) 
    '{4,  3},  // custom binary8 (E4M3) 
    '{8,  7},  // custom binary16alt (BF16) 
    '{2,  1},  // custom fp4 (E2M1) 
    '{5,  2}   // custom binary8alt (E5M2) — wider exp than E4M3 
    // add new formats here 
  };
  typedef logic [0:NUM_FP_FORMATS-1]       fmt_logic_t;    // Logic indexed by FP format (for masks) 
  typedef logic [0:NUM_FP_FORMATS-1][31:0] fmt_unsigned_t; // Unsigned indexed by FP format 
  localparam fmt_logic_t CPK_FORMATS = 7'b1100000; // FP32 and FP64 can provide CPK only 
  // --------- 
  // INT TYPES 
  // --------- 
  // | Enumerator | Width  | 
  // |:----------:|-------:| 
  // | INT8       |  8 bit | 
  // | INT16      | 16 bit | 
  // | INT32      | 32 bit | 
  // | INT64      | 64 bit | 
  // *NOTE:* Add new formats only at the end of the enumeration for backwards compatibilty! 
  localparam int unsigned NUM_INT_FORMATS = 5; // change me to add formats 
  localparam int unsigned INT_FORMAT_BITS = $clog2(NUM_INT_FORMATS);
  // Int formats. INT4 is appended last to preserve the legacy enum encoding 
  // for INT8/16/32/64; it covers the MFSA paper's INT4 DPA mode (k=8 lanes 
  // packed into one 32-b operand word). The paper expects the FP4 multiplier 
  // to be reused for INT4 (sign-mag → two's-complement on the FP4 DP2 stage). 
  typedef enum logic [INT_FORMAT_BITS-1:0] {
    INT8,
    INT16,
    INT32,
    INT64,
    INT4
    // add new formats here 
  } int_format_e;
  // Returns the width of an INT format by index 
  function automatic int unsigned int_width(int_format_e ifmt);
    unique case (ifmt)
      INT8:  return 8;
      INT16: return 16;
      INT32: return 32;
      INT64: return 64;
      INT4:  return 4;
      default: begin
        // pragma translate_off 
        $fatal(1, "Invalid INT format supplied");
        // pragma translate_on 
        // just return any integer to avoid any latches 
        // hopefully this error is caught by simulation 
        return INT8;
      end
    endcase
  endfunction
  typedef logic [0:NUM_INT_FORMATS-1] ifmt_logic_t; // Logic indexed by INT format (for masks) 
  // -------------- 
  // FP OPERATIONS 
  // -------------- 
  localparam int unsigned NUM_OPGROUPS = 4;
  // Each FP operation belongs to an operation group 
  typedef enum logic [1:0] {
    ADDMUL, DIVSQRT, NONCOMP, CONV
  } opgroup_e;
  localparam int unsigned OP_BITS = 5;
  typedef enum logic [OP_BITS-1:0] {
    FMADD, FNMSUB, ADD, MUL,     // ADDMUL operation group 
    DIV, SQRT,                   // DIVSQRT operation group 
    SGNJ, MINMAX, CMP, CLASSIFY, // NONCOMP operation group 
    F2F, F2I, I2F, CPKAB, CPKCD, // CONV operation group 
    ADDS,                         // ADDMUL operation group (kept after CPK* to preserve legacy encoding) 
    TDOT_SIMD_FMADD,              // ADDMUL operation group (TransDot merged-SIMD FMADD) 
    TDOT_DP_FMADD,                // ADDMUL operation group (TransDot dot-product FMADD) 
    TDOT_FP4_DP_FMADD,            // ADDMUL operation group (TransDot FP4 dot-product FMADD) 
    INT_DP_FMADD                  // ADDMUL-class integer DPA MAC (paper Section III-C INT path). 
                                  // int_fmt_i selects INT16 (2-DPA) or INT8 (4-DPA); 
                                  // op_mod_i = 0 for signed, 1 for unsigned operands. 
                                  // Result is INT32, written to the 32-b cascade. 
  } operation_e;
  // ------------- 
  // DIVSQRT UNIT 
  // ------------- 
  typedef enum logic[1:0] {
    PULP,    // "PULP" instantiates the PULP DivSqrt unit supports FP64, FP32, FP16, FP16ALT, FP8 and SIMD operations 
    TH32,    // "TH32" instantiates the E906 DivSqrt unit supports only FP32 (no SIMD support) 
    THMULTI  // "THMULTI" instantiates the C910 DivSqrt unit supports FP64, FP32, FP16, FP16ALT and SIMD operations 
  } divsqrt_unit_t;
  // ------------------- 
  // RISC-V FP-SPECIFIC 
  // ------------------- 
  // Rounding modes 
  typedef enum logic [2:0] {
    RNE = 3'b000,
    RTZ = 3'b001,
    RDN = 3'b010,
    RUP = 3'b011,
    RMM = 3'b100,
    ROD = 3'b101,  // This mode is not defined in RISC-V FP-SPEC 
    DYN = 3'b111
  } roundmode_e;
  // Status flags 
  typedef struct packed {
    logic NV; // Invalid 
    logic DZ; // Divide by zero 
    logic OF; // Overflow 
    logic UF; // Underflow 
    logic NX; // Inexact 
  } status_t;
  // Information about a floating point value 
  typedef struct packed {
    logic is_normal;     // is the value normal 
    logic is_subnormal;  // is the value subnormal 
    logic is_zero;       // is the value zero 
    logic is_inf;        // is the value infinity 
    logic is_nan;        // is the value NaN 
    logic is_signalling; // is the value a signalling NaN 
    logic is_quiet;      // is the value a quiet NaN 
    logic is_boxed;      // is the value properly NaN-boxed (RISC-V specific) 
  } fp_info_t;
  // Classification mask 
  typedef enum logic [9:0] {
    NEGINF     = 10'b00_0000_0001,
    NEGNORM    = 10'b00_0000_0010,
    NEGSUBNORM = 10'b00_0000_0100,
    NEGZERO    = 10'b00_0000_1000,
    POSZERO    = 10'b00_0001_0000,
    POSSUBNORM = 10'b00_0010_0000,
    POSNORM    = 10'b00_0100_0000,
    POSINF     = 10'b00_1000_0000,
    SNAN       = 10'b01_0000_0000,
    QNAN       = 10'b10_0000_0000
  } classmask_e;
  // ------------------ 
  // FPU configuration 
  // ------------------ 
  // Pipelining registers can be inserted (at elaboration time) into operational units 
  typedef enum logic [1:0] {
    BEFORE,     // registers are inserted at the inputs of the unit 
    AFTER,      // registers are inserted at the outputs of the unit 
    INSIDE,     // registers are inserted at predetermined (suboptimal) locations in the unit 
    DISTRIBUTED // registers are evenly distributed, INSIDE >= AFTER >= BEFORE 
  } pipe_config_t;
  // Arithmetic units can be arranged in parallel (per format), merged (multi-format) or not at all. 
  typedef enum logic [1:0] {
    DISABLED, // arithmetic units are not generated 
    PARALLEL, // arithmetic units are generated in prallel slices, one for each format 
    MERGED    // arithmetic units are contained within a merged unit holding multiple formats 
  } unit_type_t;
  // Array of unit types indexed by format 
  typedef unit_type_t [0:NUM_FP_FORMATS-1] fmt_unit_types_t;
  // Array of format-specific unit types by opgroup 
  typedef fmt_unit_types_t [0:NUM_OPGROUPS-1] opgrp_fmt_unit_types_t;
  // same with unsigned 
  typedef fmt_unsigned_t [0:NUM_OPGROUPS-1] opgrp_fmt_unsigned_t;
  // FPU configuration: features 
  typedef struct packed {
    int unsigned Width;
    logic        EnableVectors;
    logic        EnableNanBox;
    fmt_logic_t  FpFmtMask;
    ifmt_logic_t IntFmtMask;
  } fpu_features_t;
  localparam fpu_features_t RV64D = '{
    Width:         64,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1100000,
    IntFmtMask:    4'b0011
  };
  localparam fpu_features_t RV32D = '{
    Width:         64,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1100000,
    IntFmtMask:    4'b0010
  };
  localparam fpu_features_t RV32F = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000000,
    IntFmtMask:    4'b0010
  };
  localparam fpu_features_t RV64D_Xsflt = '{
    Width:         64,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1111100,
    IntFmtMask:    4'b1111
  };
  localparam fpu_features_t RV32F_Xsflt = '{
    Width:         32,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011100,
    IntFmtMask:    4'b1110
  };
  localparam fpu_features_t RV32F_Xf16alt_Xfvec = '{
    Width:         32,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000100,
    IntFmtMask:    4'b0110
  };
  localparam fpu_features_t fp32_addmul_no_simd = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000000,
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t fp16_addmul_no_simd = '{
    Width:         16,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b0000100,
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t fp32_fp16_addmul_no_simd = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1010000,
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t fp32_fp16_addmul_simd = '{
    Width:         32,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1010000,
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t fp32_fp16_fp8_addmul_no_simd = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011000,
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t fp32_fp16_fp8_addmul_simd = '{
    Width:         32,
    EnableVectors: 1'b1,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011000,
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t int32_addmul_no_simd = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000000,
    IntFmtMask:    4'b0010
  };
  localparam fpu_features_t transdot_features = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011010,
    IntFmtMask:    4'b0000
  };
  // Full MFSA hero config for ICCD2026: 6 FP formats (FP32, FP16, BF16, FP8 
  // E4M3, FP8ALT E5M2, FP4) + INT8/INT16/INT32 + INT4 (FP4-DP runtime slot) 
  // + MX (MXFP8, MXFP4 via OBSR). FpFmtMask=7'b1011111 covers all six FP 
  // (bit6=FP32, bit5=FP64 disabled, bit4=BF16, bit3=FP8, bit2=FP16, bit1=FP4, 
  // bit0=FP8ALT). IntFmtMask=4'b1110 enables INT8/INT16/INT32 (INT64 
  // disabled because the array's 32-b cascade cannot carry it). INT4 reuses 
  // the FP4-DP slot at runtime via `int_mode_i` + IntFmt=INT4, so it does 
  // not appear in IntFmtMask. 
  localparam fpu_features_t transdot_features_with_int = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011111,
    IntFmtMask:    4'b1110
  };
  localparam fpu_features_t transdot_features_fp16_dp_only = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1010000,
    IntFmtMask:    4'b0000
  };
  // Cumulative per-format variants used by the ASIC PE-level area staircase 
  // (syn/asic/pe). Width stays at 32 so the PE port list is format-independent; 
  // the FpFmtMask grows by one format per stage. Each mask bit is cfg[fmt], 
  // indexed as [0:NUM_FP_FORMATS-1] → MSB of the literal is cfg[0]=FP32. 
  //   Bit position (MSB..LSB in the literal): FP32, FP64, FP16, FP8, FP16ALT, FP4 
  // NOTE: The transdot FMA's SIMD block (transdot_fp4_fp8_fp16_fp32_fma_opt.sv 
  // line 282) unconditionally slices [15:0] out of operands_q_simd whenever 
  // fmt iterates to FP16 or FP8, regardless of the config mask. That makes 
  // truly-single-format masks (FP16-only / FP8-only / FP4-only) fail 
  // elaboration because WIDTH=fp_width(that format) < 16. To keep every stage 
  // elaboratable we hold FP32 in the mask for every stage above the first. 
  localparam fpu_features_t transdot_features_stage1_fp32 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000000,            // FP32 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_stage2_fp32_fp16 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1010000,            // FP32 + FP16 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_stage3_fp32_fp16_fp8 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011000,            // FP32 + FP16 + FP8 
    IntFmtMask:    4'b0000
  };
  // Stage 4 is `transdot_features` (7'b1011010, FP32+FP16+FP8+FP4). 
  // BF16 (FP16ALT, bit 4) feature masks for the ICCAD 2026 PPA study. 
  // FP32 (bit 0) is kept on in every variant to sidestep the SIMD-slice 
  // elab bug in transdot_fp4_fp8_fp16_fp32_fma_opt.sv (see line ~282 fix). 
  localparam fpu_features_t transdot_features_bf16_only = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000100,            // FP32 + FP16ALT (BF16) 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_bf16_fp8 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011100,            // FP32 + FP16 + FP8 + FP16ALT 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_bf16_fp4 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1000110,            // FP32 + FP16ALT + FP4 
    IntFmtMask:    4'b0000
  };
  // FP8 + FP4 dot-product PE. The FMA's SIMD lane (operands_q_simd of 
  // WIDTH/2) requires WIDTH >= 16 to decode FP8/FP16 SIMD slices, so the 
  // smallest viable mask still includes one 16-bit anchor format. FP16 is 
  // far smaller than FP32, giving us a meaningfully smaller PE than the 
  // FP32-anchored variant. INT helpers are auto-disabled by the 
  // INT_HELPER_SUPPORTED gate (no FP32 in mask). 
  localparam fpu_features_t transdot_features_fp8_fp4 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b0011010,            // FP16 + FP8 + FP4 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_bf16_fp8_fp4 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011110,            // FP32 + FP16 + FP8 + FP16ALT + FP4 
    IntFmtMask:    4'b0000
  };
  // ICCD-2026 Table IV cumulative INT staircase. Each step adds one int_format_e 
  // bit to the previous FP staircase. INT4 is *not* a separate cumulative step — 
  // it reuses the FP4 DP2 slot at runtime via int4_mode_i, so a config that has 
  // FP4 enabled in FpFmtMask already carries the INT4 silicon. INT8/INT16 do 
  // need their IntFmtMask bits flipped on; both are 16-bit-safe so they 
  // elaborate alongside the existing FpFmtMask without the elaborate guard 
  // tripping. IntFmtMask bit ordering (per int_format_e): bit 3 = INT8, 
  // bit 2 = INT16, bit 1 = INT32, bit 0 = INT64. 
  localparam fpu_features_t transdot_features_bf16_fp8_int8 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011100,            // FP32 + FP16 + FP8 + FP16ALT (no FP4) 
    IntFmtMask:    4'b1000               // INT8 
  };
  localparam fpu_features_t transdot_features_bf16_fp8_fp4_int8 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011110,            // FP32 + FP16 + FP8 + FP16ALT + FP4 
    IntFmtMask:    4'b1000               // INT8 (INT4 carried by the FP4 DP2 path) 
  };
  localparam fpu_features_t transdot_features_bf16_fp8_fp4_int8_int16 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011110,            // FP32 + FP16 + FP8 + FP16ALT + FP4 
    IntFmtMask:    4'b1100               // INT8 + INT16 
  };
  // E5M2 (FP8ALT) added on top of the BF16 + FP8 + FP4 set. FP8ALT rides the 
  // FP8-DP path's 4-lane substrate (its 3-b effective mantissa fits the FP8 
  // 4×4 multiplier), with SUPER_EXP_BITS_FP8 widened to 5 to hold its 5-b 
  // exponent. Direct analog of how BF16 was added on top of FP16. 
  localparam fpu_features_t transdot_features_bf16_fp8_fp4_fp8alt = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1011111,            // FP32 + FP16 + FP8 + FP16ALT + FP4 + FP8ALT 
    IntFmtMask:    4'b0000
  };
  // ICCD 2026 incremental-cost sweep on top of BF16. The bf16_fp8 preset 
  // above already includes FP16, which conflates two additions; these 
  // strictly add formats one at a time so the PPA delta isolates each. 
  //   bf16            = transdot_features_bf16_only       (FP32 + BF16) 
  //   +fp8 (e4m3/e5m2) = transdot_features_bf16_fp8_fp8alt (this preset) 
  //   +fp4             = transdot_features_bf16_fp8_fp8alt_fp4 
  //   +fp16            = transdot_features_bf16_fp8_fp4_fp8alt (above) 
  // Mask bit order (left to right): FP32, FP64, FP16, FP8, FP16ALT, FP4, FP8ALT. 
  localparam fpu_features_t transdot_features_bf16_fp8_fp8alt = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1001101,            // FP32 + FP8 + FP16ALT + FP8ALT 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_bf16_fp8_fp8alt_fp4 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b1001111,            // FP32 + FP8 + FP16ALT + FP4 + FP8ALT 
    IntFmtMask:    4'b0000
  };
  // No-FP32 variants of the BF16-incremental sweep. These drop FP32 from 
  // the FpFmtMask entirely -- the elaboration bug fixed at 
  // transdot_fp4_fp8_fp16_fp32_fma_opt.sv:282 is what previously forced 
  // FP32 to stay in. If elaboration still works, these isolate the 
  // FP32-multiplier cost from the rest of the multi-format datapath. 
  localparam fpu_features_t transdot_features_bf16_fp8_fp8alt_nofp32 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b0001101,            // BF16 + FP8 + FP8ALT (no FP32) 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_bf16_fp8_fp8alt_fp4_nofp32 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b0001111,            // BF16 + FP8 + FP4 + FP8ALT (no FP32) 
    IntFmtMask:    4'b0000
  };
  localparam fpu_features_t transdot_features_bf16_full_nofp32 = '{
    Width:         32,
    EnableVectors: 1'b0,
    EnableNanBox:  1'b1,
    FpFmtMask:     7'b0011111,            // FP16 + BF16 + FP8 + FP4 + FP8ALT (no FP32) 
    IntFmtMask:    4'b0000
  };
  // FPU configuraion: implementation 
  typedef struct packed {
    opgrp_fmt_unsigned_t   PipeRegs;
    opgrp_fmt_unit_types_t UnitTypes;
    pipe_config_t          PipeConfig;
  } fpu_implementation_t;
  localparam fpu_implementation_t DEFAULT_NOREGS = '{
    PipeRegs:   '{default: 0},
    UnitTypes:  '{'{default: PARALLEL}, // ADDMUL 
                  '{default: MERGED},   // DIVSQRT 
                  '{default: PARALLEL}, // NONCOMP 
                  '{default: MERGED}},  // CONV 
    PipeConfig: BEFORE
  };
  localparam fpu_implementation_t DEFAULT_SNITCH = '{
    PipeRegs:   '{default: 1},
    UnitTypes:  '{'{default: PARALLEL}, // ADDMUL 
                  '{default: DISABLED}, // DIVSQRT 
                  '{default: PARALLEL}, // NONCOMP 
                  '{default: MERGED}},  // CONV 
    PipeConfig: BEFORE
  };
  localparam fpu_implementation_t ADDMUL_ONLY = '{
    PipeRegs:   '{default: 4},
    UnitTypes:  '{'{default: MERGED}, // ADDMUL 
                  '{default: DISABLED}, // DIVSQRT 
                  '{default: DISABLED}, // NONCOMP 
                  '{default: DISABLED}},  // CONV 
    //PipeConfig: BEFORE 
    PipeConfig: DISTRIBUTED
  };
  localparam fpu_implementation_t ADDMUL_ONLY_PIPE3 = '{
    PipeRegs:   '{default: 3},
    UnitTypes:  '{'{default: MERGED}, // ADDMUL 
                  '{default: DISABLED}, // DIVSQRT 
                  '{default: DISABLED}, // NONCOMP 
                  '{default: DISABLED}},  // CONV 
    //PipeConfig: BEFORE 
    PipeConfig: DISTRIBUTED
  };
  localparam fpu_implementation_t ADDMUL_ONLY_PIPE1 = '{
    PipeRegs:   '{default: 1},
    UnitTypes:  '{'{default: MERGED}, // ADDMUL 
                  '{default: DISABLED}, // DIVSQRT 
                  '{default: DISABLED}, // NONCOMP 
                  '{default: DISABLED}},  // CONV 
    PipeConfig: BEFORE
    //PipeConfig: DISTRIBUTED 
  };
  // Zero-pipe variant used by the ASIC PE/array flow so the combinational 
  // critical path through one PE is what gets reported. 
  localparam fpu_implementation_t ADDMUL_ONLY_PIPE0 = '{
    PipeRegs:   '{default: 0},
    UnitTypes:  '{'{default: MERGED}, // ADDMUL 
                  '{default: DISABLED}, // DIVSQRT 
                  '{default: DISABLED}, // NONCOMP 
                  '{default: DISABLED}},  // CONV 
    PipeConfig: BEFORE
  };
  // 2-pipe variant (DISTRIBUTED) used for 2-term DPA iso-latency sweeps 
  // (BF16, FP4). RETIME must be on when synthesising this variant. 
  localparam fpu_implementation_t ADDMUL_ONLY_PIPE2 = '{
    PipeRegs:   '{default: 2},
    UnitTypes:  '{'{default: MERGED}, // ADDMUL 
                  '{default: DISABLED}, // DIVSQRT 
                  '{default: DISABLED}, // NONCOMP 
                  '{default: DISABLED}},  // CONV 
    PipeConfig: DISTRIBUTED
  };
  // Explicit 4-pipe alias of ADDMUL_ONLY for symmetry in PPA sweep tables. 
  localparam fpu_implementation_t ADDMUL_ONLY_PIPE4 = ADDMUL_ONLY;
  // ----------------------- 
  // Synthesis optimization 
  // ----------------------- 
  localparam logic DONT_CARE = 1'b1; // the value to assign as don't care 
  // ------------------------- 
  // General helper functions 
  // ------------------------- 
  function automatic int minimum(int a, int b);
    return (a < b) ? a : b;
  endfunction
  function automatic int maximum(int a, int b);
    return (a > b) ? a : b;
  endfunction
  // ------------------------------------------- 
  // Helper functions for FP formats and values 
  // ------------------------------------------- 
  // Returns the width of a FP format 
  function automatic int unsigned fp_width(fp_format_e fmt);
    return FP_ENCODINGS[fmt].exp_bits + FP_ENCODINGS[fmt].man_bits + 1;
  endfunction
  // Returns the widest FP format present 
  function automatic int unsigned max_fp_width(fmt_logic_t cfg);
    automatic int unsigned res = 0;
    for (int unsigned i = 0; i < NUM_FP_FORMATS; i++)
      if (cfg[i])
        res = unsigned'(maximum(res, fp_width(fp_format_e'(i))));
    return res;
  endfunction
  // Returns the narrowest FP format present 
  function automatic int unsigned min_fp_width(fmt_logic_t cfg);
    automatic int unsigned res = max_fp_width(cfg);
    for (int unsigned i = 0; i < NUM_FP_FORMATS; i++)
      if (cfg[i])
        res = unsigned'(minimum(res, fp_width(fp_format_e'(i))));
    return res;
  endfunction
  // Returns the number of expoent bits for a format 
  function automatic int unsigned exp_bits(fp_format_e fmt);
    return FP_ENCODINGS[fmt].exp_bits;
  endfunction
  // Returns the number of mantissa bits for a format 
  function automatic int unsigned man_bits(fp_format_e fmt);
    return FP_ENCODINGS[fmt].man_bits;
  endfunction
  // Returns the bias value for a given format (as per IEEE 754-2008) 
  function automatic int unsigned bias(fp_format_e fmt);
    return unsigned'(2**(FP_ENCODINGS[fmt].exp_bits-1)-1); // symmetrical bias 
  endfunction
  function automatic fp_encoding_t super_format(fmt_logic_t cfg);
    automatic fp_encoding_t res;
    res = '0;
    for (int unsigned fmt = 0; fmt < NUM_FP_FORMATS; fmt++)
      if (cfg[fmt]) begin // only active format 
        res.exp_bits = unsigned'(maximum(res.exp_bits, exp_bits(fp_format_e'(fmt))));
        res.man_bits = unsigned'(maximum(res.man_bits, man_bits(fp_format_e'(fmt))));
      end
    return res;
  endfunction
  // ------------------------------------------- 
  // Helper functions for INT formats and values 
  // ------------------------------------------- 
  // Returns the widest INT format present 
  function automatic int unsigned max_int_width(ifmt_logic_t cfg);
    automatic int unsigned res = 0;
    for (int ifmt = 0; ifmt < NUM_INT_FORMATS; ifmt++) begin
      if (cfg[ifmt]) res = maximum(res, int_width(int_format_e'(ifmt)));
    end
    return res;
  endfunction
  // -------------------------------------------------- 
  // Helper functions for operations and FPU structure 
  // -------------------------------------------------- 
  // Returns the operation group of the given operation 
  function automatic opgroup_e get_opgroup(operation_e op);
    unique case (op)
      FMADD, FNMSUB, ADD, ADDS, MUL,
      TDOT_SIMD_FMADD, TDOT_DP_FMADD, TDOT_FP4_DP_FMADD,
      INT_DP_FMADD:                                              return ADDMUL;
      DIV, SQRT:                                                 return DIVSQRT;
      SGNJ, MINMAX, CMP, CLASSIFY:                               return NONCOMP;
      F2F, F2I, I2F, CPKAB, CPKCD:                               return CONV;
      default:                                                   return NONCOMP;
    endcase
  endfunction
  // Returns whether the operation selects TransDot DP behavior. 
  function automatic logic is_transdot_dp_op(operation_e op);
    return (op == TDOT_DP_FMADD) || (op == TDOT_FP4_DP_FMADD);
  endfunction
  // Returns whether the operation selects TransDot merged SIMD behavior. 
  function automatic logic is_transdot_simd_op(operation_e op);
    return (op == TDOT_SIMD_FMADD);
  endfunction
  // Returns whether the operation selects the FP4 TransDot path. 
  function automatic logic is_transdot_fp4_op(operation_e op);
    return (op == TDOT_FP4_DP_FMADD);
  endfunction
  // Returns whether the operation selects the INT DPA path (paper §III-C). 
  function automatic logic is_int_dp_op(operation_e op);
    return (op == INT_DP_FMADD);
  endfunction
  // Returns the number of operands by operation group 
  function automatic int unsigned num_operands(opgroup_e grp);
    unique case (grp)
      ADDMUL:  return 3;
      DIVSQRT: return 2;
      NONCOMP: return 2;
      CONV:    return 3; // vectorial casts use 3 operands 
      default: return 0;
    endcase
  endfunction
  // Returns the number of lanes according to width, format and vectors 
  function automatic int unsigned num_lanes(int unsigned width, fp_format_e fmt, logic vec);
    return vec ? width / fp_width(fmt) : 1; // if no vectors, only one lane 
  endfunction
  // Returns the maximum number of lanes in the FPU according to width, format config and vectors 
  function automatic int unsigned max_num_lanes(int unsigned width, fmt_logic_t cfg, logic vec);
    return vec ? width / min_fp_width(cfg) : 1; // if no vectors, only one lane 
  endfunction
    // Returns the maximum number of lanes in the FPU according to width, format config and vectors 
  function automatic int unsigned num_divsqrt_lanes(int unsigned width, fmt_logic_t cfg, logic vec, divsqrt_unit_t DivSqrtSel);
    automatic fmt_logic_t cfg_tmp;
    cfg_tmp = (DivSqrtSel == THMULTI) ? cfg & 7'b1110100 : cfg;
    return vec ? width / min_fp_width(cfg_tmp) : 1; // if no vectors, only one lane 
  endfunction
  // Returns a mask of active FP formats that are present in lane lane_no of a multiformat slice 
  function automatic fmt_logic_t get_lane_formats(int unsigned width,
                                                  fmt_logic_t cfg,
                                                  int unsigned lane_no);
    automatic fmt_logic_t res;
    for (int unsigned fmt = 0; fmt < NUM_FP_FORMATS; fmt++)
      // Mask active formats with the number of lanes for that format 
      res[fmt] = cfg[fmt] & (width / fp_width(fp_format_e'(fmt)) > lane_no);
    return res;
  endfunction
  // Returns a mask of active INT formats that are present in lane lane_no of a multiformat slice 
  function automatic ifmt_logic_t get_lane_int_formats(int unsigned width,
                                                       fmt_logic_t cfg,
                                                       ifmt_logic_t icfg,
                                                       int unsigned lane_no);
    automatic ifmt_logic_t res;
    automatic fmt_logic_t lanefmts;
    res = '0;
    lanefmts = get_lane_formats(width, cfg, lane_no);
    for (int unsigned ifmt = 0; ifmt < NUM_INT_FORMATS; ifmt++)
      for (int unsigned fmt = 0; fmt < NUM_FP_FORMATS; fmt++)
        // Mask active int formats with the width of the float formats 
        if ((fp_width(fp_format_e'(fmt)) == int_width(int_format_e'(ifmt))))
          res[ifmt] |= icfg[ifmt] && lanefmts[fmt];
    return res;
  endfunction
  // Returns a mask of active FP formats that are present in lane lane_no of a CONV slice 
  function automatic fmt_logic_t get_conv_lane_formats(int unsigned width,
                                                       fmt_logic_t cfg,
                                                       int unsigned lane_no);
    automatic fmt_logic_t res;
    for (int unsigned fmt = 0; fmt < NUM_FP_FORMATS; fmt++)
      // Mask active formats with the number of lanes for that format, CPK at least twice 
      res[fmt] = cfg[fmt] && ((width / fp_width(fp_format_e'(fmt)) > lane_no) ||
                             (CPK_FORMATS[fmt] && (lane_no < 2)));
    return res;
  endfunction
  // Returns a mask of active INT formats that are present in lane lane_no of a CONV slice 
  function automatic ifmt_logic_t get_conv_lane_int_formats(int unsigned width,
                                                            fmt_logic_t cfg,
                                                            ifmt_logic_t icfg,
                                                            int unsigned lane_no);
    automatic ifmt_logic_t res;
    automatic fmt_logic_t lanefmts;
    res = '0;
    lanefmts = get_conv_lane_formats(width, cfg, lane_no);
    for (int unsigned ifmt = 0; ifmt < NUM_INT_FORMATS; ifmt++)
      for (int unsigned fmt = 0; fmt < NUM_FP_FORMATS; fmt++)
        // Mask active int formats with the width of the float formats 
        res[ifmt] |= icfg[ifmt] && lanefmts[fmt] &&
                     (fp_width(fp_format_e'(fmt)) == int_width(int_format_e'(ifmt)));
    return res;
  endfunction
  // Return whether any active format is set as MERGED 
  function automatic logic any_enabled_multi(fmt_unit_types_t types, fmt_logic_t cfg);
    for (int unsigned i = 0; i < NUM_FP_FORMATS; i++)
      if (cfg[i] && types[i] == MERGED)
        return 1'b1;
      return 1'b0;
  endfunction
  // Return whether the given format is the first active one set as MERGED 
  function automatic logic is_first_enabled_multi(fp_format_e fmt,
                                                  fmt_unit_types_t types,
                                                  fmt_logic_t cfg);
    for (int unsigned i = 0; i < NUM_FP_FORMATS; i++) begin
      if (cfg[i] && types[i] == MERGED) return (fp_format_e'(i) == fmt);
    end
    return 1'b0;
  endfunction
  // Returns the first format that is active and is set as MERGED 
  function automatic fp_format_e get_first_enabled_multi(fmt_unit_types_t types, fmt_logic_t cfg);
    for (int unsigned i = 0; i < NUM_FP_FORMATS; i++)
      if (cfg[i] && types[i] == MERGED)
        return fp_format_e'(i);
      return fp_format_e'(0);
  endfunction
  // Returns the largest number of regs that is active and is set as MERGED 
  function automatic int unsigned get_num_regs_multi(fmt_unsigned_t regs,
                                                     fmt_unit_types_t types,
                                                     fmt_logic_t cfg);
    automatic int unsigned res = 0;
    for (int unsigned i = 0; i < NUM_FP_FORMATS; i++) begin
      if (cfg[i] && types[i] == MERGED) res = maximum(res, regs[i]);
    end
    return res;
  endfunction
endpackage
// Copyright (c) 2018 - 2019 ETH Zurich, University of Bologna 
// All rights reserved. 
// This code is under development and not yet released to the public. 
// Until it is released, the code is under the copyright of ETH Zurich and 
// the University of Bologna, and may contain confidential and/or unpublished 
// work. Any reuse/redistribution is strictly forbidden without written 
// permission from ETH Zurich. 
// Bug fixes and contributions will eventually be released under the 
// SolderPad open hardware license in the context of the PULP platform 
// (http://www.pulp-platform.org), under the copyright of ETH Zurich and the 
// University of Bologna. 
/// A trailing zero counter / leading zero counter. 
/// Set MODE to 0 for trailing zero counter => cnt_o is the number of trailing zeros (from the LSB) 
/// Set MODE to 1 for leading zero counter  => cnt_o is the number of leading zeros  (from the MSB) 
/// If the input does not contain a zero, `empty_o` is asserted. Additionally `cnt_o` contains 
/// the maximum number of zeros - 1. For example: 
///   in_i = 000_0000, empty_o = 1, cnt_o = 6 (mode = 0) 
///   in_i = 000_0001, empty_o = 0, cnt_o = 0 (mode = 0) 
///   in_i = 000_1000, empty_o = 0, cnt_o = 3 (mode = 0) 
/// Furthermore, this unit contains a more efficient implementation for Verilator (simulation only). 
/// This speeds up simulation significantly. 
module lzc #(
  /// The width of the input vector. 
  parameter int unsigned WIDTH = 2,
  /// Mode selection: 0 -> trailing zero, 1 -> leading zero 
  parameter bit          MODE  = 1'b0,
  /// Dependent parameter. Do **not** change! 
  /// 
  /// Width of the output signal with the zero count. 
  parameter int unsigned CNT_WIDTH = cf_math_pkg::idx_width(WIDTH)
) (
  /// Input vector to be counted. 
  input  logic [WIDTH-1:0]     in_i,
  /// Count of the leading / trailing zeros. 
  output logic [CNT_WIDTH-1:0] cnt_o,
  /// Counter is empty: Asserted if all bits in in_i are zero. 
  output logic                 empty_o
);
  if (WIDTH == 1) begin : gen_degenerate_lzc
    assign cnt_o[0] = !in_i[0];
    assign empty_o = !in_i[0];
  end else begin : gen_lzc
    localparam int unsigned NumLevels = $clog2(WIDTH);
    // pragma translate_off 
    initial begin
      assert(WIDTH > 0) else $fatal(1, "input must be at least one bit wide");
    end
    // pragma translate_on 
    logic [WIDTH-1:0][NumLevels-1:0] index_lut;
    logic [2**NumLevels-1:0] sel_nodes;
    logic [2**NumLevels-1:0][NumLevels-1:0] index_nodes;
    logic [WIDTH-1:0] in_tmp;
    // reverse vector if required 
    always_comb begin : flip_vector
      for (int unsigned i = 0; i < WIDTH; i++) begin
        in_tmp[i] = (MODE) ? in_i[WIDTH-1-i] : in_i[i];
      end
    end
    for (genvar j = 0; unsigned'(j) < WIDTH; j++) begin : g_index_lut
      assign index_lut[j] = (NumLevels)'(unsigned'(j));
    end
    for (genvar level = 0; unsigned'(level) < NumLevels; level++) begin : g_levels
      if (unsigned'(level) == NumLevels - 1) begin : g_last_level
        for (genvar k = 0; k < 2 ** level; k++) begin : g_level
          // if two successive indices are still in the vector... 
          if (unsigned'(k) * 2 < WIDTH - 1) begin : g_reduce
            assign sel_nodes[2 ** level - 1 + k] = in_tmp[k * 2] | in_tmp[k * 2 + 1];
            assign index_nodes[2 ** level - 1 + k] = (in_tmp[k * 2] == 1'b1)
              ? index_lut[k * 2] :
                index_lut[k * 2 + 1];
          end
          // if only the first index is still in the vector... 
          if (unsigned'(k) * 2 == WIDTH - 1) begin : g_base
            assign sel_nodes[2 ** level - 1 + k] = in_tmp[k * 2];
            assign index_nodes[2 ** level - 1 + k] = index_lut[k * 2];
          end
          // if index is out of range 
          if (unsigned'(k) * 2 > WIDTH - 1) begin : g_out_of_range
            assign sel_nodes[2 ** level - 1 + k] = 1'b0;
            assign index_nodes[2 ** level - 1 + k] = '0;
          end
        end
      end else begin : g_not_last_level
        for (genvar l = 0; l < 2 ** level; l++) begin : g_level
          assign sel_nodes[2 ** level - 1 + l] =
              sel_nodes[2 ** (level + 1) - 1 + l * 2] | sel_nodes[2 ** (level + 1) - 1 + l * 2 + 1];
          assign index_nodes[2 ** level - 1 + l] = (sel_nodes[2 ** (level + 1) - 1 + l * 2] == 1'b1)
            ? index_nodes[2 ** (level + 1) - 1 + l * 2] :
              index_nodes[2 ** (level + 1) - 1 + l * 2 + 1];
        end
      end
    end
    assign cnt_o = NumLevels > unsigned'(0) ? index_nodes[0] : {($clog2(WIDTH)) {1'b0}};
    assign empty_o = NumLevels > unsigned'(0) ? ~sel_nodes[0] : ~(|in_i);
  end : gen_lzc
endmodule : lzc
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
module fpnew_classifier #(
  parameter fpnew_pkg::fp_format_e   FpFormat = fpnew_pkg::fp_format_e'(0),
  parameter int unsigned             NumOperands = 1,
  // Do not change 
  localparam int unsigned WIDTH = fpnew_pkg::fp_width(FpFormat)
) (
  input  logic                [NumOperands-1:0][WIDTH-1:0] operands_i,
  input  logic                [NumOperands-1:0]            is_boxed_i,
  output fpnew_pkg::fp_info_t [NumOperands-1:0]            info_o
);
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);
  // Type definition 
  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;
  // Iterate through all operands 
  for (genvar op = 0; op < int'(NumOperands); op++) begin : gen_num_values
    fp_t value;
    logic is_boxed;
    logic is_normal;
    logic is_inf;
    logic is_nan;
    logic is_signalling;
    logic is_quiet;
    logic is_zero;
    logic is_subnormal;
    // --------------- 
    // Classify Input 
    // --------------- 
    always_comb begin : classify_input
      value         = operands_i[op];
      is_boxed      = is_boxed_i[op];
      is_normal     = is_boxed && (value.exponent != '0) && (value.exponent != '1);
      is_zero       = is_boxed && (value.exponent == '0) && (value.mantissa == '0);
      is_subnormal  = is_boxed && (value.exponent == '0) && !is_zero;
      is_inf        = is_boxed && ((value.exponent == '1) && (value.mantissa == '0));
      is_nan        = !is_boxed || ((value.exponent == '1) && (value.mantissa != '0));
      is_signalling = is_boxed && is_nan && (value.mantissa[MAN_BITS-1] == 1'b0);
      is_quiet      = is_nan && !is_signalling;
      // Assign output for current input 
      info_o[op].is_normal     = is_normal;
      info_o[op].is_subnormal  = is_subnormal;
      info_o[op].is_zero       = is_zero;
      info_o[op].is_inf        = is_inf;
      info_o[op].is_nan        = is_nan;
      info_o[op].is_signalling = is_signalling;
      info_o[op].is_quiet      = is_quiet;
      info_o[op].is_boxed      = is_boxed;
    end
  end
endmodule
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
module fpnew_rounding #(
  parameter int unsigned AbsWidth=2 // Width of the abolute value, without sign bit 
) (
  // Input value 
  input logic [AbsWidth-1:0]   abs_value_i,             // absolute value without sign 
  input logic                  sign_i,
  // Rounding information 
  input logic [1:0]            round_sticky_bits_i,     // round and sticky bits {RS} 
  input fpnew_pkg::roundmode_e rnd_mode_i,
  input logic                  effective_subtraction_i, // sign of inputs affects rounding of zeroes 
  // Output value 
  output logic [AbsWidth-1:0]  abs_rounded_o,           // absolute value without sign 
  output logic                 sign_o,
  // Output classification 
  output logic                 exact_zero_o             // output is an exact zero 
);
  logic round_up; // Rounding decision 
  // Take the rounding decision according to RISC-V spec 
  // RoundMode | Mnemonic | Meaning 
  // :--------:|:--------:|:------- 
  //    000    |   RNE    | Round to Nearest, ties to Even 
  //    001    |   RTZ    | Round towards Zero 
  //    010    |   RDN    | Round Down (towards -\infty) 
  //    011    |   RUP    | Round Up (towards \infty) 
  //    100    |   RMM    | Round to Nearest, ties to Max Magnitude 
  //    101    |   ROD    | Round towards odd (this mode is not define in RISC-V FP-SPEC) 
  //  others   |          | *invalid* 
  always_comb begin : rounding_decision
    unique case (rnd_mode_i)
      fpnew_pkg::RNE: // Decide accoring to round/sticky bits 
        unique case (round_sticky_bits_i)
          2'b00,
          2'b01: round_up = 1'b0;           // < ulp/2 away, round down 
          2'b10: round_up = abs_value_i[0]; // = ulp/2 away, round towards even result 
          2'b11: round_up = 1'b1;           // > ulp/2 away, round up 
          default: round_up = fpnew_pkg::DONT_CARE;
        endcase
      fpnew_pkg::RTZ: round_up = 1'b0; // always round down 
      fpnew_pkg::RDN: round_up = (| round_sticky_bits_i) ? sign_i  : 1'b0; // to 0 if +, away if - 
      fpnew_pkg::RUP: round_up = (| round_sticky_bits_i) ? ~sign_i : 1'b0; // to 0 if -, away if + 
      fpnew_pkg::RMM: round_up = round_sticky_bits_i[1]; // round down if < ulp/2 away, else up 
      fpnew_pkg::ROD: round_up = ~abs_value_i[0] & (| round_sticky_bits_i);
      default: round_up = fpnew_pkg::DONT_CARE; // propagate x 
    endcase
  end
  // Perform the rounding, exponent change and overflow to inf happens automagically 
  assign abs_rounded_o = abs_value_i + round_up;
  // True zero result is a zero result without dirty round/sticky bits 
  assign exact_zero_o = (abs_value_i == '0) && (round_sticky_bits_i == '0);
  // In case of effective subtraction (thus signs of addition operands must have differed) and a 
  // true zero result, the result sign is '-' in case of RDN and '+' for other modes. 
  assign sign_o = (exact_zero_o && effective_subtraction_i)
                  ? (rnd_mode_i == fpnew_pkg::RDN)
                  : sign_i;
endmodule
// DPA-16 PE: shared definitions. Reference model: ../model/dpa16_ref.py 
package dpa16_pkg;
  typedef enum logic [2:0] {
    FMT_FP16  = 3'd0,   // 16 x FP16 
    FMT_BF16  = 3'd1,   // 16 x BF16 
    FMT_TF32  = 3'd2,   //  8 x TF32 (32-bit containers) 
    FMT_FP8   = 3'd3,   // 32 x E4M3 / E5M2 (per side) 
    FMT_NVFP4 = 3'd4,   // 64 x E2M1, UE4M3 scale per 16 
    FMT_MXFP4 = 3'd5    // 64 x E2M1, E8M0 scale per 32 (given per 16-block) 
  } fmt_e;
  localparam int NTILE = 16;   // 12x12 multiplier tiles 
  localparam int NSLOT = 32;   // aligned product slots (FP8 uses all 32) 
  localparam int WIN   = 27;   // alignment window: 2 integer + 25 fraction bits 
  localparam int AW    = 12;   // signed anchor / exponent width 
  localparam int SUMW  = 34;   // signed sum of 33 window terms 
  localparam logic [31:0] QNAN = 32'h7FC0_0000;
endpackage
// DPA-16 operand unpack: routes the 256-bit operands to the 16 multiplier tiles and computes, per product slot, 
// the sign, the "nonzero" flag and the anchor exponent (weight of the product's units bit = sum of the two 
// unbiased exponents). FP4 elements become integers k (value k/2); their products are summed per 16-block later. 
//   FP16 / BF16 : tile t <- element t                 slot t      = product of tile t 
//   TF32        : tile t <- element t (t < 8)         slot t      = product of tile t 
//   FP8         : tile t <- elements 2t, 2t+1          slot s      = product of element s (tile s/2) 
//   FP4         : tile t <- elements 4t .. 4t+3        block b     = elements 16b .. 16b+15 (tiles 4b .. 4b+3) 
module dpa16_unpack import dpa16_pkg::*; (
  input  fmt_e                    fmt_i,
  input  logic                    a_e5m2_i,
  input  logic                    b_e5m2_i,
  input  logic [255:0]            a_i,
  input  logic [255:0]            b_i,
  input  logic [31:0]             sa_i,        // block scales (FP4 modes), byte b = block b 
  input  logic [31:0]             sb_i,
  output logic [NTILE-1:0][15:0]  ta_o,        // tile operands 
  output logic [NTILE-1:0][15:0]  tb_o,
  output logic [NSLOT-1:0]        ps_o,        // product sign 
  output logic [NSLOT-1:0]        pnz_o,       // product nonzero 
  output logic signed [AW-1:0]    panc_o [NSLOT],
  output logic [63:0]             s4_o,        // FP4 product signs 
  output logic [3:0][7:0]         ms_o,        // FP4 scale significand products 
  output logic [3:0]              bnz_o,       // FP4 block has a nonzero product (and nonzero scales) 
  output logic signed [AW-1:0]    banc_o [4],
  output logic                    special_o    // NaN / Inf among the active inputs 
);
  localparam logic [3:0] E2M1_K [8] = '{4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd6, 4'd8, 4'd12};
  // ---- element decoders: significand (with hidden bit), unbiased exponent of the units bit, special 
  typedef struct packed {
    logic                 s;
    logic [10:0]          sig;
    logic [7:0] ue;
    logic                 sp;
  } el_t;
  function automatic el_t dec16(logic [15:0] x, logic bf16);
    el_t r;
    r.s = x[15];
    if (bf16) begin
      r.sig = {x[14:7] != 0, x[6:0], 3'd0};
      r.ue  = 8'(x[14:7] != 0 ? x[14:7] : 8'd1);
      r.sp  = &x[14:7];
    end else begin
      r.sig = {x[14:10] != 0, x[9:0]};
      r.ue  = 8'(x[14:10] != 0 ? x[14:10] : 5'd1);
      r.sp  = &x[14:10];
    end
    return r;
  endfunction
  function automatic el_t dec_tf32(logic [31:0] x);
    el_t r;
    r.s   = x[31];
    r.sig = {x[30:23] != 0, x[22:13]};
    r.ue  = 8'(x[30:23] != 0 ? x[30:23] : 8'd1);
    r.sp  = &x[30:23];
    return r;
  endfunction
  function automatic el_t dec_fp8(logic [7:0] x, logic e5m2);
    el_t r;
    r.s = x[7];
    if (e5m2) begin
      r.sig = {7'd0, x[6:2] != 0, x[1:0], 1'b0};
      r.ue  = 8'(x[6:2] != 0 ? x[6:2] : 5'd1);
      r.sp  = &x[6:2];
    end else begin
      r.sig = {7'd0, x[6:3] != 0, x[2:0]};
      r.ue  = 8'(x[6:3] != 0 ? x[6:3] : 4'd1);
      r.sp  = &x[6:0];
    end
    return r;
  endfunction
  logic is16, isbf, istf, is8, is4, isnv;
  assign is16 = fmt_i == FMT_FP16 || fmt_i == FMT_BF16;
  assign isbf = fmt_i == FMT_BF16;
  assign istf = fmt_i == FMT_TF32;
  assign is8  = fmt_i == FMT_FP8;
  assign is4  = fmt_i == FMT_NVFP4 || fmt_i == FMT_MXFP4;
  assign isnv = fmt_i == FMT_NVFP4;
  logic [NSLOT-1:0][7:0] raw_a_exp, raw_b_exp;
  logic [NSLOT-1:0] exponent_active;
  for (genvar s = 0; s < NSLOT; s++) begin : g_pair_exp
    logic [8:0] raw_sum;
    assign raw_sum = {1'b0, raw_a_exp[s]} + {1'b0, raw_b_exp[s]};
    assign panc_o[s] = exponent_active[s] ? AW'({1'b0, raw_sum}) : '0;
  end
  logic sp_main, sp_fp4;
  always_comb begin
    logic sp;
    sp = 1'b0;
    for (int s = 0; s < NSLOT; s++) begin
      ps_o[s]   = 1'b0;
      pnz_o[s]  = 1'b0;
      raw_a_exp[s] = '0;
      raw_b_exp[s] = '0;
      exponent_active[s] = 1'b0;
    end
    for (int t = 0; t < NTILE; t++) begin
      ta_o[t] = '0;
      tb_o[t] = '0;
    end
    if (is16 || istf) begin
      for (int t = 0; t < NTILE; t++) begin
        el_t ea, eb;
        if (istf) begin
          ea = dec_tf32(a_i[32*(t%8) +: 32]);
          eb = dec_tf32(b_i[32*(t%8) +: 32]);
        end else begin
          ea = dec16(a_i[16*t +: 16], isbf);
          eb = dec16(b_i[16*t +: 16], isbf);
        end
        if (!istf || t < 8) begin
          ta_o[t]   = {5'd0, ea.sig};
          tb_o[t]   = {5'd0, eb.sig};
          ps_o[t]   = ea.s ^ eb.s;
          pnz_o[t]  = (ea.sig != 0) && (eb.sig != 0);
          raw_a_exp[t] = ea.ue;
          raw_b_exp[t] = eb.ue;
          exponent_active[t] = 1'b1;
          sp        = sp | ea.sp | eb.sp;
        end
      end
    end else if (is8) begin
      for (int s = 0; s < NSLOT; s++) begin
        el_t ea, eb;
        ea = dec_fp8(a_i[8*s +: 8], a_e5m2_i);
        eb = dec_fp8(b_i[8*s +: 8], b_e5m2_i);
        ta_o[s/2][4*(s%2) +: 4] = ea.sig[3:0];
        tb_o[s/2][4*(s%2) +: 4] = eb.sig[3:0];
        ps_o[s]   = ea.s ^ eb.s;
        pnz_o[s]  = (ea.sig != 0) && (eb.sig != 0);
        raw_a_exp[s] = ea.ue;
        raw_b_exp[s] = eb.ue;
        exponent_active[s] = 1'b1;
        sp        = sp | ea.sp | eb.sp;
      end
    end else if (is4) begin
      for (int i = 0; i < 64; i++) begin
        ta_o[i/4][4*(i%4) +: 4] = E2M1_K[a_i[4*i +: 3]];
        tb_o[i/4][4*(i%4) +: 4] = E2M1_K[b_i[4*i +: 3]];
      end
    end
    sp_main = sp;
  end
  // ---- FP4: product signs, block nonzero flags, scales 
  always_comb begin
    logic sp4;
    sp4 = 1'b0;
    for (int i = 0; i < 64; i++)
      s4_o[i] = a_i[4*i+3] ^ b_i[4*i+3];
    for (int blk = 0; blk < 4; blk++) begin
      logic                 any;
      logic [7:0]           xa, xb;
      logic [3:0]           ga, gb;
      logic signed [AW-1:0] ua, ub;
      any = 1'b0;
      for (int i = 16 * blk; i < 16 * blk + 16; i++)
        any = any | ((a_i[4*i +: 3] != 0) && (b_i[4*i +: 3] != 0));
      xa = sa_i[8*blk +: 8];
      xb = sb_i[8*blk +: 8];
      if (isnv) begin                         // UE4M3 (sign bit ignored) 
        ga  = {xa[6:3] != 0, xa[2:0]};
        gb  = {xb[6:3] != 0, xb[2:0]};
        ua  = AW'(xa[6:3] != 0 ? xa[6:3] : 4'd1);
        ub  = AW'(xb[6:3] != 0 ? xb[6:3] : 4'd1);
        sp4 = sp4 | (&xa[6:0]) | (&xb[6:0]);
      end else begin                          // E8M0 
        ga  = 4'b1000;
        gb  = 4'b1000;
        ua  = AW'(xa);
        ub  = AW'(xb);
        sp4 = sp4 | (&xa) | (&xb);
      end
      ms_o[blk]   = ga * gb;
      bnz_o[blk]  = is4 && any && (ga != 0) && (gb != 0);
      banc_o[blk] = ua + ub;
    end
    sp_fp4 = is4 && sp4;
  end
  assign special_o = sp_main | sp_fp4;
endmodule
// DPA tile: 3x3 grid of 4x4 blocks. Full product is consumed only in full mode.
// FP8 and FP4 consume dprod directly; unused cross products need no per-nibble isolation.
// The fourth FP4 product reuses block (0,1), with its operands selected from nibble 3.
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
        logic [3:0] x, y;
        x  = a_i[4*j +: 4];
        y  = b_i[4*k +: 4];
        if (j == 0 && k == 1 && m_fp4_i) begin
          x  = a_i[15:12];
          y  = b_i[15:12];
        end
        p[j][k] = x * y;
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
// DPA-16 stage 2: FP4 block scaling, then alignment of 32 product slots + the addend in a 27-bit window 
// (2 integer + 25 fraction bits, bits shifted out are truncated) and one signed sum. 
// Each term is first left-justified so that its units bit sits at window bit 25 (mode-dependent wiring), 
// then shifted right by its distance to the largest anchor. 
//   FP16 / TF32 : 11x11 product (22 b) << 5      BF16 : 8x8 product (16 b) << 11 
//   FP8         : 4x4 / 4x3 / 3x3 product << 19 / 20 / 21 (E4M3 / mixed / E5M2) 
//   FP4 block   : |block sum| x scale product (20 b) << 7          addend : 24-bit significand << 2 
//   vector lane l (M > 0): slots 8l .. 8l+3 = 12x12 partial products hh, hl, lh, ll (24 b) << 3, 
//                          slot 8l+4 = addend significand << 2; the sum tree is cut into 8-slot segments, 
//                          segment l is lane l's sum. 
// SHARE = 0: the GEMM sum is one multi-operand add over all 33 terms (as with M = 0); each vector lane has its own 
//            small add of its five terms, fed by the shared alignment shifters. 
// SHARE = 1: the adder tree is shared too: each lane's five terms are first compressed to carry-save form (three 3:2 
//            levels), the GEMM sum adds these pairs and the other terms; lane 0 is the GEMM sum (in vector mode the 
//            other lanes' pairs are gated off), lanes 1.. resolve their own pair with one carry-propagate add. 
// SHARE = 2: lane 0 rides the GEMM sum as is: in vector mode every slot outside the lanes is zero, so the plain 33-term 
//            sum is lane 0's sum once the terms of lanes 1.. are gated out of it; lanes 1.. keep their own small add. 
//            With M = 1 nothing is gated and the lane adds no adder at all. 
// RND = 1: every term gets one more bit below the window; for lane 0's five slots in vector mode it is the OR of the 
//          bits its alignment dropped (sticky, with the term's sign), else 0, so the sums are SUMW + 1 bits and the 
//          GEMM value is unchanged (twice the RND = 0 sum). Lane 0's normaliser rounds to nearest even on it. 
module dpa16_align_sum import dpa16_pkg::*; #(
  parameter int M     = 0,
  parameter int SHARE = 0,
  parameter int RND   = 0
) (
  input  logic [2:0]              fmt_i,
  input  logic [1:0]              e5_i,          // {a is E5M2, b is E5M2} 
  input  logic [NTILE-1:0][23:0]  tprod_i,
  input  logic [NSLOT-1:0]        ps_i,
  input  logic [4:0]              dsh_i [NSLOT+1],
  input  logic                    cs_i,
  input  logic [23:0]             cm_i,
  input  logic                    vec_i,
  input  logic [((M > 0) ? M : 1)-1:0][23:0] vcm_i,
  input logic shared_mode_i,
  input logic [12:0][63:0] scalar_rows_i,
  output logic [63:0] scalar_sum_o, scalar_carry_o,
  output logic [dpa16_pkg::SUMW-1:0] csa_sum_o,
  output logic [dpa16_pkg::SUMW-1:0] csa_carry_o,
  output logic signed [SUMW+RND-1:0] sum_o,
  output logic signed [SUMW+RND-1:0] vsum_o [(M > 0) ? M : 1]
);
  localparam int ML = (M > 0) ? M : 1;
  localparam int SW = SUMW + RND;
  logic [WIN-1:0] xj [NSLOT+1];      // left-justified magnitudes 
  logic [NSLOT:0] neg;
  always_comb begin
    for (int s = 0; s < NSLOT; s++) begin
      xj[s]  = '0;
      neg[s] = ps_i[s];
      // vector mode only rewires the lane slots: every other slot is shifted out by its saturated shift (the core 
      // clears all term flags in vector mode), so it needs no gating here 
      if (M > 0 && vec_i && s < 8 * M && s % 8 < 5) begin
        if (s % 8 < 4) xj[s] = {tprod_i[4*(s/8) + 3 - s%8], 3'd0};
        else           xj[s] = {1'b0, vcm_i[s/8], 2'd0};
      end else begin
        unique case (fmt_i)
          FMT_FP16, FMT_BF16, FMT_TF32: if (s < NTILE) xj[s] = {tprod_i[s][21:0], 5'd0};
          FMT_FP8:            xj[s] = WIN'(tprod_i[s/2][8*(s%2) +: 8]) << 5'd19;
          default: begin                                       // FP4: slots 0..3 = blocks 
            if (s < 4) begin
              logic signed [12:0] bs;
              logic [11:0]        mag;
              logic [19:0]        bm;
              bs     = tprod_i[s][12:0];
              mag    = bs[12] ? 12'(-bs) : bs[11:0];
              bm     = mag * tprod_i[s][20:13];
              xj[s]  = {bm, 7'd0};
              neg[s] = bs[12];
            end
          end
        endcase
      end
    end
    xj[NSLOT]  = {1'b0, cm_i, 2'd0};
    neg[NSLOT] = cs_i;
  end
  // align (+ sticky), negate (one's complement + carry-in) 
  logic signed [SW-1:0] t [NSLOT+1];
  always_comb begin
    for (int s = 0; s <= NSLOT; s++) begin
      logic [WIN-1:0]     al;
      logic [WIN+RND-1:0] x;
      logic [SW-1:0]      u;
      al = xj[s] >> dsh_i[s];
      if (RND > 0) x = {al, (M > 0 && vec_i && s < 8 * M && s % 8 < 5) ? |(xj[s] & ~({WIN{1'b1}} << dsh_i[s])) : 1'b0};
      else         x = al;
      u = SW'(al ^ {WIN{neg[s]}});
      t[s] = $signed(u);
    end
  end
  if (M > 0) begin : g_unused_csa
    assign csa_sum_o = '0;
    assign csa_carry_o = '0;
  end
  if (M > 0 && SHARE == 1) begin : g_share
    function automatic logic [1:0][SW-1:0] csa(logic [SW-1:0] a, logic [SW-1:0] b, logic [SW-1:0] c);
      return {SW'(((a & b) | (a & c) | (b & c)) << 1), a ^ b ^ c};     // {carry, sum}, mod 2^SW 
    endfunction
    logic [ML-1:0][SW-1:0] gs, gc;            // lane groups in carry-save form 
    always_comb begin
      for (int l = 0; l < ML; l++) begin
        logic [1:0][SW-1:0] r;
        r = csa(t[8*l], t[8*l + 1], t[8*l + 2]);
        r = csa(r[0], r[1], t[8*l + 3]);
        r = csa(r[0], r[1], t[8*l + 4]);
        gs[l] = r[0];
        gc[l] = r[1];
      end
    end
    always_comb begin
      sum_o = '0;
      for (int l = 0; l < ML; l++) begin
        logic [SW-1:0] g;
        g     = {SW{!(vec_i && l > 0)}};
        sum_o = sum_o + $signed(gs[l] & g) + $signed(gc[l] & g);
      end
      for (int s = 0; s <= NSLOT; s++)
        if (!(s < 8 * M && s % 8 < 5)) sum_o = sum_o + t[s];
    end
    always_comb begin
      vsum_o[0] = sum_o;
      for (int l = 1; l < ML; l++) vsum_o[l] = $signed(gs[l] + gc[l]);
    end
  end else if (M > 0 && SHARE == 2) begin : g_lane0
    always_comb begin
      sum_o = '0;
      for (int s = 0; s <= NSLOT; s++)
        if (s >= 8 && s < 8 * M && s % 8 < 5) sum_o = sum_o + (vec_i ? SW'(0) : t[s]);
        else                                  sum_o = sum_o + t[s];
    end
    always_comb begin
      vsum_o[0] = sum_o;
      for (int l = 1; l < ML; l++) begin
        vsum_o[l] = '0;
        for (int k = 0; k < 5; k++) vsum_o[l] = vsum_o[l] + t[8*l + k];
      end
    end
  end else begin : g_sep
    if (M == 0 && RND == 0) begin : g_csa
    logic [5:0] negative_count;
    logic [6:0] negative_count_mod;
    always_comb begin
      negative_count = '0;
      for (int s = 0; s <= NSLOT; s++) negative_count += 6'(neg[s]);
    end
    assign negative_count_mod = 7'd0 - {1'b0, negative_count};
    wire [32:0][26:0] heap_terms;
    for (genvar s = 0; s < 33; s++) assign heap_terms[s] = t[s][26:0];
    ucc_shared_heap i_shared_heap (
      .dpa_i(shared_mode_i), .dpa_terms_i(heap_terms), .negative_count_i(negative_count),
      .scalar_rows_i, .sum_o(scalar_sum_o), .carry_o(scalar_carry_o)
    );
    assign csa_sum_o = scalar_sum_o[33:0];
    assign csa_carry_o = scalar_carry_o[33:0];
    assign sum_o = $signed(csa_sum_o + csa_carry_o);
    end else begin : g_sum
      always_comb begin
        sum_o = '0;
        for (int s = 0; s <= NSLOT; s++) sum_o = sum_o + t[s];
      end
    end
    always_comb begin
      for (int l = 0; l < ML; l++) begin
        vsum_o[l] = '0;
        if (M > 0)
          for (int k = 0; k < 5; k++) vsum_o[l] = vsum_o[l] + t[8*l + k];
      end
    end
  end
endmodule
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
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
 // Copyright 2018 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// Common register defines for RTL designs 
// Abridged Summary of available FF macros: 
// `FF:      asynchronous active-low reset (implicit clock and reset) 
// `FFAR:    asynchronous active-high reset 
// `FFARN:   asynchronous active-low reset 
// `FFSR:    synchronous active-high reset 
// `FFSRN:   synchronous active-low reset 
// `FFNR:    without reset 
// `FFL:     load-enable and asynchronous active-low reset (implicit clock and reset) 
// `FFLAR:   load-enable and asynchronous active-high reset 
// `FFLARN:  load-enable and asynchronous active-low reset 
// `FFLARNC: load-enable and asynchronous active-low reset and synchronous active-high clear 
// `FFLSR:   load-enable and synchronous active-high reset 
// `FFLSRN:  load-enable and synchronous active-low reset 
// `FFLNR:   load-enable without reset 
// Flip-Flop with asynchronous active-low reset (implicit clock and reset) 
// __q: Q output of FF 
// __d: D input of FF 
// __reset_value: value assigned upon reset 
// Implicit: 
// clk_i: clock input 
// rst_ni: reset input (asynchronous, active low) 
// Flip-Flop with asynchronous active-high reset 
// __q: Q output of FF 
// __d: D input of FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __arst: asynchronous reset 
// Flip-Flop with asynchronous active-low reset 
// __q: Q output of FF 
// __d: D input of FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __arst_n: asynchronous reset 
// Flip-Flop with synchronous active-high reset 
// __q: Q output of FF 
// __d: D input of FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __reset_clk: reset input 
// Flip-Flop with synchronous active-low reset 
// __q: Q output of FF 
// __d: D input of FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __reset_n_clk: reset input 
// Always-enable Flip-Flop without reset 
// __q: Q output of FF 
// __d: D input of FF 
// __clk: clock input 
// Flip-Flop with load-enable and asynchronous active-low reset (implicit clock and reset) 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __reset_value: value assigned upon reset 
// Implicit: 
// clk_i: clock input 
// rst_ni: reset input (asynchronous, active low) 
// Flip-Flop with load-enable and asynchronous active-high reset 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __arst: asynchronous reset 
// Flip-Flop with load-enable and asynchronous active-low reset 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __arst_n: asynchronous reset 
// Flip-Flop with load-enable and synchronous active-high reset 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __reset_clk: reset input 
// Flip-Flop with load-enable and synchronous active-low reset 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __reset_n_clk: reset input 
// Flip-Flop with load-enable and asynchronous active-low reset and synchronous clear 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __clear: assign reset value into FF 
// __reset_value: value assigned upon reset 
// __clk: clock input 
// __arst_n: asynchronous reset 
// Load-enable Flip-Flop without reset 
// __q: Q output of FF 
// __d: D input of FF 
// __load: load d value into FF 
// __clk: clock input 
module fpnew_noncomp #(
  parameter fpnew_pkg::fp_format_e   FpFormat    = fpnew_pkg::fp_format_e'(0),
  parameter int unsigned             NumPipeRegs = 0,
  parameter fpnew_pkg::pipe_config_t PipeConfig  = fpnew_pkg::BEFORE,
  parameter type                     TagType     = logic,
  parameter type                     AuxType     = logic,
  // Do not change 
  localparam int unsigned WIDTH = fpnew_pkg::fp_width(FpFormat),
  localparam int unsigned ExtRegEnaWidth = NumPipeRegs == 0 ? 1 : NumPipeRegs
) (
  input logic                  clk_i,
  input logic                  rst_ni,
  // Input signals 
  input logic [1:0][WIDTH-1:0]     operands_i, // 2 operands 
  input logic [1:0]                is_boxed_i, // 2 operands 
  input fpnew_pkg::roundmode_e     rnd_mode_i,
  input fpnew_pkg::operation_e     op_i,
  input logic                      op_mod_i,
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
  output fpnew_pkg::classmask_e    class_mask_o,
  output logic                     is_class_o,
  output TagType                   tag_o,
  output logic                     mask_o,
  output AuxType                   aux_o,
  // Output handshake 
  output logic                     out_valid_o,
  input  logic                     out_ready_i,
  // Indication of valid data in flight 
  output logic                     busy_o,
  // External register enable override 
  input  logic [ExtRegEnaWidth-1:0] reg_ena_i,
  // Early valid for external structural hazard generation 
  output logic                     early_out_valid_o
);
  // ---------- 
  // Constants 
  // ---------- 
  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FpFormat);
  // Pipelines 
  localparam NUM_INP_REGS = (PipeConfig == fpnew_pkg::BEFORE || PipeConfig == fpnew_pkg::INSIDE)
                            ? NumPipeRegs
                            : (PipeConfig == fpnew_pkg::DISTRIBUTED
                               ? ((NumPipeRegs + 1) / 2) // First to get distributed regs 
                               : 0); // no regs here otherwise 
  localparam NUM_OUT_REGS = PipeConfig == fpnew_pkg::AFTER
                            ? NumPipeRegs
                            : (PipeConfig == fpnew_pkg::DISTRIBUTED
                               ? (NumPipeRegs / 2) // Last to get distributed regs 
                               : 0); // no regs here otherwise 
  // ---------------- 
  // Type definition 
  // ---------------- 
  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;
  // --------------- 
  // Input pipeline 
  // --------------- 
  // Input pipeline signals, index i holds signal after i register stages 
  logic                  [0:NUM_INP_REGS][1:0][WIDTH-1:0] inp_pipe_operands_q;
  logic                  [0:NUM_INP_REGS][1:0]            inp_pipe_is_boxed_q;
  fpnew_pkg::roundmode_e [0:NUM_INP_REGS]                 inp_pipe_rnd_mode_q;
  fpnew_pkg::operation_e [0:NUM_INP_REGS]                 inp_pipe_op_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_op_mod_q;
  TagType                [0:NUM_INP_REGS]                 inp_pipe_tag_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_mask_q;
  AuxType                [0:NUM_INP_REGS]                 inp_pipe_aux_q;
  logic                  [0:NUM_INP_REGS]                 inp_pipe_valid_q;
  // Ready signal is combinatorial for all stages 
  logic [0:NUM_INP_REGS] inp_pipe_ready;
  // Input stage: First element of pipeline is taken from inputs 
  assign inp_pipe_operands_q[0] = operands_i;
  assign inp_pipe_is_boxed_q[0] = is_boxed_i;
  assign inp_pipe_rnd_mode_q[0] = rnd_mode_i;
  assign inp_pipe_op_q[0]       = op_i;
  assign inp_pipe_op_mod_q[0]   = op_mod_i;
  assign inp_pipe_tag_q[0]      = tag_i;
  assign inp_pipe_mask_q[0]     = mask_i;
  assign inp_pipe_aux_q[0]      = aux_i;
  assign inp_pipe_valid_q[0]    = in_valid_i;
  // Input stage: Propagate pipeline ready signal to updtream circuitry 
  assign in_ready_o = inp_pipe_ready[0];
  // Generate the register stages 
  for (genvar i = 0; i < NUM_INP_REGS; i++) begin : gen_input_pipeline
    // Internal register enable for this stage 
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline: 
    // 1. if the next stage is ready for our data 
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it 
    assign inp_pipe_ready[i] = inp_pipe_ready[i+1] | ~inp_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal 
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      inp_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      inp_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (inp_pipe_ready[i]) ? (inp_pipe_valid_q[i]) : (inp_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (inp_pipe_ready[i] & inp_pipe_valid_q[i]) | reg_ena_i[i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_operands_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_operands_q[i+1] <= (reg_ena) ? (inp_pipe_operands_q[i]) : (inp_pipe_operands_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_is_boxed_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_is_boxed_q[i+1] <= (reg_ena) ? (inp_pipe_is_boxed_q[i]) : (inp_pipe_is_boxed_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_rnd_mode_q[i+1] <= (fpnew_pkg::RNE);                        
    end else begin                                   
      inp_pipe_rnd_mode_q[i+1] <= (reg_ena) ? (inp_pipe_rnd_mode_q[i]) : (inp_pipe_rnd_mode_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_op_q[i+1] <= (fpnew_pkg::FMADD);                        
    end else begin                                   
      inp_pipe_op_q[i+1] <= (reg_ena) ? (inp_pipe_op_q[i]) : (inp_pipe_op_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_op_mod_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_op_mod_q[i+1] <= (reg_ena) ? (inp_pipe_op_mod_q[i]) : (inp_pipe_op_mod_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      inp_pipe_tag_q[i+1] <= (reg_ena) ? (inp_pipe_tag_q[i]) : (inp_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_mask_q[i+1] <= (reg_ena) ? (inp_pipe_mask_q[i]) : (inp_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      inp_pipe_aux_q[i+1] <= (reg_ena) ? (inp_pipe_aux_q[i]) : (inp_pipe_aux_q[i+1]);               
    end                                              
  end
  end
  // --------------------- 
  // Input classification 
  // --------------------- 
  fpnew_pkg::fp_info_t [1:0] info_q;
  // Classify input 
  fpnew_classifier #(
    .FpFormat    ( FpFormat ),
    .NumOperands ( 2        )
    ) i_class_a (
    .operands_i ( inp_pipe_operands_q[NUM_INP_REGS] ),
    .is_boxed_i ( inp_pipe_is_boxed_q[NUM_INP_REGS] ),
    .info_o     ( info_q                            )
  );
  fp_t                 operand_a, operand_b;
  fpnew_pkg::fp_info_t info_a,    info_b;
  // Packing-order-agnostic assignments 
  assign operand_a = inp_pipe_operands_q[NUM_INP_REGS][0];
  assign operand_b = inp_pipe_operands_q[NUM_INP_REGS][1];
  assign info_a    = info_q[0];
  assign info_b    = info_q[1];
  logic any_operand_inf;
  logic any_operand_nan;
  logic signalling_nan;
  // Reduction for special case handling 
  assign any_operand_inf = (| {info_a.is_inf,        info_b.is_inf});
  assign any_operand_nan = (| {info_a.is_nan,        info_b.is_nan});
  assign signalling_nan  = (| {info_a.is_signalling, info_b.is_signalling});
  logic operands_equal, operand_a_smaller;
  // Equality checks for zeroes too 
  assign operands_equal    = (operand_a == operand_b) || (info_a.is_zero && info_b.is_zero);
  // Invert result if non-zero signs involved (unsigned comparison) 
  assign operand_a_smaller = (operand_a < operand_b) ^ (operand_a.sign || operand_b.sign);
  // --------------- 
  // Sign Injection 
  // --------------- 
  fp_t                sgnj_result;
  fpnew_pkg::status_t sgnj_status;
  logic               sgnj_extension_bit;
  // Sign Injection - operation is encoded in rnd_mode_q: 
  // RNE = SGNJ, RTZ = SGNJN, RDN = SGNJX, RUP = Passthrough (no NaN-box check) 
  always_comb begin : sign_injections
    logic sign_a, sign_b; // internal signs 
    // Default assignment 
    sgnj_result = operand_a; // result based on operand a 
    // NaN-boxing check will treat invalid inputs as canonical NaNs 
    if (!info_a.is_boxed) sgnj_result = '{sign: 1'b0, exponent: '1, mantissa: 2**(MAN_BITS-1)};
    // Internal signs are treated as positive in case of non-NaN-boxed values 
    sign_a = operand_a.sign & info_a.is_boxed;
    sign_b = operand_b.sign & info_b.is_boxed;
    // Do the sign injection based on rm field 
    unique case (inp_pipe_rnd_mode_q[NUM_INP_REGS])
      fpnew_pkg::RNE: sgnj_result.sign = sign_b;          // SGNJ 
      fpnew_pkg::RTZ: sgnj_result.sign = ~sign_b;         // SGNJN 
      fpnew_pkg::RDN: sgnj_result.sign = sign_a ^ sign_b; // SGNJX 
      fpnew_pkg::RUP: sgnj_result      = operand_a;       // passthrough 
      default: sgnj_result = '{default: fpnew_pkg::DONT_CARE}; // don't care 
    endcase
  end
  assign sgnj_status = '0;        // sign injections never raise exceptions 
  // op_mod_q enables integer sign-extension of result (for storing to integer regfile) 
  assign sgnj_extension_bit = inp_pipe_op_mod_q[NUM_INP_REGS] ? sgnj_result.sign : 1'b1;
  // ------------------ 
  // Minimum / Maximum 
  // ------------------ 
  fp_t                minmax_result;
  fpnew_pkg::status_t minmax_status;
  logic               minmax_extension_bit;
  // Minimum/Maximum - operation is encoded in rnd_mode_q: 
  // RNE = MIN, RTZ = MAX 
  always_comb begin : min_max
    // Default assignment 
    minmax_status = '0;
    // Min/Max use quiet comparisons - only sNaN are invalid 
    minmax_status.NV = signalling_nan;
    // Both NaN inputs cause a NaN output 
    if (info_a.is_nan && info_b.is_nan)
      minmax_result = '{sign: 1'b0, exponent: '1, mantissa: 2**(MAN_BITS-1)}; // canonical qNaN 
    // If one operand is NaN, the non-NaN operand is returned 
    else if (info_a.is_nan) minmax_result = operand_b;
    else if (info_b.is_nan) minmax_result = operand_a;
    // Otherwise decide according to the operation 
    else begin
      unique case (inp_pipe_rnd_mode_q[NUM_INP_REGS])
        fpnew_pkg::RNE: minmax_result = operand_a_smaller ? operand_a : operand_b; // MIN 
        fpnew_pkg::RTZ: minmax_result = operand_a_smaller ? operand_b : operand_a; // MAX 
        default: minmax_result = '{default: fpnew_pkg::DONT_CARE}; // don't care 
      endcase
    end
  end
  assign minmax_extension_bit = 1'b1; // NaN-box as result is always a float value 
  // ------------ 
  // Comparisons 
  // ------------ 
  fp_t                cmp_result;
  fpnew_pkg::status_t cmp_status;
  logic               cmp_extension_bit;
  // Comparisons - operation is encoded in rnd_mode_q: 
  // RNE = LE, RTZ = LT, RDN = EQ 
  // op_mod_q inverts boolean outputs 
  always_comb begin : comparisons
    // Default assignment 
    cmp_result = '0; // false 
    cmp_status = '0; // no flags 
    // Signalling NaNs always compare as false (except for "not equal" compares) and are illegal 
    if (signalling_nan) begin
      cmp_status.NV = 1'b1; // invalid operation 
      cmp_result    = inp_pipe_rnd_mode_q[NUM_INP_REGS] == fpnew_pkg::RDN && inp_pipe_op_mod_q[NUM_INP_REGS];
    // Otherwise do comparisons 
    end else begin
      unique case (inp_pipe_rnd_mode_q[NUM_INP_REGS])
        fpnew_pkg::RNE: begin // Less than or equal 
          if (any_operand_nan) cmp_status.NV = 1'b1; // Signalling comparison: NaNs are invalid 
          else cmp_result = (operand_a_smaller | operands_equal) ^ inp_pipe_op_mod_q[NUM_INP_REGS];
        end
        fpnew_pkg::RTZ: begin // Less than 
          if (any_operand_nan) cmp_status.NV = 1'b1; // Signalling comparison: NaNs are invalid 
          else cmp_result = (operand_a_smaller & ~operands_equal) ^ inp_pipe_op_mod_q[NUM_INP_REGS];
        end
        fpnew_pkg::RDN: begin // Equal 
          if (any_operand_nan) cmp_result = inp_pipe_op_mod_q[NUM_INP_REGS]; // NaN always not equal 
          else cmp_result = operands_equal ^ inp_pipe_op_mod_q[NUM_INP_REGS];
        end
        default: cmp_result = '{default: fpnew_pkg::DONT_CARE}; // don't care 
      endcase
    end
  end
  assign cmp_extension_bit = 1'b0; // Comparisons always produce booleans in integer registers 
  // --------------- 
  // Classification 
  // --------------- 
  fpnew_pkg::status_t    class_status;
  logic                  class_extension_bit;
  fpnew_pkg::classmask_e class_mask_d; // the result is actually here 
  // Classification - always return the classification mask on the dedicated port 
  always_comb begin : classify
    if (info_a.is_normal) begin
      class_mask_d = operand_a.sign       ? fpnew_pkg::NEGNORM    : fpnew_pkg::POSNORM;
    end else if (info_a.is_subnormal) begin
      class_mask_d = operand_a.sign       ? fpnew_pkg::NEGSUBNORM : fpnew_pkg::POSSUBNORM;
    end else if (info_a.is_zero) begin
      class_mask_d = operand_a.sign       ? fpnew_pkg::NEGZERO    : fpnew_pkg::POSZERO;
    end else if (info_a.is_inf) begin
      class_mask_d = operand_a.sign       ? fpnew_pkg::NEGINF     : fpnew_pkg::POSINF;
    end else if (info_a.is_nan) begin
      class_mask_d = info_a.is_signalling ? fpnew_pkg::SNAN       : fpnew_pkg::QNAN;
    end else begin
      class_mask_d = fpnew_pkg::QNAN; // default value 
    end
  end
  assign class_status        = '0;   // classification does not set flags 
  assign class_extension_bit = 1'b0; // classification always produces results in integer registers 
  // ----------------- 
  // Result selection 
  // ----------------- 
  fp_t                   result_d;
  fpnew_pkg::status_t    status_d;
  logic                  extension_bit_d;
  logic                  is_class_d;
  // Select result 
  always_comb begin : select_result
    unique case (inp_pipe_op_q[NUM_INP_REGS])
      fpnew_pkg::SGNJ: begin
        result_d        = sgnj_result;
        status_d        = sgnj_status;
        extension_bit_d = sgnj_extension_bit;
      end
      fpnew_pkg::MINMAX: begin
        result_d        = minmax_result;
        status_d        = minmax_status;
        extension_bit_d = minmax_extension_bit;
      end
      fpnew_pkg::CMP: begin
        result_d        = cmp_result;
        status_d        = cmp_status;
        extension_bit_d = cmp_extension_bit;
      end
      fpnew_pkg::CLASSIFY: begin
        result_d        = '{default: fpnew_pkg::DONT_CARE}; // unused 
        status_d        = class_status;
        extension_bit_d = class_extension_bit;
      end
      default: begin
        result_d        = '{default: fpnew_pkg::DONT_CARE}; // dont care 
        status_d        = '{default: fpnew_pkg::DONT_CARE}; // dont care 
        extension_bit_d = fpnew_pkg::DONT_CARE;             // dont care 
      end
    endcase
  end
  assign is_class_d = (inp_pipe_op_q[NUM_INP_REGS] == fpnew_pkg::CLASSIFY);
  // ---------------- 
  // Output Pipeline 
  // ---------------- 
  // Output pipeline signals, index i holds signal after i register stages 
  fp_t                   [0:NUM_OUT_REGS] out_pipe_result_q;
  fpnew_pkg::status_t    [0:NUM_OUT_REGS] out_pipe_status_q;
  logic                  [0:NUM_OUT_REGS] out_pipe_extension_bit_q;
  fpnew_pkg::classmask_e [0:NUM_OUT_REGS] out_pipe_class_mask_q;
  logic                  [0:NUM_OUT_REGS] out_pipe_is_class_q;
  TagType                [0:NUM_OUT_REGS] out_pipe_tag_q;
  logic                  [0:NUM_OUT_REGS] out_pipe_mask_q;
  AuxType                [0:NUM_OUT_REGS] out_pipe_aux_q;
  logic                  [0:NUM_OUT_REGS] out_pipe_valid_q;
  // Ready signal is combinatorial for all stages 
  logic [0:NUM_OUT_REGS] out_pipe_ready;
  // Input stage: First element of pipeline is taken from inputs 
  assign out_pipe_result_q[0]        = result_d;
  assign out_pipe_status_q[0]        = status_d;
  assign out_pipe_extension_bit_q[0] = extension_bit_d;
  assign out_pipe_class_mask_q[0]    = class_mask_d;
  assign out_pipe_is_class_q[0]      = is_class_d;
  assign out_pipe_tag_q[0]           = inp_pipe_tag_q[NUM_INP_REGS];
  assign out_pipe_mask_q[0]          = inp_pipe_mask_q[NUM_INP_REGS];
  assign out_pipe_aux_q[0]           = inp_pipe_aux_q[NUM_INP_REGS];
  assign out_pipe_valid_q[0]         = inp_pipe_valid_q[NUM_INP_REGS];
  // Input stage: Propagate pipeline ready signal to inside pipe 
  assign inp_pipe_ready[NUM_INP_REGS] = out_pipe_ready[0];
  // Generate the register stages 
  for (genvar i = 0; i < NUM_OUT_REGS; i++) begin : gen_output_pipeline
    // Internal register enable for this stage 
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline: 
    // 1. if the next stage is ready for our data 
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it 
    assign out_pipe_ready[i] = out_pipe_ready[i+1] | ~out_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal 
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      out_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      out_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (out_pipe_ready[i]) ? (out_pipe_valid_q[i]) : (out_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (out_pipe_ready[i] & out_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_result_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_result_q[i+1] <= (reg_ena) ? (out_pipe_result_q[i]) : (out_pipe_result_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_status_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_status_q[i+1] <= (reg_ena) ? (out_pipe_status_q[i]) : (out_pipe_status_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_extension_bit_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_extension_bit_q[i+1] <= (reg_ena) ? (out_pipe_extension_bit_q[i]) : (out_pipe_extension_bit_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_class_mask_q[i+1] <= (fpnew_pkg::QNAN);                        
    end else begin                                   
      out_pipe_class_mask_q[i+1] <= (reg_ena) ? (out_pipe_class_mask_q[i]) : (out_pipe_class_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_is_class_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_is_class_q[i+1] <= (reg_ena) ? (out_pipe_is_class_q[i]) : (out_pipe_is_class_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      out_pipe_tag_q[i+1] <= (reg_ena) ? (out_pipe_tag_q[i]) : (out_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_mask_q[i+1] <= (reg_ena) ? (out_pipe_mask_q[i]) : (out_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      out_pipe_aux_q[i+1] <= (reg_ena) ? (out_pipe_aux_q[i]) : (out_pipe_aux_q[i+1]);               
    end                                              
  end
  end
  // Output stage: Ready travels backwards from output side, driven by downstream circuitry 
  assign out_pipe_ready[NUM_OUT_REGS] = out_ready_i;
  // Output stage: assign module outputs 
  assign result_o        = out_pipe_result_q[NUM_OUT_REGS];
  assign status_o        = out_pipe_status_q[NUM_OUT_REGS];
  assign extension_bit_o = out_pipe_extension_bit_q[NUM_OUT_REGS];
  assign class_mask_o    = out_pipe_class_mask_q[NUM_OUT_REGS];
  assign is_class_o      = out_pipe_is_class_q[NUM_OUT_REGS];
  assign tag_o           = out_pipe_tag_q[NUM_OUT_REGS];
  assign mask_o          = out_pipe_mask_q[NUM_OUT_REGS];
  assign aux_o           = out_pipe_aux_q[NUM_OUT_REGS];
  assign out_valid_o     = out_pipe_valid_q[NUM_OUT_REGS];
  assign busy_o          = (| {inp_pipe_valid_q, out_pipe_valid_q});
  // Early valid_o signal. This is used for dispatching instructions for dual-issue processor. 
  if (NUM_OUT_REGS > 0) begin
    assign early_out_valid_o = |{out_pipe_valid_q[NUM_OUT_REGS] & ~out_pipe_ready[NUM_OUT_REGS],
                                 out_pipe_valid_q[NUM_OUT_REGS-1]};
  end else if (NUM_INP_REGS > 0) begin
    assign early_out_valid_o = |{inp_pipe_valid_q[NUM_INP_REGS] & ~inp_pipe_ready[NUM_INP_REGS],
                                 inp_pipe_valid_q[NUM_INP_REGS-1]};
  end else begin
    assign early_out_valid_o = 1'b0;
  end
endmodule
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
 // Copyright 2018 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// Common register defines for RTL designs 
module fpnew_cast_multi #(
  parameter fpnew_pkg::fmt_logic_t   FpFmtConfig  = '1,
  parameter fpnew_pkg::ifmt_logic_t  IntFmtConfig = '1,
  // FPU configuration 
  parameter int unsigned             NumPipeRegs = 0,
  parameter fpnew_pkg::pipe_config_t PipeConfig  = fpnew_pkg::BEFORE,
  parameter type                     TagType     = logic,
  parameter type                     AuxType     = logic,
  // Do not change 
  localparam int unsigned WIDTH = fpnew_pkg::maximum(fpnew_pkg::max_fp_width(FpFmtConfig),
                                                     fpnew_pkg::max_int_width(IntFmtConfig)),
  localparam int unsigned NUM_FORMATS = fpnew_pkg::NUM_FP_FORMATS,
  localparam int unsigned ExtRegEnaWidth = NumPipeRegs == 0 ? 1 : NumPipeRegs
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  // Input signals 
  input  logic [WIDTH-1:0]       operands_i, // 1 operand 
  input  logic [NUM_FORMATS-1:0] is_boxed_i, // 1 operand 
  input  fpnew_pkg::roundmode_e  rnd_mode_i,
  input  fpnew_pkg::operation_e  op_i,
  input  logic                   op_mod_i,
  input  fpnew_pkg::fp_format_e  src_fmt_i,
  input  fpnew_pkg::fp_format_e  dst_fmt_i,
  input  fpnew_pkg::int_format_e int_fmt_i,
  input  TagType                 tag_i,
  input  logic                   mask_i,
  input  AuxType                 aux_i,
  // Input Handshake 
  input  logic                   in_valid_i,
  output logic                   in_ready_o,
  input  logic                   flush_i,
  // Output signals 
  output logic [WIDTH-1:0]       result_o,
  output fpnew_pkg::status_t     status_o,
  output logic                   extension_bit_o,
  output TagType                 tag_o,
  output logic                   mask_o,
  output AuxType                 aux_o,
  // Output handshake 
  output logic                   out_valid_o,
  input  logic                   out_ready_i,
  // Indication of valid data in flight 
  output logic                   busy_o,
  // External register enable override 
  input  logic [ExtRegEnaWidth-1:0] reg_ena_i,
  // Early valid for external structural hazard generation 
  output logic                   early_out_valid_o
);
  // ---------- 
  // Constants 
  // ---------- 
  localparam int unsigned NUM_INT_FORMATS = fpnew_pkg::NUM_INT_FORMATS;
  localparam int unsigned MAX_INT_WIDTH   = fpnew_pkg::max_int_width(IntFmtConfig);
  localparam fpnew_pkg::fp_encoding_t SUPER_FORMAT = fpnew_pkg::super_format(FpFmtConfig);
  localparam int unsigned SUPER_EXP_BITS = SUPER_FORMAT.exp_bits;
  localparam int unsigned SUPER_MAN_BITS = SUPER_FORMAT.man_bits;
  localparam int unsigned SUPER_BIAS     = 2**(SUPER_EXP_BITS - 1) - 1;
  // The internal mantissa includes normal bit or an entire integer 
  localparam int unsigned INT_MAN_WIDTH = fpnew_pkg::maximum(SUPER_MAN_BITS + 1, MAX_INT_WIDTH);
  // If needed, there will be a LZC for renormalization 
  localparam int unsigned LZC_RESULT_WIDTH = $clog2(INT_MAN_WIDTH);
  // The internal exponent must be able to represent the smallest denormal input value as signed 
  // or the number of bits in an integer 
  localparam int unsigned INT_EXP_WIDTH = fpnew_pkg::maximum($clog2(MAX_INT_WIDTH),
      fpnew_pkg::maximum(SUPER_EXP_BITS, $clog2(SUPER_BIAS + SUPER_MAN_BITS))) + 1;
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
  // --------------- 
  // Input pipeline 
  // --------------- 
  // Selected pipeline output signals as non-arrays 
  logic [WIDTH-1:0]       operands_q;
  logic [NUM_FORMATS-1:0] is_boxed_q;
  logic                   op_mod_q;
  fpnew_pkg::fp_format_e  src_fmt_q;
  fpnew_pkg::fp_format_e  dst_fmt_q;
  fpnew_pkg::int_format_e int_fmt_q;
  // Input pipeline signals, index i holds signal after i register stages 
  logic                   [0:NUM_INP_REGS][WIDTH-1:0]       inp_pipe_operands_q;
  logic                   [0:NUM_INP_REGS][NUM_FORMATS-1:0] inp_pipe_is_boxed_q;
  fpnew_pkg::roundmode_e  [0:NUM_INP_REGS]                  inp_pipe_rnd_mode_q;
  fpnew_pkg::operation_e  [0:NUM_INP_REGS]                  inp_pipe_op_q;
  logic                   [0:NUM_INP_REGS]                  inp_pipe_op_mod_q;
  fpnew_pkg::fp_format_e  [0:NUM_INP_REGS]                  inp_pipe_src_fmt_q;
  fpnew_pkg::fp_format_e  [0:NUM_INP_REGS]                  inp_pipe_dst_fmt_q;
  fpnew_pkg::int_format_e [0:NUM_INP_REGS]                  inp_pipe_int_fmt_q;
  TagType                 [0:NUM_INP_REGS]                  inp_pipe_tag_q;
  logic                   [0:NUM_INP_REGS]                  inp_pipe_mask_q;
  AuxType                 [0:NUM_INP_REGS]                  inp_pipe_aux_q;
  logic                   [0:NUM_INP_REGS]                  inp_pipe_valid_q;
  // Ready signal is combinatorial for all stages 
  logic [0:NUM_INP_REGS] inp_pipe_ready;
  // Input stage: First element of pipeline is taken from inputs 
  assign inp_pipe_operands_q[0] = operands_i;
  assign inp_pipe_is_boxed_q[0] = is_boxed_i;
  assign inp_pipe_rnd_mode_q[0] = rnd_mode_i;
  assign inp_pipe_op_q[0]       = op_i;
  assign inp_pipe_op_mod_q[0]   = op_mod_i;
  assign inp_pipe_src_fmt_q[0]  = src_fmt_i;
  assign inp_pipe_dst_fmt_q[0]  = dst_fmt_i;
  assign inp_pipe_int_fmt_q[0]  = int_fmt_i;
  assign inp_pipe_tag_q[0]      = tag_i;
  assign inp_pipe_mask_q[0]     = mask_i;
  assign inp_pipe_aux_q[0]      = aux_i;
  assign inp_pipe_valid_q[0]    = in_valid_i;
  // Input stage: Propagate pipeline ready signal to updtream circuitry 
  assign in_ready_o = inp_pipe_ready[0];
  // Generate the register stages 
  for (genvar i = 0; i < NUM_INP_REGS; i++) begin : gen_input_pipeline
    // Internal register enable for this stage 
    logic reg_ena;
    // Determine the ready signal of the current stage - advance the pipeline: 
    // 1. if the next stage is ready for our data 
    // 2. if the next stage only holds a bubble (not valid) -> we can pop it 
    assign inp_pipe_ready[i] = inp_pipe_ready[i+1] | ~inp_pipe_valid_q[i+1];
    // Valid: enabled by ready signal, synchronous clear with the flush signal 
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      inp_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      inp_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (inp_pipe_ready[i]) ? (inp_pipe_valid_q[i]) : (inp_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (inp_pipe_ready[i] & inp_pipe_valid_q[i]) | reg_ena_i[i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_operands_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_operands_q[i+1] <= (reg_ena) ? (inp_pipe_operands_q[i]) : (inp_pipe_operands_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_is_boxed_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_is_boxed_q[i+1] <= (reg_ena) ? (inp_pipe_is_boxed_q[i]) : (inp_pipe_is_boxed_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_rnd_mode_q[i+1] <= (fpnew_pkg::RNE);                        
    end else begin                                   
      inp_pipe_rnd_mode_q[i+1] <= (reg_ena) ? (inp_pipe_rnd_mode_q[i]) : (inp_pipe_rnd_mode_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_op_q[i+1] <= (fpnew_pkg::FMADD);                        
    end else begin                                   
      inp_pipe_op_q[i+1] <= (reg_ena) ? (inp_pipe_op_q[i]) : (inp_pipe_op_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_op_mod_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_op_mod_q[i+1] <= (reg_ena) ? (inp_pipe_op_mod_q[i]) : (inp_pipe_op_mod_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_src_fmt_q[i+1] <= (fpnew_pkg::fp_format_e'(0));                        
    end else begin                                   
      inp_pipe_src_fmt_q[i+1] <= (reg_ena) ? (inp_pipe_src_fmt_q[i]) : (inp_pipe_src_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_dst_fmt_q[i+1] <= (fpnew_pkg::fp_format_e'(0));                        
    end else begin                                   
      inp_pipe_dst_fmt_q[i+1] <= (reg_ena) ? (inp_pipe_dst_fmt_q[i]) : (inp_pipe_dst_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_int_fmt_q[i+1] <= (fpnew_pkg::int_format_e'(0));                        
    end else begin                                   
      inp_pipe_int_fmt_q[i+1] <= (reg_ena) ? (inp_pipe_int_fmt_q[i]) : (inp_pipe_int_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      inp_pipe_tag_q[i+1] <= (reg_ena) ? (inp_pipe_tag_q[i]) : (inp_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_mask_q[i+1] <= (reg_ena) ? (inp_pipe_mask_q[i]) : (inp_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      inp_pipe_aux_q[i+1] <= (reg_ena) ? (inp_pipe_aux_q[i]) : (inp_pipe_aux_q[i+1]);               
    end                                              
  end
  end
  // Output stage: assign selected pipe outputs to signals for later use 
  assign operands_q = inp_pipe_operands_q[NUM_INP_REGS];
  assign is_boxed_q = inp_pipe_is_boxed_q[NUM_INP_REGS];
  assign op_mod_q   = inp_pipe_op_mod_q[NUM_INP_REGS];
  assign src_fmt_q  = inp_pipe_src_fmt_q[NUM_INP_REGS];
  assign dst_fmt_q  = inp_pipe_dst_fmt_q[NUM_INP_REGS];
  assign int_fmt_q  = inp_pipe_int_fmt_q[NUM_INP_REGS];
  // ----------------- 
  // Input processing 
  // ----------------- 
  logic src_is_int, dst_is_int; // if 0, it's a float 
  assign src_is_int = (inp_pipe_op_q[NUM_INP_REGS] == fpnew_pkg::I2F);
  assign dst_is_int = (inp_pipe_op_q[NUM_INP_REGS] == fpnew_pkg::F2I);
  logic [INT_MAN_WIDTH-1:0] encoded_mant; // input mantissa with implicit bit 
  logic        [NUM_FORMATS-1:0]                    fmt_sign;
  logic signed [NUM_FORMATS-1:0][INT_EXP_WIDTH-1:0] fmt_exponent;
  logic        [NUM_FORMATS-1:0][INT_MAN_WIDTH-1:0] fmt_mantissa;
  logic signed [NUM_FORMATS-1:0][INT_EXP_WIDTH-1:0] fmt_shift_compensation; // for LZC 
  fpnew_pkg::fp_info_t [NUM_FORMATS-1:0] info;
  logic [NUM_INT_FORMATS-1:0][INT_MAN_WIDTH-1:0] ifmt_input_val;
  logic                                          int_sign;
  logic [INT_MAN_WIDTH-1:0]                      int_value, int_mantissa;
  // FP Input initialization 
  for (genvar fmt = 0; fmt < int'(NUM_FORMATS); fmt++) begin : fmt_init_inputs
    // Set up some constants 
    localparam int unsigned FP_WIDTH = fpnew_pkg::fp_width(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(fpnew_pkg::fp_format_e'(fmt));
    if (FpFmtConfig[fmt]) begin : active_format
      localparam fpnew_pkg::fp_format_e FpFormat = fpnew_pkg::fp_format_e'(fmt);
      // Classify input 
      fpnew_classifier #(
        .FpFormat    ( FpFormat ),
        .NumOperands ( 1        )
      ) i_fpnew_classifier (
        .operands_i ( operands_q[FP_WIDTH-1:0] ),
        .is_boxed_i ( is_boxed_q[fmt]          ),
        .info_o     ( info[fmt]                )
      );
      assign fmt_sign[fmt]     = operands_q[FP_WIDTH-1];
      assign fmt_exponent[fmt] = signed'({1'b0, operands_q[MAN_BITS+:EXP_BITS]});
      assign fmt_mantissa[fmt] = {info[fmt].is_normal, operands_q[MAN_BITS-1:0]}; // zero pad 
      // Compensation for the difference in mantissa widths used for leading-zero count 
      assign fmt_shift_compensation[fmt] = signed'(INT_MAN_WIDTH - 1 - MAN_BITS);
    end else begin : inactive_format
      assign info[fmt]                   = '{default: fpnew_pkg::DONT_CARE}; // format disabled 
      assign fmt_sign[fmt]               = fpnew_pkg::DONT_CARE;             // format disabled 
      assign fmt_exponent[fmt]           = '{default: fpnew_pkg::DONT_CARE}; // format disabled 
      assign fmt_mantissa[fmt]           = '{default: fpnew_pkg::DONT_CARE}; // format disabled 
      assign fmt_shift_compensation[fmt] = '{default: fpnew_pkg::DONT_CARE}; // format disabled 
    end
  end
  // Sign-extend INT input 
  for (genvar ifmt = 0; ifmt < int'(NUM_INT_FORMATS); ifmt++) begin : gen_sign_extend_int
    // Set up some constants 
    localparam int unsigned INT_WIDTH = fpnew_pkg::int_width(fpnew_pkg::int_format_e'(ifmt));
    if (IntFmtConfig[ifmt]) begin : active_format // only active formats 
      always_comb begin : sign_ext_input
        // sign-extend value only if it's signed 
        ifmt_input_val[ifmt]                = '{default: operands_q[INT_WIDTH-1] & ~op_mod_q};
        ifmt_input_val[ifmt][INT_WIDTH-1:0] = operands_q[INT_WIDTH-1:0];
      end
    end else begin : inactive_format
      assign ifmt_input_val[ifmt] = '{default: fpnew_pkg::DONT_CARE}; // format disabled 
    end
  end
  // Construct input mantissa from integer 
  assign int_value    = ifmt_input_val[int_fmt_q];
  assign int_sign     = int_value[INT_MAN_WIDTH-1] & ~op_mod_q; // only signed ints are negative 
  assign int_mantissa = int_sign ? unsigned'(-int_value) : int_value; // get magnitude of negative 
  // select mantissa with source format 
  assign encoded_mant = src_is_int ? int_mantissa : fmt_mantissa[src_fmt_q];
  // -------------- 
  // Normalization 
  // -------------- 
  logic signed [INT_EXP_WIDTH-1:0] src_bias;      // src format bias 
  logic signed [INT_EXP_WIDTH-1:0] src_exp;       // src format exponent (biased) 
  logic signed [INT_EXP_WIDTH-1:0] src_subnormal; // src is subnormal 
  logic signed [INT_EXP_WIDTH-1:0] src_offset;    // src offset within mantissa 
  assign src_bias      = signed'(fpnew_pkg::bias(src_fmt_q));
  assign src_exp       = fmt_exponent[src_fmt_q];
  assign src_subnormal = signed'({1'b0, info[src_fmt_q].is_subnormal});
  assign src_offset    = fmt_shift_compensation[src_fmt_q];
  logic                            input_sign;   // input sign 
  logic signed [INT_EXP_WIDTH-1:0] input_exp;    // unbiased true exponent 
  logic        [INT_MAN_WIDTH-1:0] input_mant;   // normalized input mantissa 
  logic                            mant_is_zero; // for integer zeroes 
  logic signed [INT_EXP_WIDTH-1:0] fp_input_exp;
  logic signed [INT_EXP_WIDTH-1:0] int_input_exp;
  // Input mantissa needs to be normalized 
  logic [LZC_RESULT_WIDTH-1:0] renorm_shamt;     // renormalization shift amount 
  logic [LZC_RESULT_WIDTH:0]   renorm_shamt_sgn; // signed form for calculations 
  // Leading-zero counter is needed for renormalization 
  lzc #(
    .WIDTH ( INT_MAN_WIDTH ),
    .MODE  ( 1             ) // MODE = 1 counts leading zeroes 
  ) i_lzc (
    .in_i    ( encoded_mant ),
    .cnt_o   ( renorm_shamt ),
    .empty_o ( mant_is_zero )
  );
  assign renorm_shamt_sgn = signed'({1'b0, renorm_shamt});
  // Get the sign from the proper source 
  assign input_sign = src_is_int ? int_sign : fmt_sign[src_fmt_q];
  // Realign input mantissa, append zeroes if destination is wider 
  assign input_mant = encoded_mant << renorm_shamt;
  // Unbias exponent and compensate for shift 
  assign fp_input_exp  = signed'(src_exp + src_subnormal - src_bias -
                                 renorm_shamt_sgn + src_offset); // compensate for shift 
  assign int_input_exp = signed'(INT_MAN_WIDTH - 1 - renorm_shamt_sgn);
  assign input_exp     = src_is_int ? int_input_exp : fp_input_exp;
  logic signed [INT_EXP_WIDTH-1:0] destination_exp;  // re-biased exponent for destination 
  // Rebias the exponent 
  assign destination_exp = input_exp + signed'(fpnew_pkg::bias(dst_fmt_q));
  // --------------- 
  // Internal pipeline 
  // --------------- 
  // Pipeline output signals as non-arrays 
  logic                            input_sign_q;
  logic signed [INT_EXP_WIDTH-1:0] input_exp_q;
  logic [INT_MAN_WIDTH-1:0]        input_mant_q;
  logic signed [INT_EXP_WIDTH-1:0] destination_exp_q;
  logic                            src_is_int_q;
  logic                            dst_is_int_q;
  fpnew_pkg::fp_info_t             info_q;
  logic                            mant_is_zero_q;
  logic                            op_mod_q2;
  fpnew_pkg::roundmode_e           rnd_mode_q;
  fpnew_pkg::fp_format_e           src_fmt_q2;
  fpnew_pkg::fp_format_e           dst_fmt_q2;
  fpnew_pkg::int_format_e          int_fmt_q2;
  // Internal pipeline signals, index i holds signal after i register stages 
  logic                   [0:NUM_MID_REGS]                    mid_pipe_input_sign_q;
  logic signed            [0:NUM_MID_REGS][INT_EXP_WIDTH-1:0] mid_pipe_input_exp_q;
  logic                   [0:NUM_MID_REGS][INT_MAN_WIDTH-1:0] mid_pipe_input_mant_q;
  logic signed            [0:NUM_MID_REGS][INT_EXP_WIDTH-1:0] mid_pipe_dest_exp_q;
  logic                   [0:NUM_MID_REGS]                    mid_pipe_src_is_int_q;
  logic                   [0:NUM_MID_REGS]                    mid_pipe_dst_is_int_q;
  fpnew_pkg::fp_info_t    [0:NUM_MID_REGS]                    mid_pipe_info_q;
  logic                   [0:NUM_MID_REGS]                    mid_pipe_mant_zero_q;
  logic                   [0:NUM_MID_REGS]                    mid_pipe_op_mod_q;
  fpnew_pkg::roundmode_e  [0:NUM_MID_REGS]                    mid_pipe_rnd_mode_q;
  fpnew_pkg::fp_format_e  [0:NUM_MID_REGS]                    mid_pipe_src_fmt_q;
  fpnew_pkg::fp_format_e  [0:NUM_MID_REGS]                    mid_pipe_dst_fmt_q;
  fpnew_pkg::int_format_e [0:NUM_MID_REGS]                    mid_pipe_int_fmt_q;
  TagType                 [0:NUM_MID_REGS]                    mid_pipe_tag_q;
  logic                   [0:NUM_MID_REGS]                    mid_pipe_mask_q;
  AuxType                 [0:NUM_MID_REGS]                    mid_pipe_aux_q;
  logic                   [0:NUM_MID_REGS]                    mid_pipe_valid_q;
  // Ready signal is combinatorial for all stages 
  logic [0:NUM_MID_REGS] mid_pipe_ready;
  // Input stage: First element of pipeline is taken from upstream logic 
  assign mid_pipe_input_sign_q[0] = input_sign;
  assign mid_pipe_input_exp_q[0]  = input_exp;
  assign mid_pipe_input_mant_q[0] = input_mant;
  assign mid_pipe_dest_exp_q[0]   = destination_exp;
  assign mid_pipe_src_is_int_q[0] = src_is_int;
  assign mid_pipe_dst_is_int_q[0] = dst_is_int;
  assign mid_pipe_info_q[0]       = info[src_fmt_q];
  assign mid_pipe_mant_zero_q[0]  = mant_is_zero;
  assign mid_pipe_op_mod_q[0]     = op_mod_q;
  assign mid_pipe_rnd_mode_q[0]   = inp_pipe_rnd_mode_q[NUM_INP_REGS];
  assign mid_pipe_src_fmt_q[0]    = src_fmt_q;
  assign mid_pipe_dst_fmt_q[0]    = dst_fmt_q;
  assign mid_pipe_int_fmt_q[0]    = int_fmt_q;
  assign mid_pipe_tag_q[0]        = inp_pipe_tag_q[NUM_INP_REGS];
  assign mid_pipe_mask_q[0]       = inp_pipe_mask_q[NUM_INP_REGS];
  assign mid_pipe_aux_q[0]        = inp_pipe_aux_q[NUM_INP_REGS];
  assign mid_pipe_valid_q[0]      = inp_pipe_valid_q[NUM_INP_REGS];
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
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      mid_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      mid_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (mid_pipe_ready[i]) ? (mid_pipe_valid_q[i]) : (mid_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (mid_pipe_ready[i] & mid_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_input_sign_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_input_sign_q[i+1] <= (reg_ena) ? (mid_pipe_input_sign_q[i]) : (mid_pipe_input_sign_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_input_exp_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_input_exp_q[i+1] <= (reg_ena) ? (mid_pipe_input_exp_q[i]) : (mid_pipe_input_exp_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_input_mant_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_input_mant_q[i+1] <= (reg_ena) ? (mid_pipe_input_mant_q[i]) : (mid_pipe_input_mant_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_dest_exp_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_dest_exp_q[i+1] <= (reg_ena) ? (mid_pipe_dest_exp_q[i]) : (mid_pipe_dest_exp_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_src_is_int_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_src_is_int_q[i+1] <= (reg_ena) ? (mid_pipe_src_is_int_q[i]) : (mid_pipe_src_is_int_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_dst_is_int_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_dst_is_int_q[i+1] <= (reg_ena) ? (mid_pipe_dst_is_int_q[i]) : (mid_pipe_dst_is_int_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_info_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_info_q[i+1] <= (reg_ena) ? (mid_pipe_info_q[i]) : (mid_pipe_info_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_mant_zero_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_mant_zero_q[i+1] <= (reg_ena) ? (mid_pipe_mant_zero_q[i]) : (mid_pipe_mant_zero_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_op_mod_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_op_mod_q[i+1] <= (reg_ena) ? (mid_pipe_op_mod_q[i]) : (mid_pipe_op_mod_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_rnd_mode_q[i+1] <= (fpnew_pkg::RNE);                        
    end else begin                                   
      mid_pipe_rnd_mode_q[i+1] <= (reg_ena) ? (mid_pipe_rnd_mode_q[i]) : (mid_pipe_rnd_mode_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_src_fmt_q[i+1] <= (fpnew_pkg::fp_format_e'(0));                        
    end else begin                                   
      mid_pipe_src_fmt_q[i+1] <= (reg_ena) ? (mid_pipe_src_fmt_q[i]) : (mid_pipe_src_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_dst_fmt_q[i+1] <= (fpnew_pkg::fp_format_e'(0));                        
    end else begin                                   
      mid_pipe_dst_fmt_q[i+1] <= (reg_ena) ? (mid_pipe_dst_fmt_q[i]) : (mid_pipe_dst_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_int_fmt_q[i+1] <= (fpnew_pkg::int_format_e'(0));                        
    end else begin                                   
      mid_pipe_int_fmt_q[i+1] <= (reg_ena) ? (mid_pipe_int_fmt_q[i]) : (mid_pipe_int_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      mid_pipe_tag_q[i+1] <= (reg_ena) ? (mid_pipe_tag_q[i]) : (mid_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_mask_q[i+1] <= (reg_ena) ? (mid_pipe_mask_q[i]) : (mid_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      mid_pipe_aux_q[i+1] <= (reg_ena) ? (mid_pipe_aux_q[i]) : (mid_pipe_aux_q[i+1]);               
    end                                              
  end
  end
  // Output stage: assign selected pipe outputs to signals for later use 
  assign input_sign_q      = mid_pipe_input_sign_q[NUM_MID_REGS];
  assign input_exp_q       = mid_pipe_input_exp_q[NUM_MID_REGS];
  assign input_mant_q      = mid_pipe_input_mant_q[NUM_MID_REGS];
  assign destination_exp_q = mid_pipe_dest_exp_q[NUM_MID_REGS];
  assign src_is_int_q      = mid_pipe_src_is_int_q[NUM_MID_REGS];
  assign dst_is_int_q      = mid_pipe_dst_is_int_q[NUM_MID_REGS];
  assign info_q            = mid_pipe_info_q[NUM_MID_REGS];
  assign mant_is_zero_q    = mid_pipe_mant_zero_q[NUM_MID_REGS];
  assign op_mod_q2         = mid_pipe_op_mod_q[NUM_MID_REGS];
  assign rnd_mode_q        = mid_pipe_rnd_mode_q[NUM_MID_REGS];
  assign src_fmt_q2        = mid_pipe_src_fmt_q[NUM_MID_REGS];
  assign dst_fmt_q2        = mid_pipe_dst_fmt_q[NUM_MID_REGS];
  assign int_fmt_q2        = mid_pipe_int_fmt_q[NUM_MID_REGS];
  // -------- 
  // Casting 
  // -------- 
  logic [INT_EXP_WIDTH-1:0] final_exp;        // after eventual adjustments 
  logic [2*INT_MAN_WIDTH:0]  preshift_mant;    // mantissa before final shift 
  logic [2*INT_MAN_WIDTH:0]  destination_mant; // mantissa from shifter, with rnd bit 
  logic [SUPER_MAN_BITS-1:0] final_mant;       // mantissa after adjustments 
  logic [MAX_INT_WIDTH-1:0]  final_int;        // integer shifted in position 
  logic [$clog2(INT_MAN_WIDTH+1)-1:0] denorm_shamt; // shift amount for denormalization 
  logic [1:0] fp_round_sticky_bits, int_round_sticky_bits, round_sticky_bits;
  logic       of_before_round, uf_before_round;
  // Perform adjustments to mantissa and exponent 
  always_comb begin : cast_value
    // Default assignment 
    final_exp       = unsigned'(destination_exp_q); // take exponent as is, only look at lower bits 
    preshift_mant   = '0;  // initialize mantissa container with zeroes 
    denorm_shamt    = SUPER_MAN_BITS - fpnew_pkg::man_bits(dst_fmt_q2); // right of mantissa 
    of_before_round = 1'b0;
    uf_before_round = 1'b0;
    // Place mantissa to the left of the shifter 
    preshift_mant = input_mant_q << (INT_MAN_WIDTH + 1);
    // Handle INT casts 
    if (dst_is_int_q) begin
      // By default right shift mantissa to be an integer 
      denorm_shamt = unsigned'(MAX_INT_WIDTH - 1 - input_exp_q);
      // overflow: when converting to unsigned the range is larger by one 
      if ((input_exp_q >= signed'(fpnew_pkg::int_width(int_fmt_q2) - 1 + op_mod_q2))    // Exponent larger than max int range, 
          && !(!op_mod_q2                                                               // unless cast to signed int 
               && input_sign_q                                                          // and input value is larges negative int value 
               && (input_exp_q == signed'(fpnew_pkg::int_width(int_fmt_q2) - 1))
               && (input_mant_q == {1'b1, {INT_MAN_WIDTH-1{1'b0}}}))) begin
        denorm_shamt    = '0; // prevent shifting 
        of_before_round = 1'b1;
      // underflow 
      end else if (input_exp_q < -1) begin
        denorm_shamt    = MAX_INT_WIDTH + 1; // all bits go to the sticky 
        uf_before_round = 1'b1;
      end
    // Handle FP over-/underflows 
    end else begin
      // Infinities 
      if (~src_is_int_q && info_q.is_inf) begin
        final_exp       = unsigned'(2**fpnew_pkg::exp_bits(dst_fmt_q2)-1); // largest exponent 
        preshift_mant   = '0;
      // Overflow (for proper rounding) 
      end else if (destination_exp_q >= signed'(2**fpnew_pkg::exp_bits(dst_fmt_q2))-1) begin
        final_exp       = unsigned'(2**fpnew_pkg::exp_bits(dst_fmt_q2)-2); // largest normal value 
        preshift_mant   = '1;                           // largest normal value and RS bits set 
        of_before_round = 1'b1;
      // Denormalize underflowing values 
      end else if (destination_exp_q < 1 &&
                   destination_exp_q >= -signed'(fpnew_pkg::man_bits(dst_fmt_q2))) begin
        final_exp       = '0; // denormal result 
        denorm_shamt    = unsigned'(denorm_shamt + 1 - destination_exp_q); // adjust right shifting 
        uf_before_round = 1'b1;
      // Limit the shift to retain sticky bits 
      end else if (destination_exp_q < -signed'(fpnew_pkg::man_bits(dst_fmt_q2))) begin
        final_exp       = '0; // denormal result 
        denorm_shamt    = unsigned'(denorm_shamt + 2 + fpnew_pkg::man_bits(dst_fmt_q2)); // to sticky 
        uf_before_round = 1'b1;
      end
    end
  end
  localparam NUM_FP_STICKY  = 2 * INT_MAN_WIDTH - SUPER_MAN_BITS - 1; // removed mantissa, 1. and R 
  localparam NUM_INT_STICKY = 2 * INT_MAN_WIDTH - MAX_INT_WIDTH; // removed int and R 
  // Mantissa adjustment shift 
  assign destination_mant = preshift_mant >> denorm_shamt;
  // Extract final mantissa and round bit, discard the normal bit (for FP) 
  assign {final_mant, fp_round_sticky_bits[1]} =
      destination_mant[2*INT_MAN_WIDTH-1-:SUPER_MAN_BITS+1];
  assign {final_int, int_round_sticky_bits[1]} = destination_mant[2*INT_MAN_WIDTH-:MAX_INT_WIDTH+1];
  // Collapse sticky bits 
  assign fp_round_sticky_bits[0]  = (| {destination_mant[NUM_FP_STICKY-1:0]});
  assign int_round_sticky_bits[0] = (| {destination_mant[NUM_INT_STICKY-1:0]});
  // select RS bits for destination operation 
  assign round_sticky_bits = dst_is_int_q ? int_round_sticky_bits : fp_round_sticky_bits;
  // ---------------------------- 
  // Rounding and classification 
  // ---------------------------- 
  logic [WIDTH-1:0] pre_round_abs;  // absolute value of result before rnd 
  logic             of_after_round; // overflow 
  logic             uf_after_round; // underflow 
  logic [NUM_FORMATS-1:0][WIDTH-1:0] fmt_pre_round_abs; // per format 
  logic [NUM_FORMATS-1:0]            fmt_of_after_round;
  logic [NUM_FORMATS-1:0]            fmt_uf_after_round;
  logic [NUM_INT_FORMATS-1:0][WIDTH-1:0] ifmt_pre_round_abs;      // per format 
  logic [NUM_INT_FORMATS-1:0][WIDTH-1:0] ifmt_rounded_signed_res; // per format 
  logic [NUM_INT_FORMATS-1:0]            ifmt_of_after_round;
  logic             rounded_sign;
  logic [WIDTH-1:0] rounded_abs; // absolute value of result after rounding 
  logic             result_true_zero;
  logic [WIDTH-1:0] rounded_uint_res;     // after possible inversion 
  logic [WIDTH-1:0] rounded_int_res;      // sign-extended, after possible inversion 
  logic             rounded_int_res_zero; // after rounding 
  // Pack exponent and mantissa into proper rounding form 
  for (genvar fmt = 0; fmt < int'(NUM_FORMATS); fmt++) begin : gen_res_assemble
    // Set up some constants 
    localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(fpnew_pkg::fp_format_e'(fmt));
    if (FpFmtConfig[fmt]) begin : active_format
      always_comb begin : assemble_result
        fmt_pre_round_abs[fmt] = {final_exp[EXP_BITS-1:0], final_mant[MAN_BITS-1:0]}; // 0-extend 
      end
    end else begin : inactive_format
      assign fmt_pre_round_abs[fmt] = '{default: fpnew_pkg::DONT_CARE};
    end
  end
  // Zero-extend integer result 
  for (genvar ifmt = 0; ifmt < int'(NUM_INT_FORMATS); ifmt++) begin : gen_int_res_zero_ext
    // Set up some constants 
    localparam int unsigned INT_WIDTH = fpnew_pkg::int_width(fpnew_pkg::int_format_e'(ifmt));
    if (IntFmtConfig[ifmt]) begin : active_format
      always_comb begin : assemble_result
        // zero-extend absolute value result 
        ifmt_pre_round_abs[ifmt]                = '0;
        ifmt_pre_round_abs[ifmt][INT_WIDTH-1:0] = final_int[INT_WIDTH-1:0];
      end
    end else begin : inactive_format
      assign ifmt_pre_round_abs[ifmt] = '{default: fpnew_pkg::DONT_CARE};
    end
  end
  // Select output with destination format and operation 
  assign pre_round_abs = dst_is_int_q ? ifmt_pre_round_abs[int_fmt_q2] : fmt_pre_round_abs[dst_fmt_q2];
  fpnew_rounding #(
    .AbsWidth ( WIDTH )
  ) i_fpnew_rounding (
    .abs_value_i             ( pre_round_abs     ),
    .sign_i                  ( input_sign_q      ), // source format 
    .round_sticky_bits_i     ( round_sticky_bits ),
    .rnd_mode_i              ( rnd_mode_q        ),
    .effective_subtraction_i ( 1'b0              ), // no operation happened 
    .abs_rounded_o           ( rounded_abs       ),
    .sign_o                  ( rounded_sign      ),
    .exact_zero_o            ( result_true_zero  )
  );
  logic [NUM_FORMATS-1:0][WIDTH-1:0] fmt_result;
  // Detect overflows and inject sign 
  for (genvar fmt = 0; fmt < int'(NUM_FORMATS); fmt++) begin : gen_sign_inject
    // Set up some constants 
    localparam int unsigned FP_WIDTH = fpnew_pkg::fp_width(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(fpnew_pkg::fp_format_e'(fmt));
    if (FpFmtConfig[fmt]) begin : active_format
      always_comb begin : post_process
        // detect of / uf 
        fmt_uf_after_round[fmt] = rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '0; // denormal 
        fmt_of_after_round[fmt] = rounded_abs[EXP_BITS+MAN_BITS-1:MAN_BITS] == '1; // inf exp. 
        // Assemble regular result, nan box short ones. Int zeroes need to be detected` 
        fmt_result[fmt]               = '1;
        fmt_result[fmt][FP_WIDTH-1:0] = src_is_int_q & mant_is_zero_q
                                        ? '0
                                        : {rounded_sign, rounded_abs[EXP_BITS+MAN_BITS-1:0]};
      end
    end else begin : inactive_format
      assign fmt_uf_after_round[fmt] = fpnew_pkg::DONT_CARE;
      assign fmt_of_after_round[fmt] = fpnew_pkg::DONT_CARE;
      assign fmt_result[fmt]         = '{default: fpnew_pkg::DONT_CARE};
    end
  end
  // Negative integer result needs to be brought into two's complement 
  assign rounded_uint_res      = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
    // Sign-extend integer result 
  for (genvar ifmt = 0; ifmt < int'(NUM_INT_FORMATS); ifmt++) begin : gen_int_res_sign_ext
    // Set up some constants 
    localparam int unsigned INT_WIDTH = fpnew_pkg::int_width(fpnew_pkg::int_format_e'(ifmt));
    if (IntFmtConfig[ifmt]) begin : active_format
      always_comb begin : assemble_result
        // zero-extend absolute value result 
        ifmt_rounded_signed_res[ifmt]                = '{default: rounded_uint_res[INT_WIDTH-1]};
        ifmt_rounded_signed_res[ifmt][INT_WIDTH-1:0] = rounded_uint_res[INT_WIDTH-1:0];
      end
    end else begin : inactive_format
      assign ifmt_rounded_signed_res[ifmt] = '{default: fpnew_pkg::DONT_CARE};
    end
  end
  assign rounded_int_res = ifmt_rounded_signed_res[int_fmt_q2];
  assign rounded_int_res_zero = (rounded_int_res == '0);
  // Detect integer overflows after rounding (only positives) 
  for (genvar ifmt = 0; ifmt < int'(NUM_INT_FORMATS); ifmt++) begin : gen_int_overflow
    // Set up some constants 
    localparam int unsigned INT_WIDTH = fpnew_pkg::int_width(fpnew_pkg::int_format_e'(ifmt));
    if (IntFmtConfig[ifmt]) begin : active_format
      always_comb begin : detect_overflow
        ifmt_of_after_round[ifmt] = 1'b0;
        // Int result can overflow if we're at the max exponent 
        if (!rounded_sign && input_exp_q == signed'(INT_WIDTH - 2 + op_mod_q2)) begin
          // Check whether the rounded MSB differs from unrounded MSB 
          ifmt_of_after_round[ifmt] = ~rounded_int_res[INT_WIDTH-2+op_mod_q2];
        end
      end
    end else begin : inactive_format
      assign ifmt_of_after_round[ifmt] = fpnew_pkg::DONT_CARE;
    end
  end
  // Classification after rounding select by destination format 
  assign uf_after_round = fmt_uf_after_round[dst_fmt_q2];
  assign of_after_round = dst_is_int_q ? ifmt_of_after_round[int_fmt_q2] : fmt_of_after_round[dst_fmt_q2];
  // ------------------------- 
  // FP Special case handling 
  // ------------------------- 
  logic [WIDTH-1:0]   fp_special_result;
  fpnew_pkg::status_t fp_special_status;
  logic               fp_result_is_special;
  logic [NUM_FORMATS-1:0][WIDTH-1:0] fmt_special_result;
  // Special result construction 
  for (genvar fmt = 0; fmt < int'(NUM_FORMATS); fmt++) begin : gen_special_results
    // Set up some constants 
    localparam int unsigned FP_WIDTH = fpnew_pkg::fp_width(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(fpnew_pkg::fp_format_e'(fmt));
    localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(fpnew_pkg::fp_format_e'(fmt));
    localparam logic [EXP_BITS-1:0] QNAN_EXPONENT = '1;
    localparam logic [MAN_BITS-1:0] QNAN_MANTISSA = 2**(MAN_BITS-1);
    if (FpFmtConfig[fmt]) begin : active_format
      always_comb begin : special_results
        logic [FP_WIDTH-1:0] special_res;
        special_res = info_q.is_zero
                      ? input_sign_q << FP_WIDTH-1 // signed zero 
                      : {1'b0, QNAN_EXPONENT, QNAN_MANTISSA}; // qNaN 
        // Initialize special result with ones (NaN-box) 
        fmt_special_result[fmt]               = '1;
        fmt_special_result[fmt][FP_WIDTH-1:0] = special_res;
      end
    end else begin : inactive_format
      assign fmt_special_result[fmt] = '{default: fpnew_pkg::DONT_CARE};
    end
  end
  // Detect special case from source format, I2F casts don't produce a special result 
  assign fp_result_is_special = ~src_is_int_q & (info_q.is_zero |
                                                 info_q.is_nan |
                                                 ~info_q.is_boxed);
  // Signalling input NaNs raise invalid flag, otherwise no flags set 
  assign fp_special_status = '{NV: info_q.is_signalling, default: 1'b0};
  // Assemble result according to destination format 
  assign fp_special_result = fmt_special_result[dst_fmt_q2]; // destination format 
  // -------------------------- 
  // INT Special case handling 
  // -------------------------- 
  logic [WIDTH-1:0]   int_special_result;
  fpnew_pkg::status_t int_special_status;
  logic               int_result_is_special;
  logic [NUM_INT_FORMATS-1:0][WIDTH-1:0] ifmt_special_result;
  // Special result construction 
  for (genvar ifmt = 0; ifmt < int'(NUM_INT_FORMATS); ifmt++) begin : gen_special_results_int
    // Set up some constants 
    localparam int unsigned INT_WIDTH = fpnew_pkg::int_width(fpnew_pkg::int_format_e'(ifmt));
    if (IntFmtConfig[ifmt]) begin : active_format
      always_comb begin : special_results
        automatic logic [INT_WIDTH-1:0] special_res;
        // Default is overflow to positive max, which is 2**INT_WIDTH-1 or 2**(INT_WIDTH-1)-1 
        special_res[INT_WIDTH-2:0] = '1;       // alone yields 2**(INT_WIDTH-1)-1 
        special_res[INT_WIDTH-1]   = op_mod_q2; // for unsigned casts yields 2**INT_WIDTH-1 
        // Negative special case (except for nans) tie to -max or 0 
        if (input_sign_q && !info_q.is_nan)
          special_res = ~special_res;
        // Initialize special result with sign-extension 
        ifmt_special_result[ifmt]                = '{default: special_res[INT_WIDTH-1]};
        ifmt_special_result[ifmt][INT_WIDTH-1:0] = special_res;
      end
    end else begin : inactive_format
      assign ifmt_special_result[ifmt] = '{default: fpnew_pkg::DONT_CARE};
    end
  end
  // Detect special case from source format (inf, nan, overflow, nan-boxing or negative unsigned) 
  assign int_result_is_special = info_q.is_nan | info_q.is_inf |
                                 of_before_round | of_after_round | ~info_q.is_boxed |
                                 (input_sign_q & op_mod_q2 & ~rounded_int_res_zero);
  // All integer special cases are invalid 
  assign int_special_status = '{NV: 1'b1, default: 1'b0};
  // Assemble result according to destination format 
  assign int_special_result = ifmt_special_result[int_fmt_q2]; // destination format 
  // ----------------- 
  // Result selection 
  // ----------------- 
  fpnew_pkg::status_t int_regular_status, fp_regular_status;
  logic [WIDTH-1:0]   fp_result, int_result;
  fpnew_pkg::status_t fp_status, int_status;
  assign fp_regular_status.NV = 1'b0; // floating-point results are always valid 
  assign fp_regular_status.DZ = 1'b0; // no divisions 
  assign fp_regular_status.OF = (src_is_int_q | ~info_q.is_inf) & (of_before_round | of_after_round); // inf casts no OF 
  assign fp_regular_status.UF = uf_after_round & fp_regular_status.NX;
  assign fp_regular_status.NX = (| fp_round_sticky_bits) | ((src_is_int_q | ~info_q.is_inf) & (of_before_round | of_after_round));
  assign int_regular_status = '{NV: of_before_round | of_after_round, // overflow is invalid for F2I casts 
                                NX: (| int_round_sticky_bits), default: 1'b0};
  assign fp_result  = fp_result_is_special  ? fp_special_result  : fmt_result[dst_fmt_q2];
  assign fp_status  = fp_result_is_special  ? fp_special_status  : fp_regular_status;
  assign int_result = int_result_is_special ? int_special_result : rounded_int_res;
  assign int_status = int_result_is_special ? int_special_status : int_regular_status;
  // Final results for output pipeline 
  logic [WIDTH-1:0]   result_d;
  fpnew_pkg::status_t status_d;
  logic               extension_bit;
  // Select output depending on special case detection 
  assign result_d = dst_is_int_q ? int_result : fp_result;
  assign status_d = dst_is_int_q ? int_status : fp_status;
  // MSB of int result decides extension, otherwise NaN box 
  assign extension_bit = dst_is_int_q ? int_result[WIDTH-1] : 1'b1;
  // ---------------- 
  // Output Pipeline 
  // ---------------- 
  // Output pipeline signals, index i holds signal after i register stages 
  logic               [0:NUM_OUT_REGS][WIDTH-1:0] out_pipe_result_q;
  fpnew_pkg::status_t [0:NUM_OUT_REGS]            out_pipe_status_q;
  logic               [0:NUM_OUT_REGS]            out_pipe_ext_bit_q;
  TagType             [0:NUM_OUT_REGS]            out_pipe_tag_q;
  logic               [0:NUM_OUT_REGS]            out_pipe_mask_q;
  AuxType             [0:NUM_OUT_REGS]            out_pipe_aux_q;
  logic               [0:NUM_OUT_REGS]            out_pipe_valid_q;
  // Ready signal is combinatorial for all stages 
  logic [0:NUM_OUT_REGS] out_pipe_ready;
  // Input stage: First element of pipeline is taken from inputs 
  assign out_pipe_result_q[0]  = result_d;
  assign out_pipe_status_q[0]  = status_d;
  assign out_pipe_ext_bit_q[0] = extension_bit;
  assign out_pipe_tag_q[0]     = mid_pipe_tag_q[NUM_MID_REGS];
  assign out_pipe_mask_q[0]    = mid_pipe_mask_q[NUM_MID_REGS];
  assign out_pipe_aux_q[0]     = mid_pipe_aux_q[NUM_MID_REGS];
  assign out_pipe_valid_q[0]   = mid_pipe_valid_q[NUM_MID_REGS];
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
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      out_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      out_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (out_pipe_ready[i]) ? (out_pipe_valid_q[i]) : (out_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (out_pipe_ready[i] & out_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + NUM_MID_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_result_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_result_q[i+1] <= (reg_ena) ? (out_pipe_result_q[i]) : (out_pipe_result_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_status_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_status_q[i+1] <= (reg_ena) ? (out_pipe_status_q[i]) : (out_pipe_status_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_ext_bit_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_ext_bit_q[i+1] <= (reg_ena) ? (out_pipe_ext_bit_q[i]) : (out_pipe_ext_bit_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      out_pipe_tag_q[i+1] <= (reg_ena) ? (out_pipe_tag_q[i]) : (out_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_mask_q[i+1] <= (reg_ena) ? (out_pipe_mask_q[i]) : (out_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      out_pipe_aux_q[i+1] <= (reg_ena) ? (out_pipe_aux_q[i]) : (out_pipe_aux_q[i+1]);               
    end                                              
  end
  end
  // Output stage: Ready travels backwards from output side, driven by downstream circuitry 
  assign out_pipe_ready[NUM_OUT_REGS] = out_ready_i;
  // Output stage: assign module outputs 
  assign result_o        = out_pipe_result_q[NUM_OUT_REGS];
  assign status_o        = out_pipe_status_q[NUM_OUT_REGS];
  assign extension_bit_o = out_pipe_ext_bit_q[NUM_OUT_REGS];
  assign tag_o           = out_pipe_tag_q[NUM_OUT_REGS];
  assign mask_o          = out_pipe_mask_q[NUM_OUT_REGS];
  assign aux_o           = out_pipe_aux_q[NUM_OUT_REGS];
  assign out_valid_o     = out_pipe_valid_q[NUM_OUT_REGS];
  assign busy_o          = (| {inp_pipe_valid_q, mid_pipe_valid_q, out_pipe_valid_q});
  // Early valid_o signal. This is used for dispatching instructions for dual-issue processor. 
  if (NUM_OUT_REGS > 0) begin
    assign early_out_valid_o = |{out_pipe_valid_q[NUM_OUT_REGS] & ~out_pipe_ready[NUM_OUT_REGS],
                                 out_pipe_valid_q[NUM_OUT_REGS-1]};
  end else if (NUM_MID_REGS > 0) begin
    assign early_out_valid_o = |{mid_pipe_valid_q[NUM_MID_REGS] & ~mid_pipe_ready[NUM_OUT_REGS],
                                 mid_pipe_valid_q[NUM_MID_REGS-1]};
  end else if (NUM_INP_REGS > 0) begin
    assign early_out_valid_o = |{inp_pipe_valid_q[NUM_INP_REGS] & ~inp_pipe_ready[NUM_INP_REGS],
                                 inp_pipe_valid_q[NUM_INP_REGS-1]};
  end else begin
    assign early_out_valid_o = 1'b0;
  end
endmodule
// s2chitni & Claude (AI-generated) 
// Constants of ucc_fma's FP32 operations, and the FU's global opcode. An FP32 FMA-path operation computes what FPnew 
// fpnew_fma computes in FP32, and these are that unit's constants. Its datapath is the FP64 FMA's, with its adder 
// frame at bits 75-0. 
package ucc_pkg;
  // fpnew_fma's derived widths in format fmt, for the FMA path's modules in either format: the leading-zero counter's 
  // input (the sum's lower 2p+3 bits), the internal exponent, and the shift amounts (up to 3p+4) 
  function automatic int unsigned lower_sum_width(fpnew_pkg::fp_format_e fmt);
    return 2 * (fpnew_pkg::man_bits(fmt) + 1) + 3;
  endfunction
  function automatic int unsigned exp_width(fpnew_pkg::fp_format_e fmt);
    return unsigned'(fpnew_pkg::maximum(fpnew_pkg::exp_bits(fmt) + 2, $clog2(lower_sum_width(fmt))));
  endfunction
  function automatic int unsigned shift_amount_width(fpnew_pkg::fp_format_e fmt);
    return $clog2(3 * (fpnew_pkg::man_bits(fmt) + 1) + 5);
  endfunction
  localparam fpnew_pkg::fp_format_e FP32 = fpnew_pkg::FP32;
  localparam int unsigned WIDTH          = fpnew_pkg::fp_width(FP32);
  localparam int unsigned EXP_BITS       = fpnew_pkg::exp_bits(FP32);
  localparam int unsigned MAN_BITS       = fpnew_pkg::man_bits(FP32);
  localparam int unsigned BIAS           = fpnew_pkg::bias(FP32);
  // fpnew_fma's derived constants, in FP32 
  localparam int unsigned PRECISION_BITS     = MAN_BITS + 1;
  localparam int unsigned LOWER_SUM_WIDTH    = lower_sum_width(FP32);
  localparam int unsigned LZC_RESULT_WIDTH   = $clog2(LOWER_SUM_WIDTH);
  localparam int unsigned EXP_WIDTH          = exp_width(FP32);
  localparam int unsigned SHIFT_AMOUNT_WIDTH = shift_amount_width(FP32);
  // The FP32 adder frame (3p+4 bits) 
  localparam int unsigned FRAME = 3 * PRECISION_BITS + 4;
  // What the output cycle's rounding needs besides the value before rounding, for the FP32 or the FP64 result 
  // (status only: the overflow before rounding, and the sticky bit RISC-V's underflow-after-rounding check reads) 
  typedef struct packed {
    logic               special;               // the value is a special result, which is not rounded 
    logic [1:0]         round_sticky;          // round and sticky bits 
    logic               effective_subtraction; // the sign of an exact zero 
    logic               of_before_round;
    logic               uf_sticky;
    fpnew_pkg::status_t special_status;
  } round_t;
  // ---------------------- 
  // The FU's global opcode 
  // ---------------------- 
  // ucc_lane's op_i, 7 bits. 0x00-0x3F are the INT32 operations below. 0x40-0x7F are floating point: bit 5 picks FP32 
  // (else FP64) and bits 4-0 the function, FP_* below. Two-operand functions read a and b, unary ones a. Every 
  // operation is one operation: an FP32 or INT32 one reads bits 31-0 of its operands. FP32 results are NaN-boxed; 
  // INT32 results, compares (FP32 and FP64) and conversions to int32 are zero-extended. Codes this map does not name 
  // return 0 after one cycle. 0x58-0x5F, in the FP64 half, are DPA-16 (FP_DPA), the only operations that read a's and 
  // b's bits above 63 and the block scales. 
  localparam logic [4:0] FP_FMA     = 5'h00; // a * b + c 
  localparam logic [4:0] FP_ADD     = 5'h01; // a + b 
  localparam logic [4:0] FP_SUB     = 5'h02; // a - b 
  localparam logic [4:0] FP_MUL     = 5'h03; // a * b 
  // 0x04-0x07 are not named: the FU has no divider, and divide, square root and reciprocal run as the SFU's rcp or 
  // rsqrt followed by FMA steps 
  localparam logic [4:0] FP_MIN     = 5'h08; // IEEE 754-2019 minimumNumber (-0 < +0), as RISC-V 
  localparam logic [4:0] FP_MAX     = 5'h09;
  localparam logic [4:0] FP_NEG     = 5'h0A; // -a, sign only 
  localparam logic [4:0] FP_ABS     = 5'h0B; // |a|, sign only 
  localparam logic [4:0] FP_EQ      = 5'h0C; // compares return 0 or 1; all but NE are false if a or b is a NaN 
  localparam logic [4:0] FP_NE      = 5'h0D; // true if a or b is a NaN 
  localparam logic [4:0] FP_LT      = 5'h0E;
  localparam logic [4:0] FP_LE      = 5'h0F;
  localparam logic [4:0] FP_GT      = 5'h10;
  localparam logic [4:0] FP_GE      = 5'h11;
  localparam logic [4:0] FP_CVT_F   = 5'h12; // from the other FP format 
  localparam logic [4:0] FP_CVT_S32 = 5'h13; // from a signed int32 
  localparam logic [4:0] FP_CVT_U32 = 5'h14; // from an unsigned int32 
  localparam logic [4:0] FP_TO_S32  = 5'h15; // to a signed int32 (saturating, NaN to the largest) 
  localparam logic [4:0] FP_TO_U32  = 5'h16; // to an unsigned int32 
  localparam logic [4:0] FP_SFU     = 5'h18; // FP32 only: 0x18-0x1E are the SFU's functions in Vortex's encoding 
  // FP64 half only: 0x18-0x1F are DPA-16, d = c + sum of a_i * b_i in FP32 with TransDot's numerics, with its format 
  // in bits 2-0: dpa16_pkg::fmt_e (FP16, BF16, TF32, FP8, NVFP4, MXFP4), then the FU's MXFP8 (FP8 with one E8M0 scale 
  // per side, byte 0) and FP4 (E2M1, no scales). a and b are DPA_VECTOR-bit vectors (ucc_lane's a_i and b_i), each 
  // with four 8-bit block scales (sa_i and sb_i) that only NVFP4, MXFP4 and MXFP8 read; inside the FU each operand is 
  // DPA_OPERAND bits, {scales, vector}. c's bits 31-0 are the FP32 addend, and bits 0 and 1 of the rounding-mode input 
  // make a's and b's FP8 and MXFP8 elements E5M2 (else E4M3). The result is NaN-boxed. 
  localparam logic [4:0]  FP_DPA      = 5'h18;
  localparam int unsigned DPA_FORMATS = 8;
  localparam int unsigned DPA_VECTOR  = 256;
  localparam int unsigned DPA_SCALES  = 32;
  localparam int unsigned DPA_OPERAND = DPA_SCALES + DPA_VECTOR;
  localparam int unsigned DPA_HI      = DPA_OPERAND - 64; // the bits of a and b only DPA-16 reads 
  // The unit that returns an opcode's result, and so its latency (cycles from issue to result) 
  typedef enum logic [3:0] {
    UNIT_ALU,  // INT32 ALU, 1 
    UNIT_CMP,  // FP min, max, neg, abs and compares, 1 
    UNIT_IMUL, // INT32 multiplies on the FP64 path, 2 
    UNIT_CVT,  // FP conversions, 2 
    UNIT_FMA,  // FP FMA, ADD, SUB, MUL, 3 
    UNIT_DPA,  // DPA-16, 4 
    UNIT_SFU,  // the SFU's functions, 5 
    UNIT_NONE  // codes the map does not name: 0, 1 
  } unit_e;
  function automatic unit_e unit_of(logic [6:0] op);
    logic [4:0] func;
    func = op[4:0];
    if (!op[6])                                    return op[5] ? UNIT_IMUL : UNIT_ALU;
    if (func <= FP_MUL)                            return UNIT_FMA;
    if (func >= FP_MIN && func <= FP_GE)           return UNIT_CMP;
    if (func >= FP_CVT_F && func <= FP_TO_U32)     return UNIT_CVT;
    if (op[5] && func >= FP_SFU && func <= FP_SFU + 5'd6) return UNIT_SFU;
    if (!op[5] && func >= FP_DPA && 6'(func) < 6'(FP_DPA) + 6'(DPA_FORMATS)) return UNIT_DPA;
    return UNIT_NONE;
  endfunction
  // INT32 operations (op_i 0x00-0x3F). With bit 5 clear the operation is the ALU's, bits 4-0 below. With 
  // bit 5 set it is a multiply of bits 31-0 on the FP64 path: bits 4-3 pick the result (INT_LO, INT_HI or INT_WIDE, the 
  // 64-bit product), bit 2 adds c's bits 31-0 (zero-extended, at the result's bit 0), and bits 1 and 0 make b and a 
  // signed. 
  localparam logic [4:0] INT_ADD       = 5'd0;
  localparam logic [4:0] INT_SUB       = 5'd1;
  localparam logic [4:0] INT_AND       = 5'd2;
  localparam logic [4:0] INT_OR        = 5'd3;
  localparam logic [4:0] INT_XOR       = 5'd4;
  localparam logic [4:0] INT_NOT       = 5'd5;  // ~a 
  localparam logic [4:0] INT_SHL       = 5'd6;  // shifts by b's bits 4-0 
  localparam logic [4:0] INT_SHR_U     = 5'd7;
  localparam logic [4:0] INT_SHR_S     = 5'd8;
  localparam logic [4:0] INT_EQ        = 5'd9;  // compares return 0 or 1 
  localparam logic [4:0] INT_NE        = 5'd10;
  localparam logic [4:0] INT_LT_S      = 5'd11;
  localparam logic [4:0] INT_LE_S      = 5'd12;
  localparam logic [4:0] INT_GT_S      = 5'd13;
  localparam logic [4:0] INT_GE_S      = 5'd14;
  localparam logic [4:0] INT_LT_U      = 5'd15;
  localparam logic [4:0] INT_LE_U      = 5'd16;
  localparam logic [4:0] INT_GT_U      = 5'd17;
  localparam logic [4:0] INT_GE_U      = 5'd18;
  localparam logic [4:0] INT_MIN_S     = 5'd19;
  localparam logic [4:0] INT_MAX_S     = 5'd20;
  localparam logic [4:0] INT_MIN_U     = 5'd21;
  localparam logic [4:0] INT_MAX_U     = 5'd22;
  localparam logic [4:0] INT_ABS       = 5'd23;
  localparam logic [4:0] INT_CZERO_EQZ = 5'd24; // b == 0 ? 0 : a (RISC-V Zicond) 
  localparam logic [4:0] INT_CZERO_NEZ = 5'd25; // b != 0 ? 0 : a; codes 26-31 return 0 
  localparam logic [1:0] INT_LO        = 2'd0;
  localparam logic [1:0] INT_HI        = 2'd1;
  localparam logic [1:0] INT_WIDE      = 2'd2;  // and 3 
endpackage
// s2chitni & Claude (AI-generated) 
// ucc_fma's addend and normalization shifters, a module of their own so that synthesis reports them separately: data_i 
// shifted left (LEFT) or right by shamt_i, filling with zeros. 
module ucc_shift #(
  parameter int unsigned WIDTH       = 8,
  parameter int unsigned SHAMT_WIDTH = 3,
  parameter bit          LEFT        = 1'b0  // 1: shift left, 0: shift right 
) (
  input  logic [WIDTH-1:0]       data_i,
  input  logic [SHAMT_WIDTH-1:0] shamt_i,
  output logic [WIDTH-1:0]       data_o
);
  assign data_o = LEFT ? data_i << shamt_i : data_i >> shamt_i;
endmodule
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
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
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from TransDot 599aaa5 src/fpnew_fma.sv: the 
// normalization shift amount and exponent of ucc_fma's FMA path in format FpFormat, which is fpnew_fma's 
// (leading-zero count of the sum's lower 2p+3 bits): an FP32 operation's in FP32, and in FP64 the FP64 path's. 
// The shift itself is ucc_fma's, shared by both modes, and ucc_fp32_ctrl chose the case and its exponent in the 
// first cycle. 
module ucc_fp32_norm #(
  parameter fpnew_pkg::fp_format_e FpFormat = fpnew_pkg::FP32,
  // Do not change 
  parameter int unsigned LOWER_SUM_WIDTH    = ucc_pkg::lower_sum_width(FpFormat),
  localparam int unsigned EXP_WIDTH          = ucc_pkg::exp_width(FpFormat),
  localparam int unsigned SHIFT_AMOUNT_WIDTH = ucc_pkg::shift_amount_width(FpFormat)
) (
  input  logic [LOWER_SUM_WIDTH-1:0]    sum_lower_i,
  input  logic                          use_lzc_i,
  input  logic signed [EXP_WIDTH-1:0]   exponent_i, // product's if use_lzc_i, else tentative 
  input  logic [SHIFT_AMOUNT_WIDTH-1:0] addend_shamt_i,
  output logic [SHIFT_AMOUNT_WIDTH-1:0] norm_shamt_o,
  output logic signed [EXP_WIDTH-1:0]   normalized_exponent_o,
  output logic [$clog2(LOWER_SUM_WIDTH)-1:0] leading_zero_count_o,
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
  assign leading_zero_count_o = leading_zero_count;
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
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
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
// s2chitni & Claude (AI-generated) 
// The UCC FU's one set of multipliers: DPA-16's 16 tiles (TransDot's dpa16_mul12, 599aaa5, unmodified), shared by 
// DPA-16 and the FU's other products, after the input register. A DPA-16 operation (dpa_i) gives the tiles the 
// operands and modes ucc_dpa16_core sends out. Any other gives tile t = 4i + j the 12-bit chunk i of the FU's 
// multiplicand a_i and chunk j of b_i, in full 12 x 12 mode; ucc_tilemul then adds the tiles' products at 2^(12 (i + j)) 
// to its two strips into the 53 x 53 product. The SFU's mode (sfu_i) turns tiles off (zero operands): a holds xl^2 
// (truncated) at bits 47-24 and xl * 2^4 at bits 23-0, b a1 at bits 50-24 and a2 * 2^4 at bits 23-0, and only the 
// tiles that multiply one half by the other are on, xl * a1 and xl^2 * a2. An FP32 product's significands are at 
// bits 23-0, so chunks 2-3 are zero and their tiles' products 0. 
module dpa16_mul11 (
  input logic [15:0] a_i, b_i,
  input logic m_fp4_i,
  output logic [23:0] prod_o,
  output logic [3:0][7:0] dprod_o
);
  wire [7:0] p [3][3];
  for (genvar j = 0; j < 3; j++) begin : g_row
    for (genvar k = 0; k < 3; k++) begin : g_col
      localparam int WA = j == 2 ? 3 : 4;
      localparam int WB = k == 2 ? 3 : 4;
      wire [WA-1:0] x;
      wire [WB-1:0] y;
      if (j == 0 && k == 1) begin : g_third
        assign x = m_fp4_i ? a_i[11:8] : a_i[3:0];
        assign y = m_fp4_i ? b_i[11:8] : b_i[7:4];
      end else if (j == 1 && k == 0) begin : g_fourth
        assign x = m_fp4_i ? a_i[15:12] : a_i[7:4];
        assign y = m_fp4_i ? b_i[15:12] : b_i[3:0];
      end else begin : g_regular
        assign x = a_i[4*j +: WA];
        assign y = b_i[4*k +: WB];
      end
      assign p[j][k] = x * y;
    end
  end
  always_comb begin
    prod_o = '0;
    for (int j = 0; j < 3; j++)
      for (int k = 0; k < 3; k++)
        prod_o += 24'(p[j][k]) << (4*(j+k));
  end
  assign dprod_o = {p[1][0], p[0][1], p[1][1], p[0][0]};
endmodule

module ucc_tiles (
  input logic dpa_i,
  input logic [15:0][15:0] dpa_ta_i, dpa_tb_i,
  input logic dpa_full_i, dpa_fp8_i, dpa_fp4_i,
  input logic [52:0] a_i, b_i,
  input logic [52:0] sfu_a_i, sfu_b_i,
  input logic sfu_i,
  input logic [17:0] square_operand_i,
  output logic [17:0] square_o,
  output logic [15:0][23:0] prod_o,
  output logic [15:0][3:0][7:0] dprod_o
);
  wire [32:0] scalar_a = {1'b0, a_i[31:0]};
  wire [32:0] scalar_b = {1'b0, b_i[31:0]};
  wire [21:0] xl = {4'd0, sfu_a_i[21:4]};
  wire [21:0] sq = {4'd0, sfu_a_i[41:24]};
  wire [32:0] coeff1 = {6'd0, sfu_b_i[50:24]};
  wire [21:0] coeff2 = {2'd0, sfu_b_i[23:4]};
  logic [35:0] square_full;
  assign square_full = 36'(prod_o[13]) + (36'(prod_o[14]) << 12)
                    + (36'(prod_o[15]) << 22);
  assign square_o = square_full[35:18];
  for (genvar t = 0; t < 16; t++) begin : gen_tile
    wire [10:0] scalar_x, scalar_y, sfu_x, sfu_y;
    wire [15:0] ta, tb;
    if (t < 9) begin : g_scalar
      assign scalar_x = scalar_a[11*(t/3) +: 11];
      assign scalar_y = scalar_b[11*(t%3) +: 11];
    end else begin : g_no_scalar
      assign scalar_x = '0;
      assign scalar_y = '0;
    end
    if (t < 6) begin : g_linear
      assign sfu_x = xl[11*(t/3) +: 11];
      assign sfu_y = coeff1[11*(t%3) +: 11];
    end else if (t < 10) begin : g_quadratic
      assign sfu_x = sq[11*((t-6)/2) +: 11];
      assign sfu_y = coeff2[11*((t-6)%2) +: 11];
    end else if (t >= 13) begin : g_square
      assign sfu_x = t == 15 ? {4'd0, square_operand_i[17:11]} : square_operand_i[10:0];
      assign sfu_y = t == 13 ? square_operand_i[10:0] : {4'd0, square_operand_i[17:11]};
    end else begin : g_no_sfu
      assign sfu_x = '0;
      assign sfu_y = '0;
    end
    assign ta = dpa_i ? dpa_ta_i[t] : {5'd0, sfu_i ? sfu_x : scalar_x};
    assign tb = dpa_i ? dpa_tb_i[t] : {5'd0, sfu_i ? sfu_y : scalar_y};
    dpa16_mul11 i_tile(.a_i(ta), .b_i(tb), .m_fp4_i(dpa_i & dpa_fp4_i),
                      .prod_o(prod_o[t]), .dprod_o(dprod_o[t]));
  end
endmodule

// s2chitni & Claude (AI-generated) 
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
module ucc_tilemul #(
  parameter bit PackedIntLow = 1'b1
) (
  input logic [15:0][23:0] tile_p_i,
  input logic [52:0] a_i, b_i,
  input logic [52:0] sfu_a_i, sfu_b_i,
  input logic sfu_i, a_signed_i, b_signed_i,
  input logic [63:0] sum_i, carry_i,
  output logic [12:0][63:0] rows_o,
  output logic [63:0] p_o
);
  initial if (!PackedIntLow) $fatal(1, "11-bit scalar routing requires packed INT32 and no FP64");
  logic [63:0] correction_a, correction_b;
  always_comb begin
    correction_a = '0;
    correction_b = '0;
    if (sfu_i) begin
      if (sfu_b_i[50]) correction_a = 64'(sfu_a_i[21:4]) << 27;
      if (sfu_b_i[23]) correction_b = 64'(sfu_a_i[41:24]) << 20;
    end else begin
      if (a_signed_i && a_i[31]) correction_a = 64'(b_i[31:0]) << 32;
      if (b_signed_i && b_i[31]) correction_b = 64'(a_i[31:0]) << 32;
    end
    rows_o = '0;
    for (int t = 0; t < 6; t++)
      rows_o[t] = 64'(tile_p_i[t]) << (11*(t/3+t%3));
    for (int t = 6; t < 9; t++)
      rows_o[t] = sfu_i ? (64'(tile_p_i[t]) << (11*((t-6)/2+(t-6)%2)))
                       : (64'(tile_p_i[t]) << (11*(t/3+t%3)));
    if (sfu_i) rows_o[9] = 64'(tile_p_i[9]) << 22;
    rows_o[10] = ~correction_a;
    rows_o[11] = ~correction_b;
    rows_o[12] = 64'd2;
  end
  assign p_o = sum_i + carry_i;
endmodule

// s2chitni & Claude (AI-generated) 
// The UCC's INT32 ALU: the integer operations that do not multiply (ucc_pkg's INT_* codes 0-25; 26-31 return 0). 
// One adder serves add, sub, the compares, min, max and abs (0 - a); shifts take b's bits 4-0, as RISC-V's and the 
// DICE PE's do. It sits after ucc_fma's input register, and its result goes to ucc_fma's result in the same cycle, 
// one cycle after issue. 
module ucc_int_alu (
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  input  logic [4:0]  op_i,
  input logic [31:0] shifted_i,
  output logic [31:0] shift_data_o,
  input  logic [32:0] sum_i,
  output logic [31:0] add_a_o,
  output logic [31:0] add_b_o,
  output logic        carry_o,
  output logic [31:0] y_o
);
  import ucc_pkg::*;
  logic        sub, abs_op, signed_op, eq, lt, b_zero;
  logic [31:0] x, y;
  logic [32:0] sum;
  logic        shift_left, shift_fill;
  logic [31:0] shift_input, shift_right, shift_result;
  assign shift_left = (op_i == INT_SHL);
  assign shift_fill = (op_i == INT_SHR_S) & a_i[31];
  for (genvar bit_idx = 0; bit_idx < 32; bit_idx++) begin : gen_shift_direction
    assign shift_input[bit_idx] = shift_left ? a_i[31-bit_idx] : a_i[bit_idx];
    assign shift_result[bit_idx] = shift_left ? shift_right[31-bit_idx] : shift_right[bit_idx];
  end
  assign shift_data_o = shift_input ^ {32{shift_fill}};
  assign shift_right = shifted_i ^ {32{shift_fill}};
  // Everything but add subtracts: the compares, min and max compute a - b, and abs computes 0 - a 
  assign abs_op    = (op_i == INT_ABS);
  assign sub       = (op_i != INT_ADD);
  assign x         = abs_op ? 32'd0 : a_i;
  assign y         = abs_op ? a_i : b_i;
  assign add_a_o = x;
  assign add_b_o = sub ? ~y : y;
  assign carry_o = sub;
  assign sum = sum_i;
  assign signed_op = (op_i inside {INT_LT_S, INT_LE_S, INT_GT_S, INT_GE_S, INT_MIN_S, INT_MAX_S});
  assign eq        = (a_i == b_i);
  // a < b: unsigned, no carry out of a + ~b + 1; signed, a's sign if the signs differ, else the difference's sign 
  assign lt        = signed_op ? ((a_i[31] ^ b_i[31]) ? a_i[31] : sum[31]) : ~sum[32];
  assign b_zero    = (b_i == '0);
  always_comb begin
    unique case (op_i)
      INT_ADD, INT_SUB:           y_o = sum[31:0];
      INT_AND:                    y_o = a_i & b_i;
      INT_OR:                     y_o = a_i | b_i;
      INT_XOR:                    y_o = a_i ^ b_i;
      INT_NOT:                    y_o = ~a_i;
      INT_SHL, INT_SHR_U,
      INT_SHR_S:                  y_o = shift_result;
      INT_EQ:                     y_o = {31'd0, eq};
      INT_NE:                     y_o = {31'd0, ~eq};
      INT_LT_S, INT_LT_U:         y_o = {31'd0, lt};
      INT_LE_S, INT_LE_U:         y_o = {31'd0, lt | eq};
      INT_GT_S, INT_GT_U:         y_o = {31'd0, ~(lt | eq)};
      INT_GE_S, INT_GE_U:         y_o = {31'd0, ~lt};
      INT_MIN_S, INT_MIN_U:       y_o = lt ? a_i : b_i;
      INT_MAX_S, INT_MAX_U:       y_o = lt ? b_i : a_i;
      INT_ABS:                    y_o = a_i[31] ? sum[31:0] : a_i;
      INT_CZERO_EQZ:              y_o = b_zero ? '0 : a_i;
      INT_CZERO_NEZ:              y_o = b_zero ? a_i : '0;
      default:                    y_o = '0;
    endcase
  end
endmodule
// s2chitni & Claude (AI-generated) 
// The UCC FU's FP min, max, neg, abs and compares (ucc_pkg's FP_MIN to FP_GE), in one cycle: FPnew's fpnew_noncomp, 
// unmodified, once in FP64 and once in FP32, combinational. Its operations are selected as FPnew encodes them in the 
// rounding mode: MINMAX (RNE min, RTZ max); SGNJ with b = a (RTZ sgnjn = neg, RDN sgnjx = abs); CMP (RNE le, RTZ lt, 
// RDN eq), op_mod negating the result unless an operand is a NaN, so GT is not-LE, GE not-LT and NE not-EQ (true for 
// NaNs). FP32 reads bits 31-0 of a and b; its values come back NaN-boxed, and a compare's 0 or 1 zero-extended in 
// either format. status_o is FPnew's flags. 
module ucc_fp_noncomp #(
  parameter bit EnableFp64 = 1'b1
) (
  input  logic               clk_i,  // FPnew's ports; with no pipeline registers the unit is combinational 
  input  logic               rst_ni,
  input  logic [63:0]        a_i,
  input  logic [63:0]        b_i,
  input  logic               fp32_i,
  input  logic [4:0]         func_i,
  output logic [63:0]        result_o,
  output fpnew_pkg::status_t status_o
);
  import ucc_pkg::*;
  fpnew_pkg::operation_e op;
  fpnew_pkg::roundmode_e rnd;
  logic                  op_mod, unary, compare;
  always_comb begin : select
    op      = fpnew_pkg::CMP;
    rnd     = fpnew_pkg::RNE;
    op_mod  = 1'b0;
    unary   = 1'b0;
    compare = 1'b1;
    unique case (func_i)
      FP_MIN:  begin op = fpnew_pkg::MINMAX; rnd = fpnew_pkg::RNE; compare = 1'b0; end
      FP_MAX:  begin op = fpnew_pkg::MINMAX; rnd = fpnew_pkg::RTZ; compare = 1'b0; end
      FP_NEG:  begin op = fpnew_pkg::SGNJ;   rnd = fpnew_pkg::RTZ; compare = 1'b0; unary = 1'b1; end
      FP_ABS:  begin op = fpnew_pkg::SGNJ;   rnd = fpnew_pkg::RDN; compare = 1'b0; unary = 1'b1; end
      FP_EQ:   rnd = fpnew_pkg::RDN;
      FP_NE:   begin rnd = fpnew_pkg::RDN; op_mod = 1'b1; end
      FP_LT:   rnd = fpnew_pkg::RTZ;
      FP_LE:   rnd = fpnew_pkg::RNE;
      FP_GT:   begin rnd = fpnew_pkg::RNE; op_mod = 1'b1; end
      FP_GE:   begin rnd = fpnew_pkg::RTZ; op_mod = 1'b1; end
      default: ;
    endcase
  end
  logic [1:0][63:0]         operands;
  logic [63:0]              result64;
  logic [31:0]              result32;
  fpnew_pkg::status_t       status64, status32;
  assign operands = {unary ? a_i : b_i, a_i};
  if (EnableFp64) begin : gen_fp64
  fpnew_noncomp #(
    .FpFormat ( fpnew_pkg::FP64 )
  ) i_fp64 (
    .clk_i,
    .rst_ni,
    .operands_i      ( operands                   ),
    .is_boxed_i      ( 2'b11                      ),
    .rnd_mode_i      ( rnd                        ),
    .op_i            ( op                         ),
    .op_mod_i        ( op_mod                     ),
    .tag_i           ( 1'b0                       ),
    .mask_i          ( 1'b1                       ),
    .aux_i           ( 1'b0                       ),
    .in_valid_i      ( 1'b1                       ),
    .in_ready_o      (                            ),
    .flush_i         ( 1'b0                       ),
    .result_o        ( result64                   ),
    .status_o        ( status64                   ),
    .extension_bit_o (                            ),
    .class_mask_o    (                            ),
    .is_class_o      (                            ),
    .tag_o           (                            ),
    .mask_o          (                            ),
    .aux_o           (                            ),
    .out_valid_o     (                            ),
    .out_ready_i     ( 1'b1                       ),
    .busy_o          (                            ),
    .reg_ena_i       ( 1'b0                       ),
    .early_out_valid_o (                          )
  );
  end else begin : gen_no_fp64
    assign result64 = '0;
    assign status64 = '0;
  end
  fpnew_noncomp #(
    .FpFormat ( fpnew_pkg::FP32 )
  ) i_fp32 (
    .clk_i,
    .rst_ni,
    .operands_i      ( {operands[1][31:0], operands[0][31:0]} ),
    .is_boxed_i      ( 2'b11                      ),
    .rnd_mode_i      ( rnd                        ),
    .op_i            ( op                         ),
    .op_mod_i        ( op_mod                     ),
    .tag_i           ( 1'b0                       ),
    .mask_i          ( 1'b1                       ),
    .aux_i           ( 1'b0                       ),
    .in_valid_i      ( 1'b1                       ),
    .in_ready_o      (                            ),
    .flush_i         ( 1'b0                       ),
    .result_o        ( result32                   ),
    .status_o        ( status32                   ),
    .extension_bit_o (                            ),
    .class_mask_o    (                            ),
    .is_class_o      (                            ),
    .tag_o           (                            ),
    .mask_o          (                            ),
    .aux_o           (                            ),
    .out_valid_o     (                            ),
    .out_ready_i     ( 1'b1                       ),
    .busy_o          (                            ),
    .reg_ena_i       ( 1'b0                       ),
    .early_out_valid_o (                          )
  );
  assign result_o = fp32_i ? (compare ? 64'(result32) : {32'hffff_ffff, result32}) : result64;
  assign status_o = fp32_i ? status32 : status64;
endmodule
// s2chitni & Claude (AI-generated) 
// The UCC FU's conversions (ucc_pkg's FP_CVT_F to FP_TO_U32): FPnew's fpnew_cast_multi, unmodified, with FP32, FP64 
// and INT32 enabled and no pipeline registers. The opcode's format bit names the FP format the conversion produces 
// or reads: FP_CVT_F converts from the other format, FP_CVT_S32/U32 from an int32, FP_TO_S32/U32 to one (op_mod is 
// FPnew's unsigned flag). FP32 operands are bits 31-0; FP32 results come back NaN-boxed, int32 results 
// zero-extended. FPnew follows RISC-V: a NaN converts to the largest int32, and out-of-range values saturate. 
// status_o is FPnew's flags. 
module ucc_fp_cast #(
  parameter bit EnableFp64 = 1'b1
) (
  input  logic                  clk_i,  // FPnew's ports; with no pipeline registers the unit is combinational 
  input  logic                  rst_ni,
  input  logic [63:0]           a_i,
  input  logic                  fp32_i,
  input  logic [4:0]            func_i,
  input  fpnew_pkg::roundmode_e rnd_mode_i,
  output logic [63:0]           result_o,
  output fpnew_pkg::status_t    status_o
);
  import ucc_pkg::*;
  // FPnew's format masks are ascending ([0:N-1]), so each format's bit is set by its index 
  function automatic fpnew_pkg::fmt_logic_t fp_formats();
    fpnew_pkg::fmt_logic_t mask;
    mask                  = '0;
    mask[fpnew_pkg::FP32] = 1'b1;
    mask[fpnew_pkg::FP64] = EnableFp64;
    return mask;
  endfunction
  function automatic fpnew_pkg::ifmt_logic_t int_formats();
    fpnew_pkg::ifmt_logic_t mask;
    mask                   = '0;
    mask[fpnew_pkg::INT32] = 1'b1;
    return mask;
  endfunction
  localparam fpnew_pkg::fmt_logic_t  FORMATS     = fp_formats();
  localparam fpnew_pkg::ifmt_logic_t INT_FORMATS = int_formats();
  fpnew_pkg::operation_e op;
  fpnew_pkg::fp_format_e fmt, other;
  logic                  op_mod, to_int;
  localparam int unsigned CAST_WIDTH = EnableFp64 ? 64 : 32;
  logic [CAST_WIDTH-1:0] result;
  assign fmt   = (fp32_i || !EnableFp64) ? fpnew_pkg::FP32 : fpnew_pkg::FP64;
  assign other = (fp32_i && EnableFp64) ? fpnew_pkg::FP64 : fpnew_pkg::FP32;
  always_comb begin : select
    op     = fpnew_pkg::F2F;
    op_mod = 1'b0;
    unique case (func_i)
      FP_CVT_S32: op = fpnew_pkg::I2F;
      FP_CVT_U32: begin op = fpnew_pkg::I2F; op_mod = 1'b1; end
      FP_TO_S32:  op = fpnew_pkg::F2I;
      FP_TO_U32:  begin op = fpnew_pkg::F2I; op_mod = 1'b1; end
      default:    ;
    endcase
    to_int = (op == fpnew_pkg::F2I);
  end
  fpnew_cast_multi #(
    .FpFmtConfig  ( FORMATS     ),
    .IntFmtConfig ( INT_FORMATS )
  ) i_cast (
    .clk_i,
    .rst_ni,
    .operands_i      ( a_i[CAST_WIDTH-1:0]                    ),
    .is_boxed_i      ( '1                                    ),
    .rnd_mode_i,
    .op_i            ( op                                    ),
    .op_mod_i        ( op_mod                                ),
    .src_fmt_i       ( (op == fpnew_pkg::F2F) ? other : fmt  ),
    .dst_fmt_i       ( fmt                                   ),
    .int_fmt_i       ( fpnew_pkg::INT32                      ),
    .tag_i           ( 1'b0                                  ),
    .mask_i          ( 1'b1                                  ),
    .aux_i           ( 1'b0                                  ),
    .in_valid_i      ( 1'b1                                  ),
    .in_ready_o      (                                       ),
    .flush_i         ( 1'b0                                  ),
    .result_o        ( result                                ),
    .status_o        ( status_o                              ),
    .extension_bit_o (                                       ),
    .tag_o           (                                       ),
    .mask_o          (                                       ),
    .aux_o           (                                       ),
    .out_valid_o     (                                       ),
    .out_ready_i     ( 1'b1                                  ),
    .busy_o          (                                       ),
    .reg_ena_i       ( 1'b0                                  ),
    .early_out_valid_o (                                     )
  );
  assign result_o = to_int ? {32'd0, result[31:0]}
                          : EnableFp64 ? 64'(result) : {32'hffffffff, result[31:0]};
endmodule
// Copyright © 2019-2026 
// Licensed under the Apache License, Version 2.0 (the "License"); 
// you may not use this file except in compliance with the License. 
// You may obtain a copy of the License at 
// http://www.apache.org/licenses/LICENSE-2.0 
// Unless required by applicable law or agreed to in writing, software 
// distributed under the License is distributed on an "AS IS" BASIS, 
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
// See the License for the specific language governing permissions and 
// limitations under the License. 
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from Vortex 50cb174 hw/rtl/mufu/VX_mufu_rom.sv 
// (vendor/vortex): the MUFU's coefficient ROM with its table copied verbatim (tests/test_sfu.py checks that it is the 
// vendored file's). Vortex's VX_rom fills its array in an initial block, which ASIC synthesis ignores, so the table 
// here is read from the constant directly. The address is the table's base plus the index, as in VX_mufu_rom, and 
// the read is registered once, as VX_rom's output register, loading only with an SFU operation (en_i); the second 
// register (VX_mufu_rom's rd_reg) is the UCC's input register. 
module ucc_sfu_rom (
  input  logic               clk_i,
  input  logic               en_i,
  input  logic [2:0]         tbl_i,
  input  logic [6:0]         idx_i,
  output logic [31:0]        a0_o,
  output logic signed [26:0] a1_o,
  output logic signed [19:0] a2_o
);
  localparam int unsigned DATAW = 72;
  localparam int unsigned SIZE  = 512;
  localparam logic [SIZE*DATAW-1:0] ROM_DATA = {
    72'h01fffff0000017fffe,
    72'h01ffffc800003ffffc,
    72'h01ffff68000097fff4,
    72'h01fffe68000187ffe0,
    72'h01fffba800041fffa9,
    72'h01fff420000b2fff13,
    72'h01ffdfc0001e57fd7c,
    72'h01ffa86000525ff92a,
    72'h03fede58008e17f8e9,
    72'h03fe229800ea17f453,
    72'h03fced6001817fecc8,
    72'h03faf050027a5fe06a,
    72'h03f7ab280412afcc31,
    72'h03f24cc006ae6fab4b,
    72'h03e982780aecbf7643,
    72'h03db2e7011c4d72203,
    72'h07a1e40016e18f6344,
    72'h0787f1c01d014f3b68,
    72'h07671e2824a3770b06,
    72'h073dc1082e1336d146,
    72'h0709e5a8399e3e8de0,
    72'h06c94c50478cb64190,
    72'h0679767058143deeb1,
    72'h0617c2406b453d99fc,
    72'h0bbec2a075fefeaec1,
    72'h0b433350811b669c9c,
    72'h0abc48a08cb58e8cf6,
    72'h0a29927898b26e80b0,
    72'h098abf50a4ef9e78ba,
    72'h08dfa408b1430e7603,
    72'h08284348bd7b0e7982,
    72'h0764d478c95fce83fb,
    72'h0dfd7340cf15af4856,
    72'h0d2b94d0d4a7774ddb,
    72'h0c543ee0da04f75465,
    72'h0b77a9b8df25ff5bf3,
    72'h0a9615e8e402776485,
    72'h09afcc00e8925f6e17,
    72'h08c51c78eccdf778a0,
    72'h07d65f48f0add78416,
    72'h0ebb32e0f2723fc69f,
    72'h0dc7e820f423dfc9ce,
    72'h0cd2f8d8f5bb37cd17,
    72'h0bdc7fc0f7378fd077,
    72'h0ae49838f89827d3ee,
    72'h09eb5e38f9dc67d77a,
    72'h08f0ee78fb03afdb19,
    72'h07f56640fc0d67deca,
    72'h0eee84b0fc84e7f0cd,
    72'h0df1c6d8fcf6f7f1bf,
    72'h0cf49ac8fd615ff2b3,
    72'h0bf70828fdc41ff3a8,
    72'h0af916a8fe1f1ff4a0,
    72'h09face00fe725ff598,
    72'h08fc3600febdd7f692,
    72'h07fd5680ff016ff78d,
    72'h0efb9cb0ff1fb7fc25,
    72'h0dfc6e90ff3c97fc64,
    72'h0cfd2490ff577ffca3,
    72'h0bfdc0a0ff706ffce3,
    72'h0afe44c8ff875ffd22,
    72'h09feb300ff9c4ffd62,
    72'h08ff0d40ffaf47fda1,
    72'h07ff5588ffc03ffde1,
    72'h7ff6218013bced8867,
    72'h7fd887882776e588c9,
    72'h7fa736b03b2ac5898b,
    72'h7f6236884ed58d8aaf,
    72'h7f0991c06274258c34,
    72'h7e9d55f07603958e1a,
    72'h7e1d93e08980cd9060,
    72'h7d8a5f389ce8cd9307,
    72'h7ce3cea0b038a5960d,
    72'h7c29fbe0c36d4d9973,
    72'h7b5d0390d683cd9d37,
    72'h7a7d0548e9793da159,
    72'h798a23a0fc4aada5d9,
    72'h788484010ef535aab6,
    72'h776c4ec92175f5afef,
    72'h7641af2933ca0db584,
    72'h7504d33145eeb5bb72,
    72'h73b5ebb157e11dc1bb,
    72'h72552c69699e75c85b,
    72'h70e2cba97b240dcf54,
    72'h6f5f02918c6f2dd6a3,
    72'h6dca0cf19d7d2dde47,
    72'h6c242941ae4b6de63f,
    72'h6a6d9881bed74dee8a,
    72'h68a69e61cf1e45f727,
    72'h66cf8101df1dd60014,
    72'h64e88901eed3860950,
    72'h62f20189fe3ce612da,
    72'h60ec38020d579e1cb0,
    72'h5ed77c621c214626d0,
    72'h5cb420b22a97ae3139,
    72'h5a82797238b88e3bea,
    72'h5842dd224681be46e0,
    72'h55f5a4a253f116521a,
    72'h539b2ac26104865d97,
    72'h5133cc626dba0e6954,
    72'h4ebfe8727a0fbe7550,
    72'h4c3fdfc286039e8188,
    72'h49b415029193e68dfc,
    72'h471cecb29cbec69aa9,
    72'h447acd22a7827ea78c,
    72'h41ce1e32b1dd76b4a5,
    72'h3f174982bbce0ec1f1,
    72'h3c56ba3ac552b6cf6e,
    72'h398cdd02ce69fedd1a,
    72'h36ba1fdad71286eaf3,
    72'h33def252df4ae6f8f7,
    72'h30fbc512e711e70723,
    72'h2e110a2aee664f1576,
    72'h2b1f34b2f5470723ec,
    72'h2826b8f2fbb2ef3285,
    72'h25280c2301a917413d,
    72'h2223a48b07288f5013,
    72'h1f19f93b0c30875f04,
    72'h1c0b822b10c0276e0e,
    72'h18f8b7fb14d6c77d2e,
    72'h15e214031873bf8c62,
    72'h12c810331b96879ba8,
    72'h0fab26eb1e3e9faafe,
    72'h0c8bd323206b9fba61,
    72'h096a900b221d2fc9ce,
    72'h0647d94323530fd944,
    72'h03242a83240d0fe8c0,
    72'h00000003244857f8cf,
    72'h7e8d3859743bdfa2f1,
    72'h7d17824177301fa177,
    72'h7b9ed1d97a307f9ff4,
    72'h7a231ae17d3d3f9e67,
    72'h78a450c98056b79cd1,
    72'h772266c1837d2f9b30,
    72'h759d4f9186b0f79986,
    72'h7414fdc989f26f97d1,
    72'h728963898d41df9610,
    72'h70fa72a1909fb79445,
    72'h6f681c91940c3f926d,
    72'h6dd252519787ef908a,
    72'h6c3904b19b13178e99,
    72'h6a9c23f19eae2f8c9c,
    72'h68fb9fe9a2599f8a91,
    72'h67576811a615cf8878,
    72'h65af6b61a9e33f8651,
    72'h64039871adc25f841b,
    72'h6253dd49b1b3af81d5,
    72'h60a02771b5b7af7f7f,
    72'h5ee86401b9cee77d18,
    72'h5d2c7f79bdf9df7a9f,
    72'h5b6c65c9c239277815,
    72'h59a80259c68d5f7578,
    72'h57df3ff1caf71772c7,
    72'h561208c1cf76f77002,
    72'h54404641d40da76d29,
    72'h5269e151d8bbcf6a39,
    72'h508ec221dd822f6732,
    72'h4eaed011e261876414,
    72'h4cc9f1d1e75a8f60dd,
    72'h4ae00d41ec6e1f5d8c,
    72'h48f10779f19d075a21,
    72'h46fcc4a1f6e82f5699,
    72'h45032811fc507752f4,
    72'h4304143201d6d74f31,
    72'h40ff6a5a077c4f4b4f,
    72'h3ef50b020d41df474b,
    72'h3ce4d5721328a74324,
    72'h3acea7f21931c73ed9,
    72'h38b25f921f5e673a69,
    72'h368fd82225afcf35d0,
    72'h3466ec522c273f310e,
    72'h3237755232c6172c21,
    72'h30014b02398dc72706,
    72'h2dc443da407fcf21bb,
    72'h2b8034b2479dbf1c3f,
    72'h2934f0da4ee937168d,
    72'h26e249e25663ef10a4,
    72'h24880f9a5e0fc70a81,
    72'h2226100265ee970420,
    72'h1fbc17026e0276fd80,
    72'h1d49ee9a764d6ef69b,
    72'h1acf5e827ed1ceef6f,
    72'h184c2c228791e6e7f7,
    72'h15c01a92909036e030,
    72'h132aea4299cf5ed814,
    72'h108c58eaa35226cfa0,
    72'h0de42182ad1b7ec6cd,
    72'h0b31fbe2b72e86bd97,
    72'h08759cbac18e86b3f7,
    72'h05aeb552cc3efea9e8,
    72'h02dcf34ad743a69f61,
    72'h00000002e2a27693f4,
    72'hfd3e0c82be2110f4aa,
    72'hfa83b352b690d8f207,
    72'hf7d0dfeaaf1580ef6c,
    72'hf5257d8aa7aec8ecd8,
    72'hf28177b2a05c78ea4b,
    72'hefe4ba12991e58e7c4,
    72'hed4f309291f430e545,
    72'heac0c75a8addd0e2cd,
    72'he8396ac283daf8e05c,
    72'he5b907527ceb70ddf1,
    72'he33f89e2760f10db8d,
    72'he0ccdf5a6f4598d92f,
    72'hde60f4ea688ed8d6d9,
    72'hdbfbb80261ea98d488,
    72'hd99d162a5b58b0d23e,
    72'hd744fd3254d8e0cffa,
    72'hd4f35b124e6b00cdbd,
    72'hd2a81df2480ed8cb85,
    72'hd063344241c438c954,
    72'hce248c7a3b8af0c729,
    72'hcbec15623562d8c504,
    72'hc9b9bdea2f4bb8c2e4,
    72'hc78d752a294568c0cb,
    72'hc5672a72234fb0beb7,
    72'hc346cd3a1d6a68bca9,
    72'hc12c4d2a179560baa1,
    72'hbf179a1211d070b89f,
    72'hbd08a3fa0c1b68b6a1,
    72'hbaff5b0a067620b4aa,
    72'hb8fbafa200e060b2b8,
    72'hb6fd9239fb5a10b0cb,
    72'hb504f389f5e2f8aee3,
    72'hb311c469f07af8ad01,
    72'hb123f5d9eb21d8ab24,
    72'haf3b7901e5d780a94c,
    72'had583f41e09bb8a779,
    72'hab7a3a09db6e60a5ab,
    72'ha9a15b09d64f50a3e2,
    72'ha7cd9409d13e60a21e,
    72'ha5fed6f9cc3b68a05f,
    72'ha4351601c746409ea5,
    72'ha2704351c25ec89cf0,
    72'ha0b05161bd84d09b3f,
    72'h9ef532b1b8b8409993,
    72'h9d3ed9f1b3f8e897eb,
    72'h9b8d3a01af46a89648,
    72'h99e045d9aaa16094aa,
    72'h9837f099a608e09310,
    72'h96942d81a17d10917a,
    72'h94f4eff19cfdc88fe9,
    72'h935a2b79988ae88e5c,
    72'h91c3d3b99424488cd4,
    72'h9031dc898fc9d08b4f,
    72'h8ea439d18b7b5889cf,
    72'h8d1adfa18738c08853,
    72'h8b95c2298301e886db,
    72'h8a14d5b97ed6b08567,
    72'h88980ec17ab6f883f8,
    72'h871f61d976a2a0828c,
    72'h85aac3a97299808124,
    72'h843a29016e9b887fc0,
    72'h82cd86d96aa8907e5f,
    72'h8164d23166c0807d03,
    72'h8000000162e3687b9e,
    72'h404060a7bf3e78183c,
    72'h40818517be78b818b8,
    72'h40c3713fbdaf081937,
    72'h41062927bce14019b9,
    72'h4149b0e7bc0f481a3f,
    72'h418e0ccfbb39001ac9,
    72'h41d34127ba5e501b57,
    72'h4219528fb97f081be9,
    72'h4260458fb89b101c80,
    72'h42a81ef7b7b2381d1b,
    72'h42f0e3afb6c4701dba,
    72'h433a98c7b5d1801e5e,
    72'h43854377b4d9401f08,
    72'h43d0e917b3db901fb6,
    72'h441d8f3fb2d840206a,
    72'h446b3b97b1cf282124,
    72'h44b9f407b0c01021e4,
    72'h4509beafafaac822a9,
    72'h455aa1cfae8f202375,
    72'h45aca3d7ad6ce82448,
    72'h45ffcb7fac43e02521,
    72'h46541fb7ab13d82602,
    72'h46a9a797a9dc8826ea,
    72'h47006a7fa89dc027da,
    72'h47587017a7573028d2,
    72'h47b1c047a608a029d3,
    72'h480c632fa4b1b82add,
    72'h48686147a352402bf0,
    72'h48c5c347a1e9e02d0d,
    72'h49249247a078502e34,
    72'h4984d79f9efd282f65,
    72'h49e69d179d782030a2,
    72'h4a49ecaf9be8d831ea,
    72'h4aaed0ef9a4ee0333f,
    72'h4b15549f98a9e834a1,
    72'h4b7d830f96f9703610,
    72'h4be767ef953d10378d,
    72'h4c530f579374503919,
    72'h4cc085f7919eb03ab5,
    72'h4d2fd8e78fbbb03c61,
    72'h4da115cf8dcac83e1f,
    72'h4e144adf8bcb603fee,
    72'h4e8986d789bce841d1,
    72'h4f00d937879eb043c8,
    72'h4f7a51f785702045d4,
    72'h4ff601cf83307847f7,
    72'h5073fa4780def84a31,
    72'h50f44d777e7ae84c85,
    72'h51770e7f7c03684ef2,
    72'h51fc512f797798517c,
    72'h52842a4776d6905424,
    72'h530eaf8f741f5056ea,
    72'h539bf7b77150d059d3,
    72'h542c1a8f6e69f05cde,
    72'h54bf31076b6990600f,
    72'h55555537684e706368,
    72'h55eea2a765173066eb,
    72'h568b360f61c2786a9b,
    72'h572b2dbf5e4eb86e7c,
    72'h57cea9775aba60728f,
    72'h5875cab75703b876da,
    72'h5920b4b75328e87b5e,
    72'h59cf8c8f4f28088022,
    72'h5a82796f4afef08528,
    72'h5add84bfa46bd02246,
    72'h5b39a4c7a3543022f5,
    72'h5b96df47a236f023a8,
    72'h5bf539e7a113f02461,
    72'h5c54ba7f9feb00251e,
    72'h5cb567179ebbf825e1,
    72'h5d1745d79d86a826aa,
    72'h5d7a5d179c4ae82779,
    72'h5ddeb3779b0880284e,
    72'h5e444faf99bf382929,
    72'h5eab38a7986ef02a0a,
    72'h5f1375979717582af3,
    72'h5f7d0dd795b8502be2,
    72'h5fe808ff9451882cd9,
    72'h60546edf92e2d02dd8,
    72'h60c24797916be82ede,
    72'h61319b778fec802fed,
    72'h61a2731f8e64603105,
    72'h6214d75f8cd3403225,
    72'h6288d16f8b38d0334f,
    72'h62fe6abf8994c03482,
    72'h6375ad0f87e6c835c0,
    72'h63eea27f862e883709,
    72'h6469557f846bb0385c,
    72'h64e5d0d7829de039bb,
    72'h65641fa780c4b03b26,
    72'h65e44d877edfc83c9e,
    72'h6666665f7ceeb83e23,
    72'h66ea768f7af1183fb6,
    72'h67708aef78e6684157,
    72'h67f8b0b776ce404307,
    72'h6882f5b774a81044c7,
    72'h690f681f7273604697,
    72'h699e16c7702fa04879,
    72'h6a2f10f76ddc404a6d,
    72'h6ac266a76b78a84c75,
    72'h6b5828676904384e90,
    72'h6bf06757667e4050c0,
    72'h6c8b354763e6205306,
    72'h6d28a4df613b105564,
    72'h6dc8c95f5e7c5057da,
    72'h6e6bb6d75ba9185a69,
    72'h6f11823758c0885d14,
    72'h6fba414755c1c05fdb,
    72'h70660aaf52abd062c1,
    72'h7114f62f4f7db065c6,
    72'h71c71c574c366868ec,
    72'h727c96ff48d4c86c36,
    72'h733580ff4557b06fa6,
    72'h73f1f66f41bde8733d,
    72'h74b214af3e061876fe,
    72'h7575fa873a2ed87aeb,
    72'h763dc7ff3636c07f07,
    72'h77099ed7321c308356,
    72'h77d9a2472ddd9087d9,
    72'h78adf74f2979088c95,
    72'h7986c4b724ecd0918c,
    72'h7a6433372036e096c4,
    72'h7b466da71b55109c3f,
    72'h7c2da0ef164528a203,
    72'h7d19fc671104b8a814,
    72'h7e0bb1e70b9128ae78,
    72'h7f02f5df05e7c0b535,
    72'h80000007000438bc93,
    72'h40404047bf7f601018,
    72'h40810207befd201049,
    72'h40c246dfbe7948107a,
    72'h41041047bdf3e810ad,
    72'h41465fe7bd6ce810e0,
    72'h41893757bce4481114,
    72'h41cc982fbc5a081149,
    72'h42108427bbce10117e,
    72'h4254fce7bb407011b5,
    72'h429a042fbab11011ec,
    72'h42df9bb7ba1ff01224,
    72'h4325c547b98d00125e,
    72'h436c82a7b8f8401298,
    72'h43b3d5b7b861b012d3,
    72'h43fbc047b7c938130f,
    72'h44444447b72ed8134c,
    72'h448d63a7b69280138a,
    72'h44d72047b5f43813c9,
    72'h45217c3fb553e8140a,
    72'h456c7987b4b190144b,
    72'h45b81a27b40d28148e,
    72'h4604604fb366a014d1,
    72'h46514e07b2bdf01516,
    72'h469ee587b21318155c,
    72'h46ed2907b1660015a3,
    72'h473c1abfb0b6a015eb,
    72'h478bbcf7b004f81635,
    72'h47dc11f7af51001680,
    72'h482d1c37ae9a9816cc,
    72'h487ede0fade1c8171a,
    72'h48d159e7ad26881769,
    72'h4924924fac68b817b9,
    72'h497889c7aba860180b,
    72'h49cd42e7aae570185f,
    72'h4a22c04faa1fd018b4,
    72'h4a7904afa95780190a,
    72'h4ad012b7a88c701962,
    72'h4b27ed37a7be9819bc,
    72'h4b809707a6ede01a17,
    72'h4bda12ffa61a401a74,
    72'h4c346407a543b01ad3,
    72'h4c8f8d2fa46a181b33,
    72'h4ceb916fa38d701b95,
    72'h4d4873f7a2ada01bfa,
    72'h4da637d7a1caa81c60,
    72'h4e04e057a0e4681cc8,
    72'h4e6470b79ffae01d32,
    72'h4ec4ec4f9f0df81d9e,
    72'h4f2656979e1d981e0c,
    72'h4f88b2f79d29b81e7c,
    72'h4fec04ff9c32481eef,
    72'h505050579b37281f63,
    72'h50b5989f9a38581fda,
    72'h511be1979935c02054,
    72'h51832f27982f4020d0,
    72'h51eb851f9724d8214e,
    72'h5254e78f96166021cf,
    72'h52bf5a879503d02252,
    72'h532ae21f93ed1022d8,
    72'h5397829f92d2082361,
    72'h5405405791b2a023ed,
    72'h54741faf908ec8247c,
    72'h54e425278f6660250d,
    72'h555555578e395825a2,
    72'h55c7b4f78d07882639,
    72'h563b48c78bd0e826d4,
    72'h56b015af8a95582772,
    72'h572620b78954b82814,
    72'h579d6ee7880ef828b9,
    72'h5816058786c3e82962,
    72'h588fe9d78573802a0e,
    72'h590b2167841d902abe,
    72'h5987b1a782c2002b72,
    72'h5a05a0578160b82c2a,
    72'h5a84f3477ff9902ce6,
    72'h5b05b0577e8c682da6,
    72'h5b87ddaf7d19182e6a,
    72'h5c0b816f7b9f802f33,
    72'h5c90a1ff7a1f803000,
    72'h5d1745cf7898f830d2,
    72'h5d9f738f770bb031a9,
    72'h5e2932077577883285,
    72'h5eb4881f73dc603366,
    72'h5f417d07723a00344c,
    72'h5fd017ef7090483538,
    72'h6060605f6edf083629,
    72'h60f25de76d26103720,
    72'h6186185f6b6530381c,
    72'h621b97bf699c38391f,
    72'h62b2e43f67caf83a28,
    72'h634c063765f1403b38,
    72'h63e70637640ed83c4e,
    72'h6483ed276223803d6b,
    72'h6522c3ef602f103e8f,
    72'h65c393df5e31403fba,
    72'h666666675c29e040ed,
    72'h670b45375a18a84228,
    72'h67b23a4f57fd58436a,
    72'h685b4fdf55d7b844b5,
    72'h6906906753a7784608,
    72'h69b40697516c584765,
    72'h6a63bd774f261048ca,
    72'h6b15c0674cd4584a38,
    72'h6bca1ae74a76d84bb1,
    72'h6c80d8f7480d484d33,
    72'h6d3a06cf4597504ebf,
    72'h6df5b0e74314a85057,
    72'h6eb3e4474084e851f9,
    72'h6f74ae173de7b853a7,
    72'h70381c073b3cc05560,
    72'h70fe3bf73883985726,
    72'h71c71c6735bbd858f8,
    72'h7292cc0732e5285ad8,
    72'h73615a172fff085cc5,
    72'h7432d6372d09105ec0,
    72'h750750672a02d060ca,
    72'h75ded94726ebc862e2,
    72'h76b981c723c380650b,
    72'h77975b7f2089706743,
    72'h787878671d3d18698c,
    72'h795ceb0f19ddf06be7,
    72'h7a44c69f166b586e54,
    72'h7b301eb712e4d070d3,
    72'h7c1f07af0f49a87366,
    72'h7d1196670b9950760d,
    72'h7e07e06707d31078c9,
    72'h7f01fbef03f6487b9b,
    72'h800000070001b07e9f
  };
  logic [8:0]       base, addr;
  logic [DATAW-1:0] word_q;
  always_comb begin
    unique case (tbl_i)
      3'd0:    base = 9'd0;   // rcp 
      3'd1:    base = 9'd128; // rsqrt 
      3'd2:    base = 9'd256; // ex2 
      3'd3:    base = 9'd320; // lg2 
      3'd4:    base = 9'd384; // sin 
      3'd5:    base = 9'd448; // tanh 
      default: base = '0;
    endcase
  end
  assign addr = base + 9'(idx_i);
  wire [7:0] bank_enable;
  wire [DATAW-1:0] bank_word [8];
  for (genvar bank = 0; bank < 8; bank++) begin : g_bank
    localparam logic [64*DATAW-1:0] DATA = ROM_DATA[bank*64*DATAW +: 64*DATAW];
    assign bank_enable[bank] = addr[8:6] == 3'(bank);
    for (genvar bitno = 0; bitno < DATAW; bitno++) begin : g_bit
      localparam logic [63:0] LUT = {DATA[63*DATAW+bitno], DATA[62*DATAW+bitno], DATA[61*DATAW+bitno], DATA[60*DATAW+bitno], DATA[59*DATAW+bitno], DATA[58*DATAW+bitno], DATA[57*DATAW+bitno], DATA[56*DATAW+bitno], DATA[55*DATAW+bitno], DATA[54*DATAW+bitno], DATA[53*DATAW+bitno], DATA[52*DATAW+bitno], DATA[51*DATAW+bitno], DATA[50*DATAW+bitno], DATA[49*DATAW+bitno], DATA[48*DATAW+bitno], DATA[47*DATAW+bitno], DATA[46*DATAW+bitno], DATA[45*DATAW+bitno], DATA[44*DATAW+bitno], DATA[43*DATAW+bitno], DATA[42*DATAW+bitno], DATA[41*DATAW+bitno], DATA[40*DATAW+bitno], DATA[39*DATAW+bitno], DATA[38*DATAW+bitno], DATA[37*DATAW+bitno], DATA[36*DATAW+bitno], DATA[35*DATAW+bitno], DATA[34*DATAW+bitno], DATA[33*DATAW+bitno], DATA[32*DATAW+bitno], DATA[31*DATAW+bitno], DATA[30*DATAW+bitno], DATA[29*DATAW+bitno], DATA[28*DATAW+bitno], DATA[27*DATAW+bitno], DATA[26*DATAW+bitno], DATA[25*DATAW+bitno], DATA[24*DATAW+bitno], DATA[23*DATAW+bitno], DATA[22*DATAW+bitno], DATA[21*DATAW+bitno], DATA[20*DATAW+bitno], DATA[19*DATAW+bitno], DATA[18*DATAW+bitno], DATA[17*DATAW+bitno], DATA[16*DATAW+bitno], DATA[15*DATAW+bitno], DATA[14*DATAW+bitno], DATA[13*DATAW+bitno], DATA[12*DATAW+bitno], DATA[11*DATAW+bitno], DATA[10*DATAW+bitno], DATA[9*DATAW+bitno], DATA[8*DATAW+bitno], DATA[7*DATAW+bitno], DATA[6*DATAW+bitno], DATA[5*DATAW+bitno], DATA[4*DATAW+bitno], DATA[3*DATAW+bitno], DATA[2*DATAW+bitno], DATA[1*DATAW+bitno], DATA[0*DATAW+bitno]};
      assign bank_word[bank][bitno] = LUT[addr[5:0]];
    end
  end
  always_comb begin
    word_q = '0;
    for (int bank = 0; bank < 8; bank++)
      word_q |= bank_word[bank] & {DATAW{bank_enable[bank]}};
  end
  // The stored coefficients without their low zero bits, as VX_mufu_rom returns them 
  assign a0_o = 32'({word_q[71:43], 2'b0});
  assign a1_o = 27'($signed({word_q[42:19], 2'b0}));
  assign a2_o = 20'($signed({word_q[18:0], 1'b0}));
endmodule
// Copyright © 2019-2026 
// Licensed under the Apache License, Version 2.0 (the "License"); 
// you may not use this file except in compliance with the License. 
// You may obtain a copy of the License at 
// http://www.apache.org/licenses/LICENSE-2.0 
// Unless required by applicable law or agreed to in writing, software 
// distributed under the License is distributed on an "AS IS" BASIS, 
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
// See the License for the specific language governing permissions and 
// limitations under the License. 
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
 // Copyright 2018 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// Common register defines for RTL designs 
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
  output logic [17:0] square_operand_o,
  input logic [17:0] square_i,
  input logic [38:0] range_i,
  output logic [23:0] range_operand_o,
  output logic [6:0] range_shamt_o,
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
  logic [7:0] range_shift_full;
  assign range_operand_o = x_sig;
  assign range_shift_full = x_e >= 173 ? 8'd0 : 8'd173 - x_e;
  assign range_shamt_o = (fn_i == FN_EX2 && x_e >= 120)
      ? 7'd53 - {3'd0, ex2_lsh}
      : (range_shift_full[7] ? 7'd127 : range_shift_full[6:0]);
  assign ex2_mag = range_i[38:1];
  assign ex2_x   = x_s ? -{1'b0, ex2_mag} : {1'b0, ex2_mag};
  logic [7:0]  trig_lsh, trig_rsh;
  logic        is_sin;
  logic [31:0] trig_u0, trig_u;
  logic        trig_odd, trig_neg, trig_one;
  logic [29:0] trig_t;
  assign trig_lsh = x_e - 8'd119;
  assign trig_rsh = 8'd119 - x_e;
  assign is_sin   = (fn_i == FN_SINPI);
  assign trig_u0 = range_i[31:0];
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
  assign s1_valid = valid_i & ~flush_i;
  assign s1_special = r_special;
  assign s1_sval = r_sval;
  assign s1_exp = r_exp;
  assign s1_neg = r_neg;
  assign s1_zsign = r_zsign;
  assign s1_lg2 = r_lg2;
  assign s1_pass = r_pass;
  assign s1_k = x_k;
  assign s1_tbl = r_tbl;
  assign s1_idx = r_idx;
  assign s1_xl = r_xl;
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
  assign valid_o = s1_valid & ~flush_i;
  assign s2_special = s1_special;
  assign s2_sval = s1_sval;
  assign s2_exp = s1_exp;
  assign s2_neg = s1_neg;
  assign s2_zsign = s1_zsign;
  assign s2_lg2 = s1_lg2;
  assign s2_pass = s1_pass;
  assign s2_k = s1_k;
  assign s2_idx = s1_idx;
  assign s2_xl = s1_xl;
  // xl^2 truncated to 18 bits, as the MUFU's 
  logic [17:0] sq;
  assign square_operand_o = s2_xl;
  assign sq = square_i;
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
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from TransDot 599aaa5 nv_tc/dpa16/rtl/dpa16_core.sv 
// (Solderpad Hardware License 0.51, vendor/transdot/LICENSE.solderpad): the module is renamed ucc_dpa16_core and its 16 
// multiplier tiles are outside it, so that the FU's other operations can use them (ucc_tiles): the core sends each 
// tile's operands and the three tile modes out (ta_o, tb_o, m_*_o) and takes the tiles' products back (tprod_i, 
// dprod_i), in the same cycle, where it used to instantiate dpa16_mul12 itself. The UCC adds one mode, MXFP8 (mx8_i, 
// with fmt_i = FMT_FP8): the 32 FP8 products take one E8M0 scale per side, byte 0 of sa_i and sb_i (an OCP MX block is 
// 32 elements), which moves every product's anchor by the same soff. The addend's anchor moves by -soff instead and the 
// result's exponent by +soff, so every term keeps the shift it would have had, without an adder per product; a scale 
// of 0xFF is NaN. And its three stage registers load only when en_i says an operation enters them, so that the FU's 
// other operations, which share its inputs, do not toggle them. Nothing else is changed. 
// DPA-16 PE datapath: d = c + sum a_i * b_i in FP32 (B200 tensor-core numerics, see ../model/dpa16_ref.py). 
// Three pipeline stages after the (externally registered) inputs: 
//   S1  unpack, 16 multiplier tiles, FP4 block sums, anchors, max anchor, per-term shift amounts   -> r1 
//   S2  FP4 block scaling, alignment of 33 terms in a 27-bit window (truncation), one signed sum  -> r2 
//   S3  normalise, truncate to FP32, specials                                                    -> d_o 
// Vector mode (M > 0, vec_i = 1): M FP32 FMA lanes vd[l] = va[l] * vb[l] + vc[l], same pipeline, built from the 
// GEMM datapath: lane l uses tiles 4l .. 4l+3 for the four 12x12 partial products of its 24x24 multiply and the 
// alignment shifters of slots 8l .. 8l+4 (partial products hh, hl, lh, ll and the addend); it adds its own small 
// 5-term sum, finds its largest anchor with one compare, and has its own normaliser (lane 0 shares the GEMM 
// normaliser and pipeline registers). Same window / truncation numerics; RND = 1: lane 0 rounds to nearest even 
// (one sticky bit per lane term, ../model/lane_rne_ref.py); RND = 2: lane 0 is an IEEE-754 FP32 FMA (RNE, bit-exact 
// with FPnew's fpnew_fma, ../model/ieee_fma_ref.py): tiles 0..3 still form the 24x24 product, merged exactly into 48 
// bits, and FPnew's back end (3p+4-bit alignment, sum, normalisation, rounding, special cases) replaces the window. 
// PIPE = 0 drops the three stage registers (purely combinational core, latency 0) for area comparisons free of 
// pipeline-register placement; ONLY >= 0 hard-wires one format (e.g. FMT_BF16) to measure the multi-format cost. 
module ucc_dpa16_core import dpa16_pkg::*; #(
  parameter int M    = 0,                              // FP32 vector lanes: 0 (GEMM only), 1, 2 or 4 
  parameter bit PIPE = 1'b1,
  parameter int ONLY = -1,
  parameter int SHARE = 0,                             // adder-tree sharing of the lanes, see dpa16_align_sum 
  parameter int RND   = 0                              // 1: lane 0 rounds to nearest even (sticky bits, see dpa16_norm); 
                                                       // 2: lane 0 is an IEEE FMA, FPnew back end (M = 1 only); 
                                                       // 3: lane 0 is an IEEE FMA, lean back end dpa16_fma_lean 
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic [2:0]    en_i,      // PIPE = 1: r1, r2 and r3 load only with an operation entering them 
  input  fmt_e          fmt_i,
  input  logic          a_e5m2_i,
  input  logic          b_e5m2_i,
  input  logic [255:0]  a_i,
  input  logic [255:0]  b_i,
  input  logic [31:0]   sa_i,
  input  logic [31:0]   sb_i,
  input  logic          mx8_i,
  input  logic [31:0]   c_i,
  input logic shared_mode_i,
  input logic [12:0][63:0] scalar_rows_i,
  output logic [63:0] scalar_sum_o, scalar_carry_o,
  output logic [dpa16_pkg::SUMW-1:0] csa_sum_o,
  output logic [dpa16_pkg::SUMW-1:0] csa_carry_o,
  output logic signed [dpa16_pkg::SUMW-1:0] norm_sum_o,
  output logic signed [dpa16_pkg::AW-1:0] norm_emax_o,
  output logic norm_zero_o,
  output logic norm_special_o,
  output logic [31:0]   d_o,
  input  logic                              vec_i,
  input  logic [((M > 0) ? M : 1)-1:0][31:0] va_i,
  input  logic [((M > 0) ? M : 1)-1:0][31:0] vb_i,
  input  logic [((M > 0) ? M : 1)-1:0][31:0] vc_i,
  output logic [((M > 0) ? M : 1)-1:0][31:0] vd_o,
  // the tiles, outside the core: their operands and modes, and their products in the same cycle 
  output logic [NTILE-1:0][15:0]           ta_o,
  output logic [NTILE-1:0][15:0]           tb_o,
  output logic                              m_full_o,
  output logic                              m_fp8_o,
  output logic                              m_fp4_o,
  input  logic [NTILE-1:0][23:0]           tprod_i,
  input  logic [NTILE-1:0][3:0][7:0]       dprod_i
);
  initial begin
    if (M != 0 || RND != 0) $fatal(1, "Biased anchor core requires GEMM M=0, RND=0");
  end
  localparam int ML = (M > 0) ? M : 1;
  localparam int LM = (RND >= 2) ? 0 : M;              // lanes that use the window datapath (slots, shifts, sums) 
  localparam int RW = (RND == 1) ? 1 : 0;              // sticky bit below the window 
  fmt_e fmt;
  assign fmt = (ONLY < 0) ? fmt_i : fmt_e'(ONLY);
  // =========================================================================================== S1 
  logic [NTILE-1:0][15:0] ta_g, tb_g, ta, tb;
  logic [NSLOT-1:0]       ps_g, pnz;
  logic signed [AW-1:0]   panc [NSLOT];
  logic [63:0]            s4;
  logic [3:0][7:0]        ms;
  logic [3:0]             bnz;
  logic signed [AW-1:0]   banc [4];
  logic                   sp_in;
  dpa16_unpack u_unpack (
    .fmt_i (fmt), .a_e5m2_i, .b_e5m2_i, .a_i, .b_i, .sa_i, .sb_i,
    .ta_o (ta_g), .tb_o (tb_g), .ps_o (ps_g), .pnz_o (pnz), .panc_o (panc),
    .s4_o (s4), .ms_o (ms), .bnz_o (bnz), .banc_o (banc), .special_o (sp_in)
  );
  logic vm, is16, istf, is8, is4;
  assign vm   = (M > 0) && vec_i;
  assign is16 = !vm && (fmt == FMT_FP16 || fmt == FMT_BF16);
  assign istf = !vm && fmt == FMT_TF32;
  assign is8  = !vm && fmt == FMT_FP8;
  assign is4  = !vm && (fmt == FMT_NVFP4 || fmt == FMT_MXFP4);
  // ---- vector lanes: FP32 decode and tile operands 
  typedef struct packed {
    logic                 s;
    logic [23:0]          sig;
    logic signed [AW-1:0] ue;
    logic                 sp;
  } f32_t;
  function automatic f32_t dec32(logic [31:0] x);
    f32_t r;
    r.s   = x[31];
    r.sig = {x[30:23] != 0, x[22:0]};
    r.ue  = AW'(x[30:23] != 0 ? x[30:23] : 8'd1) - AW'(127);
    r.sp  = &x[30:23];
    return r;
  endfunction
  f32_t vA [ML], vB [ML], vC [ML];
  always_comb begin
    for (int l = 0; l < ML; l++) begin
      vA[l] = dec32(va_i[l]);
      vB[l] = dec32(vb_i[l]);
      vC[l] = dec32(vc_i[l]);
    end
  end
  // lane l, tile 4l+k: k = 0 a_lo*b_lo, 1 a_lo*b_hi, 2 a_hi*b_lo, 3 a_hi*b_hi 
  always_comb begin
    ta = ta_g;
    tb = tb_g;
    // tiles 4M.. keep their GEMM operands in vector mode: their slots are shifted out (see dsh), nothing to gate 
    if (vm) begin
      for (int t = 0; t < 4 * M; t++) begin
        ta[t] = {4'd0, (t % 4 >= 2) ? vA[t/4].sig[23:12] : vA[t/4].sig[11:0]};
        tb[t] = {4'd0, (t % 4 == 1 || t % 4 == 3) ? vB[t/4].sig[23:12] : vB[t/4].sig[11:0]};
      end
    end
  end
  logic [NTILE-1:0][23:0]     tprod;
  logic [NTILE-1:0][3:0][7:0] dprod;
  assign ta_o     = ta;
  assign tb_o     = tb;
  assign m_full_o = is16 || istf || vm;
  assign m_fp8_o  = is8;
  assign m_fp4_o  = is4;
  assign tprod    = tprod_i;
  assign dprod    = dprod_i;
  // FP4: exact signed sum of the 16 integer products of each block (|sum| <= 16 * 144) 
  logic signed [12:0] bsum [4];
  always_comb begin
    for (int blk = 0; blk < 4; blk++) begin
      logic [12:0] unsigned_sum;
      logic [4:0] negative_count, high_correction;
      unsigned_sum = '0;
      negative_count = '0;
      for (int i = 16 * blk; i < 16 * blk + 16; i++) begin
        unsigned_sum += {5'd0, dprod[i/4][i%4] ^ {8{s4[i]}}};
        negative_count += 5'(s4[i]);
      end
      high_correction = 5'd0 - negative_count;
      bsum[blk] = $signed(unsigned_sum + {high_correction, 3'd0, negative_count});
    end
  end
  // addend 
  logic                 cs, cnz, csp;
  logic [23:0]          cm;
  logic signed [AW-1:0] canc;
  assign cs   = c_i[31];
  assign cm   = {c_i[30:23] != 0, c_i[22:0]};
  assign cnz  = cm != 0;
  assign csp  = &c_i[30:23];
  assign canc = AW'(c_i[30:23] != 0 ? c_i[30:23] : 8'd1) - AW'(127);
  // MXFP8: the two E8M0 scales' exponents, which every product's anchor would add 
  logic                 mx8, mx8_sp;
  logic signed [AW-1:0] soff;
  logic [7:0] anchor_bias;
  logic signed [AW-1:0] anchor_offset;
  assign anchor_bias = is4 ? (fmt == FMT_NVFP4 ? 8'd4 : 8'd244)
      : is8 ? 8'd14 + (a_e5m2_i ? 8'd8 : 8'd0) + (b_e5m2_i ? 8'd8 : 8'd0)
      : fmt == FMT_FP16 ? 8'd30 : 8'd254;
  assign anchor_offset = soff - AW'({1'b0, anchor_bias});
  assign mx8    = mx8_i && is8;
  assign soff   = mx8 ? AW'(sa_i[7:0]) + AW'(sb_i[7:0]) - AW'(254) : '0;
  assign mx8_sp = mx8 && (&sa_i[7:0] || &sb_i[7:0]);
  // GEMM term anchors / nonzero flags / signs 
  logic signed [AW-1:0] tanc [NSLOT+1];
  logic [NSLOT:0]       tnz;
  logic [NSLOT-1:0]     ps;
  always_comb begin
    for (int s = 0; s < NSLOT; s++) begin
      tanc[s] = panc[s];
      tnz[s]  = pnz[s] && !is4 && !vm;
      ps[s]   = ps_g[s];
    end
    for (int blk = 0; blk < 4; blk++) begin
      if (is4) begin
        tanc[blk] = banc[blk];
        tnz[blk]  = bnz[blk];
      end
    end
    tanc[NSLOT] = canc - anchor_offset;
    tnz[NSLOT]  = cnz && !vm;
  end
  // vector lanes, terms 8l + {hh, hl, lh, ll, c}: the partial products' anchors are ap, ap-12, ap-12, ap-24, so the 
  // lane's largest anchor is max(ap, addend) and the shifts follow from one difference (no search tree) 
  logic signed [AW-1:0] vsemax [ML];
  logic [ML-1:0][4:0]   vdA, vdC;           // shift of hh / of the addend (saturated) 
  logic [ML-1:0]        vpnz, vcnz;
  always_comb begin
    for (int l = 0; l < ML; l++) begin
      logic signed [AW-1:0] ap, df;
      ap      = vA[l].ue + vB[l].ue;
      vpnz[l] = vA[l].sig != 0 && vB[l].sig != 0;
      vcnz[l] = vC[l].sig != 0;
      df      = ap - vC[l].ue;
      if (vpnz[l] && (!vcnz[l] || df >= 0)) begin
        vsemax[l] = ap;
        vdA[l]    = '0;
        vdC[l]    = (df > AW'(WIN)) ? 5'(WIN) : df[4:0];
      end else begin
        vsemax[l] = vC[l].ue;
        vdC[l]    = '0;
        vdA[l]    = (-df > AW'(WIN)) ? 5'(WIN) : 5'(-df);
      end
    end
  end
  // GEMM: largest anchor over the nonzero terms, balanced tree (zero terms carry the most negative value) 
  logic signed [AW-1:0] emax;
  logic                 anynz;
  logic signed [AW-1:0] semax [4];
  logic [3:0]           snz;
  always_comb begin
    logic [8:0] l0 [32], l1 [16], l2 [8], l3 [4], l4 [2], l5;
    for (int s = 0; s < 32; s++) l0[s] = tnz[s] ? tanc[s][8:0] : 9'd0;
    for (int i = 0; i < 16; i++) l1[i] = (l0[2*i] > l0[2*i+1]) ? l0[2*i] : l0[2*i+1];
    for (int i = 0; i < 8; i++)  l2[i] = (l1[2*i] > l1[2*i+1]) ? l1[2*i] : l1[2*i+1];
    for (int i = 0; i < 4; i++)  l3[i] = (l2[2*i] > l2[2*i+1]) ? l2[2*i] : l2[2*i+1];
    for (int i = 0; i < 2; i++)  l4[i] = (l3[2*i] > l3[2*i+1]) ? l3[2*i] : l3[2*i+1];
    l5   = (l4[0] > l4[1]) ? l4[0] : l4[1];
    emax = (tnz[NSLOT] && (!(|tnz[NSLOT-1:0]) || tanc[NSLOT] > $signed({1'b0, l5})))
        ? tanc[NSLOT] : AW'({1'b0, l5});
    for (int g = 0; g < 4; g++) semax[g] = AW'({1'b0, l3[g]});
    anynz = |tnz;
    for (int g = 0; g < 4; g++) snz[g] = |tnz[8*g +: 8];
  end
  // ------------------------------------------------------------------------------------- r1 
  // FP4 reuses the tile-product register of tiles 0..3 for {scale product, block sum} 
  logic [NTILE-1:0][23:0] r1_tprod;
  logic [NSLOT-1:0]       r1_ps;
  logic signed [AW-1:0]   r1_tanc [NSLOT+1];
  logic [NSLOT:0]         r1_tnz;
  logic                   r1_cs;
  logic [23:0]            r1_cm;
  logic signed [AW-1:0]   r1_emax, r1_soff;
  logic                   r1_anynz, r1_sp;
  fmt_e                   r1_fmt;
  logic [1:0]             r1_e5;
  logic                   r1_vm;
  logic [ML-1:0][23:0]    r1_vcm;
  logic signed [AW-1:0]   r1_semax [ML];
  logic [ML-1:0]          r1_snz, r1_vsp;
  logic [ML-1:0][4:0]     r1_vdA, r1_vdC;
  logic [ML-1:0]          r1_vpnz, r1_vcnz, r1_vps, r1_vcs;
  if (PIPE) begin : g_r1
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        r1_tprod <= '0;
        r1_ps    <= '0;
        for (int s = 0; s <= NSLOT; s++) r1_tanc[s] <= '0;
        r1_tnz   <= '0;
        r1_cs    <= 1'b0;
        r1_cm    <= '0;
        r1_emax  <= '0;
        r1_soff  <= '0;
        r1_anynz <= 1'b0;
        r1_sp    <= 1'b0;
        r1_fmt   <= FMT_FP16;
        r1_e5    <= '0;
        r1_vm    <= 1'b0;
        r1_vcm   <= '0;
        for (int l = 0; l < ML; l++) r1_semax[l] <= '0;
        r1_snz   <= '0;
        r1_vsp   <= '0;
        r1_vdA   <= '0;
        r1_vdC   <= '0;
        r1_vpnz  <= '0;
        r1_vcnz  <= '0;
        r1_vps   <= '0;
        r1_vcs   <= '0;
      end else if (en_i[0]) begin
        for (int t = 0; t < NTILE; t++)
          r1_tprod[t] <= (is4 && t < 4) ? {3'd0, ms[t], bsum[t]} :
                         is8               ? {8'd0, dprod[t][1], dprod[t][0]} : tprod[t];
        r1_ps    <= ps;
        for (int s = 0; s <= NSLOT; s++) r1_tanc[s] <= tanc[s];
        r1_tnz   <= tnz;
        r1_cs    <= cs;
        r1_cm    <= cm;
        r1_emax  <= emax;
        r1_soff  <= anchor_offset;
        r1_anynz <= anynz;
        r1_sp    <= !vm && (sp_in || csp || mx8_sp);
        r1_fmt   <= fmt;
        r1_e5    <= {a_e5m2_i, b_e5m2_i};
        if (M > 0) begin
          r1_vm <= vm;
          for (int l = 0; l < ML; l++) begin
            r1_vcm[l]   <= vC[l].sig;
            r1_semax[l] <= vsemax[l];
            r1_vsp[l]   <= vA[l].sp || vB[l].sp || vC[l].sp;
            r1_vps[l]   <= vA[l].s ^ vB[l].s;
            r1_vcs[l]   <= vC[l].s;
          end
          r1_snz  <= vpnz | vcnz;
          r1_vdA  <= vdA;
          r1_vdC  <= vdC;
          r1_vpnz <= vpnz;
          r1_vcnz <= vcnz;
        end
      end
    end
  end else begin : g_r1c
    always_comb begin
      // stage-register outputs of the lane fields stay 0 without lanes, as with PIPE = 1 
      r1_vm = 1'b0; r1_vcm = '0; r1_snz = '0; r1_vsp = '0; r1_vdA = '0; r1_vdC = '0;
      r1_vpnz = '0; r1_vcnz = '0; r1_vps = '0; r1_vcs = '0;
      for (int l = 0; l < ML; l++) r1_semax[l] = '0;
      for (int t = 0; t < NTILE; t++)
        r1_tprod[t] = (is4 && t < 4) ? {3'd0, ms[t], bsum[t]} :
                      is8               ? {8'd0, dprod[t][1], dprod[t][0]} : tprod[t];
      r1_ps    = ps;
      for (int s = 0; s <= NSLOT; s++) r1_tanc[s] = tanc[s];
      r1_tnz   = tnz;
      r1_cs    = cs;
      r1_cm    = cm;
      r1_emax  = emax;
      r1_soff  = anchor_offset;
      r1_anynz = anynz;
      r1_sp    = !vm && (sp_in || csp || mx8_sp);
      r1_fmt   = fmt;
      r1_e5    = {a_e5m2_i, b_e5m2_i};
      if (M > 0) begin
        r1_vm = vm;
        for (int l = 0; l < ML; l++) begin
          r1_vcm[l]   = vC[l].sig;
          r1_semax[l] = vsemax[l];
          r1_vsp[l]   = vA[l].sp || vB[l].sp || vC[l].sp;
          r1_vps[l]   = vA[l].s ^ vB[l].s;
          r1_vcs[l]   = vC[l].s;
        end
        r1_snz  = vpnz | vcnz;
        r1_vdA  = vdA;
        r1_vdC  = vdC;
        r1_vpnz = vpnz;
        r1_vcnz = vcnz;
      end
    end
  end
  // =========================================================================================== S2 
  // each term's right shift: distance to the largest anchor, saturated at the window (vector lanes: from the lane's 
  // two registered differences, partial product k adding its 0 / 12 / 12 / 24 offset) 
  logic [4:0]       dsh [NSLOT+1];
  logic [NSLOT-1:0] ps2;
  always_comb begin
    for (int s = 0; s <= NSLOT; s++) begin
      logic signed [AW-1:0] d;
      d = r1_emax - r1_tanc[s];
      if (s < NSLOT) begin
        logic [8:0] product_distance;
        product_distance = r1_emax[8:0] - r1_tanc[s][8:0];
        dsh[s] = (!r1_tnz[s] || product_distance > 9'(WIN)) ? 5'(WIN) : product_distance[4:0];
      end else begin
        dsh[s] = (!r1_tnz[s] || d > AW'(WIN)) ? 5'(WIN) : d[4:0];
      end
      if (s < NSLOT) ps2[s] = r1_ps[s];
      // vector mode: all term flags are clear, so every slot already gets the saturated shift; only the lane slots 
      // 8l .. 8l+4 are overridden 
      if (LM > 0 && r1_vm && s < 8 * LM && s % 8 < 5) begin
        logic [5:0] dv;
        int         l, k;
        l = s / 8;
        k = s % 8;
        if (k < 4) begin
          dv = 6'(r1_vdA[l % ML]) + 6'(k == 0 ? 0 : (k == 3 ? 24 : 12));
          dsh[s] = (!r1_vpnz[l % ML] || dv > 6'(WIN)) ? 5'(WIN) : dv[4:0];
          ps2[s] = r1_vps[l % ML];
        end else begin
          dsh[s] = r1_vcnz[l % ML] ? r1_vdC[l % ML] : 5'(WIN);
          ps2[s] = r1_vcs[l % ML];
        end
      end
    end
  end
  localparam int SW = SUMW + RW;
  logic signed [SW-1:0] sum;
  localparam int LMS = (LM > 0) ? LM : 1;                // window-lane sums the adder block produces 
  logic signed [SW-1:0] vsum_a [LMS];
  logic signed [SW-1:0] vsum [ML];                       // padded to ML (IEEE lanes have no window sum) 
  dpa16_align_sum #(.M (LM), .SHARE (SHARE), .RND (RW)) u_align (
    .shared_mode_i, .scalar_rows_i, .scalar_sum_o, .scalar_carry_o,
    .csa_sum_o, .csa_carry_o,
    .fmt_i (r1_fmt), .e5_i (r1_e5), .tprod_i (r1_tprod), .ps_i (ps2), .dsh_i (dsh),
    .cs_i (r1_cs), .cm_i (r1_cm), .vec_i (r1_vm), .vcm_i (r1_vcm), .sum_o (sum), .vsum_o (vsum_a)
  );
  always_comb for (int l = 0; l < ML; l++) vsum[l] = (l < LMS) ? vsum_a[l] : '0;
  // RND = 2: lane 0 is an IEEE FMA, its exact product from tiles 0..3 (hh, hl, lh, ll = tiles 3, 2, 1, 0) goes into 
  // FPnew's FMA back end with the raw operands; the window datapath is GEMM only 
  // (RND = 3: every lane l is a lean IEEE FMA fed by its own tiles 4l .. 4l+3; RND = 2 is lane 0 only) 
  logic [ML-1:0][2:0][31:0] r1_vraw;
  logic [ML-1:0][31:0]      ieee_d;
  if (RND >= 2) begin : g_r1x
    if (PIPE) begin : g_r
      always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) r1_vraw <= '0;
        else if (en_i[0]) for (int l = 0; l < ML; l++) r1_vraw[l] <= {vc_i[l], vb_i[l], va_i[l]};
    end else begin : g_c
      always_comb for (int l = 0; l < ML; l++) r1_vraw[l] = {vc_i[l], vb_i[l], va_i[l]};
    end
  end else begin : g_r1x0
    assign r1_vraw = '0;
  end
  if (RND == 2) begin : g_ieee
    logic [47:0] prod;
    assign prod = {r1_tprod[3], 24'd0} + {12'd0, r1_tprod[2], 12'd0} + {12'd0, r1_tprod[1], 12'd0} +
                  {24'd0, r1_tprod[0]};
    dpa16_fma_back #(.FpFormat (fpnew_pkg::FP32), .NumPipeRegs (0)) u_fma (
      .clk_i, .rst_ni, .operands_i (r1_vraw[0]), .product_i (prod), .is_boxed_i (3'b111),
      .rnd_mode_i (fpnew_pkg::RNE), .op_i (fpnew_pkg::FMADD), .op_mod_i (1'b0), .tag_i (1'b0), .mask_i (1'b1),
      .aux_i (1'b0), .in_valid_i (1'b1), .in_ready_o (), .flush_i (1'b0), .result_o (ieee_d[0]), .status_o (),
      .extension_bit_o (), .tag_o (), .mask_o (), .aux_o (), .out_valid_o (), .out_ready_i (1'b1), .busy_o (),
      .reg_ena_i ('0)
    );
    for (genvar l = 1; l < ML; l++) begin : g_rest
      assign ieee_d[l] = '0;
    end
  end else if (RND == 3) begin : g_lean
    for (genvar l = 0; l < ML; l++) begin : g_l
      dpa16_fma_lean4 u_fma (.a_i (r1_vraw[l][0]), .b_i (r1_vraw[l][1]), .c_i (r1_vraw[l][2]),
                            .hh_i (r1_tprod[4 * l + 3]), .hl_i (r1_tprod[4 * l + 2]), .lh_i (r1_tprod[4 * l + 1]),
                            .ll_i (r1_tprod[4 * l]), .d_o (ieee_d[l]));
    end
  end else begin : g_no_ieee
    assign ieee_d = '0;
  end
  // lane 0 rides on the GEMM registers (RND < 2); lanes 1.. have their own 
  logic lvm;
  assign lvm = LM > 0 && r1_vm;
  logic signed [SW-1:0]   r2_sum;
  logic signed [AW-1:0]   r2_emax;
  logic                   r2_anynz, r2_sp, r2_vm;
  logic [ML-1:0][31:0]    r2_ieee;
  logic signed [SW-1:0]   r2_vsum [ML];
  logic signed [AW-1:0]   r2_semax [ML];
  logic [ML-1:0]          r2_snz, r2_vsp;
  if (PIPE) begin : g_r2
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        r2_sum   <= '0;
        r2_vm    <= 1'b0;
        r2_ieee  <= '0;
        r2_emax  <= '0;
        r2_anynz <= 1'b0;
        r2_sp    <= 1'b0;
        for (int l = 0; l < ML; l++) begin
          r2_vsum[l]  <= '0;
          r2_semax[l] <= '0;
        end
        r2_snz <= '0;
        r2_vsp <= '0;
      end else if (en_i[1]) begin
        r2_sum   <= lvm ? vsum[0]     : sum;
        r2_vm    <= r1_vm;
        r2_ieee  <= ieee_d;
        r2_emax  <= lvm ? r1_semax[0] : r1_emax + r1_soff;
        r2_anynz <= lvm ? r1_snz[0]   : r1_anynz;
        r2_sp    <= lvm ? r1_vsp[0]   : r1_sp;
        for (int l = 1; l < ML; l++) begin
          r2_vsum[l]  <= vsum[l];
          r2_semax[l] <= r1_semax[l];
        end
        r2_snz <= r1_snz;
        r2_vsp <= r1_vsp;
      end
    end
  end else begin : g_r2c
    always_comb begin
      for (int l = 0; l < ML; l++) begin
        r2_vsum[l]  = '0;
        r2_semax[l] = '0;
      end
      r2_sum   = lvm ? vsum[0]     : sum;
      r2_vm    = r1_vm;
      r2_ieee  = ieee_d;
      r2_emax  = lvm ? r1_semax[0] : r1_emax + r1_soff;
      r2_anynz = lvm ? r1_snz[0]   : r1_anynz;
      r2_sp    = lvm ? r1_vsp[0]   : r1_sp;
      for (int l = 1; l < ML; l++) begin
        r2_vsum[l]  = vsum[l];
        r2_semax[l] = r1_semax[l];
      end
      r2_snz = r1_snz;
      r2_vsp = r1_vsp;
    end
  end
  // =========================================================================================== S3 
  assign norm_sum_o = r2_sum;
  assign norm_emax_o = r2_emax;
  assign norm_zero_o = !r2_anynz;
  assign norm_special_o = r2_sp;
  logic [ML-1:0][31:0] dn;
  logic [31:0] gn;
  dpa16_norm #(.RND (RW)) u_norm (.sum_i (r2_sum), .emax_i (r2_emax), .zero_i (!r2_anynz), .special_i (r2_sp),
                                  .rne_i (r2_vm), .d_o (gn));
  assign dn[0] = (RND >= 2 && r2_vm) ? r2_ieee[0] : gn;
  for (genvar l = 1; l < ML; l++) begin : g_lane_norm
    if (RND >= 2) begin : g_i
      assign dn[l] = r2_ieee[l];
    end else begin : g_w                                 // window lane with its own small sum (RND = 1: RNE too) 
      dpa16_norm #(.RND (RW)) u_norm (.sum_i (r2_vsum[l]), .emax_i (r2_semax[l]), .zero_i (!r2_snz[l]),
                                       .special_i (r2_vsp[l]), .rne_i (RW ? r2_vm : 1'b0), .d_o (dn[l]));
    end
  end
  logic [ML-1:0][31:0] r3_d;
  if (PIPE) begin : g_r3
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) r3_d <= '0;
      else if (en_i[2]) r3_d <= dn;
    end
  end else begin : g_r3c
    assign r3_d = dn;
  end
  assign d_o  = r3_d[0];
  assign vd_o = r3_d;
endmodule
// s2chitni & Claude (AI-generated) 
// The UCC FU's DPA-16 (ucc_pkg's FP_DPA opcodes): d = c + sum of a_i * b_i in FP32, on TransDot's dpa16_core at 599aaa5 
// with its tiles taken out (ucc_dpa16_core), every format selectable per operation (M=0, PIPE=1, ONLY=-1, SHARE=0, 
// RND=0, the configuration of dora-lab's rta_dpa16 array). The 16 tiles are the 
// FU's (ucc_tiles): the core sends their operands and modes out and takes their products back in the same cycle. Its 
// numerics are TransDot's (dpa16_ref.py): exact products, every term aligned to the largest anchor in a 27-bit window 
// with truncation, one sum, FP32 by truncation, the canonical NaN for any NaN or infinity among the active inputs. The 
// inputs are the FU's input register; the core's three stages return d three cycles later, four after issue. 
// The FU's own two formats arrive mapped onto the core's paths (ucc_fma, before the input register): MXFP8 as FP8 with 
// mx8_i, which applies one E8M0 scale per side from byte 0 of the scales, and FP4 as MXFP4 with every scale 2^0. en_i 
// says which of the core's stages a DPA-16 operation enters (bit 0 the first), and only those registers load. 
module ucc_dpa16 (
  input  logic                             clk_i,
  input  logic                             rst_ni,
  input  logic [2:0]                       en_i,   // a DPA-16 operation enters S1's, S2's, S3's register 
  input  logic [2:0]                       fmt_i,  // dpa16_pkg::fmt_e 
  input  logic                             mx8_i,  // MXFP8 (with fmt_i FP8) 
  input  logic [1:0]                       e5m2_i, // FP8 subtypes: bit 0 a's, bit 1 b's (1: E5M2) 
  input  logic [ucc_pkg::DPA_OPERAND-1:0]  a_i,    // {four 8-bit block scales, 256-bit operand} 
  input  logic [ucc_pkg::DPA_OPERAND-1:0]  b_i,
  input  logic [31:0]                      c_i,
  input logic shared_mode_i,
  input logic [12:0][63:0] scalar_rows_i,
  output logic [63:0] scalar_sum_o, scalar_carry_o,
  output logic [dpa16_pkg::SUMW-1:0] csa_sum_o,
  output logic [dpa16_pkg::SUMW-1:0] csa_carry_o,
  output logic signed [dpa16_pkg::SUMW-1:0] norm_sum_o,
  output logic signed [dpa16_pkg::AW-1:0] norm_emax_o,
  output logic norm_zero_o,
  output logic norm_special_o,
  output logic [31:0]                      d_o,
  // the tiles (ucc_tiles) 
  output logic [15:0][15:0]                ta_o,
  output logic [15:0][15:0]                tb_o,
  output logic                             m_full_o,
  output logic                             m_fp8_o,
  output logic                             m_fp4_o,
  input  logic [15:0][23:0]                tprod_i,
  input  logic [15:0][3:0][7:0]            dprod_i
);
  logic [0:0][31:0] vd_unused;
  ucc_dpa16_core #(
    .M     ( 0    ),
    .PIPE  ( 1'b0 ),
    .ONLY  ( -1   ),
    .SHARE ( 0    ),
    .RND   ( 0    )
  ) i_core (
    .clk_i,
    .rst_ni,
    .en_i,
    .fmt_i    ( dpa16_pkg::fmt_e'(fmt_i) ),
    .a_e5m2_i ( e5m2_i[0]                ),
    .b_e5m2_i ( e5m2_i[1]                ),
    .a_i      ( a_i[255:0]               ),
    .b_i      ( b_i[255:0]               ),
    .sa_i     ( a_i[287:256]             ),
    .sb_i     ( b_i[287:256]             ),
    .mx8_i,
    .c_i,
    .shared_mode_i, .scalar_rows_i, .scalar_sum_o, .scalar_carry_o,
    .csa_sum_o, .csa_carry_o,
    .norm_sum_o, .norm_emax_o, .norm_zero_o, .norm_special_o,
    .d_o,
    .vec_i    ( 1'b0                     ),
    .va_i     ( '0                       ),
    .vb_i     ( '0                       ),
    .vc_i     ( '0                       ),
    .vd_o     ( vd_unused                ),
    .ta_o,
    .tb_o,
    .m_full_o,
    .m_fp8_o,
    .m_fp4_o,
    .tprod_i,
    .dprod_i
  );
endmodule
// Copyright 2019 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// SPDX-License-Identifier: SHL-0.51 
// Author: Stefan Mach <smach@iis.ee.ethz.ch> 
// Modified for the RTA UCC by s2chitni & Claude (AI-generated), from TransDot 599aaa5 src/fpnew_fma.sv: the module 
// is renamed ucc_fma and is the UCC FU's datapath, FpFormat must be FP64, ucc_op_i is the FU's global opcode 
// (ucc_pkg's map) and rnd_mode_i the rounding mode of the operations that round: RNE, RTZ, RDN, RUP or RMM, and codes 
// 5-7, which FPnew would round with a don't-care, to nearest even (DPA-16 reads its bits 1-0 as given). 
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
// For an SFU opcode, operand a's low 32 bits are an FP32 x and the operation is one of the Vortex MUFU's approximate 
// functions, in the opcode's low bits (rcp, rsqrt, ex2, lg2, sinpi, cospi, tanh). Its front end, ucc_sfu (the MUFU's 
// range reduction and coefficient ROM), takes two cycles and then hands the input register one FMA in place of the 
// operation issued that cycle (which is lost unless it is an SFU function too, whose own front end takes it; issue 
// no other operation two cycles after an SFU function, and in_ready_o is clear for one then). The FP64 path 
// evaluates the MUFU's quadratic: the tiles across the halves of a and b give 2^28 (a1 xl + a2 xl^2), with 
// corrections for the coefficients' signs; the two's complement product is sign-extended into the adder, and c has 
// no implicit bit. The FP64-normalized sum is rounded to FP32 (to nearest even) in the output cycle, and the result 
// is that FP32 value NaN-boxed, five cycles after issue (FMAs: three). 
// An INT32 opcode (0x00-0x3F) is an ALU operation or a multiply, of bits 31-0, and its result is zero-extended. The 
// ALU's (ucc_int_alu, after the input register) read a and b from the operand register, which holds them unchanged 
// for it. A multiply: 
// it places a and b at bits 52-21 of the multiplier's operands, signed or not (ucc_tilemul corrects for the signs), and 
// c as an addend whose exponents put its bit 0 at the product's bit 42 or 74; the result is bits 75-44, 107-76 or 
// 107-44 of the sum, zero-extended (a wide product fills all 64 bits). 
// FP min, max, neg, abs and compares (ucc_fp_noncomp) and conversions (ucc_fp_cast) are FPnew's own units, after the 
// input register, and status_o carries their flags. DPA-16, the INT32 operations and the SFU's functions raise none. 
// The FU has no divider. 
// A DPA-16 opcode runs on TransDot's dpa16_core (ucc_dpa16), after the input register, whose operand register also 
// holds bits 63-0 of DPA-16's a and b and its c: the rest of a and b (dpa_hi_i: the vectors' bits 255-64 and the 
// block scales) has its own register, which nothing else reads. That register, the registered format and the core's 
// three stage registers load only with a DPA-16 operation, so the FU's other operations do not toggle them. The 
// multiplier's operand registers likewise load only with an operation that uses the product (the FMA path's, the 
// SFU's FMA and INT32 multiplies), so the tiles stay still under the other operations. 
// The FMA path's three cycles are split differently from fpnew_fma's, at the same latency: the input stage forms the 
// product and aligns the addend, and the middle register holds both; the middle stage adds them (fpnew_fma's two 
// sums), normalizes, and assembles the value before rounding, which the output register holds; the output cycle 
// rounds it and assembles the result on its way to result_o. So the tiles and the tiled product have the whole input 
// stage, and the rounding uses the cycle after the output register, which used to hold only the bypass mux. 
// Every result skips the stages it does not need through a bypass mux in front of result_o: ALU and FP compare-unit 
// results one cycle after issue, combinationally from the input register; multiplies and conversions two, from the 
// middle stage's sum and the middle register's special result; FMAs three and SFU functions five, rounded from the 
// output register; DPA-16 four, from the core's own output register. Only the operations that use the middle stage 
// (the FMA path's, the SFU's FMA, multiplies and conversions) enter the middle register. When two results are due in 
// the same cycle the younger operation's is returned and the older one's is lost. tag_o, mask_o and aux_o are the 
// returned result's operation's. The bypass assumes out_ready_i stays set. 
// Defining UCC_CHECK_ISSUE makes a breach of either issue rule a simulation error: an operation issued while 
// in_ready_o is clear (the SFU's slot), and two results due in the same cycle (issue_lost and result_hidden). 
// flush_i drops every operation in flight, the SFU front end's and DPA-16's included: no operation issued in or before 
// the cycle flush_i is set returns a result after that cycle. 
 // Copyright 2018 ETH Zurich and University of Bologna. 
// Copyright and related rights are licensed under the Solderpad Hardware 
// License, Version 0.51 (the "License"); you may not use this file except in 
// compliance with the License. You may obtain a copy of the License at 
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law 
// or agreed to in writing, software, hardware and materials distributed under 
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
// CONDITIONS OF ANY KIND, either express or implied. See the License for the 
// specific language governing permissions and limitations under the License. 
// Common register defines for RTL designs 
module ucc_convert_shared (
  input logic [31:0] a_i,
  input logic [4:0] func_i,
  input fpnew_pkg::roundmode_e rnd_mode_i,
  input logic [31:0] sum_i,
  input logic [99:0] aligned_i,
  input logic [5:0] lzc_i,
  input logic [77:0] normalized_i,
  input logic [31:0] rounded_i,
  input fpnew_pkg::status_t rounded_status_i,
  output logic [31:0] add_a_o,
  output logic add_carry_o,
  output logic [23:0] align_mant_o,
  output logic [6:0] align_shamt_o,
  output logic [31:0] value_o,
  output ucc_pkg::round_t round_o,
  output logic [63:0] result_o,
  output fpnew_pkg::status_t status_o
);
  import ucc_pkg::*;
  logic i2f, negative, unsigned_int, is_nan, invalid_int, range_overflow;
  logic [7:0] exp_field, shift_full, norm_exp;
  logic [31:0] truncated_int;
  logic [1:0] round_sticky;
  logic round_up;
  assign i2f = func_i == FP_CVT_S32 || func_i == FP_CVT_U32;
  assign unsigned_int = func_i == FP_TO_U32;
  assign negative = a_i[31] && (!i2f || func_i == FP_CVT_S32);
  assign exp_field = a_i[30:23];
  assign is_nan = (&exp_field) && (|a_i[22:0]);
  assign align_mant_o = {(|exp_field), a_i[22:0]};
  assign shift_full = exp_field >= 158 ? 8'd0 : 8'd158 - exp_field;
  assign align_shamt_o = shift_full[7] ? 7'd127 : shift_full[6:0];
  assign truncated_int = aligned_i[99:68];
  assign round_sticky = {aligned_i[67], (|aligned_i[66:0]) || ((exp_field < 59) && (|a_i[30:0]))};
  always_comb begin
    unique case (rnd_mode_i)
      fpnew_pkg::RNE: round_up = round_sticky[1] && (round_sticky[0] || truncated_int[0]);
      fpnew_pkg::RTZ: round_up = 1'b0;
      fpnew_pkg::RDN: round_up = (|round_sticky) && negative;
      fpnew_pkg::RUP: round_up = (|round_sticky) && !negative;
      default: round_up = round_sticky[1];
    endcase
  end
  // -(m + r) = ~m + (1-r), so rounding and sign restoration use one addition.
  assign add_a_o = (i2f ? a_i : truncated_int) ^ {32{negative}};
  assign add_carry_o = negative ^ (!i2f && round_up);
  assign range_overflow = unsigned_int ? exp_field > 158
      : exp_field > 157 && !(negative && exp_field == 158 && a_i[22:0] == 0);
  assign invalid_int = is_nan || range_overflow
      || (unsigned_int && negative && ((|truncated_int) || round_up));
  assign norm_exp = sum_i == 0 ? 8'd0 : 8'd158 - {2'b0, lzc_i};
  assign value_o = sum_i == 0 ? 32'd0 : {negative, norm_exp, normalized_i[74:52]};
  assign round_o = '{round_sticky: {normalized_i[51], (|normalized_i[50:0])}, default: '0};
  always_comb begin
    status_o = '0;
    result_o = {32'd0, sum_i};
    if (i2f) begin
      result_o = {32'hffffffff, rounded_i};
      status_o = rounded_status_i;
    end else begin
      status_o.NV = invalid_int;
      status_o.NX = !invalid_int && (|round_sticky);
      if (invalid_int) begin
        if (unsigned_int) result_o = {32'd0, (negative && !is_nan) ? 32'd0 : 32'hffffffff};
        else result_o = {32'd0, (negative && !is_nan) ? 32'h80000000 : 32'h7fffffff};
      end
    end
  end
endmodule

module ucc_fma #(
  parameter bit EnableFp64 = 1'b0,
  parameter bit PackedIntLow = 1'b1,
  parameter bit CompactAccumulator = 1'b1,
  parameter bit FixedScalarAlign = 1'b1,
  // The only configuration the FU's pipeline supports (one register per stage), checked below 
  parameter fpnew_pkg::fp_format_e   FpFormat    = fpnew_pkg::FP64,
  parameter int unsigned             NumPipeRegs = 0,
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
  input logic dpa_mode_i,
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
  localparam int unsigned INT_SHIFT  = (!EnableFp64 && PackedIntLow) ? 0 : PRECISION_BITS - 32;
  localparam int unsigned INT_LSB    = 2 * INT_SHIFT + 2;
  localparam int unsigned INT_EXP_LO = BIAS + 2 * INT_SHIFT - MAN_BITS;
  localparam int unsigned INT_EXP_HI = INT_EXP_LO + 32;
  localparam bit COMPACT = !EnableFp64 && PackedIntLow && CompactAccumulator;
  // MUFU and scalar products arrive in the common 64-bit frame.
  localparam int unsigned PRODUCT_REG_WIDTH = 64;
  localparam int unsigned ACC_WIDTH = 78;
  // The bypass latencies (ucc_pkg::unit_e), the SFU's slot and DPA-16's three stages assume one register per stage, 
  // and the FP32, INT32 and SFU placements an FP64 datapath 
  if (EnableFp64 || !COMPACT || !FixedScalarAlign || FpFormat != fpnew_pkg::FP64 || NumPipeRegs != 0 || PipeConfig != fpnew_pkg::DISTRIBUTED) begin : gen_config_check
    $fatal(1, "ucc_fma: FpFormat must be FP64, NumPipeRegs 0 and PipeConfig DISTRIBUTED");
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
    unit_d = ucc_pkg::unit_of(ucc_op_i);
    if (!EnableFp64 && ((ucc_op_i[6:5] == 2'b10 && unit_d != ucc_pkg::UNIT_DPA) ||
                       ucc_op_i == 7'h72)) unit_d = ucc_pkg::UNIT_NONE;
    if (dpa_mode_i) unit_d = ucc_pkg::UNIT_DPA;
    else if (unit_d == ucc_pkg::UNIT_DPA) unit_d = ucc_pkg::UNIT_NONE;
    fp32_i       = (unit_d == ucc_pkg::UNIT_FMA) & (ucc_op_i[5] | !EnableFp64);
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
    mul_a_d = (fp32_i || !EnableFp64) ? PRECISION_BITS'(a32) : a64;
    mul_b_d = (fp32_i || !EnableFp64) ? PRECISION_BITS'(b32) : b64;
    // INT32 multiplies: the integers at bits 52-21, their sign bits at bit 52 
    if (unit_d == ucc_pkg::UNIT_IMUL) begin
      mul_a_d = PRECISION_BITS'(operands_i[0][31:0]) << INT_SHIFT;
      mul_b_d = PRECISION_BITS'(operands_i[1][31:0]) << INT_SHIFT;
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
  logic [99:0] common_aligned;
  logic [23:0] sfu_range_operand;
  logic [6:0] sfu_range_shamt;
  logic [17:0] sfu_square_operand, sfu_square;
  ucc_sfu i_sfu (
    .square_operand_o (sfu_square_operand),
    .square_i (sfu_square),
    .range_i (common_aligned[60:22]),
    .range_operand_o (sfu_range_operand),
    .range_shamt_o (sfu_range_shamt),
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
  assign sfu_tag_q = {2{tag_i}};
  assign sfu_mask_q = {2{mask_i}};
  assign sfu_aux_q = {2{aux_i}};
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
  assign inp_pipe_dpa_q[0] = dpa_mode_i;
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
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      inp_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      inp_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (inp_pipe_ready[i]) ? (inp_pipe_valid_q[i]) : (inp_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (inp_pipe_ready[i] & inp_pipe_valid_q[i]) | reg_ena_i[i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_operands_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_operands_q[i+1] <= (reg_ena) ? (inp_pipe_operands_q[i]) : (inp_pipe_operands_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_is_boxed_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_is_boxed_q[i+1] <= (reg_ena) ? (inp_pipe_is_boxed_q[i]) : (inp_pipe_is_boxed_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_rnd_mode_q[i+1] <= (fpnew_pkg::RNE);                        
    end else begin                                   
      inp_pipe_rnd_mode_q[i+1] <= (reg_ena) ? (inp_pipe_rnd_mode_q[i]) : (inp_pipe_rnd_mode_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_op_q[i+1] <= (fpnew_pkg::FMADD);                        
    end else begin                                   
      inp_pipe_op_q[i+1] <= (reg_ena) ? (inp_pipe_op_q[i]) : (inp_pipe_op_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_op_mod_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_op_mod_q[i+1] <= (reg_ena) ? (inp_pipe_op_mod_q[i]) : (inp_pipe_op_mod_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_fp32_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_fp32_q[i+1] <= (reg_ena) ? (inp_pipe_fp32_q[i]) : (inp_pipe_fp32_q[i+1]);               
    end                                              
  end
    // Load with an operation that uses the product only, so that the tiles do not toggle under the others 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_mul_a_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_mul_a_q[i+1] <= (reg_ena & inp_pipe_prod_q[i]) ? (inp_pipe_mul_a_q[i]) : (inp_pipe_mul_a_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_mul_b_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_mul_b_q[i+1] <= (reg_ena & inp_pipe_prod_q[i]) ? (inp_pipe_mul_b_q[i]) : (inp_pipe_mul_b_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_prod_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_prod_q[i+1] <= (reg_ena) ? (inp_pipe_prod_q[i]) : (inp_pipe_prod_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_sfu_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_sfu_q[i+1] <= (reg_ena) ? (inp_pipe_sfu_q[i]) : (inp_pipe_sfu_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_dpa_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_dpa_q[i+1] <= (reg_ena) ? (inp_pipe_dpa_q[i]) : (inp_pipe_dpa_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_sfu_special_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_sfu_special_q[i+1] <= (reg_ena) ? (inp_pipe_sfu_special_q[i]) : (inp_pipe_sfu_special_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_sfu_zero_sign_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_sfu_zero_sign_q[i+1] <= (reg_ena) ? (inp_pipe_sfu_zero_sign_q[i]) : (inp_pipe_sfu_zero_sign_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_sfu_result_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_sfu_result_q[i+1] <= (reg_ena) ? (inp_pipe_sfu_result_q[i]) : (inp_pipe_sfu_result_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_int_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_int_q[i+1] <= (reg_ena) ? (inp_pipe_int_q[i]) : (inp_pipe_int_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_int_op_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_int_op_q[i+1] <= (reg_ena) ? (inp_pipe_int_op_q[i]) : (inp_pipe_int_op_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_ucc_op_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_ucc_op_q[i+1] <= (reg_ena) ? (inp_pipe_ucc_op_q[i]) : (inp_pipe_ucc_op_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_unit_q[i+1] <= (ucc_pkg::UNIT_NONE);                        
    end else begin                                   
      inp_pipe_unit_q[i+1] <= (reg_ena) ? (inp_pipe_unit_q[i]) : (inp_pipe_unit_q[i+1]);               
    end                                              
  end
    // Load with a DPA-16 operation only: nothing else reads them 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_dpa_fmt_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_dpa_fmt_q[i+1] <= (reg_ena & inp_pipe_dpa_q[i]) ? (inp_pipe_dpa_fmt_q[i]) : (inp_pipe_dpa_fmt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_dpa_mx8_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_dpa_mx8_q[i+1] <= (reg_ena & inp_pipe_dpa_q[i]) ? (inp_pipe_dpa_mx8_q[i]) : (inp_pipe_dpa_mx8_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_dpa_hi_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_dpa_hi_q[i+1] <= (reg_ena & inp_pipe_dpa_q[i]) ? (inp_pipe_dpa_hi_q[i]) : (inp_pipe_dpa_hi_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      inp_pipe_tag_q[i+1] <= (reg_ena) ? (inp_pipe_tag_q[i]) : (inp_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      inp_pipe_mask_q[i+1] <= (reg_ena) ? (inp_pipe_mask_q[i]) : (inp_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      inp_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      inp_pipe_aux_q[i+1] <= (reg_ena) ? (inp_pipe_aux_q[i]) : (inp_pipe_aux_q[i+1]);               
    end                                              
  end
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
  if (EnableFp64 || !FixedScalarAlign) begin : gen_full_ctrl
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
  end else begin : gen_fixed_ctrl
    assign ctrl_mantissa_c = {1'b0, operands_q[2][MAN_BITS-1:0]};
    assign effective_subtraction = sfu && (operands_q[0][63] ^ operands_q[2][63]);
    assign tentative_sign = sfu && operands_q[0][63];
    assign use_lzc = 1'b1;
    assign exponent = sfu ? $signed({2'b00, operands_q[0][62:52]}) : EXP_WIDTH'(BIAS);
    assign addend_shamt = sfu ? SHIFT_AMOUNT_WIDTH'(62)
                             : SHIFT_AMOUNT_WIDTH'(3*PRECISION_BITS+4 - PRECISION_BITS - INT_LSB -
                                 ((int_op[4:3] == ucc_pkg::INT_HI) ? 32 : 0));
    assign result_is_special = 1'b0;
    assign special_result = '0;
    assign special_status = '0;
  end
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
  assign fp32_operands[0] = {fma_operands[0][ucc_pkg::WIDTH-1:ucc_pkg::MAN_BITS],
                             mul_a_d[ucc_pkg::MAN_BITS-1:0]};
  assign fp32_operands[1] = {fma_operands[1][ucc_pkg::WIDTH-1:ucc_pkg::MAN_BITS],
                             mul_b_d[ucc_pkg::MAN_BITS-1:0]};
  assign fp32_operands[2] = fma_operands[2][ucc_pkg::WIDTH-1:0];
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
  logic [PRODUCT_REG_WIDTH-1:0] product; 
  logic [15:0][15:0]           dpa_ta, dpa_tb;
  logic                        dpa_full, dpa_fp8, dpa_fp4;
  logic [15:0][23:0]           tile_prod;
  logic [15:0][3:0][7:0]       tile_dprod;
  initial if (NUM_INP_REGS != 0) $fatal(1, "Early tile routing requires zero input stages");
  ucc_tiles i_tiles (
    .sfu_a_i (sfu_mul_a),
    .sfu_b_i (sfu_mul_b),
    .square_operand_i (sfu_square_operand),
    .square_o (sfu_square),
    .dpa_i      ( inp_pipe_dpa_q[NUM_INP_REGS]     ),
    .dpa_ta_i   ( dpa_ta                           ),
    .dpa_tb_i   ( dpa_tb                           ),
    .dpa_full_i ( dpa_full                         ),
    .dpa_fp8_i  ( dpa_fp8                          ),
    .dpa_fp4_i  ( dpa_fp4                          ),
    .a_i        ( mul_a_d ),
    .b_i        ( mul_b_d ),
    .sfu_i      ( sfu                              ),
    .prod_o     ( tile_prod                        ),
    .dprod_o    ( tile_dprod                       )
  );
  logic [12:0][63:0] scalar_rows;
  logic [63:0] scalar_sum, scalar_carry;
  ucc_tilemul #(.PackedIntLow(!EnableFp64 && PackedIntLow)) i_mul (
    .rows_o(scalar_rows), .sum_i(scalar_sum), .carry_i(scalar_carry),
    .sfu_a_i (sfu_mul_a),
    .sfu_b_i (sfu_mul_b),
    .tile_p_i   ( tile_prod                         ),
    .a_i        ( mul_a_d ),
    .b_i        ( mul_b_d ),
    .sfu_i      ( sfu                               ),
    .a_signed_i ( int_mode & int_op[5] & int_op[0]  ),
    .b_signed_i ( int_mode & int_op[5] & int_op[1]  ),
    .p_o        ( product                           )
  );
  // INT32 ALU, from the operand register's bits 31-0 
  logic [ACC_WIDTH:0] sum_raw;
  logic cvt_active, cvt_i2f, cvt_f2i;
  logic [31:0] cvt_add_a, cvt_value, int_shift_data, fp32_result;
  logic cvt_add_carry;
  logic [23:0] cvt_align_mant;
  logic [6:0] cvt_align_shamt;
  logic [5:0] shared_lzc;
  logic [77:0] sum_shifted, sum_normalized;
  ucc_pkg::round_t cvt_round;
  fpnew_pkg::status_t fp32_status;
  assign cvt_active = unit_q == ucc_pkg::UNIT_CVT;
  assign cvt_i2f = cvt_active && (ucc_op_q[4:0] == ucc_pkg::FP_CVT_S32 || ucc_op_q[4:0] == ucc_pkg::FP_CVT_U32);
  assign cvt_f2i = cvt_active && !cvt_i2f;
  logic [31:0] int_alu_result, int_add_a, int_add_b;
  logic int_add_carry, int_add_active;
  assign int_add_active = (unit_q == ucc_pkg::UNIT_ALU);
  ucc_int_alu i_int_alu (
    .shifted_i (common_aligned[99:68]),
    .shift_data_o (int_shift_data),
    .sum_i (sum_raw[32:0]),
    .add_a_o (int_add_a),
    .add_b_o (int_add_b),
    .carry_o (int_add_carry),
    .a_i  ( operands_i[0][31:0] ),
    .b_i  ( operands_i[1][31:0] ),
    .op_i ( int_op[4:0]                                ),
    .y_o  ( int_alu_result                             )
  );
  // FP min, max, neg, abs and compares and conversions, from the registered operands a and b, with FPnew's flags 
  logic [WIDTH-1:0]   noncomp_result, cast_result;
  fpnew_pkg::status_t noncomp_status, cast_status;
  ucc_fp_noncomp #(.EnableFp64(EnableFp64)) i_fp_noncomp (
    .clk_i,
    .rst_ni,
    .a_i      ( operands_i[0] ),
    .b_i      ( operands_i[1] ),
    .fp32_i   ( ucc_op_q[5] | !EnableFp64            ),
    .func_i   ( ucc_op_q[4:0]                        ),
    .result_o ( noncomp_result                       ),
    .status_o ( noncomp_status                       )
  );
  ucc_convert_shared i_fp_cast (
    .a_i (operands_i[0][31:0]),
    .func_i (ucc_op_q[4:0]),
    .rnd_mode_i (inp_pipe_rnd_mode_q[NUM_INP_REGS]),
    .sum_i (sum_raw[31:0]),
    .aligned_i (common_aligned),
    .lzc_i (shared_lzc),
    .normalized_i (sum_shifted),
    .rounded_i (fp32_result),
    .rounded_status_i (fp32_status),
    .add_a_o (cvt_add_a),
    .add_carry_o (cvt_add_carry),
    .align_mant_o (cvt_align_mant),
    .align_shamt_o (cvt_align_shamt),
    .value_o (cvt_value),
    .round_o (cvt_round),
    .result_o (cast_result),
    .status_o (cast_status)
  );
  // DPA-16, from the registered operands: bits 63-0 of a and b and c's bits 31-0 in the operand register, the rest of 
  // a and b in their own. Its result leaves the core's output register three cycles later (dpa_valid_q[2]), and each 
  // of the core's stage registers loads only with the operation in it. 
  logic [dpa16_pkg::SUMW-1:0] dpa_csa_sum, dpa_csa_carry;
  logic signed [dpa16_pkg::SUMW-1:0] dpa_norm_sum;
  logic signed [dpa16_pkg::AW-1:0] dpa_norm_emax;
  logic dpa_norm_zero, dpa_norm_special;
  logic [dpa16_pkg::SUMW-2:0] dpa_magnitude;
  logic dpa_sign, dpa_zero, dpa_overflow, dpa_special;
  logic [31:0] dpa_special_result;
  logic [5:0] dpa_lzc, dpa_shamt;
  logic signed [dpa16_pkg::AW:0] dpa_norm_exp, dpa_sub_shift;
  logic signed [ucc_pkg::EXP_WIDTH-1:0] dpa_packed_exponent;
  logic [77:0] normalization_data;
  localparam int DPA_MAG_WIDTH = dpa16_pkg::SUMW - 1;
  localparam int DPA_NORM_LOW = FRAME - DPA_MAG_WIDTH;
  localparam int DPA_LZ_LOW = ucc_pkg::LOWER_SUM_WIDTH - DPA_MAG_WIDTH;
  logic [31:0] dpa_result;
  logic [2:0]  dpa_rm, dpa_valid_q;
  logic        dpa_in; // a DPA-16 operation in the input register 
  assign dpa_rm = inp_pipe_rnd_mode_q[NUM_INP_REGS];
  assign dpa_in = inp_pipe_valid_q[NUM_INP_REGS] & (unit_q == ucc_pkg::UNIT_DPA);
  ucc_dpa16 i_dpa16 (
    .shared_mode_i(dpa_mode_i), .scalar_rows_i(scalar_rows),
    .scalar_sum_o(scalar_sum), .scalar_carry_o(scalar_carry),
    .clk_i,
    .rst_ni,
    .en_i   ( {dpa_valid_q[1:0], dpa_in}                                                ),
    .fmt_i  ( inp_pipe_dpa_fmt_q[NUM_INP_REGS]                                          ),
    .mx8_i  ( inp_pipe_dpa_mx8_q[NUM_INP_REGS]                                          ),
    .e5m2_i (rnd_mode_i[1:0]),
    .a_i    ({dpa_hi_d[0], operands_i[0]}),
    .b_i    ({dpa_hi_d[1], operands_i[1]}),
    .c_i    (operands_i[2][31:0]),
    .d_o    (  ),
    .csa_sum_o (dpa_csa_sum),
    .csa_carry_o (dpa_csa_carry),
    .norm_sum_o (  ),
    .norm_emax_o (dpa_norm_emax),
    .norm_zero_o (dpa_norm_zero),
    .norm_special_o (dpa_norm_special),
    .ta_o     ( dpa_ta     ),
    .tb_o     ( dpa_tb     ),
    .m_full_o ( dpa_full   ),
    .m_fp8_o  ( dpa_fp8    ),
    .m_fp4_o  ( dpa_fp4    ),
    .tprod_i  ( tile_prod  ),
    .dprod_i  ( tile_dprod )
  );
  // flush_i drops the DPA-16 operations in flight, as it does the other stages' (the core's registers hold data only) 
  assign dpa_valid_q = {3{dpa_in & ~flush_i}};
  // DPA-16's tag, mask and aux, which travel with its result 
  TagType [2:0] dpa_tag_q;
  logic   [2:0] dpa_mask_q;
  AuxType [2:0] dpa_aux_q;
  assign dpa_tag_q = {3{inp_pipe_tag_q[NUM_INP_REGS]}};
  assign dpa_mask_q = {3{inp_pipe_mask_q[NUM_INP_REGS]}};
  assign dpa_aux_q = {3{inp_pipe_aux_q[NUM_INP_REGS]}};
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
  if (EnableFp64 || !FixedScalarAlign) begin : gen_full_align
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
  end else begin : gen_fixed_align
    logic [FRAME+P32-1:0] fp32_aligned;
    ucc_shift #(.WIDTH(FRAME+P32), .SHAMT_WIDTH(ucc_pkg::SHIFT_AMOUNT_WIDTH), .LEFT(1'b0)) i_shift (
      .data_i(int_add_active ? {int_shift_data, 68'd0}
          : {sfu_i ? sfu_range_operand : cvt_f2i ? cvt_align_mant : fp32_mantissa_c, 76'd0}),
      .shamt_i(int_add_active ? {2'd0, operands_i[1][4:0]}
          : sfu_i ? sfu_range_shamt : cvt_f2i ? cvt_align_shamt : fp32_addend_shamt),
      .data_o(fp32_aligned)
    );
    assign common_aligned = fp32_aligned;
    assign addend_aligned = '0;
    assign addend_after_shift = fp32 ? (3*PRECISION_BITS+4)'(fp32_aligned[FRAME+P32-1:P32])
                              : sfu ? ((3*PRECISION_BITS+4)'(mantissa_c) << 20)
                                    : ((3*PRECISION_BITS+4)'(mantissa_c) <<
                                        (INT_LSB + ((int_op[4:3] == ucc_pkg::INT_HI) ? 32 : 0)));
    assign addend_sticky_bits = fp32 ? PRECISION_BITS'(fp32_aligned[P32-1:0]) : '0;
  end
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
  logic [PRODUCT_REG_WIDTH-1:0] product_q;
  logic [ACC_WIDTH-1:0]         addend_after_shift_q;
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
  logic                  [0:NUM_MID_REGS][PRODUCT_REG_WIDTH-1:0] mid_pipe_product_q;
  logic                  [0:NUM_MID_REGS][ACC_WIDTH-1:0]         mid_pipe_addend_q;
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
  assign mid_pipe_product_q[0] = product[PRODUCT_REG_WIDTH-1:0];
  assign mid_pipe_addend_q[0]      = addend_after_shift[ACC_WIDTH-1:0];
  assign mid_pipe_tent_sign_q[0]   = fp32 ? fp32_tentative_sign : tentative_sign;
  assign mid_pipe_rnd_mode_q[0]    = inp_pipe_rnd_mode_q[NUM_INP_REGS];
  // SFU: the front end's special value goes in the low 32 bits of the FP64 special result 
  assign mid_pipe_res_is_spec_q[0] = sfu ? inp_pipe_sfu_special_q[NUM_INP_REGS] : fp32 ? fp32_special : result_is_special;
  // A conversion's result and flags also cross the middle register here 
  assign mid_pipe_spec_res_q[0]    = sfu  ? fp_t'(WIDTH'(inp_pipe_sfu_result_q[NUM_INP_REGS]))
                                   : fp32 ? fp_t'(WIDTH'(fp32_special_result)) : special_result;
  assign mid_pipe_spec_stat_q[0]   = sfu  ? '0 : fp32 ? fp32_special_status : special_status;
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
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      mid_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      mid_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (mid_pipe_ready[i]) ? (mid_pipe_valid_q[i]) : (mid_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (mid_pipe_ready[i] & mid_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_eff_sub_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_eff_sub_q[i+1] <= (reg_ena) ? (mid_pipe_eff_sub_q[i]) : (mid_pipe_eff_sub_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_use_lzc_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_use_lzc_q[i+1] <= (reg_ena) ? (mid_pipe_use_lzc_q[i]) : (mid_pipe_use_lzc_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_exponent_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_exponent_q[i+1] <= (reg_ena) ? (mid_pipe_exponent_q[i]) : (mid_pipe_exponent_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_add_shamt_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_add_shamt_q[i+1] <= (reg_ena) ? (mid_pipe_add_shamt_q[i]) : (mid_pipe_add_shamt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_sticky_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_sticky_q[i+1] <= (reg_ena) ? (mid_pipe_sticky_q[i]) : (mid_pipe_sticky_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_product_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_product_q[i+1] <= (reg_ena) ? (mid_pipe_product_q[i]) : (mid_pipe_product_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_addend_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_addend_q[i+1] <= (reg_ena) ? (mid_pipe_addend_q[i]) : (mid_pipe_addend_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_tent_sign_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_tent_sign_q[i+1] <= (reg_ena) ? (mid_pipe_tent_sign_q[i]) : (mid_pipe_tent_sign_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_rnd_mode_q[i+1] <= (fpnew_pkg::RNE);                        
    end else begin                                   
      mid_pipe_rnd_mode_q[i+1] <= (reg_ena) ? (mid_pipe_rnd_mode_q[i]) : (mid_pipe_rnd_mode_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_res_is_spec_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_res_is_spec_q[i+1] <= (reg_ena) ? (mid_pipe_res_is_spec_q[i]) : (mid_pipe_res_is_spec_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_spec_res_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_spec_res_q[i+1] <= (reg_ena) ? (mid_pipe_spec_res_q[i]) : (mid_pipe_spec_res_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_spec_stat_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_spec_stat_q[i+1] <= (reg_ena) ? (mid_pipe_spec_stat_q[i]) : (mid_pipe_spec_stat_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_fp32_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_fp32_q[i+1] <= (reg_ena) ? (mid_pipe_fp32_q[i]) : (mid_pipe_fp32_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_sfu_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_sfu_q[i+1] <= (reg_ena) ? (mid_pipe_sfu_q[i]) : (mid_pipe_sfu_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_sfu_zero_sign_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_sfu_zero_sign_q[i+1] <= (reg_ena) ? (mid_pipe_sfu_zero_sign_q[i]) : (mid_pipe_sfu_zero_sign_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_int_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_int_q[i+1] <= (reg_ena) ? (mid_pipe_int_q[i]) : (mid_pipe_int_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_int_sel_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_int_sel_q[i+1] <= (reg_ena) ? (mid_pipe_int_sel_q[i]) : (mid_pipe_int_sel_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_cvt_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_cvt_q[i+1] <= (reg_ena) ? (mid_pipe_cvt_q[i]) : (mid_pipe_cvt_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_fma_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_fma_q[i+1] <= (reg_ena) ? (mid_pipe_fma_q[i]) : (mid_pipe_fma_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      mid_pipe_tag_q[i+1] <= (reg_ena) ? (mid_pipe_tag_q[i]) : (mid_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      mid_pipe_mask_q[i+1] <= (reg_ena) ? (mid_pipe_mask_q[i]) : (mid_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      mid_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      mid_pipe_aux_q[i+1] <= (reg_ena) ? (mid_pipe_aux_q[i]) : (mid_pipe_aux_q[i+1]);               
    end                                              
  end
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
  logic [ACC_WIDTH-1:0] product_shifted;
  logic [ACC_WIDTH-1:0] addend_shifted;
  logic                        inject_carry_in;     // inject carry for subtractions if needed 
  always_comb begin : product_placement
    product_shifted = ACC_WIDTH'(product_q) << 2;
    if (sfu_q) product_shifted[ACC_WIDTH-1:PRODUCT_REG_WIDTH+2] = '{default: product_q[PRODUCT_REG_WIDTH-1]};
  end
  // In case of a subtraction, the addend is inverted. FP32 too, across the whole width: above the FP32 frame the 
  // product and the addend are 0, so the carry out of the frame runs to the top, and sum_carry, the sum's selection 
  // and the final sign are those of the frame (fpnew_fma's in FP32), with zeros above it in the sum. 
  assign addend_shifted  = (effective_subtraction_q) ? ~addend_after_shift_q : addend_after_shift_q;
  assign inject_carry_in = effective_subtraction_q & ~sticky_before_add_q;
  // ------ 
  // Adder 
  // ------ 
  logic                        sum_carry; // observe carry bit from raw sum for sign fixing 
  logic [ACC_WIDTH-1:0] sum;       // discard carry as sum won't overflow 
  logic                        final_sign;
  //Mantissa adder (ab+c). In normal addition, it cannot overflow. 
  logic [ACC_WIDTH-1:0] shared_add_a, shared_add_b;
  // Only the low 34 bits need a mode mux; higher bits cannot carry into the DPA result.
  assign shared_add_a = {product_shifted[ACC_WIDTH-1:dpa16_pkg::SUMW],
      dpa_mode_i ? dpa_csa_sum : cvt_active ? {2'b0, cvt_add_a} : int_add_active ? {2'b0, int_add_a} : product_shifted[dpa16_pkg::SUMW-1:0]};
  assign shared_add_b = {addend_shifted[ACC_WIDTH-1:dpa16_pkg::SUMW],
      dpa_mode_i ? dpa_csa_carry : cvt_active ? 34'd0 : int_add_active ? {2'b0, int_add_b} : addend_shifted[dpa16_pkg::SUMW-1:0]};
  wire shared_carry = (!dpa_mode_i & (cvt_active ? cvt_add_carry : int_add_active ? int_add_carry : inject_carry_in));
  assign dpa_norm_sum = $signed(sum_raw[dpa16_pkg::SUMW-1:0]);
  assign sum_carry = sum_raw[ACC_WIDTH];
  // Complement negative sum (can only happen in subtraction -> overflows for positive results). 
  // Note: inject_carry_in is used to complete the negation of the addend in the raw sum but for the negative sum the 
  // addend is not negated, so no carry needs to be injected. 
  logic [ACC_WIDTH:0] sum_neg;
  initial if (ACC_WIDTH != 78 || DPA_MAG_WIDTH != 33)
    $fatal(1, "Factored sum requires the compact FP32/DPA frame");
  ucc_factored_sum i_factored_sum (
    .a_i(shared_add_a), .b_i(shared_add_b), .carry_i(shared_carry), .dpa_i(dpa_mode_i),
    .sum_o(sum_raw), .negative_o(sum_neg)
  );
  assign sum = ACC_WIDTH'((effective_subtraction_q && ~sum_carry)
                    ? sum_neg[ACC_WIDTH-1:0] : sum_raw[ACC_WIDTH-1:0]);
  // In case of a mispredicted subtraction result, do a sign flip 
  assign final_sign = (effective_subtraction_q && (sum_carry == tentative_sign_q))
                      ? 1'b1
                      : (effective_subtraction_q ? 1'b0 : tentative_sign_q);
  // All three modes place the normalized leading bit at bit 75.
  logic [63:0] lzc_data;
  logic sum_zero;
  logic [ucc_pkg::SHIFT_AMOUNT_WIDTH-1:0] fp32_norm_shamt;
  logic signed [ucc_pkg::EXP_WIDTH-1:0] fp32_normalized_exponent, fp32_final_exponent;
  logic [6:0] compact_norm_shamt;
  logic signed [EXP_WIDTH-1:0] sfu_compact_exponent;

  assign dpa_sign = dpa_norm_sum[dpa16_pkg::SUMW-1];
  assign dpa_magnitude = dpa_sign ? sum_neg[DPA_MAG_WIDTH-1:0] : dpa_norm_sum[DPA_MAG_WIDTH-1:0];
  assign normalization_data = cvt_i2f ? {2'd0, sum_raw[31:0], 44'd0} : dpa_mode_i ? 78'({dpa_magnitude, {DPA_NORM_LOW{1'b0}}}) : sum;
  assign lzc_data = cvt_i2f ? {sum_raw[31:0], 32'd0} : dpa_mode_i ? {dpa_magnitude, 31'd0}
                 : sfu_q ? sum[63:0] : {sum[ucc_pkg::LOWER_SUM_WIDTH-1:0], 13'd0};
  assign dpa_lzc = shared_lzc;
  assign dpa_norm_exp = 13'(dpa_norm_emax) + 13'sd134 - $signed({7'd0, dpa_lzc});
  assign dpa_sub_shift = 13'(dpa_norm_emax) + 13'sd133;
  assign dpa_shamt = (dpa_norm_exp >= 13'sd1) ? dpa_lzc : dpa_sub_shift[5:0];
  assign dpa_packed_exponent = (dpa_norm_exp >= 13'sd1) ? ucc_pkg::EXP_WIDTH'(dpa_norm_exp) : '0;
  assign dpa_zero = dpa_norm_zero || (dpa_magnitude == '0) || (dpa_norm_emax < -12'sd133);
  assign dpa_overflow = (dpa_norm_emax > 12'sd152);
  assign dpa_special = dpa_norm_special || dpa_zero || dpa_overflow;
  assign dpa_special_result = dpa_norm_special ? dpa16_pkg::QNAN
      : dpa_zero ? 32'd0 : {dpa_sign, 8'hff, 23'd0};

  ucc_fp32_norm #(.LOWER_SUM_WIDTH(64)) i_norm32 (
    .sum_lower_i (lzc_data),
    .use_lzc_i (use_lzc_q),
    .exponent_i (exponent_q[ucc_pkg::EXP_WIDTH-1:0]),
    .addend_shamt_i (addend_shamt_q[ucc_pkg::SHIFT_AMOUNT_WIDTH-1:0]),
    .norm_shamt_o (fp32_norm_shamt),
    .normalized_exponent_o (fp32_normalized_exponent),
    .leading_zero_count_o (shared_lzc),
    .zero_o (sum_zero)
  );
  // Removing 28 low zero bits changes the SFU scale; 911 includes its old bias conversion.
  assign sfu_compact_exponent = exponent_q - 13'sd911 - $signed({7'd0, shared_lzc});
  assign compact_norm_shamt = cvt_i2f ? {1'b0, shared_lzc} : dpa_mode_i ? {1'b0, dpa_shamt}
      : sfu_q ? 7'd12 + {1'b0, shared_lzc} : fp32_norm_shamt;
  ucc_shift #(.WIDTH(78), .SHAMT_WIDTH(7), .LEFT(1'b1)) i_norm_shift (
    .data_i (normalization_data),
    .shamt_i (compact_norm_shamt),
    .data_o (sum_shifted)
  );
  typedef enum logic [1:0] {NORM_KEEP, NORM_RIGHT, NORM_LEFT} norm_dir_e;
  norm_dir_e fp32_norm_dir;
  always_comb begin
    fp32_norm_dir = NORM_KEEP;
    fp32_final_exponent = fp32_normalized_exponent;
    if (sum_shifted[FRAME]) begin
      fp32_norm_dir = NORM_RIGHT;
      fp32_final_exponent = fp32_normalized_exponent + 1;
    end else if (sum_shifted[FRAME-1]) begin
    end else if (fp32_normalized_exponent > 1) begin
      fp32_norm_dir = NORM_LEFT;
      fp32_final_exponent = fp32_normalized_exponent - 1;
    end else begin
      fp32_final_exponent = '0;
    end
  end
  always_comb begin
    unique case ((dpa_mode_i || sfu_q) ? NORM_KEEP : fp32_norm_dir)
      NORM_RIGHT: sum_normalized = {1'b0, sum_shifted[77:1]};
      NORM_LEFT: sum_normalized = {sum_shifted[76:0], 1'b0};
      default: sum_normalized = sum_shifted;
    endcase
  end
  logic [ucc_pkg::WIDTH-1:0] fp32_value;
  ucc_pkg::round_t fp32_round;
  ucc_fp32_preround i_preround32 (
    .final_mantissa_i (sum_normalized[ucc_pkg::LOWER_SUM_WIDTH +: P32+1]),
    .sum_sticky_bits_i (sum_normalized[ucc_pkg::LOWER_SUM_WIDTH-1:0]),
    .sticky_before_add_i (!dpa_mode_i & sticky_before_add_q),
    .final_exponent_i (dpa_mode_i ? dpa_packed_exponent : fp32_final_exponent),
    .final_sign_i (dpa_mode_i ? dpa_sign : final_sign),
    .effective_subtraction_i (!dpa_mode_i & effective_subtraction_q),
    .result_is_special_i (dpa_mode_i ? dpa_special : result_is_special_q),
    .special_result_i (dpa_mode_i ? dpa_special_result : special_result_q[ucc_pkg::WIDTH-1:0]),
    .special_status_i (dpa_mode_i ? '0 : special_status_q),
    .value_o (fp32_value),
    .round_o (fp32_round)
  );
  logic [WIDTH-1:0] fp64_value;
  ucc_pkg::round_t fp64_round;
  assign fp64_value = '0;
  assign fp64_round = '{special: result_is_special_q, default: '0};
  localparam int unsigned SFU_PRE = 5 + EXP_WIDTH + ucc_pkg::PRECISION_BITS;
  logic [SFU_PRE-1:0] sfu_pre;
  assign sfu_pre = {mid_pipe_sfu_zero_sign_q[NUM_MID_REGS], sum_zero, final_sign,
      sfu_compact_exponent, sum_normalized[51], (|sum_normalized[50:0]), sum_normalized[75:52]};
  // The output register's value: FP32 its value before rounding in the low 32 bits, SFU its fields (or its special 
  // value NaN-boxed), FP64 the value before rounding (or the special result); and what the rounding needs 
  fp_t             value_d;
  ucc_pkg::round_t round_d;
  assign value_d = (fp32_q | dpa_mode_i) ? fp_t'(WIDTH'(fp32_value))
                 : sfu_q  ? fp_t'(result_is_special_q ? {32'hffff_ffff, special_result_q[31:0]} : WIDTH'(sfu_pre))
                          : fp_t'(fp64_value);
  assign round_d = (fp32_q | dpa_mode_i) ? fp32_round : fp64_round;
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
      int_result = cast_result;
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
  always_ff @(posedge (clk_i) or negedge (rst_ni)) begin                 
    if (!rst_ni) begin                                                   
      out_pipe_valid_q[i+1] <= (1'b0);                                              
    end else begin                                                         
      out_pipe_valid_q[i+1] <= (flush_i) ? (1'b0) : (out_pipe_ready[i]) ? (out_pipe_valid_q[i]) : (out_pipe_valid_q[i+1]);       
    end                                                                    
  end
    // Enable register if pipleine ready and a valid data item is present 
    assign reg_ena = (out_pipe_ready[i] & out_pipe_valid_q[i]) | reg_ena_i[NUM_INP_REGS + NUM_MID_REGS + i];
    // Generate the pipeline registers within the stages, use enable-registers 
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_result_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_result_q[i+1] <= (reg_ena) ? (out_pipe_result_q[i]) : (out_pipe_result_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_round_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_round_q[i+1] <= (reg_ena) ? (out_pipe_round_q[i]) : (out_pipe_round_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_rnd_mode_q[i+1] <= (fpnew_pkg::RNE);                        
    end else begin                                   
      out_pipe_rnd_mode_q[i+1] <= (reg_ena) ? (out_pipe_rnd_mode_q[i]) : (out_pipe_rnd_mode_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_fp32_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_fp32_q[i+1] <= (reg_ena) ? (out_pipe_fp32_q[i]) : (out_pipe_fp32_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_tag_q[i+1] <= (TagType'('0));                        
    end else begin                                   
      out_pipe_tag_q[i+1] <= (reg_ena) ? (out_pipe_tag_q[i]) : (out_pipe_tag_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_mask_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_mask_q[i+1] <= (reg_ena) ? (out_pipe_mask_q[i]) : (out_pipe_mask_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_aux_q[i+1] <= (AuxType'('0));                        
    end else begin                                   
      out_pipe_aux_q[i+1] <= (reg_ena) ? (out_pipe_aux_q[i]) : (out_pipe_aux_q[i+1]);               
    end                                              
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin 
    if (!rst_ni) begin                               
      out_pipe_sfu_q[i+1] <= ('0);                        
    end else begin                                   
      out_pipe_sfu_q[i+1] <= (reg_ena) ? (out_pipe_sfu_q[i]) : (out_pipe_sfu_q[i+1]);               
    end                                              
  end
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
  if (EnableFp64) begin : gen_fp64_round
  ucc_fp32_round #(
    .FpFormat ( FpFormat )
  ) i_round (
    .value_i    ( value_q      ),
    .round_i    ( round_q      ),
    .rnd_mode_i ( out_rnd_mode ),
    .result_o   ( fp64_result  ),
    .status_o   ( fp64_status  )
  );
  end else begin : gen_no_fp64_round
    assign fp64_result = '0;
    assign fp64_status = '0;
  end
  // FP32's rounding, of the value's low 32 bits 
  ucc_fp32_round i_round32 (
    .value_i    ( cvt_i2f ? cvt_value : value_q[ucc_pkg::WIDTH-1:0] ),
    .round_i    ( cvt_i2f ? cvt_round : round_q                     ),
    .rnd_mode_i ( dpa_mode_i ? fpnew_pkg::RNE : out_rnd_mode ),
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
  assign dpa_result = fp32_result;
  assign fma_result = out_fp32 ? fp_t'({32'hffff_ffff, fp32_result})
                    : out_sfu  ? fp_t'({32'hffff_ffff, round_q.special ? value_q[31:0] : sfu_result})
                               : fp_t'(EnableFp64 ? fp64_result : '0);
  assign fma_status = out_fp32 ? fp32_status
                    : out_sfu  ? '0
                               : (EnableFp64 ? fp64_status : '0);
  // Output stage: assign module outputs (the bypassed results, the youngest operation's first, then the output 
  // register's FMA result, DPA-16's, the output register's SFU result) 
  logic out_valid, out_fma, dpa_out;
  assign out_valid       = out_pipe_valid_q[NUM_OUT_REGS];
  assign out_fma         = out_valid & (unit_q == ucc_pkg::UNIT_FMA) & ~out_pipe_sfu_q[NUM_OUT_REGS];
  assign dpa_out         = dpa_valid_q[2] & ~out_fma;
  assign result_o        = alu_bypass ? fp_t'(alu_result)
                         : int_bypass ? fp_t'(int_result)
                         : dpa_out    ? fp_t'({32'hffff_ffff, dpa_result}) : fma_result;
  // Flags: the compare unit's and the conversions' (FPnew's), the FMA path's; none from the ALU, the multiplies, 
  // DPA-16 or the SFU 
  assign status_o        = alu_bypass ? ((unit_q == ucc_pkg::UNIT_CMP) ? noncomp_status : '0)
                         : int_bypass ? (mid_pipe_cvt_q[NUM_MID_REGS] ? cast_status : '0)
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
endmodule
// s2chitni & Claude (AI-generated) 
// The UCC FU: ucc_fma with three distributed pipeline registers (inputs, after the addition, output), taking one 
// operation per cycle. valid_i issues op_i, the global opcode (ucc_pkg's map: INT32 0x00-0x3F, FP64 0x40-0x5F, FP32 
// 0x60-0x7F); rm_i is the rounding mode of the operations that round (FPnew's encoding: RNE 0, RTZ 1, RDN 2, RUP 3, 
// RMM 4; 5-7 round to nearest even). A cycle with valid_i clear issues nothing and returns nothing. Every operation 
// is one operation: FP32 and INT32 ones read bits 31-0 of their operands, FP32 results are NaN-boxed, and INT32 
// results and compares are zero-extended. Status flags, the handshake and flush are unconnected. The pipeline, c_i and d_o are those 
// of TransDot's fp64_fma_lane, the baseline; a_i and b_i are wider (DPA-16's vectors), and sa_i, sb_i, valid_i, op_i 
// and rm_i are the FU's own. 
// The result comes on d_o, after issue: 
// - 1 cycle: INT32 ALU operations, FP min, max, neg, abs and compares, and codes the map does not name (0); 
// - 2: INT32 multiplies and FP conversions; 
// - 3: FP FMA, ADD, SUB and MUL (FP64 or FP32); 
// - 4: DPA-16, TransDot's dpa16_core (one per cycle in every format, 16 products in FP16 and BF16); 
// - 5: the SFU's functions; 
// When two results are due in the same cycle, the younger operation's is returned. An SFU function takes the input 
// register two cycles after its issue, so an operation other than an SFU function issued then is dropped (ucc_fma 
// clears in_ready_o for it; this lane has no ready port, as the baseline has none). Defining UCC_CHECK_ISSUE makes 
// either case a simulation error, for an issuer that promises to avoid both. 
// a_i and b_i are DPA-16's 256-bit vectors and sa_i and sb_i their four 8-bit block scales, which only NVFP4, MXFP4 
// and MXFP8 read; every other operation reads bits 63-0 of a_i and b_i, which share the FU's operand register with 
// DPA-16's. 
module ucc_lane #(
  parameter bit EnableFp64 = 1'b0,
  parameter bit PackedIntLow = 1'b1,
  parameter bit CompactAccumulator = 1'b1,
  parameter bit FixedScalarAlign = 1'b1
) (
  input  logic [ucc_pkg::DPA_VECTOR-1:0] a_i,
  input  logic [ucc_pkg::DPA_VECTOR-1:0] b_i,
  input  logic [ucc_pkg::DPA_SCALES-1:0] sa_i,
  input  logic [ucc_pkg::DPA_SCALES-1:0] sb_i,
  input  logic [63:0]                    c_i,
  input  logic        valid_i,
  input  logic dpa_mode_i,
  input  logic [6:0]  op_i,
  input  logic [2:0]  rm_i,
  output logic [63:0] d_o
);
  fpnew_pkg::status_t st;
  logic ext, tag, mask, aux, ovalid, iready, busy;
  ucc_fma #(
    .EnableFp64  (EnableFp64),
    .PackedIntLow (PackedIntLow),
    .CompactAccumulator (CompactAccumulator),
    .FixedScalarAlign (FixedScalarAlign),
    .FpFormat    (fpnew_pkg::FP64),
    .NumPipeRegs (0),
    .PipeConfig  (fpnew_pkg::DISTRIBUTED)
  ) u_fma (
    .clk_i(1'b0), .rst_ni(1'b1),
    .operands_i      ({c_i, b_i[63:0], a_i[63:0]}),
    .dpa_hi_i        ({sb_i, b_i[ucc_pkg::DPA_VECTOR-1:64], sa_i, a_i[ucc_pkg::DPA_VECTOR-1:64]}),
    .is_boxed_i      (3'b111),
    .rnd_mode_i      (fpnew_pkg::roundmode_e'(rm_i)),
    .ucc_op_i        (op_i),
    .dpa_mode_i,
    .tag_i           (1'b0),
    .mask_i          (1'b1),
    .aux_i           (1'b0),
    .in_valid_i      (valid_i),
    .in_ready_o      (iready),
    .flush_i         (1'b0),
    .result_o        (d_o),
    .status_o        (st),
    .extension_bit_o (ext),
    .tag_o           (tag),
    .mask_o          (mask),
    .aux_o           (aux),
    .out_valid_o     (ovalid),
    .out_ready_i     (1'b1),
    .busy_o          (busy),
    .reg_ena_i       ('0)
  );
endmodule

module ucc_factored_sum (
  input logic [77:0] a_i, b_i,
  input logic carry_i, dpa_i,
  output logic [78:0] sum_o, negative_o
);
  wire [78:0] base_sum = {1'b0, a_i} + {1'b0, b_i};
  wire [32:0] dpa_magnitude = ~base_sum[32:0] + 33'd1;
  assign sum_o = base_sum + carry_i;
  // DPA consumes only the low 33 reverse-sum bits.
  assign negative_o = {~base_sum[78:33], dpa_i ? dpa_magnitude : ~base_sum[32:0]};
endmodule


module ucc_shared_heap (
  input logic dpa_i,
  input logic [32:0][26:0] dpa_terms_i,
  input logic [5:0] negative_count_i,
  input logic [12:0][63:0] scalar_rows_i,
  output logic [63:0] sum_o, carry_o
);
  wire [6:0] negative_mod = 7'd0 - {1'b0, negative_count_i};
  wire [1:0] dpa_0_0_0;
  assign dpa_0_0_0 = {1'b0, dpa_terms_i[0][0]} + {1'b0, dpa_terms_i[1][0]} + {1'b0, dpa_terms_i[2][0]};
  wire [1:0] dpa_0_0_1;
  assign dpa_0_0_1 = {1'b0, dpa_terms_i[3][0]} + {1'b0, dpa_terms_i[4][0]} + {1'b0, dpa_terms_i[5][0]};
  wire [1:0] dpa_0_0_2;
  assign dpa_0_0_2 = {1'b0, dpa_terms_i[6][0]} + {1'b0, dpa_terms_i[7][0]} + {1'b0, dpa_terms_i[8][0]};
  wire [1:0] dpa_0_1_0;
  assign dpa_0_1_0 = {1'b0, dpa_terms_i[0][1]} + {1'b0, dpa_terms_i[1][1]} + {1'b0, dpa_terms_i[2][1]};
  wire [1:0] dpa_0_1_1;
  assign dpa_0_1_1 = {1'b0, dpa_terms_i[3][1]} + {1'b0, dpa_terms_i[4][1]} + {1'b0, dpa_terms_i[5][1]};
  wire [1:0] dpa_0_1_2;
  assign dpa_0_1_2 = {1'b0, dpa_terms_i[6][1]} + {1'b0, dpa_terms_i[7][1]} + {1'b0, dpa_terms_i[8][1]};
  wire [1:0] dpa_0_1_3;
  assign dpa_0_1_3 = {1'b0, dpa_terms_i[9][1]} + {1'b0, dpa_terms_i[10][1]} + {1'b0, dpa_terms_i[11][1]};
  wire [1:0] dpa_0_1_4;
  assign dpa_0_1_4 = {1'b0, dpa_terms_i[12][1]} + {1'b0, dpa_terms_i[13][1]};
  wire [1:0] dpa_0_2_0;
  assign dpa_0_2_0 = {1'b0, dpa_terms_i[0][2]} + {1'b0, dpa_terms_i[1][2]} + {1'b0, dpa_terms_i[2][2]};
  wire [1:0] dpa_0_2_1;
  assign dpa_0_2_1 = {1'b0, dpa_terms_i[3][2]} + {1'b0, dpa_terms_i[4][2]} + {1'b0, dpa_terms_i[5][2]};
  wire [1:0] dpa_0_2_2;
  assign dpa_0_2_2 = {1'b0, dpa_terms_i[6][2]} + {1'b0, dpa_terms_i[7][2]} + {1'b0, dpa_terms_i[8][2]};
  wire [1:0] dpa_0_2_3;
  assign dpa_0_2_3 = {1'b0, dpa_terms_i[9][2]} + {1'b0, dpa_terms_i[10][2]} + {1'b0, dpa_terms_i[11][2]};
  wire [1:0] dpa_0_2_4;
  assign dpa_0_2_4 = {1'b0, dpa_terms_i[12][2]} + {1'b0, dpa_terms_i[13][2]} + {1'b0, dpa_terms_i[14][2]};
  wire [1:0] dpa_0_2_5;
  assign dpa_0_2_5 = {1'b0, dpa_terms_i[15][2]} + {1'b0, dpa_terms_i[16][2]};
  wire [1:0] dpa_0_3_0;
  assign dpa_0_3_0 = {1'b0, dpa_terms_i[0][3]} + {1'b0, dpa_terms_i[1][3]} + {1'b0, dpa_terms_i[2][3]};
  wire [1:0] dpa_0_3_1;
  assign dpa_0_3_1 = {1'b0, dpa_terms_i[3][3]} + {1'b0, dpa_terms_i[4][3]} + {1'b0, dpa_terms_i[5][3]};
  wire [1:0] dpa_0_3_2;
  assign dpa_0_3_2 = {1'b0, dpa_terms_i[6][3]} + {1'b0, dpa_terms_i[7][3]} + {1'b0, dpa_terms_i[8][3]};
  wire [1:0] dpa_0_3_3;
  assign dpa_0_3_3 = {1'b0, dpa_terms_i[9][3]} + {1'b0, dpa_terms_i[10][3]} + {1'b0, dpa_terms_i[11][3]};
  wire [1:0] dpa_0_3_4;
  assign dpa_0_3_4 = {1'b0, dpa_terms_i[12][3]} + {1'b0, dpa_terms_i[13][3]} + {1'b0, dpa_terms_i[14][3]};
  wire [1:0] dpa_0_3_5;
  assign dpa_0_3_5 = {1'b0, dpa_terms_i[15][3]} + {1'b0, dpa_terms_i[16][3]} + {1'b0, dpa_terms_i[17][3]};
  wire [1:0] dpa_0_4_0;
  assign dpa_0_4_0 = {1'b0, dpa_terms_i[0][4]} + {1'b0, dpa_terms_i[1][4]} + {1'b0, dpa_terms_i[2][4]};
  wire [1:0] dpa_0_4_1;
  assign dpa_0_4_1 = {1'b0, dpa_terms_i[3][4]} + {1'b0, dpa_terms_i[4][4]} + {1'b0, dpa_terms_i[5][4]};
  wire [1:0] dpa_0_4_2;
  assign dpa_0_4_2 = {1'b0, dpa_terms_i[6][4]} + {1'b0, dpa_terms_i[7][4]} + {1'b0, dpa_terms_i[8][4]};
  wire [1:0] dpa_0_4_3;
  assign dpa_0_4_3 = {1'b0, dpa_terms_i[9][4]} + {1'b0, dpa_terms_i[10][4]} + {1'b0, dpa_terms_i[11][4]};
  wire [1:0] dpa_0_4_4;
  assign dpa_0_4_4 = {1'b0, dpa_terms_i[12][4]} + {1'b0, dpa_terms_i[13][4]} + {1'b0, dpa_terms_i[14][4]};
  wire [1:0] dpa_0_4_5;
  assign dpa_0_4_5 = {1'b0, dpa_terms_i[15][4]} + {1'b0, dpa_terms_i[16][4]} + {1'b0, dpa_terms_i[17][4]};
  wire [1:0] dpa_0_5_0;
  assign dpa_0_5_0 = {1'b0, dpa_terms_i[0][5]} + {1'b0, dpa_terms_i[1][5]} + {1'b0, dpa_terms_i[2][5]};
  wire [1:0] dpa_0_5_1;
  assign dpa_0_5_1 = {1'b0, dpa_terms_i[3][5]} + {1'b0, dpa_terms_i[4][5]} + {1'b0, dpa_terms_i[5][5]};
  wire [1:0] dpa_0_5_2;
  assign dpa_0_5_2 = {1'b0, dpa_terms_i[6][5]} + {1'b0, dpa_terms_i[7][5]} + {1'b0, dpa_terms_i[8][5]};
  wire [1:0] dpa_0_5_3;
  assign dpa_0_5_3 = {1'b0, dpa_terms_i[9][5]} + {1'b0, dpa_terms_i[10][5]} + {1'b0, dpa_terms_i[11][5]};
  wire [1:0] dpa_0_5_4;
  assign dpa_0_5_4 = {1'b0, dpa_terms_i[12][5]} + {1'b0, dpa_terms_i[13][5]} + {1'b0, dpa_terms_i[14][5]};
  wire [1:0] dpa_0_5_5;
  assign dpa_0_5_5 = {1'b0, dpa_terms_i[15][5]} + {1'b0, dpa_terms_i[16][5]} + {1'b0, dpa_terms_i[17][5]};
  wire [1:0] dpa_0_6_0;
  assign dpa_0_6_0 = {1'b0, dpa_terms_i[0][6]} + {1'b0, dpa_terms_i[1][6]} + {1'b0, dpa_terms_i[2][6]};
  wire [1:0] dpa_0_6_1;
  assign dpa_0_6_1 = {1'b0, dpa_terms_i[3][6]} + {1'b0, dpa_terms_i[4][6]} + {1'b0, dpa_terms_i[5][6]};
  wire [1:0] dpa_0_6_2;
  assign dpa_0_6_2 = {1'b0, dpa_terms_i[6][6]} + {1'b0, dpa_terms_i[7][6]} + {1'b0, dpa_terms_i[8][6]};
  wire [1:0] dpa_0_6_3;
  assign dpa_0_6_3 = {1'b0, dpa_terms_i[9][6]} + {1'b0, dpa_terms_i[10][6]} + {1'b0, dpa_terms_i[11][6]};
  wire [1:0] dpa_0_6_4;
  assign dpa_0_6_4 = {1'b0, dpa_terms_i[12][6]} + {1'b0, dpa_terms_i[13][6]} + {1'b0, dpa_terms_i[14][6]};
  wire [1:0] dpa_0_6_5;
  assign dpa_0_6_5 = {1'b0, dpa_terms_i[15][6]} + {1'b0, dpa_terms_i[16][6]};
  wire [1:0] dpa_0_7_0;
  assign dpa_0_7_0 = {1'b0, dpa_terms_i[0][7]} + {1'b0, dpa_terms_i[1][7]} + {1'b0, dpa_terms_i[2][7]};
  wire [1:0] dpa_0_7_1;
  assign dpa_0_7_1 = {1'b0, dpa_terms_i[3][7]} + {1'b0, dpa_terms_i[4][7]} + {1'b0, dpa_terms_i[5][7]};
  wire [1:0] dpa_0_7_2;
  assign dpa_0_7_2 = {1'b0, dpa_terms_i[6][7]} + {1'b0, dpa_terms_i[7][7]} + {1'b0, dpa_terms_i[8][7]};
  wire [1:0] dpa_0_7_3;
  assign dpa_0_7_3 = {1'b0, dpa_terms_i[9][7]} + {1'b0, dpa_terms_i[10][7]} + {1'b0, dpa_terms_i[11][7]};
  wire [1:0] dpa_0_7_4;
  assign dpa_0_7_4 = {1'b0, dpa_terms_i[12][7]} + {1'b0, dpa_terms_i[13][7]} + {1'b0, dpa_terms_i[14][7]};
  wire [1:0] dpa_0_7_5;
  assign dpa_0_7_5 = {1'b0, dpa_terms_i[15][7]} + {1'b0, dpa_terms_i[16][7]};
  wire [1:0] dpa_0_8_0;
  assign dpa_0_8_0 = {1'b0, dpa_terms_i[0][8]} + {1'b0, dpa_terms_i[1][8]} + {1'b0, dpa_terms_i[2][8]};
  wire [1:0] dpa_0_8_1;
  assign dpa_0_8_1 = {1'b0, dpa_terms_i[3][8]} + {1'b0, dpa_terms_i[4][8]} + {1'b0, dpa_terms_i[5][8]};
  wire [1:0] dpa_0_8_2;
  assign dpa_0_8_2 = {1'b0, dpa_terms_i[6][8]} + {1'b0, dpa_terms_i[7][8]} + {1'b0, dpa_terms_i[8][8]};
  wire [1:0] dpa_0_8_3;
  assign dpa_0_8_3 = {1'b0, dpa_terms_i[9][8]} + {1'b0, dpa_terms_i[10][8]} + {1'b0, dpa_terms_i[11][8]};
  wire [1:0] dpa_0_8_4;
  assign dpa_0_8_4 = {1'b0, dpa_terms_i[12][8]} + {1'b0, dpa_terms_i[13][8]} + {1'b0, dpa_terms_i[14][8]};
  wire [1:0] dpa_0_8_5;
  assign dpa_0_8_5 = {1'b0, dpa_terms_i[15][8]} + {1'b0, dpa_terms_i[16][8]};
  wire [1:0] dpa_0_9_0;
  assign dpa_0_9_0 = {1'b0, dpa_terms_i[0][9]} + {1'b0, dpa_terms_i[1][9]} + {1'b0, dpa_terms_i[2][9]};
  wire [1:0] dpa_0_9_1;
  assign dpa_0_9_1 = {1'b0, dpa_terms_i[3][9]} + {1'b0, dpa_terms_i[4][9]} + {1'b0, dpa_terms_i[5][9]};
  wire [1:0] dpa_0_9_2;
  assign dpa_0_9_2 = {1'b0, dpa_terms_i[6][9]} + {1'b0, dpa_terms_i[7][9]} + {1'b0, dpa_terms_i[8][9]};
  wire [1:0] dpa_0_9_3;
  assign dpa_0_9_3 = {1'b0, dpa_terms_i[9][9]} + {1'b0, dpa_terms_i[10][9]} + {1'b0, dpa_terms_i[11][9]};
  wire [1:0] dpa_0_9_4;
  assign dpa_0_9_4 = {1'b0, dpa_terms_i[12][9]} + {1'b0, dpa_terms_i[13][9]} + {1'b0, dpa_terms_i[14][9]};
  wire [1:0] dpa_0_9_5;
  assign dpa_0_9_5 = {1'b0, dpa_terms_i[15][9]} + {1'b0, dpa_terms_i[16][9]};
  wire [1:0] dpa_0_10_0;
  assign dpa_0_10_0 = {1'b0, dpa_terms_i[0][10]} + {1'b0, dpa_terms_i[1][10]} + {1'b0, dpa_terms_i[2][10]};
  wire [1:0] dpa_0_10_1;
  assign dpa_0_10_1 = {1'b0, dpa_terms_i[3][10]} + {1'b0, dpa_terms_i[4][10]} + {1'b0, dpa_terms_i[5][10]};
  wire [1:0] dpa_0_10_2;
  assign dpa_0_10_2 = {1'b0, dpa_terms_i[6][10]} + {1'b0, dpa_terms_i[7][10]} + {1'b0, dpa_terms_i[8][10]};
  wire [1:0] dpa_0_10_3;
  assign dpa_0_10_3 = {1'b0, dpa_terms_i[9][10]} + {1'b0, dpa_terms_i[10][10]} + {1'b0, dpa_terms_i[11][10]};
  wire [1:0] dpa_0_10_4;
  assign dpa_0_10_4 = {1'b0, dpa_terms_i[12][10]} + {1'b0, dpa_terms_i[13][10]} + {1'b0, dpa_terms_i[14][10]};
  wire [1:0] dpa_0_10_5;
  assign dpa_0_10_5 = {1'b0, dpa_terms_i[15][10]} + {1'b0, dpa_terms_i[16][10]};
  wire [1:0] dpa_0_11_0;
  assign dpa_0_11_0 = {1'b0, dpa_terms_i[0][11]} + {1'b0, dpa_terms_i[1][11]} + {1'b0, dpa_terms_i[2][11]};
  wire [1:0] dpa_0_11_1;
  assign dpa_0_11_1 = {1'b0, dpa_terms_i[3][11]} + {1'b0, dpa_terms_i[4][11]} + {1'b0, dpa_terms_i[5][11]};
  wire [1:0] dpa_0_11_2;
  assign dpa_0_11_2 = {1'b0, dpa_terms_i[6][11]} + {1'b0, dpa_terms_i[7][11]} + {1'b0, dpa_terms_i[8][11]};
  wire [1:0] dpa_0_11_3;
  assign dpa_0_11_3 = {1'b0, dpa_terms_i[9][11]} + {1'b0, dpa_terms_i[10][11]} + {1'b0, dpa_terms_i[11][11]};
  wire [1:0] dpa_0_11_4;
  assign dpa_0_11_4 = {1'b0, dpa_terms_i[12][11]} + {1'b0, dpa_terms_i[13][11]} + {1'b0, dpa_terms_i[14][11]};
  wire [1:0] dpa_0_11_5;
  assign dpa_0_11_5 = {1'b0, dpa_terms_i[15][11]} + {1'b0, dpa_terms_i[16][11]};
  wire [1:0] dpa_0_12_0;
  assign dpa_0_12_0 = {1'b0, dpa_terms_i[0][12]} + {1'b0, dpa_terms_i[1][12]} + {1'b0, dpa_terms_i[2][12]};
  wire [1:0] dpa_0_12_1;
  assign dpa_0_12_1 = {1'b0, dpa_terms_i[3][12]} + {1'b0, dpa_terms_i[4][12]} + {1'b0, dpa_terms_i[5][12]};
  wire [1:0] dpa_0_12_2;
  assign dpa_0_12_2 = {1'b0, dpa_terms_i[6][12]} + {1'b0, dpa_terms_i[7][12]} + {1'b0, dpa_terms_i[8][12]};
  wire [1:0] dpa_0_12_3;
  assign dpa_0_12_3 = {1'b0, dpa_terms_i[9][12]} + {1'b0, dpa_terms_i[10][12]} + {1'b0, dpa_terms_i[11][12]};
  wire [1:0] dpa_0_12_4;
  assign dpa_0_12_4 = {1'b0, dpa_terms_i[12][12]} + {1'b0, dpa_terms_i[13][12]} + {1'b0, dpa_terms_i[14][12]};
  wire [1:0] dpa_0_12_5;
  assign dpa_0_12_5 = {1'b0, dpa_terms_i[15][12]} + {1'b0, dpa_terms_i[16][12]};
  wire [1:0] dpa_0_13_0;
  assign dpa_0_13_0 = {1'b0, dpa_terms_i[0][13]} + {1'b0, dpa_terms_i[1][13]} + {1'b0, dpa_terms_i[2][13]};
  wire [1:0] dpa_0_13_1;
  assign dpa_0_13_1 = {1'b0, dpa_terms_i[3][13]} + {1'b0, dpa_terms_i[4][13]} + {1'b0, dpa_terms_i[5][13]};
  wire [1:0] dpa_0_13_2;
  assign dpa_0_13_2 = {1'b0, dpa_terms_i[6][13]} + {1'b0, dpa_terms_i[7][13]} + {1'b0, dpa_terms_i[8][13]};
  wire [1:0] dpa_0_13_3;
  assign dpa_0_13_3 = {1'b0, dpa_terms_i[9][13]} + {1'b0, dpa_terms_i[10][13]} + {1'b0, dpa_terms_i[11][13]};
  wire [1:0] dpa_0_13_4;
  assign dpa_0_13_4 = {1'b0, dpa_terms_i[12][13]} + {1'b0, dpa_terms_i[13][13]} + {1'b0, dpa_terms_i[14][13]};
  wire [1:0] dpa_0_13_5;
  assign dpa_0_13_5 = {1'b0, dpa_terms_i[15][13]} + {1'b0, dpa_terms_i[16][13]};
  wire [1:0] dpa_0_14_0;
  assign dpa_0_14_0 = {1'b0, dpa_terms_i[0][14]} + {1'b0, dpa_terms_i[1][14]} + {1'b0, dpa_terms_i[2][14]};
  wire [1:0] dpa_0_14_1;
  assign dpa_0_14_1 = {1'b0, dpa_terms_i[3][14]} + {1'b0, dpa_terms_i[4][14]} + {1'b0, dpa_terms_i[5][14]};
  wire [1:0] dpa_0_14_2;
  assign dpa_0_14_2 = {1'b0, dpa_terms_i[6][14]} + {1'b0, dpa_terms_i[7][14]} + {1'b0, dpa_terms_i[8][14]};
  wire [1:0] dpa_0_14_3;
  assign dpa_0_14_3 = {1'b0, dpa_terms_i[9][14]} + {1'b0, dpa_terms_i[10][14]} + {1'b0, dpa_terms_i[11][14]};
  wire [1:0] dpa_0_14_4;
  assign dpa_0_14_4 = {1'b0, dpa_terms_i[12][14]} + {1'b0, dpa_terms_i[13][14]} + {1'b0, dpa_terms_i[14][14]};
  wire [1:0] dpa_0_14_5;
  assign dpa_0_14_5 = {1'b0, dpa_terms_i[15][14]} + {1'b0, dpa_terms_i[16][14]};
  wire [1:0] dpa_0_15_0;
  assign dpa_0_15_0 = {1'b0, dpa_terms_i[0][15]} + {1'b0, dpa_terms_i[1][15]} + {1'b0, dpa_terms_i[2][15]};
  wire [1:0] dpa_0_15_1;
  assign dpa_0_15_1 = {1'b0, dpa_terms_i[3][15]} + {1'b0, dpa_terms_i[4][15]} + {1'b0, dpa_terms_i[5][15]};
  wire [1:0] dpa_0_15_2;
  assign dpa_0_15_2 = {1'b0, dpa_terms_i[6][15]} + {1'b0, dpa_terms_i[7][15]} + {1'b0, dpa_terms_i[8][15]};
  wire [1:0] dpa_0_15_3;
  assign dpa_0_15_3 = {1'b0, dpa_terms_i[9][15]} + {1'b0, dpa_terms_i[10][15]} + {1'b0, dpa_terms_i[11][15]};
  wire [1:0] dpa_0_15_4;
  assign dpa_0_15_4 = {1'b0, dpa_terms_i[12][15]} + {1'b0, dpa_terms_i[13][15]} + {1'b0, dpa_terms_i[14][15]};
  wire [1:0] dpa_0_15_5;
  assign dpa_0_15_5 = {1'b0, dpa_terms_i[15][15]} + {1'b0, dpa_terms_i[16][15]};
  wire [1:0] dpa_0_16_0;
  assign dpa_0_16_0 = {1'b0, dpa_terms_i[0][16]} + {1'b0, dpa_terms_i[1][16]} + {1'b0, dpa_terms_i[2][16]};
  wire [1:0] dpa_0_16_1;
  assign dpa_0_16_1 = {1'b0, dpa_terms_i[3][16]} + {1'b0, dpa_terms_i[4][16]} + {1'b0, dpa_terms_i[5][16]};
  wire [1:0] dpa_0_16_2;
  assign dpa_0_16_2 = {1'b0, dpa_terms_i[6][16]} + {1'b0, dpa_terms_i[7][16]} + {1'b0, dpa_terms_i[8][16]};
  wire [1:0] dpa_0_16_3;
  assign dpa_0_16_3 = {1'b0, dpa_terms_i[9][16]} + {1'b0, dpa_terms_i[10][16]} + {1'b0, dpa_terms_i[11][16]};
  wire [1:0] dpa_0_16_4;
  assign dpa_0_16_4 = {1'b0, dpa_terms_i[12][16]} + {1'b0, dpa_terms_i[13][16]} + {1'b0, dpa_terms_i[14][16]};
  wire [1:0] dpa_0_16_5;
  assign dpa_0_16_5 = {1'b0, dpa_terms_i[15][16]} + {1'b0, dpa_terms_i[16][16]};
  wire [1:0] dpa_0_17_0;
  assign dpa_0_17_0 = {1'b0, dpa_terms_i[0][17]} + {1'b0, dpa_terms_i[1][17]} + {1'b0, dpa_terms_i[2][17]};
  wire [1:0] dpa_0_17_1;
  assign dpa_0_17_1 = {1'b0, dpa_terms_i[3][17]} + {1'b0, dpa_terms_i[4][17]} + {1'b0, dpa_terms_i[5][17]};
  wire [1:0] dpa_0_17_2;
  assign dpa_0_17_2 = {1'b0, dpa_terms_i[6][17]} + {1'b0, dpa_terms_i[7][17]} + {1'b0, dpa_terms_i[8][17]};
  wire [1:0] dpa_0_17_3;
  assign dpa_0_17_3 = {1'b0, dpa_terms_i[9][17]} + {1'b0, dpa_terms_i[10][17]} + {1'b0, dpa_terms_i[11][17]};
  wire [1:0] dpa_0_17_4;
  assign dpa_0_17_4 = {1'b0, dpa_terms_i[12][17]} + {1'b0, dpa_terms_i[13][17]} + {1'b0, dpa_terms_i[14][17]};
  wire [1:0] dpa_0_17_5;
  assign dpa_0_17_5 = {1'b0, dpa_terms_i[15][17]} + {1'b0, dpa_terms_i[16][17]};
  wire [1:0] dpa_0_18_0;
  assign dpa_0_18_0 = {1'b0, dpa_terms_i[0][18]} + {1'b0, dpa_terms_i[1][18]} + {1'b0, dpa_terms_i[2][18]};
  wire [1:0] dpa_0_18_1;
  assign dpa_0_18_1 = {1'b0, dpa_terms_i[3][18]} + {1'b0, dpa_terms_i[4][18]} + {1'b0, dpa_terms_i[5][18]};
  wire [1:0] dpa_0_18_2;
  assign dpa_0_18_2 = {1'b0, dpa_terms_i[6][18]} + {1'b0, dpa_terms_i[7][18]} + {1'b0, dpa_terms_i[8][18]};
  wire [1:0] dpa_0_18_3;
  assign dpa_0_18_3 = {1'b0, dpa_terms_i[9][18]} + {1'b0, dpa_terms_i[10][18]} + {1'b0, dpa_terms_i[11][18]};
  wire [1:0] dpa_0_18_4;
  assign dpa_0_18_4 = {1'b0, dpa_terms_i[12][18]} + {1'b0, dpa_terms_i[13][18]} + {1'b0, dpa_terms_i[14][18]};
  wire [1:0] dpa_0_18_5;
  assign dpa_0_18_5 = {1'b0, dpa_terms_i[15][18]} + {1'b0, dpa_terms_i[16][18]};
  wire [1:0] dpa_0_19_0;
  assign dpa_0_19_0 = {1'b0, dpa_terms_i[0][19]} + {1'b0, dpa_terms_i[1][19]} + {1'b0, dpa_terms_i[2][19]};
  wire [1:0] dpa_0_19_1;
  assign dpa_0_19_1 = {1'b0, dpa_terms_i[3][19]} + {1'b0, dpa_terms_i[4][19]} + {1'b0, dpa_terms_i[5][19]};
  wire [1:0] dpa_0_19_2;
  assign dpa_0_19_2 = {1'b0, dpa_terms_i[6][19]} + {1'b0, dpa_terms_i[7][19]} + {1'b0, dpa_terms_i[8][19]};
  wire [1:0] dpa_0_19_3;
  assign dpa_0_19_3 = {1'b0, dpa_terms_i[9][19]} + {1'b0, dpa_terms_i[10][19]} + {1'b0, dpa_terms_i[11][19]};
  wire [1:0] dpa_0_19_4;
  assign dpa_0_19_4 = {1'b0, dpa_terms_i[12][19]} + {1'b0, dpa_terms_i[13][19]} + {1'b0, dpa_terms_i[14][19]};
  wire [1:0] dpa_0_19_5;
  assign dpa_0_19_5 = {1'b0, dpa_terms_i[15][19]} + {1'b0, dpa_terms_i[16][19]};
  wire [1:0] dpa_0_20_0;
  assign dpa_0_20_0 = {1'b0, dpa_terms_i[0][20]} + {1'b0, dpa_terms_i[1][20]} + {1'b0, dpa_terms_i[2][20]};
  wire [1:0] dpa_0_20_1;
  assign dpa_0_20_1 = {1'b0, dpa_terms_i[3][20]} + {1'b0, dpa_terms_i[4][20]} + {1'b0, dpa_terms_i[5][20]};
  wire [1:0] dpa_0_20_2;
  assign dpa_0_20_2 = {1'b0, dpa_terms_i[6][20]} + {1'b0, dpa_terms_i[7][20]} + {1'b0, dpa_terms_i[8][20]};
  wire [1:0] dpa_0_20_3;
  assign dpa_0_20_3 = {1'b0, dpa_terms_i[9][20]} + {1'b0, dpa_terms_i[10][20]} + {1'b0, dpa_terms_i[11][20]};
  wire [1:0] dpa_0_20_4;
  assign dpa_0_20_4 = {1'b0, dpa_terms_i[12][20]} + {1'b0, dpa_terms_i[13][20]} + {1'b0, dpa_terms_i[14][20]};
  wire [1:0] dpa_0_20_5;
  assign dpa_0_20_5 = {1'b0, dpa_terms_i[15][20]} + {1'b0, dpa_terms_i[16][20]};
  wire [1:0] dpa_0_21_0;
  assign dpa_0_21_0 = {1'b0, dpa_terms_i[0][21]} + {1'b0, dpa_terms_i[1][21]} + {1'b0, dpa_terms_i[2][21]};
  wire [1:0] dpa_0_21_1;
  assign dpa_0_21_1 = {1'b0, dpa_terms_i[3][21]} + {1'b0, dpa_terms_i[4][21]} + {1'b0, dpa_terms_i[5][21]};
  wire [1:0] dpa_0_21_2;
  assign dpa_0_21_2 = {1'b0, dpa_terms_i[6][21]} + {1'b0, dpa_terms_i[7][21]} + {1'b0, dpa_terms_i[8][21]};
  wire [1:0] dpa_0_21_3;
  assign dpa_0_21_3 = {1'b0, dpa_terms_i[9][21]} + {1'b0, dpa_terms_i[10][21]} + {1'b0, dpa_terms_i[11][21]};
  wire [1:0] dpa_0_21_4;
  assign dpa_0_21_4 = {1'b0, dpa_terms_i[12][21]} + {1'b0, dpa_terms_i[13][21]} + {1'b0, dpa_terms_i[14][21]};
  wire [1:0] dpa_0_21_5;
  assign dpa_0_21_5 = {1'b0, dpa_terms_i[15][21]} + {1'b0, dpa_terms_i[16][21]};
  wire [1:0] dpa_0_22_0;
  assign dpa_0_22_0 = {1'b0, dpa_terms_i[0][22]} + {1'b0, dpa_terms_i[1][22]} + {1'b0, dpa_terms_i[2][22]};
  wire [1:0] dpa_0_22_1;
  assign dpa_0_22_1 = {1'b0, dpa_terms_i[3][22]} + {1'b0, dpa_terms_i[4][22]} + {1'b0, dpa_terms_i[5][22]};
  wire [1:0] dpa_0_22_2;
  assign dpa_0_22_2 = {1'b0, dpa_terms_i[6][22]} + {1'b0, dpa_terms_i[7][22]} + {1'b0, dpa_terms_i[8][22]};
  wire [1:0] dpa_0_22_3;
  assign dpa_0_22_3 = {1'b0, dpa_terms_i[9][22]} + {1'b0, dpa_terms_i[10][22]} + {1'b0, dpa_terms_i[11][22]};
  wire [1:0] dpa_0_22_4;
  assign dpa_0_22_4 = {1'b0, dpa_terms_i[12][22]} + {1'b0, dpa_terms_i[13][22]} + {1'b0, dpa_terms_i[14][22]};
  wire [1:0] dpa_0_22_5;
  assign dpa_0_22_5 = {1'b0, dpa_terms_i[15][22]} + {1'b0, dpa_terms_i[16][22]};
  wire [1:0] dpa_0_23_0;
  assign dpa_0_23_0 = {1'b0, dpa_terms_i[0][23]} + {1'b0, dpa_terms_i[1][23]} + {1'b0, dpa_terms_i[2][23]};
  wire [1:0] dpa_0_23_1;
  assign dpa_0_23_1 = {1'b0, dpa_terms_i[3][23]} + {1'b0, dpa_terms_i[4][23]} + {1'b0, dpa_terms_i[5][23]};
  wire [1:0] dpa_0_23_2;
  assign dpa_0_23_2 = {1'b0, dpa_terms_i[6][23]} + {1'b0, dpa_terms_i[7][23]} + {1'b0, dpa_terms_i[8][23]};
  wire [1:0] dpa_0_23_3;
  assign dpa_0_23_3 = {1'b0, dpa_terms_i[9][23]} + {1'b0, dpa_terms_i[10][23]} + {1'b0, dpa_terms_i[11][23]};
  wire [1:0] dpa_0_23_4;
  assign dpa_0_23_4 = {1'b0, dpa_terms_i[12][23]} + {1'b0, dpa_terms_i[13][23]} + {1'b0, dpa_terms_i[14][23]};
  wire [1:0] dpa_0_23_5;
  assign dpa_0_23_5 = {1'b0, dpa_terms_i[15][23]} + {1'b0, dpa_terms_i[16][23]};
  wire [1:0] dpa_0_24_0;
  assign dpa_0_24_0 = {1'b0, dpa_terms_i[0][24]} + {1'b0, dpa_terms_i[1][24]} + {1'b0, dpa_terms_i[2][24]};
  wire [1:0] dpa_0_24_1;
  assign dpa_0_24_1 = {1'b0, dpa_terms_i[3][24]} + {1'b0, dpa_terms_i[4][24]} + {1'b0, dpa_terms_i[5][24]};
  wire [1:0] dpa_0_24_2;
  assign dpa_0_24_2 = {1'b0, dpa_terms_i[6][24]} + {1'b0, dpa_terms_i[7][24]} + {1'b0, dpa_terms_i[8][24]};
  wire [1:0] dpa_0_24_3;
  assign dpa_0_24_3 = {1'b0, dpa_terms_i[9][24]} + {1'b0, dpa_terms_i[10][24]} + {1'b0, dpa_terms_i[11][24]};
  wire [1:0] dpa_0_24_4;
  assign dpa_0_24_4 = {1'b0, dpa_terms_i[12][24]} + {1'b0, dpa_terms_i[13][24]} + {1'b0, dpa_terms_i[14][24]};
  wire [1:0] dpa_0_24_5;
  assign dpa_0_24_5 = {1'b0, dpa_terms_i[15][24]} + {1'b0, dpa_terms_i[16][24]};
  wire [1:0] dpa_0_25_0;
  assign dpa_0_25_0 = {1'b0, dpa_terms_i[0][25]} + {1'b0, dpa_terms_i[1][25]} + {1'b0, dpa_terms_i[2][25]};
  wire [1:0] dpa_0_25_1;
  assign dpa_0_25_1 = {1'b0, dpa_terms_i[3][25]} + {1'b0, dpa_terms_i[4][25]} + {1'b0, dpa_terms_i[5][25]};
  wire [1:0] dpa_0_25_2;
  assign dpa_0_25_2 = {1'b0, dpa_terms_i[6][25]} + {1'b0, dpa_terms_i[7][25]} + {1'b0, dpa_terms_i[8][25]};
  wire [1:0] dpa_0_25_3;
  assign dpa_0_25_3 = {1'b0, dpa_terms_i[9][25]} + {1'b0, dpa_terms_i[10][25]} + {1'b0, dpa_terms_i[11][25]};
  wire [1:0] dpa_0_25_4;
  assign dpa_0_25_4 = {1'b0, dpa_terms_i[12][25]} + {1'b0, dpa_terms_i[13][25]} + {1'b0, dpa_terms_i[14][25]};
  wire [1:0] dpa_0_25_5;
  assign dpa_0_25_5 = {1'b0, dpa_terms_i[15][25]} + {1'b0, dpa_terms_i[16][25]};
  wire [1:0] dpa_0_26_0;
  assign dpa_0_26_0 = {1'b0, dpa_terms_i[0][26]} + {1'b0, dpa_terms_i[1][26]} + {1'b0, dpa_terms_i[2][26]};
  wire [1:0] dpa_0_26_1;
  assign dpa_0_26_1 = {1'b0, dpa_terms_i[3][26]} + {1'b0, dpa_terms_i[4][26]} + {1'b0, dpa_terms_i[5][26]};
  wire [1:0] dpa_0_26_2;
  assign dpa_0_26_2 = {1'b0, dpa_terms_i[6][26]} + {1'b0, dpa_terms_i[7][26]} + {1'b0, dpa_terms_i[8][26]};
  wire [1:0] dpa_0_26_3;
  assign dpa_0_26_3 = {1'b0, dpa_terms_i[9][26]} + {1'b0, dpa_terms_i[10][26]} + {1'b0, dpa_terms_i[11][26]};
  wire [1:0] dpa_0_26_4;
  assign dpa_0_26_4 = {1'b0, dpa_terms_i[12][26]} + {1'b0, dpa_terms_i[13][26]} + {1'b0, dpa_terms_i[14][26]};
  wire [1:0] dpa_0_26_5;
  assign dpa_0_26_5 = {1'b0, dpa_terms_i[15][26]} + {1'b0, dpa_terms_i[16][26]};
  wire [1:0] dpa_1_0_0;
  assign dpa_1_0_0 = {1'b0, dpa_0_0_0[0]} + {1'b0, dpa_0_0_1[0]} + {1'b0, dpa_0_0_2[0]};
  wire [1:0] dpa_1_0_1;
  assign dpa_1_0_1 = {1'b0, dpa_terms_i[9][0]} + {1'b0, dpa_terms_i[10][0]} + {1'b0, dpa_terms_i[11][0]};
  wire [1:0] dpa_1_0_2;
  assign dpa_1_0_2 = {1'b0, dpa_terms_i[12][0]} + {1'b0, dpa_terms_i[13][0]} + {1'b0, dpa_terms_i[14][0]};
  wire [1:0] dpa_1_0_3;
  assign dpa_1_0_3 = {1'b0, dpa_terms_i[15][0]} + {1'b0, dpa_terms_i[16][0]} + {1'b0, dpa_terms_i[17][0]};
  wire [1:0] dpa_1_0_4;
  assign dpa_1_0_4 = {1'b0, dpa_terms_i[18][0]} + {1'b0, dpa_terms_i[19][0]};
  wire [1:0] dpa_1_1_0;
  assign dpa_1_1_0 = {1'b0, dpa_0_0_0[1]} + {1'b0, dpa_0_0_1[1]} + {1'b0, dpa_0_0_2[1]};
  wire [1:0] dpa_1_1_1;
  assign dpa_1_1_1 = {1'b0, dpa_0_1_0[0]} + {1'b0, dpa_0_1_1[0]} + {1'b0, dpa_0_1_2[0]};
  wire [1:0] dpa_1_1_2;
  assign dpa_1_1_2 = {1'b0, dpa_0_1_3[0]} + {1'b0, dpa_0_1_4[0]} + {1'b0, dpa_terms_i[14][1]};
  wire [1:0] dpa_1_1_3;
  assign dpa_1_1_3 = {1'b0, dpa_terms_i[15][1]} + {1'b0, dpa_terms_i[16][1]} + {1'b0, dpa_terms_i[17][1]};
  wire [1:0] dpa_1_1_4;
  assign dpa_1_1_4 = {1'b0, dpa_terms_i[18][1]} + {1'b0, dpa_terms_i[19][1]} + {1'b0, dpa_terms_i[20][1]};
  wire [1:0] dpa_1_1_5;
  assign dpa_1_1_5 = {1'b0, dpa_terms_i[21][1]} + {1'b0, dpa_terms_i[22][1]} + {1'b0, dpa_terms_i[23][1]};
  wire [1:0] dpa_1_1_6;
  assign dpa_1_1_6 = {1'b0, dpa_terms_i[24][1]} + {1'b0, dpa_terms_i[25][1]} + {1'b0, dpa_terms_i[26][1]};
  wire [1:0] dpa_1_2_0;
  assign dpa_1_2_0 = {1'b0, dpa_0_1_0[1]} + {1'b0, dpa_0_1_1[1]} + {1'b0, dpa_0_1_2[1]};
  wire [1:0] dpa_1_2_1;
  assign dpa_1_2_1 = {1'b0, dpa_0_1_3[1]} + {1'b0, dpa_0_1_4[1]} + {1'b0, dpa_0_2_0[0]};
  wire [1:0] dpa_1_2_2;
  assign dpa_1_2_2 = {1'b0, dpa_0_2_1[0]} + {1'b0, dpa_0_2_2[0]} + {1'b0, dpa_0_2_3[0]};
  wire [1:0] dpa_1_2_3;
  assign dpa_1_2_3 = {1'b0, dpa_0_2_4[0]} + {1'b0, dpa_0_2_5[0]} + {1'b0, dpa_terms_i[17][2]};
  wire [1:0] dpa_1_2_4;
  assign dpa_1_2_4 = {1'b0, dpa_terms_i[18][2]} + {1'b0, dpa_terms_i[19][2]} + {1'b0, dpa_terms_i[20][2]};
  wire [1:0] dpa_1_2_5;
  assign dpa_1_2_5 = {1'b0, dpa_terms_i[21][2]} + {1'b0, dpa_terms_i[22][2]} + {1'b0, dpa_terms_i[23][2]};
  wire [1:0] dpa_1_2_6;
  assign dpa_1_2_6 = {1'b0, dpa_terms_i[24][2]} + {1'b0, dpa_terms_i[25][2]} + {1'b0, dpa_terms_i[26][2]};
  wire [1:0] dpa_1_2_7;
  assign dpa_1_2_7 = {1'b0, dpa_terms_i[27][2]} + {1'b0, dpa_terms_i[28][2]} + {1'b0, dpa_terms_i[29][2]};
  wire [1:0] dpa_1_3_0;
  assign dpa_1_3_0 = {1'b0, dpa_0_2_0[1]} + {1'b0, dpa_0_2_1[1]} + {1'b0, dpa_0_2_2[1]};
  wire [1:0] dpa_1_3_1;
  assign dpa_1_3_1 = {1'b0, dpa_0_2_3[1]} + {1'b0, dpa_0_2_4[1]} + {1'b0, dpa_0_2_5[1]};
  wire [1:0] dpa_1_3_2;
  assign dpa_1_3_2 = {1'b0, dpa_0_3_0[0]} + {1'b0, dpa_0_3_1[0]} + {1'b0, dpa_0_3_2[0]};
  wire [1:0] dpa_1_3_3;
  assign dpa_1_3_3 = {1'b0, dpa_0_3_3[0]} + {1'b0, dpa_0_3_4[0]} + {1'b0, dpa_0_3_5[0]};
  wire [1:0] dpa_1_3_4;
  assign dpa_1_3_4 = {1'b0, dpa_terms_i[18][3]} + {1'b0, dpa_terms_i[19][3]} + {1'b0, dpa_terms_i[20][3]};
  wire [1:0] dpa_1_3_5;
  assign dpa_1_3_5 = {1'b0, dpa_terms_i[21][3]} + {1'b0, dpa_terms_i[22][3]} + {1'b0, dpa_terms_i[23][3]};
  wire [1:0] dpa_1_3_6;
  assign dpa_1_3_6 = {1'b0, dpa_terms_i[24][3]} + {1'b0, dpa_terms_i[25][3]} + {1'b0, dpa_terms_i[26][3]};
  wire [1:0] dpa_1_3_7;
  assign dpa_1_3_7 = {1'b0, dpa_terms_i[27][3]} + {1'b0, dpa_terms_i[28][3]} + {1'b0, dpa_terms_i[29][3]};
  wire [1:0] dpa_1_3_8;
  assign dpa_1_3_8 = {1'b0, dpa_terms_i[30][3]} + {1'b0, dpa_terms_i[31][3]};
  wire [1:0] dpa_1_4_0;
  assign dpa_1_4_0 = {1'b0, dpa_0_3_0[1]} + {1'b0, dpa_0_3_1[1]} + {1'b0, dpa_0_3_2[1]};
  wire [1:0] dpa_1_4_1;
  assign dpa_1_4_1 = {1'b0, dpa_0_3_3[1]} + {1'b0, dpa_0_3_4[1]} + {1'b0, dpa_0_3_5[1]};
  wire [1:0] dpa_1_4_2;
  assign dpa_1_4_2 = {1'b0, dpa_0_4_0[0]} + {1'b0, dpa_0_4_1[0]} + {1'b0, dpa_0_4_2[0]};
  wire [1:0] dpa_1_4_3;
  assign dpa_1_4_3 = {1'b0, dpa_0_4_3[0]} + {1'b0, dpa_0_4_4[0]} + {1'b0, dpa_0_4_5[0]};
  wire [1:0] dpa_1_4_4;
  assign dpa_1_4_4 = {1'b0, dpa_terms_i[18][4]} + {1'b0, dpa_terms_i[19][4]} + {1'b0, dpa_terms_i[20][4]};
  wire [1:0] dpa_1_4_5;
  assign dpa_1_4_5 = {1'b0, dpa_terms_i[21][4]} + {1'b0, dpa_terms_i[22][4]} + {1'b0, dpa_terms_i[23][4]};
  wire [1:0] dpa_1_4_6;
  assign dpa_1_4_6 = {1'b0, dpa_terms_i[24][4]} + {1'b0, dpa_terms_i[25][4]} + {1'b0, dpa_terms_i[26][4]};
  wire [1:0] dpa_1_4_7;
  assign dpa_1_4_7 = {1'b0, dpa_terms_i[27][4]} + {1'b0, dpa_terms_i[28][4]} + {1'b0, dpa_terms_i[29][4]};
  wire [1:0] dpa_1_4_8;
  assign dpa_1_4_8 = {1'b0, dpa_terms_i[30][4]} + {1'b0, dpa_terms_i[31][4]} + {1'b0, dpa_terms_i[32][4]};
  wire [1:0] dpa_1_5_0;
  assign dpa_1_5_0 = {1'b0, dpa_0_4_0[1]} + {1'b0, dpa_0_4_1[1]} + {1'b0, dpa_0_4_2[1]};
  wire [1:0] dpa_1_5_1;
  assign dpa_1_5_1 = {1'b0, dpa_0_4_3[1]} + {1'b0, dpa_0_4_4[1]} + {1'b0, dpa_0_4_5[1]};
  wire [1:0] dpa_1_5_2;
  assign dpa_1_5_2 = {1'b0, dpa_0_5_0[0]} + {1'b0, dpa_0_5_1[0]} + {1'b0, dpa_0_5_2[0]};
  wire [1:0] dpa_1_5_3;
  assign dpa_1_5_3 = {1'b0, dpa_0_5_3[0]} + {1'b0, dpa_0_5_4[0]} + {1'b0, dpa_0_5_5[0]};
  wire [1:0] dpa_1_5_4;
  assign dpa_1_5_4 = {1'b0, dpa_terms_i[18][5]} + {1'b0, dpa_terms_i[19][5]} + {1'b0, dpa_terms_i[20][5]};
  wire [1:0] dpa_1_5_5;
  assign dpa_1_5_5 = {1'b0, dpa_terms_i[21][5]} + {1'b0, dpa_terms_i[22][5]} + {1'b0, dpa_terms_i[23][5]};
  wire [1:0] dpa_1_5_6;
  assign dpa_1_5_6 = {1'b0, dpa_terms_i[24][5]} + {1'b0, dpa_terms_i[25][5]} + {1'b0, dpa_terms_i[26][5]};
  wire [1:0] dpa_1_5_7;
  assign dpa_1_5_7 = {1'b0, dpa_terms_i[27][5]} + {1'b0, dpa_terms_i[28][5]} + {1'b0, dpa_terms_i[29][5]};
  wire [1:0] dpa_1_5_8;
  assign dpa_1_5_8 = {1'b0, dpa_terms_i[30][5]} + {1'b0, dpa_terms_i[31][5]} + {1'b0, dpa_terms_i[32][5]};
  wire [1:0] dpa_1_6_0;
  assign dpa_1_6_0 = {1'b0, dpa_0_5_0[1]} + {1'b0, dpa_0_5_1[1]} + {1'b0, dpa_0_5_2[1]};
  wire [1:0] dpa_1_6_1;
  assign dpa_1_6_1 = {1'b0, dpa_0_5_3[1]} + {1'b0, dpa_0_5_4[1]} + {1'b0, dpa_0_5_5[1]};
  wire [1:0] dpa_1_6_2;
  assign dpa_1_6_2 = {1'b0, dpa_0_6_0[0]} + {1'b0, dpa_0_6_1[0]} + {1'b0, dpa_0_6_2[0]};
  wire [1:0] dpa_1_6_3;
  assign dpa_1_6_3 = {1'b0, dpa_0_6_3[0]} + {1'b0, dpa_0_6_4[0]} + {1'b0, dpa_0_6_5[0]};
  wire [1:0] dpa_1_6_4;
  assign dpa_1_6_4 = {1'b0, dpa_terms_i[17][6]} + {1'b0, dpa_terms_i[18][6]} + {1'b0, dpa_terms_i[19][6]};
  wire [1:0] dpa_1_6_5;
  assign dpa_1_6_5 = {1'b0, dpa_terms_i[20][6]} + {1'b0, dpa_terms_i[21][6]} + {1'b0, dpa_terms_i[22][6]};
  wire [1:0] dpa_1_6_6;
  assign dpa_1_6_6 = {1'b0, dpa_terms_i[23][6]} + {1'b0, dpa_terms_i[24][6]} + {1'b0, dpa_terms_i[25][6]};
  wire [1:0] dpa_1_6_7;
  assign dpa_1_6_7 = {1'b0, dpa_terms_i[26][6]} + {1'b0, dpa_terms_i[27][6]} + {1'b0, dpa_terms_i[28][6]};
  wire [1:0] dpa_1_6_8;
  assign dpa_1_6_8 = {1'b0, dpa_terms_i[29][6]} + {1'b0, dpa_terms_i[30][6]} + {1'b0, dpa_terms_i[31][6]};
  wire [1:0] dpa_1_7_0;
  assign dpa_1_7_0 = {1'b0, dpa_0_6_0[1]} + {1'b0, dpa_0_6_1[1]} + {1'b0, dpa_0_6_2[1]};
  wire [1:0] dpa_1_7_1;
  assign dpa_1_7_1 = {1'b0, dpa_0_6_3[1]} + {1'b0, dpa_0_6_4[1]} + {1'b0, dpa_0_6_5[1]};
  wire [1:0] dpa_1_7_2;
  assign dpa_1_7_2 = {1'b0, dpa_0_7_0[0]} + {1'b0, dpa_0_7_1[0]} + {1'b0, dpa_0_7_2[0]};
  wire [1:0] dpa_1_7_3;
  assign dpa_1_7_3 = {1'b0, dpa_0_7_3[0]} + {1'b0, dpa_0_7_4[0]} + {1'b0, dpa_0_7_5[0]};
  wire [1:0] dpa_1_7_4;
  assign dpa_1_7_4 = {1'b0, dpa_terms_i[17][7]} + {1'b0, dpa_terms_i[18][7]} + {1'b0, dpa_terms_i[19][7]};
  wire [1:0] dpa_1_7_5;
  assign dpa_1_7_5 = {1'b0, dpa_terms_i[20][7]} + {1'b0, dpa_terms_i[21][7]} + {1'b0, dpa_terms_i[22][7]};
  wire [1:0] dpa_1_7_6;
  assign dpa_1_7_6 = {1'b0, dpa_terms_i[23][7]} + {1'b0, dpa_terms_i[24][7]} + {1'b0, dpa_terms_i[25][7]};
  wire [1:0] dpa_1_7_7;
  assign dpa_1_7_7 = {1'b0, dpa_terms_i[26][7]} + {1'b0, dpa_terms_i[27][7]} + {1'b0, dpa_terms_i[28][7]};
  wire [1:0] dpa_1_7_8;
  assign dpa_1_7_8 = {1'b0, dpa_terms_i[29][7]} + {1'b0, dpa_terms_i[30][7]} + {1'b0, dpa_terms_i[31][7]};
  wire [1:0] dpa_1_8_0;
  assign dpa_1_8_0 = {1'b0, dpa_0_7_0[1]} + {1'b0, dpa_0_7_1[1]} + {1'b0, dpa_0_7_2[1]};
  wire [1:0] dpa_1_8_1;
  assign dpa_1_8_1 = {1'b0, dpa_0_7_3[1]} + {1'b0, dpa_0_7_4[1]} + {1'b0, dpa_0_7_5[1]};
  wire [1:0] dpa_1_8_2;
  assign dpa_1_8_2 = {1'b0, dpa_0_8_0[0]} + {1'b0, dpa_0_8_1[0]} + {1'b0, dpa_0_8_2[0]};
  wire [1:0] dpa_1_8_3;
  assign dpa_1_8_3 = {1'b0, dpa_0_8_3[0]} + {1'b0, dpa_0_8_4[0]} + {1'b0, dpa_0_8_5[0]};
  wire [1:0] dpa_1_8_4;
  assign dpa_1_8_4 = {1'b0, dpa_terms_i[17][8]} + {1'b0, dpa_terms_i[18][8]} + {1'b0, dpa_terms_i[19][8]};
  wire [1:0] dpa_1_8_5;
  assign dpa_1_8_5 = {1'b0, dpa_terms_i[20][8]} + {1'b0, dpa_terms_i[21][8]} + {1'b0, dpa_terms_i[22][8]};
  wire [1:0] dpa_1_8_6;
  assign dpa_1_8_6 = {1'b0, dpa_terms_i[23][8]} + {1'b0, dpa_terms_i[24][8]} + {1'b0, dpa_terms_i[25][8]};
  wire [1:0] dpa_1_8_7;
  assign dpa_1_8_7 = {1'b0, dpa_terms_i[26][8]} + {1'b0, dpa_terms_i[27][8]} + {1'b0, dpa_terms_i[28][8]};
  wire [1:0] dpa_1_8_8;
  assign dpa_1_8_8 = {1'b0, dpa_terms_i[29][8]} + {1'b0, dpa_terms_i[30][8]} + {1'b0, dpa_terms_i[31][8]};
  wire [1:0] dpa_1_9_0;
  assign dpa_1_9_0 = {1'b0, dpa_0_8_0[1]} + {1'b0, dpa_0_8_1[1]} + {1'b0, dpa_0_8_2[1]};
  wire [1:0] dpa_1_9_1;
  assign dpa_1_9_1 = {1'b0, dpa_0_8_3[1]} + {1'b0, dpa_0_8_4[1]} + {1'b0, dpa_0_8_5[1]};
  wire [1:0] dpa_1_9_2;
  assign dpa_1_9_2 = {1'b0, dpa_0_9_0[0]} + {1'b0, dpa_0_9_1[0]} + {1'b0, dpa_0_9_2[0]};
  wire [1:0] dpa_1_9_3;
  assign dpa_1_9_3 = {1'b0, dpa_0_9_3[0]} + {1'b0, dpa_0_9_4[0]} + {1'b0, dpa_0_9_5[0]};
  wire [1:0] dpa_1_9_4;
  assign dpa_1_9_4 = {1'b0, dpa_terms_i[17][9]} + {1'b0, dpa_terms_i[18][9]} + {1'b0, dpa_terms_i[19][9]};
  wire [1:0] dpa_1_9_5;
  assign dpa_1_9_5 = {1'b0, dpa_terms_i[20][9]} + {1'b0, dpa_terms_i[21][9]} + {1'b0, dpa_terms_i[22][9]};
  wire [1:0] dpa_1_9_6;
  assign dpa_1_9_6 = {1'b0, dpa_terms_i[23][9]} + {1'b0, dpa_terms_i[24][9]} + {1'b0, dpa_terms_i[25][9]};
  wire [1:0] dpa_1_9_7;
  assign dpa_1_9_7 = {1'b0, dpa_terms_i[26][9]} + {1'b0, dpa_terms_i[27][9]} + {1'b0, dpa_terms_i[28][9]};
  wire [1:0] dpa_1_9_8;
  assign dpa_1_9_8 = {1'b0, dpa_terms_i[29][9]} + {1'b0, dpa_terms_i[30][9]} + {1'b0, dpa_terms_i[31][9]};
  wire [1:0] dpa_1_10_0;
  assign dpa_1_10_0 = {1'b0, dpa_0_9_0[1]} + {1'b0, dpa_0_9_1[1]} + {1'b0, dpa_0_9_2[1]};
  wire [1:0] dpa_1_10_1;
  assign dpa_1_10_1 = {1'b0, dpa_0_9_3[1]} + {1'b0, dpa_0_9_4[1]} + {1'b0, dpa_0_9_5[1]};
  wire [1:0] dpa_1_10_2;
  assign dpa_1_10_2 = {1'b0, dpa_0_10_0[0]} + {1'b0, dpa_0_10_1[0]} + {1'b0, dpa_0_10_2[0]};
  wire [1:0] dpa_1_10_3;
  assign dpa_1_10_3 = {1'b0, dpa_0_10_3[0]} + {1'b0, dpa_0_10_4[0]} + {1'b0, dpa_0_10_5[0]};
  wire [1:0] dpa_1_10_4;
  assign dpa_1_10_4 = {1'b0, dpa_terms_i[17][10]} + {1'b0, dpa_terms_i[18][10]} + {1'b0, dpa_terms_i[19][10]};
  wire [1:0] dpa_1_10_5;
  assign dpa_1_10_5 = {1'b0, dpa_terms_i[20][10]} + {1'b0, dpa_terms_i[21][10]} + {1'b0, dpa_terms_i[22][10]};
  wire [1:0] dpa_1_10_6;
  assign dpa_1_10_6 = {1'b0, dpa_terms_i[23][10]} + {1'b0, dpa_terms_i[24][10]} + {1'b0, dpa_terms_i[25][10]};
  wire [1:0] dpa_1_10_7;
  assign dpa_1_10_7 = {1'b0, dpa_terms_i[26][10]} + {1'b0, dpa_terms_i[27][10]} + {1'b0, dpa_terms_i[28][10]};
  wire [1:0] dpa_1_10_8;
  assign dpa_1_10_8 = {1'b0, dpa_terms_i[29][10]} + {1'b0, dpa_terms_i[30][10]} + {1'b0, dpa_terms_i[31][10]};
  wire [1:0] dpa_1_11_0;
  assign dpa_1_11_0 = {1'b0, dpa_0_10_0[1]} + {1'b0, dpa_0_10_1[1]} + {1'b0, dpa_0_10_2[1]};
  wire [1:0] dpa_1_11_1;
  assign dpa_1_11_1 = {1'b0, dpa_0_10_3[1]} + {1'b0, dpa_0_10_4[1]} + {1'b0, dpa_0_10_5[1]};
  wire [1:0] dpa_1_11_2;
  assign dpa_1_11_2 = {1'b0, dpa_0_11_0[0]} + {1'b0, dpa_0_11_1[0]} + {1'b0, dpa_0_11_2[0]};
  wire [1:0] dpa_1_11_3;
  assign dpa_1_11_3 = {1'b0, dpa_0_11_3[0]} + {1'b0, dpa_0_11_4[0]} + {1'b0, dpa_0_11_5[0]};
  wire [1:0] dpa_1_11_4;
  assign dpa_1_11_4 = {1'b0, dpa_terms_i[17][11]} + {1'b0, dpa_terms_i[18][11]} + {1'b0, dpa_terms_i[19][11]};
  wire [1:0] dpa_1_11_5;
  assign dpa_1_11_5 = {1'b0, dpa_terms_i[20][11]} + {1'b0, dpa_terms_i[21][11]} + {1'b0, dpa_terms_i[22][11]};
  wire [1:0] dpa_1_11_6;
  assign dpa_1_11_6 = {1'b0, dpa_terms_i[23][11]} + {1'b0, dpa_terms_i[24][11]} + {1'b0, dpa_terms_i[25][11]};
  wire [1:0] dpa_1_11_7;
  assign dpa_1_11_7 = {1'b0, dpa_terms_i[26][11]} + {1'b0, dpa_terms_i[27][11]} + {1'b0, dpa_terms_i[28][11]};
  wire [1:0] dpa_1_11_8;
  assign dpa_1_11_8 = {1'b0, dpa_terms_i[29][11]} + {1'b0, dpa_terms_i[30][11]} + {1'b0, dpa_terms_i[31][11]};
  wire [1:0] dpa_1_12_0;
  assign dpa_1_12_0 = {1'b0, dpa_0_11_0[1]} + {1'b0, dpa_0_11_1[1]} + {1'b0, dpa_0_11_2[1]};
  wire [1:0] dpa_1_12_1;
  assign dpa_1_12_1 = {1'b0, dpa_0_11_3[1]} + {1'b0, dpa_0_11_4[1]} + {1'b0, dpa_0_11_5[1]};
  wire [1:0] dpa_1_12_2;
  assign dpa_1_12_2 = {1'b0, dpa_0_12_0[0]} + {1'b0, dpa_0_12_1[0]} + {1'b0, dpa_0_12_2[0]};
  wire [1:0] dpa_1_12_3;
  assign dpa_1_12_3 = {1'b0, dpa_0_12_3[0]} + {1'b0, dpa_0_12_4[0]} + {1'b0, dpa_0_12_5[0]};
  wire [1:0] dpa_1_12_4;
  assign dpa_1_12_4 = {1'b0, dpa_terms_i[17][12]} + {1'b0, dpa_terms_i[18][12]} + {1'b0, dpa_terms_i[19][12]};
  wire [1:0] dpa_1_12_5;
  assign dpa_1_12_5 = {1'b0, dpa_terms_i[20][12]} + {1'b0, dpa_terms_i[21][12]} + {1'b0, dpa_terms_i[22][12]};
  wire [1:0] dpa_1_12_6;
  assign dpa_1_12_6 = {1'b0, dpa_terms_i[23][12]} + {1'b0, dpa_terms_i[24][12]} + {1'b0, dpa_terms_i[25][12]};
  wire [1:0] dpa_1_12_7;
  assign dpa_1_12_7 = {1'b0, dpa_terms_i[26][12]} + {1'b0, dpa_terms_i[27][12]} + {1'b0, dpa_terms_i[28][12]};
  wire [1:0] dpa_1_12_8;
  assign dpa_1_12_8 = {1'b0, dpa_terms_i[29][12]} + {1'b0, dpa_terms_i[30][12]} + {1'b0, dpa_terms_i[31][12]};
  wire [1:0] dpa_1_13_0;
  assign dpa_1_13_0 = {1'b0, dpa_0_12_0[1]} + {1'b0, dpa_0_12_1[1]} + {1'b0, dpa_0_12_2[1]};
  wire [1:0] dpa_1_13_1;
  assign dpa_1_13_1 = {1'b0, dpa_0_12_3[1]} + {1'b0, dpa_0_12_4[1]} + {1'b0, dpa_0_12_5[1]};
  wire [1:0] dpa_1_13_2;
  assign dpa_1_13_2 = {1'b0, dpa_0_13_0[0]} + {1'b0, dpa_0_13_1[0]} + {1'b0, dpa_0_13_2[0]};
  wire [1:0] dpa_1_13_3;
  assign dpa_1_13_3 = {1'b0, dpa_0_13_3[0]} + {1'b0, dpa_0_13_4[0]} + {1'b0, dpa_0_13_5[0]};
  wire [1:0] dpa_1_13_4;
  assign dpa_1_13_4 = {1'b0, dpa_terms_i[17][13]} + {1'b0, dpa_terms_i[18][13]} + {1'b0, dpa_terms_i[19][13]};
  wire [1:0] dpa_1_13_5;
  assign dpa_1_13_5 = {1'b0, dpa_terms_i[20][13]} + {1'b0, dpa_terms_i[21][13]} + {1'b0, dpa_terms_i[22][13]};
  wire [1:0] dpa_1_13_6;
  assign dpa_1_13_6 = {1'b0, dpa_terms_i[23][13]} + {1'b0, dpa_terms_i[24][13]} + {1'b0, dpa_terms_i[25][13]};
  wire [1:0] dpa_1_13_7;
  assign dpa_1_13_7 = {1'b0, dpa_terms_i[26][13]} + {1'b0, dpa_terms_i[27][13]} + {1'b0, dpa_terms_i[28][13]};
  wire [1:0] dpa_1_13_8;
  assign dpa_1_13_8 = {1'b0, dpa_terms_i[29][13]} + {1'b0, dpa_terms_i[30][13]} + {1'b0, dpa_terms_i[31][13]};
  wire [1:0] dpa_1_14_0;
  assign dpa_1_14_0 = {1'b0, dpa_0_13_0[1]} + {1'b0, dpa_0_13_1[1]} + {1'b0, dpa_0_13_2[1]};
  wire [1:0] dpa_1_14_1;
  assign dpa_1_14_1 = {1'b0, dpa_0_13_3[1]} + {1'b0, dpa_0_13_4[1]} + {1'b0, dpa_0_13_5[1]};
  wire [1:0] dpa_1_14_2;
  assign dpa_1_14_2 = {1'b0, dpa_0_14_0[0]} + {1'b0, dpa_0_14_1[0]} + {1'b0, dpa_0_14_2[0]};
  wire [1:0] dpa_1_14_3;
  assign dpa_1_14_3 = {1'b0, dpa_0_14_3[0]} + {1'b0, dpa_0_14_4[0]} + {1'b0, dpa_0_14_5[0]};
  wire [1:0] dpa_1_14_4;
  assign dpa_1_14_4 = {1'b0, dpa_terms_i[17][14]} + {1'b0, dpa_terms_i[18][14]} + {1'b0, dpa_terms_i[19][14]};
  wire [1:0] dpa_1_14_5;
  assign dpa_1_14_5 = {1'b0, dpa_terms_i[20][14]} + {1'b0, dpa_terms_i[21][14]} + {1'b0, dpa_terms_i[22][14]};
  wire [1:0] dpa_1_14_6;
  assign dpa_1_14_6 = {1'b0, dpa_terms_i[23][14]} + {1'b0, dpa_terms_i[24][14]} + {1'b0, dpa_terms_i[25][14]};
  wire [1:0] dpa_1_14_7;
  assign dpa_1_14_7 = {1'b0, dpa_terms_i[26][14]} + {1'b0, dpa_terms_i[27][14]} + {1'b0, dpa_terms_i[28][14]};
  wire [1:0] dpa_1_14_8;
  assign dpa_1_14_8 = {1'b0, dpa_terms_i[29][14]} + {1'b0, dpa_terms_i[30][14]} + {1'b0, dpa_terms_i[31][14]};
  wire [1:0] dpa_1_15_0;
  assign dpa_1_15_0 = {1'b0, dpa_0_14_0[1]} + {1'b0, dpa_0_14_1[1]} + {1'b0, dpa_0_14_2[1]};
  wire [1:0] dpa_1_15_1;
  assign dpa_1_15_1 = {1'b0, dpa_0_14_3[1]} + {1'b0, dpa_0_14_4[1]} + {1'b0, dpa_0_14_5[1]};
  wire [1:0] dpa_1_15_2;
  assign dpa_1_15_2 = {1'b0, dpa_0_15_0[0]} + {1'b0, dpa_0_15_1[0]} + {1'b0, dpa_0_15_2[0]};
  wire [1:0] dpa_1_15_3;
  assign dpa_1_15_3 = {1'b0, dpa_0_15_3[0]} + {1'b0, dpa_0_15_4[0]} + {1'b0, dpa_0_15_5[0]};
  wire [1:0] dpa_1_15_4;
  assign dpa_1_15_4 = {1'b0, dpa_terms_i[17][15]} + {1'b0, dpa_terms_i[18][15]} + {1'b0, dpa_terms_i[19][15]};
  wire [1:0] dpa_1_15_5;
  assign dpa_1_15_5 = {1'b0, dpa_terms_i[20][15]} + {1'b0, dpa_terms_i[21][15]} + {1'b0, dpa_terms_i[22][15]};
  wire [1:0] dpa_1_15_6;
  assign dpa_1_15_6 = {1'b0, dpa_terms_i[23][15]} + {1'b0, dpa_terms_i[24][15]} + {1'b0, dpa_terms_i[25][15]};
  wire [1:0] dpa_1_15_7;
  assign dpa_1_15_7 = {1'b0, dpa_terms_i[26][15]} + {1'b0, dpa_terms_i[27][15]} + {1'b0, dpa_terms_i[28][15]};
  wire [1:0] dpa_1_15_8;
  assign dpa_1_15_8 = {1'b0, dpa_terms_i[29][15]} + {1'b0, dpa_terms_i[30][15]} + {1'b0, dpa_terms_i[31][15]};
  wire [1:0] dpa_1_16_0;
  assign dpa_1_16_0 = {1'b0, dpa_0_15_0[1]} + {1'b0, dpa_0_15_1[1]} + {1'b0, dpa_0_15_2[1]};
  wire [1:0] dpa_1_16_1;
  assign dpa_1_16_1 = {1'b0, dpa_0_15_3[1]} + {1'b0, dpa_0_15_4[1]} + {1'b0, dpa_0_15_5[1]};
  wire [1:0] dpa_1_16_2;
  assign dpa_1_16_2 = {1'b0, dpa_0_16_0[0]} + {1'b0, dpa_0_16_1[0]} + {1'b0, dpa_0_16_2[0]};
  wire [1:0] dpa_1_16_3;
  assign dpa_1_16_3 = {1'b0, dpa_0_16_3[0]} + {1'b0, dpa_0_16_4[0]} + {1'b0, dpa_0_16_5[0]};
  wire [1:0] dpa_1_16_4;
  assign dpa_1_16_4 = {1'b0, dpa_terms_i[17][16]} + {1'b0, dpa_terms_i[18][16]} + {1'b0, dpa_terms_i[19][16]};
  wire [1:0] dpa_1_16_5;
  assign dpa_1_16_5 = {1'b0, dpa_terms_i[20][16]} + {1'b0, dpa_terms_i[21][16]} + {1'b0, dpa_terms_i[22][16]};
  wire [1:0] dpa_1_16_6;
  assign dpa_1_16_6 = {1'b0, dpa_terms_i[23][16]} + {1'b0, dpa_terms_i[24][16]} + {1'b0, dpa_terms_i[25][16]};
  wire [1:0] dpa_1_16_7;
  assign dpa_1_16_7 = {1'b0, dpa_terms_i[26][16]} + {1'b0, dpa_terms_i[27][16]} + {1'b0, dpa_terms_i[28][16]};
  wire [1:0] dpa_1_16_8;
  assign dpa_1_16_8 = {1'b0, dpa_terms_i[29][16]} + {1'b0, dpa_terms_i[30][16]} + {1'b0, dpa_terms_i[31][16]};
  wire [1:0] dpa_1_17_0;
  assign dpa_1_17_0 = {1'b0, dpa_0_16_0[1]} + {1'b0, dpa_0_16_1[1]} + {1'b0, dpa_0_16_2[1]};
  wire [1:0] dpa_1_17_1;
  assign dpa_1_17_1 = {1'b0, dpa_0_16_3[1]} + {1'b0, dpa_0_16_4[1]} + {1'b0, dpa_0_16_5[1]};
  wire [1:0] dpa_1_17_2;
  assign dpa_1_17_2 = {1'b0, dpa_0_17_0[0]} + {1'b0, dpa_0_17_1[0]} + {1'b0, dpa_0_17_2[0]};
  wire [1:0] dpa_1_17_3;
  assign dpa_1_17_3 = {1'b0, dpa_0_17_3[0]} + {1'b0, dpa_0_17_4[0]} + {1'b0, dpa_0_17_5[0]};
  wire [1:0] dpa_1_17_4;
  assign dpa_1_17_4 = {1'b0, dpa_terms_i[17][17]} + {1'b0, dpa_terms_i[18][17]} + {1'b0, dpa_terms_i[19][17]};
  wire [1:0] dpa_1_17_5;
  assign dpa_1_17_5 = {1'b0, dpa_terms_i[20][17]} + {1'b0, dpa_terms_i[21][17]} + {1'b0, dpa_terms_i[22][17]};
  wire [1:0] dpa_1_17_6;
  assign dpa_1_17_6 = {1'b0, dpa_terms_i[23][17]} + {1'b0, dpa_terms_i[24][17]} + {1'b0, dpa_terms_i[25][17]};
  wire [1:0] dpa_1_17_7;
  assign dpa_1_17_7 = {1'b0, dpa_terms_i[26][17]} + {1'b0, dpa_terms_i[27][17]} + {1'b0, dpa_terms_i[28][17]};
  wire [1:0] dpa_1_17_8;
  assign dpa_1_17_8 = {1'b0, dpa_terms_i[29][17]} + {1'b0, dpa_terms_i[30][17]} + {1'b0, dpa_terms_i[31][17]};
  wire [1:0] dpa_1_18_0;
  assign dpa_1_18_0 = {1'b0, dpa_0_17_0[1]} + {1'b0, dpa_0_17_1[1]} + {1'b0, dpa_0_17_2[1]};
  wire [1:0] dpa_1_18_1;
  assign dpa_1_18_1 = {1'b0, dpa_0_17_3[1]} + {1'b0, dpa_0_17_4[1]} + {1'b0, dpa_0_17_5[1]};
  wire [1:0] dpa_1_18_2;
  assign dpa_1_18_2 = {1'b0, dpa_0_18_0[0]} + {1'b0, dpa_0_18_1[0]} + {1'b0, dpa_0_18_2[0]};
  wire [1:0] dpa_1_18_3;
  assign dpa_1_18_3 = {1'b0, dpa_0_18_3[0]} + {1'b0, dpa_0_18_4[0]} + {1'b0, dpa_0_18_5[0]};
  wire [1:0] dpa_1_18_4;
  assign dpa_1_18_4 = {1'b0, dpa_terms_i[17][18]} + {1'b0, dpa_terms_i[18][18]} + {1'b0, dpa_terms_i[19][18]};
  wire [1:0] dpa_1_18_5;
  assign dpa_1_18_5 = {1'b0, dpa_terms_i[20][18]} + {1'b0, dpa_terms_i[21][18]} + {1'b0, dpa_terms_i[22][18]};
  wire [1:0] dpa_1_18_6;
  assign dpa_1_18_6 = {1'b0, dpa_terms_i[23][18]} + {1'b0, dpa_terms_i[24][18]} + {1'b0, dpa_terms_i[25][18]};
  wire [1:0] dpa_1_18_7;
  assign dpa_1_18_7 = {1'b0, dpa_terms_i[26][18]} + {1'b0, dpa_terms_i[27][18]} + {1'b0, dpa_terms_i[28][18]};
  wire [1:0] dpa_1_18_8;
  assign dpa_1_18_8 = {1'b0, dpa_terms_i[29][18]} + {1'b0, dpa_terms_i[30][18]} + {1'b0, dpa_terms_i[31][18]};
  wire [1:0] dpa_1_19_0;
  assign dpa_1_19_0 = {1'b0, dpa_0_18_0[1]} + {1'b0, dpa_0_18_1[1]} + {1'b0, dpa_0_18_2[1]};
  wire [1:0] dpa_1_19_1;
  assign dpa_1_19_1 = {1'b0, dpa_0_18_3[1]} + {1'b0, dpa_0_18_4[1]} + {1'b0, dpa_0_18_5[1]};
  wire [1:0] dpa_1_19_2;
  assign dpa_1_19_2 = {1'b0, dpa_0_19_0[0]} + {1'b0, dpa_0_19_1[0]} + {1'b0, dpa_0_19_2[0]};
  wire [1:0] dpa_1_19_3;
  assign dpa_1_19_3 = {1'b0, dpa_0_19_3[0]} + {1'b0, dpa_0_19_4[0]} + {1'b0, dpa_0_19_5[0]};
  wire [1:0] dpa_1_19_4;
  assign dpa_1_19_4 = {1'b0, dpa_terms_i[17][19]} + {1'b0, dpa_terms_i[18][19]} + {1'b0, dpa_terms_i[19][19]};
  wire [1:0] dpa_1_19_5;
  assign dpa_1_19_5 = {1'b0, dpa_terms_i[20][19]} + {1'b0, dpa_terms_i[21][19]} + {1'b0, dpa_terms_i[22][19]};
  wire [1:0] dpa_1_19_6;
  assign dpa_1_19_6 = {1'b0, dpa_terms_i[23][19]} + {1'b0, dpa_terms_i[24][19]} + {1'b0, dpa_terms_i[25][19]};
  wire [1:0] dpa_1_19_7;
  assign dpa_1_19_7 = {1'b0, dpa_terms_i[26][19]} + {1'b0, dpa_terms_i[27][19]} + {1'b0, dpa_terms_i[28][19]};
  wire [1:0] dpa_1_19_8;
  assign dpa_1_19_8 = {1'b0, dpa_terms_i[29][19]} + {1'b0, dpa_terms_i[30][19]} + {1'b0, dpa_terms_i[31][19]};
  wire [1:0] dpa_1_20_0;
  assign dpa_1_20_0 = {1'b0, dpa_0_19_0[1]} + {1'b0, dpa_0_19_1[1]} + {1'b0, dpa_0_19_2[1]};
  wire [1:0] dpa_1_20_1;
  assign dpa_1_20_1 = {1'b0, dpa_0_19_3[1]} + {1'b0, dpa_0_19_4[1]} + {1'b0, dpa_0_19_5[1]};
  wire [1:0] dpa_1_20_2;
  assign dpa_1_20_2 = {1'b0, dpa_0_20_0[0]} + {1'b0, dpa_0_20_1[0]} + {1'b0, dpa_0_20_2[0]};
  wire [1:0] dpa_1_20_3;
  assign dpa_1_20_3 = {1'b0, dpa_0_20_3[0]} + {1'b0, dpa_0_20_4[0]} + {1'b0, dpa_0_20_5[0]};
  wire [1:0] dpa_1_20_4;
  assign dpa_1_20_4 = {1'b0, dpa_terms_i[17][20]} + {1'b0, dpa_terms_i[18][20]} + {1'b0, dpa_terms_i[19][20]};
  wire [1:0] dpa_1_20_5;
  assign dpa_1_20_5 = {1'b0, dpa_terms_i[20][20]} + {1'b0, dpa_terms_i[21][20]} + {1'b0, dpa_terms_i[22][20]};
  wire [1:0] dpa_1_20_6;
  assign dpa_1_20_6 = {1'b0, dpa_terms_i[23][20]} + {1'b0, dpa_terms_i[24][20]} + {1'b0, dpa_terms_i[25][20]};
  wire [1:0] dpa_1_20_7;
  assign dpa_1_20_7 = {1'b0, dpa_terms_i[26][20]} + {1'b0, dpa_terms_i[27][20]} + {1'b0, dpa_terms_i[28][20]};
  wire [1:0] dpa_1_20_8;
  assign dpa_1_20_8 = {1'b0, dpa_terms_i[29][20]} + {1'b0, dpa_terms_i[30][20]} + {1'b0, dpa_terms_i[31][20]};
  wire [1:0] dpa_1_21_0;
  assign dpa_1_21_0 = {1'b0, dpa_0_20_0[1]} + {1'b0, dpa_0_20_1[1]} + {1'b0, dpa_0_20_2[1]};
  wire [1:0] dpa_1_21_1;
  assign dpa_1_21_1 = {1'b0, dpa_0_20_3[1]} + {1'b0, dpa_0_20_4[1]} + {1'b0, dpa_0_20_5[1]};
  wire [1:0] dpa_1_21_2;
  assign dpa_1_21_2 = {1'b0, dpa_0_21_0[0]} + {1'b0, dpa_0_21_1[0]} + {1'b0, dpa_0_21_2[0]};
  wire [1:0] dpa_1_21_3;
  assign dpa_1_21_3 = {1'b0, dpa_0_21_3[0]} + {1'b0, dpa_0_21_4[0]} + {1'b0, dpa_0_21_5[0]};
  wire [1:0] dpa_1_21_4;
  assign dpa_1_21_4 = {1'b0, dpa_terms_i[17][21]} + {1'b0, dpa_terms_i[18][21]} + {1'b0, dpa_terms_i[19][21]};
  wire [1:0] dpa_1_21_5;
  assign dpa_1_21_5 = {1'b0, dpa_terms_i[20][21]} + {1'b0, dpa_terms_i[21][21]} + {1'b0, dpa_terms_i[22][21]};
  wire [1:0] dpa_1_21_6;
  assign dpa_1_21_6 = {1'b0, dpa_terms_i[23][21]} + {1'b0, dpa_terms_i[24][21]} + {1'b0, dpa_terms_i[25][21]};
  wire [1:0] dpa_1_21_7;
  assign dpa_1_21_7 = {1'b0, dpa_terms_i[26][21]} + {1'b0, dpa_terms_i[27][21]} + {1'b0, dpa_terms_i[28][21]};
  wire [1:0] dpa_1_21_8;
  assign dpa_1_21_8 = {1'b0, dpa_terms_i[29][21]} + {1'b0, dpa_terms_i[30][21]} + {1'b0, dpa_terms_i[31][21]};
  wire [1:0] dpa_1_22_0;
  assign dpa_1_22_0 = {1'b0, dpa_0_21_0[1]} + {1'b0, dpa_0_21_1[1]} + {1'b0, dpa_0_21_2[1]};
  wire [1:0] dpa_1_22_1;
  assign dpa_1_22_1 = {1'b0, dpa_0_21_3[1]} + {1'b0, dpa_0_21_4[1]} + {1'b0, dpa_0_21_5[1]};
  wire [1:0] dpa_1_22_2;
  assign dpa_1_22_2 = {1'b0, dpa_0_22_0[0]} + {1'b0, dpa_0_22_1[0]} + {1'b0, dpa_0_22_2[0]};
  wire [1:0] dpa_1_22_3;
  assign dpa_1_22_3 = {1'b0, dpa_0_22_3[0]} + {1'b0, dpa_0_22_4[0]} + {1'b0, dpa_0_22_5[0]};
  wire [1:0] dpa_1_22_4;
  assign dpa_1_22_4 = {1'b0, dpa_terms_i[17][22]} + {1'b0, dpa_terms_i[18][22]} + {1'b0, dpa_terms_i[19][22]};
  wire [1:0] dpa_1_22_5;
  assign dpa_1_22_5 = {1'b0, dpa_terms_i[20][22]} + {1'b0, dpa_terms_i[21][22]} + {1'b0, dpa_terms_i[22][22]};
  wire [1:0] dpa_1_22_6;
  assign dpa_1_22_6 = {1'b0, dpa_terms_i[23][22]} + {1'b0, dpa_terms_i[24][22]} + {1'b0, dpa_terms_i[25][22]};
  wire [1:0] dpa_1_22_7;
  assign dpa_1_22_7 = {1'b0, dpa_terms_i[26][22]} + {1'b0, dpa_terms_i[27][22]} + {1'b0, dpa_terms_i[28][22]};
  wire [1:0] dpa_1_22_8;
  assign dpa_1_22_8 = {1'b0, dpa_terms_i[29][22]} + {1'b0, dpa_terms_i[30][22]} + {1'b0, dpa_terms_i[31][22]};
  wire [1:0] dpa_1_23_0;
  assign dpa_1_23_0 = {1'b0, dpa_0_22_0[1]} + {1'b0, dpa_0_22_1[1]} + {1'b0, dpa_0_22_2[1]};
  wire [1:0] dpa_1_23_1;
  assign dpa_1_23_1 = {1'b0, dpa_0_22_3[1]} + {1'b0, dpa_0_22_4[1]} + {1'b0, dpa_0_22_5[1]};
  wire [1:0] dpa_1_23_2;
  assign dpa_1_23_2 = {1'b0, dpa_0_23_0[0]} + {1'b0, dpa_0_23_1[0]} + {1'b0, dpa_0_23_2[0]};
  wire [1:0] dpa_1_23_3;
  assign dpa_1_23_3 = {1'b0, dpa_0_23_3[0]} + {1'b0, dpa_0_23_4[0]} + {1'b0, dpa_0_23_5[0]};
  wire [1:0] dpa_1_23_4;
  assign dpa_1_23_4 = {1'b0, dpa_terms_i[17][23]} + {1'b0, dpa_terms_i[18][23]} + {1'b0, dpa_terms_i[19][23]};
  wire [1:0] dpa_1_23_5;
  assign dpa_1_23_5 = {1'b0, dpa_terms_i[20][23]} + {1'b0, dpa_terms_i[21][23]} + {1'b0, dpa_terms_i[22][23]};
  wire [1:0] dpa_1_23_6;
  assign dpa_1_23_6 = {1'b0, dpa_terms_i[23][23]} + {1'b0, dpa_terms_i[24][23]} + {1'b0, dpa_terms_i[25][23]};
  wire [1:0] dpa_1_23_7;
  assign dpa_1_23_7 = {1'b0, dpa_terms_i[26][23]} + {1'b0, dpa_terms_i[27][23]} + {1'b0, dpa_terms_i[28][23]};
  wire [1:0] dpa_1_23_8;
  assign dpa_1_23_8 = {1'b0, dpa_terms_i[29][23]} + {1'b0, dpa_terms_i[30][23]} + {1'b0, dpa_terms_i[31][23]};
  wire [1:0] dpa_1_24_0;
  assign dpa_1_24_0 = {1'b0, dpa_0_23_0[1]} + {1'b0, dpa_0_23_1[1]} + {1'b0, dpa_0_23_2[1]};
  wire [1:0] dpa_1_24_1;
  assign dpa_1_24_1 = {1'b0, dpa_0_23_3[1]} + {1'b0, dpa_0_23_4[1]} + {1'b0, dpa_0_23_5[1]};
  wire [1:0] dpa_1_24_2;
  assign dpa_1_24_2 = {1'b0, dpa_0_24_0[0]} + {1'b0, dpa_0_24_1[0]} + {1'b0, dpa_0_24_2[0]};
  wire [1:0] dpa_1_24_3;
  assign dpa_1_24_3 = {1'b0, dpa_0_24_3[0]} + {1'b0, dpa_0_24_4[0]} + {1'b0, dpa_0_24_5[0]};
  wire [1:0] dpa_1_24_4;
  assign dpa_1_24_4 = {1'b0, dpa_terms_i[17][24]} + {1'b0, dpa_terms_i[18][24]} + {1'b0, dpa_terms_i[19][24]};
  wire [1:0] dpa_1_24_5;
  assign dpa_1_24_5 = {1'b0, dpa_terms_i[20][24]} + {1'b0, dpa_terms_i[21][24]} + {1'b0, dpa_terms_i[22][24]};
  wire [1:0] dpa_1_24_6;
  assign dpa_1_24_6 = {1'b0, dpa_terms_i[23][24]} + {1'b0, dpa_terms_i[24][24]} + {1'b0, dpa_terms_i[25][24]};
  wire [1:0] dpa_1_24_7;
  assign dpa_1_24_7 = {1'b0, dpa_terms_i[26][24]} + {1'b0, dpa_terms_i[27][24]} + {1'b0, dpa_terms_i[28][24]};
  wire [1:0] dpa_1_24_8;
  assign dpa_1_24_8 = {1'b0, dpa_terms_i[29][24]} + {1'b0, dpa_terms_i[30][24]} + {1'b0, dpa_terms_i[31][24]};
  wire [1:0] dpa_1_25_0;
  assign dpa_1_25_0 = {1'b0, dpa_0_24_0[1]} + {1'b0, dpa_0_24_1[1]} + {1'b0, dpa_0_24_2[1]};
  wire [1:0] dpa_1_25_1;
  assign dpa_1_25_1 = {1'b0, dpa_0_24_3[1]} + {1'b0, dpa_0_24_4[1]} + {1'b0, dpa_0_24_5[1]};
  wire [1:0] dpa_1_25_2;
  assign dpa_1_25_2 = {1'b0, dpa_0_25_0[0]} + {1'b0, dpa_0_25_1[0]} + {1'b0, dpa_0_25_2[0]};
  wire [1:0] dpa_1_25_3;
  assign dpa_1_25_3 = {1'b0, dpa_0_25_3[0]} + {1'b0, dpa_0_25_4[0]} + {1'b0, dpa_0_25_5[0]};
  wire [1:0] dpa_1_25_4;
  assign dpa_1_25_4 = {1'b0, dpa_terms_i[17][25]} + {1'b0, dpa_terms_i[18][25]} + {1'b0, dpa_terms_i[19][25]};
  wire [1:0] dpa_1_25_5;
  assign dpa_1_25_5 = {1'b0, dpa_terms_i[20][25]} + {1'b0, dpa_terms_i[21][25]} + {1'b0, dpa_terms_i[22][25]};
  wire [1:0] dpa_1_25_6;
  assign dpa_1_25_6 = {1'b0, dpa_terms_i[23][25]} + {1'b0, dpa_terms_i[24][25]} + {1'b0, dpa_terms_i[25][25]};
  wire [1:0] dpa_1_25_7;
  assign dpa_1_25_7 = {1'b0, dpa_terms_i[26][25]} + {1'b0, dpa_terms_i[27][25]} + {1'b0, dpa_terms_i[28][25]};
  wire [1:0] dpa_1_25_8;
  assign dpa_1_25_8 = {1'b0, dpa_terms_i[29][25]} + {1'b0, dpa_terms_i[30][25]} + {1'b0, dpa_terms_i[31][25]};
  wire [1:0] dpa_1_26_0;
  assign dpa_1_26_0 = {1'b0, dpa_0_25_0[1]} + {1'b0, dpa_0_25_1[1]} + {1'b0, dpa_0_25_2[1]};
  wire [1:0] dpa_1_26_1;
  assign dpa_1_26_1 = {1'b0, dpa_0_25_3[1]} + {1'b0, dpa_0_25_4[1]} + {1'b0, dpa_0_25_5[1]};
  wire [1:0] dpa_1_26_2;
  assign dpa_1_26_2 = {1'b0, dpa_0_26_0[0]} + {1'b0, dpa_0_26_1[0]} + {1'b0, dpa_0_26_2[0]};
  wire [1:0] dpa_1_26_3;
  assign dpa_1_26_3 = {1'b0, dpa_0_26_3[0]} + {1'b0, dpa_0_26_4[0]} + {1'b0, dpa_0_26_5[0]};
  wire [1:0] dpa_1_26_4;
  assign dpa_1_26_4 = {1'b0, dpa_terms_i[17][26]} + {1'b0, dpa_terms_i[18][26]} + {1'b0, dpa_terms_i[19][26]};
  wire [1:0] dpa_1_26_5;
  assign dpa_1_26_5 = {1'b0, dpa_terms_i[20][26]} + {1'b0, dpa_terms_i[21][26]} + {1'b0, dpa_terms_i[22][26]};
  wire [1:0] dpa_1_26_6;
  assign dpa_1_26_6 = {1'b0, dpa_terms_i[23][26]} + {1'b0, dpa_terms_i[24][26]} + {1'b0, dpa_terms_i[25][26]};
  wire [1:0] dpa_1_26_7;
  assign dpa_1_26_7 = {1'b0, dpa_terms_i[26][26]} + {1'b0, dpa_terms_i[27][26]} + {1'b0, dpa_terms_i[28][26]};
  wire [1:0] dpa_1_26_8;
  assign dpa_1_26_8 = {1'b0, dpa_terms_i[29][26]} + {1'b0, dpa_terms_i[30][26]} + {1'b0, dpa_terms_i[31][26]};
  wire [1:0] dpa_2_0_0;
  assign dpa_2_0_0 = {1'b0, dpa_1_0_0[0]} + {1'b0, dpa_1_0_1[0]} + {1'b0, dpa_1_0_2[0]};
  wire [1:0] dpa_2_0_1;
  assign dpa_2_0_1 = {1'b0, dpa_1_0_3[0]} + {1'b0, dpa_1_0_4[0]} + {1'b0, dpa_terms_i[20][0]};
  wire [1:0] dpa_2_0_2;
  assign dpa_2_0_2 = {1'b0, dpa_terms_i[21][0]} + {1'b0, dpa_terms_i[22][0]} + {1'b0, dpa_terms_i[23][0]};
  wire [1:0] dpa_2_1_0;
  assign dpa_2_1_0 = {1'b0, dpa_1_0_0[1]} + {1'b0, dpa_1_0_1[1]} + {1'b0, dpa_1_0_2[1]};
  wire [1:0] dpa_2_1_1;
  assign dpa_2_1_1 = {1'b0, dpa_1_0_3[1]} + {1'b0, dpa_1_0_4[1]} + {1'b0, dpa_1_1_0[0]};
  wire [1:0] dpa_2_1_2;
  assign dpa_2_1_2 = {1'b0, dpa_1_1_1[0]} + {1'b0, dpa_1_1_2[0]} + {1'b0, dpa_1_1_3[0]};
  wire [1:0] dpa_2_1_3;
  assign dpa_2_1_3 = {1'b0, dpa_1_1_4[0]} + {1'b0, dpa_1_1_5[0]} + {1'b0, dpa_1_1_6[0]};
  wire [1:0] dpa_2_1_4;
  assign dpa_2_1_4 = {1'b0, dpa_terms_i[27][1]} + {1'b0, dpa_terms_i[28][1]};
  wire [1:0] dpa_2_2_0;
  assign dpa_2_2_0 = {1'b0, dpa_1_1_0[1]} + {1'b0, dpa_1_1_1[1]} + {1'b0, dpa_1_1_2[1]};
  wire [1:0] dpa_2_2_1;
  assign dpa_2_2_1 = {1'b0, dpa_1_1_3[1]} + {1'b0, dpa_1_1_4[1]} + {1'b0, dpa_1_1_5[1]};
  wire [1:0] dpa_2_2_2;
  assign dpa_2_2_2 = {1'b0, dpa_1_1_6[1]} + {1'b0, dpa_1_2_0[0]} + {1'b0, dpa_1_2_1[0]};
  wire [1:0] dpa_2_2_3;
  assign dpa_2_2_3 = {1'b0, dpa_1_2_2[0]} + {1'b0, dpa_1_2_3[0]} + {1'b0, dpa_1_2_4[0]};
  wire [1:0] dpa_2_2_4;
  assign dpa_2_2_4 = {1'b0, dpa_1_2_5[0]} + {1'b0, dpa_1_2_6[0]} + {1'b0, dpa_1_2_7[0]};
  wire [1:0] dpa_2_2_5;
  assign dpa_2_2_5 = {1'b0, dpa_terms_i[30][2]} + {1'b0, dpa_terms_i[31][2]};
  wire [1:0] dpa_2_3_0;
  assign dpa_2_3_0 = {1'b0, dpa_1_2_0[1]} + {1'b0, dpa_1_2_1[1]} + {1'b0, dpa_1_2_2[1]};
  wire [1:0] dpa_2_3_1;
  assign dpa_2_3_1 = {1'b0, dpa_1_2_3[1]} + {1'b0, dpa_1_2_4[1]} + {1'b0, dpa_1_2_5[1]};
  wire [1:0] dpa_2_3_2;
  assign dpa_2_3_2 = {1'b0, dpa_1_2_6[1]} + {1'b0, dpa_1_2_7[1]} + {1'b0, dpa_1_3_0[0]};
  wire [1:0] dpa_2_3_3;
  assign dpa_2_3_3 = {1'b0, dpa_1_3_1[0]} + {1'b0, dpa_1_3_2[0]} + {1'b0, dpa_1_3_3[0]};
  wire [1:0] dpa_2_3_4;
  assign dpa_2_3_4 = {1'b0, dpa_1_3_4[0]} + {1'b0, dpa_1_3_5[0]} + {1'b0, dpa_1_3_6[0]};
  wire [1:0] dpa_2_3_5;
  assign dpa_2_3_5 = {1'b0, dpa_1_3_7[0]} + {1'b0, dpa_1_3_8[0]} + {1'b0, dpa_terms_i[32][3]};
  wire [1:0] dpa_2_4_0;
  assign dpa_2_4_0 = {1'b0, dpa_1_3_0[1]} + {1'b0, dpa_1_3_1[1]} + {1'b0, dpa_1_3_2[1]};
  wire [1:0] dpa_2_4_1;
  assign dpa_2_4_1 = {1'b0, dpa_1_3_3[1]} + {1'b0, dpa_1_3_4[1]} + {1'b0, dpa_1_3_5[1]};
  wire [1:0] dpa_2_4_2;
  assign dpa_2_4_2 = {1'b0, dpa_1_3_6[1]} + {1'b0, dpa_1_3_7[1]} + {1'b0, dpa_1_3_8[1]};
  wire [1:0] dpa_2_4_3;
  assign dpa_2_4_3 = {1'b0, dpa_1_4_0[0]} + {1'b0, dpa_1_4_1[0]} + {1'b0, dpa_1_4_2[0]};
  wire [1:0] dpa_2_4_4;
  assign dpa_2_4_4 = {1'b0, dpa_1_4_3[0]} + {1'b0, dpa_1_4_4[0]} + {1'b0, dpa_1_4_5[0]};
  wire [1:0] dpa_2_4_5;
  assign dpa_2_4_5 = {1'b0, dpa_1_4_6[0]} + {1'b0, dpa_1_4_7[0]} + {1'b0, dpa_1_4_8[0]};
  wire [1:0] dpa_2_5_0;
  assign dpa_2_5_0 = {1'b0, dpa_1_4_0[1]} + {1'b0, dpa_1_4_1[1]} + {1'b0, dpa_1_4_2[1]};
  wire [1:0] dpa_2_5_1;
  assign dpa_2_5_1 = {1'b0, dpa_1_4_3[1]} + {1'b0, dpa_1_4_4[1]} + {1'b0, dpa_1_4_5[1]};
  wire [1:0] dpa_2_5_2;
  assign dpa_2_5_2 = {1'b0, dpa_1_4_6[1]} + {1'b0, dpa_1_4_7[1]} + {1'b0, dpa_1_4_8[1]};
  wire [1:0] dpa_2_5_3;
  assign dpa_2_5_3 = {1'b0, dpa_1_5_0[0]} + {1'b0, dpa_1_5_1[0]} + {1'b0, dpa_1_5_2[0]};
  wire [1:0] dpa_2_5_4;
  assign dpa_2_5_4 = {1'b0, dpa_1_5_3[0]} + {1'b0, dpa_1_5_4[0]} + {1'b0, dpa_1_5_5[0]};
  wire [1:0] dpa_2_5_5;
  assign dpa_2_5_5 = {1'b0, dpa_1_5_6[0]} + {1'b0, dpa_1_5_7[0]} + {1'b0, dpa_1_5_8[0]};
  wire [1:0] dpa_2_6_0;
  assign dpa_2_6_0 = {1'b0, dpa_1_5_0[1]} + {1'b0, dpa_1_5_1[1]} + {1'b0, dpa_1_5_2[1]};
  wire [1:0] dpa_2_6_1;
  assign dpa_2_6_1 = {1'b0, dpa_1_5_3[1]} + {1'b0, dpa_1_5_4[1]} + {1'b0, dpa_1_5_5[1]};
  wire [1:0] dpa_2_6_2;
  assign dpa_2_6_2 = {1'b0, dpa_1_5_6[1]} + {1'b0, dpa_1_5_7[1]} + {1'b0, dpa_1_5_8[1]};
  wire [1:0] dpa_2_6_3;
  assign dpa_2_6_3 = {1'b0, dpa_1_6_0[0]} + {1'b0, dpa_1_6_1[0]} + {1'b0, dpa_1_6_2[0]};
  wire [1:0] dpa_2_6_4;
  assign dpa_2_6_4 = {1'b0, dpa_1_6_3[0]} + {1'b0, dpa_1_6_4[0]} + {1'b0, dpa_1_6_5[0]};
  wire [1:0] dpa_2_6_5;
  assign dpa_2_6_5 = {1'b0, dpa_1_6_6[0]} + {1'b0, dpa_1_6_7[0]} + {1'b0, dpa_1_6_8[0]};
  wire [1:0] dpa_2_7_0;
  assign dpa_2_7_0 = {1'b0, dpa_1_6_0[1]} + {1'b0, dpa_1_6_1[1]} + {1'b0, dpa_1_6_2[1]};
  wire [1:0] dpa_2_7_1;
  assign dpa_2_7_1 = {1'b0, dpa_1_6_3[1]} + {1'b0, dpa_1_6_4[1]} + {1'b0, dpa_1_6_5[1]};
  wire [1:0] dpa_2_7_2;
  assign dpa_2_7_2 = {1'b0, dpa_1_6_6[1]} + {1'b0, dpa_1_6_7[1]} + {1'b0, dpa_1_6_8[1]};
  wire [1:0] dpa_2_7_3;
  assign dpa_2_7_3 = {1'b0, dpa_1_7_0[0]} + {1'b0, dpa_1_7_1[0]} + {1'b0, dpa_1_7_2[0]};
  wire [1:0] dpa_2_7_4;
  assign dpa_2_7_4 = {1'b0, dpa_1_7_3[0]} + {1'b0, dpa_1_7_4[0]} + {1'b0, dpa_1_7_5[0]};
  wire [1:0] dpa_2_7_5;
  assign dpa_2_7_5 = {1'b0, dpa_1_7_6[0]} + {1'b0, dpa_1_7_7[0]} + {1'b0, dpa_1_7_8[0]};
  wire [1:0] dpa_2_8_0;
  assign dpa_2_8_0 = {1'b0, dpa_1_7_0[1]} + {1'b0, dpa_1_7_1[1]} + {1'b0, dpa_1_7_2[1]};
  wire [1:0] dpa_2_8_1;
  assign dpa_2_8_1 = {1'b0, dpa_1_7_3[1]} + {1'b0, dpa_1_7_4[1]} + {1'b0, dpa_1_7_5[1]};
  wire [1:0] dpa_2_8_2;
  assign dpa_2_8_2 = {1'b0, dpa_1_7_6[1]} + {1'b0, dpa_1_7_7[1]} + {1'b0, dpa_1_7_8[1]};
  wire [1:0] dpa_2_8_3;
  assign dpa_2_8_3 = {1'b0, dpa_1_8_0[0]} + {1'b0, dpa_1_8_1[0]} + {1'b0, dpa_1_8_2[0]};
  wire [1:0] dpa_2_8_4;
  assign dpa_2_8_4 = {1'b0, dpa_1_8_3[0]} + {1'b0, dpa_1_8_4[0]} + {1'b0, dpa_1_8_5[0]};
  wire [1:0] dpa_2_8_5;
  assign dpa_2_8_5 = {1'b0, dpa_1_8_6[0]} + {1'b0, dpa_1_8_7[0]} + {1'b0, dpa_1_8_8[0]};
  wire [1:0] dpa_2_9_0;
  assign dpa_2_9_0 = {1'b0, dpa_1_8_0[1]} + {1'b0, dpa_1_8_1[1]} + {1'b0, dpa_1_8_2[1]};
  wire [1:0] dpa_2_9_1;
  assign dpa_2_9_1 = {1'b0, dpa_1_8_3[1]} + {1'b0, dpa_1_8_4[1]} + {1'b0, dpa_1_8_5[1]};
  wire [1:0] dpa_2_9_2;
  assign dpa_2_9_2 = {1'b0, dpa_1_8_6[1]} + {1'b0, dpa_1_8_7[1]} + {1'b0, dpa_1_8_8[1]};
  wire [1:0] dpa_2_9_3;
  assign dpa_2_9_3 = {1'b0, dpa_1_9_0[0]} + {1'b0, dpa_1_9_1[0]} + {1'b0, dpa_1_9_2[0]};
  wire [1:0] dpa_2_9_4;
  assign dpa_2_9_4 = {1'b0, dpa_1_9_3[0]} + {1'b0, dpa_1_9_4[0]} + {1'b0, dpa_1_9_5[0]};
  wire [1:0] dpa_2_9_5;
  assign dpa_2_9_5 = {1'b0, dpa_1_9_6[0]} + {1'b0, dpa_1_9_7[0]} + {1'b0, dpa_1_9_8[0]};
  wire [1:0] dpa_2_10_0;
  assign dpa_2_10_0 = {1'b0, dpa_1_9_0[1]} + {1'b0, dpa_1_9_1[1]} + {1'b0, dpa_1_9_2[1]};
  wire [1:0] dpa_2_10_1;
  assign dpa_2_10_1 = {1'b0, dpa_1_9_3[1]} + {1'b0, dpa_1_9_4[1]} + {1'b0, dpa_1_9_5[1]};
  wire [1:0] dpa_2_10_2;
  assign dpa_2_10_2 = {1'b0, dpa_1_9_6[1]} + {1'b0, dpa_1_9_7[1]} + {1'b0, dpa_1_9_8[1]};
  wire [1:0] dpa_2_10_3;
  assign dpa_2_10_3 = {1'b0, dpa_1_10_0[0]} + {1'b0, dpa_1_10_1[0]} + {1'b0, dpa_1_10_2[0]};
  wire [1:0] dpa_2_10_4;
  assign dpa_2_10_4 = {1'b0, dpa_1_10_3[0]} + {1'b0, dpa_1_10_4[0]} + {1'b0, dpa_1_10_5[0]};
  wire [1:0] dpa_2_10_5;
  assign dpa_2_10_5 = {1'b0, dpa_1_10_6[0]} + {1'b0, dpa_1_10_7[0]} + {1'b0, dpa_1_10_8[0]};
  wire [1:0] dpa_2_11_0;
  assign dpa_2_11_0 = {1'b0, dpa_1_10_0[1]} + {1'b0, dpa_1_10_1[1]} + {1'b0, dpa_1_10_2[1]};
  wire [1:0] dpa_2_11_1;
  assign dpa_2_11_1 = {1'b0, dpa_1_10_3[1]} + {1'b0, dpa_1_10_4[1]} + {1'b0, dpa_1_10_5[1]};
  wire [1:0] dpa_2_11_2;
  assign dpa_2_11_2 = {1'b0, dpa_1_10_6[1]} + {1'b0, dpa_1_10_7[1]} + {1'b0, dpa_1_10_8[1]};
  wire [1:0] dpa_2_11_3;
  assign dpa_2_11_3 = {1'b0, dpa_1_11_0[0]} + {1'b0, dpa_1_11_1[0]} + {1'b0, dpa_1_11_2[0]};
  wire [1:0] dpa_2_11_4;
  assign dpa_2_11_4 = {1'b0, dpa_1_11_3[0]} + {1'b0, dpa_1_11_4[0]} + {1'b0, dpa_1_11_5[0]};
  wire [1:0] dpa_2_11_5;
  assign dpa_2_11_5 = {1'b0, dpa_1_11_6[0]} + {1'b0, dpa_1_11_7[0]} + {1'b0, dpa_1_11_8[0]};
  wire [1:0] dpa_2_12_0;
  assign dpa_2_12_0 = {1'b0, dpa_1_11_0[1]} + {1'b0, dpa_1_11_1[1]} + {1'b0, dpa_1_11_2[1]};
  wire [1:0] dpa_2_12_1;
  assign dpa_2_12_1 = {1'b0, dpa_1_11_3[1]} + {1'b0, dpa_1_11_4[1]} + {1'b0, dpa_1_11_5[1]};
  wire [1:0] dpa_2_12_2;
  assign dpa_2_12_2 = {1'b0, dpa_1_11_6[1]} + {1'b0, dpa_1_11_7[1]} + {1'b0, dpa_1_11_8[1]};
  wire [1:0] dpa_2_12_3;
  assign dpa_2_12_3 = {1'b0, dpa_1_12_0[0]} + {1'b0, dpa_1_12_1[0]} + {1'b0, dpa_1_12_2[0]};
  wire [1:0] dpa_2_12_4;
  assign dpa_2_12_4 = {1'b0, dpa_1_12_3[0]} + {1'b0, dpa_1_12_4[0]} + {1'b0, dpa_1_12_5[0]};
  wire [1:0] dpa_2_12_5;
  assign dpa_2_12_5 = {1'b0, dpa_1_12_6[0]} + {1'b0, dpa_1_12_7[0]} + {1'b0, dpa_1_12_8[0]};
  wire [1:0] dpa_2_13_0;
  assign dpa_2_13_0 = {1'b0, dpa_1_12_0[1]} + {1'b0, dpa_1_12_1[1]} + {1'b0, dpa_1_12_2[1]};
  wire [1:0] dpa_2_13_1;
  assign dpa_2_13_1 = {1'b0, dpa_1_12_3[1]} + {1'b0, dpa_1_12_4[1]} + {1'b0, dpa_1_12_5[1]};
  wire [1:0] dpa_2_13_2;
  assign dpa_2_13_2 = {1'b0, dpa_1_12_6[1]} + {1'b0, dpa_1_12_7[1]} + {1'b0, dpa_1_12_8[1]};
  wire [1:0] dpa_2_13_3;
  assign dpa_2_13_3 = {1'b0, dpa_1_13_0[0]} + {1'b0, dpa_1_13_1[0]} + {1'b0, dpa_1_13_2[0]};
  wire [1:0] dpa_2_13_4;
  assign dpa_2_13_4 = {1'b0, dpa_1_13_3[0]} + {1'b0, dpa_1_13_4[0]} + {1'b0, dpa_1_13_5[0]};
  wire [1:0] dpa_2_13_5;
  assign dpa_2_13_5 = {1'b0, dpa_1_13_6[0]} + {1'b0, dpa_1_13_7[0]} + {1'b0, dpa_1_13_8[0]};
  wire [1:0] dpa_2_14_0;
  assign dpa_2_14_0 = {1'b0, dpa_1_13_0[1]} + {1'b0, dpa_1_13_1[1]} + {1'b0, dpa_1_13_2[1]};
  wire [1:0] dpa_2_14_1;
  assign dpa_2_14_1 = {1'b0, dpa_1_13_3[1]} + {1'b0, dpa_1_13_4[1]} + {1'b0, dpa_1_13_5[1]};
  wire [1:0] dpa_2_14_2;
  assign dpa_2_14_2 = {1'b0, dpa_1_13_6[1]} + {1'b0, dpa_1_13_7[1]} + {1'b0, dpa_1_13_8[1]};
  wire [1:0] dpa_2_14_3;
  assign dpa_2_14_3 = {1'b0, dpa_1_14_0[0]} + {1'b0, dpa_1_14_1[0]} + {1'b0, dpa_1_14_2[0]};
  wire [1:0] dpa_2_14_4;
  assign dpa_2_14_4 = {1'b0, dpa_1_14_3[0]} + {1'b0, dpa_1_14_4[0]} + {1'b0, dpa_1_14_5[0]};
  wire [1:0] dpa_2_14_5;
  assign dpa_2_14_5 = {1'b0, dpa_1_14_6[0]} + {1'b0, dpa_1_14_7[0]} + {1'b0, dpa_1_14_8[0]};
  wire [1:0] dpa_2_15_0;
  assign dpa_2_15_0 = {1'b0, dpa_1_14_0[1]} + {1'b0, dpa_1_14_1[1]} + {1'b0, dpa_1_14_2[1]};
  wire [1:0] dpa_2_15_1;
  assign dpa_2_15_1 = {1'b0, dpa_1_14_3[1]} + {1'b0, dpa_1_14_4[1]} + {1'b0, dpa_1_14_5[1]};
  wire [1:0] dpa_2_15_2;
  assign dpa_2_15_2 = {1'b0, dpa_1_14_6[1]} + {1'b0, dpa_1_14_7[1]} + {1'b0, dpa_1_14_8[1]};
  wire [1:0] dpa_2_15_3;
  assign dpa_2_15_3 = {1'b0, dpa_1_15_0[0]} + {1'b0, dpa_1_15_1[0]} + {1'b0, dpa_1_15_2[0]};
  wire [1:0] dpa_2_15_4;
  assign dpa_2_15_4 = {1'b0, dpa_1_15_3[0]} + {1'b0, dpa_1_15_4[0]} + {1'b0, dpa_1_15_5[0]};
  wire [1:0] dpa_2_15_5;
  assign dpa_2_15_5 = {1'b0, dpa_1_15_6[0]} + {1'b0, dpa_1_15_7[0]} + {1'b0, dpa_1_15_8[0]};
  wire [1:0] dpa_2_16_0;
  assign dpa_2_16_0 = {1'b0, dpa_1_15_0[1]} + {1'b0, dpa_1_15_1[1]} + {1'b0, dpa_1_15_2[1]};
  wire [1:0] dpa_2_16_1;
  assign dpa_2_16_1 = {1'b0, dpa_1_15_3[1]} + {1'b0, dpa_1_15_4[1]} + {1'b0, dpa_1_15_5[1]};
  wire [1:0] dpa_2_16_2;
  assign dpa_2_16_2 = {1'b0, dpa_1_15_6[1]} + {1'b0, dpa_1_15_7[1]} + {1'b0, dpa_1_15_8[1]};
  wire [1:0] dpa_2_16_3;
  assign dpa_2_16_3 = {1'b0, dpa_1_16_0[0]} + {1'b0, dpa_1_16_1[0]} + {1'b0, dpa_1_16_2[0]};
  wire [1:0] dpa_2_16_4;
  assign dpa_2_16_4 = {1'b0, dpa_1_16_3[0]} + {1'b0, dpa_1_16_4[0]} + {1'b0, dpa_1_16_5[0]};
  wire [1:0] dpa_2_16_5;
  assign dpa_2_16_5 = {1'b0, dpa_1_16_6[0]} + {1'b0, dpa_1_16_7[0]} + {1'b0, dpa_1_16_8[0]};
  wire [1:0] dpa_2_17_0;
  assign dpa_2_17_0 = {1'b0, dpa_1_16_0[1]} + {1'b0, dpa_1_16_1[1]} + {1'b0, dpa_1_16_2[1]};
  wire [1:0] dpa_2_17_1;
  assign dpa_2_17_1 = {1'b0, dpa_1_16_3[1]} + {1'b0, dpa_1_16_4[1]} + {1'b0, dpa_1_16_5[1]};
  wire [1:0] dpa_2_17_2;
  assign dpa_2_17_2 = {1'b0, dpa_1_16_6[1]} + {1'b0, dpa_1_16_7[1]} + {1'b0, dpa_1_16_8[1]};
  wire [1:0] dpa_2_17_3;
  assign dpa_2_17_3 = {1'b0, dpa_1_17_0[0]} + {1'b0, dpa_1_17_1[0]} + {1'b0, dpa_1_17_2[0]};
  wire [1:0] dpa_2_17_4;
  assign dpa_2_17_4 = {1'b0, dpa_1_17_3[0]} + {1'b0, dpa_1_17_4[0]} + {1'b0, dpa_1_17_5[0]};
  wire [1:0] dpa_2_17_5;
  assign dpa_2_17_5 = {1'b0, dpa_1_17_6[0]} + {1'b0, dpa_1_17_7[0]} + {1'b0, dpa_1_17_8[0]};
  wire [1:0] dpa_2_18_0;
  assign dpa_2_18_0 = {1'b0, dpa_1_17_0[1]} + {1'b0, dpa_1_17_1[1]} + {1'b0, dpa_1_17_2[1]};
  wire [1:0] dpa_2_18_1;
  assign dpa_2_18_1 = {1'b0, dpa_1_17_3[1]} + {1'b0, dpa_1_17_4[1]} + {1'b0, dpa_1_17_5[1]};
  wire [1:0] dpa_2_18_2;
  assign dpa_2_18_2 = {1'b0, dpa_1_17_6[1]} + {1'b0, dpa_1_17_7[1]} + {1'b0, dpa_1_17_8[1]};
  wire [1:0] dpa_2_18_3;
  assign dpa_2_18_3 = {1'b0, dpa_1_18_0[0]} + {1'b0, dpa_1_18_1[0]} + {1'b0, dpa_1_18_2[0]};
  wire [1:0] dpa_2_18_4;
  assign dpa_2_18_4 = {1'b0, dpa_1_18_3[0]} + {1'b0, dpa_1_18_4[0]} + {1'b0, dpa_1_18_5[0]};
  wire [1:0] dpa_2_18_5;
  assign dpa_2_18_5 = {1'b0, dpa_1_18_6[0]} + {1'b0, dpa_1_18_7[0]} + {1'b0, dpa_1_18_8[0]};
  wire [1:0] dpa_2_19_0;
  assign dpa_2_19_0 = {1'b0, dpa_1_18_0[1]} + {1'b0, dpa_1_18_1[1]} + {1'b0, dpa_1_18_2[1]};
  wire [1:0] dpa_2_19_1;
  assign dpa_2_19_1 = {1'b0, dpa_1_18_3[1]} + {1'b0, dpa_1_18_4[1]} + {1'b0, dpa_1_18_5[1]};
  wire [1:0] dpa_2_19_2;
  assign dpa_2_19_2 = {1'b0, dpa_1_18_6[1]} + {1'b0, dpa_1_18_7[1]} + {1'b0, dpa_1_18_8[1]};
  wire [1:0] dpa_2_19_3;
  assign dpa_2_19_3 = {1'b0, dpa_1_19_0[0]} + {1'b0, dpa_1_19_1[0]} + {1'b0, dpa_1_19_2[0]};
  wire [1:0] dpa_2_19_4;
  assign dpa_2_19_4 = {1'b0, dpa_1_19_3[0]} + {1'b0, dpa_1_19_4[0]} + {1'b0, dpa_1_19_5[0]};
  wire [1:0] dpa_2_19_5;
  assign dpa_2_19_5 = {1'b0, dpa_1_19_6[0]} + {1'b0, dpa_1_19_7[0]} + {1'b0, dpa_1_19_8[0]};
  wire [1:0] dpa_2_20_0;
  assign dpa_2_20_0 = {1'b0, dpa_1_19_0[1]} + {1'b0, dpa_1_19_1[1]} + {1'b0, dpa_1_19_2[1]};
  wire [1:0] dpa_2_20_1;
  assign dpa_2_20_1 = {1'b0, dpa_1_19_3[1]} + {1'b0, dpa_1_19_4[1]} + {1'b0, dpa_1_19_5[1]};
  wire [1:0] dpa_2_20_2;
  assign dpa_2_20_2 = {1'b0, dpa_1_19_6[1]} + {1'b0, dpa_1_19_7[1]} + {1'b0, dpa_1_19_8[1]};
  wire [1:0] dpa_2_20_3;
  assign dpa_2_20_3 = {1'b0, dpa_1_20_0[0]} + {1'b0, dpa_1_20_1[0]} + {1'b0, dpa_1_20_2[0]};
  wire [1:0] dpa_2_20_4;
  assign dpa_2_20_4 = {1'b0, dpa_1_20_3[0]} + {1'b0, dpa_1_20_4[0]} + {1'b0, dpa_1_20_5[0]};
  wire [1:0] dpa_2_20_5;
  assign dpa_2_20_5 = {1'b0, dpa_1_20_6[0]} + {1'b0, dpa_1_20_7[0]} + {1'b0, dpa_1_20_8[0]};
  wire [1:0] dpa_2_21_0;
  assign dpa_2_21_0 = {1'b0, dpa_1_20_0[1]} + {1'b0, dpa_1_20_1[1]} + {1'b0, dpa_1_20_2[1]};
  wire [1:0] dpa_2_21_1;
  assign dpa_2_21_1 = {1'b0, dpa_1_20_3[1]} + {1'b0, dpa_1_20_4[1]} + {1'b0, dpa_1_20_5[1]};
  wire [1:0] dpa_2_21_2;
  assign dpa_2_21_2 = {1'b0, dpa_1_20_6[1]} + {1'b0, dpa_1_20_7[1]} + {1'b0, dpa_1_20_8[1]};
  wire [1:0] dpa_2_21_3;
  assign dpa_2_21_3 = {1'b0, dpa_1_21_0[0]} + {1'b0, dpa_1_21_1[0]} + {1'b0, dpa_1_21_2[0]};
  wire [1:0] dpa_2_21_4;
  assign dpa_2_21_4 = {1'b0, dpa_1_21_3[0]} + {1'b0, dpa_1_21_4[0]} + {1'b0, dpa_1_21_5[0]};
  wire [1:0] dpa_2_21_5;
  assign dpa_2_21_5 = {1'b0, dpa_1_21_6[0]} + {1'b0, dpa_1_21_7[0]} + {1'b0, dpa_1_21_8[0]};
  wire [1:0] dpa_2_22_0;
  assign dpa_2_22_0 = {1'b0, dpa_1_21_0[1]} + {1'b0, dpa_1_21_1[1]} + {1'b0, dpa_1_21_2[1]};
  wire [1:0] dpa_2_22_1;
  assign dpa_2_22_1 = {1'b0, dpa_1_21_3[1]} + {1'b0, dpa_1_21_4[1]} + {1'b0, dpa_1_21_5[1]};
  wire [1:0] dpa_2_22_2;
  assign dpa_2_22_2 = {1'b0, dpa_1_21_6[1]} + {1'b0, dpa_1_21_7[1]} + {1'b0, dpa_1_21_8[1]};
  wire [1:0] dpa_2_22_3;
  assign dpa_2_22_3 = {1'b0, dpa_1_22_0[0]} + {1'b0, dpa_1_22_1[0]} + {1'b0, dpa_1_22_2[0]};
  wire [1:0] dpa_2_22_4;
  assign dpa_2_22_4 = {1'b0, dpa_1_22_3[0]} + {1'b0, dpa_1_22_4[0]} + {1'b0, dpa_1_22_5[0]};
  wire [1:0] dpa_2_22_5;
  assign dpa_2_22_5 = {1'b0, dpa_1_22_6[0]} + {1'b0, dpa_1_22_7[0]} + {1'b0, dpa_1_22_8[0]};
  wire [1:0] dpa_2_23_0;
  assign dpa_2_23_0 = {1'b0, dpa_1_22_0[1]} + {1'b0, dpa_1_22_1[1]} + {1'b0, dpa_1_22_2[1]};
  wire [1:0] dpa_2_23_1;
  assign dpa_2_23_1 = {1'b0, dpa_1_22_3[1]} + {1'b0, dpa_1_22_4[1]} + {1'b0, dpa_1_22_5[1]};
  wire [1:0] dpa_2_23_2;
  assign dpa_2_23_2 = {1'b0, dpa_1_22_6[1]} + {1'b0, dpa_1_22_7[1]} + {1'b0, dpa_1_22_8[1]};
  wire [1:0] dpa_2_23_3;
  assign dpa_2_23_3 = {1'b0, dpa_1_23_0[0]} + {1'b0, dpa_1_23_1[0]} + {1'b0, dpa_1_23_2[0]};
  wire [1:0] dpa_2_23_4;
  assign dpa_2_23_4 = {1'b0, dpa_1_23_3[0]} + {1'b0, dpa_1_23_4[0]} + {1'b0, dpa_1_23_5[0]};
  wire [1:0] dpa_2_23_5;
  assign dpa_2_23_5 = {1'b0, dpa_1_23_6[0]} + {1'b0, dpa_1_23_7[0]} + {1'b0, dpa_1_23_8[0]};
  wire [1:0] dpa_2_24_0;
  assign dpa_2_24_0 = {1'b0, dpa_1_23_0[1]} + {1'b0, dpa_1_23_1[1]} + {1'b0, dpa_1_23_2[1]};
  wire [1:0] dpa_2_24_1;
  assign dpa_2_24_1 = {1'b0, dpa_1_23_3[1]} + {1'b0, dpa_1_23_4[1]} + {1'b0, dpa_1_23_5[1]};
  wire [1:0] dpa_2_24_2;
  assign dpa_2_24_2 = {1'b0, dpa_1_23_6[1]} + {1'b0, dpa_1_23_7[1]} + {1'b0, dpa_1_23_8[1]};
  wire [1:0] dpa_2_24_3;
  assign dpa_2_24_3 = {1'b0, dpa_1_24_0[0]} + {1'b0, dpa_1_24_1[0]} + {1'b0, dpa_1_24_2[0]};
  wire [1:0] dpa_2_24_4;
  assign dpa_2_24_4 = {1'b0, dpa_1_24_3[0]} + {1'b0, dpa_1_24_4[0]} + {1'b0, dpa_1_24_5[0]};
  wire [1:0] dpa_2_24_5;
  assign dpa_2_24_5 = {1'b0, dpa_1_24_6[0]} + {1'b0, dpa_1_24_7[0]} + {1'b0, dpa_1_24_8[0]};
  wire [1:0] dpa_2_25_0;
  assign dpa_2_25_0 = {1'b0, dpa_1_24_0[1]} + {1'b0, dpa_1_24_1[1]} + {1'b0, dpa_1_24_2[1]};
  wire [1:0] dpa_2_25_1;
  assign dpa_2_25_1 = {1'b0, dpa_1_24_3[1]} + {1'b0, dpa_1_24_4[1]} + {1'b0, dpa_1_24_5[1]};
  wire [1:0] dpa_2_25_2;
  assign dpa_2_25_2 = {1'b0, dpa_1_24_6[1]} + {1'b0, dpa_1_24_7[1]} + {1'b0, dpa_1_24_8[1]};
  wire [1:0] dpa_2_25_3;
  assign dpa_2_25_3 = {1'b0, dpa_1_25_0[0]} + {1'b0, dpa_1_25_1[0]} + {1'b0, dpa_1_25_2[0]};
  wire [1:0] dpa_2_25_4;
  assign dpa_2_25_4 = {1'b0, dpa_1_25_3[0]} + {1'b0, dpa_1_25_4[0]} + {1'b0, dpa_1_25_5[0]};
  wire [1:0] dpa_2_25_5;
  assign dpa_2_25_5 = {1'b0, dpa_1_25_6[0]} + {1'b0, dpa_1_25_7[0]} + {1'b0, dpa_1_25_8[0]};
  wire [1:0] dpa_2_26_0;
  assign dpa_2_26_0 = {1'b0, dpa_1_25_0[1]} + {1'b0, dpa_1_25_1[1]} + {1'b0, dpa_1_25_2[1]};
  wire [1:0] dpa_2_26_1;
  assign dpa_2_26_1 = {1'b0, dpa_1_25_3[1]} + {1'b0, dpa_1_25_4[1]} + {1'b0, dpa_1_25_5[1]};
  wire [1:0] dpa_2_26_2;
  assign dpa_2_26_2 = {1'b0, dpa_1_25_6[1]} + {1'b0, dpa_1_25_7[1]} + {1'b0, dpa_1_25_8[1]};
  wire [1:0] dpa_2_26_3;
  assign dpa_2_26_3 = {1'b0, dpa_1_26_0[0]} + {1'b0, dpa_1_26_1[0]} + {1'b0, dpa_1_26_2[0]};
  wire [1:0] dpa_2_26_4;
  assign dpa_2_26_4 = {1'b0, dpa_1_26_3[0]} + {1'b0, dpa_1_26_4[0]} + {1'b0, dpa_1_26_5[0]};
  wire [1:0] dpa_2_26_5;
  assign dpa_2_26_5 = {1'b0, dpa_1_26_6[0]} + {1'b0, dpa_1_26_7[0]} + {1'b0, dpa_1_26_8[0]};
  wire [1:0] dpa_2_27_0;
  assign dpa_2_27_0 = {1'b0, dpa_1_26_0[1]} + {1'b0, dpa_1_26_1[1]} + {1'b0, dpa_1_26_2[1]};
  wire [1:0] dpa_2_27_1;
  assign dpa_2_27_1 = {1'b0, dpa_1_26_3[1]} + {1'b0, dpa_1_26_4[1]} + {1'b0, dpa_1_26_5[1]};
  wire [1:0] dpa_2_27_2;
  assign dpa_2_27_2 = {1'b0, dpa_1_26_6[1]} + {1'b0, dpa_1_26_7[1]} + {1'b0, dpa_1_26_8[1]};
  wire [1:0] dpa_2_27_3;
  assign dpa_2_27_3 = {1'b0, dpa_0_26_0[1]} + {1'b0, dpa_0_26_1[1]} + {1'b0, dpa_0_26_2[1]};
  wire [1:0] dpa_2_27_4;
  assign dpa_2_27_4 = {1'b0, dpa_0_26_3[1]} + {1'b0, dpa_0_26_4[1]};
  wire [1:0] dpa_3_0_0;
  assign dpa_3_0_0 = {1'b0, dpa_2_0_0[0]} + {1'b0, dpa_2_0_1[0]} + {1'b0, dpa_2_0_2[0]};
  wire [1:0] dpa_3_0_1;
  assign dpa_3_0_1 = {1'b0, dpa_terms_i[24][0]} + {1'b0, dpa_terms_i[25][0]} + {1'b0, dpa_terms_i[26][0]};
  wire [1:0] dpa_3_1_0;
  assign dpa_3_1_0 = {1'b0, dpa_2_0_0[1]} + {1'b0, dpa_2_0_1[1]} + {1'b0, dpa_2_0_2[1]};
  wire [1:0] dpa_3_1_1;
  assign dpa_3_1_1 = {1'b0, dpa_2_1_0[0]} + {1'b0, dpa_2_1_1[0]} + {1'b0, dpa_2_1_2[0]};
  wire [1:0] dpa_3_1_2;
  assign dpa_3_1_2 = {1'b0, dpa_2_1_3[0]} + {1'b0, dpa_2_1_4[0]} + {1'b0, dpa_terms_i[29][1]};
  wire [1:0] dpa_3_2_0;
  assign dpa_3_2_0 = {1'b0, dpa_2_1_0[1]} + {1'b0, dpa_2_1_1[1]} + {1'b0, dpa_2_1_2[1]};
  wire [1:0] dpa_3_2_1;
  assign dpa_3_2_1 = {1'b0, dpa_2_1_3[1]} + {1'b0, dpa_2_1_4[1]} + {1'b0, dpa_2_2_0[0]};
  wire [1:0] dpa_3_2_2;
  assign dpa_3_2_2 = {1'b0, dpa_2_2_1[0]} + {1'b0, dpa_2_2_2[0]} + {1'b0, dpa_2_2_3[0]};
  wire [1:0] dpa_3_2_3;
  assign dpa_3_2_3 = {1'b0, dpa_2_2_4[0]} + {1'b0, dpa_2_2_5[0]};
  wire [1:0] dpa_3_3_0;
  assign dpa_3_3_0 = {1'b0, dpa_2_2_0[1]} + {1'b0, dpa_2_2_1[1]} + {1'b0, dpa_2_2_2[1]};
  wire [1:0] dpa_3_3_1;
  assign dpa_3_3_1 = {1'b0, dpa_2_2_3[1]} + {1'b0, dpa_2_2_4[1]} + {1'b0, dpa_2_2_5[1]};
  wire [1:0] dpa_3_3_2;
  assign dpa_3_3_2 = {1'b0, dpa_2_3_0[0]} + {1'b0, dpa_2_3_1[0]} + {1'b0, dpa_2_3_2[0]};
  wire [1:0] dpa_3_3_3;
  assign dpa_3_3_3 = {1'b0, dpa_2_3_3[0]} + {1'b0, dpa_2_3_4[0]} + {1'b0, dpa_2_3_5[0]};
  wire [1:0] dpa_3_4_0;
  assign dpa_3_4_0 = {1'b0, dpa_2_3_0[1]} + {1'b0, dpa_2_3_1[1]} + {1'b0, dpa_2_3_2[1]};
  wire [1:0] dpa_3_4_1;
  assign dpa_3_4_1 = {1'b0, dpa_2_3_3[1]} + {1'b0, dpa_2_3_4[1]} + {1'b0, dpa_2_3_5[1]};
  wire [1:0] dpa_3_4_2;
  assign dpa_3_4_2 = {1'b0, dpa_2_4_0[0]} + {1'b0, dpa_2_4_1[0]} + {1'b0, dpa_2_4_2[0]};
  wire [1:0] dpa_3_4_3;
  assign dpa_3_4_3 = {1'b0, dpa_2_4_3[0]} + {1'b0, dpa_2_4_4[0]} + {1'b0, dpa_2_4_5[0]};
  wire [1:0] dpa_3_5_0;
  assign dpa_3_5_0 = {1'b0, dpa_2_4_0[1]} + {1'b0, dpa_2_4_1[1]} + {1'b0, dpa_2_4_2[1]};
  wire [1:0] dpa_3_5_1;
  assign dpa_3_5_1 = {1'b0, dpa_2_4_3[1]} + {1'b0, dpa_2_4_4[1]} + {1'b0, dpa_2_4_5[1]};
  wire [1:0] dpa_3_5_2;
  assign dpa_3_5_2 = {1'b0, dpa_2_5_0[0]} + {1'b0, dpa_2_5_1[0]} + {1'b0, dpa_2_5_2[0]};
  wire [1:0] dpa_3_5_3;
  assign dpa_3_5_3 = {1'b0, dpa_2_5_3[0]} + {1'b0, dpa_2_5_4[0]} + {1'b0, dpa_2_5_5[0]};
  wire [1:0] dpa_3_6_0;
  assign dpa_3_6_0 = {1'b0, dpa_2_5_0[1]} + {1'b0, dpa_2_5_1[1]} + {1'b0, dpa_2_5_2[1]};
  wire [1:0] dpa_3_6_1;
  assign dpa_3_6_1 = {1'b0, dpa_2_5_3[1]} + {1'b0, dpa_2_5_4[1]} + {1'b0, dpa_2_5_5[1]};
  wire [1:0] dpa_3_6_2;
  assign dpa_3_6_2 = {1'b0, dpa_2_6_0[0]} + {1'b0, dpa_2_6_1[0]} + {1'b0, dpa_2_6_2[0]};
  wire [1:0] dpa_3_6_3;
  assign dpa_3_6_3 = {1'b0, dpa_2_6_3[0]} + {1'b0, dpa_2_6_4[0]} + {1'b0, dpa_2_6_5[0]};
  wire [1:0] dpa_3_7_0;
  assign dpa_3_7_0 = {1'b0, dpa_2_6_0[1]} + {1'b0, dpa_2_6_1[1]} + {1'b0, dpa_2_6_2[1]};
  wire [1:0] dpa_3_7_1;
  assign dpa_3_7_1 = {1'b0, dpa_2_6_3[1]} + {1'b0, dpa_2_6_4[1]} + {1'b0, dpa_2_6_5[1]};
  wire [1:0] dpa_3_7_2;
  assign dpa_3_7_2 = {1'b0, dpa_2_7_0[0]} + {1'b0, dpa_2_7_1[0]} + {1'b0, dpa_2_7_2[0]};
  wire [1:0] dpa_3_7_3;
  assign dpa_3_7_3 = {1'b0, dpa_2_7_3[0]} + {1'b0, dpa_2_7_4[0]} + {1'b0, dpa_2_7_5[0]};
  wire [1:0] dpa_3_8_0;
  assign dpa_3_8_0 = {1'b0, dpa_2_7_0[1]} + {1'b0, dpa_2_7_1[1]} + {1'b0, dpa_2_7_2[1]};
  wire [1:0] dpa_3_8_1;
  assign dpa_3_8_1 = {1'b0, dpa_2_7_3[1]} + {1'b0, dpa_2_7_4[1]} + {1'b0, dpa_2_7_5[1]};
  wire [1:0] dpa_3_8_2;
  assign dpa_3_8_2 = {1'b0, dpa_2_8_0[0]} + {1'b0, dpa_2_8_1[0]} + {1'b0, dpa_2_8_2[0]};
  wire [1:0] dpa_3_8_3;
  assign dpa_3_8_3 = {1'b0, dpa_2_8_3[0]} + {1'b0, dpa_2_8_4[0]} + {1'b0, dpa_2_8_5[0]};
  wire [1:0] dpa_3_9_0;
  assign dpa_3_9_0 = {1'b0, dpa_2_8_0[1]} + {1'b0, dpa_2_8_1[1]} + {1'b0, dpa_2_8_2[1]};
  wire [1:0] dpa_3_9_1;
  assign dpa_3_9_1 = {1'b0, dpa_2_8_3[1]} + {1'b0, dpa_2_8_4[1]} + {1'b0, dpa_2_8_5[1]};
  wire [1:0] dpa_3_9_2;
  assign dpa_3_9_2 = {1'b0, dpa_2_9_0[0]} + {1'b0, dpa_2_9_1[0]} + {1'b0, dpa_2_9_2[0]};
  wire [1:0] dpa_3_9_3;
  assign dpa_3_9_3 = {1'b0, dpa_2_9_3[0]} + {1'b0, dpa_2_9_4[0]} + {1'b0, dpa_2_9_5[0]};
  wire [1:0] dpa_3_10_0;
  assign dpa_3_10_0 = {1'b0, dpa_2_9_0[1]} + {1'b0, dpa_2_9_1[1]} + {1'b0, dpa_2_9_2[1]};
  wire [1:0] dpa_3_10_1;
  assign dpa_3_10_1 = {1'b0, dpa_2_9_3[1]} + {1'b0, dpa_2_9_4[1]} + {1'b0, dpa_2_9_5[1]};
  wire [1:0] dpa_3_10_2;
  assign dpa_3_10_2 = {1'b0, dpa_2_10_0[0]} + {1'b0, dpa_2_10_1[0]} + {1'b0, dpa_2_10_2[0]};
  wire [1:0] dpa_3_10_3;
  assign dpa_3_10_3 = {1'b0, dpa_2_10_3[0]} + {1'b0, dpa_2_10_4[0]} + {1'b0, dpa_2_10_5[0]};
  wire [1:0] dpa_3_11_0;
  assign dpa_3_11_0 = {1'b0, dpa_2_10_0[1]} + {1'b0, dpa_2_10_1[1]} + {1'b0, dpa_2_10_2[1]};
  wire [1:0] dpa_3_11_1;
  assign dpa_3_11_1 = {1'b0, dpa_2_10_3[1]} + {1'b0, dpa_2_10_4[1]} + {1'b0, dpa_2_10_5[1]};
  wire [1:0] dpa_3_11_2;
  assign dpa_3_11_2 = {1'b0, dpa_2_11_0[0]} + {1'b0, dpa_2_11_1[0]} + {1'b0, dpa_2_11_2[0]};
  wire [1:0] dpa_3_11_3;
  assign dpa_3_11_3 = {1'b0, dpa_2_11_3[0]} + {1'b0, dpa_2_11_4[0]} + {1'b0, dpa_2_11_5[0]};
  wire [1:0] dpa_3_12_0;
  assign dpa_3_12_0 = {1'b0, dpa_2_11_0[1]} + {1'b0, dpa_2_11_1[1]} + {1'b0, dpa_2_11_2[1]};
  wire [1:0] dpa_3_12_1;
  assign dpa_3_12_1 = {1'b0, dpa_2_11_3[1]} + {1'b0, dpa_2_11_4[1]} + {1'b0, dpa_2_11_5[1]};
  wire [1:0] dpa_3_12_2;
  assign dpa_3_12_2 = {1'b0, dpa_2_12_0[0]} + {1'b0, dpa_2_12_1[0]} + {1'b0, dpa_2_12_2[0]};
  wire [1:0] dpa_3_12_3;
  assign dpa_3_12_3 = {1'b0, dpa_2_12_3[0]} + {1'b0, dpa_2_12_4[0]} + {1'b0, dpa_2_12_5[0]};
  wire [1:0] dpa_3_13_0;
  assign dpa_3_13_0 = {1'b0, dpa_2_12_0[1]} + {1'b0, dpa_2_12_1[1]} + {1'b0, dpa_2_12_2[1]};
  wire [1:0] dpa_3_13_1;
  assign dpa_3_13_1 = {1'b0, dpa_2_12_3[1]} + {1'b0, dpa_2_12_4[1]} + {1'b0, dpa_2_12_5[1]};
  wire [1:0] dpa_3_13_2;
  assign dpa_3_13_2 = {1'b0, dpa_2_13_0[0]} + {1'b0, dpa_2_13_1[0]} + {1'b0, dpa_2_13_2[0]};
  wire [1:0] dpa_3_13_3;
  assign dpa_3_13_3 = {1'b0, dpa_2_13_3[0]} + {1'b0, dpa_2_13_4[0]} + {1'b0, dpa_2_13_5[0]};
  wire [1:0] dpa_3_14_0;
  assign dpa_3_14_0 = {1'b0, dpa_2_13_0[1]} + {1'b0, dpa_2_13_1[1]} + {1'b0, dpa_2_13_2[1]};
  wire [1:0] dpa_3_14_1;
  assign dpa_3_14_1 = {1'b0, dpa_2_13_3[1]} + {1'b0, dpa_2_13_4[1]} + {1'b0, dpa_2_13_5[1]};
  wire [1:0] dpa_3_14_2;
  assign dpa_3_14_2 = {1'b0, dpa_2_14_0[0]} + {1'b0, dpa_2_14_1[0]} + {1'b0, dpa_2_14_2[0]};
  wire [1:0] dpa_3_14_3;
  assign dpa_3_14_3 = {1'b0, dpa_2_14_3[0]} + {1'b0, dpa_2_14_4[0]} + {1'b0, dpa_2_14_5[0]};
  wire [1:0] dpa_3_15_0;
  assign dpa_3_15_0 = {1'b0, dpa_2_14_0[1]} + {1'b0, dpa_2_14_1[1]} + {1'b0, dpa_2_14_2[1]};
  wire [1:0] dpa_3_15_1;
  assign dpa_3_15_1 = {1'b0, dpa_2_14_3[1]} + {1'b0, dpa_2_14_4[1]} + {1'b0, dpa_2_14_5[1]};
  wire [1:0] dpa_3_15_2;
  assign dpa_3_15_2 = {1'b0, dpa_2_15_0[0]} + {1'b0, dpa_2_15_1[0]} + {1'b0, dpa_2_15_2[0]};
  wire [1:0] dpa_3_15_3;
  assign dpa_3_15_3 = {1'b0, dpa_2_15_3[0]} + {1'b0, dpa_2_15_4[0]} + {1'b0, dpa_2_15_5[0]};
  wire [1:0] dpa_3_16_0;
  assign dpa_3_16_0 = {1'b0, dpa_2_15_0[1]} + {1'b0, dpa_2_15_1[1]} + {1'b0, dpa_2_15_2[1]};
  wire [1:0] dpa_3_16_1;
  assign dpa_3_16_1 = {1'b0, dpa_2_15_3[1]} + {1'b0, dpa_2_15_4[1]} + {1'b0, dpa_2_15_5[1]};
  wire [1:0] dpa_3_16_2;
  assign dpa_3_16_2 = {1'b0, dpa_2_16_0[0]} + {1'b0, dpa_2_16_1[0]} + {1'b0, dpa_2_16_2[0]};
  wire [1:0] dpa_3_16_3;
  assign dpa_3_16_3 = {1'b0, dpa_2_16_3[0]} + {1'b0, dpa_2_16_4[0]} + {1'b0, dpa_2_16_5[0]};
  wire [1:0] dpa_3_17_0;
  assign dpa_3_17_0 = {1'b0, dpa_2_16_0[1]} + {1'b0, dpa_2_16_1[1]} + {1'b0, dpa_2_16_2[1]};
  wire [1:0] dpa_3_17_1;
  assign dpa_3_17_1 = {1'b0, dpa_2_16_3[1]} + {1'b0, dpa_2_16_4[1]} + {1'b0, dpa_2_16_5[1]};
  wire [1:0] dpa_3_17_2;
  assign dpa_3_17_2 = {1'b0, dpa_2_17_0[0]} + {1'b0, dpa_2_17_1[0]} + {1'b0, dpa_2_17_2[0]};
  wire [1:0] dpa_3_17_3;
  assign dpa_3_17_3 = {1'b0, dpa_2_17_3[0]} + {1'b0, dpa_2_17_4[0]} + {1'b0, dpa_2_17_5[0]};
  wire [1:0] dpa_3_18_0;
  assign dpa_3_18_0 = {1'b0, dpa_2_17_0[1]} + {1'b0, dpa_2_17_1[1]} + {1'b0, dpa_2_17_2[1]};
  wire [1:0] dpa_3_18_1;
  assign dpa_3_18_1 = {1'b0, dpa_2_17_3[1]} + {1'b0, dpa_2_17_4[1]} + {1'b0, dpa_2_17_5[1]};
  wire [1:0] dpa_3_18_2;
  assign dpa_3_18_2 = {1'b0, dpa_2_18_0[0]} + {1'b0, dpa_2_18_1[0]} + {1'b0, dpa_2_18_2[0]};
  wire [1:0] dpa_3_18_3;
  assign dpa_3_18_3 = {1'b0, dpa_2_18_3[0]} + {1'b0, dpa_2_18_4[0]} + {1'b0, dpa_2_18_5[0]};
  wire [1:0] dpa_3_19_0;
  assign dpa_3_19_0 = {1'b0, dpa_2_18_0[1]} + {1'b0, dpa_2_18_1[1]} + {1'b0, dpa_2_18_2[1]};
  wire [1:0] dpa_3_19_1;
  assign dpa_3_19_1 = {1'b0, dpa_2_18_3[1]} + {1'b0, dpa_2_18_4[1]} + {1'b0, dpa_2_18_5[1]};
  wire [1:0] dpa_3_19_2;
  assign dpa_3_19_2 = {1'b0, dpa_2_19_0[0]} + {1'b0, dpa_2_19_1[0]} + {1'b0, dpa_2_19_2[0]};
  wire [1:0] dpa_3_19_3;
  assign dpa_3_19_3 = {1'b0, dpa_2_19_3[0]} + {1'b0, dpa_2_19_4[0]} + {1'b0, dpa_2_19_5[0]};
  wire [1:0] dpa_3_20_0;
  assign dpa_3_20_0 = {1'b0, dpa_2_19_0[1]} + {1'b0, dpa_2_19_1[1]} + {1'b0, dpa_2_19_2[1]};
  wire [1:0] dpa_3_20_1;
  assign dpa_3_20_1 = {1'b0, dpa_2_19_3[1]} + {1'b0, dpa_2_19_4[1]} + {1'b0, dpa_2_19_5[1]};
  wire [1:0] dpa_3_20_2;
  assign dpa_3_20_2 = {1'b0, dpa_2_20_0[0]} + {1'b0, dpa_2_20_1[0]} + {1'b0, dpa_2_20_2[0]};
  wire [1:0] dpa_3_20_3;
  assign dpa_3_20_3 = {1'b0, dpa_2_20_3[0]} + {1'b0, dpa_2_20_4[0]} + {1'b0, dpa_2_20_5[0]};
  wire [1:0] dpa_3_21_0;
  assign dpa_3_21_0 = {1'b0, dpa_2_20_0[1]} + {1'b0, dpa_2_20_1[1]} + {1'b0, dpa_2_20_2[1]};
  wire [1:0] dpa_3_21_1;
  assign dpa_3_21_1 = {1'b0, dpa_2_20_3[1]} + {1'b0, dpa_2_20_4[1]} + {1'b0, dpa_2_20_5[1]};
  wire [1:0] dpa_3_21_2;
  assign dpa_3_21_2 = {1'b0, dpa_2_21_0[0]} + {1'b0, dpa_2_21_1[0]} + {1'b0, dpa_2_21_2[0]};
  wire [1:0] dpa_3_21_3;
  assign dpa_3_21_3 = {1'b0, dpa_2_21_3[0]} + {1'b0, dpa_2_21_4[0]} + {1'b0, dpa_2_21_5[0]};
  wire [1:0] dpa_3_22_0;
  assign dpa_3_22_0 = {1'b0, dpa_2_21_0[1]} + {1'b0, dpa_2_21_1[1]} + {1'b0, dpa_2_21_2[1]};
  wire [1:0] dpa_3_22_1;
  assign dpa_3_22_1 = {1'b0, dpa_2_21_3[1]} + {1'b0, dpa_2_21_4[1]} + {1'b0, dpa_2_21_5[1]};
  wire [1:0] dpa_3_22_2;
  assign dpa_3_22_2 = {1'b0, dpa_2_22_0[0]} + {1'b0, dpa_2_22_1[0]} + {1'b0, dpa_2_22_2[0]};
  wire [1:0] dpa_3_22_3;
  assign dpa_3_22_3 = {1'b0, dpa_2_22_3[0]} + {1'b0, dpa_2_22_4[0]} + {1'b0, dpa_2_22_5[0]};
  wire [1:0] dpa_3_23_0;
  assign dpa_3_23_0 = {1'b0, dpa_2_22_0[1]} + {1'b0, dpa_2_22_1[1]} + {1'b0, dpa_2_22_2[1]};
  wire [1:0] dpa_3_23_1;
  assign dpa_3_23_1 = {1'b0, dpa_2_22_3[1]} + {1'b0, dpa_2_22_4[1]} + {1'b0, dpa_2_22_5[1]};
  wire [1:0] dpa_3_23_2;
  assign dpa_3_23_2 = {1'b0, dpa_2_23_0[0]} + {1'b0, dpa_2_23_1[0]} + {1'b0, dpa_2_23_2[0]};
  wire [1:0] dpa_3_23_3;
  assign dpa_3_23_3 = {1'b0, dpa_2_23_3[0]} + {1'b0, dpa_2_23_4[0]} + {1'b0, dpa_2_23_5[0]};
  wire [1:0] dpa_3_24_0;
  assign dpa_3_24_0 = {1'b0, dpa_2_23_0[1]} + {1'b0, dpa_2_23_1[1]} + {1'b0, dpa_2_23_2[1]};
  wire [1:0] dpa_3_24_1;
  assign dpa_3_24_1 = {1'b0, dpa_2_23_3[1]} + {1'b0, dpa_2_23_4[1]} + {1'b0, dpa_2_23_5[1]};
  wire [1:0] dpa_3_24_2;
  assign dpa_3_24_2 = {1'b0, dpa_2_24_0[0]} + {1'b0, dpa_2_24_1[0]} + {1'b0, dpa_2_24_2[0]};
  wire [1:0] dpa_3_24_3;
  assign dpa_3_24_3 = {1'b0, dpa_2_24_3[0]} + {1'b0, dpa_2_24_4[0]} + {1'b0, dpa_2_24_5[0]};
  wire [1:0] dpa_3_25_0;
  assign dpa_3_25_0 = {1'b0, dpa_2_24_0[1]} + {1'b0, dpa_2_24_1[1]} + {1'b0, dpa_2_24_2[1]};
  wire [1:0] dpa_3_25_1;
  assign dpa_3_25_1 = {1'b0, dpa_2_24_3[1]} + {1'b0, dpa_2_24_4[1]} + {1'b0, dpa_2_24_5[1]};
  wire [1:0] dpa_3_25_2;
  assign dpa_3_25_2 = {1'b0, dpa_2_25_0[0]} + {1'b0, dpa_2_25_1[0]} + {1'b0, dpa_2_25_2[0]};
  wire [1:0] dpa_3_25_3;
  assign dpa_3_25_3 = {1'b0, dpa_2_25_3[0]} + {1'b0, dpa_2_25_4[0]} + {1'b0, dpa_2_25_5[0]};
  wire [1:0] dpa_3_26_0;
  assign dpa_3_26_0 = {1'b0, dpa_2_25_0[1]} + {1'b0, dpa_2_25_1[1]} + {1'b0, dpa_2_25_2[1]};
  wire [1:0] dpa_3_26_1;
  assign dpa_3_26_1 = {1'b0, dpa_2_25_3[1]} + {1'b0, dpa_2_25_4[1]} + {1'b0, dpa_2_25_5[1]};
  wire [1:0] dpa_3_26_2;
  assign dpa_3_26_2 = {1'b0, dpa_2_26_0[0]} + {1'b0, dpa_2_26_1[0]} + {1'b0, dpa_2_26_2[0]};
  wire [1:0] dpa_3_26_3;
  assign dpa_3_26_3 = {1'b0, dpa_2_26_3[0]} + {1'b0, dpa_2_26_4[0]} + {1'b0, dpa_2_26_5[0]};
  wire [1:0] dpa_3_27_0;
  assign dpa_3_27_0 = {1'b0, dpa_2_26_0[1]} + {1'b0, dpa_2_26_1[1]} + {1'b0, dpa_2_26_2[1]};
  wire [1:0] dpa_3_27_1;
  assign dpa_3_27_1 = {1'b0, dpa_2_26_3[1]} + {1'b0, dpa_2_26_4[1]} + {1'b0, dpa_2_26_5[1]};
  wire [1:0] dpa_3_27_2;
  assign dpa_3_27_2 = {1'b0, dpa_2_27_0[0]} + {1'b0, dpa_2_27_1[0]} + {1'b0, dpa_2_27_2[0]};
  wire [1:0] dpa_3_27_3;
  assign dpa_3_27_3 = {1'b0, dpa_2_27_3[0]} + {1'b0, dpa_2_27_4[0]} + {1'b0, dpa_0_26_5[1]};
  wire [1:0] dpa_3_28_0;
  assign dpa_3_28_0 = {1'b0, dpa_2_27_0[1]} + {1'b0, dpa_2_27_1[1]};
  wire [1:0] dpa_4_0_0;
  assign dpa_4_0_0 = {1'b0, dpa_3_0_0[0]} + {1'b0, dpa_3_0_1[0]} + {1'b0, dpa_terms_i[27][0]};
  wire [1:0] dpa_4_0_1;
  assign dpa_4_0_1 = {1'b0, dpa_terms_i[28][0]} + {1'b0, dpa_terms_i[29][0]};
  wire [1:0] dpa_4_1_0;
  assign dpa_4_1_0 = {1'b0, dpa_3_0_0[1]} + {1'b0, dpa_3_0_1[1]} + {1'b0, dpa_3_1_0[0]};
  wire [1:0] dpa_4_1_1;
  assign dpa_4_1_1 = {1'b0, dpa_3_1_1[0]} + {1'b0, dpa_3_1_2[0]} + {1'b0, dpa_terms_i[30][1]};
  wire [1:0] dpa_4_1_2;
  assign dpa_4_1_2 = {1'b0, dpa_terms_i[31][1]} + {1'b0, dpa_terms_i[32][1]};
  wire [1:0] dpa_4_2_0;
  assign dpa_4_2_0 = {1'b0, dpa_3_1_0[1]} + {1'b0, dpa_3_1_1[1]} + {1'b0, dpa_3_1_2[1]};
  wire [1:0] dpa_4_2_1;
  assign dpa_4_2_1 = {1'b0, dpa_3_2_0[0]} + {1'b0, dpa_3_2_1[0]} + {1'b0, dpa_3_2_2[0]};
  wire [1:0] dpa_4_2_2;
  assign dpa_4_2_2 = {1'b0, dpa_3_2_3[0]} + {1'b0, dpa_terms_i[32][2]} + {1'b0, negative_count_i[2]};
  wire [1:0] dpa_4_3_0;
  assign dpa_4_3_0 = {1'b0, dpa_3_2_0[1]} + {1'b0, dpa_3_2_1[1]} + {1'b0, dpa_3_2_2[1]};
  wire [1:0] dpa_4_3_1;
  assign dpa_4_3_1 = {1'b0, dpa_3_2_3[1]} + {1'b0, dpa_3_3_0[0]} + {1'b0, dpa_3_3_1[0]};
  wire [1:0] dpa_4_3_2;
  assign dpa_4_3_2 = {1'b0, dpa_3_3_2[0]} + {1'b0, dpa_3_3_3[0]} + {1'b0, negative_count_i[3]};
  wire [1:0] dpa_4_4_0;
  assign dpa_4_4_0 = {1'b0, dpa_3_3_0[1]} + {1'b0, dpa_3_3_1[1]} + {1'b0, dpa_3_3_2[1]};
  wire [1:0] dpa_4_4_1;
  assign dpa_4_4_1 = {1'b0, dpa_3_3_3[1]} + {1'b0, dpa_3_4_0[0]} + {1'b0, dpa_3_4_1[0]};
  wire [1:0] dpa_4_4_2;
  assign dpa_4_4_2 = {1'b0, dpa_3_4_2[0]} + {1'b0, dpa_3_4_3[0]} + {1'b0, negative_count_i[4]};
  wire [1:0] dpa_4_5_0;
  assign dpa_4_5_0 = {1'b0, dpa_3_4_0[1]} + {1'b0, dpa_3_4_1[1]} + {1'b0, dpa_3_4_2[1]};
  wire [1:0] dpa_4_5_1;
  assign dpa_4_5_1 = {1'b0, dpa_3_4_3[1]} + {1'b0, dpa_3_5_0[0]} + {1'b0, dpa_3_5_1[0]};
  wire [1:0] dpa_4_5_2;
  assign dpa_4_5_2 = {1'b0, dpa_3_5_2[0]} + {1'b0, dpa_3_5_3[0]} + {1'b0, negative_count_i[5]};
  wire [1:0] dpa_4_6_0;
  assign dpa_4_6_0 = {1'b0, dpa_3_5_0[1]} + {1'b0, dpa_3_5_1[1]} + {1'b0, dpa_3_5_2[1]};
  wire [1:0] dpa_4_6_1;
  assign dpa_4_6_1 = {1'b0, dpa_3_5_3[1]} + {1'b0, dpa_3_6_0[0]} + {1'b0, dpa_3_6_1[0]};
  wire [1:0] dpa_4_6_2;
  assign dpa_4_6_2 = {1'b0, dpa_3_6_2[0]} + {1'b0, dpa_3_6_3[0]} + {1'b0, dpa_terms_i[32][6]};
  wire [1:0] dpa_4_7_0;
  assign dpa_4_7_0 = {1'b0, dpa_3_6_0[1]} + {1'b0, dpa_3_6_1[1]} + {1'b0, dpa_3_6_2[1]};
  wire [1:0] dpa_4_7_1;
  assign dpa_4_7_1 = {1'b0, dpa_3_6_3[1]} + {1'b0, dpa_3_7_0[0]} + {1'b0, dpa_3_7_1[0]};
  wire [1:0] dpa_4_7_2;
  assign dpa_4_7_2 = {1'b0, dpa_3_7_2[0]} + {1'b0, dpa_3_7_3[0]} + {1'b0, dpa_terms_i[32][7]};
  wire [1:0] dpa_4_8_0;
  assign dpa_4_8_0 = {1'b0, dpa_3_7_0[1]} + {1'b0, dpa_3_7_1[1]} + {1'b0, dpa_3_7_2[1]};
  wire [1:0] dpa_4_8_1;
  assign dpa_4_8_1 = {1'b0, dpa_3_7_3[1]} + {1'b0, dpa_3_8_0[0]} + {1'b0, dpa_3_8_1[0]};
  wire [1:0] dpa_4_8_2;
  assign dpa_4_8_2 = {1'b0, dpa_3_8_2[0]} + {1'b0, dpa_3_8_3[0]} + {1'b0, dpa_terms_i[32][8]};
  wire [1:0] dpa_4_9_0;
  assign dpa_4_9_0 = {1'b0, dpa_3_8_0[1]} + {1'b0, dpa_3_8_1[1]} + {1'b0, dpa_3_8_2[1]};
  wire [1:0] dpa_4_9_1;
  assign dpa_4_9_1 = {1'b0, dpa_3_8_3[1]} + {1'b0, dpa_3_9_0[0]} + {1'b0, dpa_3_9_1[0]};
  wire [1:0] dpa_4_9_2;
  assign dpa_4_9_2 = {1'b0, dpa_3_9_2[0]} + {1'b0, dpa_3_9_3[0]} + {1'b0, dpa_terms_i[32][9]};
  wire [1:0] dpa_4_10_0;
  assign dpa_4_10_0 = {1'b0, dpa_3_9_0[1]} + {1'b0, dpa_3_9_1[1]} + {1'b0, dpa_3_9_2[1]};
  wire [1:0] dpa_4_10_1;
  assign dpa_4_10_1 = {1'b0, dpa_3_9_3[1]} + {1'b0, dpa_3_10_0[0]} + {1'b0, dpa_3_10_1[0]};
  wire [1:0] dpa_4_10_2;
  assign dpa_4_10_2 = {1'b0, dpa_3_10_2[0]} + {1'b0, dpa_3_10_3[0]} + {1'b0, dpa_terms_i[32][10]};
  wire [1:0] dpa_4_11_0;
  assign dpa_4_11_0 = {1'b0, dpa_3_10_0[1]} + {1'b0, dpa_3_10_1[1]} + {1'b0, dpa_3_10_2[1]};
  wire [1:0] dpa_4_11_1;
  assign dpa_4_11_1 = {1'b0, dpa_3_10_3[1]} + {1'b0, dpa_3_11_0[0]} + {1'b0, dpa_3_11_1[0]};
  wire [1:0] dpa_4_11_2;
  assign dpa_4_11_2 = {1'b0, dpa_3_11_2[0]} + {1'b0, dpa_3_11_3[0]} + {1'b0, dpa_terms_i[32][11]};
  wire [1:0] dpa_4_12_0;
  assign dpa_4_12_0 = {1'b0, dpa_3_11_0[1]} + {1'b0, dpa_3_11_1[1]} + {1'b0, dpa_3_11_2[1]};
  wire [1:0] dpa_4_12_1;
  assign dpa_4_12_1 = {1'b0, dpa_3_11_3[1]} + {1'b0, dpa_3_12_0[0]} + {1'b0, dpa_3_12_1[0]};
  wire [1:0] dpa_4_12_2;
  assign dpa_4_12_2 = {1'b0, dpa_3_12_2[0]} + {1'b0, dpa_3_12_3[0]} + {1'b0, dpa_terms_i[32][12]};
  wire [1:0] dpa_4_13_0;
  assign dpa_4_13_0 = {1'b0, dpa_3_12_0[1]} + {1'b0, dpa_3_12_1[1]} + {1'b0, dpa_3_12_2[1]};
  wire [1:0] dpa_4_13_1;
  assign dpa_4_13_1 = {1'b0, dpa_3_12_3[1]} + {1'b0, dpa_3_13_0[0]} + {1'b0, dpa_3_13_1[0]};
  wire [1:0] dpa_4_13_2;
  assign dpa_4_13_2 = {1'b0, dpa_3_13_2[0]} + {1'b0, dpa_3_13_3[0]} + {1'b0, dpa_terms_i[32][13]};
  wire [1:0] dpa_4_14_0;
  assign dpa_4_14_0 = {1'b0, dpa_3_13_0[1]} + {1'b0, dpa_3_13_1[1]} + {1'b0, dpa_3_13_2[1]};
  wire [1:0] dpa_4_14_1;
  assign dpa_4_14_1 = {1'b0, dpa_3_13_3[1]} + {1'b0, dpa_3_14_0[0]} + {1'b0, dpa_3_14_1[0]};
  wire [1:0] dpa_4_14_2;
  assign dpa_4_14_2 = {1'b0, dpa_3_14_2[0]} + {1'b0, dpa_3_14_3[0]} + {1'b0, dpa_terms_i[32][14]};
  wire [1:0] dpa_4_15_0;
  assign dpa_4_15_0 = {1'b0, dpa_3_14_0[1]} + {1'b0, dpa_3_14_1[1]} + {1'b0, dpa_3_14_2[1]};
  wire [1:0] dpa_4_15_1;
  assign dpa_4_15_1 = {1'b0, dpa_3_14_3[1]} + {1'b0, dpa_3_15_0[0]} + {1'b0, dpa_3_15_1[0]};
  wire [1:0] dpa_4_15_2;
  assign dpa_4_15_2 = {1'b0, dpa_3_15_2[0]} + {1'b0, dpa_3_15_3[0]} + {1'b0, dpa_terms_i[32][15]};
  wire [1:0] dpa_4_16_0;
  assign dpa_4_16_0 = {1'b0, dpa_3_15_0[1]} + {1'b0, dpa_3_15_1[1]} + {1'b0, dpa_3_15_2[1]};
  wire [1:0] dpa_4_16_1;
  assign dpa_4_16_1 = {1'b0, dpa_3_15_3[1]} + {1'b0, dpa_3_16_0[0]} + {1'b0, dpa_3_16_1[0]};
  wire [1:0] dpa_4_16_2;
  assign dpa_4_16_2 = {1'b0, dpa_3_16_2[0]} + {1'b0, dpa_3_16_3[0]} + {1'b0, dpa_terms_i[32][16]};
  wire [1:0] dpa_4_17_0;
  assign dpa_4_17_0 = {1'b0, dpa_3_16_0[1]} + {1'b0, dpa_3_16_1[1]} + {1'b0, dpa_3_16_2[1]};
  wire [1:0] dpa_4_17_1;
  assign dpa_4_17_1 = {1'b0, dpa_3_16_3[1]} + {1'b0, dpa_3_17_0[0]} + {1'b0, dpa_3_17_1[0]};
  wire [1:0] dpa_4_17_2;
  assign dpa_4_17_2 = {1'b0, dpa_3_17_2[0]} + {1'b0, dpa_3_17_3[0]} + {1'b0, dpa_terms_i[32][17]};
  wire [1:0] dpa_4_18_0;
  assign dpa_4_18_0 = {1'b0, dpa_3_17_0[1]} + {1'b0, dpa_3_17_1[1]} + {1'b0, dpa_3_17_2[1]};
  wire [1:0] dpa_4_18_1;
  assign dpa_4_18_1 = {1'b0, dpa_3_17_3[1]} + {1'b0, dpa_3_18_0[0]} + {1'b0, dpa_3_18_1[0]};
  wire [1:0] dpa_4_18_2;
  assign dpa_4_18_2 = {1'b0, dpa_3_18_2[0]} + {1'b0, dpa_3_18_3[0]} + {1'b0, dpa_terms_i[32][18]};
  wire [1:0] dpa_4_19_0;
  assign dpa_4_19_0 = {1'b0, dpa_3_18_0[1]} + {1'b0, dpa_3_18_1[1]} + {1'b0, dpa_3_18_2[1]};
  wire [1:0] dpa_4_19_1;
  assign dpa_4_19_1 = {1'b0, dpa_3_18_3[1]} + {1'b0, dpa_3_19_0[0]} + {1'b0, dpa_3_19_1[0]};
  wire [1:0] dpa_4_19_2;
  assign dpa_4_19_2 = {1'b0, dpa_3_19_2[0]} + {1'b0, dpa_3_19_3[0]} + {1'b0, dpa_terms_i[32][19]};
  wire [1:0] dpa_4_20_0;
  assign dpa_4_20_0 = {1'b0, dpa_3_19_0[1]} + {1'b0, dpa_3_19_1[1]} + {1'b0, dpa_3_19_2[1]};
  wire [1:0] dpa_4_20_1;
  assign dpa_4_20_1 = {1'b0, dpa_3_19_3[1]} + {1'b0, dpa_3_20_0[0]} + {1'b0, dpa_3_20_1[0]};
  wire [1:0] dpa_4_20_2;
  assign dpa_4_20_2 = {1'b0, dpa_3_20_2[0]} + {1'b0, dpa_3_20_3[0]} + {1'b0, dpa_terms_i[32][20]};
  wire [1:0] dpa_4_21_0;
  assign dpa_4_21_0 = {1'b0, dpa_3_20_0[1]} + {1'b0, dpa_3_20_1[1]} + {1'b0, dpa_3_20_2[1]};
  wire [1:0] dpa_4_21_1;
  assign dpa_4_21_1 = {1'b0, dpa_3_20_3[1]} + {1'b0, dpa_3_21_0[0]} + {1'b0, dpa_3_21_1[0]};
  wire [1:0] dpa_4_21_2;
  assign dpa_4_21_2 = {1'b0, dpa_3_21_2[0]} + {1'b0, dpa_3_21_3[0]} + {1'b0, dpa_terms_i[32][21]};
  wire [1:0] dpa_4_22_0;
  assign dpa_4_22_0 = {1'b0, dpa_3_21_0[1]} + {1'b0, dpa_3_21_1[1]} + {1'b0, dpa_3_21_2[1]};
  wire [1:0] dpa_4_22_1;
  assign dpa_4_22_1 = {1'b0, dpa_3_21_3[1]} + {1'b0, dpa_3_22_0[0]} + {1'b0, dpa_3_22_1[0]};
  wire [1:0] dpa_4_22_2;
  assign dpa_4_22_2 = {1'b0, dpa_3_22_2[0]} + {1'b0, dpa_3_22_3[0]} + {1'b0, dpa_terms_i[32][22]};
  wire [1:0] dpa_4_23_0;
  assign dpa_4_23_0 = {1'b0, dpa_3_22_0[1]} + {1'b0, dpa_3_22_1[1]} + {1'b0, dpa_3_22_2[1]};
  wire [1:0] dpa_4_23_1;
  assign dpa_4_23_1 = {1'b0, dpa_3_22_3[1]} + {1'b0, dpa_3_23_0[0]} + {1'b0, dpa_3_23_1[0]};
  wire [1:0] dpa_4_23_2;
  assign dpa_4_23_2 = {1'b0, dpa_3_23_2[0]} + {1'b0, dpa_3_23_3[0]} + {1'b0, dpa_terms_i[32][23]};
  wire [1:0] dpa_4_24_0;
  assign dpa_4_24_0 = {1'b0, dpa_3_23_0[1]} + {1'b0, dpa_3_23_1[1]} + {1'b0, dpa_3_23_2[1]};
  wire [1:0] dpa_4_24_1;
  assign dpa_4_24_1 = {1'b0, dpa_3_23_3[1]} + {1'b0, dpa_3_24_0[0]} + {1'b0, dpa_3_24_1[0]};
  wire [1:0] dpa_4_24_2;
  assign dpa_4_24_2 = {1'b0, dpa_3_24_2[0]} + {1'b0, dpa_3_24_3[0]} + {1'b0, dpa_terms_i[32][24]};
  wire [1:0] dpa_4_25_0;
  assign dpa_4_25_0 = {1'b0, dpa_3_24_0[1]} + {1'b0, dpa_3_24_1[1]} + {1'b0, dpa_3_24_2[1]};
  wire [1:0] dpa_4_25_1;
  assign dpa_4_25_1 = {1'b0, dpa_3_24_3[1]} + {1'b0, dpa_3_25_0[0]} + {1'b0, dpa_3_25_1[0]};
  wire [1:0] dpa_4_25_2;
  assign dpa_4_25_2 = {1'b0, dpa_3_25_2[0]} + {1'b0, dpa_3_25_3[0]} + {1'b0, dpa_terms_i[32][25]};
  wire [1:0] dpa_4_26_0;
  assign dpa_4_26_0 = {1'b0, dpa_3_25_0[1]} + {1'b0, dpa_3_25_1[1]} + {1'b0, dpa_3_25_2[1]};
  wire [1:0] dpa_4_26_1;
  assign dpa_4_26_1 = {1'b0, dpa_3_25_3[1]} + {1'b0, dpa_3_26_0[0]} + {1'b0, dpa_3_26_1[0]};
  wire [1:0] dpa_4_26_2;
  assign dpa_4_26_2 = {1'b0, dpa_3_26_2[0]} + {1'b0, dpa_3_26_3[0]} + {1'b0, dpa_terms_i[32][26]};
  wire [1:0] dpa_4_27_0;
  assign dpa_4_27_0 = {1'b0, dpa_3_26_0[1]} + {1'b0, dpa_3_26_1[1]} + {1'b0, dpa_3_26_2[1]};
  wire [1:0] dpa_4_27_1;
  assign dpa_4_27_1 = {1'b0, dpa_3_26_3[1]} + {1'b0, dpa_3_27_0[0]} + {1'b0, dpa_3_27_1[0]};
  wire [1:0] dpa_4_27_2;
  assign dpa_4_27_2 = {1'b0, dpa_3_27_2[0]} + {1'b0, dpa_3_27_3[0]} + {1'b0, negative_mod[0]};
  wire [1:0] dpa_4_28_0;
  assign dpa_4_28_0 = {1'b0, dpa_3_27_0[1]} + {1'b0, dpa_3_27_1[1]} + {1'b0, dpa_3_27_2[1]};
  wire [1:0] dpa_4_28_1;
  assign dpa_4_28_1 = {1'b0, dpa_3_27_3[1]} + {1'b0, dpa_3_28_0[0]} + {1'b0, dpa_2_27_2[1]};
  wire [1:0] dpa_4_28_2;
  assign dpa_4_28_2 = {1'b0, dpa_2_27_3[1]} + {1'b0, dpa_2_27_4[1]} + {1'b0, negative_mod[1]};
  wire [1:0] scalar_0_22_0;
  assign scalar_0_22_0 = {1'b0, scalar_rows_i[1][22]} + {1'b0, scalar_rows_i[2][22]};
  wire [1:0] scalar_0_23_0;
  assign scalar_0_23_0 = {1'b0, scalar_rows_i[1][23]} + {1'b0, scalar_rows_i[2][23]} + {1'b0, scalar_rows_i[3][23]};
  wire [1:0] scalar_0_24_0;
  assign scalar_0_24_0 = {1'b0, scalar_rows_i[1][24]} + {1'b0, scalar_rows_i[2][24]} + {1'b0, scalar_rows_i[3][24]};
  wire [1:0] scalar_0_25_0;
  assign scalar_0_25_0 = {1'b0, scalar_rows_i[1][25]} + {1'b0, scalar_rows_i[2][25]} + {1'b0, scalar_rows_i[3][25]};
  wire [1:0] scalar_0_26_0;
  assign scalar_0_26_0 = {1'b0, scalar_rows_i[1][26]} + {1'b0, scalar_rows_i[2][26]} + {1'b0, scalar_rows_i[3][26]};
  wire [1:0] scalar_0_27_0;
  assign scalar_0_27_0 = {1'b0, scalar_rows_i[1][27]} + {1'b0, scalar_rows_i[2][27]} + {1'b0, scalar_rows_i[3][27]};
  wire [1:0] scalar_0_28_0;
  assign scalar_0_28_0 = {1'b0, scalar_rows_i[1][28]} + {1'b0, scalar_rows_i[2][28]} + {1'b0, scalar_rows_i[3][28]};
  wire [1:0] scalar_0_29_0;
  assign scalar_0_29_0 = {1'b0, scalar_rows_i[1][29]} + {1'b0, scalar_rows_i[2][29]} + {1'b0, scalar_rows_i[3][29]};
  wire [1:0] scalar_0_30_0;
  assign scalar_0_30_0 = {1'b0, scalar_rows_i[1][30]} + {1'b0, scalar_rows_i[2][30]} + {1'b0, scalar_rows_i[3][30]};
  wire [1:0] scalar_0_31_0;
  assign scalar_0_31_0 = {1'b0, scalar_rows_i[1][31]} + {1'b0, scalar_rows_i[2][31]} + {1'b0, scalar_rows_i[3][31]};
  wire [1:0] scalar_0_32_0;
  assign scalar_0_32_0 = {1'b0, scalar_rows_i[1][32]} + {1'b0, scalar_rows_i[2][32]} + {1'b0, scalar_rows_i[3][32]};
  wire [1:0] scalar_1_11_0;
  assign scalar_1_11_0 = {1'b0, scalar_rows_i[0][11]} + {1'b0, scalar_rows_i[1][11]} + {1'b0, scalar_rows_i[3][11]};
  wire [1:0] scalar_1_12_0;
  assign scalar_1_12_0 = {1'b0, scalar_rows_i[0][12]} + {1'b0, scalar_rows_i[1][12]} + {1'b0, scalar_rows_i[3][12]};
  wire [1:0] scalar_1_12_1;
  assign scalar_1_12_1 = {1'b0, scalar_rows_i[6][12]} + {1'b0, scalar_rows_i[7][12]};
  wire [1:0] scalar_1_13_0;
  assign scalar_1_13_0 = {1'b0, scalar_rows_i[0][13]} + {1'b0, scalar_rows_i[1][13]} + {1'b0, scalar_rows_i[3][13]};
  wire [1:0] scalar_1_13_1;
  assign scalar_1_13_1 = {1'b0, scalar_rows_i[6][13]} + {1'b0, scalar_rows_i[7][13]} + {1'b0, scalar_rows_i[8][13]};
  wire [1:0] scalar_1_14_0;
  assign scalar_1_14_0 = {1'b0, scalar_rows_i[0][14]} + {1'b0, scalar_rows_i[1][14]} + {1'b0, scalar_rows_i[3][14]};
  wire [1:0] scalar_1_14_1;
  assign scalar_1_14_1 = {1'b0, scalar_rows_i[6][14]} + {1'b0, scalar_rows_i[7][14]} + {1'b0, scalar_rows_i[8][14]};
  wire [1:0] scalar_1_15_0;
  assign scalar_1_15_0 = {1'b0, scalar_rows_i[0][15]} + {1'b0, scalar_rows_i[1][15]} + {1'b0, scalar_rows_i[3][15]};
  wire [1:0] scalar_1_15_1;
  assign scalar_1_15_1 = {1'b0, scalar_rows_i[6][15]} + {1'b0, scalar_rows_i[7][15]} + {1'b0, scalar_rows_i[8][15]};
  wire [1:0] scalar_1_16_0;
  assign scalar_1_16_0 = {1'b0, scalar_rows_i[0][16]} + {1'b0, scalar_rows_i[1][16]} + {1'b0, scalar_rows_i[3][16]};
  wire [1:0] scalar_1_16_1;
  assign scalar_1_16_1 = {1'b0, scalar_rows_i[6][16]} + {1'b0, scalar_rows_i[7][16]} + {1'b0, scalar_rows_i[8][16]};
  wire [1:0] scalar_1_17_0;
  assign scalar_1_17_0 = {1'b0, scalar_rows_i[0][17]} + {1'b0, scalar_rows_i[1][17]} + {1'b0, scalar_rows_i[3][17]};
  wire [1:0] scalar_1_17_1;
  assign scalar_1_17_1 = {1'b0, scalar_rows_i[6][17]} + {1'b0, scalar_rows_i[7][17]} + {1'b0, scalar_rows_i[8][17]};
  wire [1:0] scalar_1_18_0;
  assign scalar_1_18_0 = {1'b0, scalar_rows_i[0][18]} + {1'b0, scalar_rows_i[1][18]} + {1'b0, scalar_rows_i[3][18]};
  wire [1:0] scalar_1_18_1;
  assign scalar_1_18_1 = {1'b0, scalar_rows_i[6][18]} + {1'b0, scalar_rows_i[7][18]} + {1'b0, scalar_rows_i[8][18]};
  wire [1:0] scalar_1_19_0;
  assign scalar_1_19_0 = {1'b0, scalar_rows_i[0][19]} + {1'b0, scalar_rows_i[1][19]} + {1'b0, scalar_rows_i[3][19]};
  wire [1:0] scalar_1_19_1;
  assign scalar_1_19_1 = {1'b0, scalar_rows_i[6][19]} + {1'b0, scalar_rows_i[7][19]} + {1'b0, scalar_rows_i[8][19]};
  wire [1:0] scalar_1_20_0;
  assign scalar_1_20_0 = {1'b0, scalar_rows_i[0][20]} + {1'b0, scalar_rows_i[1][20]} + {1'b0, scalar_rows_i[3][20]};
  wire [1:0] scalar_1_20_1;
  assign scalar_1_20_1 = {1'b0, scalar_rows_i[6][20]} + {1'b0, scalar_rows_i[7][20]} + {1'b0, scalar_rows_i[8][20]};
  wire [1:0] scalar_1_21_0;
  assign scalar_1_21_0 = {1'b0, scalar_rows_i[0][21]} + {1'b0, scalar_rows_i[1][21]} + {1'b0, scalar_rows_i[3][21]};
  wire [1:0] scalar_1_21_1;
  assign scalar_1_21_1 = {1'b0, scalar_rows_i[6][21]} + {1'b0, scalar_rows_i[7][21]} + {1'b0, scalar_rows_i[8][21]};
  wire [1:0] scalar_1_22_0;
  assign scalar_1_22_0 = {1'b0, scalar_0_22_0[0]} + {1'b0, scalar_rows_i[3][22]} + {1'b0, scalar_rows_i[4][22]};
  wire [1:0] scalar_1_22_1;
  assign scalar_1_22_1 = {1'b0, scalar_rows_i[6][22]} + {1'b0, scalar_rows_i[7][22]} + {1'b0, scalar_rows_i[8][22]};
  wire [1:0] scalar_1_22_2;
  assign scalar_1_22_2 = {1'b0, scalar_rows_i[9][22]} + {1'b0, scalar_rows_i[10][22]};
  wire [1:0] scalar_1_23_0;
  assign scalar_1_23_0 = {1'b0, scalar_0_22_0[1]} + {1'b0, scalar_0_23_0[0]} + {1'b0, scalar_rows_i[4][23]};
  wire [1:0] scalar_1_23_1;
  assign scalar_1_23_1 = {1'b0, scalar_rows_i[6][23]} + {1'b0, scalar_rows_i[7][23]} + {1'b0, scalar_rows_i[8][23]};
  wire [1:0] scalar_1_23_2;
  assign scalar_1_23_2 = {1'b0, scalar_rows_i[9][23]} + {1'b0, scalar_rows_i[10][23]} + {1'b0, scalar_rows_i[11][23]};
  wire [1:0] scalar_1_24_0;
  assign scalar_1_24_0 = {1'b0, scalar_0_23_0[1]} + {1'b0, scalar_0_24_0[0]} + {1'b0, scalar_rows_i[4][24]};
  wire [1:0] scalar_1_24_1;
  assign scalar_1_24_1 = {1'b0, scalar_rows_i[6][24]} + {1'b0, scalar_rows_i[7][24]} + {1'b0, scalar_rows_i[8][24]};
  wire [1:0] scalar_1_24_2;
  assign scalar_1_24_2 = {1'b0, scalar_rows_i[9][24]} + {1'b0, scalar_rows_i[10][24]} + {1'b0, scalar_rows_i[11][24]};
  wire [1:0] scalar_1_25_0;
  assign scalar_1_25_0 = {1'b0, scalar_0_24_0[1]} + {1'b0, scalar_0_25_0[0]} + {1'b0, scalar_rows_i[4][25]};
  wire [1:0] scalar_1_25_1;
  assign scalar_1_25_1 = {1'b0, scalar_rows_i[6][25]} + {1'b0, scalar_rows_i[7][25]} + {1'b0, scalar_rows_i[8][25]};
  wire [1:0] scalar_1_25_2;
  assign scalar_1_25_2 = {1'b0, scalar_rows_i[9][25]} + {1'b0, scalar_rows_i[10][25]} + {1'b0, scalar_rows_i[11][25]};
  wire [1:0] scalar_1_26_0;
  assign scalar_1_26_0 = {1'b0, scalar_0_25_0[1]} + {1'b0, scalar_0_26_0[0]} + {1'b0, scalar_rows_i[4][26]};
  wire [1:0] scalar_1_26_1;
  assign scalar_1_26_1 = {1'b0, scalar_rows_i[6][26]} + {1'b0, scalar_rows_i[7][26]} + {1'b0, scalar_rows_i[8][26]};
  wire [1:0] scalar_1_26_2;
  assign scalar_1_26_2 = {1'b0, scalar_rows_i[9][26]} + {1'b0, scalar_rows_i[10][26]} + {1'b0, scalar_rows_i[11][26]};
  wire [1:0] scalar_1_27_0;
  assign scalar_1_27_0 = {1'b0, scalar_0_26_0[1]} + {1'b0, scalar_0_27_0[0]} + {1'b0, scalar_rows_i[4][27]};
  wire [1:0] scalar_1_27_1;
  assign scalar_1_27_1 = {1'b0, scalar_rows_i[6][27]} + {1'b0, scalar_rows_i[7][27]} + {1'b0, scalar_rows_i[8][27]};
  wire [1:0] scalar_1_27_2;
  assign scalar_1_27_2 = {1'b0, scalar_rows_i[9][27]} + {1'b0, scalar_rows_i[10][27]} + {1'b0, scalar_rows_i[11][27]};
  wire [1:0] scalar_1_28_0;
  assign scalar_1_28_0 = {1'b0, scalar_0_27_0[1]} + {1'b0, scalar_0_28_0[0]} + {1'b0, scalar_rows_i[4][28]};
  wire [1:0] scalar_1_28_1;
  assign scalar_1_28_1 = {1'b0, scalar_rows_i[6][28]} + {1'b0, scalar_rows_i[7][28]} + {1'b0, scalar_rows_i[8][28]};
  wire [1:0] scalar_1_28_2;
  assign scalar_1_28_2 = {1'b0, scalar_rows_i[9][28]} + {1'b0, scalar_rows_i[10][28]} + {1'b0, scalar_rows_i[11][28]};
  wire [1:0] scalar_1_29_0;
  assign scalar_1_29_0 = {1'b0, scalar_0_28_0[1]} + {1'b0, scalar_0_29_0[0]} + {1'b0, scalar_rows_i[4][29]};
  wire [1:0] scalar_1_29_1;
  assign scalar_1_29_1 = {1'b0, scalar_rows_i[6][29]} + {1'b0, scalar_rows_i[7][29]} + {1'b0, scalar_rows_i[8][29]};
  wire [1:0] scalar_1_29_2;
  assign scalar_1_29_2 = {1'b0, scalar_rows_i[9][29]} + {1'b0, scalar_rows_i[10][29]} + {1'b0, scalar_rows_i[11][29]};
  wire [1:0] scalar_1_30_0;
  assign scalar_1_30_0 = {1'b0, scalar_0_29_0[1]} + {1'b0, scalar_0_30_0[0]} + {1'b0, scalar_rows_i[4][30]};
  wire [1:0] scalar_1_30_1;
  assign scalar_1_30_1 = {1'b0, scalar_rows_i[6][30]} + {1'b0, scalar_rows_i[7][30]} + {1'b0, scalar_rows_i[8][30]};
  wire [1:0] scalar_1_30_2;
  assign scalar_1_30_2 = {1'b0, scalar_rows_i[9][30]} + {1'b0, scalar_rows_i[10][30]} + {1'b0, scalar_rows_i[11][30]};
  wire [1:0] scalar_1_31_0;
  assign scalar_1_31_0 = {1'b0, scalar_0_30_0[1]} + {1'b0, scalar_0_31_0[0]} + {1'b0, scalar_rows_i[4][31]};
  wire [1:0] scalar_1_31_1;
  assign scalar_1_31_1 = {1'b0, scalar_rows_i[6][31]} + {1'b0, scalar_rows_i[7][31]} + {1'b0, scalar_rows_i[8][31]};
  wire [1:0] scalar_1_31_2;
  assign scalar_1_31_2 = {1'b0, scalar_rows_i[9][31]} + {1'b0, scalar_rows_i[10][31]} + {1'b0, scalar_rows_i[11][31]};
  wire [1:0] scalar_1_32_0;
  assign scalar_1_32_0 = {1'b0, scalar_0_31_0[1]} + {1'b0, scalar_0_32_0[0]} + {1'b0, scalar_rows_i[4][32]};
  wire [1:0] scalar_1_32_1;
  assign scalar_1_32_1 = {1'b0, scalar_rows_i[6][32]} + {1'b0, scalar_rows_i[7][32]} + {1'b0, scalar_rows_i[8][32]};
  wire [1:0] scalar_1_32_2;
  assign scalar_1_32_2 = {1'b0, scalar_rows_i[9][32]} + {1'b0, scalar_rows_i[10][32]} + {1'b0, scalar_rows_i[11][32]};
  wire [1:0] scalar_1_33_0;
  assign scalar_1_33_0 = {1'b0, scalar_0_32_0[1]} + {1'b0, scalar_rows_i[2][33]} + {1'b0, scalar_rows_i[4][33]};
  wire [1:0] scalar_1_33_1;
  assign scalar_1_33_1 = {1'b0, scalar_rows_i[5][33]} + {1'b0, scalar_rows_i[6][33]} + {1'b0, scalar_rows_i[7][33]};
  wire [1:0] scalar_1_33_2;
  assign scalar_1_33_2 = {1'b0, scalar_rows_i[9][33]} + {1'b0, scalar_rows_i[10][33]} + {1'b0, scalar_rows_i[11][33]};
  wire [1:0] scalar_1_34_0;
  assign scalar_1_34_0 = {1'b0, scalar_rows_i[2][34]} + {1'b0, scalar_rows_i[4][34]} + {1'b0, scalar_rows_i[5][34]};
  wire [1:0] scalar_1_34_1;
  assign scalar_1_34_1 = {1'b0, scalar_rows_i[6][34]} + {1'b0, scalar_rows_i[7][34]} + {1'b0, scalar_rows_i[9][34]};
  wire [1:0] scalar_1_34_2;
  assign scalar_1_34_2 = {1'b0, scalar_rows_i[10][34]} + {1'b0, scalar_rows_i[11][34]};
  wire [1:0] scalar_1_35_0;
  assign scalar_1_35_0 = {1'b0, scalar_rows_i[2][35]} + {1'b0, scalar_rows_i[4][35]} + {1'b0, scalar_rows_i[5][35]};
  wire [1:0] scalar_1_35_1;
  assign scalar_1_35_1 = {1'b0, scalar_rows_i[6][35]} + {1'b0, scalar_rows_i[7][35]} + {1'b0, scalar_rows_i[9][35]};
  wire [1:0] scalar_1_35_2;
  assign scalar_1_35_2 = {1'b0, scalar_rows_i[10][35]} + {1'b0, scalar_rows_i[11][35]};
  wire [1:0] scalar_1_36_0;
  assign scalar_1_36_0 = {1'b0, scalar_rows_i[2][36]} + {1'b0, scalar_rows_i[4][36]} + {1'b0, scalar_rows_i[5][36]};
  wire [1:0] scalar_1_36_1;
  assign scalar_1_36_1 = {1'b0, scalar_rows_i[6][36]} + {1'b0, scalar_rows_i[7][36]} + {1'b0, scalar_rows_i[9][36]};
  wire [1:0] scalar_1_36_2;
  assign scalar_1_36_2 = {1'b0, scalar_rows_i[10][36]} + {1'b0, scalar_rows_i[11][36]};
  wire [1:0] scalar_1_37_0;
  assign scalar_1_37_0 = {1'b0, scalar_rows_i[2][37]} + {1'b0, scalar_rows_i[4][37]} + {1'b0, scalar_rows_i[5][37]};
  wire [1:0] scalar_1_37_1;
  assign scalar_1_37_1 = {1'b0, scalar_rows_i[6][37]} + {1'b0, scalar_rows_i[7][37]} + {1'b0, scalar_rows_i[9][37]};
  wire [1:0] scalar_1_37_2;
  assign scalar_1_37_2 = {1'b0, scalar_rows_i[10][37]} + {1'b0, scalar_rows_i[11][37]};
  wire [1:0] scalar_1_38_0;
  assign scalar_1_38_0 = {1'b0, scalar_rows_i[2][38]} + {1'b0, scalar_rows_i[4][38]} + {1'b0, scalar_rows_i[5][38]};
  wire [1:0] scalar_1_38_1;
  assign scalar_1_38_1 = {1'b0, scalar_rows_i[6][38]} + {1'b0, scalar_rows_i[7][38]} + {1'b0, scalar_rows_i[9][38]};
  wire [1:0] scalar_1_38_2;
  assign scalar_1_38_2 = {1'b0, scalar_rows_i[10][38]} + {1'b0, scalar_rows_i[11][38]};
  wire [1:0] scalar_1_39_0;
  assign scalar_1_39_0 = {1'b0, scalar_rows_i[2][39]} + {1'b0, scalar_rows_i[4][39]} + {1'b0, scalar_rows_i[5][39]};
  wire [1:0] scalar_1_39_1;
  assign scalar_1_39_1 = {1'b0, scalar_rows_i[6][39]} + {1'b0, scalar_rows_i[7][39]} + {1'b0, scalar_rows_i[9][39]};
  wire [1:0] scalar_1_39_2;
  assign scalar_1_39_2 = {1'b0, scalar_rows_i[10][39]} + {1'b0, scalar_rows_i[11][39]};
  wire [1:0] scalar_1_40_0;
  assign scalar_1_40_0 = {1'b0, scalar_rows_i[2][40]} + {1'b0, scalar_rows_i[4][40]} + {1'b0, scalar_rows_i[5][40]};
  wire [1:0] scalar_1_40_1;
  assign scalar_1_40_1 = {1'b0, scalar_rows_i[6][40]} + {1'b0, scalar_rows_i[7][40]} + {1'b0, scalar_rows_i[9][40]};
  wire [1:0] scalar_1_40_2;
  assign scalar_1_40_2 = {1'b0, scalar_rows_i[10][40]} + {1'b0, scalar_rows_i[11][40]};
  wire [1:0] scalar_1_41_0;
  assign scalar_1_41_0 = {1'b0, scalar_rows_i[2][41]} + {1'b0, scalar_rows_i[4][41]} + {1'b0, scalar_rows_i[5][41]};
  wire [1:0] scalar_1_41_1;
  assign scalar_1_41_1 = {1'b0, scalar_rows_i[6][41]} + {1'b0, scalar_rows_i[7][41]} + {1'b0, scalar_rows_i[9][41]};
  wire [1:0] scalar_1_41_2;
  assign scalar_1_41_2 = {1'b0, scalar_rows_i[10][41]} + {1'b0, scalar_rows_i[11][41]};
  wire [1:0] scalar_1_42_0;
  assign scalar_1_42_0 = {1'b0, scalar_rows_i[2][42]} + {1'b0, scalar_rows_i[4][42]} + {1'b0, scalar_rows_i[5][42]};
  wire [1:0] scalar_1_42_1;
  assign scalar_1_42_1 = {1'b0, scalar_rows_i[6][42]} + {1'b0, scalar_rows_i[7][42]} + {1'b0, scalar_rows_i[9][42]};
  wire [1:0] scalar_1_42_2;
  assign scalar_1_42_2 = {1'b0, scalar_rows_i[10][42]} + {1'b0, scalar_rows_i[11][42]};
  wire [1:0] scalar_1_43_0;
  assign scalar_1_43_0 = {1'b0, scalar_rows_i[2][43]} + {1'b0, scalar_rows_i[4][43]} + {1'b0, scalar_rows_i[5][43]};
  wire [1:0] scalar_1_43_1;
  assign scalar_1_43_1 = {1'b0, scalar_rows_i[6][43]} + {1'b0, scalar_rows_i[7][43]} + {1'b0, scalar_rows_i[9][43]};
  wire [1:0] scalar_1_43_2;
  assign scalar_1_43_2 = {1'b0, scalar_rows_i[10][43]} + {1'b0, scalar_rows_i[11][43]};
  wire [1:0] scalar_1_44_0;
  assign scalar_1_44_0 = {1'b0, scalar_rows_i[5][44]} + {1'b0, scalar_rows_i[7][44]} + {1'b0, scalar_rows_i[8][44]};
  wire merge_0_0 = dpa_i ? dpa_4_0_0[0] : scalar_rows_i[0][0];
  wire merge_0_1 = dpa_i ? dpa_4_0_1[0] : scalar_rows_i[6][0];
  wire merge_0_2 = dpa_i ? dpa_terms_i[30][0] : scalar_rows_i[10][0];
  wire merge_0_3 = dpa_i ? dpa_terms_i[31][0] : scalar_rows_i[11][0];
  wire merge_0_4 = dpa_i ? dpa_terms_i[32][0] : 1'b0;
  wire merge_0_5 = dpa_i ? negative_count_i[0] : 1'b0;
  wire merge_1_0 = dpa_i ? dpa_4_0_0[1] : scalar_rows_i[0][1];
  wire merge_1_1 = dpa_i ? dpa_4_0_1[1] : scalar_rows_i[6][1];
  wire merge_1_2 = dpa_i ? dpa_4_1_0[0] : scalar_rows_i[10][1];
  wire merge_1_3 = dpa_i ? dpa_4_1_1[0] : scalar_rows_i[11][1];
  wire merge_1_4 = dpa_i ? dpa_4_1_2[0] : scalar_rows_i[12][1];
  wire merge_1_5 = dpa_i ? negative_count_i[1] : 1'b0;
  wire merge_2_0 = dpa_i ? dpa_4_1_0[1] : scalar_rows_i[0][2];
  wire merge_2_1 = dpa_i ? dpa_4_1_1[1] : scalar_rows_i[6][2];
  wire merge_2_2 = dpa_i ? dpa_4_1_2[1] : scalar_rows_i[10][2];
  wire merge_2_3 = dpa_i ? dpa_4_2_0[0] : scalar_rows_i[11][2];
  wire merge_2_4 = dpa_i ? dpa_4_2_1[0] : 1'b0;
  wire merge_2_5 = dpa_i ? dpa_4_2_2[0] : 1'b0;
  wire merge_3_0 = dpa_i ? dpa_4_2_0[1] : scalar_rows_i[0][3];
  wire merge_3_1 = dpa_i ? dpa_4_2_1[1] : scalar_rows_i[6][3];
  wire merge_3_2 = dpa_i ? dpa_4_2_2[1] : scalar_rows_i[10][3];
  wire merge_3_3 = dpa_i ? dpa_4_3_0[0] : scalar_rows_i[11][3];
  wire merge_3_4 = dpa_i ? dpa_4_3_1[0] : 1'b0;
  wire merge_3_5 = dpa_i ? dpa_4_3_2[0] : 1'b0;
  wire merge_4_0 = dpa_i ? dpa_4_3_0[1] : scalar_rows_i[0][4];
  wire merge_4_1 = dpa_i ? dpa_4_3_1[1] : scalar_rows_i[6][4];
  wire merge_4_2 = dpa_i ? dpa_4_3_2[1] : scalar_rows_i[10][4];
  wire merge_4_3 = dpa_i ? dpa_4_4_0[0] : scalar_rows_i[11][4];
  wire merge_4_4 = dpa_i ? dpa_4_4_1[0] : 1'b0;
  wire merge_4_5 = dpa_i ? dpa_4_4_2[0] : 1'b0;
  wire merge_5_0 = dpa_i ? dpa_4_4_0[1] : scalar_rows_i[0][5];
  wire merge_5_1 = dpa_i ? dpa_4_4_1[1] : scalar_rows_i[6][5];
  wire merge_5_2 = dpa_i ? dpa_4_4_2[1] : scalar_rows_i[10][5];
  wire merge_5_3 = dpa_i ? dpa_4_5_0[0] : scalar_rows_i[11][5];
  wire merge_5_4 = dpa_i ? dpa_4_5_1[0] : 1'b0;
  wire merge_5_5 = dpa_i ? dpa_4_5_2[0] : 1'b0;
  wire merge_6_0 = dpa_i ? dpa_4_5_0[1] : scalar_rows_i[0][6];
  wire merge_6_1 = dpa_i ? dpa_4_5_1[1] : scalar_rows_i[6][6];
  wire merge_6_2 = dpa_i ? dpa_4_5_2[1] : scalar_rows_i[10][6];
  wire merge_6_3 = dpa_i ? dpa_4_6_0[0] : scalar_rows_i[11][6];
  wire merge_6_4 = dpa_i ? dpa_4_6_1[0] : 1'b0;
  wire merge_6_5 = dpa_i ? dpa_4_6_2[0] : 1'b0;
  wire merge_7_0 = dpa_i ? dpa_4_6_0[1] : scalar_rows_i[0][7];
  wire merge_7_1 = dpa_i ? dpa_4_6_1[1] : scalar_rows_i[6][7];
  wire merge_7_2 = dpa_i ? dpa_4_6_2[1] : scalar_rows_i[10][7];
  wire merge_7_3 = dpa_i ? dpa_4_7_0[0] : scalar_rows_i[11][7];
  wire merge_7_4 = dpa_i ? dpa_4_7_1[0] : 1'b0;
  wire merge_7_5 = dpa_i ? dpa_4_7_2[0] : 1'b0;
  wire merge_8_0 = dpa_i ? dpa_4_7_0[1] : scalar_rows_i[0][8];
  wire merge_8_1 = dpa_i ? dpa_4_7_1[1] : scalar_rows_i[6][8];
  wire merge_8_2 = dpa_i ? dpa_4_7_2[1] : scalar_rows_i[10][8];
  wire merge_8_3 = dpa_i ? dpa_4_8_0[0] : scalar_rows_i[11][8];
  wire merge_8_4 = dpa_i ? dpa_4_8_1[0] : 1'b0;
  wire merge_8_5 = dpa_i ? dpa_4_8_2[0] : 1'b0;
  wire merge_9_0 = dpa_i ? dpa_4_8_0[1] : scalar_rows_i[0][9];
  wire merge_9_1 = dpa_i ? dpa_4_8_1[1] : scalar_rows_i[6][9];
  wire merge_9_2 = dpa_i ? dpa_4_8_2[1] : scalar_rows_i[10][9];
  wire merge_9_3 = dpa_i ? dpa_4_9_0[0] : scalar_rows_i[11][9];
  wire merge_9_4 = dpa_i ? dpa_4_9_1[0] : 1'b0;
  wire merge_9_5 = dpa_i ? dpa_4_9_2[0] : 1'b0;
  wire merge_10_0 = dpa_i ? dpa_4_9_0[1] : scalar_rows_i[0][10];
  wire merge_10_1 = dpa_i ? dpa_4_9_1[1] : scalar_rows_i[6][10];
  wire merge_10_2 = dpa_i ? dpa_4_9_2[1] : scalar_rows_i[10][10];
  wire merge_10_3 = dpa_i ? dpa_4_10_0[0] : scalar_rows_i[11][10];
  wire merge_10_4 = dpa_i ? dpa_4_10_1[0] : 1'b0;
  wire merge_10_5 = dpa_i ? dpa_4_10_2[0] : 1'b0;
  wire merge_11_0 = dpa_i ? dpa_4_10_0[1] : scalar_1_11_0[0];
  wire merge_11_1 = dpa_i ? dpa_4_10_1[1] : scalar_rows_i[6][11];
  wire merge_11_2 = dpa_i ? dpa_4_10_2[1] : scalar_rows_i[7][11];
  wire merge_11_3 = dpa_i ? dpa_4_11_0[0] : scalar_rows_i[8][11];
  wire merge_11_4 = dpa_i ? dpa_4_11_1[0] : scalar_rows_i[10][11];
  wire merge_11_5 = dpa_i ? dpa_4_11_2[0] : scalar_rows_i[11][11];
  wire merge_12_0 = dpa_i ? dpa_4_11_0[1] : scalar_1_11_0[1];
  wire merge_12_1 = dpa_i ? dpa_4_11_1[1] : scalar_1_12_0[0];
  wire merge_12_2 = dpa_i ? dpa_4_11_2[1] : scalar_1_12_1[0];
  wire merge_12_3 = dpa_i ? dpa_4_12_0[0] : scalar_rows_i[8][12];
  wire merge_12_4 = dpa_i ? dpa_4_12_1[0] : scalar_rows_i[10][12];
  wire merge_12_5 = dpa_i ? dpa_4_12_2[0] : scalar_rows_i[11][12];
  wire merge_13_0 = dpa_i ? dpa_4_12_0[1] : scalar_1_12_0[1];
  wire merge_13_1 = dpa_i ? dpa_4_12_1[1] : scalar_1_12_1[1];
  wire merge_13_2 = dpa_i ? dpa_4_12_2[1] : scalar_1_13_0[0];
  wire merge_13_3 = dpa_i ? dpa_4_13_0[0] : scalar_1_13_1[0];
  wire merge_13_4 = dpa_i ? dpa_4_13_1[0] : scalar_rows_i[10][13];
  wire merge_13_5 = dpa_i ? dpa_4_13_2[0] : scalar_rows_i[11][13];
  wire merge_14_0 = dpa_i ? dpa_4_13_0[1] : scalar_1_13_0[1];
  wire merge_14_1 = dpa_i ? dpa_4_13_1[1] : scalar_1_13_1[1];
  wire merge_14_2 = dpa_i ? dpa_4_13_2[1] : scalar_1_14_0[0];
  wire merge_14_3 = dpa_i ? dpa_4_14_0[0] : scalar_1_14_1[0];
  wire merge_14_4 = dpa_i ? dpa_4_14_1[0] : scalar_rows_i[10][14];
  wire merge_14_5 = dpa_i ? dpa_4_14_2[0] : scalar_rows_i[11][14];
  wire merge_15_0 = dpa_i ? dpa_4_14_0[1] : scalar_1_14_0[1];
  wire merge_15_1 = dpa_i ? dpa_4_14_1[1] : scalar_1_14_1[1];
  wire merge_15_2 = dpa_i ? dpa_4_14_2[1] : scalar_1_15_0[0];
  wire merge_15_3 = dpa_i ? dpa_4_15_0[0] : scalar_1_15_1[0];
  wire merge_15_4 = dpa_i ? dpa_4_15_1[0] : scalar_rows_i[10][15];
  wire merge_15_5 = dpa_i ? dpa_4_15_2[0] : scalar_rows_i[11][15];
  wire merge_16_0 = dpa_i ? dpa_4_15_0[1] : scalar_1_15_0[1];
  wire merge_16_1 = dpa_i ? dpa_4_15_1[1] : scalar_1_15_1[1];
  wire merge_16_2 = dpa_i ? dpa_4_15_2[1] : scalar_1_16_0[0];
  wire merge_16_3 = dpa_i ? dpa_4_16_0[0] : scalar_1_16_1[0];
  wire merge_16_4 = dpa_i ? dpa_4_16_1[0] : scalar_rows_i[10][16];
  wire merge_16_5 = dpa_i ? dpa_4_16_2[0] : scalar_rows_i[11][16];
  wire merge_17_0 = dpa_i ? dpa_4_16_0[1] : scalar_1_16_0[1];
  wire merge_17_1 = dpa_i ? dpa_4_16_1[1] : scalar_1_16_1[1];
  wire merge_17_2 = dpa_i ? dpa_4_16_2[1] : scalar_1_17_0[0];
  wire merge_17_3 = dpa_i ? dpa_4_17_0[0] : scalar_1_17_1[0];
  wire merge_17_4 = dpa_i ? dpa_4_17_1[0] : scalar_rows_i[10][17];
  wire merge_17_5 = dpa_i ? dpa_4_17_2[0] : scalar_rows_i[11][17];
  wire merge_18_0 = dpa_i ? dpa_4_17_0[1] : scalar_1_17_0[1];
  wire merge_18_1 = dpa_i ? dpa_4_17_1[1] : scalar_1_17_1[1];
  wire merge_18_2 = dpa_i ? dpa_4_17_2[1] : scalar_1_18_0[0];
  wire merge_18_3 = dpa_i ? dpa_4_18_0[0] : scalar_1_18_1[0];
  wire merge_18_4 = dpa_i ? dpa_4_18_1[0] : scalar_rows_i[10][18];
  wire merge_18_5 = dpa_i ? dpa_4_18_2[0] : scalar_rows_i[11][18];
  wire merge_19_0 = dpa_i ? dpa_4_18_0[1] : scalar_1_18_0[1];
  wire merge_19_1 = dpa_i ? dpa_4_18_1[1] : scalar_1_18_1[1];
  wire merge_19_2 = dpa_i ? dpa_4_18_2[1] : scalar_1_19_0[0];
  wire merge_19_3 = dpa_i ? dpa_4_19_0[0] : scalar_1_19_1[0];
  wire merge_19_4 = dpa_i ? dpa_4_19_1[0] : scalar_rows_i[10][19];
  wire merge_19_5 = dpa_i ? dpa_4_19_2[0] : scalar_rows_i[11][19];
  wire merge_20_0 = dpa_i ? dpa_4_19_0[1] : scalar_1_19_0[1];
  wire merge_20_1 = dpa_i ? dpa_4_19_1[1] : scalar_1_19_1[1];
  wire merge_20_2 = dpa_i ? dpa_4_19_2[1] : scalar_1_20_0[0];
  wire merge_20_3 = dpa_i ? dpa_4_20_0[0] : scalar_1_20_1[0];
  wire merge_20_4 = dpa_i ? dpa_4_20_1[0] : scalar_rows_i[10][20];
  wire merge_20_5 = dpa_i ? dpa_4_20_2[0] : scalar_rows_i[11][20];
  wire merge_21_0 = dpa_i ? dpa_4_20_0[1] : scalar_1_20_0[1];
  wire merge_21_1 = dpa_i ? dpa_4_20_1[1] : scalar_1_20_1[1];
  wire merge_21_2 = dpa_i ? dpa_4_20_2[1] : scalar_1_21_0[0];
  wire merge_21_3 = dpa_i ? dpa_4_21_0[0] : scalar_1_21_1[0];
  wire merge_21_4 = dpa_i ? dpa_4_21_1[0] : scalar_rows_i[10][21];
  wire merge_21_5 = dpa_i ? dpa_4_21_2[0] : scalar_rows_i[11][21];
  wire merge_22_0 = dpa_i ? dpa_4_21_0[1] : scalar_1_21_0[1];
  wire merge_22_1 = dpa_i ? dpa_4_21_1[1] : scalar_1_21_1[1];
  wire merge_22_2 = dpa_i ? dpa_4_21_2[1] : scalar_1_22_0[0];
  wire merge_22_3 = dpa_i ? dpa_4_22_0[0] : scalar_1_22_1[0];
  wire merge_22_4 = dpa_i ? dpa_4_22_1[0] : scalar_1_22_2[0];
  wire merge_22_5 = dpa_i ? dpa_4_22_2[0] : scalar_rows_i[11][22];
  wire merge_23_0 = dpa_i ? dpa_4_22_0[1] : scalar_1_22_0[1];
  wire merge_23_1 = dpa_i ? dpa_4_22_1[1] : scalar_1_22_1[1];
  wire merge_23_2 = dpa_i ? dpa_4_22_2[1] : scalar_1_22_2[1];
  wire merge_23_3 = dpa_i ? dpa_4_23_0[0] : scalar_1_23_0[0];
  wire merge_23_4 = dpa_i ? dpa_4_23_1[0] : scalar_1_23_1[0];
  wire merge_23_5 = dpa_i ? dpa_4_23_2[0] : scalar_1_23_2[0];
  wire merge_24_0 = dpa_i ? dpa_4_23_0[1] : scalar_1_23_0[1];
  wire merge_24_1 = dpa_i ? dpa_4_23_1[1] : scalar_1_23_1[1];
  wire merge_24_2 = dpa_i ? dpa_4_23_2[1] : scalar_1_23_2[1];
  wire merge_24_3 = dpa_i ? dpa_4_24_0[0] : scalar_1_24_0[0];
  wire merge_24_4 = dpa_i ? dpa_4_24_1[0] : scalar_1_24_1[0];
  wire merge_24_5 = dpa_i ? dpa_4_24_2[0] : scalar_1_24_2[0];
  wire merge_25_0 = dpa_i ? dpa_4_24_0[1] : scalar_1_24_0[1];
  wire merge_25_1 = dpa_i ? dpa_4_24_1[1] : scalar_1_24_1[1];
  wire merge_25_2 = dpa_i ? dpa_4_24_2[1] : scalar_1_24_2[1];
  wire merge_25_3 = dpa_i ? dpa_4_25_0[0] : scalar_1_25_0[0];
  wire merge_25_4 = dpa_i ? dpa_4_25_1[0] : scalar_1_25_1[0];
  wire merge_25_5 = dpa_i ? dpa_4_25_2[0] : scalar_1_25_2[0];
  wire merge_26_0 = dpa_i ? dpa_4_25_0[1] : scalar_1_25_0[1];
  wire merge_26_1 = dpa_i ? dpa_4_25_1[1] : scalar_1_25_1[1];
  wire merge_26_2 = dpa_i ? dpa_4_25_2[1] : scalar_1_25_2[1];
  wire merge_26_3 = dpa_i ? dpa_4_26_0[0] : scalar_1_26_0[0];
  wire merge_26_4 = dpa_i ? dpa_4_26_1[0] : scalar_1_26_1[0];
  wire merge_26_5 = dpa_i ? dpa_4_26_2[0] : scalar_1_26_2[0];
  wire merge_27_0 = dpa_i ? dpa_4_26_0[1] : scalar_1_26_0[1];
  wire merge_27_1 = dpa_i ? dpa_4_26_1[1] : scalar_1_26_1[1];
  wire merge_27_2 = dpa_i ? dpa_4_26_2[1] : scalar_1_26_2[1];
  wire merge_27_3 = dpa_i ? dpa_4_27_0[0] : scalar_1_27_0[0];
  wire merge_27_4 = dpa_i ? dpa_4_27_1[0] : scalar_1_27_1[0];
  wire merge_27_5 = dpa_i ? dpa_4_27_2[0] : scalar_1_27_2[0];
  wire merge_28_0 = dpa_i ? dpa_4_27_0[1] : scalar_1_27_0[1];
  wire merge_28_1 = dpa_i ? dpa_4_27_1[1] : scalar_1_27_1[1];
  wire merge_28_2 = dpa_i ? dpa_4_27_2[1] : scalar_1_27_2[1];
  wire merge_28_3 = dpa_i ? dpa_4_28_0[0] : scalar_1_28_0[0];
  wire merge_28_4 = dpa_i ? dpa_4_28_1[0] : scalar_1_28_1[0];
  wire merge_28_5 = dpa_i ? dpa_4_28_2[0] : scalar_1_28_2[0];
  wire merge_29_0 = dpa_i ? dpa_4_28_0[1] : scalar_1_28_0[1];
  wire merge_29_1 = dpa_i ? dpa_4_28_1[1] : scalar_1_28_1[1];
  wire merge_29_2 = dpa_i ? dpa_4_28_2[1] : scalar_1_28_2[1];
  wire merge_29_3 = dpa_i ? dpa_3_28_0[1] : scalar_1_29_0[0];
  wire merge_29_4 = dpa_i ? negative_mod[2] : scalar_1_29_1[0];
  wire merge_29_5 = dpa_i ? 1'b0 : scalar_1_29_2[0];
  wire merge_30_0 = dpa_i ? negative_mod[3] : scalar_1_29_0[1];
  wire merge_30_1 = dpa_i ? 1'b0 : scalar_1_29_1[1];
  wire merge_30_2 = dpa_i ? 1'b0 : scalar_1_29_2[1];
  wire merge_30_3 = dpa_i ? 1'b0 : scalar_1_30_0[0];
  wire merge_30_4 = dpa_i ? 1'b0 : scalar_1_30_1[0];
  wire merge_30_5 = dpa_i ? 1'b0 : scalar_1_30_2[0];
  wire merge_31_0 = dpa_i ? negative_mod[4] : scalar_1_30_0[1];
  wire merge_31_1 = dpa_i ? 1'b0 : scalar_1_30_1[1];
  wire merge_31_2 = dpa_i ? 1'b0 : scalar_1_30_2[1];
  wire merge_31_3 = dpa_i ? 1'b0 : scalar_1_31_0[0];
  wire merge_31_4 = dpa_i ? 1'b0 : scalar_1_31_1[0];
  wire merge_31_5 = dpa_i ? 1'b0 : scalar_1_31_2[0];
  wire merge_32_0 = dpa_i ? negative_mod[5] : scalar_1_31_0[1];
  wire merge_32_1 = dpa_i ? 1'b0 : scalar_1_31_1[1];
  wire merge_32_2 = dpa_i ? 1'b0 : scalar_1_31_2[1];
  wire merge_32_3 = dpa_i ? 1'b0 : scalar_1_32_0[0];
  wire merge_32_4 = dpa_i ? 1'b0 : scalar_1_32_1[0];
  wire merge_32_5 = dpa_i ? 1'b0 : scalar_1_32_2[0];
  wire merge_33_0 = dpa_i ? negative_mod[6] : scalar_1_32_0[1];
  wire merge_33_1 = dpa_i ? 1'b0 : scalar_1_32_1[1];
  wire merge_33_2 = dpa_i ? 1'b0 : scalar_1_32_2[1];
  wire merge_33_3 = dpa_i ? 1'b0 : scalar_1_33_0[0];
  wire merge_33_4 = dpa_i ? 1'b0 : scalar_1_33_1[0];
  wire merge_33_5 = dpa_i ? 1'b0 : scalar_1_33_2[0];
  wire [1:0] common_0_0_0;
  assign common_0_0_0 = {1'b0, merge_0_0} + {1'b0, merge_0_1} + {1'b0, merge_0_2};
  wire [1:0] common_0_1_0;
  assign common_0_1_0 = {1'b0, merge_1_0} + {1'b0, merge_1_1} + {1'b0, merge_1_2};
  wire [1:0] common_0_1_1;
  assign common_0_1_1 = {1'b0, merge_1_3} + {1'b0, merge_1_4};
  wire [1:0] common_0_2_0;
  assign common_0_2_0 = {1'b0, merge_2_0} + {1'b0, merge_2_1} + {1'b0, merge_2_2};
  wire [1:0] common_0_2_1;
  assign common_0_2_1 = {1'b0, merge_2_3} + {1'b0, merge_2_4} + {1'b0, merge_2_5};
  wire [1:0] common_0_3_0;
  assign common_0_3_0 = {1'b0, merge_3_0} + {1'b0, merge_3_1} + {1'b0, merge_3_2};
  wire [1:0] common_0_3_1;
  assign common_0_3_1 = {1'b0, merge_3_3} + {1'b0, merge_3_4} + {1'b0, merge_3_5};
  wire [1:0] common_0_4_0;
  assign common_0_4_0 = {1'b0, merge_4_0} + {1'b0, merge_4_1} + {1'b0, merge_4_2};
  wire [1:0] common_0_4_1;
  assign common_0_4_1 = {1'b0, merge_4_3} + {1'b0, merge_4_4} + {1'b0, merge_4_5};
  wire [1:0] common_0_5_0;
  assign common_0_5_0 = {1'b0, merge_5_0} + {1'b0, merge_5_1} + {1'b0, merge_5_2};
  wire [1:0] common_0_5_1;
  assign common_0_5_1 = {1'b0, merge_5_3} + {1'b0, merge_5_4} + {1'b0, merge_5_5};
  wire [1:0] common_0_6_0;
  assign common_0_6_0 = {1'b0, merge_6_0} + {1'b0, merge_6_1} + {1'b0, merge_6_2};
  wire [1:0] common_0_6_1;
  assign common_0_6_1 = {1'b0, merge_6_3} + {1'b0, merge_6_4} + {1'b0, merge_6_5};
  wire [1:0] common_0_7_0;
  assign common_0_7_0 = {1'b0, merge_7_0} + {1'b0, merge_7_1} + {1'b0, merge_7_2};
  wire [1:0] common_0_7_1;
  assign common_0_7_1 = {1'b0, merge_7_3} + {1'b0, merge_7_4} + {1'b0, merge_7_5};
  wire [1:0] common_0_8_0;
  assign common_0_8_0 = {1'b0, merge_8_0} + {1'b0, merge_8_1} + {1'b0, merge_8_2};
  wire [1:0] common_0_8_1;
  assign common_0_8_1 = {1'b0, merge_8_3} + {1'b0, merge_8_4} + {1'b0, merge_8_5};
  wire [1:0] common_0_9_0;
  assign common_0_9_0 = {1'b0, merge_9_0} + {1'b0, merge_9_1} + {1'b0, merge_9_2};
  wire [1:0] common_0_9_1;
  assign common_0_9_1 = {1'b0, merge_9_3} + {1'b0, merge_9_4} + {1'b0, merge_9_5};
  wire [1:0] common_0_10_0;
  assign common_0_10_0 = {1'b0, merge_10_0} + {1'b0, merge_10_1} + {1'b0, merge_10_2};
  wire [1:0] common_0_10_1;
  assign common_0_10_1 = {1'b0, merge_10_3} + {1'b0, merge_10_4} + {1'b0, merge_10_5};
  wire [1:0] common_0_11_0;
  assign common_0_11_0 = {1'b0, merge_11_0} + {1'b0, merge_11_1} + {1'b0, merge_11_2};
  wire [1:0] common_0_11_1;
  assign common_0_11_1 = {1'b0, merge_11_3} + {1'b0, merge_11_4} + {1'b0, merge_11_5};
  wire [1:0] common_0_12_0;
  assign common_0_12_0 = {1'b0, merge_12_0} + {1'b0, merge_12_1} + {1'b0, merge_12_2};
  wire [1:0] common_0_12_1;
  assign common_0_12_1 = {1'b0, merge_12_3} + {1'b0, merge_12_4} + {1'b0, merge_12_5};
  wire [1:0] common_0_13_0;
  assign common_0_13_0 = {1'b0, merge_13_0} + {1'b0, merge_13_1} + {1'b0, merge_13_2};
  wire [1:0] common_0_13_1;
  assign common_0_13_1 = {1'b0, merge_13_3} + {1'b0, merge_13_4} + {1'b0, merge_13_5};
  wire [1:0] common_0_14_0;
  assign common_0_14_0 = {1'b0, merge_14_0} + {1'b0, merge_14_1} + {1'b0, merge_14_2};
  wire [1:0] common_0_14_1;
  assign common_0_14_1 = {1'b0, merge_14_3} + {1'b0, merge_14_4} + {1'b0, merge_14_5};
  wire [1:0] common_0_15_0;
  assign common_0_15_0 = {1'b0, merge_15_0} + {1'b0, merge_15_1} + {1'b0, merge_15_2};
  wire [1:0] common_0_15_1;
  assign common_0_15_1 = {1'b0, merge_15_3} + {1'b0, merge_15_4} + {1'b0, merge_15_5};
  wire [1:0] common_0_16_0;
  assign common_0_16_0 = {1'b0, merge_16_0} + {1'b0, merge_16_1} + {1'b0, merge_16_2};
  wire [1:0] common_0_16_1;
  assign common_0_16_1 = {1'b0, merge_16_3} + {1'b0, merge_16_4} + {1'b0, merge_16_5};
  wire [1:0] common_0_17_0;
  assign common_0_17_0 = {1'b0, merge_17_0} + {1'b0, merge_17_1} + {1'b0, merge_17_2};
  wire [1:0] common_0_17_1;
  assign common_0_17_1 = {1'b0, merge_17_3} + {1'b0, merge_17_4} + {1'b0, merge_17_5};
  wire [1:0] common_0_18_0;
  assign common_0_18_0 = {1'b0, merge_18_0} + {1'b0, merge_18_1} + {1'b0, merge_18_2};
  wire [1:0] common_0_18_1;
  assign common_0_18_1 = {1'b0, merge_18_3} + {1'b0, merge_18_4} + {1'b0, merge_18_5};
  wire [1:0] common_0_19_0;
  assign common_0_19_0 = {1'b0, merge_19_0} + {1'b0, merge_19_1} + {1'b0, merge_19_2};
  wire [1:0] common_0_19_1;
  assign common_0_19_1 = {1'b0, merge_19_3} + {1'b0, merge_19_4} + {1'b0, merge_19_5};
  wire [1:0] common_0_20_0;
  assign common_0_20_0 = {1'b0, merge_20_0} + {1'b0, merge_20_1} + {1'b0, merge_20_2};
  wire [1:0] common_0_20_1;
  assign common_0_20_1 = {1'b0, merge_20_3} + {1'b0, merge_20_4} + {1'b0, merge_20_5};
  wire [1:0] common_0_21_0;
  assign common_0_21_0 = {1'b0, merge_21_0} + {1'b0, merge_21_1} + {1'b0, merge_21_2};
  wire [1:0] common_0_21_1;
  assign common_0_21_1 = {1'b0, merge_21_3} + {1'b0, merge_21_4} + {1'b0, merge_21_5};
  wire [1:0] common_0_22_0;
  assign common_0_22_0 = {1'b0, merge_22_0} + {1'b0, merge_22_1} + {1'b0, merge_22_2};
  wire [1:0] common_0_22_1;
  assign common_0_22_1 = {1'b0, merge_22_3} + {1'b0, merge_22_4} + {1'b0, merge_22_5};
  wire [1:0] common_0_23_0;
  assign common_0_23_0 = {1'b0, merge_23_0} + {1'b0, merge_23_1} + {1'b0, merge_23_2};
  wire [1:0] common_0_23_1;
  assign common_0_23_1 = {1'b0, merge_23_3} + {1'b0, merge_23_4} + {1'b0, merge_23_5};
  wire [1:0] common_0_24_0;
  assign common_0_24_0 = {1'b0, merge_24_0} + {1'b0, merge_24_1} + {1'b0, merge_24_2};
  wire [1:0] common_0_24_1;
  assign common_0_24_1 = {1'b0, merge_24_3} + {1'b0, merge_24_4} + {1'b0, merge_24_5};
  wire [1:0] common_0_25_0;
  assign common_0_25_0 = {1'b0, merge_25_0} + {1'b0, merge_25_1} + {1'b0, merge_25_2};
  wire [1:0] common_0_25_1;
  assign common_0_25_1 = {1'b0, merge_25_3} + {1'b0, merge_25_4} + {1'b0, merge_25_5};
  wire [1:0] common_0_26_0;
  assign common_0_26_0 = {1'b0, merge_26_0} + {1'b0, merge_26_1} + {1'b0, merge_26_2};
  wire [1:0] common_0_26_1;
  assign common_0_26_1 = {1'b0, merge_26_3} + {1'b0, merge_26_4} + {1'b0, merge_26_5};
  wire [1:0] common_0_27_0;
  assign common_0_27_0 = {1'b0, merge_27_0} + {1'b0, merge_27_1} + {1'b0, merge_27_2};
  wire [1:0] common_0_27_1;
  assign common_0_27_1 = {1'b0, merge_27_3} + {1'b0, merge_27_4} + {1'b0, merge_27_5};
  wire [1:0] common_0_28_0;
  assign common_0_28_0 = {1'b0, merge_28_0} + {1'b0, merge_28_1} + {1'b0, merge_28_2};
  wire [1:0] common_0_28_1;
  assign common_0_28_1 = {1'b0, merge_28_3} + {1'b0, merge_28_4} + {1'b0, merge_28_5};
  wire [1:0] common_0_29_0;
  assign common_0_29_0 = {1'b0, merge_29_0} + {1'b0, merge_29_1} + {1'b0, merge_29_2};
  wire [1:0] common_0_29_1;
  assign common_0_29_1 = {1'b0, merge_29_3} + {1'b0, merge_29_4} + {1'b0, merge_29_5};
  wire [1:0] common_0_30_0;
  assign common_0_30_0 = {1'b0, merge_30_0} + {1'b0, merge_30_1} + {1'b0, merge_30_2};
  wire [1:0] common_0_30_1;
  assign common_0_30_1 = {1'b0, merge_30_3} + {1'b0, merge_30_4} + {1'b0, merge_30_5};
  wire [1:0] common_0_31_0;
  assign common_0_31_0 = {1'b0, merge_31_0} + {1'b0, merge_31_1} + {1'b0, merge_31_2};
  wire [1:0] common_0_31_1;
  assign common_0_31_1 = {1'b0, merge_31_3} + {1'b0, merge_31_4} + {1'b0, merge_31_5};
  wire [1:0] common_0_32_0;
  assign common_0_32_0 = {1'b0, merge_32_0} + {1'b0, merge_32_1} + {1'b0, merge_32_2};
  wire [1:0] common_0_32_1;
  assign common_0_32_1 = {1'b0, merge_32_3} + {1'b0, merge_32_4} + {1'b0, merge_32_5};
  wire [1:0] common_0_33_0;
  assign common_0_33_0 = {1'b0, merge_33_0} + {1'b0, merge_33_1} + {1'b0, merge_33_2};
  wire [1:0] common_0_33_1;
  assign common_0_33_1 = {1'b0, merge_33_3} + {1'b0, merge_33_4} + {1'b0, merge_33_5};
  wire [1:0] common_0_34_0;
  assign common_0_34_0 = {1'b0, scalar_1_33_0[1]} + {1'b0, scalar_1_33_1[1]} + {1'b0, scalar_1_33_2[1]};
  wire [1:0] common_0_34_1;
  assign common_0_34_1 = {1'b0, scalar_1_34_0[0]} + {1'b0, scalar_1_34_1[0]} + {1'b0, scalar_1_34_2[0]};
  wire [1:0] common_0_35_0;
  assign common_0_35_0 = {1'b0, scalar_1_34_0[1]} + {1'b0, scalar_1_34_1[1]} + {1'b0, scalar_1_34_2[1]};
  wire [1:0] common_0_35_1;
  assign common_0_35_1 = {1'b0, scalar_1_35_0[0]} + {1'b0, scalar_1_35_1[0]} + {1'b0, scalar_1_35_2[0]};
  wire [1:0] common_0_36_0;
  assign common_0_36_0 = {1'b0, scalar_1_35_0[1]} + {1'b0, scalar_1_35_1[1]} + {1'b0, scalar_1_35_2[1]};
  wire [1:0] common_0_36_1;
  assign common_0_36_1 = {1'b0, scalar_1_36_0[0]} + {1'b0, scalar_1_36_1[0]} + {1'b0, scalar_1_36_2[0]};
  wire [1:0] common_0_37_0;
  assign common_0_37_0 = {1'b0, scalar_1_36_0[1]} + {1'b0, scalar_1_36_1[1]} + {1'b0, scalar_1_36_2[1]};
  wire [1:0] common_0_37_1;
  assign common_0_37_1 = {1'b0, scalar_1_37_0[0]} + {1'b0, scalar_1_37_1[0]} + {1'b0, scalar_1_37_2[0]};
  wire [1:0] common_0_38_0;
  assign common_0_38_0 = {1'b0, scalar_1_37_0[1]} + {1'b0, scalar_1_37_1[1]} + {1'b0, scalar_1_37_2[1]};
  wire [1:0] common_0_38_1;
  assign common_0_38_1 = {1'b0, scalar_1_38_0[0]} + {1'b0, scalar_1_38_1[0]} + {1'b0, scalar_1_38_2[0]};
  wire [1:0] common_0_39_0;
  assign common_0_39_0 = {1'b0, scalar_1_38_0[1]} + {1'b0, scalar_1_38_1[1]} + {1'b0, scalar_1_38_2[1]};
  wire [1:0] common_0_39_1;
  assign common_0_39_1 = {1'b0, scalar_1_39_0[0]} + {1'b0, scalar_1_39_1[0]} + {1'b0, scalar_1_39_2[0]};
  wire [1:0] common_0_40_0;
  assign common_0_40_0 = {1'b0, scalar_1_39_0[1]} + {1'b0, scalar_1_39_1[1]} + {1'b0, scalar_1_39_2[1]};
  wire [1:0] common_0_40_1;
  assign common_0_40_1 = {1'b0, scalar_1_40_0[0]} + {1'b0, scalar_1_40_1[0]} + {1'b0, scalar_1_40_2[0]};
  wire [1:0] common_0_41_0;
  assign common_0_41_0 = {1'b0, scalar_1_40_0[1]} + {1'b0, scalar_1_40_1[1]} + {1'b0, scalar_1_40_2[1]};
  wire [1:0] common_0_41_1;
  assign common_0_41_1 = {1'b0, scalar_1_41_0[0]} + {1'b0, scalar_1_41_1[0]} + {1'b0, scalar_1_41_2[0]};
  wire [1:0] common_0_42_0;
  assign common_0_42_0 = {1'b0, scalar_1_41_0[1]} + {1'b0, scalar_1_41_1[1]} + {1'b0, scalar_1_41_2[1]};
  wire [1:0] common_0_42_1;
  assign common_0_42_1 = {1'b0, scalar_1_42_0[0]} + {1'b0, scalar_1_42_1[0]} + {1'b0, scalar_1_42_2[0]};
  wire [1:0] common_0_43_0;
  assign common_0_43_0 = {1'b0, scalar_1_42_0[1]} + {1'b0, scalar_1_42_1[1]} + {1'b0, scalar_1_42_2[1]};
  wire [1:0] common_0_43_1;
  assign common_0_43_1 = {1'b0, scalar_1_43_0[0]} + {1'b0, scalar_1_43_1[0]} + {1'b0, scalar_1_43_2[0]};
  wire [1:0] common_0_44_0;
  assign common_0_44_0 = {1'b0, scalar_1_43_0[1]} + {1'b0, scalar_1_43_1[1]} + {1'b0, scalar_1_43_2[1]};
  wire [1:0] common_0_44_1;
  assign common_0_44_1 = {1'b0, scalar_1_44_0[0]} + {1'b0, scalar_rows_i[10][44]} + {1'b0, scalar_rows_i[11][44]};
  wire [1:0] common_0_45_0;
  assign common_0_45_0 = {1'b0, scalar_1_44_0[1]} + {1'b0, scalar_rows_i[5][45]} + {1'b0, scalar_rows_i[7][45]};
  wire [1:0] common_0_45_1;
  assign common_0_45_1 = {1'b0, scalar_rows_i[8][45]} + {1'b0, scalar_rows_i[10][45]} + {1'b0, scalar_rows_i[11][45]};
  wire [1:0] common_0_46_0;
  assign common_0_46_0 = {1'b0, scalar_rows_i[5][46]} + {1'b0, scalar_rows_i[7][46]} + {1'b0, scalar_rows_i[8][46]};
  wire [1:0] common_0_46_1;
  assign common_0_46_1 = {1'b0, scalar_rows_i[10][46]} + {1'b0, scalar_rows_i[11][46]};
  wire [1:0] common_0_47_0;
  assign common_0_47_0 = {1'b0, scalar_rows_i[5][47]} + {1'b0, scalar_rows_i[7][47]} + {1'b0, scalar_rows_i[8][47]};
  wire [1:0] common_0_47_1;
  assign common_0_47_1 = {1'b0, scalar_rows_i[10][47]} + {1'b0, scalar_rows_i[11][47]};
  wire [1:0] common_0_48_0;
  assign common_0_48_0 = {1'b0, scalar_rows_i[5][48]} + {1'b0, scalar_rows_i[7][48]} + {1'b0, scalar_rows_i[8][48]};
  wire [1:0] common_0_48_1;
  assign common_0_48_1 = {1'b0, scalar_rows_i[10][48]} + {1'b0, scalar_rows_i[11][48]};
  wire [1:0] common_0_49_0;
  assign common_0_49_0 = {1'b0, scalar_rows_i[5][49]} + {1'b0, scalar_rows_i[7][49]} + {1'b0, scalar_rows_i[8][49]};
  wire [1:0] common_0_49_1;
  assign common_0_49_1 = {1'b0, scalar_rows_i[10][49]} + {1'b0, scalar_rows_i[11][49]};
  wire [1:0] common_0_50_0;
  assign common_0_50_0 = {1'b0, scalar_rows_i[5][50]} + {1'b0, scalar_rows_i[7][50]} + {1'b0, scalar_rows_i[8][50]};
  wire [1:0] common_0_50_1;
  assign common_0_50_1 = {1'b0, scalar_rows_i[10][50]} + {1'b0, scalar_rows_i[11][50]};
  wire [1:0] common_0_51_0;
  assign common_0_51_0 = {1'b0, scalar_rows_i[5][51]} + {1'b0, scalar_rows_i[7][51]} + {1'b0, scalar_rows_i[8][51]};
  wire [1:0] common_0_51_1;
  assign common_0_51_1 = {1'b0, scalar_rows_i[10][51]} + {1'b0, scalar_rows_i[11][51]};
  wire [1:0] common_0_52_0;
  assign common_0_52_0 = {1'b0, scalar_rows_i[5][52]} + {1'b0, scalar_rows_i[7][52]} + {1'b0, scalar_rows_i[8][52]};
  wire [1:0] common_0_52_1;
  assign common_0_52_1 = {1'b0, scalar_rows_i[10][52]} + {1'b0, scalar_rows_i[11][52]};
  wire [1:0] common_0_53_0;
  assign common_0_53_0 = {1'b0, scalar_rows_i[5][53]} + {1'b0, scalar_rows_i[7][53]} + {1'b0, scalar_rows_i[8][53]};
  wire [1:0] common_0_53_1;
  assign common_0_53_1 = {1'b0, scalar_rows_i[10][53]} + {1'b0, scalar_rows_i[11][53]};
  wire [1:0] common_0_54_0;
  assign common_0_54_0 = {1'b0, scalar_rows_i[5][54]} + {1'b0, scalar_rows_i[7][54]} + {1'b0, scalar_rows_i[8][54]};
  wire [1:0] common_0_54_1;
  assign common_0_54_1 = {1'b0, scalar_rows_i[10][54]} + {1'b0, scalar_rows_i[11][54]};
  wire [1:0] common_0_55_0;
  assign common_0_55_0 = {1'b0, scalar_rows_i[8][55]} + {1'b0, scalar_rows_i[10][55]};
  wire [1:0] common_1_0_0;
  assign common_1_0_0 = {1'b0, common_0_0_0[0]} + {1'b0, merge_0_3};
  wire [1:0] common_1_1_0;
  assign common_1_1_0 = {1'b0, common_0_0_0[1]} + {1'b0, common_0_1_0[0]} + {1'b0, common_0_1_1[0]};
  wire [1:0] common_1_2_0;
  assign common_1_2_0 = {1'b0, common_0_1_0[1]} + {1'b0, common_0_1_1[1]} + {1'b0, common_0_2_0[0]};
  wire [1:0] common_1_3_0;
  assign common_1_3_0 = {1'b0, common_0_2_0[1]} + {1'b0, common_0_2_1[1]} + {1'b0, common_0_3_0[0]};
  wire [1:0] common_1_4_0;
  assign common_1_4_0 = {1'b0, common_0_3_0[1]} + {1'b0, common_0_3_1[1]} + {1'b0, common_0_4_0[0]};
  wire [1:0] common_1_5_0;
  assign common_1_5_0 = {1'b0, common_0_4_0[1]} + {1'b0, common_0_4_1[1]} + {1'b0, common_0_5_0[0]};
  wire [1:0] common_1_6_0;
  assign common_1_6_0 = {1'b0, common_0_5_0[1]} + {1'b0, common_0_5_1[1]} + {1'b0, common_0_6_0[0]};
  wire [1:0] common_1_7_0;
  assign common_1_7_0 = {1'b0, common_0_6_0[1]} + {1'b0, common_0_6_1[1]} + {1'b0, common_0_7_0[0]};
  wire [1:0] common_1_8_0;
  assign common_1_8_0 = {1'b0, common_0_7_0[1]} + {1'b0, common_0_7_1[1]} + {1'b0, common_0_8_0[0]};
  wire [1:0] common_1_9_0;
  assign common_1_9_0 = {1'b0, common_0_8_0[1]} + {1'b0, common_0_8_1[1]} + {1'b0, common_0_9_0[0]};
  wire [1:0] common_1_10_0;
  assign common_1_10_0 = {1'b0, common_0_9_0[1]} + {1'b0, common_0_9_1[1]} + {1'b0, common_0_10_0[0]};
  wire [1:0] common_1_11_0;
  assign common_1_11_0 = {1'b0, common_0_10_0[1]} + {1'b0, common_0_10_1[1]} + {1'b0, common_0_11_0[0]};
  wire [1:0] common_1_12_0;
  assign common_1_12_0 = {1'b0, common_0_11_0[1]} + {1'b0, common_0_11_1[1]} + {1'b0, common_0_12_0[0]};
  wire [1:0] common_1_13_0;
  assign common_1_13_0 = {1'b0, common_0_12_0[1]} + {1'b0, common_0_12_1[1]} + {1'b0, common_0_13_0[0]};
  wire [1:0] common_1_14_0;
  assign common_1_14_0 = {1'b0, common_0_13_0[1]} + {1'b0, common_0_13_1[1]} + {1'b0, common_0_14_0[0]};
  wire [1:0] common_1_15_0;
  assign common_1_15_0 = {1'b0, common_0_14_0[1]} + {1'b0, common_0_14_1[1]} + {1'b0, common_0_15_0[0]};
  wire [1:0] common_1_16_0;
  assign common_1_16_0 = {1'b0, common_0_15_0[1]} + {1'b0, common_0_15_1[1]} + {1'b0, common_0_16_0[0]};
  wire [1:0] common_1_17_0;
  assign common_1_17_0 = {1'b0, common_0_16_0[1]} + {1'b0, common_0_16_1[1]} + {1'b0, common_0_17_0[0]};
  wire [1:0] common_1_18_0;
  assign common_1_18_0 = {1'b0, common_0_17_0[1]} + {1'b0, common_0_17_1[1]} + {1'b0, common_0_18_0[0]};
  wire [1:0] common_1_19_0;
  assign common_1_19_0 = {1'b0, common_0_18_0[1]} + {1'b0, common_0_18_1[1]} + {1'b0, common_0_19_0[0]};
  wire [1:0] common_1_20_0;
  assign common_1_20_0 = {1'b0, common_0_19_0[1]} + {1'b0, common_0_19_1[1]} + {1'b0, common_0_20_0[0]};
  wire [1:0] common_1_21_0;
  assign common_1_21_0 = {1'b0, common_0_20_0[1]} + {1'b0, common_0_20_1[1]} + {1'b0, common_0_21_0[0]};
  wire [1:0] common_1_22_0;
  assign common_1_22_0 = {1'b0, common_0_21_0[1]} + {1'b0, common_0_21_1[1]} + {1'b0, common_0_22_0[0]};
  wire [1:0] common_1_23_0;
  assign common_1_23_0 = {1'b0, common_0_22_0[1]} + {1'b0, common_0_22_1[1]} + {1'b0, common_0_23_0[0]};
  wire [1:0] common_1_24_0;
  assign common_1_24_0 = {1'b0, common_0_23_0[1]} + {1'b0, common_0_23_1[1]} + {1'b0, common_0_24_0[0]};
  wire [1:0] common_1_25_0;
  assign common_1_25_0 = {1'b0, common_0_24_0[1]} + {1'b0, common_0_24_1[1]} + {1'b0, common_0_25_0[0]};
  wire [1:0] common_1_26_0;
  assign common_1_26_0 = {1'b0, common_0_25_0[1]} + {1'b0, common_0_25_1[1]} + {1'b0, common_0_26_0[0]};
  wire [1:0] common_1_27_0;
  assign common_1_27_0 = {1'b0, common_0_26_0[1]} + {1'b0, common_0_26_1[1]} + {1'b0, common_0_27_0[0]};
  wire [1:0] common_1_28_0;
  assign common_1_28_0 = {1'b0, common_0_27_0[1]} + {1'b0, common_0_27_1[1]} + {1'b0, common_0_28_0[0]};
  wire [1:0] common_1_29_0;
  assign common_1_29_0 = {1'b0, common_0_28_0[1]} + {1'b0, common_0_28_1[1]} + {1'b0, common_0_29_0[0]};
  wire [1:0] common_1_30_0;
  assign common_1_30_0 = {1'b0, common_0_29_0[1]} + {1'b0, common_0_29_1[1]} + {1'b0, common_0_30_0[0]};
  wire [1:0] common_1_31_0;
  assign common_1_31_0 = {1'b0, common_0_30_0[1]} + {1'b0, common_0_30_1[1]} + {1'b0, common_0_31_0[0]};
  wire [1:0] common_1_32_0;
  assign common_1_32_0 = {1'b0, common_0_31_0[1]} + {1'b0, common_0_31_1[1]} + {1'b0, common_0_32_0[0]};
  wire [1:0] common_1_33_0;
  assign common_1_33_0 = {1'b0, common_0_32_0[1]} + {1'b0, common_0_32_1[1]} + {1'b0, common_0_33_0[0]};
  wire [1:0] common_1_34_0;
  assign common_1_34_0 = {1'b0, common_0_33_0[1]} + {1'b0, common_0_33_1[1]} + {1'b0, common_0_34_0[0]};
  wire [1:0] common_1_35_0;
  assign common_1_35_0 = {1'b0, common_0_34_0[1]} + {1'b0, common_0_34_1[1]} + {1'b0, common_0_35_0[0]};
  wire [1:0] common_1_36_0;
  assign common_1_36_0 = {1'b0, common_0_35_0[1]} + {1'b0, common_0_35_1[1]} + {1'b0, common_0_36_0[0]};
  wire [1:0] common_1_37_0;
  assign common_1_37_0 = {1'b0, common_0_36_0[1]} + {1'b0, common_0_36_1[1]} + {1'b0, common_0_37_0[0]};
  wire [1:0] common_1_38_0;
  assign common_1_38_0 = {1'b0, common_0_37_0[1]} + {1'b0, common_0_37_1[1]} + {1'b0, common_0_38_0[0]};
  wire [1:0] common_1_39_0;
  assign common_1_39_0 = {1'b0, common_0_38_0[1]} + {1'b0, common_0_38_1[1]} + {1'b0, common_0_39_0[0]};
  wire [1:0] common_1_40_0;
  assign common_1_40_0 = {1'b0, common_0_39_0[1]} + {1'b0, common_0_39_1[1]} + {1'b0, common_0_40_0[0]};
  wire [1:0] common_1_41_0;
  assign common_1_41_0 = {1'b0, common_0_40_0[1]} + {1'b0, common_0_40_1[1]} + {1'b0, common_0_41_0[0]};
  wire [1:0] common_1_42_0;
  assign common_1_42_0 = {1'b0, common_0_41_0[1]} + {1'b0, common_0_41_1[1]} + {1'b0, common_0_42_0[0]};
  wire [1:0] common_1_43_0;
  assign common_1_43_0 = {1'b0, common_0_42_0[1]} + {1'b0, common_0_42_1[1]} + {1'b0, common_0_43_0[0]};
  wire [1:0] common_1_44_0;
  assign common_1_44_0 = {1'b0, common_0_43_0[1]} + {1'b0, common_0_43_1[1]} + {1'b0, common_0_44_0[0]};
  wire [1:0] common_1_45_0;
  assign common_1_45_0 = {1'b0, common_0_44_0[1]} + {1'b0, common_0_44_1[1]} + {1'b0, common_0_45_0[0]};
  wire [1:0] common_1_46_0;
  assign common_1_46_0 = {1'b0, common_0_45_0[1]} + {1'b0, common_0_45_1[1]} + {1'b0, common_0_46_0[0]};
  wire [1:0] common_1_47_0;
  assign common_1_47_0 = {1'b0, common_0_46_0[1]} + {1'b0, common_0_46_1[1]} + {1'b0, common_0_47_0[0]};
  wire [1:0] common_1_48_0;
  assign common_1_48_0 = {1'b0, common_0_47_0[1]} + {1'b0, common_0_47_1[1]} + {1'b0, common_0_48_0[0]};
  wire [1:0] common_1_49_0;
  assign common_1_49_0 = {1'b0, common_0_48_0[1]} + {1'b0, common_0_48_1[1]} + {1'b0, common_0_49_0[0]};
  wire [1:0] common_1_50_0;
  assign common_1_50_0 = {1'b0, common_0_49_0[1]} + {1'b0, common_0_49_1[1]} + {1'b0, common_0_50_0[0]};
  wire [1:0] common_1_51_0;
  assign common_1_51_0 = {1'b0, common_0_50_0[1]} + {1'b0, common_0_50_1[1]} + {1'b0, common_0_51_0[0]};
  wire [1:0] common_1_52_0;
  assign common_1_52_0 = {1'b0, common_0_51_0[1]} + {1'b0, common_0_51_1[1]} + {1'b0, common_0_52_0[0]};
  wire [1:0] common_1_53_0;
  assign common_1_53_0 = {1'b0, common_0_52_0[1]} + {1'b0, common_0_52_1[1]} + {1'b0, common_0_53_0[0]};
  wire [1:0] common_1_54_0;
  assign common_1_54_0 = {1'b0, common_0_53_0[1]} + {1'b0, common_0_53_1[1]} + {1'b0, common_0_54_0[0]};
  wire [1:0] common_1_55_0;
  assign common_1_55_0 = {1'b0, common_0_54_0[1]} + {1'b0, common_0_54_1[1]} + {1'b0, common_0_55_0[0]};
  wire [1:0] common_1_56_0;
  assign common_1_56_0 = {1'b0, common_0_55_0[1]} + {1'b0, scalar_rows_i[8][56]} + {1'b0, scalar_rows_i[10][56]};
  wire [1:0] common_1_57_0;
  assign common_1_57_0 = {1'b0, scalar_rows_i[8][57]} + {1'b0, scalar_rows_i[10][57]};
  wire [1:0] common_1_58_0;
  assign common_1_58_0 = {1'b0, scalar_rows_i[8][58]} + {1'b0, scalar_rows_i[10][58]};
  wire [1:0] common_1_59_0;
  assign common_1_59_0 = {1'b0, scalar_rows_i[8][59]} + {1'b0, scalar_rows_i[10][59]};
  wire [1:0] common_1_60_0;
  assign common_1_60_0 = {1'b0, scalar_rows_i[8][60]} + {1'b0, scalar_rows_i[10][60]};
  wire [1:0] common_1_61_0;
  assign common_1_61_0 = {1'b0, scalar_rows_i[8][61]} + {1'b0, scalar_rows_i[10][61]};
  wire [1:0] common_1_62_0;
  assign common_1_62_0 = {1'b0, scalar_rows_i[8][62]} + {1'b0, scalar_rows_i[10][62]};
  wire [1:0] common_1_63_0;
  assign common_1_63_0 = {1'b0, scalar_rows_i[8][63]} + {1'b0, scalar_rows_i[10][63]};
  wire [1:0] common_2_0_0;
  assign common_2_0_0 = {1'b0, common_1_0_0[0]} + {1'b0, merge_0_4};
  wire [1:0] common_2_1_0;
  assign common_2_1_0 = {1'b0, common_1_0_0[1]} + {1'b0, common_1_1_0[0]} + {1'b0, merge_1_5};
  wire [1:0] common_2_2_0;
  assign common_2_2_0 = {1'b0, common_1_1_0[1]} + {1'b0, common_1_2_0[0]} + {1'b0, common_0_2_1[0]};
  wire [1:0] common_2_3_0;
  assign common_2_3_0 = {1'b0, common_1_2_0[1]} + {1'b0, common_1_3_0[0]} + {1'b0, common_0_3_1[0]};
  wire [1:0] common_2_4_0;
  assign common_2_4_0 = {1'b0, common_1_3_0[1]} + {1'b0, common_1_4_0[0]} + {1'b0, common_0_4_1[0]};
  wire [1:0] common_2_5_0;
  assign common_2_5_0 = {1'b0, common_1_4_0[1]} + {1'b0, common_1_5_0[0]} + {1'b0, common_0_5_1[0]};
  wire [1:0] common_2_6_0;
  assign common_2_6_0 = {1'b0, common_1_5_0[1]} + {1'b0, common_1_6_0[0]} + {1'b0, common_0_6_1[0]};
  wire [1:0] common_2_7_0;
  assign common_2_7_0 = {1'b0, common_1_6_0[1]} + {1'b0, common_1_7_0[0]} + {1'b0, common_0_7_1[0]};
  wire [1:0] common_2_8_0;
  assign common_2_8_0 = {1'b0, common_1_7_0[1]} + {1'b0, common_1_8_0[0]} + {1'b0, common_0_8_1[0]};
  wire [1:0] common_2_9_0;
  assign common_2_9_0 = {1'b0, common_1_8_0[1]} + {1'b0, common_1_9_0[0]} + {1'b0, common_0_9_1[0]};
  wire [1:0] common_2_10_0;
  assign common_2_10_0 = {1'b0, common_1_9_0[1]} + {1'b0, common_1_10_0[0]} + {1'b0, common_0_10_1[0]};
  wire [1:0] common_2_11_0;
  assign common_2_11_0 = {1'b0, common_1_10_0[1]} + {1'b0, common_1_11_0[0]} + {1'b0, common_0_11_1[0]};
  wire [1:0] common_2_12_0;
  assign common_2_12_0 = {1'b0, common_1_11_0[1]} + {1'b0, common_1_12_0[0]} + {1'b0, common_0_12_1[0]};
  wire [1:0] common_2_13_0;
  assign common_2_13_0 = {1'b0, common_1_12_0[1]} + {1'b0, common_1_13_0[0]} + {1'b0, common_0_13_1[0]};
  wire [1:0] common_2_14_0;
  assign common_2_14_0 = {1'b0, common_1_13_0[1]} + {1'b0, common_1_14_0[0]} + {1'b0, common_0_14_1[0]};
  wire [1:0] common_2_15_0;
  assign common_2_15_0 = {1'b0, common_1_14_0[1]} + {1'b0, common_1_15_0[0]} + {1'b0, common_0_15_1[0]};
  wire [1:0] common_2_16_0;
  assign common_2_16_0 = {1'b0, common_1_15_0[1]} + {1'b0, common_1_16_0[0]} + {1'b0, common_0_16_1[0]};
  wire [1:0] common_2_17_0;
  assign common_2_17_0 = {1'b0, common_1_16_0[1]} + {1'b0, common_1_17_0[0]} + {1'b0, common_0_17_1[0]};
  wire [1:0] common_2_18_0;
  assign common_2_18_0 = {1'b0, common_1_17_0[1]} + {1'b0, common_1_18_0[0]} + {1'b0, common_0_18_1[0]};
  wire [1:0] common_2_19_0;
  assign common_2_19_0 = {1'b0, common_1_18_0[1]} + {1'b0, common_1_19_0[0]} + {1'b0, common_0_19_1[0]};
  wire [1:0] common_2_20_0;
  assign common_2_20_0 = {1'b0, common_1_19_0[1]} + {1'b0, common_1_20_0[0]} + {1'b0, common_0_20_1[0]};
  wire [1:0] common_2_21_0;
  assign common_2_21_0 = {1'b0, common_1_20_0[1]} + {1'b0, common_1_21_0[0]} + {1'b0, common_0_21_1[0]};
  wire [1:0] common_2_22_0;
  assign common_2_22_0 = {1'b0, common_1_21_0[1]} + {1'b0, common_1_22_0[0]} + {1'b0, common_0_22_1[0]};
  wire [1:0] common_2_23_0;
  assign common_2_23_0 = {1'b0, common_1_22_0[1]} + {1'b0, common_1_23_0[0]} + {1'b0, common_0_23_1[0]};
  wire [1:0] common_2_24_0;
  assign common_2_24_0 = {1'b0, common_1_23_0[1]} + {1'b0, common_1_24_0[0]} + {1'b0, common_0_24_1[0]};
  wire [1:0] common_2_25_0;
  assign common_2_25_0 = {1'b0, common_1_24_0[1]} + {1'b0, common_1_25_0[0]} + {1'b0, common_0_25_1[0]};
  wire [1:0] common_2_26_0;
  assign common_2_26_0 = {1'b0, common_1_25_0[1]} + {1'b0, common_1_26_0[0]} + {1'b0, common_0_26_1[0]};
  wire [1:0] common_2_27_0;
  assign common_2_27_0 = {1'b0, common_1_26_0[1]} + {1'b0, common_1_27_0[0]} + {1'b0, common_0_27_1[0]};
  wire [1:0] common_2_28_0;
  assign common_2_28_0 = {1'b0, common_1_27_0[1]} + {1'b0, common_1_28_0[0]} + {1'b0, common_0_28_1[0]};
  wire [1:0] common_2_29_0;
  assign common_2_29_0 = {1'b0, common_1_28_0[1]} + {1'b0, common_1_29_0[0]} + {1'b0, common_0_29_1[0]};
  wire [1:0] common_2_30_0;
  assign common_2_30_0 = {1'b0, common_1_29_0[1]} + {1'b0, common_1_30_0[0]} + {1'b0, common_0_30_1[0]};
  wire [1:0] common_2_31_0;
  assign common_2_31_0 = {1'b0, common_1_30_0[1]} + {1'b0, common_1_31_0[0]} + {1'b0, common_0_31_1[0]};
  wire [1:0] common_2_32_0;
  assign common_2_32_0 = {1'b0, common_1_31_0[1]} + {1'b0, common_1_32_0[0]} + {1'b0, common_0_32_1[0]};
  wire [1:0] common_2_33_0;
  assign common_2_33_0 = {1'b0, common_1_32_0[1]} + {1'b0, common_1_33_0[0]} + {1'b0, common_0_33_1[0]};
  wire [1:0] common_2_34_0;
  assign common_2_34_0 = {1'b0, common_1_33_0[1]} + {1'b0, common_1_34_0[0]} + {1'b0, common_0_34_1[0]};
  wire [1:0] common_2_35_0;
  assign common_2_35_0 = {1'b0, common_1_34_0[1]} + {1'b0, common_1_35_0[0]} + {1'b0, common_0_35_1[0]};
  wire [1:0] common_2_36_0;
  assign common_2_36_0 = {1'b0, common_1_35_0[1]} + {1'b0, common_1_36_0[0]} + {1'b0, common_0_36_1[0]};
  wire [1:0] common_2_37_0;
  assign common_2_37_0 = {1'b0, common_1_36_0[1]} + {1'b0, common_1_37_0[0]} + {1'b0, common_0_37_1[0]};
  wire [1:0] common_2_38_0;
  assign common_2_38_0 = {1'b0, common_1_37_0[1]} + {1'b0, common_1_38_0[0]} + {1'b0, common_0_38_1[0]};
  wire [1:0] common_2_39_0;
  assign common_2_39_0 = {1'b0, common_1_38_0[1]} + {1'b0, common_1_39_0[0]} + {1'b0, common_0_39_1[0]};
  wire [1:0] common_2_40_0;
  assign common_2_40_0 = {1'b0, common_1_39_0[1]} + {1'b0, common_1_40_0[0]} + {1'b0, common_0_40_1[0]};
  wire [1:0] common_2_41_0;
  assign common_2_41_0 = {1'b0, common_1_40_0[1]} + {1'b0, common_1_41_0[0]} + {1'b0, common_0_41_1[0]};
  wire [1:0] common_2_42_0;
  assign common_2_42_0 = {1'b0, common_1_41_0[1]} + {1'b0, common_1_42_0[0]} + {1'b0, common_0_42_1[0]};
  wire [1:0] common_2_43_0;
  assign common_2_43_0 = {1'b0, common_1_42_0[1]} + {1'b0, common_1_43_0[0]} + {1'b0, common_0_43_1[0]};
  wire [1:0] common_2_44_0;
  assign common_2_44_0 = {1'b0, common_1_43_0[1]} + {1'b0, common_1_44_0[0]} + {1'b0, common_0_44_1[0]};
  wire [1:0] common_2_45_0;
  assign common_2_45_0 = {1'b0, common_1_44_0[1]} + {1'b0, common_1_45_0[0]} + {1'b0, common_0_45_1[0]};
  wire [1:0] common_2_46_0;
  assign common_2_46_0 = {1'b0, common_1_45_0[1]} + {1'b0, common_1_46_0[0]} + {1'b0, common_0_46_1[0]};
  wire [1:0] common_2_47_0;
  assign common_2_47_0 = {1'b0, common_1_46_0[1]} + {1'b0, common_1_47_0[0]} + {1'b0, common_0_47_1[0]};
  wire [1:0] common_2_48_0;
  assign common_2_48_0 = {1'b0, common_1_47_0[1]} + {1'b0, common_1_48_0[0]} + {1'b0, common_0_48_1[0]};
  wire [1:0] common_2_49_0;
  assign common_2_49_0 = {1'b0, common_1_48_0[1]} + {1'b0, common_1_49_0[0]} + {1'b0, common_0_49_1[0]};
  wire [1:0] common_2_50_0;
  assign common_2_50_0 = {1'b0, common_1_49_0[1]} + {1'b0, common_1_50_0[0]} + {1'b0, common_0_50_1[0]};
  wire [1:0] common_2_51_0;
  assign common_2_51_0 = {1'b0, common_1_50_0[1]} + {1'b0, common_1_51_0[0]} + {1'b0, common_0_51_1[0]};
  wire [1:0] common_2_52_0;
  assign common_2_52_0 = {1'b0, common_1_51_0[1]} + {1'b0, common_1_52_0[0]} + {1'b0, common_0_52_1[0]};
  wire [1:0] common_2_53_0;
  assign common_2_53_0 = {1'b0, common_1_52_0[1]} + {1'b0, common_1_53_0[0]} + {1'b0, common_0_53_1[0]};
  wire [1:0] common_2_54_0;
  assign common_2_54_0 = {1'b0, common_1_53_0[1]} + {1'b0, common_1_54_0[0]} + {1'b0, common_0_54_1[0]};
  wire [1:0] common_2_55_0;
  assign common_2_55_0 = {1'b0, common_1_54_0[1]} + {1'b0, common_1_55_0[0]} + {1'b0, scalar_rows_i[11][55]};
  wire [1:0] common_2_56_0;
  assign common_2_56_0 = {1'b0, common_1_55_0[1]} + {1'b0, common_1_56_0[0]} + {1'b0, scalar_rows_i[11][56]};
  wire [1:0] common_2_57_0;
  assign common_2_57_0 = {1'b0, common_1_56_0[1]} + {1'b0, common_1_57_0[0]} + {1'b0, scalar_rows_i[11][57]};
  wire [1:0] common_2_58_0;
  assign common_2_58_0 = {1'b0, common_1_57_0[1]} + {1'b0, common_1_58_0[0]} + {1'b0, scalar_rows_i[11][58]};
  wire [1:0] common_2_59_0;
  assign common_2_59_0 = {1'b0, common_1_58_0[1]} + {1'b0, common_1_59_0[0]} + {1'b0, scalar_rows_i[11][59]};
  wire [1:0] common_2_60_0;
  assign common_2_60_0 = {1'b0, common_1_59_0[1]} + {1'b0, common_1_60_0[0]} + {1'b0, scalar_rows_i[11][60]};
  wire [1:0] common_2_61_0;
  assign common_2_61_0 = {1'b0, common_1_60_0[1]} + {1'b0, common_1_61_0[0]} + {1'b0, scalar_rows_i[11][61]};
  wire [1:0] common_2_62_0;
  assign common_2_62_0 = {1'b0, common_1_61_0[1]} + {1'b0, common_1_62_0[0]} + {1'b0, scalar_rows_i[11][62]};
  wire [1:0] common_2_63_0;
  assign common_2_63_0 = {1'b0, common_1_62_0[1]} + {1'b0, common_1_63_0[0]} + {1'b0, scalar_rows_i[11][63]};
  assign sum_o[0] = common_2_0_0[0];
  assign carry_o[0] = merge_0_5;
  assign sum_o[1] = common_2_0_0[1];
  assign carry_o[1] = common_2_1_0[0];
  assign sum_o[2] = common_2_1_0[1];
  assign carry_o[2] = common_2_2_0[0];
  assign sum_o[3] = common_2_2_0[1];
  assign carry_o[3] = common_2_3_0[0];
  assign sum_o[4] = common_2_3_0[1];
  assign carry_o[4] = common_2_4_0[0];
  assign sum_o[5] = common_2_4_0[1];
  assign carry_o[5] = common_2_5_0[0];
  assign sum_o[6] = common_2_5_0[1];
  assign carry_o[6] = common_2_6_0[0];
  assign sum_o[7] = common_2_6_0[1];
  assign carry_o[7] = common_2_7_0[0];
  assign sum_o[8] = common_2_7_0[1];
  assign carry_o[8] = common_2_8_0[0];
  assign sum_o[9] = common_2_8_0[1];
  assign carry_o[9] = common_2_9_0[0];
  assign sum_o[10] = common_2_9_0[1];
  assign carry_o[10] = common_2_10_0[0];
  assign sum_o[11] = common_2_10_0[1];
  assign carry_o[11] = common_2_11_0[0];
  assign sum_o[12] = common_2_11_0[1];
  assign carry_o[12] = common_2_12_0[0];
  assign sum_o[13] = common_2_12_0[1];
  assign carry_o[13] = common_2_13_0[0];
  assign sum_o[14] = common_2_13_0[1];
  assign carry_o[14] = common_2_14_0[0];
  assign sum_o[15] = common_2_14_0[1];
  assign carry_o[15] = common_2_15_0[0];
  assign sum_o[16] = common_2_15_0[1];
  assign carry_o[16] = common_2_16_0[0];
  assign sum_o[17] = common_2_16_0[1];
  assign carry_o[17] = common_2_17_0[0];
  assign sum_o[18] = common_2_17_0[1];
  assign carry_o[18] = common_2_18_0[0];
  assign sum_o[19] = common_2_18_0[1];
  assign carry_o[19] = common_2_19_0[0];
  assign sum_o[20] = common_2_19_0[1];
  assign carry_o[20] = common_2_20_0[0];
  assign sum_o[21] = common_2_20_0[1];
  assign carry_o[21] = common_2_21_0[0];
  assign sum_o[22] = common_2_21_0[1];
  assign carry_o[22] = common_2_22_0[0];
  assign sum_o[23] = common_2_22_0[1];
  assign carry_o[23] = common_2_23_0[0];
  assign sum_o[24] = common_2_23_0[1];
  assign carry_o[24] = common_2_24_0[0];
  assign sum_o[25] = common_2_24_0[1];
  assign carry_o[25] = common_2_25_0[0];
  assign sum_o[26] = common_2_25_0[1];
  assign carry_o[26] = common_2_26_0[0];
  assign sum_o[27] = common_2_26_0[1];
  assign carry_o[27] = common_2_27_0[0];
  assign sum_o[28] = common_2_27_0[1];
  assign carry_o[28] = common_2_28_0[0];
  assign sum_o[29] = common_2_28_0[1];
  assign carry_o[29] = common_2_29_0[0];
  assign sum_o[30] = common_2_29_0[1];
  assign carry_o[30] = common_2_30_0[0];
  assign sum_o[31] = common_2_30_0[1];
  assign carry_o[31] = common_2_31_0[0];
  assign sum_o[32] = common_2_31_0[1];
  assign carry_o[32] = common_2_32_0[0];
  assign sum_o[33] = common_2_32_0[1];
  assign carry_o[33] = common_2_33_0[0];
  assign sum_o[34] = common_2_33_0[1];
  assign carry_o[34] = common_2_34_0[0];
  assign sum_o[35] = common_2_34_0[1];
  assign carry_o[35] = common_2_35_0[0];
  assign sum_o[36] = common_2_35_0[1];
  assign carry_o[36] = common_2_36_0[0];
  assign sum_o[37] = common_2_36_0[1];
  assign carry_o[37] = common_2_37_0[0];
  assign sum_o[38] = common_2_37_0[1];
  assign carry_o[38] = common_2_38_0[0];
  assign sum_o[39] = common_2_38_0[1];
  assign carry_o[39] = common_2_39_0[0];
  assign sum_o[40] = common_2_39_0[1];
  assign carry_o[40] = common_2_40_0[0];
  assign sum_o[41] = common_2_40_0[1];
  assign carry_o[41] = common_2_41_0[0];
  assign sum_o[42] = common_2_41_0[1];
  assign carry_o[42] = common_2_42_0[0];
  assign sum_o[43] = common_2_42_0[1];
  assign carry_o[43] = common_2_43_0[0];
  assign sum_o[44] = common_2_43_0[1];
  assign carry_o[44] = common_2_44_0[0];
  assign sum_o[45] = common_2_44_0[1];
  assign carry_o[45] = common_2_45_0[0];
  assign sum_o[46] = common_2_45_0[1];
  assign carry_o[46] = common_2_46_0[0];
  assign sum_o[47] = common_2_46_0[1];
  assign carry_o[47] = common_2_47_0[0];
  assign sum_o[48] = common_2_47_0[1];
  assign carry_o[48] = common_2_48_0[0];
  assign sum_o[49] = common_2_48_0[1];
  assign carry_o[49] = common_2_49_0[0];
  assign sum_o[50] = common_2_49_0[1];
  assign carry_o[50] = common_2_50_0[0];
  assign sum_o[51] = common_2_50_0[1];
  assign carry_o[51] = common_2_51_0[0];
  assign sum_o[52] = common_2_51_0[1];
  assign carry_o[52] = common_2_52_0[0];
  assign sum_o[53] = common_2_52_0[1];
  assign carry_o[53] = common_2_53_0[0];
  assign sum_o[54] = common_2_53_0[1];
  assign carry_o[54] = common_2_54_0[0];
  assign sum_o[55] = common_2_54_0[1];
  assign carry_o[55] = common_2_55_0[0];
  assign sum_o[56] = common_2_55_0[1];
  assign carry_o[56] = common_2_56_0[0];
  assign sum_o[57] = common_2_56_0[1];
  assign carry_o[57] = common_2_57_0[0];
  assign sum_o[58] = common_2_57_0[1];
  assign carry_o[58] = common_2_58_0[0];
  assign sum_o[59] = common_2_58_0[1];
  assign carry_o[59] = common_2_59_0[0];
  assign sum_o[60] = common_2_59_0[1];
  assign carry_o[60] = common_2_60_0[0];
  assign sum_o[61] = common_2_60_0[1];
  assign carry_o[61] = common_2_61_0[0];
  assign sum_o[62] = common_2_61_0[1];
  assign carry_o[62] = common_2_62_0[0];
  assign sum_o[63] = common_2_62_0[1];
  assign carry_o[63] = common_2_63_0[0];
endmodule
