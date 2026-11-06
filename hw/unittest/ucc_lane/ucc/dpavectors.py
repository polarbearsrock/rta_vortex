"""Vectors for the UCC FU's DPA-16 (``dpa``): streams of operations (op, rm, a, b, c, d), as ``fuvectors``' are, with
a and b of ``dpa.OPERAND`` bits.

``dpa_ops`` is DPA-16 alone, one operation per cycle, the format changing from one to the next: directed operations
that find every element's place in each format (one nonzero product at a time, and all of them), then operations
whose elements mix values near 1.0 with zeros, subnormals, both ends of the range and specials, exact cancellations,
sparse vectors, raw random bits, and block scales across their range. Every bit an operation ignores is random:
TF32's low 13 bits, the block scales outside NVFP4, MXFP4 and MXFP8's byte 0, the FP8 subtype bits outside FP8 and
MXFP8, c's upper word.
``mixed`` puts DPA-16 among the other units' operations so that its result meets each of theirs in the same cycle.

``check`` cross-checks a DPA-16 result against the exact dot product, from its own decoding of the elements: the
result must be the canonical NaN when an active input is a NaN or an infinity, and otherwise within the window's
truncation of the exact value, n terms times the window's LSB, 2^(emax - 25), plus the FP32 result's own truncation
(one ulp); when no term loses a bit to the window it must be exactly the exact value truncated to FP32 (with the
overflow to infinity and the subnormal limit of TransDot's numerics).
"""

from fractions import Fraction

from . import dpa, opcodes
from .opcodes import M32, dpa_op

DPA_SEED = 0x55434336_44504131
DPA_RANDOM = 3000  # random operations per format, besides the directed ones
DPA_MIXED_SEED = 0x55434336_44504D58
DPA_MIXED = 30000
DPA_OPERAND = dpa.OPERAND
FP16, BF16, TF32, FP8, NVFP4, MXFP4, MXFP8, FP4 = range(len(dpa.FORMATS))
LANES = {FP16: 16, BF16: 16, TF32: 8, FP8: 32, NVFP4: 64, MXFP4: 64, MXFP8: 32, FP4: 64}
BITS = {FP16: 16, BF16: 16, TF32: 32, FP8: 8, NVFP4: 4, MXFP4: 4, MXFP8: 8, FP4: 4}
EIGHT = (FP8, MXFP8)            # FP8 elements, E4M3 or E5M2 per side
E2M1 = (NVFP4, MXFP4, FP4)      # E2M1 elements, in four blocks of 16
SCALED = (NVFP4, MXFP4, MXFP8)  # the formats that read block scales (MXFP8 byte 0 only)
E2M1_K = (0, 1, 2, 3, 4, 6, 8, 12)  # E2M1 magnitudes, twice the value
WIN_FRAC = 25
BUBBLE = (None, 0, 0, 0, 0, None)


# ---------------------------------------------------------------------------
# Element encodings: (exponent bits, mantissa bits, bias), E4M3 has no infinity and one NaN pattern per sign
# ---------------------------------------------------------------------------


def layout(fmt, e5m2=False):
    if fmt == FP16:
        return 5, 10, 15
    if fmt == BF16:
        return 8, 7, 127
    if fmt == TF32:
        return 8, 10, 127
    if fmt in EIGHT:
        return (5, 2, 15) if e5m2 else (4, 3, 7)
    raise ValueError(fmt)


def element(rng, fmt, cls, e5m2=False):
    """One element's bits (FP4: an E2M1 code) of class cls: one, any, small, tiny, large, zero, special or raw. A tiny
    element of an 8-bit-exponent format is near 2^-64, so that products land near FP32's subnormals; in the narrower
    formats it is a small one."""
    if fmt in E2M1:
        if cls in ("raw", "any", "large", "special"):
            return rng.getrandbits(4)
        if cls == "zero":
            return rng.getrandbits(1) << 3
        if cls in ("small", "tiny"):
            return rng.getrandbits(1) << 3 | rng.choice((0, 1))
        return rng.getrandbits(1) << 3 | rng.choice((1, 2, 3))  # one: 0.5, 1, 1.5
    eb, mb, bias = layout(fmt, e5m2)
    if cls == "tiny":
        if eb < 8:
            cls = "small"
        else:
            x = rng.getrandbits(1) << eb + mb | rng.randint(bias - 72, bias - 56) << mb | rng.getrandbits(mb)
            return x << 13 | rng.getrandbits(13) if fmt == TF32 else x
    top = (1 << eb) - 1
    e4m3 = fmt in EIGHT and not e5m2
    s = rng.getrandbits(1)
    if cls == "raw":
        x = rng.getrandbits(1 + eb + mb)
    elif cls == "zero":
        x = s << eb + mb
    elif cls == "special":
        x = s << eb + mb | top << mb | (((1 << mb) - 1) if e4m3 else rng.getrandbits(mb))
    else:
        hi = top if e4m3 else top - 1  # E4M3's top binade is normal, but for its last code
        e = {"one": lambda: min(max(bias + rng.randint(-2, 2), 1), hi),
             "any": lambda: rng.randint(1, hi),
             "small": lambda: rng.randint(0, min(3, hi)),
             "large": lambda: rng.randint(max(hi - 3, 1), hi)}[cls]()
        m = rng.getrandbits(mb)
        if e == 0 and cls == "small":
            m = m or 1
        if e4m3 and e == top and m == (1 << mb) - 1:
            m -= 1
        x = s << eb + mb | e << mb | m
    if fmt == TF32:
        return x << 13 | rng.getrandbits(13)  # TF32 reads a container's bits 31-13
    return x


def scale(rng, fmt, cls):
    """A block scale byte: UE4M3 for NVFP4 (bit 7 ignored), E8M0 for MXFP4 and MXFP8."""
    if fmt == NVFP4:
        junk = rng.getrandbits(1) << 7
        if cls == "special":
            return junk | 0x7F
        if cls == "zero":
            return junk
        if cls == "raw":
            return rng.getrandbits(8)
        if cls in ("small", "tiny"):
            return junk | rng.randint(0, 0x0F)
        if cls == "large":
            return junk | rng.randint(0x70, 0x7E)
        return junk | (rng.randint(5, 9) << 3 | rng.getrandbits(3))  # around 1.0 (0x38)
    if cls == "special":
        return 0xFF
    if cls == "raw":
        return rng.getrandbits(8)
    if cls == "small":
        return rng.randint(0, 8)
    if cls == "tiny":  # two scales near 2^-64 put a block near FP32's subnormals
        return rng.randint(56, 72)
    if cls == "large":
        return rng.randint(246, 254)
    return 127 + rng.randint(-4, 4)


def c_value(rng, cls):
    """An FP32 addend of class cls, under a random upper word."""
    s = rng.getrandbits(1) << 31
    if cls == "zero":
        x = s
    elif cls == "special":
        x = s | 0xFF << 23 | rng.getrandbits(23)
    elif cls == "small":
        x = s | rng.randint(0, 3) << 23 | (rng.getrandbits(23) or 1)
    elif cls == "large":
        x = s | rng.randint(240, 254) << 23 | rng.getrandbits(23)
    elif cls == "raw":
        x = rng.getrandbits(32)
    else:
        x = s | (127 + rng.randint(-8, 8)) << 23 | rng.getrandbits(23)
    return rng.getrandbits(32) << 32 | x


def pack(fmt, elems):
    return sum(x << BITS[fmt] * i for i, x in enumerate(elems))


def operand(rng, fmt, elems, scales=None):
    """An FU operand: the vector, and the block scales above it (random where the format ignores them)."""
    s = sum(x << 8 * i for i, x in enumerate(scales)) if scales is not None else rng.getrandbits(32)
    return s << dpa.VECTOR | pack(fmt, elems)


def subtype_rm(rng, a_e5m2, b_e5m2):
    """The rounding-mode input: bits 0 and 1 are the FP8 subtypes, bit 2 is ignored."""
    return rng.getrandbits(1) << 2 | b_e5m2 << 1 | a_e5m2


def row(fmt, rm, a, b, c):
    op = dpa_op(fmt)
    return op, rm, a, b, c, opcodes.evaluate(op, rm, a, b, c)


# ---------------------------------------------------------------------------
# Independent cross-check
# ---------------------------------------------------------------------------


def decode(fmt, x, e5m2=False):
    """An element's (sign, significand, lsb exponent, width, special); E2M1: (sign, k, -1, 4, False)."""
    if fmt in E2M1:
        return x >> 3 & 1, E2M1_K[x & 7], -1, 4, False
    if fmt == TF32:
        x >>= 13
    eb, mb, bias = layout(fmt, e5m2)
    s, e, m = x >> eb + mb & 1, x >> mb & (1 << eb) - 1, x & (1 << mb) - 1
    special = (x & (1 << eb + mb) - 1) == (1 << eb + mb) - 1 if fmt in EIGHT and not e5m2 else e == (1 << eb) - 1
    sig = (1 << mb | m) if e else m
    return s, sig, (e or 1) - bias - mb, mb + 1, special


def decode_scale(fmt, x):
    """A block scale's (significand, lsb exponent, special)."""
    if fmt == NVFP4:
        x &= 0x7F
        e, m = x >> 3, x & 7
        return (8 | m) if e else m, (e or 1) - 7 - 3, x == 0x7F
    return 8, x - 127 - 3, x == 0xFF


def terms(fmt, rm, a, b, c):
    """The dot product's terms, (exact value, anchor), and whether an active input is special."""
    (va, sa), (vb, sb) = dpa.split(a), dpa.split(b)
    n, w = LANES[fmt], BITS[fmt]
    ea = [decode(fmt, va >> w * i & (1 << w) - 1, bool(rm & 1)) for i in range(n)]
    eb = [decode(fmt, vb >> w * i & (1 << w) - 1, bool(rm & 2)) for i in range(n)]
    out, special = [], False
    if fmt in E2M1:
        for blk in range(4):
            if fmt == FP4:  # no scales: E8M0 2^0
                (ma, xa, spa), (mb, xb, spb) = decode_scale(MXFP4, 127), decode_scale(MXFP4, 127)
            else:
                ma, xa, spa = decode_scale(fmt, sa >> 8 * blk & 0xFF)
                mb, xb, spb = decode_scale(fmt, sb >> 8 * blk & 0xFF)
            special |= spa or spb
            prods = [(-1) ** (x[0] ^ y[0]) * x[1] * y[1] for x, y in zip(ea[16 * blk:16 * blk + 16],
                                                                        eb[16 * blk:16 * blk + 16])]
            if any(prods) and ma * mb:
                ex = xa + xb - 2
                out.append((Fraction(sum(prods) * ma * mb) * Fraction(2) ** ex, ex + 18))
    else:
        off = 0
        if fmt == MXFP8:  # one E8M0 scale per side, byte 0: 2^(x - 127), 0xFF NaN
            xa, xb = sa & 0xFF, sb & 0xFF
            special |= xa == 0xFF or xb == 0xFF
            off = xa - 127 + xb - 127
        for (s1, m1, e1, w1, sp1), (s2, m2, e2, w2, sp2) in zip(ea, eb):
            special |= sp1 or sp2
            if m1 and m2:
                out.append(((-1) ** (s1 ^ s2) * Fraction(m1 * m2) * Fraction(2) ** (e1 + e2 + off),
                            e1 + e2 + off + (w1 - 1) + (w2 - 1)))
    cx = c & M32
    ce, cm = cx >> 23 & 0xFF, cx & 0x7FFFFF
    special |= ce == 0xFF
    sig = (1 << 23 | cm) if ce else cm
    if sig:
        out.append(((-1) ** (cx >> 31) * Fraction(sig) * Fraction(2) ** ((ce or 1) - 127 - 23), (ce or 1) - 127))
    return out, special


def log2_floor(x):
    e = x.numerator.bit_length() - x.denominator.bit_length()
    return e - 1 if x < Fraction(2) ** e else e


def truncate32(v, emax):
    """v truncated to FP32 as TransDot's normaliser does: toward zero, infinity from 2^128, and subnormal results only
    while its shift allows (emax + 133 >= 0), else 0."""
    if v == 0:
        return 0
    sign, mag = (1 << 31 if v < 0 else 0), abs(v)
    e = log2_floor(mag)
    if e >= 128:
        return sign | 0x7F800000
    if e >= -126:
        m = int(mag / Fraction(2) ** (e - 23))
        return sign | (e + 127) << 23 | m - (1 << 23)
    if emax + 133 < 0:
        return 0
    m = int(mag / Fraction(2) ** -149)
    return sign | m if m else 0


def value32(x):
    e, m = x >> 23 & 0xFF, x & 0x7FFFFF
    v = Fraction((1 << 23 | m) if e else m) * Fraction(2) ** ((e or 1) - 150)
    return -v if x >> 31 else v


def check(op, rm, a, b, c, d):
    """Cross-check DPA-16 result d against the exact dot product; return how ("nan", "zero", "exact" or "bound")."""
    fmt = (op & opcodes.FUNC) - opcodes.DPA_FUNC
    where = (opcodes.name(op), rm, f"{a:072x}", f"{b:072x}", f"{c:016x}", f"{d:016x}")
    assert d >> 32 == M32, where
    r = d & M32
    out, special = terms(fmt, rm, a, b, c)
    if special:
        assert r == dpa.QNAN, where
        return "nan"
    if not out:
        assert r == 0, where
        return "zero"
    emax = max(anchor for _, anchor in out)
    lsb = Fraction(2) ** (emax - WIN_FRAC)
    exact = sum(v for v, _ in out)
    if all((v / lsb).denominator == 1 for v, _ in out):
        assert r == truncate32(exact, emax), (*where, f"{truncate32(exact, emax):08x}")
        return "exact"
    slack = len(out) * lsb
    if r & 0x7FFFFFFF == 0x7F800000:
        assert abs(exact) > Fraction(2) ** 128 - slack, where
    elif r & 0x7FFFFFFF == 0:
        assert abs(exact) < slack + Fraction(2) ** -149 or emax + 133 < 0, where
    else:
        ulp = Fraction(2) ** (max(r >> 23 & 0xFF, 1) - 150)
        assert abs(exact - value32(r)) < ulp + slack, where
        if abs(exact) > slack:
            assert (r >> 31) == (exact < 0), where
    return "bound"


# ---------------------------------------------------------------------------
# Streams
# ---------------------------------------------------------------------------

KINDS = dict(near_one=12, mixed=20, spread=12, sparse=10, cancel=10, subnormal=8, tiny=8, extremes=5, special=6,
             raw=9)
CLASSES = dict(
    near_one=dict(one=1),
    mixed=dict(one=40, any=20, small=15, zero=15, large=10),
    spread=dict(one=25, any=50, small=25),
    sparse=dict(zero=85, one=15),
    cancel=dict(one=60, any=40),
    subnormal=dict(small=70, one=30),
    tiny=dict(tiny=80, zero=20),
    extremes=dict(large=60, one=20, small=20),
    special=dict(one=40, any=20, small=15, zero=15, large=10),
    raw=dict(raw=1),
)
C_CLASSES = dict(zero=25, one=30, raw=15, small=12, large=12, special=1)


def pick(rng, weights):
    return rng.choices(tuple(weights), tuple(weights.values()))[0]


def random_row(rng, fmt, kind):
    """A random DPA-16 operation of the given kind in format fmt."""
    n = LANES[fmt]
    a_e5m2, b_e5m2 = (rng.getrandbits(1), rng.getrandbits(1)) if fmt in EIGHT else (0, 0)
    rm = subtype_rm(rng, a_e5m2, b_e5m2) if fmt in EIGHT else rng.getrandbits(3)
    classes = CLASSES[kind]
    ea = [element(rng, fmt, pick(rng, classes), bool(a_e5m2)) for _ in range(n)]
    eb = [element(rng, fmt, pick(rng, classes), bool(b_e5m2)) for _ in range(n)]
    if kind == "cancel":  # the second half's products negate the first half's
        half = n // 2
        sign = 1 << BITS[fmt] - 1
        ea[half:] = ea[:half]
        eb[half:] = [x ^ sign for x in eb[:half]]
    sa = sb = None
    if fmt in SCALED:
        sclass = {"special": "one", "extremes": "large", "subnormal": "small", "tiny": "tiny",
                  "raw": "raw"}.get(kind, "one")
        sa = [scale(rng, fmt, sclass if rng.random() < 0.8 else pick(rng, dict(one=3, raw=2, small=1, large=1)))
              for _ in range(4)]
        sb = [scale(rng, fmt, sclass if rng.random() < 0.8 else pick(rng, dict(one=3, raw=2, small=1, large=1)))
              for _ in range(4)]
        if fmt == MXFP8:  # one scale per side, byte 0: the other three are ignored, so random
            sa[1:] = [rng.getrandbits(8) for _ in range(3)]
            sb[1:] = [rng.getrandbits(8) for _ in range(3)]
    cclass = pick(rng, C_CLASSES) if kind != "tiny" else pick(rng, dict(zero=2, small=1))
    if kind == "special":  # one active special: an element, c, or a block scale
        where = rng.choice(("a", "b", "c", "s") if sa is not None else ("a", "b", "c"))
        if fmt == FP4:  # neither E2M1 nor FP4's absent scales have one
            where = "c"
        if where == "c":
            cclass = "special"
        elif where == "s":
            blk = 0 if fmt == MXFP8 else rng.randrange(4)
            (sa if rng.getrandbits(1) else sb)[blk] = scale(rng, fmt, "special")
        elif fmt in (NVFP4, MXFP4):  # E2M1 has no specials
            sa[rng.randrange(4)] = scale(rng, fmt, "special")
        else:
            side, sub = (ea, a_e5m2) if where == "a" else (eb, b_e5m2)
            side[rng.randrange(n)] = element(rng, fmt, "special", bool(sub))
    elif cclass == "special":
        cclass = "one"
    a, b = operand(rng, fmt, ea, sa), operand(rng, fmt, eb, sb)
    return row(fmt, rm, a, b, c_value(rng, cclass))


def directed(rng):
    """Every format (and FP8 subtype pair): all products 1.0, so the result is the lane count, plus c = 1 and c = -1;
    then each lane alone, its value naming it."""
    ops = []
    for fmt in range(len(dpa.FORMATS)):
        n = LANES[fmt]
        for sub in ((0, 0), (1, 0), (0, 1), (1, 1)) if fmt in EIGHT else ((0, 0),):
            if fmt in E2M1:
                one_a = one_b = 2  # E2M1 1.0
                units = {NVFP4: [0x38] * 4, MXFP4: [127] * 4}.get(fmt)  # unit scales; FP4 reads none
            else:
                one_a, one_b = ((layout(fmt, bool(e))[2] << layout(fmt, bool(e))[1]) << (13 if fmt == TF32 else 0)
                                for e in sub)
                units = [127, *(rng.getrandbits(8) for _ in range(3))] if fmt == MXFP8 else None
            for c in (0, 0x3F800000, 0xBF800000):
                a = operand(rng, fmt, [one_a] * n, units)
                b = operand(rng, fmt, [one_b] * n, units)
                ops.append(row(fmt, subtype_rm(rng, *sub), a, b, rng.getrandbits(32) << 32 | c))
            if sub not in ((0, 0), (1, 1)):
                continue
            for lane in range(n):
                va, vb = [0] * n, [0] * n
                if fmt in E2M1:
                    va[lane] = vb[lane] = lane % 7 + 1  # E2M1 codes 1-7: 0.5 to 6
                else:
                    eb_, mb, bias = layout(fmt, bool(sub[0]))
                    x = (bias + lane % 3) << mb | lane * 0x9E37 & (1 << mb) - 1
                    va[lane], vb[lane] = x << (13 if fmt == TF32 else 0), one_b
                a, b = operand(rng, fmt, va, units), operand(rng, fmt, vb, units)
                ops.append(row(fmt, subtype_rm(rng, *sub), a, b, rng.getrandbits(32) << 32))
    return ops + mx_directed()


MX_ONES = sum(0x38 << 8 * i for i in range(32))  # 32 x E4M3 1.0
MX_JUNK = 0xA5C3E1 << 8  # bytes 1-3 of an MXFP8 scale word, which nothing reads
MX_SWEEP = (0, 1, 2, 8, 64, 100, 126, 127, 128, 200, 247, 248, 249, 250, 254)
MX_FLOOR = (-131, -132, -133, -134, -135)  # soff around TransDot's subnormal limit (emax + 133 >= 0) with c = 0


def mx_directed():
    """MXFP8's scales on their own, without random bits (so the random stream after them is unchanged): a NaN scale
    (0xFF) on one side or both, with and without nonzero terms, and 0xFF only in the bytes nothing reads; one scale
    swept across its range against 2^0 (32 products of 1.0: 2^(k - 122)); soff at both ends; overflow by the scaled
    products alone and by their sum with c, and the same sum cancelling; and soff around the subnormal limit."""
    ops = []

    def add(sa, va, sb, vb, c, rm=0):
        junk = lambda s: s if s > 0xFF else MX_JUNK | s  # noqa: E731
        ops.append(row(MXFP8, rm, junk(sa) << dpa.VECTOR | va, junk(sb) << dpa.VECTOR | vb, 0x5A5A5A5A << 32 | c))

    for sa, va, sb, vb, c, rm in (
        (0xFF, MX_ONES, 0xFF, MX_ONES, 0, 0), (0x7F7F7FFF, 0, 0x7F7F7FFF, 0, 0x3F800000, 3),
        (0xFF, MX_ONES, 0xFE, MX_ONES, 0, 0),  # the NaN wins over an overflow
        (0xFF, 0, 0x7F, 0, 0, 0), (0x7F, 0, 0xFF, 0, 0, 0),  # NaN with no nonzero term
        (0xFF, 0, 0x7F, MX_ONES, 0x3F800000, 0), (0x7F, MX_ONES, 0xFF, 0, 0x3F800000, 0),
        (0xFFFFFF7F, 0, 0xFFFFFF00, 0, 0, 0), (0xFFFFFF7F, MX_ONES, 0xFFFFFF7F, MX_ONES, 0, 0),  # 0xFF unread: no NaN
    ):
        add(sa, va, sb, vb, c, rm)
    for k in MX_SWEEP:
        add(k, MX_ONES, 0x7F, MX_ONES, 0)
        add(0x7F, MX_ONES, k, MX_ONES, 0)
    for sa, va, sb, vb, c in (
        (0xFE, MX_ONES, 0xFE, MX_ONES, 0), (0xFE, MX_ONES, 0xFE, 0, 0x7F7FFFFF), (0xFE, 0, 0xFE, MX_ONES, 0xFF7FFFFF),
        (0x00, MX_ONES, 0x00, MX_ONES, 0), (0x00, MX_ONES, 0x00, MX_ONES, 0x00800000),
        (0xFE, MX_ONES, 0x7A, MX_ONES, 0x7F000000), (0xFE, MX_ONES, 0x7A, MX_ONES, 0xFF000000),
    ):
        add(sa, va, sb, vb, c)
    for s in MX_FLOOR:
        add(0, MX_ONES, 254 + s, MX_ONES, 0)
    return ops


def dpa_ops(rng):
    """The DPA-16 stream and its kinds: the directed operations, then DPA_RANDOM random ones per format, shuffled so
    that the format changes from one operation to the next."""
    ops = directed(rng)
    kinds = dict(directed=len(ops))
    rand = []
    for fmt in range(len(dpa.FORMATS)):
        for _ in range(DPA_RANDOM):
            kind = pick(rng, KINDS)
            kinds[kind] = kinds.get(kind, 0) + 1
            rand.append(random_row(rng, fmt, kind))
    rng.shuffle(rand)
    return ops + rand, kinds


def widen(rng, op):
    """An operation of another unit with random bits above a's and b's bit 63, which only DPA-16 reads."""
    if op[0] is None or opcodes.unit(op[0]) == "dpa":
        return op
    hi = DPA_OPERAND - 64
    return (op[0], op[1], op[2] | rng.getrandbits(hi) << 64, op[3] | rng.getrandbits(hi) << 64, *op[4:])


def mixed(pools, rng):
    """DPA_MIXED cycles of DPA-16 among the other units' operations (pools: a list per unit), with bubbles, settled
    (``opcodes.settle``): DPA-16's result meets the bypassed ALU and compare results, multiplies, conversions, FMAs and
    SFU functions in the same cycle."""
    weights = dict(dpa=40, fma=14, sfu=10, alu=8, imul=6, cmp=6, cvt=6, bubble=7)
    ops = []
    for _ in range(DPA_MIXED):
        kind = pick(rng, weights)
        ops.append(BUBBLE if kind == "bubble" else widen(rng, rng.choice(pools[kind])))
    return opcodes.settle(ops)
