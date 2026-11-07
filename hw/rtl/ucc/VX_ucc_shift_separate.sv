module VX_ucc_shift_separate (
    input  wire [127:0]   data_in,
    input  wire [3:0][7:0] amount,
    input  wire [3:0]     fill,
    input  wire [1:0]     mode,
    input  wire           left,
    output wire [127:0]   data_out
);
    wire [127:0] full_result, half_result, quarter_result;
    assign full_result = left ? (data_in << amount[0])
                             : 128'($signed({fill[0], data_in}) >>> amount[0]);
    for (genvar h = 0; h < 2; ++h) begin : g_half
        assign half_result[h*64 +: 64] = left ? (data_in[h*64 +: 64] << amount[2*h])
            : 64'($signed({fill[2*h], data_in[h*64 +: 64]}) >>> amount[2*h]);
    end
    for (genvar q = 0; q < 4; ++q) begin : g_quarter
        assign quarter_result[q*32 +: 32] = left ? (data_in[q*32 +: 32] << amount[q])
            : 32'($signed({fill[q], data_in[q*32 +: 32]}) >>> amount[q]);
    end
    assign data_out = (mode == 0) ? full_result : (mode == 1) ? half_result : quarter_result;
endmodule
