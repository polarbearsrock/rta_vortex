# Unified DPA16 mapped-area results

This report preserves the original completed comparison. The subsequent
[exact-FMA multiplier-reconfiguration experiment](ucc_segmented_fma.md)
records additional candidates and their separately verified measurements.

The [EXP coefficient sharing experiment](ucc_coeff_sharing.md) separately
compares standalone 1/2/4/8-port banks without reducing lookup throughput;
its areas are not substituted into the full-UCC numbers below.

The smallest measured full native-FP UCC occupies **38,246.670 um2**;
the selected exact-FP UCC occupies **39,809.826 um2**. Relative to the measured
DPA + INT + FPU + EX2/EXP sum, they save **11.16%** and **7.52%** respectively.
The minimum native configuration trades sampled EXP accuracy from 1 ULP to
2 ULP; preserving the regular polynomial costs another **190.260 um2**.
These are minima among the measured candidates, not a global-optimality claim.

## Conditions and validity

All runs use Genus 21.10, TSMC N28 HPC+ TT 0.8 V 25 C RVT/HVT/LVT libraries,
5 ns input-to-output delay, 50 ps input slew, 5 fF output load, high synthesis
effort and ZeroWireload. Listed area is combinational standard-cell area;
sequential area and sequential cell count are zero. The elastic output register
is excluded consistently. This is pre-layout timing, with no routed parasitics,
and does not establish a four/five-stage 1 GHz implementation or sequential Fmax.

All compared DPA views contain the same FP8 mask, MXFP4 and NVFP4 numerical
corrections. ROM coefficients are explicitly driven constants. Early undriven-ROM
runs, old DPA arithmetic runs and wrong-time-unit trials are excluded and
quarantined under `build_ucc/invalid_synth_rom_initial`,
`historical_pre_dpa_numeric`, and `invalid_synth_5000ns` respectively.

Each result belongs to its immutable preprocessed `design.sv` and hash in
`build_ucc/ucc_synth/<top>/manifest.json`. RTL tests identify their own source
revision. Later inactive-branch/default-output refactoring is not retroactively
assigned a new PPA measurement; mapped checks verify the frozen netlists.

## Selected implementations and independent units

| View | Cell area (um2) | Longest path (ns) |
|---|---:|---:|
| Baseline DPA16 | 33,566.778 | 4.525 |
| DPA + native BF16x9 FP32 only | 34,665.876 | 4.674 |
| DPA + anchored exact FP32 only | 37,823.310 | 5.000 |
| Full native UCC, regular EX2/EXP | 38,436.930 | 5.000 |
| Full native UCC, compact EX2/EXP | 38,246.670 | 5.000 |
| Full exact UCC, anchored/cropped FMA | 39,809.826 | 5.000 |
| Standalone INT | 2,490.138 | 2.390 |
| Standalone FP32 FMA only | 3,594.150 | 5.000 |
| Standalone full FPU | 3,637.368 | 5.000 |
| Standalone EX2 only | 2,816.604 | 4.996 |
| Standalone EX2 + natural EXP | 3,354.750 | 5.000 |
| Original Vortex seven-operation MUFU | 4,844.952 | 4.942 |

BF16x9 FP32 alone costs **1,099.098 um2 (3.27%)** over DPA. This supports the
low-overhead reuse hypothesis: original multipliers, exponent maximum, lane
alignment, accumulation and RNE/FTZ packing are reused. It is not IEEE FMA:
subnormal behavior, flags, directed rounding and cancellation accuracy differ.
The compact EXP's 2-ULP sampled error is a separate property; it is not an
accuracy bound on approximate FP32 FMA.

Exact anchored FMA alone costs **4,256.532 um2 (12.68%)** over DPA. It uses
nine 11+11+2 weighted products in the existing CSA, only one C alignment path,
and shared final adders. The full exact unit is **1,372.896 um2 (3.57%)** larger
than full native with regular polynomial. FMA-only sharing still costs
**662.382 um2** more than DPA plus the conventional standalone FMA
(37,160.928 um2); the complete instruction set makes sharing more favorable.
Exact scalar arithmetic provides
RNE/RTZ/RDN/RUP, gradual underflow, canonical NaN and documented exception flags;
EXP remains approximate.

## Single-unit and aggregate comparisons

V5 is the sum of independently synthesized DPA, INT, full FPU and two-function
EX2/EXP blocks: **43,049.034 um2**. No combined wrapper is needed for this sum;
all four use the same constraints and libraries.

| Full UCC option | UCC area (um2) | Overhead over DPA | Saving versus V5 |
|---|---:|---:|---:|
| Native FP, regular polynomial | 38,436.930 | 14.51% | 10.71% |
| Native FP, compact polynomial | 38,246.670 | 13.94% | 11.16% |
| Exact FP, anchored/cropped | 39,809.826 | 18.60% | 7.52% |

The exact UCC and standalone FPU use matching FP32 arithmetic policies. Native
UCC has weaker FP semantics. Polynomial precisions differ across EXP choices;
all errors are labeled and measured separately. Separate units can operate
concurrently, while each UCC chooses one instruction category per issue slot.

The requested model, **64DPA + 16INT + 32FMA-only + 4EX2/EXP**, totals
**2,316,547.800 um2**. Replacing FMA-only with full FPUs totals
**2,317,930.776 um2**. Both denominators are recorded in the JSON report.

| Uniform UCC aggregate | Cell area (um2) | Increase over requested mix |
|---|---:|---:|
| 64 × Native FP, regular polynomial | 2,459,963.520 | 6.19% |
| 64 × Native FP, compact polynomial | 2,447,786.880 | 5.67% |
| 64 × Exact FP, anchored/cropped | 2,547,828.864 | 9.98% |

Thus the single-unit saving does **not** imply an aggregate saving for this
mix. Uniform UCC provides up to 64 INT, FMA or EXP issue slots, while the separate
model has 16, 32 and 4 respectively; shared total issue capacity is 64 versus
independent categories. Operand delivery, scheduling, registers, interconnect
and pipeline balancing are excluded. The counts are the user's modeling
assumption, not a disclosure of NVIDIA circuitry.

Original Vortex MUFU supports RCP/RSQRT/EX2/LG2/SINPI/COSPI/TANH and lacks direct
natural EXP. Its **4,844.952 um2** is context, not a silent replacement for the
matched EXP/EX2 comparator. Seven-stage/combinational equivalence passed;
independent accuracy for all seven operations has not been established.

## Instruction-group increments

This chain holds the exact CSA-first FMA and direct-normalization architecture
constant. Differences include synthesis mapping and timing repair, not only
isolated opcode logic. V4 uses the fixed log2(e) range transform.

| Variant / added function group | Area (um2) | Increment (um2) |
|---|---:|---:|
| V0: corrected DPA | 33,566.778 | — |
| V1: exact CSA-first FMA | 39,095.658 | 5,528.880 |
| V2: + integer arithmetic | 39,385.080 | 289.422 |
| V3: + shifts, conversions, FP ordering | 39,826.458 | 441.378 |
| V4: + Boolean, EX2/EXP | 40,997.124 | 1,170.666 |

Anchoring and cropping then reduce full V4 from **40,997.124** to
**39,809.826 um2**, a further **1,187.298 um2**. The separate native-FP-only
measurement isolates its 3.27% extension. Boolean and EXP are grouped in the
V3→V4 result; no fabricated per-opcode number is inferred from flattened gates.

## What actually reduced area

| Experiment, before → after | Area change (um2) | Decision |
|---|---:|---|
| Native EXP: 33 shared range terms → fixed constant transform, paired alignment | -5,205.690 | Keep as regular-polynomial option |
| Fixed-transform native: paired → unpaired auxiliary alignment | -1,455.174 | Select unpaired |
| Native regular → compact polynomial and shared range, unpaired | -190.260 | Offer sampled 2-ULP option |
| Exact fixed-transform: CSA-first → anchored | -1,052.226 | Select anchored |
| Anchored: full slice output → statically cropped scalar partial products | -135.072 | Select cropping |
| W65 native EX2: unpaired → paired alignment | +446.418 | Reject for area |
| Native original EXP: direct normalization | +163.044 | Reject for native area |
| Above + one-hot routing, relative to original | +129.906 | Reject for native area |

The fixed coefficient network is only an input range transform, not a separate
general FP32/INT32 multiplier. Polynomial multiplication, CSA, final adder and
normalization remain shared. The compact option instead frees multiplier slices
for the transform. Unpaired native alignment adds a small auxiliary path because
its measured routing cost is lower than coupling the DPA lane shifters. Exact
mode shares its C aligner with conversions and EXP. Integer shifts continue to
share normalization in both versions.

A local partitionable-shifter benchmark is **816.354 um2**, versus
**2,531.592 um2** for separate shifters (67.75% smaller). Its local win did not
predict the full-core paired-alignment result. The full-core measurements take
precedence. Earlier valid candidates remain in the machine-readable report,
including native/full exact original EXP at 45,097.794 / 48,924.288 um2.

## Timing, power and physical attribution

Selected critical-path endpoints are:

| View | Start | End | Reported delay / slack |
|---|---|---|---|
| DPA | a[2][6] | result[0] | 4.525 ns / 475 ps |
| Native regular EXP | a[5] | result[22] | 5.000 ns / 0 ps |
| Native compact EXP | op[6] | result[28] | 5.000 ns / 0 ps |
| Exact anchored/cropped | scale_b[1][6] | result[5] | 5.000 ns / 0 ps |

There is no internal iteration. The elastic wrapper has one-cycle interface
latency and demonstrated 1,000 consecutive acceptances with mixed operations,
flags, tags and predicates. II=1 applies at a clock period sufficient for the
whole combinational core plus register overhead; 1 GHz remains unmeasured.
The original four-stage tensor baseline is separately tested.

The table below counts only exclusive retained hierarchy, never a parent plus
its children. Flattening merges mux, shifter, normalization and multiplier
logic; these are attributable **subsets**, not complete functional-area costs.
Missing shifter/rounder categories do not mean zero area. The unattributed
residual is shown rather than assigned arbitrarily.

| Retained category (um2) | DPA | Native regular | Native compact | Exact |
|---|---:|---:|---:|---:|
| Retained multiplier cells | 3,502.296 | 3,633.336 | 3,680.082 | 3,171.042 |
| Retained reduction / adder cells | 256.536 | 1,955.646 | 2,158.758 | 2,065.140 |
| Retained coefficient ROM | 0.000 | 334.656 | 312.984 | 326.214 |
| Retained exponent ordering | 1,373.148 | 1,461.978 | 1,432.494 | 0.000 |
| Unattributed tensor preparation | 24,549.210 | 23,316.678 | 23,295.636 | 25,310.628 |
| Unattributed other, including mux/shift/round | 3,885.588 | 7,734.636 | 7,366.716 | 8,936.802 |

`ucc_area_breakdown.json` includes the full hierarchy and checks that exclusive
areas sum to each total. `ucc_measurements.json` also includes vectorless leakage
and dynamic power from default Genus activity. These are not workload-based
power or energy estimates. There is no post-route area, extracted timing or
measured power result.

## Verification and next optimization priorities

The independent DPA reference passed 88,944 cases. Exact FMA references were
cross-checked against Berkeley SoftFloat, including 334,656 distant-addend
rounding cases. Full instruction regressions cover scalar arithmetic, integer,
conversion, Boolean, EXP and tensor mode switching. Each selected mapped full
UCC passed 23,008 independent-reference gate cases using installed TSMC Verilog
models. Each selected full RTL configuration passed 928,532 standard checks. The
selected exact implementation additionally passed 334,656 distant-addend and
186,240 subnormal cases through the full UCC; every selected configuration
passed 147,516 high-precision EXP/EX2 boundary vectors. Detailed counts,
source/vector hashes and protocol results are in
`ucc_verification.json` and the per-test manifests. Gate simulations are
zero-delay; Genus reports supply timing. Generated ROM identifiers too long for
Xcelium are reversibly renamed, with both hashes recorded.

The regular EXP polynomial showed at most 1 ULP and compact at most 2 ULP on
73,757 EX2 and 73,759 natural EXP high-precision samples; this is not an
exhaustive bound. On 12 synthetic softmax rows (18,944 entries), the regular and compact
EXP variants showed maximum absolute probability errors below 4.6e-9 and
7.64e-9 respectively. This isolates EXP error with binary64 sum/division; it is
not a full attention benchmark. Approximate BF16x9 cancellation remains
a numerical limitation. Unsupported optional bit fields/narrow conversions and
other MUFU operations are listed in the architecture and instruction documents.

Further work should prioritize mapping/routing of the FP4 scale path, then a
measured four/five-stage 1 GHz partition and physical implementation. For the
aggregate model, heterogeneous allocation of full EXP/exact capabilities may
save more area than placing every feature in all 64 units, but changes the
uniform-unit premise. None of these potential savings is included above.
