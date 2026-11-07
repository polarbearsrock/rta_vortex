#!/usr/bin/env python3
"""Probe narrow FMA windows where unnormalized subnormal operands can cancel."""
import json
from pathlib import Path
import random
from reference import fma, approximate_fma

BUILD = Path(__file__).resolve().parents[3] / 'build_ucc'
rng = random.Random(0x57494e44)
cases = []
for n in range(1, 24):
    for da in (-1, 0, 1):
        a = ((1 << n) + da) & 0x7fffff
        for e in range(90, 150):
            for b_sig in (0x800001, 0xffffff, 0x800000, 0xaaaaab):
                b = (e << 23) | (b_sig & 0x7fffff)
                rounded, _ = fma(a, b, 0)
                cases.append((a, b, rounded ^ 0x80000000))
for _ in range(30000):
    a = rng.randrange(1, 0x800000)
    b = (rng.randrange(90, 150) << 23) | rng.getrandbits(23)
    rounded, _ = fma(a, b, 0)
    cases.append((a, b, rounded ^ 0x80000000))
widths = (32, 56, 64, 65, 80)
counts = {w: {'value_mismatches': 0, 'flag_mismatches': 0, 'first': None} for w in widths}
out = BUILD / 'ucc_fma_window_sweep'
out.mkdir(exist_ok=True)
with (out / 'ieee_vectors.txt').open('w') as vectors:
    for a, b, c in cases:
        for rm in range(4):
            expected, ef = fma(a, b, c, rm)
            vectors.write(f'{a:08x} {b:08x} {c:08x} 0 {rm:x} {expected:08x} {ef:02x}\n')
            for w in widths:
                result, flags = approximate_fma(a, b, c, rm, w, 11)
                counts[w]['value_mismatches'] += result != expected
                counts[w]['flag_mismatches'] += flags != ef
                if (result, flags) != (expected, ef) and counts[w]['first'] is None:
                    counts[w]['first'] = {'a': a, 'b': b, 'c': c, 'rm': rm,
                                          'actual': [result, flags], 'expected': [expected, ef]}
report = {'cases': len(cases)*4, 'chunk': 11, 'windows': counts,
          'limitation': 'Targeted empirical test, not a formal all-input proof.'}
(out / 'results.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
