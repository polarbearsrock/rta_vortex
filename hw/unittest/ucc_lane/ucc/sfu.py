"""The UCC's SFU mode: its reference, Vortex's MUFU for comparison, and the
MUFU's accuracy bounds.

``evaluate(fn, x)`` is what ``ucc_lane`` returns for an SFU operation: the
MUFU's range reduction and coefficient table (hw/rtl/mufu), the quadratic
``a0 + a1 xl + a2 xl^2`` summed exactly (xl^2 truncated to 18 bits, as the
MUFU's), rounded once to FP32 to nearest even, with the MUFU's special values,
zero signs and flush to zero. ``mufu(fn, x)`` is Vortex's own bit-exact C model
(sw/common/mufu.cpp, compiled on first use), which truncates
each product before the sum and rounds half up. ``accurate`` is the bound the
Vortex MUFU regression applies (tests/regression/mufu/main.cpp).
"""

from dataclasses import dataclass
import ctypes
import functools
import math
from pathlib import Path
import re
import struct
import subprocess
import tempfile

from .paths import MUFU_RTL, MUFU_SW

RCP, RSQRT, EX2, LG2, SINPI, COSPI, TANH = range(7)
NAMES = ("rcp", "rsqrt", "ex2", "lg2", "sinpi", "cospi", "tanh")
FRAC, XL_BITS = 30, 18
QNAN, POS_INF, NEG_INF, ONE = 0x7FC00000, 0x7F800000, 0xFF800000, 0x3F800000
SIGN = 1 << 31


@functools.cache
def table():
    """The datapath's (a0, a1, a2) per ROM entry, from mufu_tables.h, and the
    tables' bases."""
    text = (MUFU_SW / "mufu_tables.h").read_text()
    shift = {k: int(v) for k, v in re.findall(r"constexpr uint32_t (S[012]) = (\d+);", text)}
    bases = {k: int(v) for k, v in re.findall(r"constexpr uint32_t TBL_(\w+)_BASE = (\d+);", text)}
    rows = re.findall(r"\{0x([0-9a-f]+)u, (-?\d+), (-?\d+)\}", text)
    entries = [
        (int(a0, 16) << shift["S0"], int(a1) << shift["S1"], int(a2) << shift["S2"])
        for a0, a1, a2 in rows
    ]
    assert len(entries) == 512
    return entries, bases


def rom_words():
    """VX_mufu_rom.sv's 512 72-bit words, entry 0 first."""
    text = (MUFU_RTL / "VX_mufu_rom.sv").read_text()
    words = [int(w, 16) for w in re.findall(r"72'h([0-9a-f]+)", text)]
    return words[::-1]


@dataclass
class Reduced:
    special: bool = False
    value: int = 0
    addr: int = 0
    xl: int = 0
    exp: int = 0
    neg: bool = False
    zsign: bool = False
    lg2: bool = False
    k: int = 0


def reduce(fn, x):
    """The MUFU's range reduction (mufu.cpp's reduce, VX_mufu_pe's stage 1)."""
    _, base = table()
    s, e, m = x >> 31, x >> 23 & 0xFF, x & 0x7FFFFF
    zero, inf, nan = e == 0, e == 0xFF and m == 0, e == 0xFF and m != 0
    sig = m | 1 << 23

    def special(v):
        return Reduced(special=True, value=v)

    if nan:
        return special(QNAN)
    if fn == RCP:
        if inf:
            return special(s << 31)
        if zero:
            return special(NEG_INF if s else POS_INF)
        return Reduced(addr=base["RCP"] + (m >> 16), xl=(m & 0xFFFF) << 2, exp=127 - e, neg=bool(s))
    if fn == RSQRT:
        if zero:
            return special(NEG_INF if s else POS_INF)
        if s:
            return special(QNAN)
        if inf:
            return special(0)
        k = e - 127
        return Reduced(addr=base["RSQRT"] + ((k & 1) << 6) + (m >> 17), xl=(m & 0x1FFFF) << 1, exp=-(k >> 1))
    if fn == EX2:
        if inf:
            return special(0 if s else POS_INF)
        if zero:
            return special(ONE)
        if e >= 134:
            return special(0 if s else POS_INF)
        sh = e - 120
        mag = sig << sh if sh >= 0 else (sig >> -sh if sh > -24 else 0)
        X = -mag if s else mag
        f = X & (1 << FRAC) - 1
        return Reduced(addr=base["EX2"] + (f >> 24), xl=f >> 6 & (1 << XL_BITS) - 1, exp=X >> FRAC)
    if fn == LG2:
        if zero:
            return special(NEG_INF)
        if s:
            return special(QNAN)
        if inf:
            return special(POS_INF)
        return Reduced(addr=base["LG2"] + (m >> 17), xl=(m & 0x1FFFF) << 1, lg2=True, k=e - 127)
    if fn in (SINPI, COSPI):
        is_sin = fn == SINPI
        if inf:
            return special(QNAN)
        if zero:
            return special(s << 31 if is_sin else ONE)
        sh = e - 119
        if sh >= 32:
            u = 0
        elif sh >= 0:
            u = sig << sh & 0xFFFFFFFF
        else:
            u = sig >> -sh if sh > -24 else 0
        if not is_sin:
            u = u + (1 << FRAC) & 0xFFFFFFFF
        q, t = u >> FRAC, u & (1 << FRAC) - 1
        neg = bool(q >> 1 & 1 ^ (s if is_sin else 0))
        if q & 1:
            if t == 0:
                return special(ONE | SIGN if neg else ONE)
            t = ~t & (1 << FRAC) - 1
        return Reduced(addr=base["SIN"] + (t >> 24), xl=t >> 6 & (1 << XL_BITS) - 1, neg=neg,
                       zsign=is_sin and bool(s))
    if fn == TANH:
        if inf or e >= 130:
            return special(ONE | SIGN if s else ONE)
        if zero:
            return special(s << 31)
        if e < 122:
            return special(x)  # ucc_sfu passes x through the datapath, exactly
        return Reduced(addr=base["TANH"] + (e - 122 << 3) + (m >> 20), xl=m >> 2 & (1 << XL_BITS) - 1,
                       exp=e - 127 + 4, neg=bool(s))
    return special(0)


def round_fp32(mag, exp, neg):
    """mag * 2^exp, mag > 0, rounded to FP32 to nearest even; FP32's
    exponent range is applied after rounding: infinity above, zero below."""
    lead = mag.bit_length() - 1
    shift = lead - 23
    if shift > 0:
        q, rem, half = mag >> shift, mag & (1 << shift) - 1, 1 << shift - 1
        q += rem > half or (rem == half and q & 1)
        if q >> 24:
            q, lead = q >> 1, lead + 1
    else:
        q = mag << -shift
    biased = lead + exp + 127
    sign = SIGN if neg else 0
    if biased >= 255:
        return sign | POS_INF
    if biased <= 0:
        return sign
    return sign | biased << 23 | q & 0x7FFFFF


def terms(r):
    """a0 and the two products, the MUFU's sum before its truncations (in
    units of 2^-48 of the result scale)."""
    entries, _ = table()
    a0, a1, a2 = entries[r.addr]
    sq = r.xl * r.xl >> XL_BITS
    return a0 << XL_BITS, a1 * r.xl, a2 * sq


def evaluate(fn, x):
    """ucc_lane's SFU result for function ``fn`` of the FP32 encoding ``x``."""
    r = reduce(fn, x)
    if r.special:
        return r.value
    total = sum(terms(r))
    if r.lg2:
        total += r.k << FRAC + XL_BITS
        neg, mag, exp, zsign = total < 0, abs(total), 0, False
    else:
        assert total >= 0, (fn, x)
        neg, mag, exp, zsign = r.neg, total, r.exp, r.zsign
    if mag == 0:
        return SIGN if zsign else 0
    return round_fp32(mag, exp - FRAC - XL_BITS, neg)


@functools.cache
def _mufu_library():
    build = Path(tempfile.mkdtemp(prefix="rta-ucc-mufu-"))
    (build / "wrap.cpp").write_text(
        '#include "mufu.h"\n'
        'extern "C" unsigned mufu_eval(unsigned fn, unsigned x) { return vortex::mufu::eval(fn, x); }\n'
    )
    common = MUFU_SW
    subprocess.run(["g++", "-std=c++17", "-O2", "-shared", "-fPIC", f"-I{common}", str(common / "mufu.cpp"),
                    str(build / "wrap.cpp"), "-o", str(build / "libmufu.so")], check=True)
    library = ctypes.CDLL(str(build / "libmufu.so"))
    library.mufu_eval.argtypes = (ctypes.c_uint, ctypes.c_uint)
    library.mufu_eval.restype = ctypes.c_uint
    return library


def mufu(fn, x):
    """Vortex's bit-exact MUFU result (its C model)."""
    return _mufu_library().mufu_eval(fn, x)


def f32(x):
    return struct.unpack("<f", struct.pack("<I", x))[0]


def reference(fn, x):
    """The function in double precision, as the Vortex regression computes it."""
    v = f32(x)
    try:
        if fn == RCP:
            return 1.0 / v
        if fn == RSQRT:
            return 1.0 / math.sqrt(v)
        if fn == EX2:
            return 2.0 ** v
        if fn == LG2:
            return math.log2(v)
        if fn == SINPI:
            return math.sin(math.pi * math.fmod(v, 2.0))
        if fn == COSPI:
            return math.cos(math.pi * math.fmod(v, 2.0))
        return math.tanh(v)
    except (ValueError, ZeroDivisionError, OverflowError):
        return math.nan


def accurate(fn, x, y):
    """The Vortex MUFU regression's accuracy bound (raw_accurate): True when
    ``y`` is within it, or the input or result is out of the bound's scope."""
    v, r = f32(x), reference(fn, x)
    normal = v != 0 and math.isfinite(v) and abs(v) >= 1.1754943508222875e-38
    if not normal or not math.isfinite(r) or abs(r) >= 3.4028234663852886e38 or abs(r) < 1.1754943508222875e-38:
        return True
    err = abs(f32(y) - r)
    ulp = math.ldexp(1.0, math.frexp(r)[1] - 24)
    if fn == LG2:
        return err <= 2.0 ** -22 if 0.5 <= v <= 2.0 else err <= 2 * ulp
    if fn in (SINPI, COSPI):
        return err <= 2.0 ** -21
    if fn == TANH:
        return err <= 2.0 ** -11 * abs(r)
    return err <= 2 * ulp
