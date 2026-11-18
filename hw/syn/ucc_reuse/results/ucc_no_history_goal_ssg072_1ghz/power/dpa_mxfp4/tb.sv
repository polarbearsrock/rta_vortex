`timescale 1ps/1ps
module tb;
  logic clk = 0, rst_ni = 0, valid = 0;
  logic [6:0] op = 0;
  logic [2:0] rm = 0;
  logic [287:0] a = 0, b = 0;
  logic [63:0] c = 0, d;
  logic nv, nk;
  logic [6:0] nop;
  logic [2:0] nrm;
  logic [287:0] na, nb;
  logic [63:0] nc, nd;
  int fd, cycles = 0, checked = 0;
  string vectors, vcd;
  logic mode = 0;
  wire out_valid;
  initial if (!$value$plusargs("mode=%d", mode)) $fatal(1, "Missing mode");
  ucc_b32_pipe5 dut (.clk_i(clk), .rst_ni, .valid_i(valid), .op_i(op), .rm_i(rm),
    .dpa_mode_i(mode), .valid_o(out_valid),
    .a_i(a[255:0]), .b_i(b[255:0]), .sa_i(a[287:256]), .sb_i(b[287:256]), .c_i(c), .d_o(d));
  always #500 clk = ~clk;
  initial begin
    if (!$value$plusargs("vectors=%s", vectors)) $fatal(1, "Missing vectors");
    if (!$value$plusargs("vcd=%s", vcd)) $fatal(1, "Missing VCD path");
    fd = $fopen(vectors, "r");
    if (!fd) $fatal(1, "Cannot read vectors");
    $dumpfile(vcd);
    $dumpvars(0, dut);
    repeat (8) @(negedge clk);
    rst_ni = 1;
    while ($fscanf(fd, "%h %h %h %h %h %h %h %h\n", nv, nop, nrm, na, nb, nc, nk, nd) == 8) begin
      @(negedge clk);
      if (cycles == 100) $display("WINDOW_START %0t", $time);
      if (cycles == 1100) $display("WINDOW_END %0t", $time);
      if (out_valid !== nk) $fatal(1, "valid mismatch cycle=%0d", cycles);
      if (nk) begin
        if (d !== nd) $fatal(1, "Mismatch cycle=%0d got=%016h expected=%016h", cycles, d, nd);
        checked++;
      end
      valid = nv; op = nop; rm = nrm; a = na; b = nb; c = nc;
      cycles++;
    end
    $display("ENERGY_SIM_DONE cycles=%0d checked=%0d mismatches=0", cycles, checked);
    $finish;
  end
endmodule
