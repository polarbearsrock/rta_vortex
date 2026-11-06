"""The FU's opcode map and issue rules, and the floating-point reference against known results and the C library."""

import random
import re
from fractions import Fraction

import pytest

from .. import fpops, intops, opcodes
from ..fuvectors import BUBBLE, check, row, specials
from ..models import FP32, FP64
from ..opcodes import fp
from ..paths import RTL

RNE, RTZ, RDN, RUP, RMM = fpops.MODES


def test_map_matches_ucc_pkg():
    """FUNCS and DPA-16's function code are ucc_pkg's FP_* codes, and every opcode has the unit the map gives it."""
    text = (RTL / "ucc_pkg.sv").read_text()
    codes = re.findall(r"localparam logic \[4:0\]\s+FP_(\w+)\s*= 5'h([0-9A-F]{2});", text)
    assert {name: int(value, 16) for name, value in codes} == dict(opcodes.FUNCS, DPA=opcodes.DPA_FUNC)
    units = [opcodes.unit(op) for op in range(128)]
    assert units[:64] == ["alu"] * 32 + ["imul"] * 32
    counts = {u: units[64:].count(u) for u in set(units[64:])}
    assert counts == dict(fma=8, cmp=20, cvt=10, sfu=7, dpa=8, none=11)
    assert units[0x58:0x60] == ["dpa"] * 8
    assert [opcodes.name(op) for op in (0x40, 0x61, 0x72, 0x55, 0x78, 0x7E, 0x58, 0x5D, 0x5E, 0x5F, 0x57, 0x7F, 0x44,
                                        0x66)] == [
        "fma.fp64", "add.fp32", "cvt_f.fp32", "to_s32.fp64", "sfu.rcp", "sfu.tanh", "dpa16.fp16", "dpa16.mxfp4",
        "dpa16.mxfp8", "dpa16.fp4", "reserved0x57", "reserved0x7f", "reserved0x44", "reserved0x66"]
    assert re.search(r"localparam int unsigned DPA_FORMATS = (\d+);", text)[1] == str(len(opcodes.dpa.FORMATS))
    # no divider: the codes DIV, SQRT and RCP had return 0 after one cycle
    assert opcodes.latency(0x44) == opcodes.latency(0x66) == 1 and opcodes.evaluate(0x45, RNE, 1, 2, 3) == 0
    assert opcodes.latency(opcodes.dpa_op(0)) == 4


def stream(*ops):
    """Operations with their results, from (opcode, ...) or None for an idle cycle."""
    return [BUBBLE if op is None else row(op, RNE, 1, 2, 3) for op in ops]


def fates(ops):
    settled, removed = opcodes.settle(ops)
    return [op[5] is not None for op in settled if op[0] is not None], removed


def test_settle_rules():
    fma, alu, mul, sfu = fp("FMA"), 0x00, 0x20, opcodes.sfu_op(0)
    # an SFU function takes the input register two cycles after its issue; another SFU function is not lost
    assert fates(stream(sfu, fma, fma, fma)) == ([True, True, False, True], dict(lost=1, hidden=0))
    assert fates(stream(sfu, None, sfu, None, fma)) == ([True, True, False], dict(lost=1, hidden=0))
    # the younger result wins: an ALU result due with an FMA's, a multiply's with an FMA's
    assert fates(stream(fma, None, alu)) == ([False, True], dict(lost=0, hidden=1))
    assert fates(stream(fma, mul)) == ([False, True], dict(lost=0, hidden=1))
    # DPA-16 (4 cycles): an FMA issued after it is younger, an SFU function before it older; it is lost in the SFU's slot
    dpa = opcodes.dpa_op(0)
    assert fates(stream(dpa, fma)) == ([False, True], dict(lost=0, hidden=1))
    assert fates(stream(sfu, dpa)) == ([False, True], dict(lost=0, hidden=1))
    assert fates(stream(sfu, None, dpa)) == ([True, False], dict(lost=1, hidden=0))
    assert fates(stream(dpa, None, mul, None, alu))[0] == [False, True, True]
    assert fates(stream(dpa, dpa, dpa))[0] == [True, True, True]


def test_flush_fates():
    fma, alu, sfu, dpa = fp("FMA"), 0x00, opcodes.sfu_op(0), opcodes.dpa_op(0)
    # a flush drops what is in flight: issued in or before its cycle, due after it; DPA-16 issued after it returns
    assert opcodes.fates(stream(fma, alu, None, dpa), [1]) == ["flushed", "flushed", None, "ok"]
    # a result due in the flush's own cycle still comes
    assert opcodes.fates(stream(fma, None, None, None), [3]) == ["ok", None, None, None]
    # an SFU function flushed before its slot leaves the slot free; flushed in it, the slot still takes the FMA
    assert opcodes.fates(stream(sfu, None, fma), [1]) == ["flushed", None, "ok"]
    assert opcodes.fates(stream(sfu, None, fma), [2]) == ["flushed", None, "lost"]
    assert opcodes.settle(stream(sfu, None, fma), [0])[1] == dict(lost=0, hidden=0, flushed=1)
    # without flushes, settle is the issue rules alone
    assert opcodes.fates(stream(sfu, None, fma, alu)) == ["ok", None, "lost", "ok"]


def test_unnamed_rounding_modes_round_to_nearest_even():
    """ucc_fma rounds the codes 5-7 to nearest even in the FMA path and the conversions."""
    one = FP64.bias << 52
    above_half = FP64.bias - 53 << 52 | 1  # just above half an ulp of 1.0
    cases = [
        (fp("ADD"), one, above_half, 0),
        (fp("FMA"), one, one, above_half),
        (fp("TO_S32"), FP64.bias + 1 << 52 | 1 << 50, 0, 0),  # 2.5
        (fp("CVT_F", True), 0x3FD5555555555555, 0, 0),  # 1/3 to FP32
        (fp("CVT_S32", True), (1 << 24) + 3, 0, 0),
    ]
    for op, a, b, c in cases:
        rne = opcodes.evaluate(op, RNE, a, b, c)
        assert rne != opcodes.evaluate(op, RTZ, a, b, c) or rne != opcodes.evaluate(op, RUP, a, b, c), op
        assert [opcodes.evaluate(op, rm, a, b, c) for rm in (5, 6, 7)] == [rne] * 3, opcodes.name(op)


def test_known_results():
    one, two = FP64.bias << 52, FP64.bias + 1 << 52
    big, tiny = FP64.inf - 1, 1
    half_ulp = FP64.bias - 53 << 52  # 2^-53: 1 + 2^-53 is halfway between 1 and its successor
    assert [fpops.add(FP64, one, half_ulp, rm) for rm in fpops.MODES] == [one, one, one, one + 1, one + 1]
    assert [fpops.mul(FP64, big, two, rm) for rm in fpops.MODES] == [FP64.inf, big, big, FP64.inf, FP64.inf]
    neg = FP64.sign
    assert [fpops.mul(FP64, neg | big, two, rm) for rm in fpops.MODES] == [
        neg | FP64.inf, neg | big, neg | FP64.inf, neg | big, neg | FP64.inf]
    assert fpops.sub(FP64, one, one, RNE) == 0 and fpops.sub(FP64, one, one, RDN) == neg
    assert fpops.mul(FP64, neg, one, RDN) == neg and fpops.mul(FP64, 0, neg | one, RNE) == neg
    assert fpops.fma(FP64, tiny, FP64.bias - 1 << 52, 0, RUP) == tiny  # half the smallest subnormal rounds up
    assert fpops.fma(FP64, tiny, FP64.bias - 1 << 52, 0, RMM) == tiny
    assert fpops.fma(FP64, tiny, FP64.bias - 1 << 52, 0, RNE) == 0
    # 5/2 of the smallest subnormal: RNE rounds to even, RMM away from zero
    assert fpops.fma(FP64, 5, FP64.bias - 1 << 52, 0, RNE) == 2
    assert fpops.fma(FP64, 5, FP64.bias - 1 << 52, 0, RMM) == 3


def test_conversions():
    nan32, nan64 = FP32.qnan, FP64.qnan
    assert fpops.to_int(FP64, nan64, True, RNE) == 0x7FFFFFFF and fpops.to_int(FP64, nan64, False, RNE) == 0xFFFFFFFF
    assert fpops.to_int(FP64, FP64.sign | FP64.inf, True, RNE) == 0x80000000
    assert fpops.to_int(FP64, FP64.sign | FP64.inf, False, RNE) == 0
    minus_half = FP64.sign | FP64.bias - 1 << 52
    assert fpops.to_int(FP64, minus_half, False, RNE) == 0 and fpops.to_int(FP64, minus_half, True, RDN) == 0xFFFFFFFF
    almost = fpops.round_rational(FP64, Fraction(2**32) - Fraction(1, 2), RNE)  # ties to even, 2^32: saturates
    assert fpops.to_int(FP64, almost, False, RNE) == 0xFFFFFFFF and fpops.to_int(FP64, almost, False, RDN) == 0xFFFFFFFF
    assert fpops.to_int(FP32, 0xCF000000, True, RNE) == 0x80000000  # -2^31 exactly
    assert [fpops.from_int(FP32, (1 << 24) + 1, True, rm) for rm in fpops.MODES] == [
        0x4B800000, 0x4B800000, 0x4B800000, 0x4B800001, 0x4B800001]
    assert fpops.from_int(FP32, 0xFFFFFFFF, True, RNE) == 0xBF800000 and fpops.from_int(FP32, 0, False, RNE) == 0
    threshold = fpops.round_rational(FP64, Fraction(2**128) - Fraction(2**103), RNE)  # FP32's overflow threshold
    assert [fpops.to_float(FP32, FP64, threshold, rm) for rm in fpops.MODES] == [
        nan32 - (1 << 22), FP32.inf - 1, FP32.inf - 1, FP32.inf, FP32.inf]
    assert fpops.to_float(FP64, FP32, FP32.inf | 1, RNE) == nan64


def test_compare_unit():
    nan, neg_zero = FP64.qnan, FP64.sign
    assert [opcodes.evaluate(fp(c), RNE, nan, nan, 0) for c in opcodes.COMPARES] == [0, 1, 0, 0, 0, 0]
    assert [opcodes.evaluate(fp(c), RNE, neg_zero, 0, 0) for c in opcodes.COMPARES] == [1, 0, 0, 1, 0, 1]
    assert opcodes.evaluate(fp("MIN"), RNE, 0, neg_zero, 0) == neg_zero
    assert opcodes.evaluate(fp("MAX"), RNE, nan, neg_zero, 0) == neg_zero
    assert opcodes.evaluate(fp("MAX"), RNE, FP64.inf | 1, nan, 0) == nan
    # FP32 reads bits 31-0: its values come back NaN-boxed, its compares zero-extended; NEG and ABS keep a NaN's
    # payload
    snan2 = 0xDEADBEEF << 32 | FP32.inf | 1
    assert opcodes.evaluate(fp("NEG", True), RNE, snan2, 0, 0) == opcodes.BOX | FP32.sign | FP32.inf | 1
    assert opcodes.evaluate(fp("ABS", True), RNE, snan2 | FP32.sign, 0, 0) == opcodes.BOX | FP32.inf | 1
    one = 0x3F800000
    assert opcodes.evaluate(fp("LT", True), RNE, FP32.qnan << 32 | one, one << 32 | one + 1, 0) == 1
    assert opcodes.evaluate(fp("LT", True), RNE, one << 32 | FP32.qnan, one + 1 << 32 | one, 0) == 0
    assert opcodes.evaluate(fp("MAX", True), RNE, FP32.qnan << 32 | FP32.sign, one << 32, 0) == opcodes.BOX


def test_one_lane():
    """INT32 operations read bits 31-0 and zero-extend; FP32 FMA-path operations read bits 31-0 and NaN-box."""
    a, b = 0x00000005_FFFFFFFF, 0x00000003_00000001
    assert opcodes.evaluate(intops.alu("ADD"), RNE, a, b, 0) == 0
    assert opcodes.evaluate(intops.alu("LT_S"), RNE, a, b, 0) == 1
    assert opcodes.evaluate(intops.alu("SUB"), RNE, a, b, 0) == 0xFFFFFFFE
    one, two = 0x3F800000, 0x40000000
    assert opcodes.evaluate(fp("ADD", True), RNE, two << 32 | one, two << 32 | one, two << 32 | one) == \
        opcodes.BOX | two
    assert opcodes.evaluate(fp("FMA", True), RNE, one << 32 | two, one << 32 | two, one << 32) == \
        opcodes.BOX | 0x40800000
    assert opcodes.evaluate(intops.mul(intops.LO), RNE, a, b, 0) == 0xFFFFFFFF
    assert opcodes.evaluate(31, RNE, a, b, 0) == 0 and opcodes.evaluate(0x47, RNE, a, b, 0) == 0


@pytest.mark.parametrize("fmt", (FP64, FP32), ids=lambda f: f.name)
def test_matches_c(fmt):
    """Every operation the C library has, in its four rounding modes, on specials and random encodings."""
    rng = random.Random(fmt.width)
    pool = specials(fmt)
    funcs = ("FMA", "ADD", "SUB", "MUL", "TO_S32", "TO_U32", "CVT_F", "CVT_S32", "CVT_U32",
             *opcodes.COMPARES, "MIN", "MAX")
    checked = dict.fromkeys(funcs, 0)
    for _ in range(800):
        a, b, c = (rng.choice(pool) if rng.randrange(4) == 0 else rng.getrandbits(64) for _ in range(3))
        for func in funcs:
            for rm in (RNE, RTZ, RDN, RUP):
                checked[func] += check(*row(fp(func, fmt is FP32), rm, a, b, c)) is not None
    # every case, except conversions to int32 of what C cannot round to an integer (an infinity, |x| >= 2^62)
    assert all(n == 800 * 4 for func, n in checked.items() if func not in ("TO_S32", "TO_U32")), checked
    assert min(checked["TO_S32"], checked["TO_U32"]) > 0.5 * 800 * 4, checked
