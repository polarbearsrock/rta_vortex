`include "VX_define.vh"

module VX_ucc_mufu_standalone (
    input  wire [31:0] a,
    input  wire [7:0]  op,
    output wire [31:0] result,
    output wire [4:0]  flags,
    output wire        predicate
);
    wire natural = op[0];
    wire [7:0] e = a[30:23];
    wire [23:0] significand = {(|e), a[22:0]};
    wire [54:0] range_product = significand * 31'h5c551d95;
    wire signed [11:0] distance = (natural ? 12'sd150 : 12'sd120) - 12'(e);
    wire left = distance < 0;
    wire [11:0] amount = left ? 12'(-distance) : 12'(distance);
    wire [63:0] aligned;
    VX_ucc_shift_jam #(.W (64), .SW (12)) alignment (
        .data_in (natural ? 64'(range_product) : 64'(significand)),
        .amount (amount), .left (left), .fill (1'b0),
        .data_out (aligned), `UNUSED_PIN (sticky)
    );
    wire [38:0] fixed_x = a[31] ? -aligned[38:0] : aligned[38:0];
    wire signed [8:0] integer_part = $signed(fixed_x[38:30]);
    wire [17:0] residual = fixed_x[23:6];
    wire [31:0] a0;
    wire signed [26:0] a1;
    wire signed [19:0] a2;
    VX_mufu_rom #(.REGISTERED (0)) coefficients (
        .clk (1'b0), .enable (1'b1), .tbl (3'd2), .idx ({1'b0, fixed_x[29:24]}),
        .a0 (a0), .a1 (a1), .a2 (a2)
    );
    wire [35:0] square = residual * residual;
    wire [44:0] linear = $unsigned(a1) * residual;
    wire [37:0] quadratic = $unsigned(a2) * square[35:18];
    wire [2:0][49:0] terms;
    assign terms[0] = {a0, 18'd0};
    assign terms[1] = 50'(linear);
    assign terms[2] = 50'(quadratic);
    wire [49:0] sum, carry;
    VX_csa_tree #(.N (3), .W (50), .S (50)) reduction (
        .operands (terms), .sum (sum), .carry (carry)
    );
    wire [49:0] polynomial = sum + carry;
    wire [31:0] finite_result;
    VX_ucc_round #(.W (64)) rounder (
        .magnitude (64'(polynomial)), .base_exp (12'(integer_part) - 12'sd48),
        .sign (1'b0), .rm (2'd0), .sticky_in (1'b0), .dpa (1'b0),
        .shift_mode (1'b0), .shift_left (1'b0), .shift_signed (1'b0), .shift_count (5'd0),
        `UNUSED_PIN (shift_result), `UNUSED_PIN (clz_result),
        .result (finite_result), `UNUSED_PIN (flags)
    );
    wire nan_input = (&e) && (|a[22:0]);
    wire special = e == 0 || e >= (natural ? 134 : 135);
    assign result = !special ? finite_result : nan_input ? 32'h7fc00000
                  : e == 0 ? 32'h3f800000 : a[31] ? 32'd0 : 32'h7f800000;
    assign flags = '0;
    assign predicate = 1'b0;
endmodule
