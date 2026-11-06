"""The INT32 mode's codes and reference against the operations' own definitions."""

import random
import re

from .. import intops
from ..vectors import mul53, tilemul
from ..paths import RTL

M32 = intops.M32


def test_codes_match_ucc_pkg():
    """intops' ALU codes are ucc_pkg's INT_* codes, and the multiply fields its INT_LO/HI/WIDE."""
    text = (RTL / "ucc_pkg.sv").read_text()
    codes = {name: int(value) for name, value in re.findall(r"localparam logic \[4:0\] INT_(\w+)\s*= 5'd(\d+);", text)}
    assert codes == {name: k for k, name in enumerate(intops.ALU)}
    results = dict(re.findall(r"localparam logic \[1:0\] INT_(LO|HI|WIDE)\s*= 2'd(\d);", text))
    assert {k: int(v) for k, v in results.items()} == {"LO": intops.LO, "HI": intops.HI, "WIDE": intops.WIDE}


def rv32(name, rs1, rs2):
    """RV32IM and Zicond, written from the ISA manual's definitions."""
    s1 = rs1 - (1 << 32) if rs1 >> 31 else rs1
    s2 = rs2 - (1 << 32) if rs2 >> 31 else rs2
    return {
        "add": rs1 + rs2, "sub": rs1 - rs2, "and": rs1 & rs2, "or": rs1 | rs2, "xor": rs1 ^ rs2,
        "sll": rs1 << (rs2 % 32), "srl": rs1 >> (rs2 % 32), "sra": s1 >> (rs2 % 32),
        "slt": int(s1 < s2), "sltu": int(rs1 < rs2),
        "czero.eqz": 0 if rs2 == 0 else rs1, "czero.nez": rs1 if rs2 == 0 else 0,
        "mul": s1 * s2, "mulh": s1 * s2 >> 32, "mulhsu": s1 * rs2 >> 32, "mulhu": rs1 * rs2 >> 32,
    }[name] & M32


def test_riscv_operations():
    rng = random.Random(1)
    edge = [0, 1, 31, 32, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF]
    pairs = [(a, b) for a in edge for b in edge] + [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(3000)]
    for name, op in intops.RISCV.items():
        for a, b in pairs:
            assert intops.evaluate(op, a, b, rng.getrandbits(32)) == rv32(name, a, b), (name, a, b)


def test_ptx_multiplies():
    """mul.wide, mad.lo and mad.hi as PTX defines them: mad.hi adds c to the product's high word."""
    rng = random.Random(2)
    for _ in range(3000):
        a, b, c = (rng.getrandbits(32) for _ in range(3))
        sa, sb, sc = (intops.signed(x) for x in (a, b, c))
        assert intops.evaluate(intops.PTX["mul.wide.s32"], a, b, c) == (sa * sb) & intops.M64
        assert intops.evaluate(intops.PTX["mul.wide.u32"], a, b, c) == a * b
        assert intops.evaluate(intops.PTX["mad.lo"], a, b, c) == (a * b + c) & M32
        assert intops.evaluate(intops.PTX["mad.hi.s32"], a, b, c) == ((sa * sb >> 32) + sc) & M32
        assert intops.evaluate(intops.PTX["mad.hi.u32"], a, b, c) == ((a * b >> 32) + c) & M32


def test_reserved_codes_return_zero():
    for op in range(len(intops.ALU), intops.MUL):
        assert intops.evaluate(op, 0xFFFFFFFF, 0x12345678, 1) == 0


def test_multiplier_gives_every_product():
    """With the integers at bits 52-21 the tiled product holds a * b at bits 105-42 for every signedness, as the
    replaced Booth multiplier did, and the result fields of every multiply code are bits of that product plus c."""
    rng = random.Random(3)
    for _ in range(2000):
        a, b, c = (rng.getrandbits(32) for _ in range(3))
        for op in range(intops.MUL, intops.CODES):
            a_signed, b_signed = bool(op & intops.A_SIGNED), bool(op & intops.B_SIGNED)
            p = tilemul(a << 21, b << 21, a_signed=a_signed, b_signed=b_signed)
            assert p == mul53(a << 21, a << 21, b << 21, b_signed, a_signed)
            p >>= 42
            # the adder's view: c at the result's bit 0, or bit 32 for the high word, read mod 2^64
            result = op >> 3 & 3
            add = (c if op & intops.MAD else 0) << (32 if result == intops.HI else 0)
            s = (p + add) & intops.M64
            got = s >> 32 if result == intops.HI else (s if result >= intops.WIDE else s & M32)
            assert got == intops.evaluate(op, a, b, c), (intops.name(op), a, b, c)
