# EXP coefficient sharing across PEs without throughput loss

The smallest measured coefficient-bank area per PE is the four-port `plane`
organization, **295.533 um2/PE**. However, the mapped netlists contain **no dynamic
lookup cells shared between PEs**. The group saves only **0.945 um2/PE (0.319%)**
relative to separately mapped one-port plane lookups. The useful improvement is
the lookup encoding itself: one-port plane logic is **9.88%** smaller than the
original one-port ROM implementation. Keep selection local to each PE; four PEs
can be an RTL/synthesis group, but there is no measured reason to build a central
shared lookup unit or extend the group to eight PEs.

The question is whether grouping several UCC PEs around the EXP/EX2 coefficient
table reduces area while preserving one independent lookup per PE per cycle.
The arithmetic datapaths and polynomial coefficients are unchanged. Every PE
retains its own unrestricted six-bit index. There is no arbitration, bank-conflict
stall, time multiplexing, or additional register in any candidate.

## Compared organizations

All three styles are tested with 1, 2, 4 and 8 read ports:

| Style | RTL organization | Purpose |
|---|---|---|
| `replica` | One existing `VX_mufu_rom`, fixed to the EX2 subtable, per PE | Original implementation control |
| `array` | One constant 64-by-72 array with an independent indexed read per PE | Test whether a shared RTL declaration produces physical savings |
| `plane` | Common constant bit planes, independent row decode and masked OR per PE | Compare an explicit decoded multiport organization |

The one-port controls distinguish a better lookup implementation from actual
cross-PE sharing. A group is compared both with the same-size original group and
with the sum of independently mapped one-port banks of the same style.

`VX_ucc_coeff_bank.sv` implements the three organizations. The compact coefficient
package is generated from the existing MUFU ROM's EX2 addresses 256--319; the
runner rejects a mismatch with the canonical constants. Outputs carry the same
32/27/20-bit expanded coefficients consumed by `VX_ucc_ex2_prepare`.
The 72-bit packed words represent 576 bytes of logical data, not a RAM macro.

Because this is a constant combinational function, each independently addressed
read port still needs selection logic. The array and plane styles are shared
logical organizations; their physical sharing must be established by synthesis.
The experiment does not assume that eight ports cost the area of one port.

## Validation and measurement

The RTL test checks all three styles and all four group sizes simultaneously.
Its vectors include every broadcast index, distinct simultaneous indices,
every pair of address values on every pair of eight PE inputs, and random input
groups. Expected coefficients come from the original table decoder rather than
from the generated compact table. Mapped simulations use installed TSMC cell
models and independent expected values, including broadcast and distinct-index
traffic. A new complete vector is accepted at every test step; all outputs are
checked together.

Each bank is synthesized with the existing Genus 21.10 / TSMC N28 TT 0.8 V
25 C RVT/HVT/LVT setup, 5 ns combinational delay, 50 ps input slew and 5 fF per
output pin. Sequential area is zero. Reports use ZeroWireload, so they do not
quantify the additional physical wire length of centralizing a table.

These measurements isolate the coefficient bank. They must not be subtracted
directly from the earlier full-UCC area: the standalone output loads and
optimization boundaries differ. A candidate must be evaluated within the full
UCC before claiming an end-to-end 5 ns timing or whole-core area improvement.
The original UCC remains unchanged during this comparison.

Reproduce the experiment from the repository root with:

```sh
python3 hw/syn/ucc/coeff_sharing.py all --jobs 3
```

The script configures and runs tools in `build_ucc`, preserves completed frozen
synthesis directories, and generates `ucc_coeff_sharing_measurements.json` in
this directory. Separate `rtl`, `synth`, `gate`, and `report` actions are available.
Source, configuration, vector and netlist hashes link the measurements to their
verification evidence. Partial synthesis directories must be archived before
rerunning; completed results are not overwritten automatically.

## Results

All 12 candidates passed synthesis and mapped verification under matching
constraints. Areas below are standalone coefficient-bank cell areas, including
every independent read port; each output coefficient tuple is 79 bits after
expansion from the packed table word.

| PE/read ports | Style | Group area (um2) | Area per PE (um2) | Delay (ns) |
|---:|---|---:|---:|---:|
| 1 | Original ROM replicas | 328.986 | 328.986 | 0.294 |
| 1 | Shared constant array | 327.852 | 327.852 | 0.300 |
| 1 | Decoded bit planes | 296.478 | 296.478 | 0.271 |
| 2 | Original ROM replicas | 657.972 | 328.986 | 0.291 |
| 2 | Shared constant array | 655.074 | 327.537 | 0.324 |
| 2 | Decoded bit planes | 594.846 | 297.423 | 0.281 |
| 4 | Original ROM replicas | 1,315.440 | 328.860 | 0.288 |
| 4 | Shared constant array | 1,311.156 | 327.789 | 0.322 |
| 4 | Decoded bit planes | **1,182.132** | **295.533** | **0.262** |
| 8 | Original ROM replicas | 2,628.360 | 328.545 | 0.297 |
| 8 | Shared constant array | 2,617.398 | 327.175 | 0.326 |
| 8 | Decoded bit planes | 2,364.768 | 295.596 | 0.276 |

The eight-port plane group costs 0.063 um2/PE more than the four-port group.
Its area is almost exactly twice the four-port group area. The original ROM and
shared-array organizations also scale approximately linearly with read-port
count. There is no table-capacity amortization resembling one SRAM serving all
PEs at the same throughput.

`coeff_cones.py` audits all eight flattened array/plane netlists using cell pin
directions from the installed TSMC Verilog models. Its parsed cell count must
match the synthesis report. Every coefficient output depends only on its own
PE's address. In all eight audited netlists, the number of dynamic cells feeding
outputs of multiple PEs is **zero**. Constants are excluded from this dynamic
sharing count. Thus the small deviations from linear area are mapping/sizing
differences, not a shared address-dependent table circuit.

The four-port plane group saves 10.13% versus four original ROM instances in the
same grouped experiment. Almost all of that saving is already available in the
one-port encoding. Centralizing the group would add physical connectivity that
this ZeroWireload experiment does not price; the sub-1-um2/PE grouping difference
does not establish a post-route area advantage.

The old approximately 326-um2 ROM number came from retained hierarchy inside a
full UCC. The 328.986-um2 control here has explicit standalone output loads and
different optimization boundaries. These are different measurement scopes, not
two contradictory measurements of the same circuit configuration.

## Verification result and integration boundary

- RTL: **118,912 input-vector groups**, **5,351,040 coefficient comparisons**
  across all 12 configurations, zero mismatches.
- Mapped cells: **62,976 input-vector groups**, **214,656 coefficient comparisons**
  across all 12 configurations, zero mismatches.
- Every PE can present a different index simultaneously. Each N-port group
  produces N complete coefficient tuples without arbitration or additional
  latency stages. Address collisions also return all requested copies.
- All standalone bank delays are between **0.262 and 0.326 ns** under the 5 ns
  constraint; this is not a newly measured full-UCC timing result.

The full UCC RTL and its selected defaults are unchanged. The verified bank is
available as `VX_ucc_coeff_bank` with `PORTS=1/2/4/8` and `STYLE=0/1/2`. A future
integration of the plane encoding should first measure one full PE with its
actual coefficient consumers. A cross-PE table interface is not justified by
the current area results. Custom ROM macros, time-multipumped memories, and
workload-dependent address coalescing are outside this standard-cell experiment.

Machine-readable data, source hashes, individual reports and cone audits are in
[ucc_coeff_sharing_measurements.json](ucc_coeff_sharing_measurements.json).
