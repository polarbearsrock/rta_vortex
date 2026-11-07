`include "VX_define.vh"

module VX_ucc_v4_csa_comb import VX_tcu_pkg::*; #(
    parameter W = 80,
    parameter CHUNK = 11,
    parameter FMA_CSA = 1,
    parameter DIRECT_NORM = 1
) (
    input  wire                dpa,
    input  wire [4:0]          fmt,
    input  wire [63:0]         mask,
    input  wire [7:0][31:0]    a_vec,
    input  wire [7:0][31:0]    b_vec,
    input  wire [3:0][7:0]     scale_a,
    input  wire [3:0][7:0]     scale_b,
    input  wire [31:0]         a,
    input  wire [31:0]         b,
    input  wire [31:0]         c,
    input  wire [7:0]          op,
    input  wire [1:0]          rm,
    input  wire [7:0]          immediate,
    output wire [31:0]         result,
    output wire [4:0]          flags,
    output wire                predicate
);
    VX_ucc_comb #(
        .W          (W),
        .CHUNK      (CHUNK),
        .FMA_CSA (FMA_CSA),
        .DIRECT_NORM (DIRECT_NORM),
        .ENABLE_INT (1),
        .ENABLE_AUX (1),
        .ENABLE_BOOL (1),
        .ENABLE_EX2 (1),
        .NATIVE_FP (0),
        .SHARED_ALIGN (0),
        .SMALL_NATIVE (0),
        .ENABLE_EXP (1)
    ) core (
        .dpa       (dpa),
        .fmt       (fmt),
        .mask      (mask),
        .a_vec     (a_vec),
        .b_vec     (b_vec),
        .scale_a   (scale_a),
        .scale_b   (scale_b),
        .a         (a),
        .b         (b),
        .c         (c),
        .op        (op),
        .rm        (rm),
        .immediate (immediate),
        .result    (result),
        .flags     (flags),
        .predicate (predicate)
    );
endmodule
