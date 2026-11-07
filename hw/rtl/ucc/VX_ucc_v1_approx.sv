module VX_ucc_v1_approx (
    input  wire              dpa,
    input  wire [4:0]         fmt,
    input  wire [63:0]        mask,
    input  wire [7:0][31:0]   a_vec,
    input  wire [7:0][31:0]   b_vec,
    input  wire [3:0][7:0]    scale_a,
    input  wire [3:0][7:0]    scale_b,
    input  wire [31:0]        a,
    input  wire [31:0]        b,
    input  wire [31:0]        c,
    input  wire [1:0]         op,
    input  wire [1:0]         rm,
    output wire [31:0]        result,
    output wire [4:0]         flags
);
    VX_ucc_v1_comb #(
        .W (32)
    ) core (
        .dpa     (dpa),
        .fmt     (fmt),
        .mask    (mask),
        .a_vec   (a_vec),
        .b_vec   (b_vec),
        .scale_a (scale_a),
        .scale_b (scale_b),
        .a       (a),
        .b       (b),
        .c       (c),
        .op      (op),
        .rm      (rm),
        .result  (result),
        .flags   (flags)
    );
endmodule
