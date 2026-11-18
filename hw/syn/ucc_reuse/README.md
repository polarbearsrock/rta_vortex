# B32 UCC implementation snapshots

The current no-FP64 implementation is the [qualified no-history snapshot](results/ucc_no_history_goal_ssg072_1ghz/README.md), top `ucc_b32_pipe5`. It has no consecutive-instruction detector. At N28 SSG 0.72 V /125°C, 1 GHz, 300 ps IO and LEF/QRC, cell area is **45,474.786 µm²** and fixed-four CUDA dynamic-energy overhead is **18.980269%**. Setup, clock-enable timing, design rules and all fourteen DPA energy checks pass. Retiming is off. Its check/replay entry points do not depend on superseded build directories.

The earlier [per-instruction gating snapshot](results/ucc_per_instruction_gating_ssg072_1ghz/README.md) removed the original run detectors but measured **45,651.186 µm² / +38.2381%**. It is superseded by the qualified version above.

The [previous qualified snapshot](results/ucc_area45800_energy20_ssg072_1ghz/README.md) achieved **45,782.604 µm² / +19.3964%**, using the now-removed run detectors. Its measurements remain historical evidence and must not be assigned to the current implementation.

For both recent snapshots, `implementation/mapped.v` is the actual measured structural Verilog. `implementation/native_reference.sv` is synthesizable reference RTL; it does not contain every subsequent mapped optimization and cannot reproduce the reported area/energy alone. Do not compile both definitions of `ucc_b32_pipe5` together. These are standalone FU fixtures, not the generic `hw/rtl/ucc/ucc_lane.sv` selection.

The original [fixed-pipeline snapshot and matched DPA baseline](results/b32plus_sm25_ssg072_1ghz/README.md) remain unchanged. The baseline source is [baseline_pipe5/design.sv](baseline_pipe5/design.sv), top `ucc_dpa16_baseline`, `DpaStages=5`.
