module VX_ucc_shift_shared (
    input  wire [127:0]   data_in,
    input  wire [3:0][7:0] amount,
    input  wire [3:0]     fill,
    input  wire [1:0]     mode,
    input  wire           left,
    output wire [127:0]   data_out
);
    VX_partitioned_shifter shift (
        .data_in  (data_in),
        .amount   (amount),
        .fill     (fill),
        .mode     (mode),
        .left     (left),
        .data_out (data_out)
    );
endmodule
