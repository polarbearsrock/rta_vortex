`include "VX_define.vh"

module VX_ucc_coeff_bank import VX_ucc_coeff_pkg::*; #(
    parameter PORTS = 1,
    parameter STYLE = 0
) (
    input  wire [PORTS*6-1:0] indices,
    output wire [PORTS*79-1:0] coefficients
);
    `STATIC_ASSERT (PORTS > 0, ("coefficient bank needs at least one read port"))
    `STATIC_ASSERT (STYLE >= 0 && STYLE <= 2, ("unsupported coefficient bank style"))
    if (STYLE == 0) begin : g_replicated
        for (genvar portno = 0; portno < PORTS; ++portno) begin : g_port
            VX_mufu_rom #(.REGISTERED (0)) rom (
                .clk (1'b0), .enable (1'b1), .tbl (3'd2),
                .idx ({1'b0, indices[6*portno +: 6]}),
                .a0 (coefficients[79*portno+47 +: 32]),
                .a1 (coefficients[79*portno+20 +: 27]),
                .a2 (coefficients[79*portno +: 20])
            );
        end
    end else begin : g_shared
        wire [63:0][71:0] words;
        for (genvar rowno = 0; rowno < 64; ++rowno) begin : g_word
            assign words[rowno] = EX2_WORDS[rowno*72 +: 72];
        end
        for (genvar portno = 0; portno < PORTS; ++portno) begin : g_port
            wire [71:0] row;
            if (STYLE == 1) begin : g_array
                assign row = words[indices[6*portno +: 6]];
            end else begin : g_plane
                wire [63:0] selected;
                for (genvar rowno = 0; rowno < 64; ++rowno) begin : g_decode
                    assign selected[rowno] = indices[6*portno +: 6] == 6'(rowno);
                end
                for (genvar bitno = 0; bitno < 72; ++bitno) begin : g_bit
                    wire [63:0] plane;
                    for (genvar rowno = 0; rowno < 64; ++rowno) begin : g_row
                        assign plane[rowno] = words[rowno][bitno];
                    end
                    assign row[bitno] = |(selected & plane);
                end
            end
            assign coefficients[79*portno+47 +: 32] = 32'({row[71:43], 2'b0});
            assign coefficients[79*portno+20 +: 27] = 27'($signed({row[42:19], 2'b0}));
            assign coefficients[79*portno +: 20] = {row[18:0], 1'b0};
        end
    end
endmodule
