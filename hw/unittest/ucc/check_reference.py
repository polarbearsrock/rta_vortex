#!/usr/bin/env python3
import itertools
import json
from pathlib import Path
import random
import shutil
import subprocess
from reference import fma

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "build_ucc/ucc_reference"
OUT.mkdir(parents=True, exist_ok=True)
softfloat = ROOT / "third_party/softfloat"
sf_build = OUT / "softfloat"
sf_build.mkdir(exist_ok=True)
shutil.copyfile(softfloat / "build/Linux-x86_64-GCC/platform.h", sf_build / "platform.h")
with (OUT / "softfloat_build.log").open("w") as log:
    subprocess.run(["make", "-f", str(softfloat / "build/Linux-x86_64-GCC/Makefile"),
                    "SOURCE_DIR=" + str(softfloat / "source"), "-j4"], cwd=sf_build,
                   stdout=log, stderr=subprocess.STDOUT, check=True)
subprocess.run(["gcc", "-std=c11", "-O2", "-I" + str(softfloat / "source/include"),
                str(Path(__file__).with_name("softfloat_oracle.c")), str(sf_build / "softfloat.a"),
                "-o", str(OUT / "softfloat_oracle")], cwd=ROOT / "build_ucc", check=True)
subprocess.run(["gcc", "-std=c11", "-O2", "-frounding-math", "-fno-builtin-fmaf",
                str(Path(__file__).with_name("fma_oracle.c")), "-lm", "-o", str(OUT / "oracle")],
               cwd=ROOT / "build_ucc", check=True)
edges = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x00800000,
         0x3f000000, 0x3f800000, 0xbf800000, 0x3f800001,
         0x7f7fffff, 0xff7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7f800001]
vectors = [(*v, rm) for v in itertools.product(edges, repeat=3) for rm in range(4)]
rng = random.Random(0x464D4132)
vectors += [(*(rng.getrandbits(32) for _ in range(3)), rng.randrange(4)) for _ in range(50000)]
text = "".join(f"{a:08x} {b:08x} {c:08x} {rm}\n" for a, b, c, rm in vectors)
failures = []
policy_differences = []
for name in ("softfloat_oracle", "oracle"):
    oracle = subprocess.run([str(OUT / name)], input=text, capture_output=True,
                            text=True, cwd=ROOT / "build_ucc", check=True)
    answers = oracle.stdout.splitlines()
    assert len(answers) == len(vectors)
    for v, line in zip(vectors, answers):
        expected = tuple(int(x, 16) for x in line.split())
        got = fma(*v)
        if got != expected:
            mismatch = {"input": [f"{x:08x}" for x in v[:3]], "rounding": v[3],
                        "reference": got, name: expected}
            a, b, c = (x & 0x7fffffff for x in v[:3])
            invalid_qnan = ((a == 0 and b == 0x7f800000) or (b == 0 and a == 0x7f800000)) and c > 0x7f800000 and c & 0x400000
            if name == "oracle" and invalid_qnan and got == (0x7fc00000, 16) and expected == (0x7fc00000, 0):
                policy_differences.append(mismatch)
            else:
                failures.append(mismatch)
report = {"cases_per_oracle": len(vectors), "oracles": ["Berkeley SoftFloat", "system libm fmaf"],
          "mismatches": len(failures), "examples": failures[:20],
          "libm_invalid_qnan_policy_differences": len(policy_differences)}
(OUT / "result.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
raise SystemExit(bool(failures))
