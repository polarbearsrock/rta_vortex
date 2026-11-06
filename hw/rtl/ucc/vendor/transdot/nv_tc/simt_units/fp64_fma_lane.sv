// One SIMT FP64 FMA lane (IEEE FP64 FMA, RNE) as the iso-area reference for the vector lanes: FPnew fpnew_fma,
// 3 pipeline registers (distributed), no handshake.
module fp64_fma_lane #(
  parameter bit PIPE = 1'b1          // 0: no pipeline registers
) (
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
    .FpFormat    (fpnew_pkg::FP64),
    .NumPipeRegs (PIPE ? 3 : 0),
    .PipeConfig  (fpnew_pkg::DISTRIBUTED)
  ) u_fma (
    .clk_i, .rst_ni,
    .operands_i      ({c_i, b_i, a_i}),
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
