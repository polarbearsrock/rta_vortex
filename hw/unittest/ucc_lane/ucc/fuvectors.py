"""Vectors for the UCC FU's operations beyond those of vectors.py (the FMA datapath in RNE, the SFU's functions and
INT32): the FMA in the other rounding modes, ADD, SUB and MUL, the compare unit's functions, the
conversions, a stream of every opcode at random, and the rounding modes FPnew does not name (5-7). Each is a stream
of operations (op, rm, a, b, c, d), one per
cycle (``opcodes``; op None for a cycle that issues none), with d the FU's result from the references alone
(``opcodes.evaluate``), cross-checked independently wherever possible (``check``). Operand bits an operation does
not read are random, and the FU must ignore them: an FP32 operand's upper word where the operation reads bits 31-0,
and the operands it does not take.
"""

from fractions import Fraction
import struct

from . import dpavectors, fpops, opcodes
from .models import FP32, FP64, decode
from .opcodes import M32, fp

ARITH_SEED = 0x55434336_524D4F44
CMP_SEED = 0x55434336_434D5050
CVT_SEED = 0x55434336_43565453
FU_MIXED_SEED = 0x55434336_414C4C46
FU_MIXED = 60000
RESERVED_RM_SEED = 0x55434336_52534D44
RESERVED_RM = 6000
RESERVED_MODES = (5, 6, 7)  # rounding-mode codes FPnew does not name for the FMA path and the conversions: RNE
MODES = fpops.MODES
BUBBLE = (None, 0, 0, 0, 0, None)
CMP_FUNCS = ("MIN", "MAX", "NEG", "ABS", "EQ", "NE", "LT", "LE", "GT", "GE")
C_NAME = {FP64: "f64", FP32: "f32"}


def enc(fmt, s, e, m):
    return s << fmt.width - 1 | e << fmt.mantissa | m


def rand_fp(rng, fmt, lo=1, hi=None, sign=None):
    """A random encoding with a biased exponent in [lo, hi) (default: any normal value)."""
    hi = fmt.top if hi is None else hi
    s = rng.getrandbits(1) if sign is None else sign
    return enc(fmt, s, rng.randrange(lo, hi), rng.getrandbits(fmt.mantissa))


def subnormal(rng, fmt, sign=None):
    """A random nonzero subnormal with a random number of significant bits."""
    s = rng.getrandbits(1) if sign is None else sign
    return enc(fmt, s, 0, rng.getrandbits(rng.randrange(1, fmt.mantissa + 1)) or 1)


def specials(fmt):
    """Signed zeros, both ends of the subnormal and normal ranges, 0.5, 1 and its neighbours, 3, the largest
    binade's first value, infinities, and quiet and signalling NaNs with payloads."""
    m = fmt.mantissa
    one = fmt.bias << m
    magnitudes = (
        0, 1, (1 << m) - 1, 1 << m, fmt.bias - 1 << m, one, one + 1, one - 1, fmt.bias + 1 << m | 1 << m - 1,
        fmt.top - 1 << m, fmt.inf - 1, fmt.inf, fmt.qnan, fmt.qnan | 0x1234, fmt.inf | 1, fmt.inf | (1 << m - 1) - 1,
    )
    return [s | x for s in (0, fmt.sign) for x in magnitudes]


def operand(fmt, x, rng):
    """x as a 64-bit operand: an FP64 value as it is, an FP32 value in bits 31-0 under a random upper word."""
    return x if fmt is FP64 else rng.getrandbits(32) << 32 | x


def row(op, rm, a, b, c):
    return op, rm, a, b, c, opcodes.evaluate(op, rm, a, b, c)


def value(fmt, x):
    """x as a Python float (an FP32 value is exact in a double)."""
    if fmt is FP64:
        return struct.unpack("<d", struct.pack("<Q", x))[0]
    return struct.unpack("<f", struct.pack("<I", x))[0]


def check(op, rm, a, b, c, d):
    """Check result d against an independent computation where there is one, and return its name, else None: the
    C library for arithmetic and conversions in every mode but RMM (a NaN from C must be the canonical NaN here),
    Python's float comparisons, min and max for the compare unit, and the exact dot product for DPA-16
    (``dpavectors.check``)."""
    if opcodes.unit(op) == "dpa":
        return dpavectors.check(op, rm, a, b, c, d)
    u, f = opcodes.unit(op), opcodes.fmt(op)
    func = opcodes.NAMES.get(op & opcodes.FUNC)
    where = (opcodes.name(op), rm, f"{a:016x}", f"{b:016x}", f"{c:016x}", f"{d:016x}")
    word = (1 << f.width) - 1
    if u in ("fma", "cvt") and rm == fpops.RMM:
        return None
    box = opcodes.BOX if f is FP32 else 0  # an FP32 value's upper word
    if u == "fma":
        want = fpops.c_arith(func.lower(), f, rm, a & word, b & word, c & word)
        assert d == box | (f.qnan if fpops.is_nan(f, want) else want), (*where, f"{want:x}")
        return "c"
    if u == "cvt":
        if func in ("TO_S32", "TO_U32"):
            lo, hi = (-(1 << 31), (1 << 31) - 1) if func == "TO_S32" else (0, M32)
            if fpops.is_nan(f, a & word):
                assert d == hi & M32, where
                return "nan"
            k = fpops.c_convert(f"s32.{C_NAME[f]}", rm, a & word)
            if k is None:
                return None
            assert d == min(max(k, lo), hi) & M32, (*where, k)
            return "c"
        if func == "CVT_F":
            src = FP64 if f is FP32 else FP32
            want = fpops.c_convert(f"{C_NAME[f]}.{C_NAME[src]}", rm, a & (1 << src.width) - 1)
        else:
            want = fpops.c_convert(f"{C_NAME[f]}.{'s32' if func == 'CVT_S32' else 'u32'}", rm, a & M32)
        assert d & word == (f.qnan if fpops.is_nan(f, want) else want), (*where, f"{want:x}")
        return "c"
    if u == "cmp" and func not in ("NEG", "ABS"):
        x, y = a & word, b & word
        fx, fy = value(f, x), value(f, y)
        if func in ("MIN", "MAX"):
            if fx != fx and fy != fy:
                want = f.qnan
            elif fx != fx or fy != fy:
                want = x if fy != fy else y
            elif fx == fy == 0:  # -0 < +0
                want = x & y if func == "MAX" else x | y
            else:
                want = x if (fx < fy if func == "MIN" else fx > fy) else y
            want |= box
        else:  # 0 or 1, zero-extended in either format
            want = int({"EQ": fx == fy, "NE": fx != fy, "LT": fx < fy, "LE": fx <= fy, "GT": fx > fy,
                        "GE": fx >= fy}[func])
        assert d == want, where
        return "python"
    return None


def summary(ops, cross_check=True, removed=None):
    """A stream's counts: cycles, operations per unit and rounding mode, results checked in simulation, results
    the issue rules removed, and the independent cross-checks of the expected results."""
    units, modes, checks = {}, {}, {}
    for op, rm, a, b, c, d in ops:
        if op is None:
            continue
        u = opcodes.unit(op)
        units[u] = units.get(u, 0) + 1
        if u in ("fma", "cvt"):
            mode = fpops.MODE_NAMES[rm] if rm in MODES else f"rm{rm}"
            modes[mode] = modes.get(mode, 0) + 1
        if cross_check and d is not None:
            how = check(op, rm, a, b, c, d) or "none"
            checks[how] = checks.get(how, 0) + 1
    out = dict(cycles=len(ops), operations=sum(units.values()), units=units, rounding_modes=modes,
               checked=sum(op[5] is not None for op in ops))
    if cross_check:
        out["cross_checks"] = checks
    if removed is not None:
        out["removed"] = removed
    return out


# ---------------------------------------------------------------------------
# FMA, ADD, SUB and MUL
# ---------------------------------------------------------------------------


def fma_modes(rows64, rows32, rng):
    """vectors.py's FMA vectors (a, b, c, d), validated in RNE, in RTZ, RDN, RUP and RMM: an FP64 stream and an
    FP32 one, each FP32 operand under a random upper word."""
    op64, op32 = fp("FMA"), fp("FMA", True)
    ops64 = [row(op64, rm, a, b, c) for rm in MODES[1:] for a, b, c, _ in rows64]
    ops32 = [row(op32, rm, *(operand(FP32, x, rng) for x in (a, b, c))) for rm in MODES[1:] for a, b, c, _ in rows32]
    return ops64, ops32


def add_pairs(rng, fmt):
    """(x, y) operands for ADD and SUB, and their kinds: every pair of specials, exponents within the alignment
    window and far apart, near and exact cancellation, y half an ulp of x (an exact tie) or near it, sums at the
    overflow threshold, subnormal and tiny operands, random encodings."""
    rows, kinds = [], {}

    def add(kind, x, y):
        rows.append((x, y))
        kinds[kind] = kinds.get(kind, 0) + 1

    p, mask = fmt.mantissa + 1, (1 << fmt.width) - 1
    for x in specials(fmt):
        for y in specials(fmt):
            add("special", x, y)
    for _ in range(6000):
        ex = rng.randrange(1, fmt.top)
        ey = min(fmt.top - 1, max(1, ex + rng.randrange(-p - 3, p + 4)))
        add("near", rand_fp(rng, fmt, ex, ex + 1), rand_fp(rng, fmt, ey, ey + 1))
    for _ in range(3000):
        ex = rng.randrange(1, fmt.top)
        ey = ex + rng.choice((-1, 1)) * rng.randrange(p + 4, 4 * p)
        if 1 <= ey < fmt.top:
            add("far", rand_fp(rng, fmt, ex, ex + 1), rand_fp(rng, fmt, ey, ey + 1))
    for _ in range(3000):
        x = rand_fp(rng, fmt)
        add("cancel", x, (x ^ fmt.sign) + rng.randrange(-3, 4) & mask)
    for _ in range(3000):
        ex = rng.randrange(p + 2, fmt.top)
        x = rand_fp(rng, fmt, ex, ex + 1)
        m = 0 if rng.getrandbits(1) else rng.getrandbits(fmt.mantissa)
        add("tie", x, enc(fmt, rng.getrandbits(1), ex - p, m))
    for _ in range(1000):
        s = rng.getrandbits(1)
        ey = fmt.top - 1 - rng.randrange(0, p + 2)
        y = rand_fp(rng, fmt, ey, ey + 1, s if rng.randrange(5) else 1 - s)
        add("overflow", rand_fp(rng, fmt, fmt.top - 1, fmt.top, s), y)
    for _ in range(2000):
        x, y = (subnormal(rng, fmt) if rng.getrandbits(1) else rand_fp(rng, fmt, 1, 3) for _ in range(2))
        add("subnormal", x, y)
    for _ in range(3000):
        add("random", rng.getrandbits(fmt.width), rng.getrandbits(fmt.width))
    return rows, kinds


def add_sub_mul(rows64, rows32, rng):
    """ADD and SUB of every add_pairs pair in every rounding mode, and MUL of every FMA vector's a and b in a random
    one, in FP64 and FP32 (each FP32 operand under a random upper word), in a random order."""
    ops, kinds = [], {}
    for f in (FP64, FP32):
        pairs, kinds[f.name] = add_pairs(rng, f)
        for x, y in pairs:
            x, y = operand(f, x, rng), operand(f, y, rng)
            for name in ("ADD", "SUB"):
                for rm in MODES:
                    ops.append(row(fp(name, f is FP32), rm, x, y, rng.getrandbits(64)))
    for a, b, _, _ in rows64:
        ops.append(row(fp("MUL"), rng.choice(MODES), a, b, rng.getrandbits(64)))
    for a, b, _, _ in rows32:
        a, b = operand(FP32, a, rng), operand(FP32, b, rng)
        ops.append(row(fp("MUL", True), rng.choice(MODES), a, b, rng.getrandbits(64)))
    rng.shuffle(ops)
    return ops, kinds


# ---------------------------------------------------------------------------
# The compare unit: MIN, MAX, NEG, ABS and the compares
# ---------------------------------------------------------------------------


def cmp_pairs(rng, fmt):
    """(x, y) for the compare unit, and their kinds: every pair of specials, equal values, values and their
    negations, values of one exponent, neighbouring encodings, random encodings."""
    rows, kinds = [], {}

    def add(kind, x, y):
        rows.append((x, y))
        kinds[kind] = kinds.get(kind, 0) + 1

    def any_value():
        pick = rng.randrange(4)
        if pick == 0:
            return rand_fp(rng, fmt)
        if pick == 1:
            return subnormal(rng, fmt)
        return rng.getrandbits(fmt.width) if pick == 2 else rng.choice(specials(fmt))

    mask = (1 << fmt.width) - 1
    for x in specials(fmt):
        for y in specials(fmt):
            add("special", x, y)
    for _ in range(600):
        x = any_value()
        add("equal", x, x)
    for _ in range(600):
        x = any_value()
        add("negated", x, x ^ fmt.sign)
    for _ in range(1000):
        e = rng.randrange(fmt.top)
        add("same_exponent", *(enc(fmt, rng.getrandbits(1), e, rng.getrandbits(fmt.mantissa)) for _ in range(2)))
    for _ in range(600):
        x = any_value()
        add("adjacent", x, x + rng.choice((-1, 1)) & mask)
    for _ in range(1200):
        add("random", rng.getrandbits(fmt.width), rng.getrandbits(fmt.width))
    return rows, kinds


def cmp_ops(rng):
    """Every cmp_pairs pair of both formats through each of the compare unit's functions, in a random order and a
    random rounding mode (which they ignore), each FP32 operand under a random upper word."""
    ops, kinds = [], {}
    for f in (FP64, FP32):
        pairs, kinds[f.name] = cmp_pairs(rng, f)
        for a, b in pairs:
            a, b = operand(f, a, rng), operand(f, b, rng)
            for func in CMP_FUNCS:
                ops.append(row(fp(func, f is FP32), rng.choice(MODES), a, b, rng.getrandbits(64)))
    rng.shuffle(ops)
    return ops, kinds


# ---------------------------------------------------------------------------
# Conversions
# ---------------------------------------------------------------------------


def cvt_ops(rng):
    """The conversions, in a random order: FP64 to FP32 of FP64 specials, random encodings, and values at, halfway
    between, just off halfway between and between FP32 values (from zero and the subnormals to the overflow
    threshold), in every rounding mode; FP32 to FP64 (exact) of FP32 specials and random encodings; int32 to FP32
    and FP64, signed and unsigned, of corner integers, random integers and integers whose FP32 rounding is a tie or
    near one, in every mode; FP32 and FP64 to int32, signed and unsigned, of specials and values at, around and
    between integers, at the int32 ranges' ends, in every mode."""
    ops, kinds = [], {}

    def add(kind, func, fp32, x, modes=MODES):
        for rm in modes:
            ops.append(row(fp(func, fp32), rm, x, rng.getrandbits(64), rng.getrandbits(64)))
        key = f"{opcodes.name(fp(func, fp32))}.{kind}"
        kinds[key] = kinds.get(key, 0) + 1

    # FP64 to FP32
    m32 = FP32.mantissa
    for x in specials(FP64):
        add("special", "CVT_F", True, x)
    for _ in range(4000):
        pick = rng.randrange(8)
        if pick == 0:
            t = 0
        elif pick == 1:
            t = FP32.inf - 1  # the largest FP32 value: its tie is the overflow threshold
        elif pick == 2:
            t = subnormal(rng, FP32, 0)
        elif pick == 3:
            t = rng.randrange(0, 1 << m32 + 1)  # the subnormals and the first binade
        else:
            t = rand_fp(rng, FP32, sign=0)
        v = decode(FP32, t)[2]
        ulp = Fraction(2) ** (max(t >> m32, 1) - FP32.bias - m32)
        kind = rng.choice(("exact", "tie", "above_tie", "below_tie", "between"))
        w = v + {"exact": 0, "tie": ulp / 2, "above_tie": ulp / 2 + ulp / 2**20, "below_tie": ulp / 2 - ulp / 2**20,
                 "between": ulp * Fraction(rng.getrandbits(20), 1 << 20)}[kind]
        x = 0 if w == 0 else fpops.round_rational(FP64, w, fpops.RNE)
        add(kind, "CVT_F", True, rng.getrandbits(1) << 63 | x)
    for _ in range(500):
        add("random", "CVT_F", True, rng.getrandbits(64))
    # FP32 to FP64
    for x in specials(FP32):
        add("special", "CVT_F", False, operand(FP32, x, rng), (rng.choice(MODES),))
    for _ in range(2000):
        x = subnormal(rng, FP32) if rng.randrange(4) == 0 else rng.getrandbits(32)
        add("random", "CVT_F", False, operand(FP32, x, rng), (rng.choice(MODES),))
    # int32 to FP32 and FP64
    ints = [(x, "corner") for x in (0, 1, 2, 3, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0xFFFFFFFE, 1 << 24,
                                    (1 << 24) + 1, (1 << 24) + 3, (1 << 25) + 2, (1 << 25) + 6, 0x7FFFFFC0,
                                    0x7FFFFF80, 0xFFFFFF80, 0xFFFFFFC0)]
    for _ in range(1500):
        pick = rng.randrange(3)
        if pick == 0:
            ints.append((rng.getrandbits(32), "random"))
        elif pick == 1:
            ints.append((rng.getrandbits(rng.randrange(1, 33)), "short"))
        else:  # 24 significant bits, then a tie or a near one
            rest = rng.randrange(1, 9)
            tail = 1 << rest - 1 if rng.getrandbits(1) else rng.getrandbits(rest)
            x = (rng.getrandbits(23) | 1 << 23) << rest | tail
            ints.append((-x & M32 if rng.getrandbits(1) and x < 1 << 31 else x, "fp32_tie"))
    for x, kind in ints:
        for func in ("CVT_S32", "CVT_U32"):
            for fp32 in (True, False):
                add(kind, func, fp32, rng.getrandbits(32) << 32 | x)
    # FP32 and FP64 to int32
    offsets = (0, Fraction(1, 4), Fraction(1, 2), Fraction(3, 4), Fraction(1, 1 << 20))
    for f in (FP64, FP32):
        values = [(x, "special") for x in specials(f)]
        for k in (0, 1, 2, (1 << 31) - 1, 1 << 31, (1 << 31) + 1, (1 << 32) - 1, 1 << 32, (1 << 32) + 1):
            for off in offsets:
                for v in (k + off, k - off, -k + off, -k - off):
                    if v:
                        values.append((fpops.round_rational(f, Fraction(v), fpops.RNE), "boundary"))
        for _ in range(1500):
            k = rng.getrandbits(rng.randrange(0, 34))
            off = rng.choice(offsets) if rng.getrandbits(1) else Fraction(rng.getrandbits(16), 1 << 16)
            v = (k + off) * rng.choice((-1, 1))
            values.append((fpops.round_rational(f, Fraction(v), fpops.RNE) if v else 0, "near_integer"))
        for x, kind in values:
            for func in ("TO_S32", "TO_U32"):
                add(kind, func, f is FP32, operand(f, x, rng))
    rng.shuffle(ops)
    return ops, kinds


# ---------------------------------------------------------------------------
# Every opcode at random
# ---------------------------------------------------------------------------


def mixed_fu(pools, rng):
    """FU_MIXED cycles, each an operation drawn at random from the pools (a list of operations per unit), a reserved
    opcode (with random operands and rounding mode) or none, then settled (``opcodes.settle``): the stream and how
    many results each issue rule removed. a's and b's bits above 63 are random in every operation but DPA-16's."""
    reserved = [op for op in range(1 << 7) if opcodes.unit(op) == "none"]
    weights = dict(fma=24, alu=12, imul=10, cmp=12, cvt=12, sfu=8, dpa=8, none=4, bubble=10)
    wide = dpavectors.DPA_OPERAND
    ops = []
    for _ in range(FU_MIXED):
        kind = rng.choices(tuple(weights), tuple(weights.values()))[0]
        if kind == "bubble":
            ops.append(BUBBLE)
        elif kind == "none":
            ops.append(row(rng.choice(reserved), rng.choice(MODES), rng.getrandbits(wide), rng.getrandbits(wide),
                           rng.getrandbits(64)))
        else:
            ops.append(dpavectors.widen(rng, rng.choice(pools[kind])))
    return opcodes.settle(ops)


def reserved_modes(pools, rng):
    """RESERVED_RM operations, half of the FMA path and half conversions, drawn from the pools' RNE ones and issued
    again in the rounding modes FPnew does not name (RESERVED_MODES), which round to nearest even: their expected
    results are the RNE ones the pools' streams cross-checked, and ``opcodes.evaluate`` must agree. The FMA-path
    block comes first, then an idle cycle, so that no conversion's result meets an FMA's."""
    ops = []
    for kind in ("fma", "cvt"):
        rne = [op for op in pools[kind] if op[1] == fpops.RNE]
        ops += [(op, rng.choice(RESERVED_MODES), a, b, c, d)
                for op, rm, a, b, c, d in rng.choices(rne, k=RESERVED_RM // 2)]
        if kind == "fma":
            ops.append(BUBBLE)
    for op, rm, a, b, c, d in ops:
        assert op is None or opcodes.evaluate(op, rm, a, b, c) == d, (opcodes.name(op), rm)
    return ops
