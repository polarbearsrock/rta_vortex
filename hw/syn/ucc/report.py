#!/usr/bin/env python3
"""Extract measured cell area and timing, rejecting stale or wrongly constrained runs."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def measured(path):
    manifest = json.loads((path / "manifest.json").read_text())
    top = manifest["top"]
    digest = hashlib.sha256((path / "design.sv").read_bytes()).hexdigest()
    if digest != manifest["preprocessed_sha256"]:
        raise ValueError(f"preprocessed design changed after manifest creation: {path}")
    if not (path / "complete.txt").is_file():
        raise ValueError(f"unfinished synthesis: {path}")
    log = (path / "run.log").read_text()
    if "ELABUTL-125" in log or re.search(r"Assuming a logic .*value for undriven", log):
        raise ValueError(f"undriven signals invalidate synthesis: {path}")
    sdc = (path / "mapped.sdc").read_text()
    if not re.search(r"set_units -time 1000ps", sdc):
        raise ValueError(f"unexpected time units: {path}")
    period = float(re.search(r'create_clock .*?-period ([\d.]+)', sdc)[1])
    if period != manifest["timing_budget_ns"]:
        raise ValueError(f"constraint mismatch: {period}ns at {path}")
    if not re.search(r"set_input_transition 0\.05\b", sdc):
        raise ValueError(f"input slew is not 50ps: {path}")
    if not re.search(r"set_load -pin_load 0\.005\b", sdc):
        raise ValueError(f"output load is not 5fF: {path}")
    area = (path / "area.rpt").read_text()
    row = re.search(r"^" + re.escape(top) + r"\s+(\d+)\s+([\d.]+)", area, re.M)
    timing = (path / "timing.rpt").read_text()
    delay = int(re.search(r"Data Path:-\s+(\d+)", timing)[1])
    slack = int(re.search(r"Slack:=\s+(-?\d+)", timing)[1])
    required = int(re.search(r"Required Time:=\s+(\d+)", timing)[1])
    if required != round(period * 1000):
        raise ValueError(f"timing report budget mismatch: {path}")
    qor = (path / "qor.rpt").read_text()
    seq = int(re.search(r"Sequential Instance Count\s+(\d+)", qor)[1])
    if manifest["view"] == "combinational" and seq:
        raise ValueError(f"sequential cells in combinational view: {path}")
    power = (path / "power_vectorless.rpt").read_text()
    if "Power Unit: W" not in power:
        raise ValueError(f"unexpected power units: {path}")
    power_row = re.search(r"^\s*Subtotal\s+([\deE.+-]+)\s+([\deE.+-]+)\s+([\deE.+-]+)", power, re.M)
    leakage, internal, switching = map(float, power_row.groups())
    return {
        "top": top, "area_um2": float(row[2]), "cells": int(row[1]),
        "sequential_cells": seq, "data_path_ps": delay, "slack_ps": slack,
        "critical_path_start": re.search(r"Startpoint:\s+(.+)", timing)[1].strip(),
        "critical_path_end": re.search(r"Endpoint:\s+(.+)", timing)[1].strip(),
        "sequential_fmax_mhz": None,
        "combinational_area_um2": float(row[2]) if seq == 0 else None,
        "sequential_area_um2": 0.0 if seq == 0 else None,
        "power_vectorless": {"leakage_w": leakage, "internal_w": internal,
                             "switching_w": switching, "dynamic_w": internal + switching,
                             "limitation": "Genus default activity assumptions; no workload waveform annotation."},
        "timing_budget_ns": period, "timing_met": slack >= 0,
        "corner": "TT 0.8V 25C", "wireload": "ZeroWireload",
        "input_slew_ps": 50, "output_load_ff": 5,
        "preprocessed_sha256": digest,
        "dpa_numeric_sources": {name: digest for name, digest in manifest.get("source_sha256", {}).items()
                                if name in ("hw/rtl/tcu/tfr/VX_tcu_tfr_mul_f4.sv", "hw/rtl/tcu/tfr/VX_tcu_tfr_mul_f8.sv")},
        "reports": str(path), "status": "synthesized; functional verification reported separately",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    report = {"measurements": [measured(p.resolve()) for p in args.runs]}
    by_top = {r["top"]: r for r in report["measurements"]}
    dpa_sources = [r["dpa_numeric_sources"] for r in report["measurements"] if r["dpa_numeric_sources"]]
    if dpa_sources and any(s != dpa_sources[0] for s in dpa_sources[1:]):
        raise ValueError("mixed DPA numerical revisions: use matching baseline and unified runs")
    if "VX_ucc_shift_shared" in by_top and "VX_ucc_shift_separate" in by_top:
        report["shift_area_saving_fraction"] = 1 - by_top["VX_ucc_shift_shared"]["area_um2"] / by_top["VX_ucc_shift_separate"]["area_um2"]
    report["incremental_comparisons"] = []
    chain = ["VX_ucc_dpa16_comb", "VX_ucc_v1_comb", "VX_ucc_v2_comb", "VX_ucc_v3_comb", "VX_ucc_v4_ex2_comb"]
    for before, after in zip(chain, chain[1:]):
        if before in by_top and after in by_top:
            a, b = by_top[before]["area_um2"], by_top[after]["area_um2"]
            report["incremental_comparisons"].append({"from": before, "to": after,
                "area_increment_um2": b - a, "increment_fraction": b / a - 1})
    optimized_chain = ["VX_ucc_dpa16_comb", "VX_ucc_v1_opt_comb", "VX_ucc_v2_opt_comb", "VX_ucc_v3_opt_comb", "VX_ucc_v4_csa_const_comb"]
    for before, after in zip(optimized_chain, optimized_chain[1:]):
        if before in by_top and after in by_top:
            a, b = by_top[before]["area_um2"], by_top[after]["area_um2"]
            report["incremental_comparisons"].append({"from": before, "to": after,
                "area_increment_um2": b-a, "increment_fraction": b/a-1,
                "qualification": "CSA-first exact FMA and direct normalization; differences include mapping/timing interactions."})
    if all(name in by_top for name in (chain[0], chain[1], "VX_ucc_fma_test")):
        separate = by_top[chain[0]]["area_um2"] + by_top["VX_ucc_fma_test"]["area_um2"]
        report["first_exact_v1_vs_separate_dpa_fma"] = {"separate_area_um2": separate,
            "shared_area_um2": by_top[chain[1]]["area_um2"],
            "saving_fraction": 1 - by_top[chain[1]]["area_um2"] / separate,
            "coverage": "FMA/MUL/ADD/SUB only; not the complete CUDA or system aggregate comparison."}
    if all(name in by_top for name in (chain[0], chain[1], "VX_ucc_fma_standalone")):
        separate = by_top[chain[0]]["area_um2"] + by_top["VX_ucc_fma_standalone"]["area_um2"]
        report["first_exact_v1_vs_conventional_standalone"] = {"separate_area_um2": separate,
            "shared_area_um2": by_top[chain[1]]["area_um2"],
            "saving_fraction": 1 - by_top[chain[1]]["area_um2"] / separate,
            "coverage": "Same four FP32 operations; conventional full multiplier and two aligned terms. Use this stronger comparator over sliced standalone FMA."}
    units = ["VX_ucc_dpa16_comb", "VX_ucc_int_standalone", "VX_ucc_fpu_standalone", "VX_ucc_mufu_standalone"]
    report["full_unit_comparisons"] = []
    if all(name in by_top for name in units):
        dpa, integer, fpu, mufu = [by_top[name]["area_um2"] for name in units]
        separate = dpa + integer + fpu + mufu
        for name in ("VX_ucc_v4_exp_comb", "VX_ucc_v4_exact_exp_comb", "VX_ucc_v4_norm_comb", "VX_ucc_v4_csa_comb",
                     "VX_ucc_v4_route_comb", "VX_ucc_v4_const_comb", "VX_ucc_v4_const_unpaired_comb",
                     "VX_ucc_v4_compact_comb", "VX_ucc_v4_csa_const_comb",
                     "VX_ucc_v4_anchor_comb", "VX_ucc_v4_anchor_crop_comb",
                     "VX_ucc_v4_compact_unpaired_comb"):
            if name not in by_top:
                continue
            unified = by_top[name]["area_um2"]
            entry = {"unified_top": name, "unified_um2": unified, "separate_um2": separate,
                     "overhead_vs_dpa_fraction": unified/dpa-1,
                     "saving_vs_separate_fraction": 1-unified/separate,
                     "same_function_groups_system": {"separate_um2": 64*dpa+16*integer+32*fpu+4*mufu,
                         "unified_um2": 64*unified,
                         "saving_fraction": 1-(64*unified)/(64*dpa+16*integer+32*fpu+4*mufu)},
                     "qualification": "Tensor/scalar modes mutually exclusive; separate units can execute concurrently. Native FP is RNE/FTZ approximate; standalone FPU is IEEE exact. Both MUFU comparators cover EX2 and natural EXP only; polynomial precisions differ."}
            if "VX_ucc_fma_standalone" in by_top:
                fma = by_top["VX_ucc_fma_standalone"]["area_um2"]
                requested = 64*dpa+16*integer+32*fma+4*mufu
                entry["requested_64D_16I_32FMA_4SFU"] = {"separate_um2": requested,
                    "unified_um2": 64*unified, "saving_fraction": 1-64*unified/requested,
                    "qualification": "User modeling assumption, not NVIDIA disclosure; FMA-only blocks omit conversion/FP compare capabilities included in UCC. SFU here means the measured two-operation EXP/EX2 unit."}
            report["full_unit_comparisons"].append(entry)
    text = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(text)
    if not args.quiet:
        print(text, end="")


if __name__ == "__main__":
    main()
