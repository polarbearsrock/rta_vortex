`include "VX_define.vh"

module VX_ucc_partitioned_acc #(
    parameter N = 17
) (
    input  wire [N-1:0][63:0] operands,
    input  wire [N-1:0]      negatives,
    input  wire [N-1:0]      sticky_in,
    input  wire              full_product,
    output wire [63:0]      sum,
    output wire [31:0]      magnitude,
    output wire              sign,
    output wire              sticky_out
);
    wire [$clog2(N+1)-1:0] corrections;
    VX_popcount #(
        .N (N)
    ) popcount (
        .data_in  (negatives),
        .data_out (corrections)
    );
    wire [N:0][63:0] terms;
    assign terms[N-1:0] = operands;
    assign terms[N] = 64'(corrections);
    wire [63:0] sum_vec, carry_vec;
    VX_csa_tree #(
        .N (N+1),
        .W (64),
        .S (64)
    ) reduction (
        .operands (terms),
        .sum      (sum_vec),
        .carry    (carry_vec)
    );
    wire [31:0] low, high_or_negative;
    wire carry_low;
    VX_ks_adder #(
        .N (32),
        .BYPASS (`FORCE_BUILTIN_ADDER(32))
    ) low_adder (
        .cin   (1'b0),
        .dataa (sum_vec[31:0]),
        .datab (carry_vec[31:0]),
        .sum   (low),
        .cout  (carry_low)
    );
    // The DPA negative-sum adder becomes the high half of the integer adder.
    VX_ks_adder #(
        .N (32),
        .BYPASS (`FORCE_BUILTIN_ADDER(32))
    ) high_adder (
        .cin   (full_product ? carry_low : 1'b1),
        .dataa (full_product ? sum_vec[63:32] : ~sum_vec[31:0]),
        .datab (full_product ? carry_vec[63:32] : ~carry_vec[31:0]),
        .sum   (high_or_negative),
        `UNUSED_PIN (cout)
    );
    wire [31:0] negative_magnitude = high_or_negative + 32'd1;
    assign sum = {full_product ? high_or_negative : {32{low[31]}}, low};
    assign sign = low[31];
    assign magnitude = sign ? negative_magnitude : low;
    assign sticky_out = |sticky_in;
endmodule
