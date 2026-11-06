// s2chitni & Claude (AI-generated)
//
// The reference for ucc_lane's FP32 FMA: one unmodified FPnew fpnew_fma in FP32, with fp64_fma_lane's pipeline and
// settings (three distributed registers, FMADD, round to nearest even, no handshake), on bits 31-0 of a, b and c,
// its result NaN-boxed as ucc_lane returns it.
module fpnew_fp32_lane (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [63:0] a_i,
  input  logic [63:0] b_i,
  input  logic [63:0] c_i,
  output logic [63:0] d_o
);
  fpnew_pkg::status_t st;
  logic ext, tag, mask, aux, ovalid, iready, busy;

  fpnew_fma #(
    .FpFormat    (fpnew_pkg::FP32),
    .NumPipeRegs (3),
    .PipeConfig  (fpnew_pkg::DISTRIBUTED)
  ) u_fma (
    .clk_i, .rst_ni,
    .operands_i      ({c_i[31:0], b_i[31:0], a_i[31:0]}),
    .is_boxed_i      (3'b111),
    .rnd_mode_i      (fpnew_pkg::RNE),
    .op_i            (fpnew_pkg::FMADD),
    .op_mod_i        (1'b0),
    .tag_i           (1'b0),
    .mask_i          (1'b1),
    .aux_i           (1'b0),
    .in_valid_i      (1'b1),
    .in_ready_o      (iready),
    .flush_i         (1'b0),
    .result_o        (d_o[31:0]),
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

  assign d_o[63:32] = '1;
endmodule
