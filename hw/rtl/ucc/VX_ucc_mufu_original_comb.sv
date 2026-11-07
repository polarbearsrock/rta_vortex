module VX_ucc_mufu_original_comb (
    input  wire [31:0] a,
    input  wire [2:0] fn,
    output wire [31:0] result
);
    VX_mufu_pe #(.PIPELINED (0)) core (
        .clk (1'b0), .reset (1'b0), .enable (1'b1),
        .fn (fn), .dataa (a), .result (result)
    );
endmodule
