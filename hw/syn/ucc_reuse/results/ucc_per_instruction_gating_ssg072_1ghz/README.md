# Current UCC: per-instruction gating without fixed-run detectors

All fifteen FMA/MUL/EX2 run-history registers are removed. Exact constant propagation also removes redundant control and bypasses always-enabled child gates: **128 cells removed, including 28 ICGs**. Arithmetic state and pipeline locations remain unchanged. Existing per-stage valid/opcode enables remain active; the design never waits for five equal instructions to authorize these enables. See [GATING.md](GATING.md).

| Metric | Result |
|---|---:|
| Cell area | **45,651.186 µm²** |
| CUDA dynamic overhead | **+38.238130%** |
| DPA/CUDA setup WNS | **0.0 / 0.0 ps** |
| Clock-gating setup slack, DPA/CUDA | 0.0 / 1.1 ps |
| TNS, violating paths and DRVs | 0 |
| Cells / FFs / ICGs | 51,142 / 4,501 / 142 |

Functional replay and timing pass. **The current version does not meet the former <20% CUDA energy target.** The historical +19.40% result depends on the removed mechanism and does not describe this version. DPA modes are covered by the mixed functional replay; DPA energy has not been remeasured for this revision.

| Operation | Baseline pJ/op | Previous UCC pJ/op | Current UCC pJ/op | Current leakage mW |
|---|---:|---:|---:|---:|
| fma32 | 5.585850 | 6.647630 | 7.530630 | 9.69544 |
| add32 | 0.884434 | 1.014158 | 0.996990 | 9.50156 |
| mul32 | 3.446001 | 3.481676 | 4.725380 | 9.65818 |
| sfu_ex2 | 4.654456 | 6.253480 | 6.889320 | 9.68785 |

The fixed-four energy sum rises from 17.396944 to 20.142320 pJ, while cell area falls by 131.418 µm². Removing a capture-suppression mechanism restores clock activity even when the data register value remains constant. Per-instruction unused-bank gating is already present; replacing these constant captures requires further bank-specific constant bypass/storage optimization, not merely shifting the same opcode decoder by one cycle. No such unmeasured saving is claimed here.

`UCC_EXPECTED_CELLS=51142`, `UCC_EXPECTED_ICGS=142`. This mapping was re-imported without synthesis, resizing or retiming. All result bytes, gate replay and power traces correspond to the new mapping.
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
python3 hw/syn/ucc_reuse/check_snapshot.py hw/syn/ucc_reuse/results/ucc_per_instruction_gating_ssg072_1ghz
```

To replay with Xcelium and locally installed PDK models (the recorded paths work on the original host):

```bash
python3 hw/syn/ucc_reuse/check_snapshot.py hw/syn/ucc_reuse/results/ucc_per_instruction_gating_ssg072_1ghz \
  --replay-out build_ucc_snapshot_replay --xrun /path/to/xrun
```

Supply three `--cell-model /path/to/model.v` arguments to use relocated SVT/HVT/LVT models. Set the license environment normally. The replay writes only to its new output directory.

For read-only STA, copy `timing/{timing.tcl,flow.tcl,mmmc.tcl,dpa.sdc,cuda.sdc,reference/}` into a new run directory and copy `implementation/mapped.v` there as `input.v`. Set `UCC_RUN_DIR`, `UCC_EXPECTED_CELLS` and `UCC_EXPECTED_ICGS` to the values below; launch Genus 25.1 with `-batch -files timing.tcl`. Library configuration paths refer to the original host and must be adjusted for another installation. This rechecks the mapped netlist; it is not RTL synthesis.

Conditions: SSG 0.72 V /125°C, 1 GHz, input/output delay 300 ps each, uncertainty 50 ps, max transition 100 ps, max fanout 32, BUFFD4 input drive and 5 fF output load, LEF/QRC. Retiming is off. FP32/DPA latency is five cycles, SFU six, ADD two and MUL four. Homogeneous II=1; mixed issue uses the recorded dispatcher reservations and mode/format switches drain.

Dynamic energy is Joules internal + switching from checked zero-delay gate VCDs, excluding leakage. Baseline is separate DPA16 + FP32 + INT32 + SFU: active-unit dynamic plus measured idle dynamic of the other units. The four-stream ratio is sum(UCC energy)/sum(baseline energy), with equal operation counts, not an average of percentages. There are 100 warmup issues followed by 1,000 measured issues per stream. These fixed-opcode measurements are not an arbitrary mixed-opcode energy estimate and do not include post-route/SPEF/CTS/glitch energy.
