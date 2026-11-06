// DPA-16 stage 2: FP4 block scaling, then alignment of 32 product slots + the addend in a 27-bit window
// (2 integer + 25 fraction bits, bits shifted out are truncated) and one signed sum.
// Each term is first left-justified so that its units bit sits at window bit 25 (mode-dependent wiring),
// then shifted right by its distance to the largest anchor.
//   FP16 / TF32 : 11x11 product (22 b) << 5      BF16 : 8x8 product (16 b) << 11
//   FP8         : 4x4 / 4x3 / 3x3 product << 19 / 20 / 21 (E4M3 / mixed / E5M2)
//   FP4 block   : |block sum| x scale product (20 b) << 7          addend : 24-bit significand << 2
//   vector lane l (M > 0): slots 8l .. 8l+3 = 12x12 partial products hh, hl, lh, ll (24 b) << 3,
//                          slot 8l+4 = addend significand << 2; the sum tree is cut into 8-slot segments,
//                          segment l is lane l's sum.
// SHARE = 0: the GEMM sum is one multi-operand add over all 33 terms (as with M = 0); each vector lane has its own
//            small add of its five terms, fed by the shared alignment shifters.
// SHARE = 1: the adder tree is shared too: each lane's five terms are first compressed to carry-save form (three 3:2
//            levels), the GEMM sum adds these pairs and the other terms; lane 0 is the GEMM sum (in vector mode the
//            other lanes' pairs are gated off), lanes 1.. resolve their own pair with one carry-propagate add.
// SHARE = 2: lane 0 rides the GEMM sum as is: in vector mode every slot outside the lanes is zero, so the plain 33-term
//            sum is lane 0's sum once the terms of lanes 1.. are gated out of it; lanes 1.. keep their own small add.
//            With M = 1 nothing is gated and the lane adds no adder at all.
// RND = 1: every term gets one more bit below the window; for lane 0's five slots in vector mode it is the OR of the
//          bits its alignment dropped (sticky, with the term's sign), else 0, so the sums are SUMW + 1 bits and the
//          GEMM value is unchanged (twice the RND = 0 sum). Lane 0's normaliser rounds to nearest even on it.
module dpa16_align_sum import dpa16_pkg::*; #(
  parameter int M     = 0,
  parameter int SHARE = 0,
  parameter int RND   = 0
) (
  input  logic [2:0]              fmt_i,
  input  logic [1:0]              e5_i,          // {a is E5M2, b is E5M2}
  input  logic [NTILE-1:0][23:0]  tprod_i,
  input  logic [NSLOT-1:0]        ps_i,
  input  logic [4:0]              dsh_i [NSLOT+1],
  input  logic                    cs_i,
  input  logic [23:0]             cm_i,
  input  logic                    vec_i,
  input  logic [((M > 0) ? M : 1)-1:0][23:0] vcm_i,
  output logic signed [SUMW+RND-1:0] sum_o,
  output logic signed [SUMW+RND-1:0] vsum_o [(M > 0) ? M : 1]
);
  localparam int ML = (M > 0) ? M : 1;
  localparam int SW = SUMW + RND;

  logic [WIN-1:0] xj [NSLOT+1];      // left-justified magnitudes
  logic [NSLOT:0] neg;

  always_comb begin
    logic [4:0] base8;
    base8 = 5'd19 + 5'(e5_i[0]) + 5'(e5_i[1]);
    for (int s = 0; s < NSLOT; s++) begin
      xj[s]  = '0;
      neg[s] = ps_i[s];
      // vector mode only rewires the lane slots: every other slot is shifted out by its saturated shift (the core
      // clears all term flags in vector mode), so it needs no gating here
      if (M > 0 && vec_i && s < 8 * M && s % 8 < 5) begin
        if (s % 8 < 4) xj[s] = {tprod_i[4*(s/8) + 3 - s%8], 3'd0};
        else           xj[s] = {1'b0, vcm_i[s/8], 2'd0};
      end else begin
        unique case (fmt_i)
          FMT_FP16, FMT_TF32: if (s < NTILE) xj[s] = {tprod_i[s][21:0], 5'd0};
          FMT_BF16:           if (s < NTILE) xj[s] = {tprod_i[s][15:0], 11'd0};
          FMT_FP8:            xj[s] = WIN'(tprod_i[s/2][8*(s%2) +: 8]) << base8;
          default: begin                                       // FP4: slots 0..3 = blocks
            if (s < 4) begin
              logic signed [12:0] bs;
              logic [11:0]        mag;
              logic [19:0]        bm;
              bs     = tprod_i[s][12:0];
              mag    = bs[12] ? 12'(-bs) : bs[11:0];
              bm     = mag * tprod_i[s][20:13];
              xj[s]  = {bm, 7'd0};
              neg[s] = bs[12];
            end
          end
        endcase
      end
    end
    xj[NSLOT]  = {1'b0, cm_i, 2'd0};
    neg[NSLOT] = cs_i;
  end

  // align (+ sticky), negate (one's complement + carry-in)
  logic signed [SW-1:0] t [NSLOT+1];
  always_comb begin
    for (int s = 0; s <= NSLOT; s++) begin
      logic [WIN-1:0]     al;
      logic [WIN+RND-1:0] x;
      logic [SW-1:0]      u;
      al = xj[s] >> dsh_i[s];
      if (RND > 0) x = {al, (M > 0 && vec_i && s < 8 * M && s % 8 < 5) ? |(xj[s] & ~({WIN{1'b1}} << dsh_i[s])) : 1'b0};
      else         x = al;
      u    = neg[s] ? ~SW'(x) : SW'(x);
      t[s] = $signed(u) + $signed(SW'(neg[s]));
    end
  end

  if (M > 0 && SHARE == 1) begin : g_share
    function automatic logic [1:0][SW-1:0] csa(logic [SW-1:0] a, logic [SW-1:0] b, logic [SW-1:0] c);
      return {SW'(((a & b) | (a & c) | (b & c)) << 1), a ^ b ^ c};     // {carry, sum}, mod 2^SW
    endfunction

    logic [ML-1:0][SW-1:0] gs, gc;            // lane groups in carry-save form
    always_comb begin
      for (int l = 0; l < ML; l++) begin
        logic [1:0][SW-1:0] r;
        r = csa(t[8*l], t[8*l + 1], t[8*l + 2]);
        r = csa(r[0], r[1], t[8*l + 3]);
        r = csa(r[0], r[1], t[8*l + 4]);
        gs[l] = r[0];
        gc[l] = r[1];
      end
    end
    always_comb begin
      sum_o = '0;
      for (int l = 0; l < ML; l++) begin
        logic [SW-1:0] g;
        g     = {SW{!(vec_i && l > 0)}};
        sum_o = sum_o + $signed(gs[l] & g) + $signed(gc[l] & g);
      end
      for (int s = 0; s <= NSLOT; s++)
        if (!(s < 8 * M && s % 8 < 5)) sum_o = sum_o + t[s];
    end
    always_comb begin
      vsum_o[0] = sum_o;
      for (int l = 1; l < ML; l++) vsum_o[l] = $signed(gs[l] + gc[l]);
    end
  end else if (M > 0 && SHARE == 2) begin : g_lane0
    always_comb begin
      sum_o = '0;
      for (int s = 0; s <= NSLOT; s++)
        if (s >= 8 && s < 8 * M && s % 8 < 5) sum_o = sum_o + (vec_i ? SW'(0) : t[s]);
        else                                  sum_o = sum_o + t[s];
    end
    always_comb begin
      vsum_o[0] = sum_o;
      for (int l = 1; l < ML; l++) begin
        vsum_o[l] = '0;
        for (int k = 0; k < 5; k++) vsum_o[l] = vsum_o[l] + t[8*l + k];
      end
    end
  end else begin : g_sep
    always_comb begin
      sum_o = '0;
      for (int s = 0; s <= NSLOT; s++) sum_o = sum_o + t[s];
    end
    always_comb begin
      for (int l = 0; l < ML; l++) begin
        vsum_o[l] = '0;
        if (M > 0)
          for (int k = 0; k < 5; k++) vsum_o[l] = vsum_o[l] + t[8*l + k];
      end
    end
  end
endmodule
