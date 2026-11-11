# Frozen five-stage DPA16 baseline

`design.sv` is the exact standalone RTL used for the **39,050.802 µm²**
Genus 25.10 / N28 SSG 0.72 V / 125°C baseline. Elaborate
`ucc_dpa16_baseline` with `DpaStages=5`; throughput is one DPA transaction
per cycle. The 1 GHz setup view passes with retiming disabled.

The original Shwet DPA arithmetic is retained: 27-bit alignment window and
truncation, with all sixteen original 12×12 tiles. NVFP4 and MXFP4 block
scaling are included. The B32+ UCC instead uses its shared rounding backend;
the area comparison does not imply identical DPA rounding semantics.

RTL SHA-256:
`778387c9201dea5cac75ba15649a9557d2a449cd953478f042a5602ad7bdefca`.

`manifest.json` is the immutable source/provenance record and includes older
synthesis settings. The settings for this measurement are in
[baseline/manifest.json](../results/b32plus_sm25_ssg072_1ghz/baseline/manifest.json):
LEF/QRC, ungroup both and clock-gating insertion enabled.

From the repository root in the recorded tool/PDK environment:

```bash
python3 hw/syn/ucc_reuse/run_pipeline_sm.py \
  --baseline hw/syn/ucc_reuse/baseline_pipe5 \
  --run-dir build_dpa5_reproduce --launch
```

[Matched baseline and UCC results](../results/b32plus_sm25_ssg072_1ghz/README.md).
