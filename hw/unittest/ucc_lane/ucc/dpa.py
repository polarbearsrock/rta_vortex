"""DPA-16's reference: TransDot's own model of its dpa16_core, ``nv_tc/dpa16/model/dpa16_ref.py`` at 599aaa5, vendored
unmodified (``hw/rtl/ucc/vendor/transdot``, with provenance), and loaded from there, plus the FU's two formats on its paths:
MXFP8 (``mxfp8``) and FP4 (MXFP4 with unit scales).

``evaluate(fmt, rm, a, b, c)`` is what the FU's DPA-16 returns (before NaN-boxing) for format ``fmt`` (``FORMATS``:
dpa16_pkg's encoding, then MXFP8 and FP4) with the FU's operands: a and b are OPERAND bits, {four 8-bit block scales,
256-bit vector}, which ucc_lane takes as the vector on a_i and b_i and the scales on sa_i and sb_i; c's bits 31-0 are
the FP32 addend; rm's bits 0 and 1 make a's and b's FP8 and MXFP8 elements E5M2 (else E4M3).
"""

import importlib.util

from .paths import TRANSDOT

MODEL = TRANSDOT / "nv_tc" / "dpa16" / "model" / "dpa16_ref.py"
_spec = importlib.util.spec_from_file_location("transdot_dpa16_ref", MODEL)
ref = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ref)

# dpa16_pkg::fmt_e (ref.FP16 .. ref.MXFP4), then the FU's: MXFP8, FP8 with one E8M0 scale per side, and FP4, E2M1
# without scales
FORMATS = ("FP16", "BF16", "TF32", "FP8", "NVFP4", "MXFP4", "MXFP8", "FP4")
TRANSDOT = 6
MXFP8, FP4 = TRANSDOT, TRANSDOT + 1
assert tuple(ref.FMT_NAMES[k].upper() for k in range(TRANSDOT)) == FORMATS[:TRANSDOT]
VECTOR = 256
OPERAND = VECTOR + 32
M32 = (1 << 32) - 1
QNAN = ref.QNAN
UNIT_SCALES = 0x7F7F7F7F  # E8M0 2^0 in all four blocks: FP4 is MXFP4 with these


def split(x):
    """An FU operand's 256-bit vector and its block scales."""
    return x & (1 << VECTOR) - 1, x >> VECTOR & M32


def mxfp8(a, b, sa, sb, c, a_e5m2=False, b_e5m2=False):
    """MXFP8: ``ref.dpa16``'s FP8 mode with one E8M0 scale per side, byte 0 of sa and sb (an OCP MX block is 32
    elements). The scales' exponents move every product's lsb exponent and anchor alike; a scale of 0xFF is NaN.
    Everything else is TransDot's FP8 path, term for term."""
    xa, xb = sa & 0xFF, sb & 0xFF
    off = xa + xb - 254
    special = xa == 0xFF or xb == 0xFF
    terms = []
    for (s1, m1, e1, w1, sp1), (s2, m2, e2, w2, sp2) in zip(ref.elements(a, ref.FP8, a_e5m2),
                                                            ref.elements(b, ref.FP8, b_e5m2)):
        special |= sp1 or sp2
        if m1 and m2:
            terms.append((s1 ^ s2, m1 * m2, e1 + e2 + off, e1 + e2 + off + (w1 - 1) + (w2 - 1)))
    cs, cm, ce, csp = ref.dec(c, 8, 23, 127)
    special |= csp
    if cm:
        terms.append((cs, cm, ce, ce + 23))
    return ref.window_sum(terms, special)


def evaluate(fmt, rm, a, b, c):
    (va, sa), (vb, sb) = split(a), split(b)
    e5a, e5b = bool(rm & 1), bool(rm & 2)
    if fmt == MXFP8:
        return mxfp8(va, vb, sa, sb, c & M32, e5a, e5b)
    if fmt == FP4:
        return ref.dpa16(ref.MXFP4, va, vb, UNIT_SCALES, UNIT_SCALES, c & M32)
    return ref.dpa16(fmt, va, vb, sa, sb, c & M32, a_e5m2=e5a, b_e5m2=e5b)
