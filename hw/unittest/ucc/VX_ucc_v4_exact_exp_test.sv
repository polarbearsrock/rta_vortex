module VX_ucc_v4_exact_exp_test #(
    parameter W = 80,
    parameter CHUNK = 11,
    parameter FMA_CSA = 0,
    parameter DIRECT_NORM = 0,
    parameter EXP_CONST = 0,
    parameter FMA_ANCHORED = 0,
    parameter FMA_CROP = 0,
    parameter FMA_SEGMENTED = 0,
    parameter WINDOW_NORM = 0,
    parameter MUL_C_ALIGN = 0
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
    input  wire [7:0]         op,
    input  wire [1:0]         rm,
    input  wire [7:0]         immediate,
    output wire [31:0]        result,
    output wire [4:0]         flags,
    output wire               predicate,
    output wire [31:0]        reference_result
);
    VX_ucc_v4_exact_exp_comb #(
        .W     (W),
        .CHUNK (CHUNK),
        .FMA_CSA (FMA_CSA),
        .DIRECT_NORM (DIRECT_NORM),
        .EXP_CONST (EXP_CONST),
        .FMA_ANCHORED (FMA_ANCHORED),
        .FMA_CROP (FMA_CROP),
        .FMA_SEGMENTED (FMA_SEGMENTED),
        .WINDOW_NORM (WINDOW_NORM),
        .MUL_C_ALIGN (MUL_C_ALIGN)
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
        .immediate (immediate),
        .result  (result),
        .flags   (flags),
        .predicate (predicate)
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
