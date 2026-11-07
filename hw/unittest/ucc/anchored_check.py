#!/usr/bin/env python3
"""Check a product-anchored window and distant-addend rounding against exact FMA."""
import json
from pathlib import Path

from reference import classify, fma, round_binary32, NX, UF, OF

BUILD = Path(__file__).resolve().parents[3] / 'build_ucc'


def anchored(a, b, c, rm):
    x, y, z = map(classify, (a, b, c))
    if any(q['nan'] or q['inf'] for q in (x,y,z)):
        return fma(a,b,c,rm)
    product, pe = x['sig']*y['sig'], x['exp']+y['exp']
    ps = x['sign']^y['sign']
    if z['sig'] and (not product or z['exp']+23 >= pe+47+27):
        if not product:
            return c,0
        up = ps == z['sign'] and ((rm == 3 and not z['sign']) or (rm == 2 and z['sign']))
        down = ps != z['sign'] and (rm == 1 or (rm == 3 and z['sign']) or (rm == 2 and not z['sign']))
        result = c + int(up)-int(down)
        tiny = ((c>>23)&255) == 0 or ((c&0x7fffffff) == 0x00800000 and down)
        overflow = (result&0x7fffffff) == 0x7f800000
        return result, NX | (UF if tiny else 0) | (OF if overflow else 0)
    base = pe-3
    distance = base-z['exp']
    if distance > 0:
        kept, lost = divmod(z['sig'],1<<distance)
        addend = kept | int(lost != 0)
    else:
        addend = z['sig']<<-distance
    total = (-product if ps else product)*8 + (-addend if z['sign'] else addend)
    if not total:
        sign = ps if not product and not z['sig'] and ps == z['sign'] else int(rm == 2)
        return sign<<31,0
    return round_binary32(abs(total),base,int(total<0),rm)


def dominance_cases():
    for ce in (0,1,2,126,127,128,253,254):
        ze = ce-150 if ce else -149
        for cf in (0,1,0x3fffff,0x7fffff):
            for gap in range(22,33):
                pe = ze-24-gap
                for ae in (0,1,2,24,64,100,127,150,200,254):
                    xe = ae-150 if ae else -149
                    be = pe-xe+150
                    if not 1 <= be <= 254:
                        continue
                    for af in (0,1,0x7fffff):
                        for bf in (0,1,0x7fffff):
                            for ps in (0,1):
                                for cs in (0,1):
                                    for rm in range(4):
                                        yield (ae<<23)|af|(ps<<31),(be<<23)|bf,(ce<<23)|cf|(cs<<31),rm


def main():
    out = BUILD/'ucc_anchor'
    out.mkdir(exist_ok=True)
    failures, count = [],0

    def check(a,b,c,rm,expected):
        nonlocal count
        actual = anchored(a,b,c,rm)
        count += 1
        if actual != expected:
            if len(failures) < 20:
                failures.append({'a':a,'b':b,'c':c,'rm':rm,'actual':actual,'expected':expected})

    for name in ('ucc_v1_csa/vectors.txt','ucc_fma_window_sweep/ieee_vectors.txt'):
        for line in (BUILD/name).read_text().splitlines():
            a,b,c,op,rm,result,flags = [int(x,16) for x in line.split()]
            if op >= 2:
                b,c = 0x3f800000,b^((op&1)<<31)
            elif op == 1:
                c = (a^b)&0x80000000
            check(a,b,c,rm,(result,flags))
    dominance_count = 0
    with (out/'dominance_vectors.txt').open('w') as vectors:
        for a,b,c,rm in dominance_cases():
            expected = fma(a,b,c,rm)
            check(a,b,c,rm,expected)
            vectors.write(f'{a:x} {b:x} {c:x} 0 {rm:x} {expected[0]:x} {expected[1]:x}\n')
            dominance_count += 1
    report = {'checks':count,'dominance_checks':dominance_count,'first_failures':failures,
              'limitation':'Finite arithmetic model and directed tests, not a formal proof or RTL result.'}
    (out/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if failures:
        raise RuntimeError('anchored arithmetic differs from IEEE reference')


if __name__ == '__main__':
    main()
