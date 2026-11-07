module VX_ucc_shift_jam #(
    parameter W = 80,
    parameter SW = 10
) (
    input  wire [W-1:0]  data_in,
    input  wire [SW-1:0] amount,
    input  wire          left,
    input  wire          fill,
    output wire [W-1:0] data_out,
    output wire          sticky
);
    localparam LEVELS = $clog2(W);
    wire [LEVELS:0][W-1:0] stage;
    wire [LEVELS:0] lost;
    wire [W-1:0] shifted;
    wire over = amount >= SW'(W);
    assign lost[0] = 1'b0;
    for (genvar i = 0; i < W; ++i) begin : g_reverse
        assign stage[0][i] = left ? data_in[W-1-i] : data_in[i];
        assign shifted[i] = left ? stage[LEVELS][W-1-i] : stage[LEVELS][i];
    end
    for (genvar s = 0; s < LEVELS; ++s) begin : g_stage
        localparam D = 1 << s;
        assign stage[s+1] = amount[s] ? {{D{fill && !left}}, stage[s][W-1:D]} : stage[s];
        assign lost[s+1] = lost[s] | (amount[s] && (|stage[s][D-1:0]));
    end
    assign data_out = over ? {W{fill && !left}} : shifted;
    assign sticky = !left && (over ? (|data_in) : lost[LEVELS]);
endmodule
