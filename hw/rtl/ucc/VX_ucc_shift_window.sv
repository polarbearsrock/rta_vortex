module VX_ucc_shift_window #(
    parameter W = 64,
    parameter SW = 12
) (
    input  wire [W-1:0] data_in,
    input  wire [SW-1:0] amount,
    input  wire left,
    input  wire fill,
    output wire [31:0] data_out,
    output wire sticky
);
    localparam BLOCKS = (W+7)/8;
    localparam PAD = BLOCKS*8;
    wire [31:0] reversed;
    for (genvar i = 0; i < 32; ++i) begin : g_reverse
        assign reversed[i] = data_in[31-i];
    end
    wire sign_fill = fill && !left;
    wire [PAD+38:0] extended = {{(PAD+39-W){sign_fill}}, left ? W'(reversed) : data_in};
    wire [BLOCKS-1:0][38:0] windows;
    wire [BLOCKS-1:0] lost;
    for (genvar i = 0; i < BLOCKS; ++i) begin : g_window
        assign windows[i] = extended[8*i +: 39];
        if (i == 0) begin : g_no_tail
            assign lost[i] = 1'b0;
        end else begin : g_tail
            assign lost[i] = |extended[8*i-1:0];
        end
    end
    wire over = amount >= SW'(left ? 32 : W);
    wire [$clog2(BLOCKS)-1:0] block_index = $clog2(BLOCKS)'(amount >> 3);
    wire [38:0] selected = over ? {39{sign_fill}} : windows[block_index];
    wire [38:0] fine = selected >> amount[2:0];
    wire [7:0] mask = (8'd1 << amount[2:0]) - 8'd1;
    assign sticky = !left && (over ? (|data_in) : lost[block_index] || (|(selected[7:0] & mask)));
    for (genvar i = 0; i < 32; ++i) begin : g_output
        assign data_out[i] = left ? fine[31-i] : fine[i];
    end
endmodule
