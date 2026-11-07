module VX_ucc_mul_align #(
    parameter W = 64
) (
    input wire [23:0] significand,
    input wire signed [11:0] distance,
    output wire [2:0][10:0] mul_a,
    output wire [2:0][10:0] mul_b,
    input wire [2:0][21:0] products,
    output wire [W-1:0] aligned,
    output wire sticky
);
    wire [2:0] fine = -distance[2:0];
    wire [32:0] padded = {9'd0, significand};
    for (genvar i = 0; i < 3; ++i) begin : g_input
        assign mul_a[i] = padded[11*i +: 11];
        assign mul_b[i] = 11'd1 << fine;
    end
    wire [30:0] fine_result = 31'(products[0]) | (31'(products[1]) << 11) | (31'(products[2]) << 22);
    wire signed [12:0] coarse = 13'(distance) + 13'(fine);
    wire left = coarse < 0;
    wire [12:0] amount = left ? 13'(-coarse) : 13'(coarse);
    localparam BLOCKS = (W+7)/8;
    wire [BLOCKS-1:0][W-1:0] choices;
    wire [BLOCKS-1:0] lost;
    for (genvar i = 0; i < BLOCKS; ++i) begin : g_coarse
        assign choices[i] = left ? W'(fine_result) << (8*i) : W'(fine_result) >> (8*i);
        if (i == 0) begin : g_no_tail
            assign lost[i] = 1'b0;
        end else if (8*i >= 31) begin : g_all_tail
            assign lost[i] = |fine_result;
        end else begin : g_tail
            assign lost[i] = |fine_result[8*i-1:0];
        end
    end
    wire [$clog2(BLOCKS)-1:0] index = $clog2(BLOCKS)'(amount >> 3);
    wire over = amount >= 13'(W);
    assign aligned = over ? '0 : choices[index];
    assign sticky = !left && (over ? (|significand) : lost[index]);
endmodule
