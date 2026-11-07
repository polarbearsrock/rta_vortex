module VX_ucc_fpu_standalone #(
    parameter W = 80
) (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [7:0]  op,
    input  wire [1:0]  rm,
    output wire [31:0] result,
    output wire [4:0]  flags,
    output wire        predicate
);
    VX_ucc_fma_standalone #(.W (W), .ENABLE_AUX (1)) core (
        .a (a), .b (b), .c (c), .op (op), .rm (rm),
        .result (result), .flags (flags), .predicate (predicate)
    );
endmodule
