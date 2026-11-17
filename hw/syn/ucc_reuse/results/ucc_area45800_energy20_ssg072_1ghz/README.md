# Historical UCC checkpoint with run-history gating

This is the historical implementation that met the earlier area/energy goal. The user subsequently requested removal of its five-issue opcode-run detectors; use the [new per-instruction snapshot](../ucc_per_instruction_gating_ssg072_1ghz/README.md) for current work.

| Metric | Result |
|---|---:|
| Cell area | 45,782.604 µm² |
| Equal-count CUDA dynamic overhead | +19.396425% |
| DPA/CUDA setup WNS | 0.0 / 0.0 ps at 0.1 ps report resolution |
| Setup, ICG setup and DRV violations | 0 |
| Cells / FFs / ICGs | 51,270 / 4,516 / 170 |
| DPA dynamic reduction vs full separate baseline | 16.59%–27.05%, all 14 streams measured |

The optional detector recognizes FMA32 (0x60), unsigned MUL.LO (0x20) and EX2 (0x7a). After five prior matching valid CUDA issues, the current issue must also match before it suppresses proved constant captures. It has fifteen history FFs and originally split nineteen data banks totaling 256 bits. Later isolation also reused these events. Opcode changes, bubbles, reset or DPA mode remove the additional skip condition. This explains why the old savings favor homogeneous streams. The `sticky4` source name instead denotes four-bit OR groups for rounding sticky storage; it is unrelated to run detection.

`UCC_EXPECTED_CELLS=51270`, `UCC_EXPECTED_ICGS=170`. Exact measurements are in `provenance/scalar_comparison.json` and `provenance/dpa_result.json`; the original audit records 12,529 source/evidence hashes.

## Contents and checks

- `implementation/mapped.v`: exact measured N28 mapping, top `ucc_b32_pipe5`.
- `implementation/native_reference.sv`: prior synthesizable numerical/pipeline reference. Subsequent mapped edits are not all represented here; resynthesizing it alone does not reproduce this result.
- `validation/`: unchanged mixed-operation bench, oracle, compressed vectors and original passing log; 144,656 comparisons, 200 drained mode changes and sixteen active-MUL hot resets.
- `timing/`: raw two-view reports, ICG checks, DRVs, constraints and the read-only Genus import flow. Reports over 1 MB are gzip-compressed.
- `power/`: Joules reports, annotation, input vectors and scripts for each measured operation. Raw VCDs remain in the original workspace referenced by the source manifests.
- `provenance/`: original measurement metadata and source-transform snapshots. Absolute paths in historical records identify the original workspace; they are not portable build paths. Transform scripts retain their original imports and are archived for inspection, not advertised as a standalone regeneration flow.

PDK Liberty, LEF, QRC and cell model contents are external dependencies and are not vendored. The mapped design instantiates their cell names. `validation/cell_models.json` records the cell models used in the original simulation.

Run the byte/hash and result-consistency check from the repository root:

```bash
python3 hw/syn/ucc_reuse/check_snapshot.py hw/syn/ucc_reuse/results/ucc_area45800_energy20_ssg072_1ghz
```

To replay with Xcelium and locally installed PDK models (the recorded paths work on the original host):

```bash
python3 hw/syn/ucc_reuse/check_snapshot.py hw/syn/ucc_reuse/results/ucc_area45800_energy20_ssg072_1ghz \
  --replay-out build_ucc_snapshot_replay --xrun /path/to/xrun
```

Supply three `--cell-model /path/to/model.v` arguments to use relocated SVT/HVT/LVT models. Set the license environment normally. The replay writes only to its new output directory.

For read-only STA, copy `timing/{timing.tcl,flow.tcl,mmmc.tcl,dpa.sdc,cuda.sdc,reference/}` into a new run directory and copy `implementation/mapped.v` there as `input.v`. Set `UCC_RUN_DIR`, `UCC_EXPECTED_CELLS` and `UCC_EXPECTED_ICGS` to the values below; launch Genus 25.1 with `-batch -files timing.tcl`. Library configuration paths refer to the original host and must be adjusted for another installation. This rechecks the mapped netlist; it is not RTL synthesis.

Conditions: SSG 0.72 V /125°C, 1 GHz, input/output delay 300 ps each, uncertainty 50 ps, max transition 100 ps, max fanout 32, BUFFD4 input drive and 5 fF output load, LEF/QRC. Retiming is off. FP32/DPA latency is five cycles, SFU six, ADD two and MUL four. Homogeneous II=1; mixed issue uses the recorded dispatcher reservations and mode/format switches drain.

Dynamic energy is Joules internal + switching from checked zero-delay gate VCDs, excluding leakage. Baseline is separate DPA16 + FP32 + INT32 + SFU: active-unit dynamic plus measured idle dynamic of the other units. The four-stream ratio is sum(UCC energy)/sum(baseline energy), with equal operation counts, not an average of percentages. There are 100 warmup issues followed by 1,000 measured issues per stream. These fixed-opcode measurements are not an arbitrary mixed-opcode energy estimate and do not include post-route/SPEF/CTS/glitch energy.
