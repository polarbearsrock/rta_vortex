#!/usr/bin/env python3
"""Build isolated UCC experiments using the repository configuration generator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
RTL = ROOT / "hw/rtl"
BUILD = ROOT / "build_ucc"
FLAGS = ["-DASIC", "-DSYNTHESIS", "-DVX_CFG_XLEN=32", "-DVX_CFG_NUM_THREADS=64",
         "-DVX_CFG_EXT_TCU_ENABLE", "-DVX_CFG_TCU_TYPE=TFR",
         "-DVX_CFG_TCU_LATENCY=4", "-DVX_CFG_TCU_TF32_ENABLE",
         "-DVX_CFG_TCU_FP8_ENABLE", "-DVX_CFG_TCU_FP4_ENABLE",
         "-DVX_CFG_TCU_MX_ENABLE", "-DVX_CFG_TCU_MXFP4_ENABLE",
         "-DVX_CFG_TCU_NVFP4_ENABLE"]


def verilator():
    choices = [os.environ.get("VERILATOR"), shutil.which("verilator"),
               "/data2/jwang710/DICE-IDE/.verilator-env/bin/verilator",
               "/data/eda_tools/vortex_tools/verilator/bin/verilator",
               "/data2/jwang710/chipyard/.conda-env/bin/verilator"]
    return next(x for x in choices if x and Path(x).is_file())


def sources(top):
    index = {p.stem: p for p in RTL.rglob("*.sv")}
    index.update({p.stem: p for p in (ROOT / "hw/unittest/ucc").glob("*.sv")})
    visited, ordered = set(), []

    def visit(name):
        if name in visited or name not in index:
            return
        visited.add(name)
        path = index[name]
        content = re.sub(r"//[^\n]*|/\*.*?\*/", "", path.read_text(), flags=re.S)
        for dep in sorted(set(re.findall(r"\bVX_\w+\b", content))):
            visit(dep)
        ordered.append(path)

    visit(top)
    return sorted(ordered, key=lambda p: not p.stem.endswith("_pkg"))


def prepare(extra_flags=()):
    BUILD.mkdir(exist_ok=True)
    subprocess.run([str(ROOT / "configure"), "--xlen=32",
                    "--tooldir=/data/eda_tools/vortex_tools"], cwd=BUILD, check=True)
    suffix = "_" + hashlib.sha256(" ".join(extra_flags).encode()).hexdigest()[:8] if extra_flags else ""
    config = BUILD / ("ucc_config" + suffix)
    config.mkdir(exist_ok=True)
    subprocess.run(["python3", str(ROOT / "ci/gen_config.py"),
                    "--config", str(ROOT / "VX_config.toml"), "--format", "verilog",
                    "--resolved", "--cflags", " ".join(FLAGS + list(extra_flags)),
                    "--output", str(config / "VX_config.vh")], cwd=BUILD, check=True)
    return config


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["segments", "mufu_original", "stream", "dpa_model", "baseline", "shift", "shift-separate", "fma11", "fma8", "fma_direct", "int_direct", "fpu_direct", "mufu_direct", "v1_csa", "v1", "v2", "v3", "v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp", "native", "pair", "prepare-synth"])
    parser.add_argument("--top", default="VX_ucc_dpa16_comb")
    parser.add_argument("--width", type=int, default=80)
    parser.add_argument("--parameter", action="append", default=[])
    parser.add_argument("--label", default="")
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_]*', args.label) or any(not re.fullmatch(r'[A-Z][A-Z0-9_]*=\d+', p) for p in args.parameter):
        parser.error('label must be alphanumeric; parameters must be NAME=unsigned_integer')
    if args.parameter and (not args.label or args.action == 'prepare-synth'):
        parser.error('test parameter overrides require a label and cannot be used for synthesis')
    extra_flags = ["-DVX_CFG_EXT_MUFU_ENABLE"] if args.action == "mufu_original" or args.top == "VX_ucc_mufu_original_comb" else []
    config = prepare(extra_flags)
    includes = [config, BUILD / "hw", RTL, RTL / "libs"]
    common = [verilator(), "-DVX_CFG_XLEN=32"] + ["-I" + str(p) for p in includes]
    common += [str(config / "VX_config.vh")]
    if args.action != "prepare-synth":
        top = {"segments": "VX_ucc_segments_test", "mufu_original": "VX_ucc_mufu_original_test", "stream": "VX_ucc_stream", "dpa_model": "VX_ucc_dpa16_comb", "baseline": "VX_ucc_baseline_test", "shift": "VX_ucc_shift_shared",
               "shift-separate": "VX_ucc_shift_separate", "int_direct": "VX_ucc_int_standalone", "fpu_direct": "VX_ucc_fpu_standalone", "mufu_direct": "VX_ucc_mufu_standalone", "fma11": "VX_ucc_fma_test",
               "fma8": "VX_ucc_fma_test", "fma_direct": "VX_ucc_fma_standalone",
               "v1_csa": "VX_ucc_v1_csa_test", "v1": "VX_ucc_v1_test", "v2": "VX_ucc_v2_test",
               "v3": "VX_ucc_v3_test", "v4": "VX_ucc_v4_test", "v4_native": "VX_ucc_v4_native_test", "v4_paired": "VX_ucc_v4_paired_test", "v4_small": "VX_ucc_v4_small_test", "v4_exp": "VX_ucc_v4_exp_test", "v4_exact_exp": "VX_ucc_v4_exact_exp_test",
               "pair": "VX_paired_shift_jam", "native": "VX_ucc_native_test"}[args.action]
        obj = BUILD / ("ucc_" + args.action + ("_w" + str(args.width) if args.width != 80 else "") + ("_" + args.label if args.label else ""))
        obj.mkdir(exist_ok=True)
        (obj / "result.txt").unlink(missing_ok=True)
        cxx = os.environ.get("CXX", "/data/eda_tools/gcc-11/bin/g++")
        cxxlib = Path(subprocess.check_output([cxx, "-print-file-name=libstdc++.so"], text=True).strip()).parent
        cflags = "-std=c++17 -O2" + (" -DSEPARATE_SHIFT" if args.action == "shift-separate" else "")
        if args.action in ("v2", "v3", "v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp"):
            cflags += " -DUCC_V2"
        if args.action in ("v3", "v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp"):
            cflags += " -DUCC_V3"
        if args.action in ("v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp"):
            cflags += " -DUCC_V4"
        if args.action == "v1_csa":
            cflags += " -DUCC_V1_CSA"
        if args.action == "v4_exact_exp":
            cflags += " -DUCC_V4_EXACT_EXP"
        if args.action == "v4_exp":
            cflags += " -DUCC_V4_EXP"
        if args.action == "v4_small":
            cflags += " -DUCC_V4_SMALL"
        if args.action == "v4_paired":
            cflags += " -DUCC_V4_PAIRED"
        if args.action == "v4_native":
            cflags += " -DUCC_V4_NATIVE"
        if args.action == "native":
            cflags += " -DUCC_NATIVE"
        if args.action == "mufu_direct":
            cflags += " -DMUFU_DIRECT"
        if args.action == "fma_direct":
            cflags += " -DFMA_DIRECT"
        cmd = common + ["--cc", "--exe", "--assert",
                        "--top-module", top, "--Mdir", str(obj),
                        "-CFLAGS", cflags, "-LDFLAGS", "-Wl,-rpath," + str(cxxlib)]
        cmd += [str(p) for p in sources(top)]
        cpp = "unified" if args.action in ("v1_csa", "v1", "v2", "v3", "v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp", "native") else "pair" if args.action == "pair" else "fma" if args.action.startswith("fma") else "baseline" if args.action == "baseline" else "shift"
        if args.action == "segments":
            cpp = "segments"
        elif args.action == "mufu_original":
            cpp = "mufu_original"
        elif args.action == "stream":
            cpp = "stream"
        elif args.action == "dpa_model":
            cpp = "dpa"
        elif args.action == "int_direct":
            cpp = "integer"
        elif args.action in ("fpu_direct", "mufu_direct"):
            cpp = "scalar"
        if cpp == "fma":
            cmd += ["-GW=" + str(args.width)]
            if args.action in ("fma11", "fma8"):
                cmd += ["-GCHUNK=" + args.action[3:]]
        elif cpp == "unified" or args.action == "fpu_direct":
            cmd += ["-GW=" + str(args.width)]
        cmd += [str(ROOT / ("hw/unittest/ucc/" + cpp + ".cpp"))]
        cmd += ["-G" + p for p in args.parameter]
        test_sources = sources(top) + [ROOT / ("hw/unittest/ucc/" + cpp + ".cpp")]
        reference_sources = sorted((ROOT / 'hw/unittest/ucc').glob('*.py'))
        test_manifest = {
            'top': top, 'action': args.action, 'width': args.width, 'parameters': args.parameter,
            'verilator_command': cmd, 'compiler': cxx,
            'verilator_version': subprocess.check_output([common[0], '--version'], text=True).strip(),
            'source_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in test_sources},
            'reference_sha256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in reference_sources},
            'config_sha256': hashlib.sha256((config/'VX_config.vh').read_bytes()).hexdigest(),
            'status': 'building',
        }
        (obj/'test_manifest.json').write_text(json.dumps(test_manifest, indent=2)+'\n')
        with (obj / "build.log").open("w") as log:
            subprocess.run(cmd, cwd=BUILD, stdout=log, stderr=subprocess.STDOUT, check=True)
            subprocess.run(["make", "-C", str(obj), "-f", "V" + top + ".mk", "-j4",
                            "CXX=" + cxx, "LINK=" + cxx, "AR=/usr/bin/ar"], cwd=BUILD,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        sim_args = []
        if args.action == "dpa_model":
            from dpa_reference import generate as generate_dpa
            vector_file = obj / "vectors.txt"
            generate_dpa(vector_file)
            sim_args.append(str(vector_file))
        if cpp in ("fma", "unified") or args.action == "fpu_direct":
            from fma_vectors import generate
            vector_file = obj / "vectors.txt"
            generate(vector_file, args.width, int(args.action[3:]) if args.action in ("fma11", "fma8") else 8 if args.action in ("native", "v4_native", "v4_paired", "v4_small", "v4_exp") else 11,
                     native=args.action in ("native", "v4_native", "v4_paired", "v4_small", "v4_exp"))
            sim_args.append(str(vector_file))
        if args.action in ("v3", "v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp", "fpu_direct", "mufu_direct"):
            from aux_vectors import generate as generate_aux
            aux_file = obj / "aux_vectors.txt"
            generate_aux(aux_file, extended=args.action in ("v4", "v4_native", "v4_paired", "v4_small", "v4_exp", "v4_exact_exp", "mufu_direct"),
                         narrow=args.action in ("v4_small", "v4_exp"), natural=args.action in ("v4_exp", "v4_exact_exp", "mufu_direct"),
                         compact="COMPACT_EXP=1" in args.parameter)
            sim_args.append(str(aux_file))
        result = subprocess.run([str(obj / ("V" + top)), *sim_args], cwd=BUILD,
                                text=True, capture_output=True)
        test_manifest.update(status='passed' if result.returncode == 0 else 'failed', returncode=result.returncode,
                             vectors_sha256={str(p.relative_to(BUILD)): hashlib.sha256(p.read_bytes()).hexdigest()
                                             for p in map(Path, sim_args)})
        (obj/'test_manifest.json').write_text(json.dumps(test_manifest, indent=2)+'\n')
        (obj / "result.txt").write_text(result.stdout + result.stderr)
        print(result.stdout + result.stderr, end="")
        result.check_returncode()
    else:
        out = BUILD / "ucc_synth" / args.top
        out.mkdir(parents=True, exist_ok=True)
        srcs = sources(args.top)
        cmd = common + ["-E", "-P"] + [str(p) for p in srcs]
        with (out / "design.sv").open("w") as f:
            subprocess.run(cmd, cwd=BUILD, stdout=f, check=True)
        (out / "manifest.json").write_text(json.dumps({
            "top": args.top, "config_flags": FLAGS + extra_flags,
            "sources": [str(p.relative_to(ROOT)) for p in srcs],
            "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in srcs},
            "preprocessed_sha256": hashlib.sha256((out / "design.sv").read_bytes()).hexdigest(),
            "config_sha256": hashlib.sha256((config / "VX_config.vh").read_bytes()).hexdigest(),
            "timing_budget_ns": 5.0, "view": "combinational",
        }, indent=2) + "\n")
        print(out)


if __name__ == "__main__":
    main()
