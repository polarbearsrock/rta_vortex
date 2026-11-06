"""DPA-16's reference (TransDot's model, vendored) as the FU uses it: its formats are dpa16_pkg's and then the FU's
MXFP8 and FP4, every lane is where the format puts it, the bits a format ignores change nothing, the FU's formats
reduce to TransDot's where they should, and the stream's results agree with the exact dot product."""

import random
import re

from .. import dpa, dpavectors, opcodes
from ..dpavectors import EIGHT, FP4, FP8, LANES, MXFP4, MXFP8, NVFP4, TF32
from ..paths import RTL, TRANSDOT


def test_formats_match_dpa16_pkg():
    """dpa16_pkg's formats come first, in its encoding; the FU's MXFP8 and FP4 take the two codes after them."""
    text = (TRANSDOT / "nv_tc/dpa16/rtl/dpa16_pkg.sv").read_text()
    fmts = re.findall(r"FMT_(\w+)\s*= 3'd(\d)", text)
    assert [(name, int(code)) for name, code in fmts] == [(name, k) for k, name in enumerate(dpa.FORMATS[:dpa.TRANSDOT])]
    assert dpa.FORMATS[dpa.TRANSDOT:] == ("MXFP8", "FP4") and (dpa.MXFP8, dpa.FP4) == (6, 7) == (MXFP8, FP4)
    fma = (RTL / "ucc_fma.sv").read_text()
    assert re.search(r"assign dpa_mx8_d\s+= ucc_op_i\[2:0\] == 3'd6;", fma)
    assert re.search(r"assign dpa_fp4_d\s+= ucc_op_i\[2:0\] == 3'd7;", fma)
    assert re.search(r"assign inp_pipe_dpa_fmt_q\[0\]\s+= dpa_mx8_d \? 3'd3 : \(dpa_fp4_d \? 3'd5 : ucc_op_i\[2:0\]\);", fma)


def test_lane_counts():
    """All products 1.0: the result is the number of lanes, and c adds to it."""
    rng = random.Random(1)
    ops = dpavectors.directed(rng)
    totals = {}
    for op, rm, a, b, c, d in ops:
        fmt = (op & opcodes.FUNC) - opcodes.DPA_FUNC
        if c & 0xFFFFFFFF == 0 and fmt not in totals:
            totals[fmt] = dpavectors.value32(d & 0xFFFFFFFF)
    assert totals == {fmt: n for fmt, n in LANES.items()}


def test_ignored_bits():
    """TF32's low 13 bits, the block scales outside NVFP4 and MXFP4 (all of them in FP4, bytes 1-3 in MXFP8), the
    FP8 subtype bits outside FP8 and MXFP8, rm's bit 2 and c's upper word change no result."""
    rng = random.Random(2)
    for fmt in range(len(dpa.FORMATS)):
        for _ in range(200):
            op, rm, a, b, c, d = dpavectors.random_row(rng, fmt, "mixed")
            rm2 = rm ^ 4 if fmt in EIGHT else rng.getrandbits(3)
            c2 = rng.getrandbits(32) << 32 | c & 0xFFFFFFFF
            a2, b2 = a, b
            if fmt == MXFP8:
                a2 ^= rng.getrandbits(24) << dpa.VECTOR + 8
                b2 ^= rng.getrandbits(24) << dpa.VECTOR + 8
            elif fmt not in (NVFP4, MXFP4):
                a2 ^= rng.getrandbits(32) << dpa.VECTOR
                b2 ^= rng.getrandbits(32) << dpa.VECTOR
            if fmt == TF32:
                junk = sum(rng.getrandbits(13) << 32 * i for i in range(8))
                a2 ^= junk
            assert opcodes.evaluate(op, rm2, a2, b2, c2) == d


def test_fu_formats_reduce_to_transdots():
    """MXFP8 with both scales 2^0 is TransDot's FP8, with any other pair of scales its FP8 of the same elements with
    the scales' product folded into c's exponent where that is exact; FP4 is TransDot's MXFP4 with every scale 2^0."""
    rng = random.Random(3)
    for _ in range(2000):
        va, vb, c = rng.getrandbits(256), rng.getrandbits(256), rng.getrandbits(32)
        e5a, e5b = bool(rng.getrandbits(1)), bool(rng.getrandbits(1))
        junk = rng.getrandbits(24) << 8
        assert (dpa.mxfp8(va, vb, junk | 127, junk | 127, c, e5a, e5b)
                == dpa.ref.dpa16(dpa.ref.FP8, va, vb, rng.getrandbits(32), rng.getrandbits(32), c, e5a, e5b))
        rm = rng.getrandbits(3)
        assert (dpa.evaluate(FP4, rm, rng.getrandbits(32) << 256 | va, rng.getrandbits(32) << 256 | vb, c)
                == dpa.ref.dpa16(dpa.ref.MXFP4, va, vb, dpa.UNIT_SCALES, dpa.UNIT_SCALES, c))
    # a scale moves the whole sum: with c = 0, scales 2^k and 2^-k cancel, and 2^k alone scales an exact result by 2^k
    for _ in range(2000):
        va, vb = rng.getrandbits(256), rng.getrandbits(256)
        e5a, e5b = bool(rng.getrandbits(1)), bool(rng.getrandbits(1))
        k = rng.randint(-20, 20)
        base = dpa.ref.dpa16(dpa.ref.FP8, va, vb, 0, 0, 0, e5a, e5b)
        assert dpa.mxfp8(va, vb, 127 + k, 127 - k, 0, e5a, e5b) == base
        scaled = dpa.mxfp8(va, vb, 127 + k, 127, 0, e5a, e5b)
        e = base >> 23 & 0xFF
        if base & 0x7FFFFFFF not in (0, 0x7FC00000) and 1 <= e + k <= 254 and 1 <= e <= 254:
            assert scaled == base + (k << 23)
    assert dpa.mxfp8(0, 0, 0xFF, 127, 0) == dpa.QNAN and dpa.mxfp8(0, 0, 127, 0xFF, 0) == dpa.QNAN


def test_mxfp8_directed_values():
    """The directed MXFP8 operations (dpavectors.mx_directed) give their hand-computed results: NaN for a NaN scale on
    either side or both, with terms or without; no NaN for 0xFF in the bytes MXFP8 does not read; 2^(k - 122) for 32
    products of 1.0 under scales 2^(k - 127) and 2^0, infinity from k = 250; the ends of soff, with c alone, overflow
    by the sum and its cancellation; and the subnormal limit with c = 0: 2^-126, 2^-127, 2^-128, then 0."""
    qnan, inf = dpa.QNAN, 0x7F800000
    want = [qnan] * 7 + [0, 0x42000000]
    for k in dpavectors.MX_SWEEP:
        want += [(k + 5) << 23 if k + 5 <= 254 else inf] * 2
    want += [inf, 0x7F7FFFFF, 0xFF7FFFFF, 0, 0x00800000, inf, 0]
    want += [0x00800000, 0x00400000, 0x00200000, 0, 0]
    assert [d & 0xFFFFFFFF for *_, d in dpavectors.mx_directed()] == want


def test_mx_fp4_coverage():
    """The stream holds what the MXFP8 and FP4 bugs need: NaN scales (byte 0) on a, on b, on both, and with no
    nonzero term; 0xFF only in the bytes MXFP8 does not read; soff at both ends; infinite, subnormal and flushed
    (emax + 133 < 0) results; and FP4 operations whose result would change if their scale words were read."""
    ops, _ = dpavectors.dpa_ops(random.Random(dpavectors.DPA_SEED))
    n = dict.fromkeys(("nan_a", "nan_b", "nan_both", "nan_no_term", "unread_ff", "soff_hi", "soff_lo", "inf", "sub",
                       "flushed", "fp4_scales_matter", "fp4_ff"), 0)
    for op, rm, a, b, c, d in ops:
        fmt, r = (op & opcodes.FUNC) - opcodes.DPA_FUNC, d & 0xFFFFFFFF
        (va, sa), (vb, sb) = dpa.split(a), dpa.split(b)
        if fmt == MXFP8:
            xa, xb = sa & 0xFF, sb & 0xFF
            terms, special = dpavectors.terms(MXFP8, rm, a, b, c)
            n["nan_a"] += xa == 0xFF
            n["nan_b"] += xb == 0xFF
            n["nan_both"] += xa == xb == 0xFF
            n["nan_no_term"] += (xa == 0xFF or xb == 0xFF) and not terms
            n["unread_ff"] += r != dpa.QNAN and any(s >> 8 * k & 0xFF == 0xFF for s in (sa, sb) for k in (1, 2, 3))
            if 0xFF not in (xa, xb):
                n["soff_hi"] += xa + xb - 254 >= 240
                n["soff_lo"] += xa + xb - 254 <= -240
            n["inf"] += r & 0x7FFFFFFF == 0x7F800000
            n["sub"] += r & 0x7F800000 == 0 and r & 0x7FFFFF != 0
            exact = sum(v for v, _ in terms)
            n["flushed"] += not special and r & 0x7FFFFFFF == 0 and 0 < abs(exact) < 2 ** -126
        elif fmt == FP4:
            n["fp4_scales_matter"] += dpa.ref.dpa16(dpa.ref.MXFP4, va, vb, sa, sb, c & dpa.M32) != r
            n["fp4_ff"] += r != dpa.QNAN and any(s >> 8 * k & 0xFF == 0xFF for s in (sa, sb) for k in range(4))
    floor = dict(nan_a=10, nan_b=10, nan_both=2, nan_no_term=2, unread_ff=20, soff_hi=20, soff_lo=20, inf=50, sub=20,
                 flushed=50, fp4_scales_matter=1000, fp4_ff=20)
    assert all(n[k] >= v for k, v in floor.items()), n


def test_stream_matches_exact_sums():
    """Every result of the regression's DPA-16 stream is within the window's truncation of the exact dot product
    (exactly its FP32 truncation where no term loses a bit), or the canonical NaN where an input is special, in every
    format."""
    ops, kinds = dpavectors.dpa_ops(random.Random(dpavectors.DPA_SEED))
    how = {}
    for op in ops:
        k = dpavectors.check(*op)
        fmt = (op[0] & opcodes.FUNC) - opcodes.DPA_FUNC
        how.setdefault(fmt, {}).setdefault(k, 0)
        how[fmt][k] += 1
    assert set(how) == set(range(len(dpa.FORMATS)))
    for fmt, h in how.items():
        assert set(h) == {"nan", "zero", "exact", "bound"}, (fmt, h)
        assert h["exact"] > 250 and h["nan"] > 100, (fmt, h)


def test_core_fork_moves_the_tiles_and_adds_mxfp8():
    """rtl/ucc_dpa16_core.sv is TransDot's dpa16_core with its header, its name, and its tiles moved out (ports for
    their operands, modes and products) changed, the MXFP8 mode (mx8_i) and the stage registers' enables (en_i)
    added, and nothing else."""
    upstream = (TRANSDOT / "nv_tc/dpa16/rtl/dpa16_core.sv").read_text()
    fork = (RTL / "ucc_dpa16_core.sv").read_text()
    fork = fork[fork.index("// DPA-16 PE datapath"):]
    fork = fork.replace("module ucc_dpa16_core import", "module dpa16_core import")
    # the stage registers' enables, then the MXFP8 mode, undone line by line: (the fork's text, upstream's, how many
    # times)
    en = fork[fork.index("  input  logic [2:0]    en_i,"):fork.index("\n", fork.index("en_i,")) + 1]
    mx8 = fork[fork.index("\n  // MXFP8: the two E8M0"):fork.index("\n", fork.index("  assign mx8_sp =")) + 1]
    for new, old, n in (
        (en, "", 1),
        ("      end else if (en_i[0]) begin\n", "      end else begin\n", 1),
        ("        else if (en_i[0]) for (int l", "        else         for (int l", 1),
        ("      end else if (en_i[1]) begin\n", "      end else begin\n", 1),
        ("      else if (en_i[2]) r3_d <= dn;", "      else         r3_d <= dn;", 1),
        ("  input  logic          mx8_i,\n", "", 1),
        (mx8, "", 1),
        ("    tanc[NSLOT] = canc - soff;", "    tanc[NSLOT] = canc;", 1),
        ("  logic signed [AW-1:0]   r1_emax, r1_soff;", "  logic signed [AW-1:0]   r1_emax;", 1),
        ("        r1_soff  <= '0;\n", "", 1),
        ("        r1_soff  <= soff;\n", "", 1),
        ("      r1_soff  = soff;\n", "", 1),
        ("(sp_in || csp || mx8_sp)", "(sp_in || csp)", 2),
        ("r1_emax + r1_soff;", "r1_emax;", 2),
    ):
        assert fork.count(new) == n, new
        fork = fork.replace(new, old)
    assert "mx8" not in fork and "soff" not in fork and "en_i" not in fork
    ports = fork[fork.index("  output logic [((M > 0) ? M : 1)-1:0][31:0] vd_o,"):fork.index(");", fork.index("vd_o,"))]
    fork = fork.replace(ports, "  output logic [((M > 0) ? M : 1)-1:0][31:0] vd_o\n")
    moved = fork[fork.index("  assign ta_o     = ta;"):fork.index("  assign dprod    = dprod_i;") + 28]
    tiles = (
        "  for (genvar t = 0; t < NTILE; t++) begin : g_tile\n"
        "    dpa16_mul12 u_mul (\n"
        "      .a_i (ta[t]), .b_i (tb[t]),\n"
        "      .m_full_i (is16 || istf || vm), .m_fp8_i (is8), .m_fp4_i (is4),\n"
        "      .prod_o (tprod[t]), .dprod_o (dprod[t])\n"
        "    );\n"
        "  end"
    )
    assert fork.replace(moved, tiles) == upstream
