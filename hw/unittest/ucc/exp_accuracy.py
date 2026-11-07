#!/usr/bin/env python3
"""Measure polynomial error near range boundaries with two high precision oracles."""
import argparse
import json
import math
from pathlib import Path
import random
import struct

import mpmath as mp

from ex2_reference import ex2
from reference import classify, round_binary32

BUILD = Path(__file__).resolve().parents[3] / 'build_ucc'


def encode(value):
    return struct.unpack('<I', struct.pack('<f', float(value)))[0]


def decode(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def mathematical_exp(bits, natural, precision):
    x = classify(bits)
    if x['nan']:
        return 0x7fc00000
    if x['inf']:
        return 0 if x['sign'] else 0x7f800000
    with mp.workprec(precision):
        value = mp.ldexp(mp.mpf(x['sig']), x['exp'])
        if x['sign']:
            value = -value
        if value > 256:
            return 0x7f800000
        if value < -256:
            return 0
        result = mp.exp(value) if natural else mp.power(2, value)
        sign, magnitude, exponent, _ = result._mpf_
        return round_binary32(magnitude, exponent, sign)[0]


def inputs(natural):
    points = {0, 0x80000000, 1, 0x80000001, 0x7f800000, 0xff800000,
              0x7fc00000, 0x7f800001, 0x007fffff, 0x00800000}
    with mp.workprec(200):
        factor = mp.log(2) if natural else mp.mpf(1)
        for integer in range(-151, 129):
            for fraction in range(64):
                center = encode((integer + mp.mpf(fraction)/64) * factor)
                for delta in (-1, 0, 1):
                    points.add((center + delta) & 0xffffffff)
    rng = random.Random(0x455850 + natural)
    for _ in range(10000):
        points.add(encode(rng.uniform(-110, 90) if natural else rng.uniform(-151, 129)))
        points.add(rng.getrandbits(32))
    return sorted(points)


def attention_error(compact=False):
    summary = {}
    for narrow in ((True,) if compact else (False, True)):
        rng = random.Random(0x4154544e)
        worst_abs, worst_l1, worst_relative = 0.0, 0.0, 0.0
        rows, entries = 0, 0
        for length in (128, 512, 4096):
            for kind in ('gaussian', 'uniform', 'near_equal', 'outlier'):
                data = [rng.gauss(0, 4) if kind == 'gaussian' else rng.uniform(-40, 0)
                        if kind == 'uniform' else rng.uniform(-1e-5, 1e-5)
                        if kind == 'near_equal' else rng.gauss(0, 1) for _ in range(length)]
                if kind == 'outlier':
                    data[0] = 50
                maximum = max(data)
                bits = [encode(x-maximum) for x in data]
                actual = [decode(ex2(x, narrow=narrow, natural=True, compact=compact)) for x in bits]
                with mp.workprec(200):
                    reference = [mp.exp(mp.mpf(decode(x))) for x in bits]
                    total = mp.fsum(reference)
                    reference = [float(x/total) for x in reference]
                actual_total = math.fsum(actual)
                actual = [x/actual_total for x in actual]
                errors = [abs(a-b) for a,b in zip(actual,reference)]
                worst_abs = max(worst_abs,max(errors))
                worst_l1 = max(worst_l1,math.fsum(errors))
                worst_relative = max(worst_relative,max(e/b for e,b in zip(errors,reference) if b))
                rows += 1
                entries += length
        summary['compact' if compact else 'narrow' if narrow else 'wide'] = {
            'rows': rows, 'entries': entries, 'max_probability_abs_error': worst_abs,
            'max_row_l1_error': worst_l1, 'max_probability_relative_error': worst_relative}
    summary['scope'] = ('Isolated EXP contribution after binary32 max subtraction; sums and division '
                        'use host binary64, reference uses 200-bit mpmath. This is not a full attention kernel.')
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compact-only', action='store_true')
    args = parser.parse_args()
    modes = (True,) if args.compact_only else (False, True)
    out = BUILD / 'ucc_exp_highprec'
    out.mkdir(exist_ok=True)
    report = {'oracle': 'mpmath 200/300-bit exp and exp2, independently rounded by integer binary32 packer',
              'mpmath_version': mp.__version__, 'precision_bits': [200, 300],
              'limitation': 'Precision agreement and sampled error are empirical, not exhaustive proofs.',
              'measurements': []}
    files = {narrow: (out/('compact_vectors.txt' if args.compact_only else 'narrow_vectors.txt' if narrow else 'wide_vectors.txt')).open('w') for narrow in modes}
    try:
        for natural in (False, True):
            points = inputs(natural)
            rows = {n: {'natural': natural, 'narrow': n, 'compact': args.compact_only, 'cases': len(points),
                        'different_results': 0, 'max_finite_ulp': 0, 'special_result_differences': 0,
                        'worst': None, 'precision_disagreements': 0} for n in modes}
            for bits in points:
                expected = mathematical_exp(bits, natural, 200)
                more = mathematical_exp(bits, natural, 300)
                for narrow, row in rows.items():
                    actual = ex2(bits, narrow, natural, compact=args.compact_only)
                    row['precision_disagreements'] += expected != more
                    row['different_results'] += actual != expected
                    if max(actual, expected) < 0x7f800000:
                        distance = abs(actual-expected)
                        if distance > row['max_finite_ulp']:
                            row['max_finite_ulp'] = distance
                            row['worst'] = {'input': f'{bits:08x}', 'actual': f'{actual:08x}', 'reference': f'{expected:08x}'}
                    elif actual != expected:
                        row['special_result_differences'] += 1
                    files[narrow].write(f'{bits:08x} 0 0 {0x61 if natural else 0x60:x} 0 {actual:08x} 0 0 0\n')
            report['measurements'].extend(rows.values())
    finally:
        for file in files.values():
            file.close()
    report['attention_exp_only'] = attention_error(compact=args.compact_only)
    (out/('compact_results.json' if args.compact_only else 'results.json')).write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    if any(row['precision_disagreements'] for row in report['measurements']):
        raise RuntimeError('high precision reference has not converged')


if __name__ == '__main__':
    main()
