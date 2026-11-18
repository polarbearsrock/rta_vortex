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

  initial begin
    if (!$value$plusargs("NORMAL_AFTER_SFU_MASK=%d",normal_after_sfu_mask)) $fatal(1,"missing reservation mask");
    if (!$value$plusargs("SFU_AFTER_NORMAL_MASK=%d",sfu_after_normal_mask)) $fatal(1,"missing reservation mask");
    repeat(2) tick(); rst_ni=1;
    fd=$fopen("vectors.txt","r");
    if (!fd) $fatal(1,"missing vectors");
    while (!$feof(fd)) begin
      n=$fscanf(fd,"%h %h %h %h %h %h",next_op,next_rm,full_a,full_b,next_c,next_expected);
      if (n==6) begin
        if (is_mul4(next_op)) begin
          mul_a[next_op[4:0]]=full_a; mul_b[next_op[4:0]]=full_b;
          mul_c[next_op[4:0]]=next_c; mul_expected[next_op[4:0]]=next_expected;
          mul_rm[next_op[4:0]]=next_rm; mul_seen[next_op[4:0]]=1;
        end
        if (is_sfu(next_op) && (!sfu_seen[next_op[2:0]] ||
            (full_a[30:23] != 0 && full_a[30:23] != 255))) begin
          sfu_a[next_op[2:0]]=full_a; sfu_b[next_op[2:0]]=full_b;
          sfu_c[next_op[2:0]]=next_c; sfu_expected[next_op[2:0]]=next_expected;
          sfu_rm[next_op[2:0]]=next_rm; sfu_seen[next_op[2:0]]=1;
        end
        if (next_op==7'h60 && (!fma_seen ||
            (full_a[30:23] != 0 && full_a[30:23] != 255 &&
             full_b[30:23] != 0 && full_b[30:23] != 255))) begin
          fma_a=full_a; fma_b=full_b; fma_c=next_c;
          fma_expected=next_expected; fma_rm=next_rm; fma_seen=1;
        end
        if (dpa_mode_i != (next_op[6:3]==4'b1011)) begin
          drain(); dpa_mode_i=(next_op[6:3]==4'b1011); mode_changes++;
        end
        if ((issued%97)==7) begin
          valid_i=0; a_i=~a_i; b_i=~b_i; c_i=~c_i; tick();
        end
        while (reservation_conflict(next_op)) begin
          valid_i=0; tick(); reservation_bubbles++;
        end
        {sa_i,a_i}=full_a; {sb_i,b_i}=full_b; c_i=next_c;
        op_i=next_op; rm_i=next_rm; expected=next_expected; valid_i=1;
        tick(); issued++;
      end else if (n!=-1) $fatal(1,"malformed vectors");
    end
    drain();
    if (checks != issued) $fatal(1,"lost results issued=%0d checked=%0d",issued,checks);
    if (sfu_seen != 7'h7f || !fma_seen) $fatal(1,"missing stream samples");
    dpa_mode_i=0;
    op_i=7'h60; {sa_i,a_i}=fma_a; {sb_i,b_i}=fma_b;
    c_i=fma_c; rm_i=fma_rm; expected=fma_expected;
    valid_i=1; repeat(64) begin tick(); issued++; end
    drain();
    for (integer j=0;j<64;j++) begin
      op_i=7'h78+(j%7); {sa_i,a_i}=sfu_a[j%7]; {sb_i,b_i}=sfu_b[j%7];
      c_i=sfu_c[j%7]; rm_i=sfu_rm[j%7]; expected=sfu_expected[j%7];
      valid_i=1; tick(); issued++;
    end
    drain();
    for (integer j=0;j<128;j++) begin
      op_i=j%2; a_i=256'(32'h80000000 ^ (32'h10203041 * j));
      b_i=256'(32'hffffffff ^ (32'h76543211 * j)); c_i=0; rm_i=0;
      expected={32'b0, (op_i[0] ? a_i[31:0]-b_i[31:0] : a_i[31:0]+b_i[31:0])};
      valid_i=1; tick(); issued++;
    end
    drain();
    if (mul_seen != 32'hffffffff) $fatal(1,"missing multiply variants");
    for (integer j=0;j<128;j++) begin
      op_i=7'h20+(j%32); {sa_i,a_i}=mul_a[j%32]; {sb_i,b_i}=mul_b[j%32];
      c_i=mul_c[j%32]; rm_i=mul_rm[j%32]; expected=mul_expected[j%32];
      valid_i=1; tick(); issued++;
    end
    drain();
    if (max_mul4_run<128) $fatal(1,"insufficient MUL4 II=1 coverage");
    if (max_int2_run<128) $fatal(1,"insufficient INT2 II=1 coverage");
    if (checks != issued) $fatal(1,"lost stream results");
    if (max_normal_run<16 || max_sfu_run<16) $fatal(1,"insufficient II=1 coverage");
    dpa_mode_i=0; op_i=0; a_i=32'd3; b_i=32'd4; c_i=0; rm_i=0; expected=64'd7;
    valid_i=1; repeat(3) tick();
    rst_ni=0; valid_i=0; tick(); rst_ni=1; drain();
    valid_i=1; repeat(10) tick(); drain();

    for (integer reset_case=0; reset_case<16; reset_case++) begin
      drain(); dpa_mode_i=0;
      for (integer j=0; j<20; j++) begin
        op_i=7'h20; a_i=256'(32'h8aab1234 ^ (32'h10203041 * (j+reset_case)));
        b_i=256'(32'h12345678 ^ (32'h76543211 * (j+reset_case))); c_i=0; rm_i=0;
        valid_i=1; #1; expected=comb_result; tick();
      end
      rst_ni=0; valid_i=0; repeat(1+(reset_case%3)) tick(); rst_ni=1;
      for (integer j=0; j<40; j++) begin
        case ((j+reset_case)%5)
          0: next_op=7'h60;
          1: next_op=7'h20;
          2: next_op=7'h00;
          3: next_op=7'h22;
          4: next_op=7'h7a;
        endcase
        while (reservation_conflict(next_op)) begin valid_i=0; tick(); end
        op_i=next_op; a_i=256'(32'h3f123456 ^ (32'h2031 * (j+reset_case)));
        b_i=256'(32'h3e765432 ^ (32'h4321 * j)); c_i=64'h3faabbcc; rm_i=0;
        valid_i=1; #1; expected=comb_result; tick();
      end
      drain();
    end
    $display("SCHEDULE_PASS issued=%0d checks=%0d cycles=%0d mode_changes=%0d reservation_bubbles=%0d max_normal_run=%0d max_sfu_run=%0d max_int2_run=%0d int2_latency=2 max_mul4_run=%0d mul4_latency=4",
             issued,checks,cycles,mode_changes,reservation_bubbles,max_normal_run,max_sfu_run,max_int2_run,max_mul4_run);
    $finish;
  end
endmodule
