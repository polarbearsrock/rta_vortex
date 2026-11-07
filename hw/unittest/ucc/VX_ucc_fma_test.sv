module VX_ucc_fma_test #(
    parameter W = 80,
    parameter CHUNK = 11,
    parameter ANCHORED = 0
) (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [1:0]  op,
    input  wire [1:0]  rm,
    output wire [31:0] result,
    output wire [4:0]  flags
);
    wire [8:0][10:0] mul_a, mul_b;
    wire [8:0][21:0] products;
    wire [9:0][W-1:0] operands;
    wire [9:0] negatives;
    wire signed [11:0] base_exp;
    wire zero_sign, special;
    wire [31:0] special_result;
    wire [4:0] special_flags;
    wire [W-1:0] raw_sum;
    VX_ucc_fma_prepare #(
        .W     (W),
        .ANCHORED (ANCHORED),
        .CHUNK (CHUNK)
    ) prepare (
        .resolved_product ('0),
        .align_mul_a (), .align_mul_b (), .align_products ('0),
        .raw_sum (raw_sum[31:0]),
        .reduced_products ('0),
        .post_operands (),
        .post_negatives (),
        .a              (a),
        .b              (b),
        .c              (c),
        .op             (op),
        .rm             (rm),
        .mul_a          (mul_a),
        .mul_b          (mul_b),
        .products       (products),
        .external_align (1'b0),
        .align_data     ({W{1'b0}}),
        .align_distance (12'sd0),
        .align_result   (),
        .align_sticky   (),
        .operands       (operands),
        .negatives      (negatives),
        .base_exp       (base_exp),
        .zero_sign      (zero_sign),
        .special        (special),
        .special_result (special_result),
        .special_flags  (special_flags)
    );
    for (genvar i = 0; i < 9; ++i) begin : g_mul
        VX_wallace_mul #(
            .N (11),
            .P (22)
        ) mul (
            .a (mul_a[i]),
            .b (mul_b[i]),
            .p (products[i])
        );
    end
    wire [W-1:0] mag;
    wire sign, sticky;
    VX_tcu_tfr_acc #(
        .N  (10),
        .WO (W)
    ) acc (
        .post_enable (1'b0),
        .post_operands ('0),
        .post_negatives ('0),
        .reduced_sigs (),
        .clk        (1'b0),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .sigs_in    (operands),
        .sticky_in  (10'd0),
        .fp_negs    (negatives),
        .sum_out    (raw_sum),
        .sig_out    (mag),
        .sign_out   (sign),
        .sticky_out (sticky)
    );
    wire [31:0] finite_result;
    wire [4:0] finite_flags;
    VX_ucc_round #(
        .W (W)
    ) rounder (
        .magnitude (mag),
        .base_exp  (base_exp),
        .sign      ((|mag) ? sign : zero_sign),
        .rm        (rm),
        .sticky_in (sticky),
        .dpa       (1'b0),
        .shift_mode (1'b0),
        .shift_left (1'b0),
        .shift_signed (1'b0),
        .shift_count (5'd0),
        .shift_result (),
        .clz_result (),
        .result    (finite_result),
        .flags     (finite_flags)
    );
    assign result = special ? special_result : finite_result;
    assign flags = special ? special_flags : finite_flags;
endmodule
