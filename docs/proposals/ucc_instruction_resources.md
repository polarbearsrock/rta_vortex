# Instruction and physical resource map

This is a research unit interface, not an NVIDIA instruction encoding. Tensor
mode and scalar mode are exclusive. Opcode values below describe the current
scalar RTL. Intermediate synthesis variants are recorded separately from
functional regression results.

The [exact-FMA follow-up](ucc_segmented_fma.md) preserves this instruction list
and adds optional multiplier-compressor reuse and narrow normalization. Its
resource/area table records those configurations separately from the original
anchored exact datapath described here.

| Instructions / opcode | Arithmetic normally required | Actual TFR resource and current reuse | Incremental logic / status |
|---|---|---|---|
| FMA/MUL/ADD/SUB, 00–03 | 24x24 product, exponent alignment, signed accumulation, normalization, rounding, exceptional cases | Nine of sixteen f16-bank 11-bit multipliers; shared CSA/final adders and rounder | Selected exact version anchors the product in an 80-bit accumulator, aligns only C and uses shared-adder directed rounding when C dominates; four rounding modes and flags |
| Native approximate FMA/MUL/ADD/SUB | Nine 8x8 digit products with different binary weights | Original exponent maximum, lane alignment, 32-bit accumulation, LZD and RNE/FTZ packing as well as multiplier bank | `VX_ucc_bf16x9_comb`; only operand/exponent routing, scalar decoding and special cases; 185,536 scalar and 30,000 DPA cases passed; 3.27% mapped-area overhead on the corrected DPA baseline |
| FP NEG/ABS, 04–05 | Sign bit manipulation | Output bypass | Payload-preserving sign operations, no arithmetic unit |
| FP EQ/NE/LT/LE/GT/GE, 08–0d | NaN/zero classification and exact ordering | Operand bit-pattern subtraction through existing final adder; sign-order correction | Never uses rounded FP subtraction; quiet predicates set NV for sNaN |
| FP MIN/MAX, 0e–0f | Ordering and result mux | Same subtraction/order logic | Number-preferred NaN policy; both NaNs yield canonical NaN; MIN(-0,+0)=-0 and MAX(-0,+0)=+0 |
| IADD/ISUB/INEG/IABS, 10–13 | Carry-propagate add/subtract | Existing CSA and final adder raw complement result | Operand inversion and correction bits reuse existing negative-term popcount; 32-bit wrap, including ABS(INT_MIN) |
| MUL.LO, MUL.HI.U, MUL.HI.S, MUL.HI.SU, 14–17 | Full 32x32 product and signed correction | Nine 11-bit products with 11+11+10 decomposition, same CSA/final adder | Fixed wiring for partial-product weights; signed corrections enter spare CSA inputs; no FP rounding |
| Signed integer comparisons, 18–1d; unsigned, 28–2d | Subtract flags and predicate | Raw shared-adder result and operand signs | EQ/NE/LT/LE/GT/GE in that order; result 0/1 and predicate |
| MIN/MAX.S, 1e–1f; MIN/MAX.U, 2e–2f | Compare and mux | Same subtract flags | Result mux; predicate reports less-than |
| SHL/SHR.U/SHR.S/CLZ, 30–33 | Barrel shift and leading-zero detection | Shared normalizer bidirectional shifter and LZD | Operand/shift-control mux; shift count is B[4:0], CLZ(0)=32 |
| I32/U32→F32, 40–41 | Absolute value, LZD, normalize, round | Shared accumulator sign/magnitude output and FP normalizer/rounder | Exponent base zero and format controls |
| F32→I32/U32, 42–43 | Exponent-controlled shift, integer rounding, sign and range handling | Exact: FMA C aligner; native: auxiliary aligner selected by whole-core area; shared CSA/final adder for rounding and sign | Saturate on out-of-range/Inf, NaN→0, NV only on invalid; valid inexact conversion sets NX |
| AND/OR/XOR/NOT/LOP3/SEL/MOV, 50–56 | Boolean gates and muxes | Independent small Boolean unit | LOP3 index={A bit,B bit,C bit}; 8-bit immediate is truth table; SEL uses C[0] |
| EX2, 60 | Range reduction, coefficient ROM, square and polynomial, pack | Exact C aligner or native auxiliary aligner; same 16-slice multiplier bank, final CSA and rounder | Regular polynomial uses 13 slices (3 square, 6 linear, 4 quadratic); compact uses 8 (1, 6, 1); dependent products occupy different slices for II=1 |
| Natural EXP, 61 | Fixed-point x*log2(e) range transform plus EX2 polynomial | Regular option: fixed coefficient network; compact: six freed 11-bit slices plus three small constant-select terms; shared polynomial/reduction/normalization | Full native UCC: 38,436.930 um2 regular or 38,246.670 um2 compact; high-precision samples reached 1 or 2 ULP respectively; original FP8-slice range sharing cost more |
| BFE/BFI/SHF, FP16/BF16 conversions | Masking/funnel shifts or narrow-format packing | Candidate shifter/rounder reuse | Excluded from the initial RTL; extra format/width control would need a separate cost study |
| RCP/RSQRT/LG2/SIN/COS/TANH | Range reduction and approximation | Existing Vortex MUFU tables are available for investigation | Not yet supported by this UCC |
| Integer DIV/REM and FP DIV/SQRT | Iterative sequences | Compiler/software lowering using primitives | No dedicated units |

Scalar opcodes 00/01/02/03 compute A*B+C, A*B, A+B and A-B respectively;
C is ignored by MUL/ADD/SUB. SEL chooses A when C[0] is one, otherwise B.
EX2/EXP use fixed RNE packing and expose zero status flags; they do not
implement IEEE transcendental exception semantics.

Rounding modes are 0=RNE, 1=RTZ, 2=RDN, 3=RUP. The exact scalar FMA
path implements gradual underflow and flags NV/DZ/OF/UF/NX (DZ remains zero
for these primitives). The native BF16x9 experiment deliberately retains
the baseline's fixed RNE/FTZ output policy and reports only NV. Tensor mode
retains its original bounded alignment policy and does not expose FP flags.
These numerical policies must remain distinct in comparisons. Integer/FP
conversion and FP-ordering instructions keep their specified policies even
when the FMA arithmetic uses the approximate native path.

The V3 regression passed 185,536 FP operations, 101,536 integer operations,
307,456 shift/conversion/FP-order operations and mixed-mode DPA comparisons.
The V4 EX2/Boolean regression extended auxiliary checks to 508,041 cases.
On 100,585 EX2 inputs the maximum observed difference was 1 ULP against a
binary64 exponential rounded to binary32. This is a measured sample result,
not a correctly-rounded claim or an exhaustive error bound.

All current UCC views are combinational. EX2 uses different physical slices
for its dependent square and quadratic operations; there is no iterative
reuse that would force II>1. The elastic streaming wrapper passed stalls, resets, tags and 1,000
consecutive acceptances; it has one output register. Pipeline stage balancing
remains outstanding. A mapped 5 ns path is not
evidence that a four- or five-stage implementation already meets 1 GHz.

Independent DPA verification now uses integer arithmetic with explicit two-term
FP8/four-term FP4 grouping, local truncation, 26-bit global alignment and final
RNE/FTZ packing. MXFP4 scales are E8M0; NVFP4 scales use nonnegative E4M3
with zero/subnormal support and NaN propagation. NVFP4 scale sign bits are
reserved/ignored at this boundary; global FP32 scale application stays outside
the core. Baseline scale and masked-FP8 corrections passed 88,944 independent cases,
15,992 pipeline comparisons and 7,168 mapped gate checks.
