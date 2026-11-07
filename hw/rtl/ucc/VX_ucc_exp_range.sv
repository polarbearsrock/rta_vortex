`include "VX_define.vh"

module VX_ucc_exp_range (
    input  wire [31:0]       a,
    output wire [2:0][10:0]  wide_a,
    output wire [2:0][10:0]  wide_b,
    input  wire [2:0][21:0]  wide_products,
    output wire [31:0][3:0]  small_a,
    output wire [31:0][3:0]  small_b,
    input  wire [31:0][7:0]  small_products,
    output wire [54:0]      product
);
    localparam [30:0] LOG2E_Q30 = 31'h5c551d95;
    wire [23:0] significand = {(|a[30:23]), a[22:0]};
    wire [32:0][54:0] terms;
    for (genvar i = 0; i < 3; ++i) begin : g_high
        assign wide_a[i] = {3'd0, significand[i*8 +: 8]};
        assign wide_b[i] = LOG2E_Q30[30:20];
        assign terms[i] = 55'(wide_products[i]) << (20 + i*8);
    end
    for (genvar i = 0; i < 30; ++i) begin : g_low
        localparam COLUMN = i % 5;
        localparam ROW = i / 5;
        localparam OFFSET = 4 * (ROW + COLUMN);
        if (COLUMN == 3) begin : g_one
            assign small_a[i] = '0;
            assign small_b[i] = '0;
            assign terms[3+i] = 55'(significand[ROW*4 +: 4]) << OFFSET;
        end else begin : g_product
            assign small_a[i] = significand[ROW*4 +: 4];
            assign small_b[i] = LOG2E_Q30[COLUMN*4 +: 4];
            assign terms[3+i] = 55'(small_products[i]) << OFFSET;
        end
    end
    assign small_a[31:30] = '0;
    assign small_b[31:30] = '0;
    wire [54:0] sum_vec, carry_vec;
    VX_csa_tree #(
        .N (33),
        .W (55),
        .S (55)
    ) reduction (
        .operands (terms),
        .sum      (sum_vec),
        .carry    (carry_vec)
    );
    VX_ks_adder #(
        .N (55),
        .BYPASS (`FORCE_BUILTIN_ADDER(55))
    ) adder (
        .cin   (1'b0),
        .dataa (sum_vec),
        .datab (carry_vec),
        .sum   (product),
        `UNUSED_PIN (cout)
    );
endmodule
