`include "VX_define.vh"

module VX_ucc_ex2_prepare #(
    parameter W = 80,
    parameter NARROW = 0,
    parameter COMPACT = 0
) (
    input  wire [31:0]           a,
    input  wire                 natural,
    input  wire [54:0]          range_product,
    output wire [W-1:0]         align_data,
    output wire signed [11:0]   align_distance,
    input  wire [W-1:0]         aligned,
    output wire [15:0][10:0]    mul_a,
    output wire [15:0][10:0]    mul_b,
    input  wire [15:0][21:0]    products,
    output wire [16:0][W-1:0]   operands,
    output wire signed [11:0]   base_exp,
    output wire                 special,
    output wire [31:0]          special_result
);
    `STATIC_ASSERT (W >= 49, ("EX2 product preparation requires 49 bits"))
    wire [7:0] e = a[30:23];
    assign align_data = natural ? W'(range_product) : W'({(|e), a[22:0]});
    assign align_distance = (natural ? 12'sd150 : 12'sd120) - 12'(e);
    wire [38:0] fixed_x = a[31] ? -aligned[38:0] : aligned[38:0];
    wire signed [8:0] integer_part = $signed(fixed_x[38:30]);
    wire [5:0] index = fixed_x[29:24];
    wire [17:0] residual = fixed_x[23:6];
    wire [31:0] a0;
    wire signed [26:0] a1;
    wire signed [19:0] a2;
    VX_mufu_rom #(
        .REGISTERED (0)
    ) coefficients (
        .clk    (1'b0),
        .enable (1'b1),
        .tbl    (3'd2),
        .idx    ({1'b0, index}),
        .a0     (a0),
        .a1     (a1),
        .a2     (a2)
    );

    if (COMPACT) begin : g_compact
        wire [32:0] linear_coefficient = 33'(a1);
        wire [21:0] linear_input = {4'd0, residual};
        for (genvar i = 0; i < 6; ++i) begin : g_linear
            assign mul_a[i] = linear_coefficient[(i/2)*11 +: 11];
            assign mul_b[i] = linear_input[(i%2)*11 +: 11];
            wire [W-1:0] term = W'(products[i]) << (11*((i/2)+(i%2)));
            assign operands[i] = NARROW ? term >> 18 : term;
        end
        assign mul_a[6] = residual[17:7];
        assign mul_b[6] = residual[17:7];
        assign mul_a[7] = a2[16:6];
        assign mul_b[7] = products[6][21:11];
        assign mul_a[15:8] = '0;
        assign mul_b[15:8] = '0;
        assign operands[6] = NARROW ? W'(products[7]) >> 5 : W'(products[7]) << 13;
        assign operands[7] = NARROW ? W'(a0) : W'(a0) << 18;
        assign operands[16:8] = '0;
    end else begin : g_full
        // Symmetry reduces an 18-bit square to three 11-bit slice products.
        assign mul_a[0] = residual[10:0];
        assign mul_b[0] = residual[10:0];
        assign mul_a[1] = residual[10:0];
        assign mul_b[1] = {4'd0, residual[17:11]};
        assign mul_a[2] = {4'd0, residual[17:11]};
        assign mul_b[2] = {4'd0, residual[17:11]};
        wire [2:0][35:0] square_terms;
        assign square_terms[0] = 36'(products[0]);
        assign square_terms[1] = 36'(products[1]) << 12;
        assign square_terms[2] = 36'(products[2]) << 22;
        wire [35:0] square_sum, square_carry;
        VX_csa_tree #(
            .N (3),
            .W (36),
            .S (36)
        ) square_reduction (
            .operands (square_terms),
            .sum      (square_sum),
            .carry    (square_carry)
        );
        wire [35:0] square = square_sum + square_carry;
        wire [17:0] squared_residual = square[35:18];
        wire [32:0] linear_coefficient = 33'(a1);
        wire [21:0] quadratic_coefficient = 22'(a2);
        wire [21:0] linear_input = {4'd0, residual};
        wire [21:0] quadratic_input = {4'd0, squared_residual};
        for (genvar i = 0; i < 6; ++i) begin : g_linear
            assign mul_a[3+i] = linear_coefficient[(i/2)*11 +: 11];
            assign mul_b[3+i] = linear_input[(i%2)*11 +: 11];
            wire [W-1:0] term = W'(products[3+i]) << (11*((i/2)+(i%2)));
            assign operands[i] = NARROW ? term >> 18 : term;
        end
        for (genvar i = 0; i < 4; ++i) begin : g_quadratic
            assign mul_a[9+i] = quadratic_coefficient[(i/2)*11 +: 11];
            assign mul_b[9+i] = quadratic_input[(i%2)*11 +: 11];
            wire [W-1:0] term = W'(products[9+i]) << (11*((i/2)+(i%2)));
            assign operands[6+i] = NARROW ? term >> 18 : term;
        end
        assign mul_a[15:13] = '0;
        assign mul_b[15:13] = '0;
        assign operands[10] = NARROW ? W'(a0) : W'(a0) << 18;
        assign operands[16:11] = '0;
        `UNUSED_VAR (square[17:0])
    end
    assign base_exp = 12'(integer_part) - (NARROW ? 12'sd30 : 12'sd48);
    wire nan_input = (&e) && (|a[22:0]);
    assign special = e == 0 || e >= (natural ? 134 : 135);
    assign special_result = nan_input ? 32'h7fc00000
                          : e == 0 ? 32'h3f800000
                          : a[31] ? 32'd0 : 32'h7f800000;
    `UNUSED_VAR ({aligned[W-1:39], fixed_x[5:0]})
endmodule
