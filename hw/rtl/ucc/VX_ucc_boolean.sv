module VX_ucc_boolean (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [31:0] c,
    input  wire [7:0]  immediate,
    input  wire [2:0]  op,
    output logic [31:0] result
);
    wire [31:0] lop3;
    for (genvar i = 0; i < 32; ++i) begin : g_lop3
        assign lop3[i] = immediate[{a[i], b[i], c[i]}];
    end
    always_comb begin
        case (op)
            3'd0: result = a & b;
            3'd1: result = a | b;
            3'd2: result = a ^ b;
            3'd3: result = ~a;
            3'd4: result = lop3;
            3'd5: result = c[0] ? a : b;
            3'd6: result = a;
            default: result = '0;
        endcase
    end
endmodule
