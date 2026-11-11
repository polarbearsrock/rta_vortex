# B32+ UCC synthesis snapshot

The selected no-FP64 implementation is
[`selected_pipe5/design.sv`](selected_pipe5/design.sv), top `ucc_b32_pipe5`.
It has five-cycle ordinary operations and six-cycle SFU operations, with
homogeneous II=1 and fixed dispatcher reservations.

The matched five-stage DPA16 is
[`baseline_pipe5/design.sv`](baseline_pipe5/design.sv), top
`ucc_dpa16_baseline`, parameter `DpaStages=5`.

At N28 SSG 0.72 V / 125°C, 1 GHz, their final cell areas are
**46,711.098 / 39,050.802 µm²**, respectively: **19.62% UCC overhead**.
Both pass required setup views with retiming disabled.

Start with the [results and reproduction instructions](results/b32plus_sm25_ssg072_1ghz/README.md).
These are standalone FU fixtures; compiling `hw/rtl/ucc/ucc_lane.sv` does
not select this generated pipeline snapshot.
