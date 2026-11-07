`include "VX_define.vh"

module VX_ucc_mul_reducer (
    input  wire                 reduce_mode,
    input  wire [2:0][10:0]     a,
    input  wire [2:0][10:0]     b,
    input  wire [8:0][21:0]     partials,
    output wire [2:0][21:0]     products
);
    function automatic integer count_at(integer level);
        integer n;
        n = 11;
        for (integer i = 0; i < level; ++i) begin
            n = (n / 3) * 2 + n % 3;
        end
        return n;
    endfunction
    wire [5:0][10:0][65:0] rows;
    for (genvar i = 0; i < 11; ++i) begin : g_input
        wire [65:0] native_row;
        for (genvar lane = 0; lane < 3; ++lane) begin : g_lane
            assign native_row[lane*22 +: 22] = (22'(a[lane]) << i) & {22{b[lane][i]}};
        end
        if (i < 9) begin : g_partial
            assign rows[0][i] = reduce_mode ? 66'(partials[i]) << (11*((i/3)+(i%3))) : native_row;
        end else begin : g_padding
            assign rows[0][i] = reduce_mode ? '0 : native_row;
        end
    end
    for (genvar level = 0; level < 5; ++level) begin : g_level
        localparam NI = count_at(level);
        localparam GROUPS = NI / 3;
        localparam NO = count_at(level+1);
        for (genvar j = 0; j < GROUPS; ++j) begin : g_compress
            wire [65:0] x = rows[level][3*j];
            wire [65:0] y = rows[level][3*j+1];
            wire [65:0] z = rows[level][3*j+2];
            wire [65:0] carry = ((x & y) | (x & z) | (y & z)) << 1;
            assign rows[level+1][2*j] = x ^ y ^ z;
            for (genvar bitno = 0; bitno < 66; ++bitno) begin : g_boundary
                assign rows[level+1][2*j+1][bitno] = ((bitno == 22 || bitno == 44) && !reduce_mode) ? 1'b0 : carry[bitno];
            end
        end
        for (genvar j = 0; j < NI % 3; ++j) begin : g_pass
            assign rows[level+1][2*GROUPS+j] = rows[level][3*GROUPS+j];
        end
        for (genvar j = NO; j < 11; ++j) begin : g_unused
            assign rows[level+1][j] = '0;
        end
    end
    wire [3:0] carry_chain;
    assign carry_chain[0] = 1'b0;
    for (genvar lane = 0; lane < 3; ++lane) begin : g_adder
        VX_ks_adder #(.N (22), .BYPASS (`FORCE_BUILTIN_ADDER(22))) adder (
            .dataa (rows[5][0][lane*22 +: 22]),
            .datab (rows[5][1][lane*22 +: 22]),
            .cin (reduce_mode && carry_chain[lane]),
            .sum (products[lane]), .cout (carry_chain[lane+1])
        );
    end
    `UNUSED_VAR (carry_chain[3])
endmodule
