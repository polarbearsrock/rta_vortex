`include "VX_define.vh"

module VX_ucc_dpa16_comb import VX_tcu_pkg::*; (
    input  wire [4:0]           fmt,
    input  wire [63:0]          mask,
    input  wire [7:0][31:0]     a,
    input  wire [7:0][31:0]     b,
    input  wire [3:0][7:0]      scale_a,
    input  wire [3:0][7:0]      scale_b,
    input  wire [31:0]          c,
    output wire [31:0]          result
);
    `STATIC_ASSERT(TCU_MAX_INPUTS == 64, ("DPA16 requires 64 packed FP4 inputs"))

    wire [16:0][TCU_EXP_BITS-1:0] exponents;
    wire [16:0] exp_sel;
    wire [16:0][24:0] raw_sigs;
    fedp_excep_t exceptions;
    wire [15:0] lane_mask;
    wire [TCU_EXP_BITS-1:0] max_exp;
    wire [16:0][31:0] aligned;
    wire [16:0] sticky, negs;
    wire [31:0] magnitude;
    wire sign, sum_sticky;

    VX_tcu_tfr_shared_mul #(
        .N        (8),
        .W        (25),
        .WA       (32),
        .SF       (4),
        .USE_DSP  (0),
        .PROD_REG (0)
    ) mul (
        .clk        (1'b0),
        .enable     (1'b1),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .vld_mask   (mask),
        .fmt_s      (fmt),
        .a_row      (a),
        .b_col      (b),
        .c_val      (c),
        `UNUSED_PIN (mantissa_a),
        `UNUSED_PIN (mantissa_b),
        .external_products ('0),
        .external_exp_enable (1'b0),
        .external_exponents ('0),
        `UNUSED_PIN (f8_mantissa_a),
        `UNUSED_PIN (f8_mantissa_b),
        .external_f8_products ('0),
        .sf_a       (scale_a),
        .sf_b       (scale_b),
        .exponents  (exponents),
        .exp_sel    (exp_sel),
        .raw_sigs   (raw_sigs),
        .exceptions (exceptions),
        .lane_mask  (lane_mask)
    );

    VX_tcu_tfr_align #(
        .N  (17),
        .WI (25),
        .WO (32)
    ) align (
        .clk         (1'b0),
        .valid_in    (1'b0),
        .req_id      (32'd0),
        .exponents   (exponents),
        .sel_exp     (exp_sel),
        .lane_mask   (lane_mask),
        .sigs_in     (raw_sigs),
        .is_int      (1'b0),
        .external_shift (1'b0),
        .external_data (52'd0),
        .external_amount (8'd0),
        `UNUSED_PIN (external_result),
        `UNUSED_PIN (external_sticky),
        .max_exp     (max_exp),
        .sigs_out    (aligned),
        .sticky_bits (sticky),
        .fp_negs     (negs)
    );

    VX_tcu_tfr_acc #(
        .N  (17),
        .WO (32)
    ) acc (
        .post_enable (1'b0),
        .post_operands ('0),
        .post_negatives ('0),
        .reduced_sigs (),
        .clk        (1'b0),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .sigs_in    (aligned),
        .sticky_in  (sticky),
        .fp_negs    (negs),
        `UNUSED_PIN (sum_out),
        .sig_out    (magnitude),
        .sign_out   (sign),
        .sticky_out (sum_sticky)
    );

    VX_tcu_tfr_norm_round #(
        .WA     (32),
        .C_HI_W (7)
    ) norm (
        .clk        (1'b0),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .max_exp    (max_exp),
        .acc_sig    (magnitude),
        .acc_sign   (sign),
        .cval_hi    (7'd0),
        .is_int     (1'b0),
        .sticky_in  (sum_sticky),
        .exceptions (exceptions),
        .result     (result)
    );
endmodule
