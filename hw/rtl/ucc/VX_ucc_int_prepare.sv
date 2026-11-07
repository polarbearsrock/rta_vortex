`include "VX_define.vh"

module VX_ucc_int_prepare #(
    parameter W = 80
) (
    input  wire [31:0]            a,
    input  wire [31:0]            b,
    input  wire [7:0]             op,
    output wire [8:0][10:0]       mul_a,
    output wire [8:0][10:0]       mul_b,
    input  wire [8:0][21:0]       products,
    output wire [16:0][W-1:0]     operands,
    output wire [16:0]            negatives,
    input  wire [W-1:0]           sum,
    output wire [31:0]            result,
    output wire                   predicate
);
    `STATIC_ASSERT (W >= 64, ("integer products require at least 64 accumulator bits"))
    wire multiply = op >= 8'h14 && op <= 8'h17;
    wire negate = op == 8'h12 || (op == 8'h13 && a[31]);
    wire absolute = op == 8'h13;
    wire passthrough = op >= 8'h30;
    wire subtract = op == 8'h11 || op >= 8'h18 || (op >= 8'h08 && op <= 8'h0f);
    wire sign_extend = op == 8'h32 || op == 8'h40;
    wire signed_a = op == 8'h16 || op == 8'h17;
    wire signed_b = op == 8'h16;
    wire correction_a = signed_a && a[31];
    wire correction_b = signed_b && b[31];
    wire [32:0] xa = {1'b0, a};
    wire [32:0] xb = {1'b0, b};

    for (genvar i = 0; i < 17; ++i) begin : g_operand
        if (i < 9) begin : g_product
            assign mul_a[i] = xa[(i/3)*11 +: 11];
            assign mul_b[i] = xb[(i%3)*11 +: 11];
            wire [W-1:0] partial = W'(products[i]) << (11*((i/3)+(i%3)));
            if (i == 0) begin : g_first
                assign operands[i] = multiply ? partial : negate ? ~W'(a)
                                   : sign_extend ? W'($signed(a)) : W'(a);
                assign negatives[i] = !multiply && negate;
            end else if (i == 1) begin : g_second
                assign operands[i] = multiply ? partial : (negate || absolute || passthrough) ? '0
                                   : subtract ? ~W'(b) : W'(b);
                assign negatives[i] = !multiply && subtract && !(negate || absolute || passthrough);
            end else begin : g_remaining
                assign operands[i] = multiply ? partial : '0;
                assign negatives[i] = 1'b0;
            end
        end else if (i == 9) begin : g_signed_a
            assign operands[i] = multiply && correction_a ? ~(W'(b) << 32) : '0;
            assign negatives[i] = multiply && correction_a;
        end else if (i == 10) begin : g_signed_b
            assign operands[i] = multiply && correction_b ? ~(W'(a) << 32) : '0;
            assign negatives[i] = multiply && correction_b;
        end else begin : g_zero
            assign operands[i] = '0;
            assign negatives[i] = 1'b0;
        end
    end
    wire equal = sum[31:0] == 0;
    wire unsigned_compare = op[5];
    wire less = !unsigned_compare && (a[31] != b[31]) ? a[31] : sum[32];
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
    wire compare_op = op[3] && (op[2:0] <= 5);
    wire minmax = op[3] && (op[2:1] == 3);
    wire high_product = multiply && op != 8'h14;
    assign predicate = compare_op ? comparison : minmax && less;
    assign result = compare_op ? {31'd0, comparison}
                  : minmax ? ((less ^ op[0]) ? a : b)
                  : high_product ? sum[63:32] : sum[31:0];
    if (W > 64) begin : g_unused_high
        `UNUSED_VAR (sum[W-1:64])
    end
endmodule
