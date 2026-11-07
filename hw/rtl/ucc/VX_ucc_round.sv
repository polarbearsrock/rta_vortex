`include "VX_define.vh"

module VX_ucc_round #(
    parameter W = 80,
    parameter DIRECT_DISTANCE = 0,
    parameter WINDOW_SHIFT = 0
) (
    input  wire [W-1:0]       magnitude,
    input  wire signed [11:0] base_exp,
    input  wire               sign,
    input  wire [1:0]         rm,
    input  wire               sticky_in,
    input  wire               dpa,
    input  wire               shift_mode,
    input  wire               shift_left,
    input  wire               shift_signed,
    input  wire [4:0]         shift_count,
    output wire [31:0]        shift_result,
    output wire [31:0]        clz_result,
    output wire [31:0]        result,
    output wire [4:0]         flags
);
    wire [$clog2(W)-1:0] lz;
    wire nonzero;
    VX_lzc #(
        .N (W)
    ) lzc (
        .data_in   (magnitude),
        .data_out  (lz),
        .valid_out (nonzero)
    );
    wire signed [11:0] exponent = base_exp + 12'(W-1) - 12'(lz);
    wire subnormal = !dpa && (exponent < -12'sd126);
    wire signed [11:0] quantum = subnormal ? -12'sd149 : exponent - 12'sd23;
    wire signed [11:0] distance = DIRECT_DISTANCE
                               ? (subnormal ? -12'sd152 - base_exp : 12'(W-27) - 12'(lz))
                               : quantum - base_exp - 12'sd3;
    wire left = shift_mode ? shift_left : distance < 0;
    wire [11:0] shift_amount = shift_mode ? 12'(shift_count)
                            : left ? 12'(-distance) : 12'(distance);
    wire [31:0] shifted;
    wire shift_sticky;
    if (WINDOW_SHIFT) begin : g_window
        VX_ucc_shift_window #(.W (W), .SW (12)) shifter (
            .data_in (magnitude), .amount (shift_amount), .left (left),
            .fill (shift_mode && shift_signed), .data_out (shifted), .sticky (shift_sticky)
        );
    end else begin : g_full_shift
        wire [W-1:0] full_shifted;
        VX_ucc_shift_jam #(.W (W), .SW (12)) shifter (
            .data_in (magnitude), .amount (shift_amount), .left (left),
            .fill (shift_mode && shift_signed), .data_out (full_shifted), .sticky (shift_sticky)
        );
        assign shifted = full_shifted[31:0];
        if (W > 32) begin : g_unused
            `UNUSED_VAR (full_shifted[W-1:32])
        end
    end
    assign shift_result = shifted[31:0];
    assign clz_result = nonzero ? 32'(lz) - 32'(W-32) : 32'd32;
    wire [23:0] kept = shifted[26:3];
    wire guard_bit = shifted[2];
    wire round_bit = shifted[1];
    wire tail = shifted[0] | shift_sticky | sticky_in;
    wire inexact = guard_bit | round_bit | tail;
    wire increment = ((rm == 0) && guard_bit && (round_bit || tail || kept[0]))
                   || ((rm == 2) && sign && inexact)
                   || ((rm == 3) && !sign && inexact);
    wire [24:0] rounded = {1'b0, kept} + 25'(increment);
    wire [23:0] significand = rounded[24] ? rounded[24:1] : rounded[23:0];
    wire signed [11:0] out_exp = quantum + 12'sd150 + 12'(rounded[24]);
    wire overflow = out_exp >= 255;
    wire to_inf = (rm == 0) || ((rm == 2) && sign) || ((rm == 3) && !sign);

    // At exponent -127, unbounded-precision rounding retains one more bit
    // than subnormal encoding; inspect that bit before testing tininess.
    wire ub_inexact = round_bit | tail;
    wire ub_increment = ((rm == 0) && round_bit && (tail || guard_bit))
                      || ((rm == 2) && sign && ub_inexact)
                      || ((rm == 3) && !sign && ub_inexact);
    wire [24:0] ub_rounded = {1'b0, kept[22:0], guard_bit} + 25'(ub_increment);
    wire tiny = (exponent < -127) || ((exponent == -127) && !ub_rounded[24]);
    wire [7:0] packed_exp = significand[23] ? 8'(out_exp) : 8'd0;
    wire [31:0] finite_result = {sign, packed_exp, significand[22:0]};
    wire [31:0] overflow_result = {sign, (to_inf ? 31'h7f800000 : 31'h7f7fffff)};
    wire flush = dpa && out_exp <= 0;
    assign result = !nonzero || flush ? {sign, 31'd0}
                  : overflow ? overflow_result : finite_result;
    assign flags = dpa || !nonzero ? 5'd0 : {2'b00, overflow, (tiny && inexact), (inexact || overflow)};
endmodule
