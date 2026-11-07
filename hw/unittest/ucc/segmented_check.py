#!/usr/bin/env python3
"""Validate a 64-bit, operand-bounded FMA window against the exact integer oracle."""
import json
from pathlib import Path
import random

from reference import classify, fma, round_binary32

BUILD = Path(__file__).resolve().parents[3] / 'build_ucc'


def segmented(a, b, c, rm):
    x, y, z = map(classify, (a, b, c))
    if any(q['nan'] or q['inf'] for q in (x, y, z)):
        return fma(a, b, c, rm)
    product = x['sig'] * y['sig']
    pe = x['exp'] + y['exp']
    ps = x['sign'] ^ y['sign']
    ptop = pe + x['sig'].bit_length() + y['sig'].bit_length() - 1 if product else -1024
    ctop = z['exp'] + z['sig'].bit_length() - 1 if z['sig'] else -1024
    base = max(ptop, ctop) - 61

    def align(sig, exponent):
        distance = base-exponent
        if distance <= 0:
            return sig << -distance
        kept, lost = divmod(sig, 1 << distance)
        return kept | int(lost != 0)

    p, c = align(product, pe), align(z['sig'], z['exp'])
    total = (-p if ps else p) + (-c if z['sign'] else c)
    assert -(1 << 63) <= total < (1 << 63)
    if not total:
        sign = ps if not product and not z['sig'] and ps == z['sign'] else int(rm == 2)
        return sign << 31, 0
    return round_binary32(abs(total), base, int(total < 0), rm)


def main():
    out = BUILD/'ucc_segmented_model'
    out.mkdir(exist_ok=True)
    count, failures = 0, []

    def check(a, b, c, rm, expected):
        nonlocal count
        actual = segmented(a, b, c, rm)
        count += 1
        if actual != expected and len(failures) < 20:
            failures.append({'a': a, 'b': b, 'c': c, 'rm': rm, 'expected': expected, 'actual': actual})

    for name in ['ucc_v1_csa/vectors.txt', 'ucc_fma_window_sweep/ieee_vectors.txt', 'ucc_anchor/dominance_vectors.txt']:
        for line in (BUILD/name).read_text().splitlines():
            a, b, c, op, rm, result, flags = [int(x, 16) for x in line.split()]
            if op >= 2:
                b, c = 0x3f800000, b ^ ((op & 1) << 31)
            elif op == 1:
                c = (a ^ b) & 0x80000000
            check(a, b, c, rm, (result, flags))
    rng = random.Random(0x53454746)
    extra = 0
    with (out/'vectors.txt').open('w') as vectors:
        for rm in range(4):
            a, b, c = 0x3f800001, 0x3f800001, 0xbf800002
            expected = fma(a, b, c, rm)
            assert expected == (0x28800000, 0)
            check(a, b, c, rm, expected)
            vectors.write(f'{a:08x} {b:08x} {c:08x} 0 {rm:x} {expected[0]:08x} {expected[1]:02x}\n')
            extra += 1
        for i in range(100000):
            a, b, c = [rng.getrandbits(32) for _ in range(3)]
            if i % 4 == 0:
                a = (a & 0x807fffff)
            elif i % 4 == 1:
                a = (a & 0x80000000) | (1 << rng.randrange(24))
            if i % 4 in (1, 2):
                rounded, _ = fma(a, b, 0)
                c = ((rounded ^ 0x80000000) + rng.randrange(-2, 3)) & 0xffffffff
            for rm in range(4):
                expected = fma(a, b, c, rm)
                check(a, b, c, rm, expected)
                vectors.write(f'{a:08x} {b:08x} {c:08x} 0 {rm:x} {expected[0]:08x} {expected[1]:02x}\n')
                extra += 1
    report = {'checks': count, 'new_directed_random_checks': extra, 'first_failures': failures,
              'scope': 'Exact integer FMA oracle; model checks do not replace RTL or all-input formal proof.'}
    (out/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    if failures:
        raise RuntimeError('segmented model mismatch')


if __name__ == '__main__':
    main()
