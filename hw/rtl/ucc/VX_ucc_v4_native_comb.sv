`include "VX_define.vh"

module VX_ucc_v4_native_comb import VX_tcu_pkg::*; #(
    parameter W = 65,
    parameter CHUNK = 11
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
        .ENABLE_INT (1),
        .ENABLE_AUX (1),
        .ENABLE_BOOL (1),
        .ENABLE_EX2 (1),
        .NATIVE_FP (1)
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
