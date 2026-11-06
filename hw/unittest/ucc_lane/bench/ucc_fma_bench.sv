// s2chitni & Claude (AI-generated)
//
// ucc_fma as ucc_lane builds it, with the ports ucc_lane leaves unconnected brought out for the regression: the
// handshake (in_ready_o, out_valid_o, busy_o), flush_i, the status flags, and 16-bit tag and aux and the mask, which
// must come back with the operation whose result d_o returns. lost_o and hidden_o are ucc_fma's issue_lost and
// result_hidden, the breaches UCC_CHECK_ISSUE reports.
module ucc_fma_bench (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  input  logic [ucc_pkg::DPA_VECTOR-1:0] a_i,
  input  logic [ucc_pkg::DPA_VECTOR-1:0] b_i,
  input  logic [ucc_pkg::DPA_SCALES-1:0] sa_i,
  input  logic [ucc_pkg::DPA_SCALES-1:0] sb_i,
  input  logic [63:0]                    c_i,
  input  logic                           valid_i,
  input  logic [6:0]                     op_i,
  input  logic [2:0]                     rm_i,
  input  logic                           flush_i,
  input  logic [15:0]                    tag_i,
  input  logic [15:0]                    aux_i,
  input  logic                           mask_i,
  output logic [63:0]                    d_o,
  output logic [4:0]                     status_o,
  output logic [15:0]                    tag_o,
  output logic [15:0]                    aux_o,
  output logic                           mask_o,
  output logic                           valid_o,
  output logic                           ready_o,
  output logic                           busy_o,
  output logic                           lost_o,
  output logic                           hidden_o
);
  fpnew_pkg::status_t status;
  logic               ext;

  ucc_fma #(
    .TagType ( logic [15:0] ),
    .AuxType ( logic [15:0] )
  ) u_fma (
    .clk_i, .rst_ni,
    .operands_i      ({c_i, b_i[63:0], a_i[63:0]}),
    .dpa_hi_i        ({sb_i, b_i[ucc_pkg::DPA_VECTOR-1:64], sa_i, a_i[ucc_pkg::DPA_VECTOR-1:64]}),
    .is_boxed_i      (3'b111),
    .rnd_mode_i      (fpnew_pkg::roundmode_e'(rm_i)),
    .ucc_op_i        (op_i),
    .tag_i,
    .mask_i,
    .aux_i,
    .in_valid_i      (valid_i),
    .in_ready_o      (ready_o),
    .flush_i,
    .result_o        (d_o),
    .status_o        (status),
    .extension_bit_o (ext),
    .tag_o,
    .mask_o,
    .aux_o,
    .out_valid_o     (valid_o),
    .out_ready_i     (1'b1),
    .busy_o,
    .reg_ena_i       ('0)
  );

  assign status_o = status;
  assign lost_o   = u_fma.issue_lost;
  assign hidden_o = u_fma.result_hidden;
endmodule
