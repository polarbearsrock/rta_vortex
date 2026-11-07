`include "VX_define.vh"

module VX_ucc_ex2_standalone (
    input  wire [31:0] a,
    input  wire [7:0]  op,
    output wire [31:0] result,
    output wire [4:0]  flags,
    output wire        predicate
);
    `UNUSED_VAR (op)
    VX_ucc_mufu_standalone core (
        .a (a), .op (8'h60), .result (result), .flags (flags), .predicate (predicate)
    );
endmodule
