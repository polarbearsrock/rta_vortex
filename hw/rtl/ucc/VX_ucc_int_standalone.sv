`include "VX_define.vh"

module VX_ucc_int_standalone (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [7:0]  op,
    input  wire [7:0]  immediate,
    output wire [31:0] result,
    output wire        predicate
);
    wire [63:0] product = a * b;
    wire high = op >= 8'h15 && op <= 8'h17;
    wire compare_op = op >= 8'h18 && op <= 8'h2f;
    wire negate = op == 8'h12 || (op == 8'h13 && a[31]);
    wire subtract = op == 8'h11 || compare_op;
    wire correction_a = high && op != 8'h15 && a[31];
    wire correction_b = high && op == 8'h16 && b[31];
    wire [3:0][32:0] operands;
    assign operands[0] = {1'b0, high ? product[63:32] : negate ? ~a : a};
    assign operands[1] = {1'b0, high ? (correction_a ? ~b : 32'd0)
                                     : subtract ? ~b : op == 8'h10 ? b : 32'd0};
    assign operands[2] = {1'b0, correction_b ? ~a : 32'd0};
    assign operands[3] = high ? (33'(correction_a) + 33'(correction_b)) : 33'(negate || subtract);
    wire [32:0] sum_vec, carry_vec;
    VX_csa_tree #(
        .N (4),
        .W (33),
        .S (33)
    ) reduction (
        .operands (operands),
        .sum      (sum_vec),
        .carry    (carry_vec)
    );
    wire [31:0] sum;
    wire carry;
    VX_ks_adder #(
        .N (32),
        .BYPASS (`FORCE_BUILTIN_ADDER(32))
    ) adder (
        .cin   (1'b0),
        .dataa (sum_vec[31:0]),
        .datab (carry_vec[31:0]),
        .sum   (sum),
        .cout  (carry)
    );
    wire borrow = !(sum_vec[32] ^ carry_vec[32] ^ carry);
    wire less = !op[5] && a[31] != b[31] ? a[31] : borrow;
    wire equal = sum == 0;
    logic comparison;
    always_comb begin
        case (op[2:0])
            3'd0: comparison = equal;
            3'd1: comparison = !equal;
            3'd2: comparison = less;
            3'd3: comparison = less || equal;
            3'd4: comparison = !(less || equal);
            3'd5: comparison = !less;
            default: comparison = less;
        endcase
    end
    wire minmax = compare_op && op[2:1] == 3;
    wire [31:0] shifted;
    VX_ucc_shift_jam #(
        .W (32),
        .SW (6)
    ) shifter (
        .data_in  (a),
        .amount   ({1'b0, b[4:0]}),
        .left     (op == 8'h30),
        .fill     (op == 8'h32 && a[31]),
        .data_out (shifted),
        `UNUSED_PIN (sticky)
    );
    wire [4:0] lz;
    wire nonzero;
    VX_lzc #(
        .N (32)
    ) leading_zeros (
        .data_in   (a),
        .data_out  (lz),
        .valid_out (nonzero)
    );
    wire [31:0] boolean_result;
    VX_ucc_boolean boolean_unit (
        .a         (a),
        .b         (b),
        .c         (c),
        .op        (op[2:0]),
        .immediate (immediate),
        .result    (boolean_result)
    );
    assign predicate = compare_op && comparison;
    assign result = op[7:4] == 5 ? boolean_result
                  : op == 8'h33 ? (nonzero ? 32'(lz) : 32'd32)
                  : op[7:4] == 3 ? shifted
                  : op == 8'h14 ? product[31:0]
                  : minmax ? ((less ^ op[0]) ? a : b)
                  : compare_op ? {31'd0, comparison} : sum;
endmodule
