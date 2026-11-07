module VX_ucc_float_to_int #(
    parameter W = 80
) (
    input  wire [31:0]           a,
    input  wire                 unsigned_result,
    input  wire [1:0]           rm,
    output wire [W-1:0]         align_data,
    output wire signed [11:0]   align_distance,
    input  wire [W-1:0]         aligned,
    input  wire                 sticky,
    output wire [1:0][W-1:0]    operands,
    output wire [1:0]           negatives,
    input  wire [W-1:0]         sum,
    output wire [31:0]          result,
    output wire [4:0]           flags
);
    wire [7:0] e = a[30:23];
    wire sign = a[31];
    wire signed [11:0] exponent = e == 0 ? -12'sd126 : 12'(e) - 12'sd127;
    assign align_data = W'({(|e), a[22:0]});
    assign align_distance = 12'sd20 - exponent;
    wire [31:0] kept = aligned[34:3];
    wire guard_bit = aligned[2];
    wire tail = (|aligned[1:0]) || sticky;
    wire inexact = guard_bit || tail;
    wire increment = (rm == 0 && guard_bit && (tail || kept[0]))
                   || (rm == 2 && sign && inexact)
                   || (rm == 3 && !sign && inexact);
    assign operands[0] = sign ? ~W'(kept) : W'(kept);
    assign operands[1] = sign ? ~W'(increment) : W'(increment);
    assign negatives = {2{sign}};
    wire nan_input = (&e) && (|a[22:0]);
    wire invalid_unsigned = exponent >= 32 || (sign && (|sum));
    wire invalid_signed = exponent > 31
                       || (exponent == 31 && (!sign || sum != W'($signed(32'h80000000))));
    wire invalid = (&e) || (unsigned_result ? invalid_unsigned : invalid_signed);
    wire [31:0] saturated = nan_input ? 32'd0
                         : unsigned_result ? (sign ? 32'd0 : 32'hffffffff)
                         : sign ? 32'h80000000 : 32'h7fffffff;
    assign result = invalid ? saturated : sum[31:0];
    assign flags = {invalid, 3'd0, (inexact && !invalid)};
endmodule
