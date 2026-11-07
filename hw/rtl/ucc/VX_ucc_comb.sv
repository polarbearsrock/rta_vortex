`include "VX_define.vh"

module VX_ucc_comb import VX_tcu_pkg::*; #(
    parameter W = 80,
    parameter CHUNK = 11,
    parameter ENABLE_INT = 0,
    parameter ENABLE_AUX = 0,
    parameter ENABLE_BOOL = 0,
    parameter ENABLE_EX2 = 0,
    parameter NATIVE_FP = 0,
    parameter SHARED_ALIGN = 0,
    parameter SMALL_NATIVE = 0,
    parameter ENABLE_EXP = 0,
    parameter FMA_CSA = 0,
    parameter DIRECT_NORM = 0,
    parameter ONEHOT_ROUTE = 0,
    parameter EXP_CONST = 0,
    parameter COMPACT_EXP = 0,
    parameter FMA_ANCHORED = 0,
    parameter FMA_CROP = 0,
    parameter FMA_SEGMENTED = 0,
    parameter WINDOW_NORM = 0,
    parameter MUL_C_ALIGN = 0
) (
    input  wire                dpa,
    input  wire [4:0]          fmt,
    input  wire [63:0]         mask,
    input  wire [7:0][31:0]    a_vec,
    input  wire [7:0][31:0]    b_vec,
    input  wire [3:0][7:0]     scale_a,
    input  wire [3:0][7:0]     scale_b,
    input  wire [31:0]         a,
    input  wire [31:0]         b,
    input  wire [31:0]         c,
    input  wire [7:0]          op,
    input  wire [1:0]          rm,
    input  wire [7:0]          immediate,
    output wire [31:0]         result,
    output wire [4:0]          flags,
    output wire                predicate
);
    `STATIC_ASSERT (W >= 32, ("shared accumulator must cover DPA16"))
    `STATIC_ASSERT (!SMALL_NATIVE || (NATIVE_FP && W == 64), ("small native datapath requires W64 and native FP"))
    `STATIC_ASSERT (!ENABLE_EXP || ENABLE_EX2, ("natural EXP requires the shared EX2 polynomial"))
    `STATIC_ASSERT (!FMA_CSA || (!NATIVE_FP && W >= 64), ("carry-save FMA requires exact mode and at least 64 bits"))
    `STATIC_ASSERT (!FMA_ANCHORED || (!NATIVE_FP && !FMA_CSA && W >= 80), ("anchored FMA requires an 80-bit exact accumulator"))
    `STATIC_ASSERT (!FMA_SEGMENTED || (!NATIVE_FP && !FMA_CSA && !FMA_ANCHORED && W == 64 && CHUNK == 11), ("segmented FMA requires W64 and 11-bit slices"))
    `STATIC_ASSERT (!MUL_C_ALIGN || FMA_SEGMENTED, ("multiplier alignment requires segmented exact mode"))
    wire [W-1:0] raw_sum;
    wire [1:0][W-1:0] reduced_products;
    wire [2:0][W-1:0] post_operands;
    wire [2:0] post_negatives;
    localparam NORM_W = SMALL_NATIVE ? 32 : W;
    wire [15:0][10:0] tensor_ma, tensor_mb;
    wire [15:0][21:0] products;
    wire [15:0][10:0] bank_ma, bank_mb;
    wire [2:0][10:0] align_ma, align_mb;
    wire [31:0][3:0] tensor_f8_ma, tensor_f8_mb, range_small_a, range_small_b;
    wire [31:0][7:0] f8_products;
    wire [2:0][10:0] range_wide_a, range_wide_b;
    wire [5:0][10:0] compact_range_a, compact_range_b;
    wire [54:0] range_product;
    wire [8:0][10:0] scalar_ma, scalar_mb;
    wire [9:0][W-1:0] scalar_operands;
    wire [9:0] scalar_negs;
    wire signed [11:0] scalar_base;
    wire zero_sign, scalar_special;
    wire [31:0] scalar_special_result;
    wire [4:0] scalar_special_flags;
    wire [16:0][TCU_EXP_BITS-1:0] exponents;
    wire [16:0] exp_sel;
    wire [16:0][24:0] raw_sigs, native_sigs;
    wire [16:0][9:0] native_exponents;
    wire native_mode = NATIVE_FP && !dpa && op <= 8'h03;
    wire tensor_format_mode = dpa || native_mode;
    fedp_excep_t exceptions;
    wire [15:0] lane_mask;
    wire [TCU_EXP_BITS-1:0] max_exp;
    wire [16:0][31:0] aligned;
    wire [16:0] tensor_sticky, tensor_negs;

    VX_tcu_tfr_shared_mul #(
        .N            (8),
        .W            (25),
        .WA           (32),
        .SF           (4),
        .USE_DSP      (0),
        .PROD_REG     (0),
        .EXTERNAL_MUL (1),
        .EXTERNAL_EXP (NATIVE_FP),
        .EXTERNAL_F8 (ENABLE_EXP && !EXP_CONST && !COMPACT_EXP)
    ) tensor_prepare (
        .clk               (1'b0),
        .enable            (1'b1),
        .valid_in          (1'b0),
        .req_id            (32'd0),
        .vld_mask          (mask),
        .fmt_s             (fmt),
        .a_row             (a_vec),
        .b_col             (b_vec),
        .c_val             (c),
        .sf_a              (scale_a),
        .sf_b              (scale_b),
        .mantissa_a        (tensor_ma),
        .mantissa_b        (tensor_mb),
        .external_products (products),
        .external_exp_enable (native_mode),
        .external_exponents (native_exponents),
        .f8_mantissa_a (tensor_f8_ma),
        .f8_mantissa_b (tensor_f8_mb),
        .external_f8_products (f8_products),
        .exponents         (exponents),
        .exp_sel           (exp_sel),
        .raw_sigs          (raw_sigs),
        .exceptions        (exceptions),
        .lane_mask         (lane_mask)
    );
    wire shift_mode = ENABLE_AUX && op[7:4] == 3 && !dpa;
    wire int_to_float = ENABLE_AUX && (op == 8'h40 || op == 8'h41) && !dpa;
    wire float_to_int = ENABLE_AUX && (op == 8'h42 || op == 8'h43) && !dpa;
    wire fp_compare = ENABLE_AUX && op >= 8'h08 && op <= 8'h0f && !dpa;
    wire fp_sign_op = ENABLE_AUX && (op == 8'h04 || op == 8'h05) && !dpa;
    wire integer_arithmetic = ENABLE_INT && (op[7:4] == 1 || op[7:4] == 2) && !dpa;
    wire exp_mode = ENABLE_EXP && op == 8'h61 && !dpa;
    wire ex2_mode = (ENABLE_EX2 && op == 8'h60 && !dpa) || exp_mode;
    wire [15:0][10:0] ex2_ma, ex2_mb;
    wire [16:0][W-1:0] ex2_operands;
    wire [W-1:0] ex2_align_data;
    wire signed [11:0] ex2_align_distance, ex2_base;
    wire ex2_special;
    wire [31:0] ex2_special_result;
    wire boolean_mode = ENABLE_BOOL && op[7:4] == 5 && !dpa;
    wire [31:0] boolean_result;
    if (ENABLE_BOOL) begin : g_boolean
        VX_ucc_boolean boolean_unit (
            .a         (a),
            .b         (b),
            .c         (c),
            .immediate (immediate),
            .op        (op[2:0]),
            .result    (boolean_result)
        );
    end else begin : g_no_boolean
        assign boolean_result = '0;
    end
    wire [W-1:0] conversion_data, conversion_aligned;
    wire signed [11:0] conversion_distance;
    wire conversion_sticky;
    wire [51:0] shared_alignment_result;
    wire shared_alignment_sticky;
    wire signed [11:0] shared_alignment_distance = (ex2_mode ? ex2_align_distance : conversion_distance) + (exp_mode ? -12'sd3 : 12'sd14);
    wire [7:0] shared_alignment_amount = shared_alignment_distance < 0 ? 8'd0 : 8'(shared_alignment_distance);
    wire [51:0] shared_alignment_data = exp_mode ? range_product[54:3] : {14'd0, (|a[30:23]), a[22:0], 14'd0};
    wire [1:0][W-1:0] conversion_operands;
    wire [1:0] conversion_negs;
    wire [31:0] conversion_result, comparison_result;
    wire [4:0] conversion_flags, comparison_flags;
    wire comparison_predicate;
    if (NATIVE_FP) begin : g_native_fp
        assign align_ma = '0;
        assign align_mb = '0;
        assign post_operands = '0;
        assign post_negatives = '0;
        VX_ucc_bf16x9_prepare prepare (
            .a              (a),
            .b              (b),
            .c              (c),
            .op             (op[1:0]),
            .mul_a          (scalar_ma),
            .mul_b          (scalar_mb),
            .products       (products[8:0]),
            .exponents      (native_exponents),
            .significands   (native_sigs),
            .zero_sign      (zero_sign),
            .special        (scalar_special),
            .special_result (scalar_special_result),
            .flags          (scalar_special_flags)
        );
        assign scalar_operands = '0;
        assign scalar_negs = '0;
        assign scalar_base = 12'(max_exp) - 12'sd318;
        if (SHARED_ALIGN) begin : g_paired_alignment
            assign conversion_aligned = W'(shared_alignment_result);
            assign conversion_sticky = shared_alignment_sticky;
        end else if (ENABLE_AUX || ENABLE_EX2) begin : g_external_alignment
            wire signed [11:0] distance = ex2_mode ? ex2_align_distance : conversion_distance;
            wire left = distance < 0;
            wire [11:0] amount = left ? 12'(-distance) : 12'(distance);
            VX_ucc_shift_jam #(
                .W  (W),
                .SW (12)
            ) shifter (
                .data_in  (ex2_mode ? ex2_align_data : conversion_data),
                .amount   (amount),
                .left     (left),
                .fill     (1'b0),
                .data_out (conversion_aligned),
                .sticky   (conversion_sticky)
            );
        end else begin : g_no_external_alignment
            assign conversion_aligned = '0;
            assign conversion_sticky = 1'b0;
        end
    end else begin : g_exact_fp
        assign native_exponents = '0;
        assign native_sigs = '0;
        VX_ucc_fma_prepare #(
            .RESOLVED (FMA_SEGMENTED),
            .MUL_C_ALIGN (MUL_C_ALIGN),
            .REDUCE_FIRST (FMA_CSA),
            .ANCHORED (FMA_ANCHORED),
            .CROP_PRODUCTS (FMA_CROP),
            .W     (W),
            .CHUNK (CHUNK)
        ) scalar_prepare (
            .resolved_product ({products[11][3:0], products[10], products[9]}),
            .align_mul_a (align_ma), .align_mul_b (align_mb), .align_products (products[14:12]),
            .raw_sum (raw_sum[31:0]),
            .reduced_products (reduced_products),
            .post_operands (post_operands),
            .post_negatives (post_negatives),
            .a              (a),
            .b              (b),
            .c              (c),
            .op             (op[1:0]),
            .rm             (rm),
            .mul_a          (scalar_ma),
            .mul_b          (scalar_mb),
            .products       (products[8:0]),
            .external_align (float_to_int || ex2_mode),
            .align_data     (ex2_mode ? ex2_align_data : conversion_data),
            .align_distance (ex2_mode ? ex2_align_distance : conversion_distance),
            .align_result   (conversion_aligned),
            .align_sticky   (conversion_sticky),
            .operands       (scalar_operands),
            .negatives      (scalar_negs),
            .base_exp       (scalar_base),
            .zero_sign      (zero_sign),
            .special        (scalar_special),
            .special_result (scalar_special_result),
            .special_flags  (scalar_special_flags)
        );
    end
    wire integer_mode = integer_arithmetic || shift_mode || int_to_float || fp_compare;
    wire [8:0][10:0] integer_ma, integer_mb;
    wire [16:0][W-1:0] integer_operands;
    wire [16:0] integer_negs;
    wire [31:0] integer_result;
    wire integer_predicate;
    if (ENABLE_INT || ENABLE_AUX) begin : g_integer
        VX_ucc_int_prepare #(
            .W (W)
        ) prepare (
            .a          (a),
            .b          (b),
            .op         (op),
            .mul_a      (integer_ma),
            .mul_b      (integer_mb),
            .products   (products[8:0]),
            .operands   (integer_operands),
            .negatives  (integer_negs),
            .sum        (raw_sum),
            .result     (integer_result),
            .predicate  (integer_predicate)
        );
    end else begin : g_no_integer
        assign integer_ma = '0;
        assign integer_mb = '0;
        assign integer_operands = '0;
        assign integer_negs = '0;
        assign integer_result = '0;
        assign integer_predicate = 1'b0;
    end
    if (ENABLE_AUX) begin : g_auxiliary
        VX_ucc_float_to_int #(
            .W (W)
        ) convert (
            .a               (a),
            .unsigned_result (op[0]),
            .rm              (rm),
            .align_data      (conversion_data),
            .align_distance  (conversion_distance),
            .aligned         (conversion_aligned),
            .sticky          (conversion_sticky),
            .operands        (conversion_operands),
            .negatives       (conversion_negs),
            .sum             (raw_sum),
            .result          (conversion_result),
            .flags           (conversion_flags)
        );
        VX_ucc_fp_compare compare (
            .a             (a),
            .b             (b),
            .op            (op),
            .unsigned_less (raw_sum[32]),
            .result        (comparison_result),
            .predicate     (comparison_predicate),
            .flags         (comparison_flags)
        );
    end else begin : g_no_auxiliary
        assign conversion_data = '0;
        assign conversion_distance = '0;
        assign conversion_operands = '0;
        assign conversion_negs = '0;
        assign conversion_result = '0;
        assign conversion_flags = '0;
        assign comparison_result = '0;
        assign comparison_predicate = 1'b0;
        assign comparison_flags = '0;
    end
    if (ENABLE_EXP && EXP_CONST) begin : g_constant_range
        assign compact_range_a = '0;
        assign compact_range_b = '0;
        assign range_product = {(|a[30:23]), a[22:0]} * 31'h5c551d95;
        assign range_wide_a = '0;
        assign range_wide_b = '0;
        assign range_small_a = '0;
        assign range_small_b = '0;
        assign f8_products = '0;
    end else if (ENABLE_EXP && COMPACT_EXP) begin : g_compact_range
        VX_ucc_exp_range_compact prepare (
            .a (a), .mul_a (compact_range_a), .mul_b (compact_range_b),
            .products (products[13:8]), .product (range_product)
        );
        assign range_wide_a = '0;
        assign range_wide_b = '0;
        assign range_small_a = '0;
        assign range_small_b = '0;
        assign f8_products = '0;
    end else if (ENABLE_EXP) begin : g_exp_range
        assign compact_range_a = '0;
        assign compact_range_b = '0;
        VX_ucc_exp_range prepare (
            .a              (a),
            .wide_a         (range_wide_a),
            .wide_b         (range_wide_b),
            .wide_products  (products[15:13]),
            .small_a        (range_small_a),
            .small_b        (range_small_b),
            .small_products (f8_products),
            .product        (range_product)
        );
        for (genvar i = 0; i < 32; ++i) begin : g_slice
            wire [3:0] ma, mb;
            if (i < 30 && i % 5 != 3) begin : g_shared
                assign ma = exp_mode ? range_small_a[i] : tensor_f8_ma[i];
                assign mb = exp_mode ? range_small_b[i] : tensor_f8_mb[i];
            end else begin : g_tensor
                assign ma = tensor_f8_ma[i];
                assign mb = tensor_f8_mb[i];
            end
            VX_tcu_tfr_wmul #(
                .N (4)
            ) multiplier (
                .clk    (1'b0),
                .enable (1'b1),
                .a      (ma),
                .b      (mb),
                .p      (f8_products[i])
            );
        end
    end else begin : g_no_exp_range
        assign compact_range_a = '0;
        assign compact_range_b = '0;
        assign range_wide_a = '0;
        assign range_wide_b = '0;
        assign range_small_a = '0;
        assign range_small_b = '0;
        assign range_product = '0;
        assign f8_products = '0;
    end
    if (ENABLE_EX2) begin : g_ex2
        wire [15:0][10:0] polynomial_a, polynomial_b;
        for (genvar i = 0; i < 16; ++i) begin : g_routing
            if (COMPACT_EXP && i >= 8 && i < 14) begin : g_range
                assign ex2_ma[i] = exp_mode ? compact_range_a[i-8] : 11'd0;
                assign ex2_mb[i] = exp_mode ? compact_range_b[i-8] : 11'd0;
            end else begin : g_polynomial
                assign ex2_ma[i] = polynomial_a[i];
                assign ex2_mb[i] = polynomial_b[i];
            end
        end
        VX_ucc_ex2_prepare #(
            .W (W),
            .NARROW (SMALL_NATIVE),
            .COMPACT (COMPACT_EXP)
        ) prepare (
            .a              (a),
            .natural        (exp_mode),
            .range_product  (range_product),
            .align_data     (ex2_align_data),
            .align_distance (ex2_align_distance),
            .aligned        (conversion_aligned),
            .mul_a          (polynomial_a),
            .mul_b          (polynomial_b),
            .products       (products),
            .operands       (ex2_operands),
            .base_exp       (ex2_base),
            .special        (ex2_special),
            .special_result (ex2_special_result)
        );
    end else begin : g_no_ex2
        assign ex2_ma = '0;
        assign ex2_mb = '0;
        assign ex2_operands = '0;
        assign ex2_align_data = '0;
        assign ex2_align_distance = '0;
        assign ex2_base = '0;
        assign ex2_special = 1'b0;
        assign ex2_special_result = '0;
    end
    for (genvar i = 0; i < 16; ++i) begin : g_mul
        wire [10:0] ma, mb;
        if (i < 9) begin : g_scalar
            if (ONEHOT_ROUTE) begin : g_parallel
                wire scalar_select = !ex2_mode && !dpa && !integer_mode;
                assign ma = ({11{ex2_mode}} & ex2_ma[i]) | ({11{dpa}} & tensor_ma[i])
                          | ({11{integer_mode}} & integer_ma[i]) | ({11{scalar_select}} & scalar_ma[i]);
                assign mb = ({11{ex2_mode}} & ex2_mb[i]) | ({11{dpa}} & tensor_mb[i])
                          | ({11{integer_mode}} & integer_mb[i]) | ({11{scalar_select}} & scalar_mb[i]);
            end else begin : g_priority
                assign ma = ex2_mode ? ex2_ma[i] : dpa ? tensor_ma[i] : integer_mode ? integer_ma[i] : scalar_ma[i];
                assign mb = ex2_mode ? ex2_mb[i] : dpa ? tensor_mb[i] : integer_mode ? integer_mb[i] : scalar_mb[i];
            end
        end else if (i >= 13 && !COMPACT_EXP) begin : g_range
            assign ma = exp_mode ? range_wide_a[i-13] : ex2_mode ? ex2_ma[i] : tensor_ma[i];
            assign mb = exp_mode ? range_wide_b[i-13] : ex2_mode ? ex2_mb[i] : tensor_mb[i];
        end else begin : g_tensor
            assign ma = ex2_mode ? ex2_ma[i] : tensor_ma[i];
            assign mb = ex2_mode ? ex2_mb[i] : tensor_mb[i];
        end
        if (MUL_C_ALIGN && i >= 12 && i <= 14) begin : g_align_route
            assign bank_ma[i] = !dpa && op <= 8'h03 ? align_ma[i-12] : ma;
            assign bank_mb[i] = !dpa && op <= 8'h03 ? align_mb[i-12] : mb;
        end else begin : g_normal_route
            assign bank_ma[i] = ma;
            assign bank_mb[i] = mb;
        end
        if (!FMA_SEGMENTED || i < 9 || i >= 12) begin : g_single
            VX_tcu_tfr_wmul #(.N (11)) multiplier (
                .clk (1'b0), .enable (1'b1), .a (bank_ma[i]), .b (bank_mb[i]), .p (products[i])
            );
        end
    end
    if (FMA_SEGMENTED) begin : g_reconfigured_slices
        VX_ucc_mul_reducer multiplier_group (
            .reduce_mode (!dpa && op <= 8'h03),
            .a (bank_ma[11:9]), .b (bank_mb[11:9]), .partials (products[8:0]),
            .products (products[11:9])
        );
    end
    VX_tcu_tfr_align #(
        .N  (17),
        .WI (25),
        .WO (32),
        .SHARED_SHIFT (SHARED_ALIGN)
    ) tensor_align (
        .clk         (1'b0),
        .valid_in    (1'b0),
        .req_id      (32'd0),
        .exponents   (exponents),
        .sel_exp     (exp_sel),
        .lane_mask   (native_mode ? 16'h01ff : lane_mask),
        .sigs_in     (native_mode ? native_sigs : raw_sigs),
        .is_int      (1'b0),
        .external_shift (float_to_int || ex2_mode),
        .external_data (shared_alignment_data),
        .external_amount (shared_alignment_amount),
        .external_result (shared_alignment_result),
        .external_sticky (shared_alignment_sticky),
        .max_exp     (max_exp),
        .sigs_out    (aligned),
        .sticky_bits (tensor_sticky),
        .fp_negs     (tensor_negs)
    );
    wire [16:0][W-1:0] operands;
    wire [16:0] negatives;
    for (genvar i = 0; i < 17; ++i) begin : g_acc_mux
        wire [W-1:0] converted;
        wire converted_negative;
        if (i < 2) begin : g_conversion
            assign converted = conversion_operands[i];
            assign converted_negative = conversion_negs[i];
        end else begin : g_no_conversion
            assign converted = '0;
            assign converted_negative = 1'b0;
        end
        if (i < 10) begin : g_scalar
            if (ONEHOT_ROUTE) begin : g_parallel
                wire scalar_select = !ex2_mode && !float_to_int && !integer_mode && !tensor_format_mode;
                wire [W-1:0] tensor_operand = SMALL_NATIVE ? W'(aligned[i]) : W'($signed(aligned[i]));
                assign operands[i] = ({W{ex2_mode}} & ex2_operands[i]) | ({W{float_to_int}} & converted)
                                   | ({W{integer_mode}} & integer_operands[i]) | ({W{tensor_format_mode}} & tensor_operand)
                                   | ({W{scalar_select}} & scalar_operands[i]);
                assign negatives[i] = (float_to_int && converted_negative) || (integer_mode && integer_negs[i])
                                    || (tensor_format_mode && tensor_negs[i]) || (scalar_select && scalar_negs[i]);
            end else begin : g_priority
                assign operands[i] = ex2_mode ? ex2_operands[i] : float_to_int ? converted : integer_mode ? integer_operands[i] : tensor_format_mode ? (SMALL_NATIVE ? W'(aligned[i]) : W'($signed(aligned[i]))) : scalar_operands[i];
                assign negatives[i] = ex2_mode ? 1'b0 : float_to_int ? converted_negative : integer_mode ? integer_negs[i] : tensor_format_mode ? tensor_negs[i] : scalar_negs[i];
            end
        end else begin : g_tensor
            if (ONEHOT_ROUTE) begin : g_parallel
                wire [W-1:0] tensor_operand = SMALL_NATIVE ? W'(aligned[i]) : W'($signed(aligned[i]));
                assign operands[i] = ({W{ex2_mode}} & ex2_operands[i]) | ({W{float_to_int}} & converted)
                                   | ({W{integer_mode}} & integer_operands[i]) | ({W{tensor_format_mode}} & tensor_operand);
                assign negatives[i] = (float_to_int && converted_negative) || (integer_mode && integer_negs[i])
                                    || (tensor_format_mode && tensor_negs[i]);
            end else begin : g_priority
                assign operands[i] = ex2_mode ? ex2_operands[i] : float_to_int ? converted : integer_mode ? integer_operands[i] : tensor_format_mode ? (SMALL_NATIVE ? W'(aligned[i]) : W'($signed(aligned[i]))) : '0;
                assign negatives[i] = ex2_mode ? 1'b0 : float_to_int ? converted_negative : integer_mode ? integer_negs[i] : tensor_format_mode && tensor_negs[i];
            end
        end
    end
    wire [W-1:0] magnitude;
    wire sign, sticky;
    if (FMA_SEGMENTED) begin : g_segmented_accumulator
        assign reduced_products = '0;
        VX_ucc_segmented_acc #(.N (17)) accumulator (
            .operands (operands), .negatives (negatives),
            .sticky_in (tensor_format_mode ? tensor_sticky : 17'd0),
            .sum (raw_sum), .magnitude (magnitude), .sign (sign), .sticky_out (sticky)
        );
    end else if (SMALL_NATIVE) begin : g_partitioned_accumulator
        assign reduced_products = '0;
        wire [31:0] small_magnitude;
        VX_ucc_partitioned_acc #(
            .N (17)
        ) accumulator (
            .operands     (operands),
            .negatives    (negatives),
            .sticky_in    (tensor_format_mode ? tensor_sticky : 17'd0),
            .full_product (integer_arithmetic || fp_compare || float_to_int),
            .sum          (raw_sum),
            .magnitude    (small_magnitude),
            .sign         (sign),
            .sticky_out   (sticky)
        );
        assign magnitude = W'(small_magnitude);
    end else begin : g_wide_accumulator
        VX_tcu_tfr_acc #(
            .POST_REDUCE (FMA_CSA),
            .N  (17),
            .WO (W)
        ) accumulator (
            .post_enable (FMA_CSA && !dpa && op <= 8'h03),
            .post_operands (post_operands),
            .post_negatives (post_negatives),
            .reduced_sigs (reduced_products),
            .clk        (1'b0),
            .valid_in   (1'b0),
            .req_id     (32'd0),
            .sigs_in    (operands),
            .sticky_in  (tensor_format_mode ? tensor_sticky : 17'd0),
            .fp_negs    (negatives),
            .sum_out    (raw_sum),
            .sig_out    (magnitude),
            .sign_out   (sign),
            .sticky_out (sticky)
        );
    end
    wire signed [11:0] base_exp = ex2_mode ? ex2_base : dpa ? 12'(max_exp) - 12'sd286 : int_to_float ? 12'sd0 : scalar_base;
    wire [31:0] rounded_result, shifted_result, clz_result;
    wire [4:0] rounded_flags;
    VX_ucc_round #(
        .WINDOW_SHIFT (WINDOW_NORM),
        .W (NORM_W),
        .DIRECT_DISTANCE (DIRECT_NORM)
    ) rounder (
        .magnitude (NORM_W'(shift_mode || (SMALL_NATIVE && int_to_float && op[0]) ? raw_sum : magnitude)),
        .base_exp  (base_exp),
        .sign      (SMALL_NATIVE && int_to_float && op[0] ? 1'b0 : dpa || int_to_float || (|magnitude) ? sign : zero_sign),
        .rm        (tensor_format_mode || ex2_mode ? 2'd0 : rm),
        .sticky_in (sticky),
        .dpa       (tensor_format_mode),
        .shift_mode (shift_mode),
        .shift_left (op == 8'h30),
        .shift_signed (op == 8'h32 && a[31]),
        .shift_count (b[4:0]),
        .shift_result (shifted_result),
        .clz_result (clz_result),
        .result    (rounded_result),
        .flags     (rounded_flags)
    );
    assign predicate = fp_compare ? comparison_predicate : integer_arithmetic && integer_predicate;
    assign result = ex2_mode ? (ex2_special ? ex2_special_result : rounded_result)
                  : boolean_mode ? boolean_result
                  : fp_sign_op ? {op[0] ? 1'b0 : !a[31], a[30:0]}
                  : fp_compare ? comparison_result
                  : shift_mode ? (op == 8'h33 ? clz_result : shifted_result)
                  : int_to_float ? rounded_result
                  : float_to_int ? conversion_result
                  : integer_arithmetic ? integer_result : dpa ? (exceptions.is_nan ? 32'h7fc00000
                         : exceptions.is_inf ? {exceptions.sign, 8'hff, 23'd0}
                         : rounded_result)
                       : scalar_special ? scalar_special_result : rounded_result;
    assign flags = ex2_mode || boolean_mode || fp_sign_op || shift_mode || integer_arithmetic || dpa ? 5'd0
                 : fp_compare ? comparison_flags
                 : float_to_int ? conversion_flags
                 : int_to_float ? rounded_flags
                 : native_mode ? scalar_special_flags
                 : scalar_special ? scalar_special_flags : rounded_flags;
endmodule
