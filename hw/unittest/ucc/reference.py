"""Integer-only binary32 FMA oracle; no intermediate host floating point."""
from enum import IntEnum


class Rounding(IntEnum):
    RNE = 0
    RTZ = 1
    RDN = 2
    RUP = 3


NX, UF, OF, DZ, NV = 1, 2, 4, 8, 16
QNAN = 0x7FC00000


def classify(x):
    exp, frac = (x >> 23) & 255, x & 0x7FFFFF
    return {
        "sign": x >> 31,
        "zero": exp == 0 and frac == 0,
        "inf": exp == 255 and frac == 0,
        "nan": exp == 255 and frac != 0,
        "snan": exp == 255 and frac != 0 and (frac & 0x400000) == 0,
        "sig": frac | (0x800000 if exp else 0),
        "exp": exp - 150 if exp else -149,
    }


def round_binary32(magnitude, exponent, sign, rm=Rounding.RNE):
    """Round a nonnegative integer times a power of two, tininess after rounding."""
    if magnitude == 0:
        return sign << 31, 0
    top = magnitude.bit_length() - 1 + exponent
    # IEEE tininess is tested with unbounded exponent, before subnormal encoding.
    tiny = top < -126
    if top == -127:
        unbounded_shift = magnitude.bit_length() - 24
        if unbounded_shift > 0:
            ub_kept, ub_lost = divmod(magnitude, 1 << unbounded_shift)
            half = 1 << (unbounded_shift - 1)
            ub_increment = ((rm == Rounding.RNE and (ub_lost > half or (ub_lost == half and ub_kept & 1)))
                            or (rm == Rounding.RUP and not sign and ub_lost != 0)
                            or (rm == Rounding.RDN and sign and ub_lost != 0))
            tiny = ub_kept + int(ub_increment) < (1 << 24)
    quantum = max(top - 23, -149)
    shift = quantum - exponent
    if shift > 0:
        kept, lost = divmod(magnitude, 1 << shift)
        midpoint = 1 << (shift - 1)
        increment = ((rm == Rounding.RNE and (lost > midpoint or (lost == midpoint and kept & 1)))
                     or (rm == Rounding.RUP and not sign and lost != 0)
                     or (rm == Rounding.RDN and sign and lost != 0))
        kept += int(increment)
    else:
        kept, lost = magnitude << -shift, 0
    if kept >= 1 << 24:
        kept >>= 1
        quantum += 1
    if quantum > 104:
        to_inf = rm == Rounding.RNE or (rm == Rounding.RUP and not sign) or (rm == Rounding.RDN and sign)
        return (sign << 31) | (0x7F800000 if to_inf else 0x7F7FFFFF), OF | NX
    normal = kept >= 1 << 23
    exp_field = quantum + 150 if normal else 0
    result = (sign << 31) | (exp_field << 23) | (kept & 0x7FFFFF)
    flags = (NX if lost else 0) | (UF if lost and tiny else 0)
    return result, flags


def fma(a, b, c, rm=Rounding.RNE):
    x, y, z = map(classify, (a, b, c))
    ps = x["sign"] ^ y["sign"]
    bad_product = (x["inf"] and y["zero"]) or (x["zero"] and y["inf"])
    product_inf = (x["inf"] or y["inf"]) and not (x["nan"] or y["nan"] or bad_product)
    bad_sum = product_inf and z["inf"] and ps != z["sign"]
    if x["nan"] or y["nan"] or z["nan"]:
        return QNAN, NV if x["snan"] or y["snan"] or z["snan"] or bad_product else 0
    if bad_product or bad_sum:
        return QNAN, NV
    if product_inf:
        return (ps << 31) | 0x7F800000, 0
    if z["inf"]:
        return (z["sign"] << 31) | 0x7F800000, 0
    pm, pe = x["sig"] * y["sig"], x["exp"] + y["exp"]
    cm, ce = z["sig"], z["exp"]
    common = min(pe, ce)
    total = ((-pm if ps else pm) << (pe - common)) + ((-cm if z["sign"] else cm) << (ce - common))
    if total == 0:
        sign = ps if pm == cm == 0 and ps == z["sign"] else int(rm == Rounding.RDN)
        return sign << 31, 0
    return round_binary32(abs(total), common, int(total < 0), rm)


def approximate_fma(a, b, c, rm=Rounding.RNE, width=32, chunk=11):
    """Round-to-odd partial terms in a bounded window, then round to binary32."""
    x, y, z = map(classify, (a, b, c))
    if any(v["nan"] or v["inf"] for v in (x, y, z)):
        return fma(a, b, c, rm)
    pzero = x["zero"] or y["zero"]
    psign = x["sign"] ^ y["sign"]
    pe = x["exp"] + y["exp"]
    top = max(-1024 if pzero else pe + 47, -1024 if z["zero"] else z["exp"] + 23)
    quantum = top - (width - 3)

    def align(sig, exponent):
        distance = quantum - exponent
        if distance <= 0:
            return sig << -distance
        q, r = divmod(sig, 1 << distance)
        return q | int(r != 0)

    product = 0
    for i in range(3):
        for j in range(3):
            ma = (x["sig"] >> (i * chunk)) & ((1 << chunk) - 1)
            mb = (y["sig"] >> (j * chunk)) & ((1 << chunk) - 1)
            product += align(ma * mb, pe + (i + j) * chunk)
    addend = align(z["sig"], z["exp"])
    total = (-product if psign else product) + (-addend if z["sign"] else addend)
    if total == 0:
        zs = psign if pzero and z["zero"] and psign == z["sign"] else int(rm == Rounding.RDN)
        return zs << 31, 0
    return round_binary32(abs(total), quantum, int(total < 0), rm)


def native_bf16x9_fma(a, b, c):
    """Eight-bit slices using the unchanged TFR 26-bit alignment window and RNE/FTZ packer."""
    x, y, z = map(classify, (a, b, c))
    if any(v['nan'] or v['inf'] for v in (x, y, z)):
        result, flags = fma(a, b, c)
        return result, flags & NV
    psign = x['sign'] ^ y['sign']
    terms = []
    for i in range(3):
        for j in range(3):
            product = ((x['sig'] >> (8*i)) & 255) * ((y['sig'] >> (8*j)) & 255)
            exponent = x['exp'] + y['exp'] + 8*(i+j) + 308 if product else 0
            terms.append((product << 10, exponent, psign))
    terms.append((z['sig'] << 1, z['exp'] + 317 if z['sig'] else 0, z['sign']))
    maximum = max(term[1] for term in terms)
    total, sticky = 0, False
    for magnitude, exponent, sign in terms:
        kept, lost = divmod(magnitude, 1 << (maximum - exponent))
        total += -kept if sign else kept
        sticky |= lost != 0
    if total == 0:
        zs = psign if (x['zero'] or y['zero']) and z['zero'] and psign == z['sign'] else 0
        return zs << 31, 0
    sign, magnitude = int(total < 0), abs(total)
    normalized = magnitude << (32 - magnitude.bit_length())
    kept = normalized >> 8
    guard = (normalized >> 7) & 1
    remainder = normalized & 127
    kept += bool(guard and (remainder or sticky or (kept & 1)))
    exponent = maximum + magnitude.bit_length() - 192
    if kept >= 1 << 24:
        kept >>= 1
        exponent += 1
    if exponent <= 0:
        return sign << 31, 0
    if exponent >= 255:
        return (sign << 31) | 0x7f800000, 0
    return (sign << 31) | (exponent << 23) | (kept & 0x7fffff), 0
