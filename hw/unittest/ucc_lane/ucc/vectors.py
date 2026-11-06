"""The UCC regression's vectors and their exact expected results, without the
simulator: the multiplier's operands, the FP64 lane vectors (exactly those
validated before the baseline synthesis), the FP32 vectors and their
operations, the SFU inputs, the INT32 operations, and the FU's
streams of operations (``opcodes``), these, ``fuvectors``' for the other
operations and ``dpavectors``' for DPA-16. ``verify`` simulates them; synthesis
runs validate their preprocessed RTL with them.
"""

import ctypes
import hashlib
import random
import struct

from . import dpavectors, fuvectors, intops, opcodes, sfu
from .models import FP32, FP64, fma, libm_fma
from .opcodes import BOX, fp

SEED = 0x55434336_34464D41
MUL_SEED = 0x55434336_4D554C35
FP32_SEED = 0x55434336_46503332
MIXED_SEED = 0x55434336_4D495844
MIXED = 40000
SFU_SEED = 0x55434336_53465530
SFU_RANDOM = 6000  # random inputs per function, besides the directed ones
SFU_MIXED_SEED = 0x55434336_53464D58
SFU_MIXED = 40000
INT_SEED = 0x55434336_494E5433
INT_RANDOM = 1200  # random operands per INT32 code, besides the directed ones
INT_MIXED_SEED = 0x55434336_494E544D
INT_MIXED = 40000
LATENCY = 3  # the FMA's, in the baseline lanes too
RESET_CYCLES = 4
# SHA-256 of the vectors file ("a b c d" in hex, one FMA per line) validated
# before the baseline synthesis.
BASELINE_VECTORS_SHA256 = (
    "41e2d301986db7eb5b40192789495e0a876287c2527ec469fbd8f846b34e2fca"
)
ONE = 0x3FF0000000000000
MAN = (1 << 52) - 1
ONE32 = 0x3F800000
MAN32 = (1 << 23) - 1
M53 = (1 << 53) - 1
M24 = (1 << 24) - 1


def booth_low(b):
    """The value of Booth digits 0-13 of ``b``, the rows of the replaced Booth multiplier that multiplied a_lo."""
    return (b & (1 << 28) - 1) - ((b >> 27 & 1) << 28)


def signed53(x):
    return x - (1 << 53) if x >> 52 else x


def mul53(a_lo, a_hi, b, signed=False, a_signed=False):
    """The replaced Booth multiplier's (ucc_mul53's) definition: rows 0-13 multiplied a_lo, rows 14-26 a_hi; b
    two's complement when ``signed``, a_lo and a_hi when ``a_signed``. The tiled product must give what it gave."""
    low = booth_low(b)
    if signed:
        b = signed53(b)
    if a_signed:
        a_lo, a_hi = signed53(a_lo), signed53(a_hi)
    return (a_lo * low + a_hi * (b - low)) % (1 << 106)


def tilemul(a, b, sfu=False, a_signed=False, b_signed=False):
    """The FU's tiled product (ucc_tiles and ucc_tilemul) for any 53-bit a and b, modulo 2^106: a * b, less 2^53 times
    the other operand for each signed operand whose sign bit is set; in the SFU the two cross products at 2^24, the a
    strip, and its sign corrections."""
    lo_a, lo_b, mid_a = a & M24, b & M24, a >> 24 & M24
    if sfu:
        p = ((lo_a * (b >> 24) + mid_a * lo_b) * 2 ** 24 + (a >> 48) * b * 2 ** 48
             - (b >> 50 & 1) * lo_a * 2 ** 51 - (b >> 23 & 1) * mid_a * 2 ** 48)
    else:
        p = a * b - (a_signed and a >> 52) * b * 2 ** 53 - (b_signed and b >> 52) * a * 2 ** 53
    return p % (1 << 106)


# mul_vectors kinds that set a_signed_i and b_signed_i. The int kinds are 32-bit integers at bits 52-21.
INT_KINDS = ("int", "int_a", "int_b", "int_ab")
A_SIGNED_KINDS = ("int_a", "int_ab")
B_SIGNED_KINDS = ("int_b", "int_ab")
INT_CORNERS = (0, 1, 2, 3, 31, 32, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF,
               0x55555555, 0xAAAAAAAA, 0x0000FFFF, 0xFFFF0000, 0x12345678)


def sfu_operands(a1, a2, xl):
    """ucc_sfu's multiplier operands for one table entry's a1, a2 and xl: a = sq * 2^24 + xl * 2^4 and
    b = a1 * 2^24 + a2 * 2^4, a1 and a2 two's complement (27 and 20 bits), sq = xl^2 truncated to 18 bits."""
    return (xl * xl >> 18) << 24 | xl << 4, (a1 % (1 << 27)) << 24 | (a2 % (1 << 20)) << 4


def booth_sfu_operands(a1, a2, xl):
    """The operands the SFU gave the replaced Booth multiplier: (a_lo, a_hi, b)."""
    return xl << 28, xl * xl >> 18, ((a2 << 28) + a1) % (1 << 53)


def mul_vectors(rng):
    """(kind, a, b, sfu, a_signed, b_signed, p) rows for the tiled product: FP64 products, FP32 products (the
    significands at bits 23-0), the SFU's (every table entry, its own layout), INT32 products (each signedness), and
    arbitrary operands in each mode. Every product but the arbitrary ones is also checked against what it stands for
    and against the replaced Booth multiplier's result for the same operation."""
    rows, kinds = [], {}

    def add(kind, a, b, sfu_mode=False, a_signed=False, b_signed=False):
        rows.append((kind, a, b, sfu_mode, a_signed, b_signed, tilemul(a, b, sfu_mode, a_signed, b_signed)))
        kinds[kind] = kinds.get(kind, 0) + 1

    def significand(bits):
        x = rng.getrandbits(bits)
        return x | 1 << bits - 1 if rng.getrandbits(1) else x

    corners53 = [
        0, 1, 2, 3, 1 << 26, 3 << 27, 1 << 52, 1 << 52 | 1, M53 >> 1, M53,
        0x0AAAAAAAAAAAAA, 0x15555555555555, 0x1AAAAAAAAAAAAA,
        *(((1 << 12) - 1) << 12 * k for k in range(4)), 0x1F << 48, M53 ^ (0x1F << 48),
    ]
    for a in corners53:
        for b in corners53:
            add("fp64", a, b)
    for _ in range(40000):
        add("fp64", significand(53), significand(53))
    corners24 = [0, 1, 2, 1 << 23, 1 << 23 | 1, M24 >> 1, M24, 0x555555, 0xAAAAAA]
    for a in corners24:
        for b in corners24:
            add("fp32", a, b)
    for _ in range(30000):
        add("fp32", significand(24), significand(24))
    entries, _ = sfu.table()
    sfu_rows = []
    for _, a1, a2 in entries:
        for xl in (0, 1, (1 << 18) - 1, *(rng.getrandbits(18) for _ in range(5))):
            sfu_rows.append((a1, a2, xl))
            add("sfu", *sfu_operands(a1, a2, xl), sfu_mode=True)
    for _ in range(5000):
        add("sfu_any", rng.getrandbits(53), rng.getrandbits(53), sfu_mode=True)
    shift = 53 - 32
    for kind in INT_KINDS:
        for x in INT_CORNERS:
            for y in INT_CORNERS:
                add(kind, x << shift, y << shift, a_signed=kind in A_SIGNED_KINDS, b_signed=kind in B_SIGNED_KINDS)
        for _ in range(3000):
            x, y = rng.getrandbits(32), rng.getrandbits(32)
            add(kind, x << shift, y << shift, a_signed=kind in A_SIGNED_KINDS, b_signed=kind in B_SIGNED_KINDS)
    for _ in range(5000):
        add("signed_any", rng.getrandbits(53), rng.getrandbits(53), a_signed=bool(rng.getrandbits(1)),
            b_signed=bool(rng.getrandbits(1)))
    sfu_index = 0
    for kind, a, b, sfu_mode, a_signed, b_signed, p in rows:
        if kind in ("fp64", "fp32"):
            assert p == a * b == mul53(a, a, b)
        elif kind == "sfu":
            a1, a2, xl = sfu_rows[sfu_index]
            sfu_index += 1
            assert p == (a1 * xl + a2 * (xl * xl >> 18) << 28) % (1 << 106)
            assert p == mul53(*booth_sfu_operands(a1, a2, xl), True)
        elif kind in INT_KINDS:
            x, y = a >> shift, b >> shift
            x = intops.signed(x) if a_signed else x
            y = intops.signed(y) if b_signed else y
            assert p == (x * y << 2 * shift) % (1 << 106)
            assert p == mul53(a, a, b, b_signed, a_signed)
    return rows, kinds


def fp64(rng, sign=None, exp=None):
    s = rng.getrandbits(1) if sign is None else sign
    e = rng.randrange(1, 2047) if exp is None else exp
    return s << 63 | e << 52 | rng.getrandbits(52)


def exponent(x):
    return x >> 52 & 0x7FF


def vectors(rng):
    """(kind, a, b, c) rows: all triples of 32 special encodings, then exact
    and near cancellation, overlapping and distant exponents, underflow,
    overflow, random encodings, and the MUL (c = -0) and ADD (a = 1.0) forms."""
    rows, kinds = [], {}

    def add(kind, a, b, c):
        rows.append((kind, a, b, c))
        kinds[kind] = kinds.get(kind, 0) + 1

    magnitudes = [
        0, ONE, 0x3FF8000000000000, 1, MAN, 1 << 52, 0x7FEFFFFFFFFFFFFF, FP64.inf,
        FP64.qnan, 0x7FF0000000000001, 0x5FF0000000000000, 0x1FF0000000000000,
        0x3FF5555555555555, 0x000FFFFFFFFFFFFE, 0x0010000000000001,
        0x7FE0000000000000,
    ]
    specials = magnitudes + [FP64.sign | m for m in magnitudes]
    for a in specials:
        for b in specials:
            for c in specials[::2] + specials[1::4]:
                add("special", a, b, c)
    for _ in range(12000):
        a = fp64(rng, exp=rng.randrange(700, 1350))
        b = fp64(rng, exp=rng.randrange(700, 1350))
        p = fma(FP64, a, b, 0)
        if exponent(p) == 0x7FF:
            continue
        near = (p ^ FP64.sign) + rng.randrange(-3, 4) & (1 << 64) - 1
        add("cancellation", a, b, near)
    for _ in range(20000):
        ea, eb = rng.randrange(400, 1650), rng.randrange(400, 1650)
        ec = min(2046, max(1, ea + eb - 1023 + rng.randrange(-60, 61)))
        add("overlap", fp64(rng, exp=ea), fp64(rng, exp=eb), fp64(rng, exp=ec))
    for _ in range(10000):
        ea, eb = rng.randrange(600, 1450), rng.randrange(600, 1450)
        gap = rng.choice((-1, 1)) * rng.randrange(100, 500)
        ec = ea + eb - 1023 + gap
        if 1 <= ec <= 2046:
            add("distant", fp64(rng, exp=ea), fp64(rng, exp=eb), fp64(rng, exp=ec))
    for _ in range(10000):
        ea = rng.randrange(1, 1023)
        eb = min(2046, max(1, 1023 - ea + rng.randrange(-80, 10)))
        c = rng.choice(
            (
                0,
                FP64.sign,
                rng.getrandbits(1) << 63 | rng.getrandbits(52),
                fp64(rng, exp=rng.randrange(1, 4)),
            )
        )
        add("underflow", fp64(rng, exp=ea), fp64(rng, exp=eb), c)
    for _ in range(5000):
        ea = rng.randrange(1024, 2047)
        eb = min(2046, max(1, 2046 + 1023 - ea + rng.randrange(-3, 3)))
        a, b = fp64(rng, exp=ea), fp64(rng, exp=eb)
        add("overflow", a, b, fp64(rng, exp=rng.randrange(1900, 2047)))
    for _ in range(30000):
        add("random", rng.getrandbits(64), rng.getrandbits(64), rng.getrandbits(64))
    for _ in range(5000):
        add("mul", fp64(rng), fp64(rng), FP64.sign)
    for _ in range(5000):
        b = fp64(rng)
        ec = min(2046, max(1, exponent(b) + rng.randrange(-60, 61)))
        add("add", ONE, b, fp64(rng, exp=ec))
    return rows, kinds


def fp32(rng, sign=None, exp=None):
    s = rng.getrandbits(1) if sign is None else sign
    e = rng.randrange(1, 255) if exp is None else exp
    return s << 31 | e << 23 | rng.getrandbits(23)


def exponent32(x):
    return x >> 23 & 0xFF


def vectors32(rng):
    """The FP64 generator's kinds in FP32 (p = 24): exponent ranges scaled to
    the format, overlap within its alignment window (-49 to 26) and distant
    gaps across both saturations. Then ties: products exactly halfway between
    two FP32 values, with c 20 to 80 binades below them; subnormal times
    normal products, with c up to 52 binades below them; and sums that need
    the 1-bit left normalization and land exactly halfway."""
    rows, kinds = [], {}

    def add(kind, a, b, c):
        rows.append((kind, a, b, c))
        kinds[kind] = kinds.get(kind, 0) + 1

    magnitudes = [
        0, ONE32, 0x3FC00000, 1, MAN32, 1 << 23, 0x7F7FFFFF, FP32.inf, FP32.qnan,
        0x7F800001, 0x5F800000, 0x1F800000, 0x3FAAAAAA, 0x007FFFFE, 0x00800001,
        0x7F000000,
    ]
    specials = magnitudes + [FP32.sign | m for m in magnitudes]
    for a in specials:
        for b in specials:
            for c in specials[::2] + specials[1::4]:
                add("special", a, b, c)
    for _ in range(12000):
        a = fp32(rng, exp=rng.randrange(64, 191))
        b = fp32(rng, exp=rng.randrange(64, 191))
        p = fma(FP32, a, b, 0)
        if exponent32(p) == 0xFF:
            continue
        near = (p ^ FP32.sign) + rng.randrange(-3, 4) & (1 << 32) - 1
        add("cancellation", a, b, near)
    for _ in range(20000):
        ea, eb = rng.randrange(40, 216), rng.randrange(40, 216)
        ec = min(254, max(1, ea + eb - 127 + rng.randrange(-30, 31)))
        add("overlap", fp32(rng, exp=ea), fp32(rng, exp=eb), fp32(rng, exp=ec))
    for _ in range(10000):
        ea, eb = rng.randrange(60, 196), rng.randrange(60, 196)
        gap = rng.choice((-1, 1)) * rng.randrange(20, 100)
        ec = ea + eb - 127 + gap
        if 1 <= ec <= 254:
            add("distant", fp32(rng, exp=ea), fp32(rng, exp=eb), fp32(rng, exp=ec))
    for _ in range(10000):
        ea = rng.randrange(1, 127)
        eb = min(254, max(1, 127 - ea + rng.randrange(-30, 10)))
        c = rng.choice(
            (
                0,
                FP32.sign,
                rng.getrandbits(1) << 31 | rng.getrandbits(23),
                fp32(rng, exp=rng.randrange(1, 4)),
            )
        )
        add("underflow", fp32(rng, exp=ea), fp32(rng, exp=eb), c)
    for _ in range(5000):
        ea = rng.randrange(128, 255)
        eb = min(254, max(1, 254 + 127 - ea + rng.randrange(-3, 3)))
        a, b = fp32(rng, exp=ea), fp32(rng, exp=eb)
        add("overflow", a, b, fp32(rng, exp=rng.randrange(230, 255)))
    for _ in range(12000):
        # The product is exactly halfway between two FP32 values and c is far
        # below it, so whether c counts as sticky decides the rounding.
        ta = rng.randrange(0, 24)
        tb = rng.choice((22, 23)) - ta
        if not 0 <= tb <= 23:
            continue
        ma, mb = (
            (rng.getrandbits(23 - t) << 1 | 1) << t | 1 << 23 if t < 23 else 1 << 23
            for t in (ta, tb)
        )
        p = ma * mb
        if p.bit_length() - 25 != ta + tb:
            continue
        ea, eb = rng.randrange(80, 176), rng.randrange(80, 176)
        a = rng.getrandbits(1) << 31 | ea << 23 | ma & MAN32
        b = rng.getrandbits(1) << 31 | eb << 23 | mb & MAN32
        ec = ea + eb - 127 + rng.randrange(-80, -19)
        m = rng.choice((0, 1 << rng.randrange(23), MAN32, rng.getrandbits(23)))
        c = rng.getrandbits(1) << 31 | (ec << 23 | m if ec >= 1 else m)
        add("tie", a, b, c)
    for _ in range(12000):
        # A subnormal times a normal: the product has leading zeros, so after
        # cancellation the round bit can fall to the frame's lowest bits. With
        # a = 2^-149 and c 24 to 27 binades below the product it can fall to
        # bit 0, where c's sticky bit decides the rounding.
        eb = rng.randrange(152, 255)
        if rng.getrandbits(1):
            sub = 1
            b = eb << 23 | rng.getrandbits(rng.randrange(1, 23))
            ec = eb - 126 - rng.randrange(24, 28)
        else:
            bits = rng.randrange(1, 4) if rng.getrandbits(1) else rng.randrange(1, 24)
            sub = (rng.getrandbits(bits - 1) << 1 | 1) << rng.randrange(24 - bits)
            b = eb << 23 | (0 if rng.getrandbits(1) else rng.getrandbits(23))
            ec = eb - 126 + rng.randrange(-52, 4)
        if not 1 <= ec <= 254:
            continue
        sub |= rng.getrandbits(1) << 31
        b |= rng.getrandbits(1) << 31
        a, b = (sub, b) if rng.getrandbits(1) else (b, sub)
        add("subnormal_product", a, b, fp32(rng, exp=ec))
    for _ in range(6000):
        # c = +-2^E minus an odd multiple of 2^(E-25): the sum needs the 1-bit
        # left normalization and is exactly halfway between two FP32 values,
        # so only an exact sticky bit gives the right rounding.
        ec = rng.randrange(30, 255)
        m = rng.getrandbits(rng.randrange(1, 25)) | 1
        ea = ec - 25 + m.bit_length() - 1 - rng.randrange(0, 20)
        eb = ec - 25 + m.bit_length() - 1 - ea + 127
        if not (1 <= ea <= 254 and 1 <= eb <= 254):
            continue
        sa = rng.getrandbits(1)
        a = sa << 31 | ea << 23 | m << 24 - m.bit_length() & MAN32
        b = eb << 23
        c = (sa ^ 1) << 31 | ec << 23
        a, b = (a, b) if rng.getrandbits(1) else (b, a)
        add("left_tie", a, b, c)
    for _ in range(30000):
        add("random", rng.getrandbits(32), rng.getrandbits(32), rng.getrandbits(32))
    for _ in range(5000):
        add("mul", fp32(rng), fp32(rng), FP32.sign)
    for _ in range(5000):
        b = fp32(rng)
        ec = min(254, max(1, exponent32(b) + rng.randrange(-30, 31)))
        add("add", ONE32, b, fp32(rng, exp=ec))
    return rows, kinds


def f64(x):
    return struct.unpack("<d", struct.pack("<Q", x))[0]


def pack_f64(x):
    return FP64.qnan if x != x else struct.unpack("<Q", struct.pack("<d", x))[0]


def f32(x):
    return struct.unpack("<f", struct.pack("<I", x))[0]


def pack_f32(x):
    """A double rounded to FP32 by C's conversion (nearest even; 53 >= 2*24 + 2
    bits, so rounding an exact product or sum to double first is harmless)."""
    if x != x:
        return FP32.qnan
    return struct.unpack("<I", struct.pack("<f", ctypes.c_float(x).value))[0]


def expected(rows, fmt=FP64):
    """(a, b, c, d) with exact results, each cross-checked independently."""
    real, pack = (f64, pack_f64) if fmt == FP64 else (f32, pack_f32)
    digits = fmt.width // 4
    out, checks = [], dict(libm_fma=0, mul_form=0, add_form=0)
    for kind, a, b, c in rows:
        d = fma(fmt, a, b, c)
        libm = libm_fma(fmt, a, b, c)
        operands = " ".join(f"{x:0{digits}x}" for x in (a, b, c))
        if libm is not None:
            assert libm == d, (kind, operands, f"{d:0{digits}x}")
            checks["libm_fma"] += 1
        if kind == "mul":
            assert pack(real(a) * real(b)) == d, (operands, f"{d:0{digits}x}")
            checks["mul_form"] += 1
        if kind == "add":
            assert pack(real(b) + real(c)) == d, (operands, f"{d:0{digits}x}")
            checks["add_form"] += 1
        out.append((a, b, c, d))
    return out, checks


def words32(results, rng):
    """The FP32 FMAs as 64-bit words: each operand in bits 31-0 under a random
    upper word, which the FU must ignore, and the result NaN-boxed."""
    return [
        (*(rng.getrandbits(32) << 32 | x for x in (a, b, c)), BOX | d)
        for a, b, c, d in results
    ]


def mixed(fp64_words, fp32_words, rng):
    """(words, modes): MIXED operations, each FP64 or FP32 at random."""
    words, modes = [], []
    for _ in range(MIXED):
        mode = rng.getrandbits(1)
        words.append(rng.choice(fp32_words if mode else fp64_words))
        modes.append(mode)
    return words, modes


def sfu_inputs(rng):
    """(kind, fn, x) per SFU operation: special and boundary encodings for
    every function, every table entry at the ends and inside of its interval,
    function-specific edges, and random encodings."""
    rows, kinds = [], {}

    def add(kind, fn, x):
        rows.append((kind, fn, x & 0xFFFFFFFF))
        kinds[kind] = kinds.get(kind, 0) + 1

    def enc(sign, e, m):
        return sign << 31 | e << 23 | m

    specials = [0, 1, 0x7FFFFF, 0x800000, 0x7F7FFFFF, 0x7F800000, 0x7F800001, 0x7FC00000, 0x3F800000]
    for fn in range(7):
        for x in specials:
            add("special", fn, x)
            add("special", fn, x | sfu.SIGN)
        for e in range(1, 255):
            for sign in (0, 1):
                add("binade", fn, enc(sign, e, 0))
                add("binade", fn, enc(sign, e, 0x7FFFFF))
        # every table entry: xl zero, all ones and random
        for idx in range(128):
            for low in (0, (1 << 16) - 1, rng.getrandbits(16)):
                if fn == sfu.RCP:
                    add("table", fn, enc(rng.getrandbits(1), rng.randrange(1, 254), idx << 16 | low))
                elif fn == sfu.RSQRT:
                    e = 127 + (idx >> 6) + 2 * rng.randrange(-60, 60)
                    add("table", fn, enc(0, e, (idx & 63) << 17 | low << 1 | rng.getrandbits(1)))
                elif fn == sfu.LG2 and idx < 64:
                    add("table", fn, enc(0, rng.randrange(1, 255), idx << 17 | low << 1 | rng.getrandbits(1)))
                elif fn == sfu.EX2 and idx < 64:
                    n = (idx << 18 | low << 2 | rng.getrandbits(2)) / 2.0**24 + rng.randrange(-125, 127)
                    add("table", fn, pack_f32(-n if rng.getrandbits(1) else n))
                elif fn in (sfu.SINPI, sfu.COSPI) and idx < 64:
                    t = idx << 18 | low << 2 | rng.getrandbits(2)
                    add("table", fn, pack_f32((t / 2.0**25 + rng.randrange(-4, 4)) * (-1) ** rng.getrandbits(1)))
                elif fn == sfu.TANH and idx < 64:
                    add("table", fn, enc(rng.getrandbits(1), 122 + (idx >> 3), (idx & 7) << 20 | low << 4))
        for _ in range(SFU_RANDOM):
            if rng.getrandbits(1):
                add("random", fn, rng.getrandbits(32))
            else:
                add("random", fn, enc(rng.getrandbits(1), rng.randrange(96, 160), rng.getrandbits(23)))
    for n in range(-160, 161):  # ex2 around integers, halves and its overflow / underflow ends
        for d in (0.0, 0.5, 2.0**-20, -(2.0**-20)):
            add("edge", sfu.EX2, pack_f32(n + d))
    for k in range(-16, 17):  # sinpi / cospi at quarter turns and around them, and far out
        for d in (0.0, 2.0**-22, -(2.0**-22)):
            for fn in (sfu.SINPI, sfu.COSPI):
                add("edge", fn, pack_f32(k / 4 + d))
    for e in range(150, 200):
        for fn in (sfu.SINPI, sfu.COSPI):
            add("edge", fn, enc(rng.getrandbits(1), e, rng.getrandbits(23)))
    for e in (120, 121, 122, 129, 130, 131):  # tanh's passthrough and saturation edges
        for _ in range(20):
            add("edge", sfu.TANH, enc(rng.getrandbits(1), e, rng.getrandbits(23)))
    for m in range(-40, 41):  # lg2 around 1
        add("edge", sfu.LG2, 0x3F800000 + m)
    return rows, kinds


def sfu_vectors(rng):
    """(fn, x, y) with the UCC's results; each one is within the Vortex MUFU
    regression's accuracy bound, and the summary counts how many equal
    Vortex's MUFU and by how many units in the last place the rest differ."""
    rows, kinds = sfu_inputs(rng)
    out, same, worst = [], 0, 0
    for kind, fn, x in rows:
        y = sfu.evaluate(fn, x)
        assert sfu.accurate(fn, x, y), (sfu.NAMES[fn], f"{x:08x}", f"{y:08x}")
        m = sfu.mufu(fn, x)
        same += y == m
        if y != m:
            worst = max(worst, abs((y & 0x7FFFFFFF) - (m & 0x7FFFFFFF)) if y >> 31 == m >> 31 else 1 << 31)
        out.append((fn, x, y))
    return out, dict(kinds=kinds, equal_to_vortex_mufu=same, largest_ulp_difference=worst)


def sfu_ops(rows, rng):
    """One SFU operation per cycle, (op, rm, a, b, c, d) as every stream of
    operations: a's upper word, b and c are random, which the FU must ignore,
    and the result is NaN-boxed."""
    return [
        (opcodes.sfu_op(fn), 0, rng.getrandbits(32) << 32 | x, rng.getrandbits(64), rng.getrandbits(64), BOX | y)
        for fn, x, y in rows
    ]


def mixed_all(fp64_words, fp32_words, sfu_rows, rng):
    """SFU_MIXED operations, each an FP64 FMA, an FP32 FMA or an SFU
    operation at random, settled: an FMA issued two cycles after an SFU
    operation is lost (d None); the stream issues it anyway."""
    ops = []
    for _ in range(SFU_MIXED):
        pick = rng.randrange(3)
        if pick == 2:
            fn, x, y = rng.choice(sfu_rows)
            ops.append((opcodes.sfu_op(fn), 0, rng.getrandbits(32) << 32 | x, rng.getrandbits(64),
                        rng.getrandbits(64), BOX | y))
            continue
        a, b, c, d = rng.choice(fp32_words if pick else fp64_words)
        ops.append((fp("FMA", pick == 1), 0, a, b, c, d))
    return opcodes.settle(ops)


def int_vectors(rng):
    """(op, a, b, c) for every INT32 code: the directed operands with each
    other, then INT_RANDOM random ones (a quarter each: any words, small
    shift-like b, a == b, and small magnitudes of either sign)."""
    rows = []
    small = [x & intops.M32 for x in range(-8, 9)]
    for op in range(intops.CODES):
        for a in INT_CORNERS:
            for b in INT_CORNERS:
                rows.append((op, a, b, rng.getrandbits(32)))
        for k in range(INT_RANDOM):
            a, b, c = rng.getrandbits(32), rng.getrandbits(32), rng.getrandbits(32)
            if k % 4 == 1:
                b = rng.getrandbits(27) << 5 | rng.randrange(32) if rng.getrandbits(1) else rng.randrange(40)
            elif k % 4 == 2:
                b = a
            elif k % 4 == 3:
                a, b = rng.choice(small), rng.choice(small)
            rows.append((op, a, b, c))
    return rows


def int_ops(rows, rng):
    """One INT32 operation per cycle (its code is its opcode), of bits 31-0:
    its operands' upper words are random, which the FU must ignore."""
    ops = []
    for op, a, b, c in rows:
        a, b, c = (rng.getrandbits(32) << 32 | x for x in (a, b, c))
        ops.append((op, 0, a, b, c, opcodes.evaluate(op, 0, a, b, c)))
    return ops


def mixed_int(fp64_words, fp32_words, sfu_rows, int_list, rng):
    """INT_MIXED operations, each an FP64 FMA, an FP32 FMA, an SFU
    operation or an INT32 operation at random, settled: an FMA or INT32
    operation issued two cycles after an SFU operation is lost, and when two
    results are due in the same cycle the older one is hidden (an INT32 result
    comes one or two cycles after issue, an FMA's three, an SFU operation's
    five). Lost and hidden results have d None; the stream issues their
    operations anyway."""
    ops = []
    for _ in range(INT_MIXED):
        pick = rng.randrange(4)
        if pick == 3:
            ops.append(rng.choice(int_list))
            continue
        if pick == 2:
            fn, x, y = rng.choice(sfu_rows)
            ops.append((opcodes.sfu_op(fn), 0, rng.getrandbits(32) << 32 | x, rng.getrandbits(64),
                        rng.getrandbits(64), BOX | y))
            continue
        a, b, c, d = rng.choice(fp32_words if pick else fp64_words)
        ops.append((fp("FMA", pick == 1), 0, a, b, c, d))
    return opcodes.settle(ops)


def lane_vectors():
    """Every lane stream and a summary of how they were made. For the
    baseline lanes, (a, b, c, d) rows: the baseline's FP64 FMAs (SHA-256
    checked) and the FP32 FMAs. For the UCC FU, ``ops``, its streams of
    operations (``opcodes``): those FMAs and words, the two at random, the
    SFU's functions, INT32 operations, all of these at random, and
    ``fuvectors``': the FMA in the other rounding modes, ADD, SUB and MUL, the
    compare unit, the conversions, every opcode at random, and FMA-path
    operations and conversions in the rounding modes FPnew does not name; and
    ``dpavectors``': DPA-16 alone and among the others."""
    rows, kinds = vectors(random.Random(SEED))
    results, checks = expected(rows)
    text = "".join(f"{a:016x} {b:016x} {c:016x} {d:016x}\n" for a, b, c, d in results)
    digest = hashlib.sha256(text.encode()).hexdigest()
    assert digest == BASELINE_VECTORS_SHA256, digest
    rng32 = random.Random(FP32_SEED)
    rows32, kinds32 = vectors32(rng32)
    results32, checks32 = expected(rows32, FP32)
    fma32_words = words32(results32, rng32)
    text32 = "".join(f"{a:08x} {b:08x} {c:08x} {d:08x}\n" for a, b, c, d in results32)
    words_mixed, modes_mixed = mixed(results, fma32_words, random.Random(MIXED_SEED))
    rng_sfu = random.Random(SFU_SEED)
    rows_sfu, sfu_summary = sfu_vectors(rng_sfu)
    ops_sfu = sfu_ops(rows_sfu, rng_sfu)
    ops_all, removed_sfu = mixed_all(results, fma32_words, rows_sfu, random.Random(SFU_MIXED_SEED))
    rng_int = random.Random(INT_SEED)
    ops_int = int_ops(int_vectors(rng_int), rng_int)
    ops_int_mixed, removed_int = mixed_int(results, fma32_words, rows_sfu, ops_int, random.Random(INT_MIXED_SEED))
    rng_arith = random.Random(fuvectors.ARITH_SEED)
    fma64, fma32 = fuvectors.fma_modes(results, results32, rng_arith)
    arith, arith_kinds = fuvectors.add_sub_mul(results, results32, rng_arith)
    cmp, cmp_kinds = fuvectors.cmp_ops(random.Random(fuvectors.CMP_SEED))
    cvt, cvt_kinds = fuvectors.cvt_ops(random.Random(fuvectors.CVT_SEED))
    dpa16, dpa_kinds = dpavectors.dpa_ops(random.Random(dpavectors.DPA_SEED))
    ops = dict(
        fp64=[(fp("FMA"), 0, a, b, c, d) for a, b, c, d in results],
        fp32=[(fp("FMA", True), 0, a, b, c, d) for a, b, c, d in fma32_words],
        mixed=[(fp("FMA", mode == 1), 0, *word) for word, mode in zip(words_mixed, modes_mixed)],
        sfu=ops_sfu, mixed_sfu=ops_all, int=ops_int, mixed_int=ops_int_mixed,
        fma_rm_fp64=fma64, fma_rm_fp32=fma32, add_sub_mul=arith, fp_cmp=cmp, fp_cvt=cvt,
        dpa16=dpa16,
    )
    pools = dict(
        fma=ops["fp64"] + ops["fp32"] + fma64 + fma32 + arith, sfu=ops_sfu, cmp=cmp, cvt=cvt,
        alu=[op for op in ops_int if not op[0] & intops.MUL], imul=[op for op in ops_int if op[0] & intops.MUL],
        dpa=dpa16,
    )
    ops["mixed_dpa16"], removed_dpa = dpavectors.mixed(pools, random.Random(dpavectors.DPA_MIXED_SEED))
    ops["mixed_fu"], removed_fu = fuvectors.mixed_fu(pools, random.Random(fuvectors.FU_MIXED_SEED))
    ops["rm_reserved"] = fuvectors.reserved_modes(pools, random.Random(fuvectors.RESERVED_RM_SEED))
    seeds = dict(
        fp64=SEED, fp32=FP32_SEED, mixed=MIXED_SEED, sfu=SFU_SEED, mixed_sfu=SFU_MIXED_SEED, int=INT_SEED,
        mixed_int=INT_MIXED_SEED, fma_rm_fp64=fuvectors.ARITH_SEED, fma_rm_fp32=fuvectors.ARITH_SEED,
        add_sub_mul=fuvectors.ARITH_SEED, fp_cmp=fuvectors.CMP_SEED,
        fp_cvt=fuvectors.CVT_SEED, dpa16=dpavectors.DPA_SEED, mixed_dpa16=dpavectors.DPA_MIXED_SEED,
        mixed_fu=fuvectors.FU_MIXED_SEED, rm_reserved=fuvectors.RESERVED_RM_SEED,
    )
    # fuvectors' and dpavectors' own streams cross-check their expected results; the others were checked as they
    # were made
    cross_checked = ("fma_rm_fp64", "fma_rm_fp32", "add_sub_mul", "fp_cmp", "fp_cvt", "dpa16")
    kinds_of = dict(add_sub_mul=arith_kinds, fp_cmp=cmp_kinds, fp_cvt=cvt_kinds,
                    dpa16=dpa_kinds)
    removed = dict(mixed_sfu=removed_sfu, mixed_int=removed_int, mixed_dpa16=removed_dpa, mixed_fu=removed_fu)
    streams = {}
    for name, stream in ops.items():
        streams[name] = dict(seed=f"{seeds[name]:#x}",
                             **fuvectors.summary(stream, name in cross_checked, removed.get(name)))
        if name in kinds_of:
            streams[name]["kinds"] = kinds_of[name]
    summary = dict(
        fp64=dict(
            seed=f"{SEED:#x}",
            vectors=len(results),
            vectors_sha256=digest,
            kinds=kinds,
            reference_cross_checks=checks,
        ),
        fp32=dict(
            seed=f"{FP32_SEED:#x}",
            vectors=len(results32),
            vectors_sha256=hashlib.sha256(text32.encode()).hexdigest(),
            operations=len(fma32_words),
            kinds=kinds32,
            reference_cross_checks=checks32,
        ),
        sfu=dict(seed=f"{SFU_SEED:#x}", operations=len(ops_sfu), **sfu_summary),
        int=dict(seed=f"{INT_SEED:#x}", codes=intops.CODES, operations=len(ops_int)),
        streams=streams,
    )
    return dict(fp64=results, fp32=fma32_words, ops=ops, summary=summary)
