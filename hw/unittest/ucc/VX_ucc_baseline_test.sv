`include "VX_define.vh"

module VX_ucc_baseline_test (
    input  wire                clk,
    input  wire                reset,
    input  wire                enable,
    input  wire [4:0]          fmt,
    input  wire [63:0]         mask,
    input  wire [7:0][31:0]    a,
    input  wire [7:0][31:0]    b,
    input  wire [3:0][7:0]     scale_a,
    input  wire [3:0][7:0]     scale_b,
    input  wire [31:0]         c,
    output wire [31:0]         comb_result,
    output wire [31:0]         pipe_result
);
    VX_ucc_dpa16_comb comb (
        .fmt     (fmt),
        .mask    (mask),
        .a       (a),
        .b       (b),
        .scale_a (scale_a),
        .scale_b (scale_b),
        .c       (c),
        .result  (comb_result)
    );

    VX_tcu_fedp_tfr #(
        .N         (8),
        .SF        (4),
        .LANE_MASK (1),
        .LATENCY   (4),
        .USE_DSP   (0)
    ) piped (
        .clk      (clk),
        .reset    (reset),
        .enable   (enable),
        .vld_mask (mask),
        .fmt_s    (fmt),
        .fmt_d    (5'd0),
        .a_row    (a),
        .b_col    (b),
        .sf_a     (scale_a),
        .sf_b     (scale_b),
        .c_val    (c),
        .d_val    (pipe_result)
    );
endmodule
