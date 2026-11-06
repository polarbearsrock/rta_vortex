"""Simulate the UCC's units in Verilator and check every result against its
reference. Each device under test is an executable the Makefile builds from
``main.cpp``; this module writes each case's stimulus and expected results to a
case file, runs the cases in parallel and checks every compare. The cases:

- ``ucc_mul_tiles``, the FU's 53x53 product on DPA-16's tiles (``ucc_tiles``
  and ``ucc_tilemul``): FP64 and FP32 products, the SFU's and INT32 products
  in their modes, and arbitrary operands in each mode, against
  its definition (``vectors.tilemul``), which is also checked against the
  products they stand for and the replaced Booth multiplier's results;
- ``fp64_fma_lane``, TransDot's unchanged lane (FPnew ``fpnew_fma``, three
  distributed pipeline registers), and ``fpnew_fp32_lane``, an unchanged
  ``fpnew_fma`` in FP32 with the same pipeline: the baselines, on the FP64
  and the FP32 FMAs;
- the UCC FU, ``ucc_lane``, on streams of operations (``opcodes``):

  - ``ucc_lane_fp64`` and ``ucc_lane_fp32``, the baselines' vectors as FP64
    and FP32 FMAs in RNE, and ``ucc_lane_mixed``, the two at random;
  - ``ucc_lane_sfu``, the SFU's functions, and ``ucc_lane_mixed_sfu``, FMAs
    and SFU functions at random;
  - ``ucc_lane_int``, every INT32 code on directed and random operands, and
    ``ucc_lane_mixed_int``, FMAs, SFU functions and INT32 operations at
    random;
  - ``ucc_lane_fma_rm_fp64`` and ``ucc_lane_fma_rm_fp32``, the FMA vectors
    in RTZ, RDN, RUP and RMM;
  - ``ucc_lane_add_sub_mul``, ADD and SUB in every rounding mode, and MUL;
  - ``ucc_lane_fp_cmp``, MIN, MAX, NEG, ABS and the compares;
  - ``ucc_lane_fp_cvt``, the conversions;
  - ``ucc_lane_dpa16``, DPA-16 in every format, back to back, the format
    changing from one operation to the next, and ``ucc_lane_mixed_dpa16``,
    DPA-16 among the FMA path's, the SFU's and the bypassed operations, so
    that its result meets every other unit's in the same cycle;
  - ``ucc_lane_mixed_fu``, every opcode at random, reserved ones and idle
    cycles included;
  - ``ucc_lane_rm_reserved``, FMA-path operations and conversions in the
    rounding modes FPnew does not name (5-7), which round to nearest even;

- ``ucc_fma`` itself (``bench/ucc_fma_bench.sv``), with the ports ucc_lane
  leaves unconnected, checked every cycle against the issue rules
  (``opcodes.fates``): whether a result comes (out_valid_o) and the tag, aux
  and mask of the operation it belongs to, in_ready_o, busy_o, and the two
  breaches UCC_CHECK_ISSUE reports. ``ucc_fma_mixed_fu`` runs
  ``ucc_lane_mixed_fu``'s stream, ``ucc_fma_flush`` the same with flush_i
  set in random cycles, and ``ucc_fma_status`` directed operations whose
  status flags are known, each alone;
- on ``ucc_lane`` built with UCC_CHECK_ISSUE defined, two streams that keep
  the issue rules (``ucc_lane_sfu`` and ``ucc_lane_dpa16`` again), which
  must run without an error, and one that breaks them
  (``ucc_lane_mixed_sfu_breach``), which must stop at its first breach.

The FU takes one operation per cycle and each result is compared
``opcodes.latency(op)`` cycles after issue. In the streams that mix
operations the FU's issue rules (``opcodes.settle``) remove some results: an
operation issued two cycles after an SFU function is lost, and a result due
in the same cycle as a younger operation's is hidden. The streams issue those operations
anyway and compare no result for them. The FP64 vectors are exactly those of
the baseline synthesis run's validation (same seed and generator; their
SHA-256 is checked). Every expected result comes from the references alone
(``opcodes.evaluate``) and is cross-checked independently: the FMA vectors
against libm's ``fma`` and ``fmaf``, the other floating-point operations
against the C library in each rounding mode it has, and against Python's
comparisons (``fuvectors.check``). DPA-16's reference is TransDot's own model,
``dpa16_ref.py``, unmodified, with the FU's MXFP8 and FP4 on its FP8 and MXFP4
paths (``dpa``); each result is also checked against the exact dot product,
which it must match to within its window's truncation (``dpavectors.check``).
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import random
import re
import struct
import subprocess
import time
from typing import Optional

from . import fpops, intops, opcodes
from .dpa import VECTOR as DPA_VECTOR
from .opcodes import MAX_LATENCY, SFU_SLOT, evaluate, fates, fp, latency, unit
from .paths import CVFPU, TRANSDOT
from .vectors import LATENCY, MIXED, MUL_SEED, RESET_CYCLES, lane_vectors, mul_vectors

TRANSDOT_COMMIT = "599aaa5a50f97244a40e63ca6d7bd81db1deb383"
CVFPU_COMMIT = "58ca3c376beb914b2b80b811d4b270c063d4e6f7"
BENCH_SEED = 0x55434336_464D4142  # ucc_fma_bench's tags, aux, masks and flush cycles
FLUSH_EVERY = 40  # ucc_fma_flush sets flush_i in one cycle in this many, at random
ISSUE_CHECKED = ("sfu", "dpa16")  # streams that keep the issue rules, run again with UCC_CHECK_ISSUE
FP64_VECTORS = 121385  # the FP64 baseline synthesis run's validation vectors
BREACHING = "mixed_sfu"  # a stream that breaks the issue rules: ucc_lane_issue_checked must stop on it
LANE_INPUTS = (("rst_ni", 1), ("a_i", DPA_VECTOR), ("b_i", DPA_VECTOR), ("sa_i", 32), ("sb_i", 32), ("c_i", 64),
               ("valid_i", 1), ("op_i", 7), ("rm_i", 3))
BASELINE_INPUTS = (("rst_ni", 1), ("a_i", 64), ("b_i", 64), ("c_i", 64))
BENCH_PORTS = (("d_o", 64), ("status_o", 5), ("tag_o", 16), ("aux_o", 16), ("mask_o", 1), ("valid_o", 1),
               ("ready_o", 1), ("busy_o", 1), ("lost_o", 1), ("hidden_o", 1))
BENCH_OUTPUTS = tuple(name for name, _ in BENCH_PORTS)
# Each module's inputs (its clock aside) and outputs with their widths, in the testbench's order (main.cpp's
# UCC_PORTS, which checks every case file's names against its own)
PORTS = {
    "ucc_lane": (LANE_INPUTS, (("d_o", 64),)),
    "ucc_fma_bench": (LANE_INPUTS + (("flush_i", 1), ("tag_i", 16), ("aux_i", 16), ("mask_i", 1)), BENCH_PORTS),
    "ucc_mul_tiles": ((("a_i", 53), ("b_i", 53), ("sfu_i", 1), ("a_signed_i", 1), ("b_signed_i", 1)), (("p_o", 106),)),
    "fp64_fma_lane": (BASELINE_INPUTS, (("d_o", 64),)),
    "fpnew_fp32_lane": (BASELINE_INPUTS, (("d_o", 64),)),
}


def names(ports):
    return [name for name, _ in ports]


def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def check_sources():
    """Every vendored file is the upstream file (git blob and SHA-256)."""
    provenance = json.loads((TRANSDOT / "PROVENANCE.json").read_text())
    assert provenance["commit"] == TRANSDOT_COMMIT
    cvfpu = json.loads((CVFPU / "PROVENANCE.json").read_text())
    assert cvfpu["commit"] == CVFPU_COMMIT
    for base, records in (
        (TRANSDOT, provenance["files"]),
        (TRANSDOT / "common_cells", provenance["common_cells"]["files"]),
        (CVFPU, cvfpu["files"]),
    ):
        for name, record in records.items():
            data = (base / name).read_bytes()
            assert hashlib.sha256(data).hexdigest() == record["sha256"], name
            assert git_blob(data) == record["git_blob"], name
    return provenance


@dataclass
class Case:
    """A device under test on a stimulus: per cycle each input's value, a compare mask (bit k: the module's k-th
    output) and each output's expected value. ``device`` is the executable that simulates it (the module's own, or
    another build of the module). A case that ``stops`` must end at a simulation error instead (UCC_CHECK_ISSUE's)."""

    name: str
    module: str
    inputs: dict
    masks: list
    expected: dict
    device: str = ""
    stops: bool = False

    def __post_init__(self):
        self.device = self.device or self.module
        ins, outs = PORTS[self.module]
        assert set(self.inputs) == set(names(ins)) and set(self.expected) <= set(names(outs)), self.name
        assert all(len(v) == len(self.masks) for v in (*self.inputs.values(), *self.expected.values())), self.name
        assert min(self.masks) >= 0 and max(self.masks) < 1 << len(outs), self.name
        # every value, compared or not, fits its port, as the simulator reads it
        widths = dict(ins + outs)
        for port, values in (*self.inputs.items(), *self.expected.items()):
            assert min(values) >= 0 and max(values) < 1 << widths[port], (self.name, port)

    def write(self, path):
        """The case file main.cpp reads: its name and module, its ports, then one line per cycle (hex)."""
        ins, outs = (names(p) for p in PORTS[self.module])
        zeros = [0] * len(self.masks)
        columns = [self.inputs[p] for p in ins] + [self.masks] + [self.expected.get(p, zeros) for p in outs]
        with open(path, "w") as f:
            f.write(f"ucc_case {self.name} {self.module}\n")
            f.write(f"ports {' '.join(ins)} | {' '.join(outs)}\n")
            f.writelines(" ".join(format(v, "x") for v in row) + "\n" for row in zip(*columns))

    def describe(self, cycle, port, dut, ref):
        """A mismatch, with the inputs of its cycle and of the cycles that can have issued its operation."""
        ins = names(PORTS[self.module][0])
        lines = [f"{self.name}: cycle {cycle}, {port} is {dut}, expected {ref}"]
        for t in range(max(0, cycle - MAX_LATENCY), cycle + 1):
            values = ", ".join(f"{p}={self.inputs[p][t]:x}" for p in ins if self.inputs[p][t])
            lines.append(f"  cycle {t}: {values or 'every input 0'}")
        return "\n".join(lines)


@dataclass
class Result:
    name: str
    cycles: int
    compares: int
    mismatch: Optional[str]
    seconds: float
    stopped: Optional[int] = None  # the cycle a case that stops stopped in


DONE = re.compile(r"^UCC_DONE case=(\S+) cycles=(\d+) compares=(\d+) bad=(-?\d+)$", re.M)
MISMATCH = re.compile(r"^UCC_MISMATCH case=\S+ cycle=(\d+) port=(\S+) dut=(\S+) ref=(\S+)$", re.M)
BREACH = re.compile(r"^\[(\d+)\] %Error: .*ucc_fma: ", re.M)  # UCC_CHECK_ISSUE's error, at its time (10 per cycle)


def simulate(cases, bin_dir, workdir, jobs):
    """Writes every case's file, runs each on its device's executable (``jobs`` at a time, the longest first) and
    returns the results in the cases' order, and the seconds spent writing and running. A device that stops (a
    simulation error, such as UCC_CHECK_ISSUE's) or fails to read its case raises, unless the case ``stops``: then
    it must stop at UCC_CHECK_ISSUE's error and print no result."""
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    for case in cases:
        case.write(workdir / f"{case.name}.case")
    written = time.monotonic()

    def run(case):
        began = time.monotonic()
        device = Path(bin_dir) / case.device
        proc = subprocess.run([str(device), str(workdir / f"{case.name}.case")], capture_output=True, text=True)
        (workdir / f"{case.name}.log").write_text(proc.stdout + proc.stderr)
        done = DONE.search(proc.stdout)
        mismatch = MISMATCH.search(proc.stdout)
        if case.stops:
            breach = BREACH.search(proc.stdout + proc.stderr)
            if proc.returncode == 0 or done is not None or breach is None:
                raise RuntimeError(f"{case.name}: {device.name} should stop at a breach of the issue rules, but exited "
                                   f"with {proc.returncode}:\n{(proc.stdout + proc.stderr)[-3000:]}")
            return Result(case.name, 0, 0, None, time.monotonic() - began, int(breach[1]) // 10)
        if done is None or done[1] != case.name or proc.returncode != int(mismatch is not None):
            raise RuntimeError(f"{case.name}: {device.name} exited with {proc.returncode}:\n"
                               f"{(proc.stdout + proc.stderr)[-3000:]}")
        described = case.describe(int(mismatch[1]), *mismatch.groups()[1:]) if mismatch else None
        return Result(case.name, int(done[2]), int(done[3]), described, time.monotonic() - began)

    longest = sorted(cases, key=lambda c: -len(c.masks))
    with ThreadPoolExecutor(jobs) as pool:
        results = {r.name: r for r in pool.map(run, longest)}
    return [results[c.name] for c in cases], dict(stimulus=written - start, run=time.monotonic() - written)


def mul_case(rows):
    """ucc_mul_tiles, combinational: one product per cycle, compared in its cycle."""
    names = ("a_i", "b_i", "sfu_i", "a_signed_i", "b_signed_i")
    inputs = {name: [int(row[k + 1]) for row in rows] for k, name in enumerate(names)}
    return Case("ucc_mul_tiles", "ucc_mul_tiles", inputs, [1] * len(rows), {"p_o": [row[6] for row in rows]})


def lane_case(name, words):
    """A baseline lane: reset, one FMA (a, b, c, d) per cycle, then a drain;
    result i is compared LATENCY cycles after its operands."""
    n = len(words)
    idle = [0] * RESET_CYCLES
    drain = [0] * LATENCY
    inputs = {
        "rst_ni": idle + [1] * (n + LATENCY),
        **{
            port: idle + [word[k] for word in words] + drain
            for k, port in enumerate(("a_i", "b_i", "c_i"))
        },
    }
    lead = RESET_CYCLES + LATENCY
    values = {"d_o": [0] * lead + [word[3] for word in words]}
    return Case(name, name, inputs, [0] * lead + [1] * n, values)


def ops_case(name, ops, device=""):
    """ucc_lane with a stream of operations, one per cycle: (op, rm, a, b, c,
    d), op None for a cycle that issues none (valid_i clear) and d None for a
    result the FU does not return (``opcodes.settle``). a and b are the
    references' {block scales, vector}, split here into a_i and sa_i, b_i and
    sb_i. Reset, the stream, then idle cycles until the last result; each
    result is compared ``latency(op)`` cycles after issue."""
    n = len(ops)
    total = RESET_CYCLES + n + MAX_LATENCY
    ports = ("valid_i", "op_i", "rm_i", "a_i", "b_i", "sa_i", "sb_i", "c_i")
    vector = (1 << DPA_VECTOR) - 1
    inputs = {port: [0] * total for port in ports}
    inputs["rst_ni"] = [0] * RESET_CYCLES + [1] * (n + MAX_LATENCY)
    d, check = [0] * total, [0] * total
    for i, (op, rm, a, b, c, result) in enumerate(ops):
        if op is None:
            continue
        cycle = RESET_CYCLES + i
        for port, value in zip(ports, (1, op, rm, a & vector, b & vector, a >> DPA_VECTOR, b >> DPA_VECTOR, c)):
            inputs[port][cycle] = value
        if result is not None:
            out = cycle + latency(op)
            assert not check[out], out
            d[out], check[out] = result, 1
    return Case(name, "ucc_lane", inputs, check, {"d_o": d}, device)


NV, OF, UF, NX = 0x10, 0x04, 0x02, 0x01  # fpnew_pkg::status_t's bits (DZ is 0x08)
FLAGLESS = ("alu", "imul", "dpa", "sfu", "none")  # units whose results raise no flag


def fma_case(name, ops, rng, flushes=(), status=None):
    """ucc_fma_bench with a stream of operations (op, rm, a, b, c, d) as ``ops_case`` takes them, flush_i set in the
    cycles ``flushes`` and tag_i the cycle's index (aux_i and mask_i random), compared every cycle with what the
    issue rules leave (``opcodes.fates``): out_valid_o where a result comes, with that operation's result, tag, aux
    and mask; in_ready_o (clear in an SFU function's slot unless op_i is an SFU function); busy_o (an operation from
    its issue to its result or its flush); and ucc_fma's issue_lost and result_hidden. status_o is compared where the
    result's unit raises no flag (0), and where ``status`` (stream index to flags) gives the flags. A d of None is
    evaluated: an operation the stream's own issue rules removed can return a result once flushes free its slot.
    Returns the case and its number of compares."""
    n = len(ops)
    total = RESET_CYCLES + n + MAX_LATENCY + 1
    ports = ("valid_i", "op_i", "rm_i", "a_i", "b_i", "sa_i", "sb_i", "c_i")
    vector = (1 << DPA_VECTOR) - 1
    inputs = {port: [0] * total for port in ports}
    inputs["rst_ni"] = [0] * RESET_CYCLES + [1] * (total - RESET_CYCLES)
    inputs["flush_i"] = [0] * total
    inputs["tag_i"] = [0] * RESET_CYCLES + [i & 0xFFFF for i in range(total - RESET_CYCLES)]
    inputs["aux_i"] = [rng.getrandbits(16) for _ in range(total)]
    inputs["mask_i"] = [rng.getrandbits(1) for _ in range(total)]
    for f in flushes:
        inputs["flush_i"][RESET_CYCLES + f] = 1
    flushes = sorted(flushes)
    fate = fates(ops, flushes)
    out = {port: [0] * total for port in BENCH_OUTPUTS}
    check = {port: [0] * total for port in BENCH_OUTPUTS}
    due = [0] * total
    for i, ((op, rm, a, b, c, d), f) in enumerate(zip(ops, fate)):
        if op is None:
            continue
        cycle = RESET_CYCLES + i
        for port, value in zip(ports, (1, op, rm, a & vector, b & vector, a >> DPA_VECTOR, b >> DPA_VECTOR, c)):
            inputs[port][cycle] = value
        end = cycle + latency(op)
        if f == "lost":
            end = cycle
        elif f == "flushed":
            end = RESET_CYCLES + next(x for x in flushes if x >= i)
        for t in range(cycle, end + 1):
            out["busy_o"][t] = 1
        if f in ("ok", "hidden"):
            due[end] += 1
        if f == "ok":
            u = unit(op)
            out["d_o"][end] = evaluate(op, rm, a, b, c) if d is None else d
            out["tag_o"][end] = inputs["tag_i"][cycle]
            out["aux_o"][end] = inputs["aux_i"][cycle]
            out["mask_o"][end] = inputs["mask_i"][cycle]
            for port in ("d_o", "tag_o", "aux_o", "mask_o"):
                check[port][end] = 1
            if status is not None and i in status:
                out["status_o"][end], check["status_o"][end] = status[i], 1
            elif u in FLAGLESS:
                check["status_o"][end] = 1
    flush_set = set(flushes)
    for t in range(RESET_CYCLES, total):
        i = t - RESET_CYCLES
        j = i - SFU_SLOT
        # an SFU function's FMA takes the input register in its slot, unless a flush dropped it first
        slot = (0 <= j < n and ops[j][0] is not None and unit(ops[j][0]) == "sfu"
                and not any(x in flush_set for x in range(j, i)))
        sfu_now = i < n and ops[i][0] is not None and unit(ops[i][0]) == "sfu"
        out["ready_o"][t] = int(not (slot and not sfu_now))
        out["lost_o"][t] = int(inputs["valid_i"][t] == 1 and not out["ready_o"][t])
        assert out["lost_o"][t] == int(i < n and fate[i] == "lost"), (name, i)
        out["valid_o"][t] = int(due[t] > 0)
        out["hidden_o"][t] = int(due[t] > 1)
        for port in ("valid_o", "ready_o", "busy_o", "lost_o", "hidden_o"):
            check[port][t] = 1
    masks = [sum(check[port][t] << k for k, port in enumerate(BENCH_OUTPUTS)) for t in range(total)]
    case = Case(name, "ucc_fma_bench", inputs, masks, out)
    return case, sum(bin(m).count("1") for m in masks)


def status_ops():
    """Directed operations whose status flags are known (IEEE 754 and RISC-V, as FPnew raises them), each followed
    by idle cycles so that no result meets another: the FMA path's, the compare unit's, the conversions', and units
    that raise none. Returns the stream and its flags by stream index."""
    def d64(x):
        return struct.unpack("<Q", struct.pack("<d", x))[0]

    def d32(x):
        return struct.unpack("<I", struct.pack("<f", x))[0]

    qnan64, snan64, qnan32, snan32 = 0x7FF8000000000000, 0x7FF0000000000001, 0x7FC00000, 0x7F800001
    one64, one32 = d64(1.0), d32(1.0)
    fp16_nan = 0x7E00  # an FP16 NaN element: DPA-16 returns the canonical NaN and no flag
    rows = [
        (fp("FMA"), d64(1.0), d64(1.0), 0, 0),
        (fp("MUL"), d64(1e308), d64(10.0), 0, OF | NX),
        (fp("ADD"), one64, d64(2.0 ** -60), 0, NX),
        (fp("FMA"), d64(float("inf")), 0, one64, NV),
        (fp("FMA"), one64, one64, snan64, NV),
        (fp("MUL"), d64(2.0 ** -1022), d64(0.5), 0, 0),  # an exact subnormal: no underflow
        (fp("MUL", True), d32(2.0) << 32 | d32(1e-30), d32(3.0) << 32 | d32(1e-30), 0, UF | NX),
        (fp("MUL", True), d32(1e-30) << 32 | d32(2.0), d32(1e-30) << 32 | d32(3.0), 0, 0),  # the upper words unread
        (fp("LT"), qnan64, one64, 0, NV),  # a signalling compare
        (fp("EQ"), qnan64, one64, 0, 0),  # a quiet compare
        (fp("EQ"), snan64, one64, 0, NV),
        (fp("NE"), snan64, one64, 0, NV),
        (fp("LE"), one64, d64(2.0), 0, 0),
        (fp("MIN"), snan64, one64, 0, NV),
        (fp("MAX"), qnan64, one64, 0, 0),
        (fp("NEG"), snan64, 0, 0, 0),
        (fp("LT", True), one32 << 32 | qnan32, d32(2.0) << 32 | d32(2.0), 0, NV),
        (fp("LT", True), qnan32 << 32 | one32, d32(2.0) << 32 | d32(2.0), 0, 0),  # the upper words unread
        (fp("TO_S32"), qnan64, 0, 0, NV),
        (fp("TO_S32"), d64(3e9), 0, 0, NV),
        (fp("TO_S32"), d64(1.5), 0, 0, NX),
        (fp("TO_S32"), d64(-7.0), 0, 0, 0),
        (fp("TO_U32", True), d32(-1.0), 0, 0, NV),
        (fp("CVT_F", True), d64(1 / 3), 0, 0, NX),
        (fp("CVT_F", True), d64(1e300), 0, 0, OF | NX),
        (fp("CVT_F"), snan32, 0, 0, NV),
        (fp("CVT_F"), d32(1.5), 0, 0, 0),
        (fp("CVT_S32", True), (1 << 24) + 1, 0, 0, NX),
        (fp("CVT_S32"), 12345, 0, 0, 0),
        (intops.alu("ADD"), 0xFFFFFFFF, 1, 0, 0),
        (intops.mul(intops.WIDE), 0xFFFFFFFF, 0xFFFFFFFF, 0, 0),
        (opcodes.sfu_op(0), 0, 0, 0, 0),  # rcp(+0) = +inf, no flag as the MUFU
        (opcodes.dpa_op(0), fp16_nan, one64, 0, 0),
        (0x44, one64, one64, one64, 0),  # an unnamed code
    ]
    ops, flags = [], {}
    for op, a, b, c, st in rows:
        flags[len(ops)] = st
        ops.append((op, fpops.RNE, a, b, c, evaluate(op, fpops.RNE, a, b, c)))
        ops += [(None, 0, 0, 0, 0, None)] * MAX_LATENCY
    return ops, flags


def check_counts(summary):
    """Every case compared what its stream holds, by the vectors' own counts."""
    cases = summary["cases"]
    for name in ("fp64_fma_lane", "ucc_lane_fp64"):
        assert cases[name]["compares"] == FP64_VECTORS, name
    for name in ("fpnew_fp32_lane", "ucc_lane_fp32"):
        assert cases[name]["compares"] == summary["fp32"]["operations"], name
    assert cases["ucc_lane_mixed"]["compares"] == MIXED
    assert cases["ucc_lane_sfu"]["compares"] == summary["sfu"]["operations"]
    assert cases["ucc_lane_int"]["compares"] == summary["int"]["operations"]
    for name, stream in summary["streams"].items():
        assert cases[f"ucc_lane_{name}"]["compares"] == stream["checked"], name


def verify(output_dir, bin_dir, jobs=8):
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    check_sources()
    mul_rows, mul_kinds = mul_vectors(random.Random(MUL_SEED))
    print(f"{len(mul_rows)} ucc_mul_tiles vectors {mul_kinds}", flush=True)
    streams = lane_vectors()
    for name, info in streams["summary"].items():
        print(f"{name}: {info}", flush=True)
    cases = [
        mul_case(mul_rows),
        lane_case("fp64_fma_lane", streams["fp64"]),
        lane_case("fpnew_fp32_lane", streams["fp32"]),
        *(ops_case(f"ucc_lane_{name}", ops) for name, ops in streams["ops"].items()),
    ]
    counts = dict(ucc_mul_tiles=len(mul_rows), fp64_fma_lane=len(streams["fp64"]),
                  fpnew_fp32_lane=len(streams["fp32"]))
    for name, ops in streams["ops"].items():
        counts[f"ucc_lane_{name}"] = sum(op[5] is not None for op in ops)
    # ucc_fma itself: the issue rules every cycle, under flushes, and the status flags
    rng = random.Random(BENCH_SEED)
    mixed = streams["ops"]["mixed_fu"]
    flushes = [i for i in range(len(mixed)) if rng.randrange(FLUSH_EVERY) == 0]
    status_stream, flags = status_ops()
    bench = dict(
        ucc_fma_mixed_fu=fma_case("ucc_fma_mixed_fu", mixed, rng),
        ucc_fma_flush=fma_case("ucc_fma_flush", mixed, rng, flushes),
        ucc_fma_status=fma_case("ucc_fma_status", status_stream, rng, status=flags),
    )
    for name, (case, compares) in bench.items():
        cases.append(case)
        counts[name] = compares
    fates_flush = fates(mixed, flushes)
    bench_summary = dict(
        seed=f"{BENCH_SEED:#x}", flushes=len(flushes),
        flush_fates={k: fates_flush.count(k) for k in ("ok", "lost", "hidden", "flushed")},
        status_operations=len(flags),
    )
    # The streams that keep the issue rules, again on the build with UCC_CHECK_ISSUE, which stops at a breach; and
    # one that breaks them, on which it must stop
    for name in ISSUE_CHECKED:
        cases.append(ops_case(f"ucc_lane_{name}_issue_checked", streams["ops"][name], "ucc_lane_issue_checked"))
        counts[f"ucc_lane_{name}_issue_checked"] = counts[f"ucc_lane_{name}"]
    breach = ops_case(f"ucc_lane_{BREACHING}_breach", streams["ops"][BREACHING], "ucc_lane_issue_checked")
    breach.stops = True
    cases.append(breach)
    counts[breach.name] = 0
    results, seconds = simulate(cases, bin_dir, output_dir / "cases", jobs)
    summary = dict(
        transdot_commit=TRANSDOT_COMMIT,
        multiplier=dict(seed=f"{MUL_SEED:#x}", vectors=len(mul_rows), kinds=mul_kinds),
        **streams["summary"],
        bench=bench_summary,
        cases={r.name: dict(cycles=r.cycles, compares=r.compares, mismatch=r.mismatch,
                            **({} if r.stopped is None else dict(stopped=r.stopped))) for r in results},
        seconds=seconds,
    )
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"bench: {bench_summary}", flush=True)
    for r in results:
        what = f"stopped at the breach in cycle {r.stopped}" if r.stopped is not None else \
            f"{r.cycles} cycles, {r.compares} compares"
        print(f"{r.name}: {what}, {r.seconds:.1f} s" + (f"\n{r.mismatch}" if r.mismatch else ""), flush=True)
    for r in results:
        if r.mismatch is not None:
            raise AssertionError(r.mismatch)
        assert r.compares == counts[r.name], (r.name, r.compares, counts[r.name])
    check_counts(summary)
    print(f"{len(results)} cases, {sum(r.compares for r in results)} compares, all match "
          f"({seconds['stimulus']:.0f} s writing, {seconds['run']:.0f} s simulating)", flush=True)
    return summary


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--bin", type=Path, required=True, help="the directory of the executables the Makefile builds")
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--jobs", type=int, default=8)
    a = p.parse_args()
    verify(a.out, a.bin, a.jobs)


if __name__ == "__main__":
    main()
