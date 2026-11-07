`include "VX_define.vh"

module VX_ucc_bf16x9_comb import VX_tcu_pkg::*; (
    input  wire                 dpa,
    input  wire [4:0]           fmt,
    input  wire [63:0]          mask,
    input  wire [7:0][31:0]     a_vec,
    input  wire [7:0][31:0]     b_vec,
    input  wire [3:0][7:0]      scale_a,
    input  wire [3:0][7:0]      scale_b,
    input  wire [31:0]          a,
    input  wire [31:0]          b,
    input  wire [31:0]          c,
    input  wire [1:0]           op,
    output wire [4:0]           flags,
    output wire [31:0]          result
);
    `STATIC_ASSERT(TCU_MAX_INPUTS == 64, ("DPA16 requires 64 packed FP4 inputs"))

    wire [16:0][TCU_EXP_BITS-1:0] exponents;
    wire [16:0] exp_sel;
    wire [16:0][24:0] raw_sigs, tensor_sigs, scalar_sigs;
    wire [16:0][9:0] scalar_exponents;
    wire [15:0][10:0] tensor_ma, tensor_mb;
    wire [8:0][10:0] scalar_ma, scalar_mb;
    wire [15:0][21:0] products;
    wire scalar_zero_sign, scalar_special;
    wire [31:0] scalar_special_result;
    wire [4:0] scalar_flags;
    wire [15:0] tensor_mask;
    VX_ucc_bf16x9_prepare scalar_prepare (
        .a              (a),
        .b              (b),
        .c              (c),
        .op             (op),
        .mul_a          (scalar_ma),
        .mul_b          (scalar_mb),
        .products       (products[8:0]),
        .exponents      (scalar_exponents),
        .significands   (scalar_sigs),
        .zero_sign      (scalar_zero_sign),
        .special        (scalar_special),
        .special_result (scalar_special_result),
        .flags          (scalar_flags)
    );
    for (genvar i = 0; i < 16; ++i) begin : g_mul
        wire [10:0] ma, mb;
        if (i < 9) begin : g_scalar
            assign ma = dpa ? tensor_ma[i] : scalar_ma[i];
            assign mb = dpa ? tensor_mb[i] : scalar_mb[i];
        end else begin : g_tensor
            assign ma = tensor_ma[i];
            assign mb = tensor_mb[i];
        end
        VX_tcu_tfr_wmul #(
            .N (11)
        ) multiplier (
            .clk    (1'b0),
            .enable (1'b1),
            .a      (ma),
            .b      (mb),
            .p      (products[i])
        );
    end
    assign raw_sigs = dpa ? tensor_sigs : scalar_sigs;
    fedp_excep_t exceptions;
    wire [15:0] lane_mask = dpa ? tensor_mask : 16'h01ff;
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
        .PROD_REG (0),
        .EXTERNAL_MUL (1),
        .EXTERNAL_EXP (1)
    ) mul (
        .clk        (1'b0),
        .enable     (1'b1),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .vld_mask   (mask),
        .fmt_s      (fmt),
        .a_row      (a_vec),
        .b_col      (b_vec),
        .c_val      (c),
        .mantissa_a (tensor_ma),
        .mantissa_b (tensor_mb),
        .external_products (products),
        .external_exp_enable (!dpa),
        .external_exponents (scalar_exponents),
        `UNUSED_PIN (f8_mantissa_a),
        `UNUSED_PIN (f8_mantissa_b),
        .external_f8_products ('0),
        .sf_a       (scale_a),
        .sf_b       (scale_b),
        .exponents  (exponents),
        .exp_sel    (exp_sel),
        .raw_sigs   (tensor_sigs),
        .exceptions (exceptions),
        .lane_mask  (tensor_mask)
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

    wire [31:0] rounded_result;
    fedp_excep_t selected_exceptions;
    assign selected_exceptions = dpa ? exceptions : '0;
    VX_tcu_tfr_norm_round #(
        .WA     (32),
        .C_HI_W (7)
    ) norm (
        .clk        (1'b0),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .max_exp    (dpa ? max_exp : max_exp - 10'd32),
        .acc_sig    (magnitude),
        .acc_sign   (sign),
        .cval_hi    (7'd0),
        .is_int     (1'b0),
        .sticky_in  (sum_sticky),
        .exceptions (selected_exceptions),
        .result     (rounded_result)
    );
    assign result = !dpa && scalar_special ? scalar_special_result
                  : !dpa && !(|magnitude) ? {scalar_zero_sign, 31'd0} : rounded_result;
    assign flags = dpa ? 5'd0 : scalar_flags;
endmodule
