// s2chitni & Claude (AI-generated)
//
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
module ucc_lane (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  input  logic [ucc_pkg::DPA_VECTOR-1:0] a_i,
  input  logic [ucc_pkg::DPA_VECTOR-1:0] b_i,
  input  logic [ucc_pkg::DPA_SCALES-1:0] sa_i,
  input  logic [ucc_pkg::DPA_SCALES-1:0] sb_i,
  input  logic [63:0]                    c_i,
  input  logic        valid_i,
  input  logic [6:0]  op_i,
  input  logic [2:0]  rm_i,
  output logic [63:0] d_o
);
  fpnew_pkg::status_t st;
  logic ext, tag, mask, aux, ovalid, iready, busy;
  ucc_fma #(
    .FpFormat    (fpnew_pkg::FP64),
    .NumPipeRegs (3),
    .PipeConfig  (fpnew_pkg::DISTRIBUTED)
  ) u_fma (
    .clk_i, .rst_ni,
    .operands_i      ({c_i, b_i[63:0], a_i[63:0]}),
    .dpa_hi_i        ({sb_i, b_i[ucc_pkg::DPA_VECTOR-1:64], sa_i, a_i[ucc_pkg::DPA_VECTOR-1:64]}),
    .is_boxed_i      (3'b111),
    .rnd_mode_i      (fpnew_pkg::roundmode_e'(rm_i)),
    .ucc_op_i        (op_i),
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
