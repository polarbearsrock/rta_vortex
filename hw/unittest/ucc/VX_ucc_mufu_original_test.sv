module VX_ucc_mufu_original_test (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [31:0] a,
    input wire [2:0] fn,
    output wire [31:0] comb_result,
    output wire [31:0] pipe_result
);
    VX_ucc_mufu_original_comb combinational (
        .a (a), .fn (fn), .result (comb_result)
    );
    VX_mufu_pe pipeline (
        .clk (clk), .reset (reset), .enable (enable),
        .fn (fn), .dataa (a), .result (pipe_result)
    );
endmodule
