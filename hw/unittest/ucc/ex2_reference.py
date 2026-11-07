import json
import math
from pathlib import Path
import re
import struct
from reference import round_binary32

ROOT = Path(__file__).resolve().parents[3]
ROM = list(reversed([int(x, 16) for x in re.findall(r"72'h([0-9a-fA-F]+)",
                    (ROOT / 'hw/rtl/mufu/VX_mufu_rom.sv').read_text())]))


def coefficients(index):
    row = ROM[256 + index]
    a0, a1, a2 = (row >> 43) << 2, ((row >> 19) & 0xffffff) << 2, (row & 0x7ffff) << 1
    a1 -= (1 << 26) if a1 & (1 << 25) else 0
    a2 -= (1 << 20) if a2 & (1 << 19) else 0
    assert a1 >= 0 and a2 >= 0
    return a0, a1, a2


def ex2(bits, narrow=False, natural=False, compact=False):
    e, frac, sign = (bits >> 23) & 255, bits & 0x7fffff, bits >> 31
    if e == 255 and frac:
        return 0x7fc00000
    if e == 0:
        return 0x3f800000
    if e >= (134 if natural else 135):
        return 0 if sign else 0x7f800000
    sig = frac | 0x800000
    magnitude = ((sig * 0x5c551d95) >> (150 - e)) if natural else (
        sig << (e - 120) if e >= 120 else sig >> (120 - e))
    fixed = -magnitude if sign else magnitude
    integer, fraction = divmod(fixed, 1 << 30)
    index, residual = fraction >> 24, (fraction & 0xffffff) >> 6
    a0, a1, a2 = coefficients(index)
    if compact:
        square = (residual >> 7) ** 2
        quadratic = (a2 >> 6) * (square >> 11)
        if narrow:
            linear = 0
            for i in range(3):
                for j in range(2):
                    product = ((a1 >> (11*i)) & 2047) * ((residual >> (11*j)) & 2047)
                    linear += (product << (11*(i+j))) >> 18
            return round_binary32(a0 + linear + (quadratic >> 5), integer - 30, 0)[0]
        return round_binary32((a0 << 18) + a1*residual + (quadratic << 13), integer - 48, 0)[0]
    squared = residual * residual // (1 << 18)
    if narrow:
        polynomial = a0
        for coefficient, value, pieces in ((a1, residual, 3), (a2, squared, 2)):
            for i in range(pieces):
                for j in range(2):
                    product = ((coefficient >> (11*i)) & 2047) * ((value >> (11*j)) & 2047)
                    polynomial += (product << (11*(i+j))) >> 18
        return round_binary32(polynomial, integer - 30, 0)[0]
    polynomial = (a0 << 18) + a1 * residual + a2 * squared
    return round_binary32(polynomial, integer - 48, 0)[0]


def ieee_comparison(bits, natural=False):
    x = struct.unpack('<f', struct.pack('<I', bits))[0]
    if math.isnan(x):
        return 0x7fc00000
    if x >= 128:
        return 0x7f800000
    if x < -150:
        return 0
    try:
        value = math.exp(x) if natural else 2.0 ** x
        return struct.unpack('<I', struct.pack('<f', value))[0]
    except OverflowError:
        return 0x7f800000


def report_accuracy(inputs, path, narrow=False, natural=False, compact=False):
    maximum, count, differences, worst = 0, 0, 0, None
    for bits in inputs:
        actual, reference = ex2(bits, narrow, natural, compact), ieee_comparison(bits, natural)
        count += 1
        differences += actual != reference
        if actual < 0x7f800000 and reference < 0x7f800000:
            distance = abs(actual - reference)
            if distance > maximum:
                maximum, worst = distance, {'input': bits, 'actual': actual, 'reference': reference}
    Path(path).write_text(json.dumps({
        'cases': count, 'natural_exp': natural, 'narrow_polynomial': narrow, 'compact_polynomial': compact,
        'different_outputs': differences, 'maximum_observed_finite_ulp': maximum,
        'worst': worst, 'reference': 'Host binary64 exponential rounded to binary32',
        'limitation': 'Measured error on these inputs; neither an exhaustive error bound nor correctly rounded EXP2 proof.'
    }, indent=2) + '\n')
