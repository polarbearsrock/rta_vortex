module VX_ucc_fma_prepare #(
    parameter W = 80,
    parameter CHUNK = 11,
    parameter REDUCE_FIRST = 0,
    parameter ANCHORED = 0,
    parameter CROP_PRODUCTS = 0,
    parameter RESOLVED = 0,
    parameter MUL_C_ALIGN = 0
) (
    input  wire [31:0]             a,
    input  wire [31:0]             b,
    input  wire [31:0]             c,
    input  wire [1:0]              op,
    input  wire [1:0]              rm,
    input  wire [31:0]             raw_sum,
    input  wire [47:0]             resolved_product,
    output wire [2:0][10:0]        align_mul_a,
    output wire [2:0][10:0]        align_mul_b,
    input wire [2:0][21:0]         align_products,
    output wire [8:0][10:0]        mul_a,
    output wire [8:0][10:0]        mul_b,
    input  wire [8:0][21:0]        products,
    input  wire [1:0][W-1:0]       reduced_products,
    output wire [2:0][W-1:0]       post_operands,
    output wire [2:0]              post_negatives,
    input  wire                    external_align,
    input  wire [W-1:0]            align_data,
    input  wire signed [11:0]      align_distance,
    output wire [W-1:0]            align_result,
    output wire                    align_sticky,
    output wire [9:0][W-1:0]       operands,
    output wire [9:0]              negatives,
    output wire signed [11:0]     base_exp,
    output wire                    zero_sign,
    output wire                    special,
    output wire [31:0]             special_result,
    output wire [4:0]              special_flags
);
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
    wire pzero = xzero || yzero;
    assign zero_sign = pzero && zzero && (psign == z[31]) ? psign : rm == 2;
    wire signed [11:0] xe = (ex == 0) ? -12'sd149 : 12'({1'b0, ex}) - 12'sd150;
    wire signed [11:0] ye = (ey == 0) ? -12'sd149 : 12'({1'b0, ey}) - 12'sd150;
    wire signed [11:0] ze = (ez == 0) ? -12'sd149 : 12'({1'b0, ez}) - 12'sd150;
    wire signed [11:0] pe = xe + ye;
    wire [4:0] lx, ly, lz;
    if (RESOLVED) begin : g_input_bounds
        VX_lzc #(.N (24)) x_lzc (.data_in (mx), .data_out (lx), .valid_out ());
        VX_lzc #(.N (24)) y_lzc (.data_in (my), .data_out (ly), .valid_out ());
        VX_lzc #(.N (24)) z_lzc (.data_in (mz), .data_out (lz), .valid_out ());
    end else begin : g_fixed_bounds
        assign lx = '0;
        assign ly = '0;
        assign lz = '0;
    end
    wire signed [11:0] ptop = pzero ? -12'sd1024 : pe + 12'sd47 - 12'(lx) - 12'(ly);
    wire signed [11:0] ctop = zzero ? -12'sd1024 : ze + 12'sd23 - 12'(lz);
    // This gap bounds the product below one eighth of C's encoding quantum.
    wire dominant_c = ANCHORED && !zzero && (pzero || ctop >= ptop + 12'sd27);
    wire step_up = !pzero && psign == z[31] && ((rm == 3 && !z[31]) || (rm == 2 && z[31]));
    wire step_down = !pzero && psign != z[31] && (rm == 1 || (rm == 3 && z[31]) || (rm == 2 && !z[31]));
    wire dominant_overflow = !pzero && step_up && z[30:0] == 31'h7f7fffff;
    wire dominant_tiny = !pzero && (ez == 0 || (z[30:0] == 31'h00800000 && step_down));
    assign special = nan_result || pinf || zinf || dominant_c;
    assign special_result = nan_result ? 32'h7fc00000
                          : pinf || zinf || !dominant_c ? {pinf ? psign : z[31], 8'hff, 23'd0} : raw_sum;
    assign special_flags = dominant_c && !(nan_result || pinf || zinf)
                         ? {2'b00, dominant_overflow, dominant_tiny, !pzero} : {invalid, 4'd0};
    assign base_exp = ANCHORED ? pe - 12'sd3
                              : ((ptop > ctop) ? ptop : ctop) - 12'(W-3);

    wire [32:0] xa = {9'd0, mx}, ya = {9'd0, my};
    wire [W-1:0] resolved_aligned;
    if (RESOLVED) begin : g_resolved_align
        wire signed [11:0] distance = base_exp - pe;
        wire left = distance < 0;
        wire [11:0] amount = left ? 12'(-distance) : 12'(distance);
        wire [W-1:0] shifted;
        wire sticky;
        VX_ucc_shift_jam #(.W (W), .SW (12)) align (
            .data_in (W'(resolved_product)), .amount (amount), .left (left), .fill (1'b0),
            .data_out (shifted), .sticky (sticky)
        );
        assign resolved_aligned = shifted | W'(sticky);
    end else begin : g_no_resolved_align
        assign resolved_aligned = '0;
    end
    for (genvar i = 0; i < 9; ++i) begin : g_product
        localparam OFFSET = CHUNK * ((i / 3) + (i % 3));
        localparam A_BITS = (i/3 == 2) ? 24-2*CHUNK : CHUNK;
        localparam B_BITS = (i%3 == 2) ? 24-2*CHUNK : CHUNK;
        localparam PRODUCT_BITS = CROP_PRODUCTS ? A_BITS+B_BITS : 22;
        wire [PRODUCT_BITS-1:0] product = products[i][PRODUCT_BITS-1:0];
        assign mul_a[i] = 11'(xa[(i/3)*CHUNK +: CHUNK]);
        assign mul_b[i] = 11'(ya[(i%3)*CHUNK +: CHUNK]);
        if (RESOLVED) begin : g_complete_product
            assign operands[i] = i == 0 ? (psign ? ~resolved_aligned : resolved_aligned) : '0;
            assign negatives[i] = i == 0 && psign;
        end else if (ANCHORED) begin : g_fixed
            wire [W-1:0] magnitude = W'(product) << (OFFSET+3);
            wire [W-1:0] encoded_c = i == 0 ? W'(z)
                                   : i == 1 ? (W'(step_up) | {W{step_down}}) : '0;
            assign operands[i] = dominant_c ? encoded_c : psign ? ~magnitude : magnitude;
            assign negatives[i] = !dominant_c && psign;
        end else if (REDUCE_FIRST) begin : g_raw
            assign operands[i] = W'(product) << OFFSET;
            assign negatives[i] = 1'b0;
        end else begin : g_aligned
            wire signed [11:0] distance = base_exp - pe - 12'(OFFSET);
            wire left = distance < 0;
            wire [11:0] amount = left ? 12'(-distance) : 12'(distance);
            wire [W-1:0] shifted;
            wire sticky;
            VX_ucc_shift_jam #(.W (W), .SW (12)) align (
                .data_in (W'(product)), .amount (amount), .left (left), .fill (1'b0),
                .data_out (shifted), .sticky (sticky)
            );
            wire [W-1:0] jammed = shifted | W'(sticky);
            assign operands[i] = psign ? ~jammed : jammed;
            assign negatives[i] = psign;
        end
    end
    wire signed [11:0] c_distance = external_align ? align_distance : MUL_C_ALIGN ? 12'sd0 : base_exp - ze;
    wire c_left = c_distance < 0;
    wire [11:0] c_amount = c_left ? 12'(-c_distance) : 12'(c_distance);
    wire [W-1:0] c_shifted;
    wire c_sticky;
    VX_ucc_shift_jam #(
        .W  (W),
        .SW (12)
    ) align_c (
        .data_in  (external_align ? align_data : MUL_C_ALIGN ? {W{1'b0}} : W'(mz)),
        .amount   (c_amount),
        .left     (c_left),
        .fill     (1'b0),
        .data_out (c_shifted),
        .sticky   (c_sticky)
    );
    wire [W-1:0] mul_aligned;
    wire mul_sticky;
    if (MUL_C_ALIGN) begin : g_multiplier_alignment
        VX_ucc_mul_align #(.W (W)) align (
            .significand (mz), .distance (base_exp-ze), .mul_a (align_mul_a), .mul_b (align_mul_b),
            .products (align_products), .aligned (mul_aligned), .sticky (mul_sticky)
        );
    end else begin : g_no_multiplier_alignment
        assign align_mul_a = '0;
        assign align_mul_b = '0;
        assign mul_aligned = '0;
        assign mul_sticky = 1'b0;
    end
    wire [W-1:0] c_jammed = MUL_C_ALIGN && !external_align ? mul_aligned | W'(mul_sticky) : c_shifted | W'(c_sticky);
    assign align_result = c_shifted;
    assign align_sticky = c_sticky;
    assign operands[9] = REDUCE_FIRST || dominant_c ? '0 : z[31] ? ~c_jammed : c_jammed;
    assign negatives[9] = !REDUCE_FIRST && !dominant_c && z[31];
    if (REDUCE_FIRST) begin : g_post_alignment
        wire signed [11:0] distance = base_exp - pe;
        wire left = distance < 0;
        wire [11:0] amount = left ? 12'(-distance) : 12'(distance);
        for (genvar i = 0; i < 2; ++i) begin : g_row
            wire [W-1:0] shifted;
            wire sticky;
            VX_ucc_shift_jam #(.W (W), .SW (12)) align (
                .data_in (W'(reduced_products[i][47:0])), .amount (amount),
                .left (left), .fill (1'b0), .data_out (shifted), .sticky (sticky)
            );
            wire [W-1:0] jammed = shifted | W'(sticky);
            assign post_operands[i] = psign ? ~jammed : jammed;
            assign post_negatives[i] = psign;
        end
        assign post_operands[2] = z[31] ? ~c_jammed : c_jammed;
        assign post_negatives[2] = z[31];
    end else begin : g_no_post_alignment
        assign post_operands = '0;
        assign post_negatives = '0;
    end
endmodule
