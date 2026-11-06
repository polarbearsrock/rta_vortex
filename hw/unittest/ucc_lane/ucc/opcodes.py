"""The UCC FU's global opcode (ucc_lane's op_i): its map, each opcode's unit and latency, the FU's issue rules, and
what the FU returns for any operation.

The map is ucc_pkg's. 0x00-0x3F are the INT32 operations (``intops``' codes). 0x40-0x7F are floating point: bit 5
picks FP32 (else FP64) and bits 4-0 the function (``FUNCS``). The SFU's functions are FP32 only, 0x78 plus Vortex's
encoding (``sfu``). DPA-16 takes the same function codes in the FP64 half, 0x58 plus its format (``dpa.FORMATS``).
Codes the map does not name return 0 one cycle after issue.

``evaluate(op, rm, a, b, c)`` is what ucc_lane returns for one operation, from the references alone: ``intops`` for
INT32, ``fpops`` for floating point in rounding mode rm (FPnew's encoding, which INT32 operations and the SFU's
functions ignore; the codes 5-7 FPnew does not name for the FMA path and the conversions round to nearest even),
``sfu`` for the SFU's functions and TransDot's model (``dpa``) for DPA-16. a and b are
``dpa.OPERAND`` bits; only DPA-16 reads their bits above 63. Every operation is one operation: an FP32 or INT32 one
reads bits 31-0 of its operands. FP32 results, DPA-16's included, are NaN-boxed; INT32 results, compares (FP32 and
FP64) and conversions to int32 are zero-extended.

``settle(ops)`` applies the FU's issue rules to a stream of operations, one per cycle (``fates``, each operation's,
also under ucc_fma's flush), and ``latency(op)`` is when each result comes.
"""

import bisect

from . import dpa, fpops, intops, sfu
from .models import FP32, FP64

FP, FP32_BIT, FUNC = 0x40, 0x20, 0x1F
FUNCS = dict(
    FMA=0x00, ADD=0x01, SUB=0x02, MUL=0x03,
    MIN=0x08, MAX=0x09, NEG=0x0A, ABS=0x0B, EQ=0x0C, NE=0x0D, LT=0x0E, LE=0x0F, GT=0x10, GE=0x11,
    CVT_F=0x12, CVT_S32=0x13, CVT_U32=0x14, TO_S32=0x15, TO_U32=0x16, SFU=0x18,
)
NAMES = {code: name for name, code in FUNCS.items()}
DPA_FUNC = 0x18  # DPA-16, FP64 half only: plus the format
COMPARES = ("EQ", "NE", "LT", "LE", "GT", "GE")
M32, M64 = (1 << 32) - 1, (1 << 64) - 1
BOX = M32 << 32  # the upper word of an FP32 result
# Cycles from issue to result, per unit (ucc_pkg's unit_e)
LATENCY = dict(alu=1, cmp=1, imul=2, cvt=2, fma=3, dpa=4, sfu=5, none=1)
MAX_LATENCY = max(LATENCY.values())
SFU_SLOT = 2  # an SFU function takes the input register this many cycles after its issue


def fp(name, fp32=False):
    """The opcode of FP function ``name`` (a FUNCS key) in FP32 or FP64."""
    return FP | FP32_BIT * fp32 | FUNCS[name]


def sfu_op(fn):
    """The opcode of SFU function fn (Vortex's encoding, sfu.RCP to sfu.TANH)."""
    return fp("SFU", True) + fn


def dpa_op(fmt):
    """The opcode of DPA-16 in format fmt (dpa.FORMATS' index)."""
    return FP | DPA_FUNC + fmt


def fmt(op):
    return FP32 if op & FP32_BIT else FP64


def unit(op):
    """ucc_pkg's unit_of: the unit that returns op's result."""
    func = op & FUNC
    if not op & FP:
        return "imul" if op & intops.MUL else "alu"
    if func <= FUNCS["MUL"]:
        return "fma"
    if FUNCS["MIN"] <= func <= FUNCS["GE"]:
        return "cmp"
    if FUNCS["CVT_F"] <= func <= FUNCS["TO_U32"]:
        return "cvt"
    if op & FP32_BIT and FUNCS["SFU"] <= func < FUNCS["SFU"] + len(sfu.NAMES):
        return "sfu"
    if not op & FP32_BIT and DPA_FUNC <= func < DPA_FUNC + len(dpa.FORMATS):
        return "dpa"
    return "none"


def latency(op):
    """Cycles from op's issue to its result."""
    return LATENCY[unit(op)]


def name(op):
    if not op & FP:
        return intops.name(op)
    u = unit(op)
    if u == "sfu":
        return f"sfu.{sfu.NAMES[(op & FUNC) - FUNCS['SFU']]}"
    if u == "dpa":
        return f"dpa16.{dpa.FORMATS[(op & FUNC) - DPA_FUNC].lower()}"
    if u == "none":
        return f"reserved{op:#04x}"
    return f"{NAMES[op & FUNC].lower()}.{fmt(op).name.lower()}"


def evaluate(op, rm, a, b, c):
    """What ucc_lane returns for opcode op in rounding mode rm, with operands a and b (dpa.OPERAND bits) and c (64
    bits)."""
    u = unit(op)
    if u == "dpa":
        return BOX | dpa.evaluate((op & FUNC) - DPA_FUNC, rm, a, b, c)
    a, b = a & M64, b & M64
    if u in ("alu", "imul"):
        return intops.evaluate(op, a, b, c)
    if u == "none":
        return 0
    if u == "sfu":
        return BOX | sfu.evaluate((op & FUNC) - FUNCS["SFU"], a & M32)
    if rm not in fpops.MODES:
        rm = fpops.RNE  # 5-7: FPnew names none of them for the FMA path and the conversions
    f, func = fmt(op), NAMES[op & FUNC]
    if u == "fma":
        def lane(x, y, z):
            if func == "FMA":
                return fpops.fma(f, x, y, z, rm)
            return {"ADD": fpops.add, "SUB": fpops.sub, "MUL": fpops.mul}[func](f, x, y, rm)

        if f is FP64:
            return lane(a, b, c)
        return BOX | lane(a & M32, b & M32, c & M32)
    if u == "cmp":
        result = compare_unit(f, func, a, b)
        return result if f is FP64 or func in COMPARES else BOX | result
    if func in ("TO_S32", "TO_U32"):
        return fpops.to_int(f, a & (1 << f.width) - 1, func == "TO_S32", rm)
    if func == "CVT_F":
        other = FP64 if f is FP32 else FP32
        result = fpops.to_float(f, other, a & (1 << other.width) - 1, rm)
    else:
        result = fpops.from_int(f, a & M32, func == "CVT_S32", rm)
    return (BOX if f is FP32 else 0) | result


def compare_unit(f, func, x, y):
    """The compare unit's result for one value of format f: a compare's 1 or 0, or MIN's, MAX's, NEG's or ABS's
    value."""
    x, y = x & (1 << f.width) - 1, y & (1 << f.width) - 1
    if func in COMPARES:
        return fpops.compare(f, x, y, func.lower())
    if func in ("MIN", "MAX"):
        return fpops.minmax(f, x, y, func == "MAX")
    # NEG and ABS change the sign bit alone, NaNs included
    return x ^ f.sign if func == "NEG" else x & ~f.sign


def fates(ops, flushes=()):
    """Each operation's fate in a stream, one per cycle, as the FU treats it (None for a cycle that issues none):
    - "lost": an operation other than an SFU function issued SFU_SLOT cycles after an SFU function (the SFU's FMA
      takes its place in the input register);
    - "flushed": an operation in flight in a cycle of ``flushes`` (ucc_fma's flush_i, which ucc_lane ties off):
      issued in or before it, its result due after it; an SFU function flushed before its slot leaves the slot free;
    - "hidden": a result due in the same cycle as a younger operation's;
    - "ok": the result the FU returns."""
    flushes = sorted(set(flushes))

    def flush_in(lo, hi):  # a flush in cycles lo to hi - 1
        k = bisect.bisect_left(flushes, lo)
        return k < len(flushes) and flushes[k] < hi

    units = [None if op[0] is None else unit(op[0]) for op in ops]
    fate = [None if u is None else "ok" for u in units]
    for i in range(SFU_SLOT, len(ops)):
        j = i - SFU_SLOT
        if units[i] not in (None, "sfu") and units[j] == "sfu" and not flush_in(j, i):
            fate[i] = "lost"
    for i, op in enumerate(ops):
        if fate[i] == "ok" and flush_in(i, i + latency(op[0])):
            fate[i] = "flushed"
    due = {}
    for i, op in enumerate(ops):
        if fate[i] == "ok":
            t = i + latency(op[0])
            if t in due:
                fate[due[t]] = "hidden"
            due[t] = i
    return fate


def settle(ops, flushes=()):
    """A stream of operations, one per cycle, as the FU returns them: each is (op, rm, a, b, c, d), op None for a
    cycle that issues none, and d becomes None for a result the FU does not return (``fates``: lost, hidden, or with
    ``flushes`` flushed). Returns the stream and how many results each rule removed."""
    fate = fates(ops, flushes)
    settled = [op if f in (None, "ok") else (*op[:5], None) for op, f in zip(ops, fate)]
    kinds = ("lost", "hidden") + (("flushed",) if flushes else ())
    return settled, {k: fate.count(k) for k in kinds}
