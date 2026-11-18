`timescale 1ns/1ps
`ifndef SFU_LATENCY
`define SFU_LATENCY 6
`endif
module b32_schedule_tb;
  localparam integer SFU_LATENCY = `SFU_LATENCY;
  localparam integer MAX_LATENCY = (SFU_LATENCY > 5) ? SFU_LATENCY : 5;
  logic clk_i=0, rst_ni=0, valid_i=0, dpa_mode_i=0;
  logic [255:0] a_i=0, b_i=0;
  logic [31:0] sa_i=0, sb_i=0;
  logic [63:0] c_i=0, expected=0;
  logic [6:0] op_i=0;
  logic [2:0] rm_i=0;
  wire [63:0] d_o, comb_result;
  wire valid_o;
  logic [63:0] due_data[MAX_LATENCY];
  logic [MAX_LATENCY-1:0] due_valid='0;
  logic [MAX_LATENCY-1:0] sfu_history='0, normal_history='0, mul4_history='0;
  logic [287:0] full_a, full_b;
  logic [6:0] next_op;
  logic [2:0] next_rm;
  logic [63:0] next_c, next_expected;
  integer normal_after_sfu_mask=0, sfu_after_normal_mask=0;
  integer fd, n, issued=0, checks=0, cycles=0, mode_changes=0, reservation_bubbles=0;
  integer normal_run=0, sfu_run=0, max_normal_run=0, max_sfu_run=0;
  integer int2_run=0, max_int2_run=0, mul4_run=0, max_mul4_run=0;
  logic [287:0] mul_a[32], mul_b[32];
  logic [63:0] mul_c[32], mul_expected[32];
  logic [31:0] mul_seen='0;
  logic [2:0] mul_rm[32];
  logic [287:0] sfu_a[7], sfu_b[7], fma_a, fma_b;
  logic [63:0] sfu_c[7], sfu_expected[7], fma_c, fma_expected;
  logic [2:0] sfu_rm[7], fma_rm;
  logic [6:0] sfu_seen='0;
  logic fma_seen=0;
  ucc_b32_pipe5 dut(.*);
  ucc_lane reference_comb(.a_i, .b_i, .sa_i, .sb_i, .c_i, .valid_i, .dpa_mode_i,
                          .op_i, .rm_i, .d_o(comb_result));

  function automatic logic is_sfu(logic [6:0] op);
    return op[6:3] == 4'hf && op[2:0] != 3'd7;
  endfunction

  function automatic logic is_int2(logic [6:0] op);
    return op[6:1] == 6'd0;
  endfunction

  function automatic logic is_mul4(logic [6:0] op);
    return op[6:5] == 2'b01;
  endfunction

  function automatic logic reservation_conflict(logic [6:0] op);
    logic conflict;
    conflict = 0;
    for (integer delta=1; delta<=MAX_LATENCY; delta++) begin
      if (is_sfu(op)) conflict |= sfu_after_normal_mask[delta] && normal_history[delta-1];
      else conflict |= normal_after_sfu_mask[delta] && sfu_history[delta-1];
    end
    if (is_int2(op)) conflict = normal_history[1] || normal_history[2] ||
                                 mul4_history[1] || sfu_history[2] || sfu_history[3];
    if (is_mul4(op)) conflict = normal_history[0] || sfu_history[0] || sfu_history[1];
    return conflict;
  endfunction

  task automatic tick;
    integer latency;
    #4;
    if (!rst_ni) begin
      due_valid='0; sfu_history='0; normal_history='0; mul4_history='0;
    end else begin
      for (integer j=0; j<MAX_LATENCY-1; j++) due_data[j]=due_data[j+1];
      due_valid=due_valid >> 1;
      if (valid_i) begin
        if (reservation_conflict(op_i)) $fatal(1,"test dispatcher violated reservation");
        if (!is_sfu(op_i) && comb_result !== expected)
          $fatal(1,"reference/vector mismatch op=%h got=%h expected=%h",op_i,comb_result,expected);
        latency=is_int2(op_i) ? 2 : is_mul4(op_i) ? 4 : is_sfu(op_i) ? SFU_LATENCY : 5;
        if (due_valid[latency-1]) $fatal(1,"output reservation collision");
        due_data[latency-1]=expected;
        due_valid[latency-1]=1;
      end
      sfu_history={sfu_history[MAX_LATENCY-2:0],valid_i && is_sfu(op_i)};
      normal_history={normal_history[MAX_LATENCY-2:0],valid_i && !is_sfu(op_i) && !is_int2(op_i) && !is_mul4(op_i)};
      mul4_history={mul4_history[MAX_LATENCY-2:0],valid_i && is_mul4(op_i)};
    end
    normal_run=(rst_ni && valid_i && !is_sfu(op_i) && !is_int2(op_i) && !is_mul4(op_i)) ? normal_run+1 : 0;
    mul4_run=(rst_ni && valid_i && is_mul4(op_i)) ? mul4_run+1 : 0;
    if (mul4_run>max_mul4_run) max_mul4_run=mul4_run;
    int2_run=(rst_ni && valid_i && is_int2(op_i)) ? int2_run+1 : 0;
    if (int2_run>max_int2_run) max_int2_run=int2_run;
    sfu_run=(rst_ni && valid_i && is_sfu(op_i)) ? sfu_run+1 : 0;
    if (normal_run>max_normal_run) max_normal_run=normal_run;
    if (sfu_run>max_sfu_run) max_sfu_run=sfu_run;
    clk_i=1; #1;
    if (valid_o !== due_valid[0]) $fatal(1,"valid mismatch cycle=%0d",cycles);
    if (valid_o) begin
      if (d_o !== due_data[0])
        $fatal(1,"schedule mismatch cycle=%0d check=%0d got=%h expected=%h",cycles,checks,d_o,due_data[0]);
      checks++;
    end
    #4; clk_i=0; #1; cycles++;
  endtask

  task automatic drain;
    valid_i=0;
    repeat(MAX_LATENCY+1) tick();
    if (due_valid != 0) $fatal(1,"drain failed");
  endtask


  integer reset_cases=0, reset_width;
  initial begin
    if (!$value$plusargs("NORMAL_AFTER_SFU_MASK=%d",normal_after_sfu_mask)) $fatal(1,"missing mask");
    if (!$value$plusargs("SFU_AFTER_NORMAL_MASK=%d",sfu_after_normal_mask)) $fatal(1,"missing mask");
    repeat(2) tick(); rst_ni=1;
    fd=$fopen("pairs.txt","r");
    if (!fd) $fatal(1,"missing pairs");
    while (!$feof(fd)) begin
      n=$fscanf(fd,"%h %h %h %h %h %h",next_op,next_rm,full_a,full_b,next_c,next_expected);
      if(n==6) begin
        drain(); dpa_mode_i=(next_op[6:3]==4'b1011);
        {sa_i,a_i}=full_a; {sb_i,b_i}=full_b; c_i=next_c;
        op_i=next_op; rm_i=next_rm; expected=next_expected; valid_i=1;
        repeat(8) begin tick(); issued++; end
        // Flush a live pipeline, not an already-idle bank. Vary reset length.
        rst_ni=0; valid_i=0; reset_width=1+(reset_cases%2);
        repeat(reset_width) tick();
        n=$fscanf(fd,"%h %h %h %h %h %h",next_op,next_rm,full_a,full_b,next_c,next_expected);
        if(n!=6) $fatal(1,"incomplete pair");
        dpa_mode_i=(next_op[6:3]==4'b1011);
        {sa_i,a_i}=full_a; {sb_i,b_i}=full_b; c_i=next_c;
        op_i=next_op; rm_i=next_rm; expected=next_expected;
        rst_ni=1; valid_i=1; tick(); issued++;
        drain(); reset_cases++;
      end else if(n!=-1) $fatal(1,"malformed pair");
    end
    if(reset_cases!=2560) $fatal(1,"wrong reset coverage %0d",reset_cases);
    $display("RESET_ENTRY_PASS checks=%0d reset_cases=%0d cycles=%0d",checks,reset_cases,cycles);
    $finish;
  end
endmodule
