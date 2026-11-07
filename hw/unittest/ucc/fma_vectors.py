import itertools
import json
from pathlib import Path
import random
import struct
from reference import fma, approximate_fma, native_bf16x9_fma


def generate(path, width=80, chunk=11, native=False):
    edges = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000,
             0x3f000000, 0x3f800000, 0xbf800000, 0x3f800001,
             0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7f800001]
    cases = [(*v, op, rm) for v in itertools.product(edges, repeat=3)
             for op in range(4) for rm in range(4)]
    rng = random.Random(0x464d4131)
    cases += [(*(rng.getrandbits(32) for _ in range(3)), rng.randrange(4), rng.randrange(4))
              for _ in range(100000)]
    for _ in range(20000):
        a = rng.randrange(0x3f000000, 0x40000000)
        b = rng.randrange(0x3f000000, 0x40000000)
        af, bf = (struct.unpack("f", struct.pack("I", x))[0] for x in (a, b))
        c = struct.unpack("I", struct.pack("f", -af * bf))[0]
        cases.append((a, b, c, 0, rng.randrange(4)))
    value_differences, flag_differences, maximum_ulp = 0, 0, 0
    worst = None
    with Path(path).open("w") as f:
        for a, b, c, op, rm in cases:
            if op == 0:
                operands = a, b, c
            elif op == 1:
                operands = a, b, (a ^ b) & 0x80000000
            else:
                operands = a, 0x3f800000, b ^ (0x80000000 if op == 3 else 0)
            exact, exact_flags = fma(*operands, 0 if native else rm)
            result, flags = (native_bf16x9_fma(*operands) if native else
                             (exact, exact_flags) if width >= 80 else approximate_fma(*operands, rm, width, chunk))
            if result != exact:
                value_differences += 1
                if (result & 0x7fffffff) < 0x7f800000 and (exact & 0x7fffffff) < 0x7f800000:
                    def ordered(x):
                        return 0x80000000 - (x & 0x7fffffff) if x >> 31 else 0x80000000 + x
                    ulp = abs(ordered(result) - ordered(exact))
                    if ulp > maximum_ulp:
                        maximum_ulp, worst = ulp, {"inputs": [a, b, c], "op": op, "rm": rm,
                                                  "exact": exact, "approximate": result}
            flag_differences += flags != exact_flags
            f.write(f"{a:08x} {b:08x} {c:08x} {op:x} {rm:x} {result:08x} {flags:02x}\n")
    Path(path).with_suffix(".accuracy.json").write_text(json.dumps({
        "cases": len(cases), "width": 32 if native else width, "chunk": chunk, "native_bf16x9": native,
        "alignment_window_bits": 26 if native else width,
        "ieee_comparison_rounding": "RNE" if native else "instruction rounding mode",
        "value_differences_from_ieee": value_differences,
        "flag_differences_from_ieee": flag_differences,
        "maximum_finite_ulp_distance": maximum_ulp, "worst_finite_case": worst,
        "note": ("Native DPA alignment, fixed RNE/FTZ; only invalid flag implemented." if native else
                 "IEEE FMA reference." if width >= 80 else
                 "Approximate results are round-to-odd partial-term semantics, not IEEE FMA.")
    }, indent=2) + "\n")
    return len(cases)
