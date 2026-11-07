module VX_partitioned_shifter #(
    parameter W = 128,
    parameter AW = $clog2(W) + 1
) (
    input  wire [W-1:0]      data_in,
    input  wire [3:0][AW-1:0] amount,
    input  wire [3:0]        fill,
    input  wire [1:0]        mode,
    input  wire              left,
    output wire [W-1:0]      data_out
);
    localparam Q = W / 4;
    localparam LEVELS = $clog2(W);
    wire [LEVELS:0][W-1:0] stage;
    wire [3:0][AW-1:0] lane_amount;
    wire [3:0] lane_fill;
    wire [W-1:0] shifted;

    // Reversal shares one right-shift network between both directions.
    for (genvar i = 0; i < W; ++i) begin : g_reverse
        assign stage[0][i] = left ? data_in[W-1-i] : data_in[i];
        assign data_out[i] = left ? shifted[W-1-i] : shifted[i];
    end
    for (genvar q = 0; q < 4; ++q) begin : g_control
        wire [AW-1:0] half_amount = left ? amount[((3-q)/2)*2] : amount[(q/2)*2];
        wire [AW-1:0] quarter_amount = left ? amount[3-q] : amount[q];
        assign lane_amount[q] = (mode == 0) ? amount[0]
                             : (mode == 1) ? half_amount : quarter_amount;
        assign lane_fill[q] = !left && ((mode == 0) ? fill[0]
                                         : (mode == 1) ? fill[(q/2)*2] : fill[q]);
        wire over = (mode == 0) ? (lane_amount[q] >= AW'(W))
                  : (mode == 1) ? (lane_amount[q] >= AW'(W/2))
                                : (lane_amount[q] >= AW'(Q));
        assign shifted[q*Q +: Q] = over ? {Q{lane_fill[q]}} : stage[LEVELS][q*Q +: Q];
    end
    for (genvar s = 0; s < LEVELS; ++s) begin : g_stage
        localparam D = 1 << s;
        for (genvar i = 0; i < W; ++i) begin : g_bit
            localparam LANE = i / Q;
            wire incoming;
            if (i + D >= W) begin : g_outside
                assign incoming = lane_fill[LANE];
            end else begin : g_inside
                wire blocked = ((i / Q != (i+D) / Q) && (mode >= 2))
                             || ((i / (W/2) != (i+D) / (W/2)) && (mode != 0));
                assign incoming = blocked ? lane_fill[LANE] : stage[s][i+D];
            end
            assign stage[s+1][i] = lane_amount[LANE][s] ? incoming : stage[s][i];
        end
    end
endmodule
