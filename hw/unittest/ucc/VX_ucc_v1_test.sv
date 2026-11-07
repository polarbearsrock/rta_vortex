module VX_ucc_v1_test #(
    parameter W = 80,
    parameter CHUNK = 11
) (
    input  wire               dpa,
    input  wire [4:0]         fmt,
    input  wire [63:0]        mask,
    input  wire [7:0][31:0]   a_vec,
    input  wire [7:0][31:0]   b_vec,
    input  wire [3:0][7:0]    scale_a,
    input  wire [3:0][7:0]    scale_b,
    input  wire [31:0]        a,
    input  wire [31:0]        b,
    input  wire [31:0]        c,
    input  wire [1:0]         op,
    input  wire [1:0]         rm,
    output wire [31:0]        result,
    output wire [4:0]         flags,
    output wire [31:0]        reference_result
);
    VX_ucc_v1_comb #(
        .W     (W),
        .CHUNK (CHUNK)
    ) unified (
        .dpa     (dpa),
        .fmt     (fmt),
        .mask    (mask),
        .a_vec   (a_vec),
        .b_vec   (b_vec),
        .scale_a (scale_a),
        .scale_b (scale_b),
        .a       (a),
        .b       (b),
        .c       (c),
        .op      (op),
        .rm      (rm),
        .result  (result),
        .flags   (flags)
    );
    VX_ucc_dpa16_comb baseline (
        .fmt     (fmt),
        .mask    (mask),
        .a       (a_vec),
        .b       (b_vec),
        .scale_a (scale_a),
        .scale_b (scale_b),
        .c       (c),
        .result  (reference_result)
    );
endmodule
