// s2chitni & Claude (AI-generated)
//
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
