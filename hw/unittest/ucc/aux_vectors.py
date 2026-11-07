import itertools
from pathlib import Path
import random
import struct
from reference import classify, round_binary32, NV, NX, QNAN


def convert(x, op, rm):
    if op in (0x40, 0x41):
        value = x - (1 << 32) if op == 0x40 and x >= 1 << 31 else x
        return round_binary32(abs(value), 0, int(value < 0), rm)
    unsigned = op == 0x43
    value = classify(x)
    low, high = (0, (1 << 32) - 1) if unsigned else (-(1 << 31), (1 << 31) - 1)
    if value['nan']:
        return 0, NV
    if value['inf']:
        return (low if value['sign'] else high) & 0xffffffff, NV
    numerator = value['sig'] << max(value['exp'], 0)
    denominator = 1 << max(-value['exp'], 0)
    q, r = divmod(numerator, denominator)
    increment = ((rm == 0 and (2*r > denominator or (2*r == denominator and q & 1)))
                 or (rm == 2 and value['sign'] and r != 0)
                 or (rm == 3 and not value['sign'] and r != 0))
    rounded = (q + int(increment)) * (-1 if value['sign'] else 1)
    if rounded < low or rounded > high:
        return min(max(rounded, low), high) & 0xffffffff, NV
    return rounded & 0xffffffff, NX if r else 0


def compare(a, b, op):
    x, y = classify(a), classify(b)
    flags = NV if x['snan'] or y['snan'] else 0
    nan = x['nan'] or y['nan']
    zeros = x['zero'] and y['zero']
    # Ordering maps IEEE encodings to monotonically increasing integer keys.
    key = lambda bits: -(bits & 0x7fffffff) if bits >> 31 else bits
    equal, less = key(a) == key(b), key(a) < key(b)
    predicates = [not nan and equal, nan or not equal, not nan and less,
                  not nan and (less or equal), not nan and not (less or equal), not nan and not less]
    if op <= 0x0d:
        return int(predicates[op-8]), flags, int(predicates[op-8])
    if x['nan'] and y['nan']:
        result = QNAN
    elif x['nan']:
        result = b
    elif y['nan']:
        result = a
    elif zeros:
        result = ((x['sign'] and y['sign']) if op == 0xf else (x['sign'] or y['sign'])) << 31
    else:
        result = (a if less else b) if op == 0xe else (b if less else a)
    return result, flags, int(not nan and less)


def generate(path, extended=False, narrow=False, natural=False, compact=False):
    rng = random.Random(0x41555833)
    floats = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000,
              0x3effffff, 0x3f000000, 0x3f000001, 0xbf000000, 0x3fc00000, 0xbfc00000,
              0x4effffff, 0x4f000000, 0x4f000001, 0xcf000000, 0xcf000001,
              0x4f7fffff, 0x4f800000, 0x7f7fffff, 0xff7fffff,
              0x7f800000, 0xff800000, 0x7fc00000, 0x7f800001]
    cases = [(x, 0, op, rm) for x in floats + [0xffffffff, 0x7fffffff]
             for op in range(0x40, 0x44) for rm in range(4)]
    cases += [(rng.getrandbits(32), 0, rng.randrange(0x40, 0x44), rng.randrange(4))
              for _ in range(100000)]
    cases += [(a, b, op, 0) for a, b in itertools.product(floats, repeat=2) for op in range(8, 16)]
    cases += [(rng.getrandbits(32), rng.getrandbits(32), rng.randrange(8, 16), 0)
              for _ in range(100000)]
    cases += [(rng.getrandbits(32), shift, op, 0) for shift in range(256) for op in range(0x30, 0x34)]
    cases += [(rng.getrandbits(32), rng.getrandbits(32), rng.randrange(0x30, 0x34), 0)
              for _ in range(100000)]
    cases += [(rng.getrandbits(32), 0, rng.randrange(4, 6), 0) for _ in range(1000)]
    if extended:
        cases += [(rng.getrandbits(32), rng.getrandbits(32), rng.randrange(0x50, 0x57), 0)
                  for _ in range(100000)]
        to_bits = lambda x: struct.unpack('<I', struct.pack('<f', x))[0]
        exp_inputs = [rng.getrandbits(32) for _ in range(25000)]
        exp_inputs += [to_bits(rng.uniform(-150, 128)) for _ in range(75000)]
        exp_inputs += [to_bits(n + j / 64) for n in (-150, -149, -127, -126, -1, 0, 1, 126, 127) for j in range(65)]
        cases += [(x, 0, 0x60, 0) for x in exp_inputs]
        from ex2_reference import report_accuracy
        report_accuracy(exp_inputs, Path(path).with_suffix('.ex2_accuracy.json'), narrow, compact=compact)
        if natural:
            natural_inputs = [rng.getrandbits(32) for _ in range(25000)]
            natural_inputs += [to_bits(rng.uniform(-104, 89)) for _ in range(75000)]
            natural_inputs += [to_bits(n + j/64) for n in (-104, -100, -80, -10, -1, 0, 1, 10, 80, 88) for j in range(65)]
            cases += [(x, 0, 0x61, 0) for x in natural_inputs]
            report_accuracy(natural_inputs, Path(path).with_suffix('.exp_accuracy.json'), narrow, True, compact)
    with Path(path).open('w') as out:
        for a, b, op, rm in cases:
            predicate = 0
            c, immediate = rng.getrandbits(32), rng.randrange(256)
            if op in (0x60, 0x61):
                from ex2_reference import ex2
                result, flags = ex2(a, narrow, op == 0x61, compact), 0
            elif op >= 0x50:
                table = sum(((immediate >> ((((a >> i) & 1) << 2) | (((b >> i) & 1) << 1) | ((c >> i) & 1))) & 1) << i
                            for i in range(32))
                result = {0x50: a & b, 0x51: a | b, 0x52: a ^ b, 0x53: ~a,
                          0x54: table, 0x55: a if c & 1 else b, 0x56: a}[op] & 0xffffffff
                flags = 0
            elif op >= 0x40:
                result, flags = convert(a, op, rm)
            elif op >= 0x30:
                count = b & 31
                signed = a - (1 << 32) if a >> 31 else a
                result = {0x30: a << count, 0x31: a >> count, 0x32: signed >> count,
                          0x33: 32 - a.bit_length()}[op] & 0xffffffff
                flags = 0
            elif op >= 8:
                result, flags, predicate = compare(a, b, op)
            else:
                result, flags = (a ^ 0x80000000 if op == 4 else a & 0x7fffffff), 0
            line = f'{a:08x} {b:08x} {c:08x} {op:02x} {rm:x} {result:08x} {flags:02x} {predicate:x}'
            out.write(line + (f' {immediate:02x}' if extended else '') + '\n')
    return len(cases)
