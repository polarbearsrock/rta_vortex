`include "VX_define.vh"

module VX_paired_shift_jam #(
    parameter LW = 26,
    parameter AW = 8
) (
    input  wire [2*LW-1:0]   data_in,
    input  wire [1:0][AW-1:0] amount,
    input  wire              joined,
    output wire [2*LW-1:0]   data_out,
    output wire [1:0]        sticky
);
    localparam W = 2 * LW;
    localparam LEVELS = $clog2(W);
    `STATIC_ASSERT (AW >= LEVELS, ("shift amount must cover the joined word"))
    wire [LEVELS:0][W-1:0] stage;
    wire [LEVELS:0][1:0] lost;
    assign stage[0] = data_in;
    assign lost[0] = '0;
    for (genvar s = 0; s < LEVELS; ++s) begin : g_stage
        localparam D = 1 << s;
        for (genvar i = 0; i < W; ++i) begin : g_bit
            localparam LANE = i / LW;
            wire control = joined ? amount[0][s] : amount[LANE][s];
            wire incoming;
            if (i+D >= W) begin : g_outside
                assign incoming = 1'b0;
            end else if (i/LW != (i+D)/LW) begin : g_boundary
                assign incoming = joined && stage[s][i+D];
            end else begin : g_inside
                assign incoming = stage[s][i+D];
            end
            assign stage[s+1][i] = control ? incoming : stage[s][i];
        end
        for (genvar q = 0; q < 2; ++q) begin : g_sticky
            localparam LOST_W = D < LW ? D : LW;
            wire lane_lost = |stage[s][q*LW +: LOST_W];
            wire full_lost = |stage[s][D-1:0];
            assign lost[s+1][q] = joined
                               ? ((q == 0) && (lost[s][0] || (amount[0][s] && full_lost)))
                               : (lost[s][q] || (amount[q][s] && lane_lost));
        end
    end
    for (genvar q = 0; q < 2; ++q) begin : g_output
        wire over = joined ? amount[0] >= AW'(W) : amount[q] >= AW'(LW);
        assign data_out[q*LW +: LW] = over ? '0 : stage[LEVELS][q*LW +: LW];
        assign sticky[q] = joined ? ((q == 0) && (over ? (|data_in) : lost[LEVELS][0]))
                                 : (over ? (|data_in[q*LW +: LW]) : lost[LEVELS][q]);
    end
endmodule
