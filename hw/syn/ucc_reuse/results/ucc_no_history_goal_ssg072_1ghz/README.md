# No-history UCC: completed area/energy checkpoint

Measured mapped implementation: **45,474.786 µm²**,
CUDA dynamic-energy overhead **18.980269%**.
All fourteen DPA streams pass the stricter +5% requirement, with energy
**18.38–28.59% below** the frozen separate baseline.

TSMC N28 SSG 0.72 V /125°C, Genus 25.1, LEF/QRC wire model, 1 GHz,
300 ps input/output delays, 50 ps uncertainty, 100 ps max transition,
max fanout 32, BUFFD4 input drive and 5 fF output load. Ungroup both,
clock gating enabled, retiming disabled. Both DPA/CUDA setup views and
all transition/fanout/capacitance rules pass. Data WNS is 0.0 ps at report
precision, with zero violating paths; clock-enable WNS is +0.5/+0.1 ps.

| Operation | Dynamic pJ/op | Leakage mW |
|---|---:|---:|
| fma32 | 6.685170 | 9.56483 |
| add32 | 0.858977 | 9.36274 |
| mul32 | 3.728970 | 9.51291 |
| sfu_ex2 | 6.063190 | 9.54228 |

CUDA comparison uses equal operation counts for FMA32, ADD32, MUL32 and
fixed EX2, and the ratio of their energy sums. UCC sum is
**17.336307 pJ**, baseline sum **14.57074112 pJ**.
The baseline includes the active separate block and measured idle dynamic
power of the other blocks. This is an aggregate target, not a requirement
that every individual scalar instruction is within 20%. Leakage is separate.
The SFU oracle retains the previously selected baseline truncation policy.

No consecutive-opcode/run detector remains. ADD/SUB latency is two cycles,
integer multiply four, normal/FP32/DPA five and SFU six; homogeneous II=1.
Mixed dispatch uses the existing fixed reservations; CUDA/tensor and tensor
format transitions drain. Numerical semantics and the frozen vectors have
not changed in this optimization. All 144,656 mixed checks,
sixteen hot-MUL resets, and 14,336 checks covering
2,560 reset-entry cases pass.

`implementation/mapped.v` is the optimized implementation. `implementation/native_reference.sv`
is the frozen functional reference, **not** a native-SV implementation of
the selected mapping optimizations. Standard Genus combinational remapping
preserves the original 4,496 FF and 153 ICG inventories and clock connections.
It is supported by fresh functional regressions; no complete formal remap
equivalence is claimed. The subsequent eleven master changes and fifteen
unary-cell insertions have independent actual-Liberty/whole-graph identity.

Joules uses fresh checked zero-delay gate VCDs, 100 warmup and 1,000 measured
operations per stream. Dynamic energy is internal plus switching. This is
a synthesis-level comparison, without postroute/CTS/SPEF or delay-glitch
power claims. Library models are not copied into this archive; manifests
record their original paths and hashes. Reports and manifests identify the
exact source runs and reproduction scripts in the workspace.

Mapped SHA-256: `795547913478148b7ab047464cfad79d96323e793cf111626b02b1be1383ece6`.
Original checkpoint: `/data2/jwang710/UCC_FU/rta_vortex_shwet_reuse/build_ucc_shared_gating/no_history_full_checkpoint_goal_45475_20261117.json`.

## Recheck and reproduce after cleanup

From the repository root (configure the Cadence license environment normally):

```bash
python3 hw/syn/ucc_reuse/check_snapshot.py hw/syn/ucc_reuse/results/ucc_no_history_goal_ssg072_1ghz

python3 hw/syn/ucc_reuse/check_snapshot.py hw/syn/ucc_reuse/results/ucc_no_history_goal_ssg072_1ghz \
  --replay-out build_ucc_mixed_replay --xrun /path/to/xrun

python3 hw/syn/ucc_reuse/replay_snapshot.py hw/syn/ucc_reuse/results/ucc_no_history_goal_ssg072_1ghz \
  --timing --out build_ucc_sta_replay --genus /path/to/genus

python3 hw/syn/ucc_reuse/replay_snapshot.py hw/syn/ucc_reuse/results/ucc_no_history_goal_ssg072_1ghz \
  --operation fma32 --out build_ucc_fma_power_replay \
  --xrun /path/to/xrun --joules /path/to/joules
```

`power/streams.json` lists all nineteen streams: the four scalar streams,
idle, and fourteen DPA streams. Power replay regenerates the waveform from
the archived bench and vectors before running the original Joules deck.
STA imports the measured mapping without optimization. Neither entry point
needs superseded build directories. External PDK/model, LEF/QRC and tool
paths must be relocated for another host. No private PDK contents are included.

`source_archive.json` records byte-exact provenance; large text reports and
vectors are gzip-compressed. Absolute paths in original provenance JSON are
historical source locations, not portable dependencies. Following cleanup,
use these package check/replay commands instead of historical build-tree
scripts that recursively audit deleted experiments. Raw waveform files are
regenerable; they are not part of the Git snapshot.

The baseline energy manifests and final design-rule audit summaries are
under `baseline/`. The fixed comparison denominator and all fourteen DPA
limits are recorded in `provenance/contract.json`. Earlier published snapshots
remain in Git for historical comparison. The unrelated generic `ucc_lane.sv`
working tree is not the selected mapped implementation.
