"""The UCC FU's floating-point reference.

Every FP operation of the FU on values of one format, computed as an exact
rational and rounded once in the requested mode (FPnew's encoding: RNE, RTZ,
RDN, RUP, RMM), with subnormals, overflow per mode, and FPnew's conventions,
which are RISC-V's:

- a NaN result is the canonical quiet NaN;
- an exact zero sum is +0, or -0 in RDN, unless both terms are zeros of the
  same sign;
- min and max return the non-NaN operand, and -0 is less than +0;
- compares are false if an operand is a NaN, except NE, which is true;
- a conversion to int32 rounds in the requested mode, a NaN gives the
  largest value, and out-of-range values saturate (an unsigned conversion of
  a negative value gives 0).

``c_arith`` and ``c_convert`` compute the same operations with the C library
and compiler, which honour the rounding mode fesetround sets, as an
independent check of the exact arithmetic (RNE, RTZ, RDN and RUP; C has no
RMM).
"""

import ctypes
import functools
from fractions import Fraction
import math
from pathlib import Path
import subprocess
import tempfile

from .models import FP32, FP64, decode

RNE, RTZ, RDN, RUP, RMM = range(5)
MODES = (RNE, RTZ, RDN, RUP, RMM)
MODE_NAMES = ("rne", "rtz", "rdn", "rup", "rmm")


def one(fmt):
    return fmt.bias << fmt.mantissa


def max_finite(fmt):
    return (fmt.top - 1) << fmt.mantissa | (1 << fmt.mantissa) - 1


def is_nan(fmt, x):
    return (x >> fmt.mantissa & fmt.top) == fmt.top and x & (1 << fmt.mantissa) - 1


def exponent_of(m):
    """floor(log2(m)) of a positive rational."""
    e = m.numerator.bit_length() - m.denominator.bit_length()
    if m < Fraction(2) ** e:
        e -= 1
    return e


def overflow(fmt, s, rm):
    """The result of an overflow of sign s: infinity, or the largest finite value where the mode rounds toward
    zero for that sign."""
    to_inf = rm in (RNE, RMM) or (rm == RUP and not s) or (rm == RDN and s)
    return s << fmt.width - 1 | (fmt.inf if to_inf else max_finite(fmt))


def round_up(rm, s, k, r):
    """Whether the magnitude k + r (0 <= r < 1, r compared exactly) rounds up."""
    if r == 0:
        return False
    if rm == RNE:
        return r > Fraction(1, 2) or (r == Fraction(1, 2) and k & 1)
    if rm == RMM:
        return r >= Fraction(1, 2)
    if rm == RTZ:
        return False
    return bool(s) if rm == RDN else not s


def pack(fmt, s, q, k):
    """Sign s and magnitude k * 2^q, k the rounded significand of an exponent-q grid, as bits."""
    if k == 1 << fmt.mantissa + 1:
        k, q = 1 << fmt.mantissa, q + 1
    if k >= 1 << fmt.mantissa:
        biased = q + fmt.bias + fmt.mantissa
        return None if biased >= fmt.top else s << fmt.width - 1 | biased << fmt.mantissa | k - (1 << fmt.mantissa)
    assert q == 1 - fmt.bias - fmt.mantissa
    return s << fmt.width - 1 | k


def round_rational(fmt, v, rm):
    """A nonzero exact rational rounded to ``fmt`` in mode ``rm``."""
    s = int(v < 0)
    m = -v if s else v
    q = max(exponent_of(m), 1 - fmt.bias) - fmt.mantissa
    scaled = m / Fraction(2) ** q
    k = scaled.numerator // scaled.denominator
    k += round_up(rm, s, k, scaled - k)
    bits = pack(fmt, s, q, k)
    return overflow(fmt, s, rm) if bits is None else bits


def zero_sum(fmt, s1, s2, rm):
    """An exact zero x + y of terms whose zeros have signs s1, s2 (IEEE 754 6.3)."""
    if s1 == s2:
        return s1 << fmt.width - 1
    return int(rm == RDN) << fmt.width - 1


def fma(fmt, a, b, c, rm):
    """IEEE-754 fusedMultiplyAdd(a, b, c), as fpnew_fma computes it."""
    (sa, ka, va), (sb, kb, vb), (sc, kc, vc) = (decode(fmt, x) for x in (a, b, c))
    if "nan" in (ka, kb, kc):
        return fmt.qnan
    sp = sa ^ sb
    if ka == "inf" or kb == "inf":
        zero = (ka == "num" and va == 0) or (kb == "num" and vb == 0)
        if zero or (kc == "inf" and sc != sp):
            return fmt.qnan
        return sp << fmt.width - 1 | fmt.inf
    if kc == "inf":
        return sc << fmt.width - 1 | fmt.inf
    exact = va * vb + vc
    if exact == 0:
        return zero_sum(fmt, sp, sc, rm) if va * vb == 0 and vc == 0 else int(rm == RDN) << fmt.width - 1
    return round_rational(fmt, exact, rm)


def add(fmt, a, b, rm):
    """a + b: FPnew's ADD, 1.0 * a + b."""
    return fma(fmt, one(fmt), a, b, rm)


def sub(fmt, a, b, rm):
    return fma(fmt, one(fmt), a, b ^ fmt.sign, rm)


def mul(fmt, a, b, rm):
    """a * b: FPnew's MUL, a * b + 0 with the zero's sign chosen so a zero product keeps its sign."""
    return fma(fmt, a, b, (0 if rm == RDN else fmt.sign), rm)


def minmax(fmt, a, b, is_max):
    if is_nan(fmt, a) and is_nan(fmt, b):
        return fmt.qnan
    if is_nan(fmt, a):
        return b
    if is_nan(fmt, b):
        return a
    (sa, ka, va), (sb, kb, vb) = decode(fmt, a), decode(fmt, b)
    xa = (-1 if sa else 1) * math.inf if ka == "inf" else va
    xb = (-1 if sb else 1) * math.inf if kb == "inf" else vb
    a_smaller = xa < xb or (xa == xb and sa > sb)  # -0 < +0
    return (b if a_smaller else a) if is_max else (a if a_smaller else b)


def compare(fmt, a, b, cond):
    if is_nan(fmt, a) or is_nan(fmt, b):
        return int(cond == "ne")
    (sa, ka, va), (sb, kb, vb) = decode(fmt, a), decode(fmt, b)
    xa = (-1 if sa else 1) * math.inf if ka == "inf" else va
    xb = (-1 if sb else 1) * math.inf if kb == "inf" else vb
    return int({"eq": xa == xb, "ne": xa != xb, "lt": xa < xb, "le": xa <= xb, "gt": xa > xb,
                "ge": xa >= xb}[cond])


def to_float(fmt, src, x, rm):
    """FP to the other FP format (F2F)."""
    s, k, v = decode(src, x)
    if k == "nan":
        return fmt.qnan
    if k == "inf":
        return s << fmt.width - 1 | fmt.inf
    if v == 0:
        return s << fmt.width - 1
    return round_rational(fmt, v, rm)


def from_int(fmt, x, signed, rm):
    """int32 to FP (I2F); +0 for zero."""
    x &= 0xFFFFFFFF
    v = x - (1 << 32) if signed and x >> 31 else x
    return 0 if v == 0 else round_rational(fmt, Fraction(v), rm)


def round_int(v, rm):
    """An exact rational rounded to an integer in mode rm."""
    s = int(v < 0)
    m = -v if s else v
    k = m.numerator // m.denominator
    k += round_up(rm, s, k, m - k)
    return -k if s else k


def to_int(fmt, x, signed, rm):
    """FP to int32 (F2I), saturating as FPnew (RISC-V) does; the result's 32 bits."""
    lo, hi = (-(1 << 31), (1 << 31) - 1) if signed else (0, (1 << 32) - 1)
    s, k, v = decode(fmt, x)
    if k == "nan":
        return hi & 0xFFFFFFFF
    if k == "inf":
        return (lo if s else hi) & 0xFFFFFFFF
    r = round_int(v, rm)
    if r > hi:
        return hi & 0xFFFFFFFF
    if r < lo:
        return lo & 0xFFFFFFFF
    return r & 0xFFFFFFFF


# ---------------------------------------------------------------------------
# The C library as a cross-check (RNE, RTZ, RDN, RUP)
# ---------------------------------------------------------------------------

C_SOURCE = r"""
#include <fenv.h>
#include <math.h>
#include <stdint.h>
#include <string.h>
static const int modes[4] = {FE_TONEAREST, FE_TOWARDZERO, FE_DOWNWARD, FE_UPWARD};
static double d(uint64_t x) { double r; memcpy(&r, &x, 8); return r; }
static float f(uint32_t x) { float r; memcpy(&r, &x, 4); return r; }
static uint64_t D(double x) { uint64_t r; memcpy(&r, &x, 8); return r; }
static uint32_t F(float x) { uint32_t r; memcpy(&r, &x, 4); return r; }
uint64_t c_op64(int op, int rm, uint64_t a, uint64_t b, uint64_t c) {
  volatile double x = d(a), y = d(b), z = d(c), r = 0;
  fesetround(modes[rm]);
  switch (op) {
    case 0: r = fma(x, y, z); break;
    case 1: r = x + y; break;
    case 2: r = x - y; break;
    case 3: r = x * y; break;
  }
  fesetround(FE_TONEAREST);
  return D(r);
}
uint32_t c_op32(int op, int rm, uint32_t a, uint32_t b, uint32_t c) {
  volatile float x = f(a), y = f(b), z = f(c), r = 0;
  fesetround(modes[rm]);
  switch (op) {
    case 0: r = fmaf(x, y, z); break;
    case 1: r = x + y; break;
    case 2: r = x - y; break;
    case 3: r = x * y; break;
  }
  fesetround(FE_TONEAREST);
  return F(r);
}
uint64_t c_cvt(int op, int rm, uint64_t a) {
  volatile uint64_t r = 0;
  volatile double x = d(a); volatile float y = f((uint32_t)a);
  volatile int32_t s = (int32_t)(uint32_t)a; volatile uint32_t u = (uint32_t)a;
  fesetround(modes[rm]);
  switch (op) {
    case 0: r = D((double)y); break;               /* F64 <- F32 */
    case 1: r = F((float)x); break;                /* F32 <- F64 */
    case 2: r = D((double)s); break;               /* F64 <- S32 */
    case 3: r = D((double)u); break;               /* F64 <- U32 */
    case 4: r = F((float)s); break;                /* F32 <- S32 */
    case 5: r = F((float)u); break;                /* F32 <- U32 */
    case 6: r = (uint64_t)(int64_t)llrint(x); break;  /* round F64 to an integer */
    case 7: r = (uint64_t)(int64_t)llrintf(y); break; /* round F32 to an integer */
  }
  fesetround(FE_TONEAREST);
  return r;
}
"""


@functools.cache
def _clib():
    build = Path(tempfile.mkdtemp(prefix="ucc-fpref-"))
    (build / "fpref.c").write_text(C_SOURCE)
    subprocess.run(["gcc", "-O0", "-frounding-math", "-fno-fast-math", "-shared", "-fPIC", "-o",
                    str(build / "fpref.so"), str(build / "fpref.c"), "-lm"], check=True)
    lib = ctypes.CDLL(str(build / "fpref.so"))
    lib.c_op64.argtypes = (ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_uint64, ctypes.c_uint64)
    lib.c_op64.restype = ctypes.c_uint64
    lib.c_op32.argtypes = (ctypes.c_int, ctypes.c_int, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32)
    lib.c_op32.restype = ctypes.c_uint32
    lib.c_cvt.argtypes = (ctypes.c_int, ctypes.c_int, ctypes.c_uint64)
    lib.c_cvt.restype = ctypes.c_uint64
    return lib


C_ARITH = ("fma", "add", "sub", "mul")
C_CONVERT = ("f64.f32", "f32.f64", "f64.s32", "f64.u32", "f32.s32", "f32.u32")


def c_arith(name, fmt, rm, a, b=0, c=0):
    """The C library's result for an arithmetic operation (C_ARITH) in mode rm, which must not be RMM: C lacks it."""
    assert rm != RMM
    lib = _clib()
    op = C_ARITH.index(name)
    return lib.c_op64(op, rm, a, b, c) if fmt is FP64 else lib.c_op32(op, rm, a, b, c)


def c_convert(kind, rm, x):
    """The C library's conversion "<to>.<from>" (C_CONVERT) in mode rm (not RMM), or for "s32.f64" and "s32.f32"
    the integer C's llrint rounds x to, before any saturation; None where C cannot (a NaN, an infinity, or
    |x| >= 2^62)."""
    assert rm != RMM
    lib = _clib()
    if kind in C_CONVERT:
        return lib.c_cvt(C_CONVERT.index(kind), rm, x)
    fmt = FP64 if kind.endswith("f64") else FP32
    s, k, v = decode(fmt, x)
    if k != "num" or abs(v) >= 2 ** 62:
        return None
    r = lib.c_cvt(6 if fmt is FP64 else 7, rm, x)
    return r - (1 << 64) if r >> 63 else r
