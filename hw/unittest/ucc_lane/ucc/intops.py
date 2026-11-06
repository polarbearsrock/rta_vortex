"""The UCC's INT32 mode: its operation codes and reference.

``evaluate(op, a, b, c)`` is the INT32 operation ``op`` (its opcode, ucc_pkg's
INT_* codes) of the low words of a, b and c, from the operations' definitions
alone. Codes 0-25 are the ALU's (``ALU`` in code order; 26-31 return 0). Codes
with bit 5 set multiply: bits 4-3 pick the low word, the high word or the
whole 64-bit product, bit 2 adds c (its low word, zero-extended, at the
result's bit 0), and bits 1 and 0 make b and a signed. A 32-bit result is
zero-extended to 64 bits.
``RISCV`` and ``PTX`` name the codes of the RV32IM/Zicond and PTX operations
they implement.
"""

ALU = (
    "ADD", "SUB", "AND", "OR", "XOR", "NOT", "SHL", "SHR_U", "SHR_S",
    "EQ", "NE", "LT_S", "LE_S", "GT_S", "GE_S", "LT_U", "LE_U", "GT_U", "GE_U",
    "MIN_S", "MAX_S", "MIN_U", "MAX_U", "ABS", "CZERO_EQZ", "CZERO_NEZ",
)
MUL, MAD, B_SIGNED, A_SIGNED = 0x20, 0x04, 0x02, 0x01
LO, HI, WIDE = 0, 1, 2
CODES = 64
M32, M64 = (1 << 32) - 1, (1 << 64) - 1


def alu(name):
    return ALU.index(name)


def mul(result, mad=False, a_signed=False, b_signed=False):
    return MUL | result << 3 | MAD * mad | B_SIGNED * b_signed | A_SIGNED * a_signed


RISCV = {
    "add": alu("ADD"), "sub": alu("SUB"), "and": alu("AND"), "or": alu("OR"), "xor": alu("XOR"),
    "sll": alu("SHL"), "srl": alu("SHR_U"), "sra": alu("SHR_S"), "slt": alu("LT_S"), "sltu": alu("LT_U"),
    "czero.eqz": alu("CZERO_EQZ"), "czero.nez": alu("CZERO_NEZ"),
    "mul": mul(LO), "mulh": mul(HI, a_signed=True, b_signed=True), "mulhsu": mul(HI, a_signed=True),
    "mulhu": mul(HI),
}
PTX = {
    "mul.lo": mul(LO), "mul.hi.s32": mul(HI, a_signed=True, b_signed=True), "mul.hi.u32": mul(HI),
    "mul.wide.s32": mul(WIDE, a_signed=True, b_signed=True), "mul.wide.u32": mul(WIDE),
    "mad.lo": mul(LO, mad=True), "mad.hi.s32": mul(HI, mad=True, a_signed=True, b_signed=True),
    "mad.hi.u32": mul(HI, mad=True), "abs.s32": alu("ABS"), "not.b32": alu("NOT"),
    "min.s32": alu("MIN_S"), "max.s32": alu("MAX_S"), "min.u32": alu("MIN_U"), "max.u32": alu("MAX_U"),
}


def name(op):
    if op & MUL:
        result = ("lo", "hi", "wide", "wide")[op >> 3 & 3]
        signs = ("u", "su", "us", "s")[op & 3]  # a then b: s(igned) or u(nsigned)
        return f"{'mad' if op & MAD else 'mul'}.{result}.{signs}"
    return ALU[op].lower().replace("_", ".") if op < len(ALU) else f"reserved{op}"


def signed(x):
    x &= M32
    return x - (1 << 32) if x >> 31 else x


def evaluate(op, a, b, c):
    a, b, c = a & M32, b & M32, c & M32
    if op & MUL:
        x = signed(a) if op & A_SIGNED else a
        y = signed(b) if op & B_SIGNED else b
        add = c if op & MAD else 0
        result = op >> 3 & 3
        if result == HI:
            return (x * y + (add << 32) >> 32) & M32
        product = (x * y + add) & M64
        return product if result >= WIDE else product & M32
    if op >= len(ALU):
        return 0
    sa, sb, shift = signed(a), signed(b), b & 31
    return {
        "ADD": a + b, "SUB": a - b, "AND": a & b, "OR": a | b, "XOR": a ^ b, "NOT": ~a,
        "SHL": a << shift, "SHR_U": a >> shift, "SHR_S": sa >> shift,
        "EQ": a == b, "NE": a != b,
        "LT_S": sa < sb, "LE_S": sa <= sb, "GT_S": sa > sb, "GE_S": sa >= sb,
        "LT_U": a < b, "LE_U": a <= b, "GT_U": a > b, "GE_U": a >= b,
        "MIN_S": a if sa < sb else b, "MAX_S": b if sa < sb else a,
        "MIN_U": a if a < b else b, "MAX_U": b if a < b else a,
        "ABS": abs(sa), "CZERO_EQZ": 0 if b == 0 else a, "CZERO_NEZ": a if b == 0 else 0,
    }[ALU[op]] & M32
