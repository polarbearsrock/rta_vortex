"""Exact IEEE-754 fusedMultiplyAdd for the UCC lanes, and libm's as a cross-check.

The reference computes ``a * b + c`` as a rational and rounds it once to
nearest even, with subnormals, overflow to infinity and FPnew's conventions:
every NaN result is the canonical quiet NaN, and an exact zero sum is +0
unless the product and ``c`` are both zeros of the same sign.
"""

import ctypes
import ctypes.util
from dataclasses import dataclass
from fractions import Fraction
import struct


@dataclass(frozen=True)
class Format:
    name: str
    exponent: int
    mantissa: int

    @property
    def width(self):
        return 1 + self.exponent + self.mantissa

    @property
    def bias(self):
        return (1 << self.exponent - 1) - 1

    @property
    def top(self):
        """The all-ones exponent field (infinities and NaNs)."""
        return (1 << self.exponent) - 1

    @property
    def sign(self):
        return 1 << self.width - 1

    @property
    def inf(self):
        return self.top << self.mantissa

    @property
    def qnan(self):
        return self.inf | 1 << self.mantissa - 1


FP64 = Format("FP64", 11, 52)
FP32 = Format("FP32", 8, 23)


def decode(fmt, x):
    """(sign, kind, value): kind is 'nan', 'inf' or 'num', value the exact
    signed rational of a 'num'."""
    s = x >> fmt.width - 1
    e = x >> fmt.mantissa & fmt.top
    f = x & (1 << fmt.mantissa) - 1
    if e == fmt.top:
        return s, ("nan" if f else "inf"), None
    significand = f if e == 0 else f | 1 << fmt.mantissa
    value = Fraction(significand) * Fraction(2) ** (
        max(e, 1) - fmt.bias - fmt.mantissa
    )
    return s, "num", -value if s else value


def round_nearest(fmt, v):
    """A nonzero exact value rounded to ``fmt``, nearest even."""
    s = int(v < 0)
    m = -v if s else v
    e = m.numerator.bit_length() - m.denominator.bit_length()
    if m < Fraction(2) ** e:
        e -= 1
    q = max(e, 1 - fmt.bias) - fmt.mantissa
    scaled = m / Fraction(2) ** q
    k = scaled.numerator // scaled.denominator
    r = scaled - k
    if r > Fraction(1, 2) or (r == Fraction(1, 2) and k & 1):
        k += 1
    if k == 1 << fmt.mantissa + 1:
        k, q = 1 << fmt.mantissa, q + 1
    if k >= 1 << fmt.mantissa:
        biased = q + fmt.bias + fmt.mantissa
        if biased >= fmt.top:
            bits = fmt.inf
        else:
            bits = biased << fmt.mantissa | k - (1 << fmt.mantissa)
    else:
        assert q == 1 - fmt.bias - fmt.mantissa
        bits = k
    return s << fmt.width - 1 | bits


def fma(fmt, a, b, c):
    """IEEE-754 fusedMultiplyAdd(a, b, c) in ``fmt``, round to nearest even."""
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
        return c
    product = va * vb
    exact = product + vc
    if exact == 0:
        return (sp & sc) << fmt.width - 1 if product == 0 and vc == 0 else 0
    return round_nearest(fmt, exact)


_LIBM = ctypes.CDLL(ctypes.util.find_library("m"))
_LIBM.fma.argtypes = (ctypes.c_double,) * 3
_LIBM.fma.restype = ctypes.c_double
_LIBM.fmaf.argtypes = (ctypes.c_float,) * 3
_LIBM.fmaf.restype = ctypes.c_float
_LIBM_FMA = {FP64: (_LIBM.fma, "<Q", "<d"), FP32: (_LIBM.fmaf, "<I", "<f")}


def libm_fma(fmt, a, b, c):
    """The C library's fma (FP64) or fmaf (FP32), or None for a NaN result."""
    function, bits, real = _LIBM_FMA[fmt]

    def value(x):
        return struct.unpack(real, struct.pack(bits, x))[0]

    x = function(value(a), value(b), value(c))
    return None if x != x else struct.unpack(bits, struct.pack(real, x))[0]
