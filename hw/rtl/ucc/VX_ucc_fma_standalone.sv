module VX_ucc_fma_standalone #(
    parameter W = 80,
    parameter ENABLE_AUX = 0
) (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [7:0]  op,
    input  wire [1:0]  rm,
    output wire [31:0] result,
    output wire [4:0]  flags,
    output wire        predicate
);
    wire int_to_float = ENABLE_AUX && (op == 8'h40 || op == 8'h41);
    wire float_to_int = ENABLE_AUX && (op == 8'h42 || op == 8'h43);
    wire compare_mode = ENABLE_AUX && op >= 8'h08 && op <= 8'h0f;
    wire sign_mode = ENABLE_AUX && (op == 8'h04 || op == 8'h05);
    wire [W-1:0] conversion_data, raw_sum;
    wire signed [11:0] conversion_distance;
    wire [1:0][W-1:0] conversion_operands;
    wire [1:0] conversion_negatives;
    wire [31:0] conversion_result, comparison_result;
    wire [4:0] conversion_flags, comparison_flags;
    wire comparison_predicate;
    // op: 0 FMA, 1 MUL, 2 ADD, 3 SUB. MUL uses a same-sign zero addend.
    wire [31:0] x = a;
    wire [31:0] y = op[1] ? 32'h3f800000 : b;
    wire psign = x[31] ^ y[31];
    wire [31:0] z = op[1] ? {b[31] ^ op[0], b[30:0]}
                         : op[0] ? {psign, 31'd0} : c;
    wire [7:0] ex = x[30:23], ey = y[30:23], ez = z[30:23];
    wire [23:0] mx = {(|ex), x[22:0]}, my = {(|ey), y[22:0]}, mz = {(|ez), z[22:0]};
    wire xzero = x[30:0] == 0, yzero = y[30:0] == 0, zzero = z[30:0] == 0;
    wire xnan = (&ex) && (|x[22:0]), ynan = (&ey) && (|y[22:0]), znan = (&ez) && (|z[22:0]);
    wire xinf = (&ex) && !(|x[22:0]), yinf = (&ey) && !(|y[22:0]), zinf = (&ez) && !(|z[22:0]);
    wire snan = (xnan && !x[22]) || (ynan && !y[22]) || (znan && !z[22]);
    wire bad_product = (xinf && yzero) || (yinf && xzero);
    wire pinf = (xinf || yinf) && !(xnan || ynan || bad_product);
    wire bad_sum = pinf && zinf && (psign != z[31]);
    wire invalid = snan || bad_product || bad_sum;
    wire nan_result = xnan || ynan || znan || invalid;
    wire special = nan_result || pinf || zinf;
    wire [31:0] special_result = nan_result ? 32'h7fc00000
                          : {pinf ? psign : z[31], 8'hff, 23'd0};
    wire [4:0] special_flags = {invalid, 4'd0};
    wire pzero = xzero || yzero;
    wire zero_sign = pzero && zzero && (psign == z[31]) ? psign : rm == 2;
    wire signed [11:0] xe = (ex == 0) ? -12'sd149 : 12'({1'b0, ex}) - 12'sd150;
    wire signed [11:0] ye = (ey == 0) ? -12'sd149 : 12'({1'b0, ey}) - 12'sd150;
    wire signed [11:0] ze = (ez == 0) ? -12'sd149 : 12'({1'b0, ez}) - 12'sd150;
    wire signed [11:0] pe = xe + ye;
    wire signed [11:0] ptop = pzero ? -12'sd1024 : pe + 12'sd47;
    wire signed [11:0] ctop = zzero ? -12'sd1024 : ze + 12'sd23;
    wire signed [11:0] base_exp = ((ptop > ctop) ? ptop : ctop) - 12'(W-3);

    wire [47:0] product = mx * my;
    wire [1:0][W-1:0] aligned, operands;
    wire [1:0] negative_terms, align_sticky;
    for (genvar i = 0; i < 2; ++i) begin : g_align
        wire signed [11:0] distance = i == 1 && float_to_int ? conversion_distance : base_exp - (i == 0 ? pe : ze);
        wire left = distance < 0;
        wire [11:0] amount = left ? 12'(-distance) : 12'(distance);
        VX_ucc_shift_jam #(
            .W  (W),
            .SW (12)
        ) shifter (
            .data_in  (i == 0 ? W'(product) : float_to_int ? conversion_data : W'(mz)),
            .amount   (amount),
            .left     (left),
            .fill     (1'b0),
            .data_out (aligned[i]),
            .sticky   (align_sticky[i])
        );
        wire [W-1:0] jammed = aligned[i] | W'(align_sticky[i]);
        wire fma_negative = i == 0 ? psign : z[31];
        assign negative_terms[i] = float_to_int ? conversion_negatives[i]
                                  : int_to_float ? 1'b0 : compare_mode ? (i == 1) : fma_negative;
        assign operands[i] = float_to_int ? conversion_operands[i]
                           : int_to_float ? (i == 0 ? (op[0] ? W'(a) : W'($signed(a))) : '0)
                           : compare_mode ? (i == 0 ? W'(a) : ~W'(b))
                           : fma_negative ? ~jammed : jammed;
    end
    if (ENABLE_AUX) begin : g_auxiliary
        VX_ucc_float_to_int #(.W (W)) convert (
            .a (a), .unsigned_result (op[0]), .rm (rm),
            .align_data (conversion_data), .align_distance (conversion_distance),
            .aligned (aligned[1]), .sticky (align_sticky[1]),
            .operands (conversion_operands), .negatives (conversion_negatives),
            .sum (raw_sum), .result (conversion_result), .flags (conversion_flags)
        );
        VX_ucc_fp_compare compare (
            .a (a), .b (b), .op (op), .unsigned_less (raw_sum[32]),
            .result (comparison_result), .predicate (comparison_predicate), .flags (comparison_flags)
        );
    end else begin : g_no_auxiliary
        assign conversion_data = '0;
        assign conversion_distance = '0;
        assign conversion_operands = '0;
        assign conversion_negatives = '0;
        assign conversion_result = '0;
        assign conversion_flags = '0;
        assign comparison_result = '0;
        assign comparison_predicate = 1'b0;
        assign comparison_flags = '0;
    end
    wire [W-1:0] magnitude;
    wire sign;
    VX_tcu_tfr_acc #(
        .N  (2),
        .WO (W)
    ) accumulator (
        .post_enable (1'b0),
        .post_operands ('0),
        .post_negatives ('0),
        .reduced_sigs (),
        .clk        (1'b0),
        .valid_in   (1'b0),
        .req_id     (32'd0),
        .sigs_in    (operands),
        .sticky_in  (2'd0),
        .fp_negs    (negative_terms),
        .sum_out    (raw_sum),
        .sig_out    (magnitude),
        .sign_out   (sign),
        .sticky_out ()
    );
    wire [31:0] finite_result;
    wire [4:0] finite_flags;
    VX_ucc_round #(
        .W (W)
    ) rounder (
        .magnitude   (magnitude),
        .base_exp    (int_to_float ? 12'sd0 : base_exp),
        .sign        (int_to_float || (|magnitude) ? sign : zero_sign),
        .rm          (rm),
        .sticky_in   (1'b0),
        .dpa         (1'b0),
        .shift_mode  (1'b0),
        .shift_left  (1'b0),
        .shift_signed (1'b0),
        .shift_count (5'd0),
        .shift_result (),
        .clz_result  (),
        .result      (finite_result),
        .flags       (finite_flags)
    );
    assign result = sign_mode ? {op[0] ? 1'b0 : !a[31], a[30:0]}
                  : compare_mode ? comparison_result
                  : float_to_int ? conversion_result
                  : int_to_float ? finite_result : special ? special_result : finite_result;
    assign flags = sign_mode ? 5'd0 : compare_mode ? comparison_flags
                 : float_to_int ? conversion_flags
                 : int_to_float ? finite_flags : special ? special_flags : finite_flags;
    assign predicate = compare_mode && comparison_predicate;
endmodule
