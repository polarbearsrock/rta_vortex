# B32+ UCC and DPA16: matched 1 GHz synthesis

The selected no-FP64 B32+ implementation has **46,711.098 µm²** cell area,
below the 47,000 µm² target. Relative to the five-stage DPA16 baseline,
the increment is **7,660.296 µm² / 19.62%**.

| Final Genus result | DPA16 baseline | B32+ UCC |
|---|---:|---:|
| Cell area, µm² | 39,050.802 | 46,711.098 |
| Combinational cell area, µm² | 31,659.138 | 34,977.852 |
| Sequential cell area including ICG, µm² | 7,391.664 | 11,733.246 |
| Setup WNS / TNS, ps | 0 / 0 | DPA and CUDA: 0 / 0 |
| Violating setup paths | 0 | Both views: 0 |
| Inserted clock gates | 5 | 0 |

Raw results: [UCC PPA](synthesis/ppa.json), [baseline PPA](baseline/ppa.json),
[UCC area](synthesis/area.rpt), [baseline area](baseline/area.rpt),
[CUDA timing](synthesis/timing_cuda.rpt), [DPA timing](synthesis/timing_dpa.rpt),
[baseline timing](baseline/timing_dpa.rpt).

## Matched flow

Genus 25.10-p002_1; TSMC N28 RVT/HVT/LVT, SSG 0.72 V / 125°C setup;
SM SS/FF/TT MMMC views and LEF/QRC inputs. Period 1 ns, input/output delay
300 ps each, setup uncertainty 50 ps, clock transition 50 ps, maximum
transition 100 ps, maximum fanout 32, BUFFD4BWP30P140 input driver, output
load 5 fF. Generic effort medium, map/opt effort high; ungroup both;
clock-gating insertion enabled; **retiming disabled**.

These are completed `syn_opt` library cell areas with PLE, before placement,
routing and CTS. Net area is not included. The UCC uses separate DPA/CUDA
views with `dpa_mode_i` held constant; switching requires draining the pipeline.
The only false path is reset. No additional data-path timing exceptions
were introduced for the selected candidate.

The authoritative measurement settings are in
[synthesis/manifest.json](synthesis/manifest.json) and
[baseline/manifest.json](baseline/manifest.json), checked against the tool's
`settings.rpt` and analysis-view reports. The `source_manifest.json` files
retain historical provenance; their earlier synthesis settings are not the
settings of this measurement. PDK files are referenced by paths and hashes;
the libraries themselves are not included.

## RTL and scheduling

- [Selected UCC RTL](../../selected_pipe5/design.sv), top `ucc_b32_pipe5`.
  SHA-256: `0110c24c49204a77ff3fe8ab9b53734ed5d425aa8567da2ccc16a75ff6ad51e2`.
- [Baseline RTL](../../baseline_pipe5/design.sv), top `ucc_dpa16_baseline`,
  parameter `DpaStages=5`.
  SHA-256: `778387c9201dea5cac75ba15649a9557d2a449cd953478f042a5602ad7bdefca`.
- FP32, INT32, DPA and other ordinary operations have fixed five-cycle
  latency. SFU latency is six cycles. Homogeneous instruction streams have II=1.
- The interface is valid-only. An ordinary instruction cannot issue in the
  first cycle after an SFU instruction; ordinary-to-SFU issue has no additional
  forbidden offset. The dispatcher must enforce this fixed reservation and
  drain all classes before changing `dpa_mode_i`.
- Retained formats include TF32, FP16/BF16, FP8/MXFP8 and FP4/NVFP4/MXFP4.
  Seven approximate MUFU functions remain: rcp, rsqrt, ex2, lg2, sinpi,
  cospi and tanh. FP64 is disabled.
- The baseline retains Shwet's 27-bit DPA alignment/truncation semantics.
  B32+ retains its shared rounding backend, so the two DPA arithmetic
  implementations do not claim identical rounding semantics.

These frozen, self-contained files are the synthesis inputs. They are
standalone FU fixtures and do not replace or integrate the repository's
production `ucc_lane` into the GPU.

## Optimization and validation

Manual register placement separates tile input selection from subsequent
arithmetic. Proven mask simplifications remove 226 internal masks, followed
by transferring 134 output-mask bits to 21 existing input-register equations.
The last step changes neither arithmetic instances nor stage positions.
Relative to the 47,322.198 µm² parent, combinational area falls by 731.430 µm²
while sequential area rises by 120.330 µm², saving 611.100 µm² overall.

The accepted RTL regression passes **143,486 checks over 175,387 cycles**,
including 200 drained mode transitions, reset, mixed-issue reservation bubbles,
all eight DPA encodings and seven MUFU functions. The existing stream includes
97 consecutive DPA issues with changing formats and 64 consecutive SFU issues.
See [validation summary](validation/summary.json),
[DPA coverage](validation/dpa_stream_coverage.json) and
[baseline validation record](validation/baseline_summary.json).

[Acceptance](acceptance.json) records 285 passed checks covering hashes,
functional evidence and matched synthesis settings/results. Local proof
snapshots are in [proofs](proofs/); these are not whole-core formal equivalence.
No new gate-level replay was needed. The MUFU functions retain their previous
approximate numerical behavior, with no IEEE correct-rounding claim.

[Stage-area diagnostics](diagnostics/stage_area/README.md) and
[critical-path diagnostics](diagnostics/path_audit/README.md) explain the
physical implementation. Endpoint fanin cones can overlap and must not be
summed as independent arithmetic-module areas.

## Reproduce

In the recorded Genus/PDK environment, from the repository root, choose fresh
run directories. Omit `--launch` to prepare inputs only:

```bash
python3 hw/syn/ucc_reuse/run_pipeline_sm.py \
  --baseline hw/syn/ucc_reuse/selected_pipe5 \
  --run-dir build_b32plus_reproduce --launch

python3 hw/syn/ucc_reuse/run_pipeline_sm.py \
  --baseline hw/syn/ucc_reuse/baseline_pipe5 \
  --run-dir build_dpa5_reproduce --launch
```

The runner uses the tool/SM/PDK paths in `run_sm_corner.py`. Frozen copies of
the actual SDC, MMMC, synthesis script and SM reference configurations are
also included in each result directory. The source checkout used for these
results was based on `670b016a2`; no unpublished production RTL is needed
to synthesize either frozen fixture.

To replay the UCC RTL checks, copy `validation/` into a fresh build directory,
decompress `vectors.txt.gz`, and run from there with Xcelium 22.09:

```bash
xrun -64bit -sv -timescale 1ns/1ps -top b32_schedule_tb \
  /absolute/path/to/checkout/hw/syn/ucc_reuse/selected_pipe5/design.sv \
  reference.sv bench.sv +NORMAL_AFTER_SFU_MASK=2 +SFU_AFTER_NORMAL_MASK=0
```

The [package manifest](package_manifest.json) hashes the published files using
paths relative to the repository root. Raw reports, proof inputs/logs and
validation files are unchanged from the accepted local archive; synthesis
logs are losslessly compressed. Duplicate RTL, mapped netlists and generated
mapped SDCs are omitted. `source_archive_manifest.json`, `acceptance.json` and
`reproduction_check.json` preserve original provenance and may refer to local
build paths or omitted files; they are not portable live-status records.
