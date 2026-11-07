module VX_ucc_segments_test (
    input wire reduce_mode,
    input wire [2:0][31:0] a, b,
    input wire [8:0][31:0] partials,
    output wire [2:0][31:0] products,
    input wire [95:0] data,
    input wire [11:0] amount,
    input wire left, fill,
    output wire [1:0][31:0] shifted,
    output wire [1:0] sticky,
    input wire [16:0][63:0] operands,
    input wire [16:0] negatives,
    output wire [63:0] sum, magnitude,
    output wire sign,
    input wire [23:0] c_sig,
    input wire signed [11:0] c_distance,
    output wire [63:0] c_aligned,
    output wire c_sticky
);
    wire [2:0][10:0] ma, mb;
    wire [8:0][21:0] pp;
    wire [2:0][21:0] p;
    for (genvar i = 0; i < 3; ++i) begin : g_lanes
        assign ma[i] = a[i][10:0];
        assign mb[i] = b[i][10:0];
        assign products[i] = {10'd0, p[i]};
    end
    for (genvar i = 0; i < 9; ++i) begin : g_partials
        assign pp[i] = partials[i][21:0];
    end
    VX_ucc_mul_reducer reducer (.reduce_mode (reduce_mode), .a (ma), .b (mb), .partials (pp), .products (p));
    for (genvar i = 0; i < 2; ++i) begin : g_window
        VX_ucc_shift_window #(.W (64+16*i)) shifter (
            .data_in (data[63+16*i:0]), .amount (amount), .left (left), .fill (fill),
            .data_out (shifted[i]), .sticky (sticky[i])
        );
    end
    VX_ucc_segmented_acc accumulator (
        .operands (operands), .negatives (negatives), .sticky_in ('0),
        .sum (sum), .magnitude (magnitude), .sign (sign), .sticky_out ()
    );
    wire [2:0][10:0] ca, cb;
    wire [2:0][21:0] cp;
    VX_ucc_mul_align align_c (
        .significand (c_sig), .distance (c_distance), .mul_a (ca), .mul_b (cb),
        .products (cp), .aligned (c_aligned), .sticky (c_sticky)
    );
    for (genvar i = 0; i < 3; ++i) begin : g_align_mul
        VX_tcu_tfr_wmul #(.N (11)) multiplier (
            .clk (1'b0), .enable (1'b1), .a (ca[i]), .b (cb[i]), .p (cp[i])
        );
    end
endmodule
