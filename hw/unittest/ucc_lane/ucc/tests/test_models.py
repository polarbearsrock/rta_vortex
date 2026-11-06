"""The exact reference against known results and libm, and the pinned sources."""

import random
import pytest
from ..models import FP32, FP64, fma, libm_fma
from ..verify import check_sources


def test_vendored_sources_unmodified():
    check_sources()


@pytest.mark.parametrize("fmt", (FP64, FP32), ids=lambda f: f.name)
def test_known_results(fmt):
    one = fmt.bias << fmt.mantissa
    two = fmt.bias + 1 << fmt.mantissa
    tiny = 1  # the smallest subnormal
    big = fmt.inf - 1  # the largest finite value
    zero, neg_zero = 0, fmt.sign
    assert fma(fmt, one, one, one) == two
    assert fma(fmt, one, one, fmt.sign | one) == zero
    assert fma(fmt, zero, one, zero) == zero
    assert fma(fmt, neg_zero, one, neg_zero) == neg_zero
    assert fma(fmt, neg_zero, one, zero) == zero
    assert fma(fmt, fmt.inf, zero, one) == fmt.qnan
    assert fma(fmt, fmt.inf, one, fmt.sign | fmt.inf) == fmt.qnan
    assert fma(fmt, fmt.inf, fmt.sign | one, one) == fmt.sign | fmt.inf
    assert fma(fmt, one, one, fmt.inf | 1) == fmt.qnan  # signalling NaN in
    assert fma(fmt, big, two, zero) == fmt.inf
    assert fma(fmt, tiny, one, tiny) == 2
    # Half the smallest subnormal rounds to even (zero); three halves to two.
    half = fmt.bias - 1 << fmt.mantissa
    assert fma(fmt, tiny, half, zero) == zero
    assert fma(fmt, 3, half, zero) == 2


def operand(rng, fmt, near=None):
    """A random encoding, or a finite value whose exponent is near ``near``."""
    if near is None:
        return rng.getrandbits(fmt.width)
    e = min(fmt.top - 1, max(0, near + rng.randrange(-30, 31)))
    sign = rng.getrandbits(1) << fmt.width - 1
    return sign | e << fmt.mantissa | rng.getrandbits(fmt.mantissa)


@pytest.mark.parametrize("fmt", (FP64, FP32), ids=lambda f: f.name)
def test_matches_libm(fmt):
    rng = random.Random(fmt.width)
    checked = 0
    for index in range(20000):
        if index % 2:
            a, b, c = (operand(rng, fmt) for _ in range(3))
        else:
            ea = rng.randrange(1, fmt.top)
            eb = min(fmt.top - 1, max(1, 2 * fmt.bias - ea + rng.randrange(-40, 41)))
            a, b = operand(rng, fmt, ea), operand(rng, fmt, eb)
            c = operand(rng, fmt, max(0, ea + eb - fmt.bias))
        d = fma(fmt, a, b, c)
        libm = libm_fma(fmt, a, b, c)
        if libm is None:
            assert d == fmt.qnan
        else:
            assert d == libm, (f"{a:x} {b:x} {c:x}", f"{d:x}", f"{libm:x}")
            checked += 1
    assert checked > 15000
