`include "VX_define.vh"

module VX_ucc_exp_range_compact (
    input  wire [31:0]       a,
    output wire [5:0][10:0]  mul_a,
    output wire [5:0][10:0]  mul_b,
    input  wire [5:0][21:0]  products,
    output wire [54:0]      product
);
    localparam [32:0] LOG2E_Q30 = 33'h05c551d95;
    wire [23:0] significand = {(|a[30:23]), a[22:0]};
    wire [8:0][54:0] terms;
    for (genvar i = 0; i < 6; ++i) begin : g_product
        assign mul_a[i] = significand[(i/3)*11 +: 11];
        assign mul_b[i] = LOG2E_Q30[(i%3)*11 +: 11];
        assign terms[i] = 55'(products[i]) << (11*((i/3)+(i%3)));
    end
    // Two input bits select four constant values, with no variable multiplier.
    for (genvar i = 0; i < 3; ++i) begin : g_high_digit
        localparam [12:0] COEFFICIENT = 13'(LOG2E_Q30[i*11 +: 11]);
        wire [12:0] value = significand[23:22] == 0 ? 13'd0
                           : significand[23:22] == 1 ? COEFFICIENT
                           : significand[23:22] == 2 ? COEFFICIENT*13'd2 : COEFFICIENT*13'd3;
        assign terms[6+i] = 55'(value) << (22+11*i);
    end
    wire [54:0] sum_vec, carry_vec;
    VX_csa_tree #(.N (9), .W (55), .S (55)) reduction (
        .operands (terms), .sum (sum_vec), .carry (carry_vec)
    );
    VX_ks_adder #(.N (55), .BYPASS (`FORCE_BUILTIN_ADDER(55))) adder (
        .cin (1'b0), .dataa (sum_vec), .datab (carry_vec), .sum (product),
        `UNUSED_PIN (cout)
    );
endmodule
