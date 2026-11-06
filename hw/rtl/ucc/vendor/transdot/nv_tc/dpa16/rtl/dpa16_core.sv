// DPA-16 PE datapath: d = c + sum a_i * b_i in FP32 (B200 tensor-core numerics, see ../model/dpa16_ref.py).
// Three pipeline stages after the (externally registered) inputs:
//   S1  unpack, 16 multiplier tiles, FP4 block sums, anchors, max anchor, per-term shift amounts   -> r1
//   S2  FP4 block scaling, alignment of 33 terms in a 27-bit window (truncation), one signed sum  -> r2
//   S3  normalise, truncate to FP32, specials                                                    -> d_o
// Vector mode (M > 0, vec_i = 1): M FP32 FMA lanes vd[l] = va[l] * vb[l] + vc[l], same pipeline, built from the
// GEMM datapath: lane l uses tiles 4l .. 4l+3 for the four 12x12 partial products of its 24x24 multiply and the
// alignment shifters of slots 8l .. 8l+4 (partial products hh, hl, lh, ll and the addend); it adds its own small
// 5-term sum, finds its largest anchor with one compare, and has its own normaliser (lane 0 shares the GEMM
// normaliser and pipeline registers). Same window / truncation numerics; RND = 1: lane 0 rounds to nearest even
// (one sticky bit per lane term, ../model/lane_rne_ref.py); RND = 2: lane 0 is an IEEE-754 FP32 FMA (RNE, bit-exact
// with FPnew's fpnew_fma, ../model/ieee_fma_ref.py): tiles 0..3 still form the 24x24 product, merged exactly into 48
// bits, and FPnew's back end (3p+4-bit alignment, sum, normalisation, rounding, special cases) replaces the window.
// PIPE = 0 drops the three stage registers (purely combinational core, latency 0) for area comparisons free of
// pipeline-register placement; ONLY >= 0 hard-wires one format (e.g. FMT_BF16) to measure the multi-format cost.
module dpa16_core import dpa16_pkg::*; #(
  parameter int M    = 0,                              // FP32 vector lanes: 0 (GEMM only), 1, 2 or 4
  parameter bit PIPE = 1'b1,
  parameter int ONLY = -1,
  parameter int SHARE = 0,                             // adder-tree sharing of the lanes, see dpa16_align_sum
  parameter int RND   = 0                              // 1: lane 0 rounds to nearest even (sticky bits, see dpa16_norm);
                                                       // 2: lane 0 is an IEEE FMA, FPnew back end (M = 1 only);
                                                       // 3: lane 0 is an IEEE FMA, lean back end dpa16_fma_lean
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  fmt_e          fmt_i,
  input  logic          a_e5m2_i,
  input  logic          b_e5m2_i,
  input  logic [255:0]  a_i,
  input  logic [255:0]  b_i,
  input  logic [31:0]   sa_i,
  input  logic [31:0]   sb_i,
  input  logic [31:0]   c_i,
  output logic [31:0]   d_o,
  input  logic                              vec_i,
  input  logic [((M > 0) ? M : 1)-1:0][31:0] va_i,
  input  logic [((M > 0) ? M : 1)-1:0][31:0] vb_i,
  input  logic [((M > 0) ? M : 1)-1:0][31:0] vc_i,
  output logic [((M > 0) ? M : 1)-1:0][31:0] vd_o
);
  localparam int ML = (M > 0) ? M : 1;
  localparam int LM = (RND >= 2) ? 0 : M;              // lanes that use the window datapath (slots, shifts, sums)
  localparam int RW = (RND == 1) ? 1 : 0;              // sticky bit below the window

  fmt_e fmt;
  assign fmt = (ONLY < 0) ? fmt_i : fmt_e'(ONLY);

  // =========================================================================================== S1
  logic [NTILE-1:0][15:0] ta_g, tb_g, ta, tb;
  logic [NSLOT-1:0]       ps_g, pnz;
  logic signed [AW-1:0]   panc [NSLOT];
  logic [63:0]            s4;
  logic [3:0][7:0]        ms;
  logic [3:0]             bnz;
  logic signed [AW-1:0]   banc [4];
  logic                   sp_in;

  dpa16_unpack u_unpack (
    .fmt_i (fmt), .a_e5m2_i, .b_e5m2_i, .a_i, .b_i, .sa_i, .sb_i,
    .ta_o (ta_g), .tb_o (tb_g), .ps_o (ps_g), .pnz_o (pnz), .panc_o (panc),
    .s4_o (s4), .ms_o (ms), .bnz_o (bnz), .banc_o (banc), .special_o (sp_in)
  );

  logic vm, is16, istf, is8, is4;
  assign vm   = (M > 0) && vec_i;
  assign is16 = !vm && (fmt == FMT_FP16 || fmt == FMT_BF16);
  assign istf = !vm && fmt == FMT_TF32;
  assign is8  = !vm && fmt == FMT_FP8;
  assign is4  = !vm && (fmt == FMT_NVFP4 || fmt == FMT_MXFP4);

  // ---- vector lanes: FP32 decode and tile operands
  typedef struct packed {
    logic                 s;
    logic [23:0]          sig;
    logic signed [AW-1:0] ue;
    logic                 sp;
  } f32_t;

  function automatic f32_t dec32(logic [31:0] x);
    f32_t r;
    r.s   = x[31];
    r.sig = {x[30:23] != 0, x[22:0]};
    r.ue  = AW'(x[30:23] != 0 ? x[30:23] : 8'd1) - AW'(127);
    r.sp  = &x[30:23];
    return r;
  endfunction

  f32_t vA [ML], vB [ML], vC [ML];
  always_comb begin
    for (int l = 0; l < ML; l++) begin
      vA[l] = dec32(va_i[l]);
      vB[l] = dec32(vb_i[l]);
      vC[l] = dec32(vc_i[l]);
    end
  end

  // lane l, tile 4l+k: k = 0 a_lo*b_lo, 1 a_lo*b_hi, 2 a_hi*b_lo, 3 a_hi*b_hi
  always_comb begin
    ta = ta_g;
    tb = tb_g;
    // tiles 4M.. keep their GEMM operands in vector mode: their slots are shifted out (see dsh), nothing to gate
    if (vm) begin
      for (int t = 0; t < 4 * M; t++) begin
        ta[t] = {4'd0, (t % 4 >= 2) ? vA[t/4].sig[23:12] : vA[t/4].sig[11:0]};
        tb[t] = {4'd0, (t % 4 == 1 || t % 4 == 3) ? vB[t/4].sig[23:12] : vB[t/4].sig[11:0]};
      end
    end
  end

  logic [NTILE-1:0][23:0]     tprod;
  logic [NTILE-1:0][3:0][7:0] dprod;
  for (genvar t = 0; t < NTILE; t++) begin : g_tile
    dpa16_mul12 u_mul (
      .a_i (ta[t]), .b_i (tb[t]),
      .m_full_i (is16 || istf || vm), .m_fp8_i (is8), .m_fp4_i (is4),
      .prod_o (tprod[t]), .dprod_o (dprod[t])
    );
  end

  // FP4: exact signed sum of the 16 integer products of each block (|sum| <= 16 * 144)
  logic signed [12:0] bsum [4];
  always_comb begin
    for (int blk = 0; blk < 4; blk++) begin
      bsum[blk] = '0;
      for (int i = 16 * blk; i < 16 * blk + 16; i++) begin
        logic [7:0] p;
        p = dprod[i/4][i%4];
        bsum[blk] = s4[i] ? bsum[blk] - 13'(p) : bsum[blk] + 13'(p);
      end
    end
  end

  // addend
  logic                 cs, cnz, csp;
  logic [23:0]          cm;
  logic signed [AW-1:0] canc;
  assign cs   = c_i[31];
  assign cm   = {c_i[30:23] != 0, c_i[22:0]};
  assign cnz  = cm != 0;
  assign csp  = &c_i[30:23];
  assign canc = AW'(c_i[30:23] != 0 ? c_i[30:23] : 8'd1) - AW'(127);

  // GEMM term anchors / nonzero flags / signs
  logic signed [AW-1:0] tanc [NSLOT+1];
  logic [NSLOT:0]       tnz;
  logic [NSLOT-1:0]     ps;
  always_comb begin
    for (int s = 0; s < NSLOT; s++) begin
      tanc[s] = panc[s];
      tnz[s]  = pnz[s] && !is4 && !vm;
      ps[s]   = ps_g[s];
    end
    for (int blk = 0; blk < 4; blk++) begin
      if (is4) begin
        tanc[blk] = banc[blk];
        tnz[blk]  = bnz[blk];
      end
    end
    tanc[NSLOT] = canc;
    tnz[NSLOT]  = cnz && !vm;
  end

  // vector lanes, terms 8l + {hh, hl, lh, ll, c}: the partial products' anchors are ap, ap-12, ap-12, ap-24, so the
  // lane's largest anchor is max(ap, addend) and the shifts follow from one difference (no search tree)
  logic signed [AW-1:0] vsemax [ML];
  logic [ML-1:0][4:0]   vdA, vdC;           // shift of hh / of the addend (saturated)
  logic [ML-1:0]        vpnz, vcnz;
  always_comb begin
    for (int l = 0; l < ML; l++) begin
      logic signed [AW-1:0] ap, df;
      ap      = vA[l].ue + vB[l].ue;
      vpnz[l] = vA[l].sig != 0 && vB[l].sig != 0;
      vcnz[l] = vC[l].sig != 0;
      df      = ap - vC[l].ue;
      if (vpnz[l] && (!vcnz[l] || df >= 0)) begin
        vsemax[l] = ap;
        vdA[l]    = '0;
        vdC[l]    = (df > AW'(WIN)) ? 5'(WIN) : df[4:0];
      end else begin
        vsemax[l] = vC[l].ue;
        vdC[l]    = '0;
        vdA[l]    = (-df > AW'(WIN)) ? 5'(WIN) : 5'(-df);
      end
    end
  end

  // GEMM: largest anchor over the nonzero terms, balanced tree (zero terms carry the most negative value)
  localparam logic signed [AW-1:0] NEG = {1'b1, {(AW-1){1'b0}}};
  logic signed [AW-1:0] emax;
  logic                 anynz;
  logic signed [AW-1:0] semax [4];
  logic [3:0]           snz;
  always_comb begin
    logic signed [AW-1:0] l0 [32], l1 [16], l2 [8], l4 [2], l5;
    for (int s = 0; s < 32; s++) l0[s] = tnz[s] ? tanc[s] : NEG;
    for (int i = 0; i < 16; i++) l1[i] = (l0[2*i] > l0[2*i+1]) ? l0[2*i] : l0[2*i+1];
    for (int i = 0; i < 8; i++)  l2[i] = (l1[2*i] > l1[2*i+1]) ? l1[2*i] : l1[2*i+1];
    for (int i = 0; i < 4; i++)  semax[i] = (l2[2*i] > l2[2*i+1]) ? l2[2*i] : l2[2*i+1];
    for (int i = 0; i < 2; i++)  l4[i] = (semax[2*i] > semax[2*i+1]) ? semax[2*i] : semax[2*i+1];
    l5   = (l4[0] > l4[1]) ? l4[0] : l4[1];
    emax = (tnz[NSLOT] && tanc[NSLOT] > l5) ? tanc[NSLOT] : l5;
    anynz = |tnz;
    for (int g = 0; g < 4; g++) snz[g] = |tnz[8*g +: 8];
  end

  // ------------------------------------------------------------------------------------- r1
  // FP4 reuses the tile-product register of tiles 0..3 for {scale product, block sum}
  logic [NTILE-1:0][23:0] r1_tprod;
  logic [NSLOT-1:0]       r1_ps;
  logic signed [AW-1:0]   r1_tanc [NSLOT+1];
  logic [NSLOT:0]         r1_tnz;
  logic                   r1_cs;
  logic [23:0]            r1_cm;
  logic signed [AW-1:0]   r1_emax;
  logic                   r1_anynz, r1_sp;
  fmt_e                   r1_fmt;
  logic [1:0]             r1_e5;
  logic                   r1_vm;
  logic [ML-1:0][23:0]    r1_vcm;
  logic signed [AW-1:0]   r1_semax [ML];
  logic [ML-1:0]          r1_snz, r1_vsp;
  logic [ML-1:0][4:0]     r1_vdA, r1_vdC;
  logic [ML-1:0]          r1_vpnz, r1_vcnz, r1_vps, r1_vcs;
  if (PIPE) begin : g_r1
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        r1_tprod <= '0;
        r1_ps    <= '0;
        for (int s = 0; s <= NSLOT; s++) r1_tanc[s] <= '0;
        r1_tnz   <= '0;
        r1_cs    <= 1'b0;
        r1_cm    <= '0;
        r1_emax  <= '0;
        r1_anynz <= 1'b0;
        r1_sp    <= 1'b0;
        r1_fmt   <= FMT_FP16;
        r1_e5    <= '0;
        r1_vm    <= 1'b0;
        r1_vcm   <= '0;
        for (int l = 0; l < ML; l++) r1_semax[l] <= '0;
        r1_snz   <= '0;
        r1_vsp   <= '0;
        r1_vdA   <= '0;
        r1_vdC   <= '0;
        r1_vpnz  <= '0;
        r1_vcnz  <= '0;
        r1_vps   <= '0;
        r1_vcs   <= '0;
      end else begin
        for (int t = 0; t < NTILE; t++)
          r1_tprod[t] <= (is4 && t < 4) ? {3'd0, ms[t], bsum[t]} :
                         is8               ? {8'd0, dprod[t][1], dprod[t][0]} : tprod[t];
        r1_ps    <= ps;
        for (int s = 0; s <= NSLOT; s++) r1_tanc[s] <= tanc[s];
        r1_tnz   <= tnz;
        r1_cs    <= cs;
        r1_cm    <= cm;
        r1_emax  <= emax;
        r1_anynz <= anynz;
        r1_sp    <= !vm && (sp_in || csp);
        r1_fmt   <= fmt;
        r1_e5    <= {a_e5m2_i, b_e5m2_i};
        if (M > 0) begin
          r1_vm <= vm;
          for (int l = 0; l < ML; l++) begin
            r1_vcm[l]   <= vC[l].sig;
            r1_semax[l] <= vsemax[l];
            r1_vsp[l]   <= vA[l].sp || vB[l].sp || vC[l].sp;
            r1_vps[l]   <= vA[l].s ^ vB[l].s;
            r1_vcs[l]   <= vC[l].s;
          end
          r1_snz  <= vpnz | vcnz;
          r1_vdA  <= vdA;
          r1_vdC  <= vdC;
          r1_vpnz <= vpnz;
          r1_vcnz <= vcnz;
        end
      end
    end
  end else begin : g_r1c
    always_comb begin
      // stage-register outputs of the lane fields stay 0 without lanes, as with PIPE = 1
      r1_vm = 1'b0; r1_vcm = '0; r1_snz = '0; r1_vsp = '0; r1_vdA = '0; r1_vdC = '0;
      r1_vpnz = '0; r1_vcnz = '0; r1_vps = '0; r1_vcs = '0;
      for (int l = 0; l < ML; l++) r1_semax[l] = '0;
      for (int t = 0; t < NTILE; t++)
        r1_tprod[t] = (is4 && t < 4) ? {3'd0, ms[t], bsum[t]} :
                      is8               ? {8'd0, dprod[t][1], dprod[t][0]} : tprod[t];
      r1_ps    = ps;
      for (int s = 0; s <= NSLOT; s++) r1_tanc[s] = tanc[s];
      r1_tnz   = tnz;
      r1_cs    = cs;
      r1_cm    = cm;
      r1_emax  = emax;
      r1_anynz = anynz;
      r1_sp    = !vm && (sp_in || csp);
      r1_fmt   = fmt;
      r1_e5    = {a_e5m2_i, b_e5m2_i};
      if (M > 0) begin
        r1_vm = vm;
        for (int l = 0; l < ML; l++) begin
          r1_vcm[l]   = vC[l].sig;
          r1_semax[l] = vsemax[l];
          r1_vsp[l]   = vA[l].sp || vB[l].sp || vC[l].sp;
          r1_vps[l]   = vA[l].s ^ vB[l].s;
          r1_vcs[l]   = vC[l].s;
        end
        r1_snz  = vpnz | vcnz;
        r1_vdA  = vdA;
        r1_vdC  = vdC;
        r1_vpnz = vpnz;
        r1_vcnz = vcnz;
      end
    end
  end

  // =========================================================================================== S2
  // each term's right shift: distance to the largest anchor, saturated at the window (vector lanes: from the lane's
  // two registered differences, partial product k adding its 0 / 12 / 12 / 24 offset)
  logic [4:0]       dsh [NSLOT+1];
  logic [NSLOT-1:0] ps2;
  always_comb begin
    for (int s = 0; s <= NSLOT; s++) begin
      logic signed [AW-1:0] d;
      d = r1_emax - r1_tanc[s];
      dsh[s] = (!r1_tnz[s] || d > AW'(WIN)) ? 5'(WIN) : d[4:0];
      if (s < NSLOT) ps2[s] = r1_ps[s];
      // vector mode: all term flags are clear, so every slot already gets the saturated shift; only the lane slots
      // 8l .. 8l+4 are overridden
      if (LM > 0 && r1_vm && s < 8 * LM && s % 8 < 5) begin
        logic [5:0] dv;
        int         l, k;
        l = s / 8;
        k = s % 8;
        if (k < 4) begin
          dv = 6'(r1_vdA[l % ML]) + 6'(k == 0 ? 0 : (k == 3 ? 24 : 12));
          dsh[s] = (!r1_vpnz[l % ML] || dv > 6'(WIN)) ? 5'(WIN) : dv[4:0];
          ps2[s] = r1_vps[l % ML];
        end else begin
          dsh[s] = r1_vcnz[l % ML] ? r1_vdC[l % ML] : 5'(WIN);
          ps2[s] = r1_vcs[l % ML];
        end
      end
    end
  end

  localparam int SW = SUMW + RW;
  logic signed [SW-1:0] sum;
  localparam int LMS = (LM > 0) ? LM : 1;                // window-lane sums the adder block produces
  logic signed [SW-1:0] vsum_a [LMS];
  logic signed [SW-1:0] vsum [ML];                       // padded to ML (IEEE lanes have no window sum)
  dpa16_align_sum #(.M (LM), .SHARE (SHARE), .RND (RW)) u_align (
    .fmt_i (r1_fmt), .e5_i (r1_e5), .tprod_i (r1_tprod), .ps_i (ps2), .dsh_i (dsh),
    .cs_i (r1_cs), .cm_i (r1_cm), .vec_i (r1_vm), .vcm_i (r1_vcm), .sum_o (sum), .vsum_o (vsum_a)
  );
  always_comb for (int l = 0; l < ML; l++) vsum[l] = (l < LMS) ? vsum_a[l] : '0;

  // RND = 2: lane 0 is an IEEE FMA, its exact product from tiles 0..3 (hh, hl, lh, ll = tiles 3, 2, 1, 0) goes into
  // FPnew's FMA back end with the raw operands; the window datapath is GEMM only
  // (RND = 3: every lane l is a lean IEEE FMA fed by its own tiles 4l .. 4l+3; RND = 2 is lane 0 only)
  logic [ML-1:0][2:0][31:0] r1_vraw;
  logic [ML-1:0][31:0]      ieee_d;
  if (RND >= 2) begin : g_r1x
    if (PIPE) begin : g_r
      always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) r1_vraw <= '0;
        else         for (int l = 0; l < ML; l++) r1_vraw[l] <= {vc_i[l], vb_i[l], va_i[l]};
    end else begin : g_c
      always_comb for (int l = 0; l < ML; l++) r1_vraw[l] = {vc_i[l], vb_i[l], va_i[l]};
    end
  end else begin : g_r1x0
    assign r1_vraw = '0;
  end
  if (RND == 2) begin : g_ieee
    logic [47:0] prod;
    assign prod = {r1_tprod[3], 24'd0} + {12'd0, r1_tprod[2], 12'd0} + {12'd0, r1_tprod[1], 12'd0} +
                  {24'd0, r1_tprod[0]};
    dpa16_fma_back #(.FpFormat (fpnew_pkg::FP32), .NumPipeRegs (0)) u_fma (
      .clk_i, .rst_ni, .operands_i (r1_vraw[0]), .product_i (prod), .is_boxed_i (3'b111),
      .rnd_mode_i (fpnew_pkg::RNE), .op_i (fpnew_pkg::FMADD), .op_mod_i (1'b0), .tag_i (1'b0), .mask_i (1'b1),
      .aux_i (1'b0), .in_valid_i (1'b1), .in_ready_o (), .flush_i (1'b0), .result_o (ieee_d[0]), .status_o (),
      .extension_bit_o (), .tag_o (), .mask_o (), .aux_o (), .out_valid_o (), .out_ready_i (1'b1), .busy_o (),
      .reg_ena_i ('0)
    );
    for (genvar l = 1; l < ML; l++) begin : g_rest
      assign ieee_d[l] = '0;
    end
  end else if (RND == 3) begin : g_lean
    for (genvar l = 0; l < ML; l++) begin : g_l
      dpa16_fma_lean4 u_fma (.a_i (r1_vraw[l][0]), .b_i (r1_vraw[l][1]), .c_i (r1_vraw[l][2]),
                            .hh_i (r1_tprod[4 * l + 3]), .hl_i (r1_tprod[4 * l + 2]), .lh_i (r1_tprod[4 * l + 1]),
                            .ll_i (r1_tprod[4 * l]), .d_o (ieee_d[l]));
    end
  end else begin : g_no_ieee
    assign ieee_d = '0;
  end

  // lane 0 rides on the GEMM registers (RND < 2); lanes 1.. have their own
  logic lvm;
  assign lvm = LM > 0 && r1_vm;
  logic signed [SW-1:0]   r2_sum;
  logic signed [AW-1:0]   r2_emax;
  logic                   r2_anynz, r2_sp, r2_vm;
  logic [ML-1:0][31:0]    r2_ieee;
  logic signed [SW-1:0]   r2_vsum [ML];
  logic signed [AW-1:0]   r2_semax [ML];
  logic [ML-1:0]          r2_snz, r2_vsp;
  if (PIPE) begin : g_r2
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        r2_sum   <= '0;
        r2_vm    <= 1'b0;
        r2_ieee  <= '0;
        r2_emax  <= '0;
        r2_anynz <= 1'b0;
        r2_sp    <= 1'b0;
        for (int l = 0; l < ML; l++) begin
          r2_vsum[l]  <= '0;
          r2_semax[l] <= '0;
        end
        r2_snz <= '0;
        r2_vsp <= '0;
      end else begin
        r2_sum   <= lvm ? vsum[0]     : sum;
        r2_vm    <= r1_vm;
        r2_ieee  <= ieee_d;
        r2_emax  <= lvm ? r1_semax[0] : r1_emax;
        r2_anynz <= lvm ? r1_snz[0]   : r1_anynz;
        r2_sp    <= lvm ? r1_vsp[0]   : r1_sp;
        for (int l = 1; l < ML; l++) begin
          r2_vsum[l]  <= vsum[l];
          r2_semax[l] <= r1_semax[l];
        end
        r2_snz <= r1_snz;
        r2_vsp <= r1_vsp;
      end
    end
  end else begin : g_r2c
    always_comb begin
      for (int l = 0; l < ML; l++) begin
        r2_vsum[l]  = '0;
        r2_semax[l] = '0;
      end
      r2_sum   = lvm ? vsum[0]     : sum;
      r2_vm    = r1_vm;
      r2_ieee  = ieee_d;
      r2_emax  = lvm ? r1_semax[0] : r1_emax;
      r2_anynz = lvm ? r1_snz[0]   : r1_anynz;
      r2_sp    = lvm ? r1_vsp[0]   : r1_sp;
      for (int l = 1; l < ML; l++) begin
        r2_vsum[l]  = vsum[l];
        r2_semax[l] = r1_semax[l];
      end
      r2_snz = r1_snz;
      r2_vsp = r1_vsp;
    end
  end

  // =========================================================================================== S3
  logic [ML-1:0][31:0] dn;
  logic [31:0] gn;
  dpa16_norm #(.RND (RW)) u_norm (.sum_i (r2_sum), .emax_i (r2_emax), .zero_i (!r2_anynz), .special_i (r2_sp),
                                  .rne_i (r2_vm), .d_o (gn));
  assign dn[0] = (RND >= 2 && r2_vm) ? r2_ieee[0] : gn;
  for (genvar l = 1; l < ML; l++) begin : g_lane_norm
    if (RND >= 2) begin : g_i
      assign dn[l] = r2_ieee[l];
    end else begin : g_w                                 // window lane with its own small sum (RND = 1: RNE too)
      dpa16_norm #(.RND (RW)) u_norm (.sum_i (r2_vsum[l]), .emax_i (r2_semax[l]), .zero_i (!r2_snz[l]),
                                       .special_i (r2_vsp[l]), .rne_i (RW ? r2_vm : 1'b0), .d_o (dn[l]));
    end
  end

  logic [ML-1:0][31:0] r3_d;
  if (PIPE) begin : g_r3
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) r3_d <= '0;
      else         r3_d <= dn;
    end
  end else begin : g_r3c
    assign r3_d = dn;
  end
  assign d_o  = r3_d[0];
  assign vd_o = r3_d;
endmodule
