// DPA-16 operand unpack: routes the 256-bit operands to the 16 multiplier tiles and computes, per product slot,
// the sign, the "nonzero" flag and the anchor exponent (weight of the product's units bit = sum of the two
// unbiased exponents). FP4 elements become integers k (value k/2); their products are summed per 16-block later.
//   FP16 / BF16 : tile t <- element t                 slot t      = product of tile t
//   TF32        : tile t <- element t (t < 8)         slot t      = product of tile t
//   FP8         : tile t <- elements 2t, 2t+1          slot s      = product of element s (tile s/2)
//   FP4         : tile t <- elements 4t .. 4t+3        block b     = elements 16b .. 16b+15 (tiles 4b .. 4b+3)
module dpa16_unpack import dpa16_pkg::*; (
  input  fmt_e                    fmt_i,
  input  logic                    a_e5m2_i,
  input  logic                    b_e5m2_i,
  input  logic [255:0]            a_i,
  input  logic [255:0]            b_i,
  input  logic [31:0]             sa_i,        // block scales (FP4 modes), byte b = block b
  input  logic [31:0]             sb_i,
  output logic [NTILE-1:0][15:0]  ta_o,        // tile operands
  output logic [NTILE-1:0][15:0]  tb_o,
  output logic [NSLOT-1:0]        ps_o,        // product sign
  output logic [NSLOT-1:0]        pnz_o,       // product nonzero
  output logic signed [AW-1:0]    panc_o [NSLOT],
  output logic [63:0]             s4_o,        // FP4 product signs
  output logic [3:0][7:0]         ms_o,        // FP4 scale significand products
  output logic [3:0]              bnz_o,       // FP4 block has a nonzero product (and nonzero scales)
  output logic signed [AW-1:0]    banc_o [4],
  output logic                    special_o    // NaN / Inf among the active inputs
);
  localparam logic [3:0] E2M1_K [8] = '{4'd0, 4'd1, 4'd2, 4'd3, 4'd4, 4'd6, 4'd8, 4'd12};

  // ---- element decoders: significand (with hidden bit), unbiased exponent of the units bit, special
  typedef struct packed {
    logic                 s;
    logic [10:0]          sig;
    logic signed [AW-1:0] ue;
    logic                 sp;
  } el_t;

  function automatic el_t dec16(logic [15:0] x, logic bf16);
    el_t r;
    r.s = x[15];
    if (bf16) begin
      r.sig = {3'd0, x[14:7] != 0, x[6:0]};
      r.ue  = AW'(x[14:7] != 0 ? x[14:7] : 8'd1) - AW'(127);
      r.sp  = &x[14:7];
    end else begin
      r.sig = {x[14:10] != 0, x[9:0]};
      r.ue  = AW'(x[14:10] != 0 ? x[14:10] : 5'd1) - AW'(15);
      r.sp  = &x[14:10];
    end
    return r;
  endfunction

  function automatic el_t dec_tf32(logic [31:0] x);
    el_t r;
    r.s   = x[31];
    r.sig = {x[30:23] != 0, x[22:13]};
    r.ue  = AW'(x[30:23] != 0 ? x[30:23] : 8'd1) - AW'(127);
    r.sp  = &x[30:23];
    return r;
  endfunction

  function automatic el_t dec_fp8(logic [7:0] x, logic e5m2);
    el_t r;
    r.s = x[7];
    if (e5m2) begin
      r.sig = {8'd0, x[6:2] != 0, x[1:0]};
      r.ue  = AW'(x[6:2] != 0 ? x[6:2] : 5'd1) - AW'(15);
      r.sp  = &x[6:2];
    end else begin
      r.sig = {7'd0, x[6:3] != 0, x[2:0]};
      r.ue  = AW'(x[6:3] != 0 ? x[6:3] : 4'd1) - AW'(7);
      r.sp  = &x[6:0];
    end
    return r;
  endfunction

  logic is16, isbf, istf, is8, is4, isnv;
  assign is16 = fmt_i == FMT_FP16 || fmt_i == FMT_BF16;
  assign isbf = fmt_i == FMT_BF16;
  assign istf = fmt_i == FMT_TF32;
  assign is8  = fmt_i == FMT_FP8;
  assign is4  = fmt_i == FMT_NVFP4 || fmt_i == FMT_MXFP4;
  assign isnv = fmt_i == FMT_NVFP4;

  logic sp_main, sp_fp4;

  always_comb begin
    logic sp;
    sp = 1'b0;
    for (int s = 0; s < NSLOT; s++) begin
      ps_o[s]   = 1'b0;
      pnz_o[s]  = 1'b0;
      panc_o[s] = '0;
    end
    for (int t = 0; t < NTILE; t++) begin
      ta_o[t] = '0;
      tb_o[t] = '0;
    end
    if (is16 || istf) begin
      for (int t = 0; t < NTILE; t++) begin
        el_t ea, eb;
        if (istf) begin
          ea = dec_tf32(a_i[32*(t%8) +: 32]);
          eb = dec_tf32(b_i[32*(t%8) +: 32]);
        end else begin
          ea = dec16(a_i[16*t +: 16], isbf);
          eb = dec16(b_i[16*t +: 16], isbf);
        end
        if (!istf || t < 8) begin
          ta_o[t]   = {5'd0, ea.sig};
          tb_o[t]   = {5'd0, eb.sig};
          ps_o[t]   = ea.s ^ eb.s;
          pnz_o[t]  = (ea.sig != 0) && (eb.sig != 0);
          panc_o[t] = ea.ue + eb.ue;
          sp        = sp | ea.sp | eb.sp;
        end
      end
    end else if (is8) begin
      for (int s = 0; s < NSLOT; s++) begin
        el_t ea, eb;
        ea = dec_fp8(a_i[8*s +: 8], a_e5m2_i);
        eb = dec_fp8(b_i[8*s +: 8], b_e5m2_i);
        ta_o[s/2][4*(s%2) +: 4] = ea.sig[3:0];
        tb_o[s/2][4*(s%2) +: 4] = eb.sig[3:0];
        ps_o[s]   = ea.s ^ eb.s;
        pnz_o[s]  = (ea.sig != 0) && (eb.sig != 0);
        panc_o[s] = ea.ue + eb.ue;
        sp        = sp | ea.sp | eb.sp;
      end
    end else if (is4) begin
      for (int i = 0; i < 64; i++) begin
        ta_o[i/4][4*(i%4) +: 4] = E2M1_K[a_i[4*i +: 3]];
        tb_o[i/4][4*(i%4) +: 4] = E2M1_K[b_i[4*i +: 3]];
      end
    end
    sp_main = sp;
  end

  // ---- FP4: product signs, block nonzero flags, scales
  always_comb begin
    logic sp4;
    sp4 = 1'b0;
    for (int i = 0; i < 64; i++)
      s4_o[i] = a_i[4*i+3] ^ b_i[4*i+3];
    for (int blk = 0; blk < 4; blk++) begin
      logic                 any;
      logic [7:0]           xa, xb;
      logic [3:0]           ga, gb;
      logic signed [AW-1:0] ua, ub;
      any = 1'b0;
      for (int i = 16 * blk; i < 16 * blk + 16; i++)
        any = any | ((a_i[4*i +: 3] != 0) && (b_i[4*i +: 3] != 0));
      xa = sa_i[8*blk +: 8];
      xb = sb_i[8*blk +: 8];
      if (isnv) begin                         // UE4M3 (sign bit ignored)
        ga  = {xa[6:3] != 0, xa[2:0]};
        gb  = {xb[6:3] != 0, xb[2:0]};
        ua  = AW'(xa[6:3] != 0 ? xa[6:3] : 4'd1) - AW'(2);
        ub  = AW'(xb[6:3] != 0 ? xb[6:3] : 4'd1) - AW'(2);
        sp4 = sp4 | (&xa[6:0]) | (&xb[6:0]);
      end else begin                          // E8M0
        ga  = 4'b1000;
        gb  = 4'b1000;
        ua  = AW'(xa) - AW'(122);
        ub  = AW'(xb) - AW'(122);
        sp4 = sp4 | (&xa) | (&xb);
      end
      ms_o[blk]   = ga * gb;
      bnz_o[blk]  = is4 && any && (ga != 0) && (gb != 0);
      banc_o[blk] = ua + ub;
    end
    sp_fp4 = is4 && sp4;
  end

  assign special_o = sp_main | sp_fp4;
endmodule
