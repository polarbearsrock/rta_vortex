# Selected B32+ fixed pipeline

`design.sv` is the frozen, synthesizable `ucc_b32_pipe5` top with no FP64.
Genus 25.10 / N28 SSG 0.72 V /125°C final cell area is **46,711.098 µm²**;
both DPA and CUDA setup views pass at 1 GHz with retiming disabled.
The same-flow five-stage DPA16 baseline is 39,050.802 µm²: **19.62% overhead**.

Ordinary instructions take five cycles, SFU six, with homogeneous II=1.
The dispatcher must reserve the first cycle after SFU issue against ordinary
issue, and drain the pipeline before changing `dpa_mode_i`. There is no
dynamic backpressure. All frozen B32 instruction and FP4 scaling semantics
are preserved; this directory is an independent FU fixture, not GPU integration.

The RTL hash is
`0110c24c49204a77ff3fe8ab9b53734ed5d425aa8567da2ccc16a75ff6ad51e2`.
`manifest.json` and `pipeline.json` retain the generation and validation evidence.

From the repository root, reproduce synthesis into a new directory:

```bash
python3 hw/syn/ucc_reuse/run_pipeline_sm.py \
  --baseline hw/syn/ucc_reuse/selected_pipe5 \
  --run-dir build_ucc_b32plus_reproduce --launch
```

[Accepted result, constraints, proof snapshots and regression vectors](../results/b32plus_sm25_ssg072_1ghz/README.md).
