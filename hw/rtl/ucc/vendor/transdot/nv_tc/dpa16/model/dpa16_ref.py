"""Bit-accurate reference model of the DPA-16 PE datapath (rtl/dpa16_core.sv): d = c + sum_i a_i * b_i in FP32.

Operands are 256-bit vectors per side:
  FP16 / BF16  16 elements      TF32  8 elements (32-bit containers, top 19 bits used)
  FP8          32 elements (E4M3 or E5M2 per side)
  NVFP4 / MXFP4 64 E2M1 elements in 4 blocks of 16, one 8-bit scale per block and side
                (NVFP4: UE4M3 scale; MXFP4: E8M0 scale, the driver repeats it for both halves of a 32-block)
Numerics follow the B200 / H100 tensor-core model of Khattak & Mikaitis (TACO 2026, arXiv 2512.07004, Table II,
Fig. 5), measured there for fp16 / bf16 / tf19 only; the fp8 and fp4 modes apply the same window to 32 / 64-wide sums
as an assumption (B200's native tcgen05 fp8 / fp4 path is not characterised; Hopper's native fp8 path keeps 13 bits):
products are exact and kept denormalised (2 integer bits); every term, c included, is aligned to the largest
anchor exponent in a 27-bit window (2 integer + 25 fraction bits) with truncation; one sum; normalise; truncate
to FP32 (subnormal outputs kept while the shift allows, overflow -> inf).
FP4: E2M1 values are k/2 with k in {0,1,2,3,4,6,8,12}; a block's 16 products are summed exactly as integers,
multiplied by the two scale significands and then aligned like a product.
Any NaN / Inf among the active inputs (elements, scales, c) gives the canonical NaN 0x7FC00000.
Not modelled (B200 corner cases): the alignment-exponent floor e_min = -133 when c = 0 and all products are tiny.
"""
FP16, BF16, TF32, FP8, NVFP4, MXFP4 = range(6)
FMT_NAMES = {FP16: "fp16", BF16: "bf16", TF32: "tf32", FP8: "fp8", NVFP4: "nvfp4", MXFP4: "mxfp4"}
E2M1_K = [0, 1, 2, 3, 4, 6, 8, 12]
QNAN = 0x7FC00000
WIN_FRAC = 25                     # fraction bits of the alignment window


def bits(v, lo, n):
    return (v >> lo) & ((1 << n) - 1)


def dec(x, eb, mb, bias):
    """IEEE-like decode -> (sign, significand with hidden bit, lsb exponent, special)."""
    s = bits(x, eb + mb, 1)
    e = bits(x, mb, eb)
    m = bits(x, 0, mb)
    hid = 1 if e else 0
    return s, (hid << mb) | m, (e if e else 1) - bias - mb, e == (1 << eb) - 1


def dec_fp8(x, e5m2):
    if e5m2:
        return dec(x, 5, 2, 15)
    s, sig, e, _ = dec(x, 4, 3, 7)
    return s, sig, e, bits(x, 0, 7) == 0x7F            # E4M3: only S.1111.111 is NaN


def elements(v, fmt, e5m2=False):
    """List of (sign, significand, lsb exponent, width, special) for one 256-bit operand."""
    out = []
    if fmt in (FP16, BF16):
        eb, mb, bias = (5, 10, 15) if fmt == FP16 else (8, 7, 127)
        for i in range(16):
            s, sig, e, sp = dec(bits(v, 16 * i, 16), eb, mb, bias)
            out.append((s, sig, e, mb + 1, sp))
    elif fmt == TF32:
        for i in range(8):
            s, sig, e, sp = dec(bits(v, 32 * i + 13, 19), 8, 10, 127)
            out.append((s, sig, e, 11, sp))
    elif fmt == FP8:
        for i in range(32):
            s, sig, e, sp = dec_fp8(bits(v, 8 * i, 8), e5m2)
            out.append((s, sig, e, 3 if e5m2 else 4, sp))
    else:
        for i in range(64):
            x = bits(v, 4 * i, 4)
            out.append((x >> 3, E2M1_K[x & 7], -1, 4, False))
    return out


def scale(x, fmt):
    """Block scale -> (significand, lsb exponent, special)."""
    if fmt == NVFP4:
        _, sig, e, _ = dec(x & 0x7F, 4, 3, 7)
        return sig, e, (x & 0x7F) == 0x7F
    return 8, x - 127 - 3, x == 0xFF


def dpa16(fmt, a, b, sa, sb, c, a_e5m2=False, b_e5m2=False, trace=None):
    """Returns the FP32 result bits. sa / sb: 32-bit words, byte i = scale of block i."""
    special = False
    terms = []                                      # (sign, magnitude X, lsb exponent, anchor)
    if fmt in (NVFP4, MXFP4):
        ea, eb_ = elements(a, fmt), elements(b, fmt)
        for blk in range(4):
            acc, anyp = 0, False
            for i in range(16 * blk, 16 * blk + 16):
                p = ea[i][1] * eb_[i][1]
                anyp |= p != 0
                acc += -p if ea[i][0] ^ eb_[i][0] else p
            ma, xa, spa = scale(bits(sa, 8 * blk, 8), fmt)
            mb, xb, spb = scale(bits(sb, 8 * blk, 8), fmt)
            special |= spa or spb
            ex = xa + xb - 2
            if anyp and ma * mb:                       # a block with nonzero products sets the anchor even if
                terms.append((acc < 0, abs(acc) * ma * mb, ex, ex + 18))   # they cancel
    else:
        ea, eb_ = elements(a, fmt, a_e5m2), elements(b, fmt, b_e5m2)
        for (s1, m1, e1, w1, sp1), (s2, m2, e2, w2, sp2) in zip(ea, eb_):
            special |= sp1 or sp2
            if m1 and m2:
                terms.append((s1 ^ s2, m1 * m2, e1 + e2, e1 + e2 + (w1 - 1) + (w2 - 1)))
    cs, cm, ce, csp = dec(c, 8, 23, 127)
    special |= csp
    if cm:
        terms.append((cs, cm, ce, ce + 23))
    return window_sum(terms, special, trace)


def vec_fma(a, b, c):
    """One vector lane (M > 0, vec_i = 1): a * b + c in FP32 on the GEMM datapath. The 24x24 product is formed as
    four 12x12 partial products hh, hl, lh, ll, each aligned and truncated as its own window term."""
    sa, ma, ea, spa = dec(a, 8, 23, 127)
    sb, mb, eb, spb = dec(b, 8, 23, 127)
    sc, mc, ec, spc = dec(c, 8, 23, 127)
    terms = []
    if ma and mb:                                   # all four set the anchor, even a zero partial product
        ap = (ea + 23) + (eb + 23)
        ahi, alo, bhi, blo = ma >> 12, ma & 0xFFF, mb >> 12, mb & 0xFFF
        for x, anc in ((ahi * bhi, ap), (ahi * blo, ap - 12), (alo * bhi, ap - 12), (alo * blo, ap - 24)):
            terms.append((sa ^ sb, x, anc - 22, anc))
    if mc:
        terms.append((sc, mc, ec, ec + 23))
    return window_sum(terms, spa or spb or spc)


def window_sum(terms, special, trace=None):
    """Align the terms (sign, magnitude, lsb exponent, anchor) to the largest anchor in the 27-bit window,
    sum, normalise and truncate to FP32."""
    if special:
        return QNAN
    if not terms:
        return 0
    emax = max(t[3] for t in terms)
    acc = 0
    for s, x, ex, _ in terms:
        sh = ex - emax + WIN_FRAC
        al = x << sh if sh >= 0 else x >> -sh       # truncation toward zero on the magnitude
        assert al < 1 << 27, (s, x, ex, emax)
        acc += -al if s else al
    if trace is not None:
        trace.update(emax=emax, acc=acc, nterms=len(terms))
    if acc == 0:
        return 0
    sign = 1 if acc < 0 else 0
    mag = abs(acc)
    assert mag < 1 << 33
    lz = 32 - (mag.bit_length() - 1)
    exp = emax + 134 - lz
    if exp >= 1:
        sh = lz
    elif emax + 133 >= 0:
        sh, exp = emax + 133, 0
    else:
        return 0
    if exp >= 255:
        return (sign << 31) | 0x7F800000
    m = ((mag << sh) >> 9) & 0xFFFFFF
    return (sign << 31) | (exp << 23) | (m & 0x7FFFFF)


# ------------------------------------------------------------------ helpers for tests
def f32_to_bits(x):
    import struct
    return struct.unpack("<I", struct.pack("<f", x))[0]


def bits_to_f32(u):
    import struct
    return struct.unpack("<f", struct.pack("<I", u))[0]


def value(fmt, a, b, sa, sb, c, a_e5m2=False, b_e5m2=False):
    """Exact real value of the dot product (for checking the model itself)."""
    from fractions import Fraction as F
    tot = F(0)
    if fmt in (NVFP4, MXFP4):
        ea, eb_ = elements(a, fmt), elements(b, fmt)
        for i in range(64):
            ma, xa, _ = scale(bits(sa, 8 * (i // 16), 8), fmt)
            mb, xb, _ = scale(bits(sb, 8 * (i // 16), 8), fmt)
            p = F(ea[i][1] * eb_[i][1] * ma * mb) * F(2) ** (xa + xb - 2)
            tot += -p if ea[i][0] ^ eb_[i][0] else p
    else:
        for (s1, m1, e1, _, _), (s2, m2, e2, _, _) in zip(elements(a, fmt, a_e5m2), elements(b, fmt, b_e5m2)):
            p = F(m1 * m2) * F(2) ** (e1 + e2)
            tot += -p if s1 ^ s2 else p
    cs, cm, ce, _ = dec(c, 8, 23, 127)
    tot += (-1 if cs else 1) * F(cm) * F(2) ** ce
    return tot
