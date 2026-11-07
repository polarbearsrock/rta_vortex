`include "VX_define.vh"

module VX_ucc_stream #(
    parameter EXACT_FP = 0,
    parameter FMA_STYLE = 3,
    parameter EXP_STYLE = 1,
    parameter SHARED_ALIGN = 0,
    parameter WINDOW_NORM = EXACT_FP,
    parameter TAG_W = 8
) (
    input  wire clk,
    input  wire rst_n,
    input  wire valid_i,
    output wire ready_o,
    input  wire dpa_i,
    input  wire [4:0] fmt_i,
    input  wire [63:0] mask_i,
    input  wire [7:0][31:0] a_vec_i,
    input  wire [7:0][31:0] b_vec_i,
    input  wire [3:0][7:0] scale_a_i,
    input  wire [3:0][7:0] scale_b_i,
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [31:0] c_i,
    input  wire [7:0] opcode_i,
    input  wire [1:0] rounding_mode_i,
    input  wire [7:0] immediate_i,
    input  wire [TAG_W-1:0] tag_i,
    input  wire ready_i,
    output logic valid_o,
    output logic [31:0] result_o,
    output logic [4:0] flags_o,
    output logic predicate_o,
    output logic [TAG_W-1:0] tag_o
);
    `STATIC_ASSERT (FMA_STYLE >= 0 && FMA_STYLE <= 5, ("unsupported FMA style"))
    `STATIC_ASSERT (EXP_STYLE >= 0 && EXP_STYLE <= 2, ("unsupported exponential style"))
    wire [31:0] result;
    wire [4:0] flags;
    wire predicate;
    VX_ucc_comb #(
        .W (EXACT_FP && FMA_STYLE < 4 ? 80 : 64), .CHUNK (11),
        .ENABLE_INT (1), .ENABLE_AUX (1), .ENABLE_BOOL (1),
        .ENABLE_EX2 (1), .ENABLE_EXP (1),
        .NATIVE_FP (!EXACT_FP), .SHARED_ALIGN (!EXACT_FP && SHARED_ALIGN), .SMALL_NATIVE (!EXACT_FP),
        .EXP_CONST (EXP_STYLE == 1), .COMPACT_EXP (EXP_STYLE == 2),
        .DIRECT_NORM (EXACT_FP), .FMA_CSA (EXACT_FP && FMA_STYLE == 1),
        .FMA_ANCHORED (EXACT_FP && (FMA_STYLE == 2 || FMA_STYLE == 3)), .FMA_CROP (EXACT_FP && FMA_STYLE == 3),
        .FMA_SEGMENTED (EXACT_FP && FMA_STYLE >= 4),
        .MUL_C_ALIGN (EXACT_FP && FMA_STYLE == 5),
        .WINDOW_NORM (WINDOW_NORM || (EXACT_FP && FMA_STYLE >= 4))
    ) core (
        .dpa (dpa_i), .fmt (fmt_i), .mask (mask_i),
        .a_vec (a_vec_i), .b_vec (b_vec_i), .scale_a (scale_a_i), .scale_b (scale_b_i),
        .a (a_i), .b (b_i), .c (c_i), .op (opcode_i),
        .rm (rounding_mode_i), .immediate (immediate_i),
        .result (result), .flags (flags), .predicate (predicate)
    );
    assign ready_o = rst_n && (!valid_o || ready_i);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            valid_o <= 1'b0;
        end else if (ready_o) begin
            valid_o <= valid_i;
            if (valid_i) begin
                result_o <= result;
                flags_o <= flags;
                predicate_o <= predicate;
                tag_o <= tag_i;
            end
        end
    end
endmodule
