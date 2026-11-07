`include "VX_define.vh"

module VX_ucc_v4_route_comb import VX_tcu_pkg::*; #(
    parameter W = 64,
    parameter CHUNK = 11,
    parameter SHARED_ALIGN = 1,
    parameter DIRECT_NORM = 1,
    parameter ONEHOT_ROUTE = 1
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
        .NATIVE_FP (1),
        .SHARED_ALIGN (SHARED_ALIGN),
        .DIRECT_NORM (DIRECT_NORM),
        .ONEHOT_ROUTE (ONEHOT_ROUTE),
        .SMALL_NATIVE (1),
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
