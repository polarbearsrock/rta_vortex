"""Integer model of grouped low-precision products and bounded TFR accumulation."""
from pathlib import Path
import random
from reference import classify, QNAN


def decode(bits, eb, fb, finite_only=False):
    e, f = (bits >> fb) & ((1 << eb) - 1), bits & ((1 << fb) - 1)
    nan = e == (1 << eb) - 1 and (f == (1 << fb) - 1 if finite_only else f != 0)
    inf = not finite_only and e == (1 << eb) - 1 and f == 0
    return {'sign': (bits >> (eb + fb)) & 1, 'sig': f | ((1 << fb) if e else 0),
            'e': max(e, 1), 'nan': nan, 'inf': inf, 'zero': e == f == 0}


def dpa(fmt, mask, a, b, c, scale_a, scale_b):
    terms, inf_signs = [], set()
    nan = False
    stride, eb, fb = {1:(8,8,10), 2:(4,5,10), 3:(4,8,7),
                     4:(2,4,3), 5:(2,5,2), 10:(1,2,1), 11:(1,2,1)}[fmt]
    width = 4 * stride
    for group in range(16):
        local = []
        sa, sb = (scale_a >> (8*(group//4))) & 255, (scale_b >> (8*(group//4))) & 255
        for slot in range(group*4, group*4+4, stride):
            if slot % stride or not (mask >> slot) & 1:
                continue
            av = (a[slot//8] >> (4*(slot%8))) & ((1 << width)-1)
            bv = (b[slot//8] >> (4*(slot%8))) & ((1 << width)-1)
            x, y = decode(av, eb, fb, fmt == 4), decode(bv, eb, fb, fmt == 4)
            if fmt >= 10:
                x['nan'] = y['nan'] = x['inf'] = y['inf'] = False
            sign = x['sign'] ^ y['sign']
            nan |= x['nan'] or y['nan'] or (x['inf'] and y['zero']) or (y['inf'] and x['zero'])
            if x['inf'] or y['inf']:
                inf_signs.add(sign)
            sig = x['sig'] * y['sig']
            exponent = x['e'] + y['e']
            if fmt <= 3:
                # All half/TF products enter the same 11-bit-significand bank.
                sig <<= 2*(10-fb) + 4
                exponent += 262 - 2*((1 << (eb-1))-1)
                local.append((sig, exponent, sign))
            elif fmt <= 5:
                sig <<= 2*(3-fb) + 16
                local.append((sig, exponent, sign))
            else:
                exponent -= 2
                if fmt == 11:
                    sx, sy = decode(sa & 127, 4, 3, True), decode(sb & 127, 4, 3, True)
                    nan |= sx['nan'] or sy['nan']
                    sig *= sx['sig'] * sy['sig']
                    exponent += sx['e'] + sy['e']
                else:
                    nan |= sa == 255 or sb == 255
                    exponent += sa + sb
                local.append((sig << 11, exponent, sign))
        nonzero = [(m,e,s) for m,e,s in local if m]
        if not nonzero:
            continue
        maximum = max(e for _,e,_ in nonzero)
        total = sum((-1 if s else 1) * (m >> (maximum-e)) for m,e,s in nonzero)
        if not total:
            continue
        if fmt <= 3:
            terms.append((abs(total), maximum, int(total < 0)))
        elif fmt <= 5:
            terms.append(((abs(total) >> 1) << 2, maximum + 263 - 2*((1 << (eb-1))-1), int(total < 0)))
        else:
            terms.append((abs(total) << 2, maximum + (251 if fmt == 11 else 17), int(total < 0)))
    z = classify(c)
    nan |= z['nan']
    if z['inf']:
        inf_signs.add(z['sign'])
    if nan or len(inf_signs) > 1:
        return QNAN
    if inf_signs:
        return (next(iter(inf_signs)) << 31) | 0x7f800000
    if z['sig']:
        terms.append((z['sig'] << 1, z['exp'] + 285, z['sign']))
    if not terms:
        return 0
    maximum = max(e for _,e,_ in terms)
    total, sticky = 0, False
    for magnitude, exponent, sign in terms:
        kept, lost = divmod(magnitude, 1 << (maximum-exponent))
        total += -kept if sign else kept
        sticky |= lost != 0
    if not total:
        return 0
    magnitude, sign = abs(total), int(total < 0)
    normalized = magnitude << (32-magnitude.bit_length())
    kept, tail = divmod(normalized, 256)
    kept += tail > 128 or (tail == 128 and (sticky or kept & 1))
    exponent = maximum + magnitude.bit_length() - 160
    if kept >= 1 << 24:
        kept >>= 1
        exponent += 1
    if exponent <= 0:
        return sign << 31
    if exponent >= 255:
        return (sign << 31) | 0x7f800000
    return (sign << 31) | (exponent << 23) | (kept & 0x7fffff)


def generate(path):
    rng = random.Random(0x55434344)
    with Path(path).open('w') as output:
        def emit(fmt, mask, a, b, c, sa, sb):
            expected = dpa(fmt, mask, a, b, c, sa, sb)
            output.write(' '.join(f'{v:x}' for v in [fmt,mask,sa,sb,c,*a,*b,expected]) + '\n')
        for fmt in [1,2,3,4,5,10,11]:
            for _ in range(10000):
                emit(fmt,rng.getrandbits(64),[rng.getrandbits(32) for _ in range(8)],
                     [rng.getrandbits(32) for _ in range(8)],rng.getrandbits(32),rng.getrandbits(32),rng.getrandbits(32))
        for sa in range(128):
            for sb in range(128):
                emit(11,1,[2]+[0]*7,[2]+[0]*7,0,sa,sb)
        for sa in range(256):
            for sb in [0,1,63,95,127,128,159,191,254,255]:
                emit(10,1,[2]+[0]*7,[2]+[0]*7,0,sa,sb)


if __name__ == '__main__':
    import sys
    generate(sys.argv[1])
