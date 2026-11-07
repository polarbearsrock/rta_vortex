`include "VX_define.vh"

module VX_ucc_segmented_acc #(
    parameter N = 17
) (
    input  wire [N-1:0][63:0] operands,
    input  wire [N-1:0] negatives,
    input  wire [N-1:0] sticky_in,
    output wire [63:0] sum,
    output wire [63:0] magnitude,
    output wire sign,
    output wire sticky_out
);
    wire [$clog2(N+1)-1:0] corrections;
    VX_popcount #(.N (N)) popcount (.data_in (negatives), .data_out (corrections));
    wire [N:0][63:0] terms = {64'(corrections), operands};
    wire [63:0] s, c;
    VX_csa_tree #(.N (N+1), .W (64), .S (64)) reduction (
        .operands (terms), .sum (s), .carry (c)
    );
    wire carry_low;
    VX_ks_adder #(.N (32), .BYPASS (`FORCE_BUILTIN_ADDER(32))) low_adder (
        .dataa (s[31:0]), .datab (c[31:0]), .cin (1'b0),
        .sum (sum[31:0]), .cout (carry_low)
    );
    VX_ks_adder #(.N (32), .BYPASS (`FORCE_BUILTIN_ADDER(32))) high_adder (
        .dataa (s[63:32]), .datab (c[63:32]), .cin (carry_low),
        .sum (sum[63:32]), `UNUSED_PIN (cout)
    );
    assign sign = sum[63];
    assign magnitude = (sum ^ {64{sign}}) + 64'(sign);
    assign sticky_out = |sticky_in;
endmodule
