# B32+ UCC: fixed pipeline at 1 GHz

The selected standalone no-FP64 UCC occupies **46,711.098 µm²**, compared with
**39,050.802 µm²** for the matched five-stage DPA16: **19.62% overhead**.
Both pass the required setup views at TSMC N28 SSG 0.72 V / 125°C, 1 GHz,
with Genus 25.10, LEF/QRC, 300 ps input/output delays and retiming disabled.

Ordinary instructions take five cycles; SFU instructions take six. Homogeneous
streams have II=1. The dispatcher reserves the first cycle after SFU issue
against ordinary issue and drains the pipeline before a DPA/CUDA mode switch.
This is an independent FU fixture, without GPU/SimX integration.

The accepted RTL passes 143,486 regression checks. Its arithmetic and instruction
scope are unchanged from the frozen B32 reference. The original DPA baseline
retains its truncation semantics; B32+ uses its shared rounding backend.

- [Selected UCC RTL](../../hw/syn/ucc_reuse/selected_pipe5/design.sv)
- [Five-stage baseline RTL](../../hw/syn/ucc_reuse/baseline_pipe5/design.sv)
- [Complete results, constraints, validation and reproduction](../../hw/syn/ucc_reuse/results/b32plus_sm25_ssg072_1ghz/README.md)
