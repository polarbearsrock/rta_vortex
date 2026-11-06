# RTA UCC: the Universal CUDA Core PE datapath

Every RTA PE becomes a Universal CUDA Core (UCC) that supports DPA16, INT32,
FP32, FP64 and SFU operations. The datapath starts from an FP64 FMA, and the
other operations are added to it one step at a time. This folder holds that
datapath, now the UCC tile's single FU with one global opcode for all of its
operations; its regression is the unit test `hw/unittest/ucc_lane`. The
sections follow the steps in the order they were built; "The FU" describes the
interface as it is now.

The FU was built in dora-lab (`examples/devices/rta_ucc`, last at 88d6323)
and moved here with its RTL unchanged but for three reworded comments (in
`ucc_dpa16.sv`, `ucc_shift.sv` and `bench/ucc_mul53.sv`); the preprocessed RTL
is identical. The Python modules and tests now find their sources through
`ucc/paths.py` (the `dpa.py` and `sfu.py` docstrings name the new paths).
`verify.py` runs the regression on Vortex's unit-test flow
([Running](#running)) instead of DORA's leaf simulation harness, and takes
over the case-count checks of dora-lab's slow `tests/test_lane.py`, which is
not copied. It adds one case, `ucc_lane_mixed_sfu_breach`, which checks that
`UCC_CHECK_ISSUE` is armed (24 cases in dora-lab, 25 here).
`vectors.py` and `verify.py` have reworded comments, and the two
`PROVENANCE.json` notes are reworded. Unless a sentence names another
repository, the commits this document names are dora-lab's. This copy leaves
out synthesis results. Its sections keep dora-lab's layout: `rtl/` is this
folder, `vendor/` is `vendor/` here, `bench/` is `hw/unittest/ucc_lane/bench`,
the Python modules and `tests/` are in `hw/unittest/ucc_lane/ucc`, and
`vendor/vortex` (Vortex's MUFU) is Vortex's own `hw/rtl/mufu` and
`sw/common/mufu.cpp`.

## The FP64 baseline

The baseline is TransDot's `nv_tc/simt_units/fp64_fma_lane.sv` at commit
`599aaa5a50f97244a40e63ca6d7bd81db1deb383`, unchanged. It is FPnew
`fpnew_fma` in FP64 with three distributed pipeline registers: at the inputs,
after the 163-bit addition, and at the output. It takes one FMA per cycle and
returns each result three cycles later. It issues FMADD with round to nearest
even only; its status flags and handshake outputs are unconnected.

## The multiplier

The FU no longer has this multiplier: its product now comes from DPA-16's
tiles (see [One multiplier](#one-multiplier-the-fmas-product-on-dpa-16s-tiles)).
`bench/ucc_mul53.sv` keeps it as the reference the tiled product was checked
against, and the earlier sections describe the steps that used it.

`ucc_mul53` is the 53×53 significand multiplier with its rows written
out: radix-4 Booth on b, 27 rows plus one operand that holds every row's sign
correction, summed in one carry-save tree and a 106-bit carry-propagate
adder. Rows 0–13 multiply `a_lo_i` and rows 14–26 multiply `a_hi_i`:

- **FP64:** both inputs get the same a, so the product is a × b.
- **2 × FP32:** the operands are packed as {x1 at bits 52–29, five zero bits,
  x0 at bits 23–0}, `a_lo_i` keeps only a0 and `a_hi_i` only a1. Bits 28–24 of
  b are zero, so rows 0–13 multiply by b0 and rows 14–26 by b1 · 2^29, and the
  product holds a0 · b0 in bits 47–0 and a1 · b1 in bits 105–58.
- **SFU:** with `b_signed_i` set, b is two's complement (the top Booth digit
  sees its sign). With b = a2 · 2^28 + a1, `a_lo_i` = xl · 2^28 and `a_hi_i` =
  xl², the product is 2^28 (a1 · xl + a2 · xl²), the MUFU's two products in one
  sum.
- **INT32:** with `a_signed_i` set, a is two's complement too (a row's sign
  flips when its multiplicand is negative). 32-bit integers at bits 52–21 of a
  and b give their exact product, signed or not, at bits 105–42.

## Two FP32 FMAs per cycle

This step was undone on 2026-11-05: the FU now runs one FP32 operation per
cycle ([One operation per opcode](#one-operation-per-opcode)). This section
describes the two-lane design as it was built.

With an FP32 FMA opcode, `ucc_lane` runs two FP32 FMAs per cycle instead of one
FP64 FMA, which matches B200's 2:1 FP32:FP64 rate. Each 64-bit operand and the
result then hold {lane 1 in bits 63–32, lane 0 in bits 31–0}. Each lane's
result is bit for bit that of FPnew `fpnew_fma` in FP32, three cycles later,
and the mode can change every cycle. The split follows Huang et al., ARITH-18
2007.

The lanes run in the FP64 FMA's datapath (`rtl/ucc_fma.sv`):

- **Multiplier.** Lane 0's significands go to bits 23–0 of both multiplier
  operands and lane 1's to bits 52–29. After the input register, rows 0–13
  see only lane 0's bits of a and rows 14–26 only lane 1's, so the product
  holds a0 · b0 in bits 47–0 and a1 · b1 in bits 105–58. Both operands are
  formed before the input register in both modes (implicit bit, ADD's 1.0,
  packing). They also hold a's and b's mantissas for the classifiers, so only
  a's and b's signs and exponents stay in the operand register. This puts a
  few gates in front of the input register, where the FP64 baseline has
  none, so whatever drives the operands shares its cycle with them.
- **Adder.** Each lane's frame in the 163-bit addition is an FP32 FMA's 76
  bits: lane 0 bits 75–0, lane 1 bits 152–77. Lane 1's product moves up 19
  bits into its frame. Bit 76 separates the lanes. In the positive sum both of
  its inputs are lane 1's carry-in, so it keeps lane 0's carry and passes lane
  1's carry-in to bit 77. In the negative sum both of its inputs are 1, which
  carries the 1 that completes lane 1's two's complement. The addend inversion
  and the choice between the two sums are per frame.
- **Shifters.** `rtl/ucc_split_shift.sv` is a logarithmic shifter that can
  split in two: with `split_i` set no bit crosses the split, so each part
  shifts by its own lane's amount and drops what leaves it. The addend shifter
  splits at the bottom of lane 1's frame and the normalization shifter at
  bit 77.
- **1-bit normalization.** The last normalization mux selects per frame.

Each lane has its own control, copied from `fpnew_fma` in FP32:
`ucc_fp32_ctrl` (classification, operation selection, special cases,
exponents, addend shift amount), `ucc_fp32_norm` (its own 51-bit leading-zero
counter and the normalization amount) and `ucc_fp32_round` (rounding, flags,
result selection). The addend shifter has no room for lane 1's shifted-out
bits, so `ucc_fp32_ctrl` computes each lane's sticky bit from the shift amount
instead. It also decides in the first cycle whether the lane's sum is
normalized by its leading-zero count or by undoing the addend's shift, so one
exponent crosses the middle register instead of `fpnew_fma`'s three. The
constants are in `rtl/ucc_pkg.sv`. The FP64 path now uses the same modules in
FP64 ([Review fixes](#review-fixes)).

Lane 1 has its own FP32 control, like lane 0, instead of reusing the FP64
control in FP32 format as first planned. That keeps format muxes off the
FP64 control path into the addend shifter.

The split lengthens the path after the multiplier: lane 1's product passes
through a mux, and each lane's sum select waits for that lane's own carry,
which leaves the multiplier less of the first cycle.

Two earlier versions of this step differed in where the operands were formed
and what the registers held. The first muxed the operands after the input
register. The second formed them before it, but kept two registers for a and
three exponents per lane in the middle register.

## SFU mode: the Vortex MUFU's functions

An SFU opcode (0x78–0x7E) computes one FP32 function of `a_i[31:0]`, chosen
by the opcode's low three bits in Vortex's encoding: rcp, rsqrt, ex2, lg2,
sinpi, cospi or tanh. These are the functions of Vortex's MUFU (`vendor/vortex`, from the RTA
Vortex fork at 50cb174, unmodified). The result comes five cycles after issue,
NaN-boxed (bits 63–32 all ones), with no flags. SFU operations can issue every
cycle. Two cycles after issue an SFU operation takes the input register, so
no FMA may issue in that cycle; one that does is lost.

The MUFU splits x into a table index and an 18-bit fraction xl, evaluates
a0 + a1 · xl + a2 · xl² from a 512 × 72-bit coefficient ROM, and normalizes
and rounds the sum. In the UCC that work is split three ways.

**Front end** (`rtl/ucc_sfu.sv`, `rtl/ucc_sfu_rom.sv`, two cycles). It is the
MUFU's range reduction (`VX_mufu_pe`'s first stage, copied) and its ROM (the
same table). It hands the input register one FP64 FMA:

- **Multiplier operands:** b = a2 · 2^28 + a1, signed. a holds xl · 2^28 for
  rows 0–13 and xl² for rows 14–26.
- **Addend:** c's significand is a0, or for lg2 |k · 2^30 + a0|, where k is
  x's exponent. Its exponent puts a0's lowest bit at the product's bit 46 and
  gives the result the MUFU's scale.
- **Signs:** they make the operation an effective addition carrying the
  result's sign. lg2 of x < 1 is a subtraction instead.

**FP64 path.** It is unchanged apart from three details: `ucc_mul53` reads b
as signed, the two's complement product's sign fills the adder bits above it,
and c has no implicit bit. Its normalization is reused.

**Rounding** (second cycle). The FP64-normalized sum is rounded to FP32, to
nearest even. As in the MUFU:

- an exactly zero sum is a zero of the front end's sign;
- results beyond FP32's normal range become an infinity or a zero;
- special values go through the FP64 path's special-result registers.

One small difference from the MUFU: tanh of |x| < 2^-5 passes x through the
datapath (product zero, c = x), where the MUFU carries x as a special value.

**Results differ from Vortex's MUFU in the last bits.** The MUFU truncates
both products to its fixed-point grid before adding them, and rounds half up
from one bit. The UCC adds them exactly and rounds once, to nearest even. Of
the regression's 52,749 SFU inputs:

- 51,168 (97.0%) give Vortex's result bit for bit;
- every result meets the Vortex MUFU regression's accuracy bounds: 2 ulp,
  except lg2 near 1 (2^-22 absolute), sinpi and cospi (2^-21 absolute) and
  tanh (2^-11 relative);
- where the results differ, the UCC's is closer to the exact value in 1,177 of
  1,581 cases.

The largest differences are near zero, where the bounds are absolute: lg2
just below 1 and sinpi of tiny x. `sfu.py` is the UCC's reference, and
`sfu.mufu` runs Vortex's own C model (`vendor/vortex/sw/common/mufu.cpp`) for
the comparison.

## INT32 mode: ALU results in one cycle, multiplies in two

An INT32 opcode (0x00–0x3F, `ucc_pkg`'s `INT_*` codes; `intops.py` names them
and is the reference) computes one INT32 operation of the low words of `a_i`,
`b_i` and `c_i`. ALU operations later gained a second lane and lost it
again ([One operation per opcode](#one-operation-per-opcode)). An ALU
operation's result comes one cycle after issue and a multiply's two,
zero-extended (a wide product fills all 64 bits), with no flags.

The operations cover the DICE v2 PE's integer units, Vortex's integer ALU
(RV32I with Zicond) and RV32M's multiplies:

- **ALU** (`rtl/ucc_int_alu.sv`, codes 0–25): add, sub, abs; and, or, xor,
  not; shl, shr.u and shr.s by b's bits 4–0, as RISC-V and the DICE PE shift;
  eq, ne, lt, le, gt and ge, signed and unsigned, returning 0 or 1; min and
  max, signed and unsigned; czero.eqz and czero.nez. Codes 26–31 return 0.
- **Multiplies** (bit 5 set): bits 4–3 pick the low word, the high word or
  the whole 64-bit product, bit 2 adds c's low word (zero-extended) at the
  result's bit 0, and bits 1 and 0 make b and a signed. These give RISC-V's
  mul, mulh, mulhsu and mulhu and PTX's mul.lo, mul.hi, mul.wide, mad.lo and
  mad.hi.
- **Not in hardware:** division and remainder, which CUDA also compiles to
  rcp, mul.hi and a correction; and popc, clz and brev.

The DICE PE's own integer multiplier is 32 × 32 and computes only the low
word.

Each INT32 result skips the stages it does not need:

- **Operands** are formed before the input register, as the other modes' are.
  a and b go to bits 52–21 of the multiplier's operands, so their sign bits
  sit at bit 52. a and b take 1.0's exponent. c's significand is its low word,
  and its exponent puts c's bit 0 at the product's bit 42 (bit 74 for a high
  word).
- **ALU** results are computed after the input register from the registered
  multiplier operands, and go to `d_o` in the same cycle, one cycle after
  issue.
- **Multiplies** use `ucc_mul53`'s new `a_signed_i`. A row's sign flips when
  its multiplicand is negative, one gate per row, so the product a · b sits
  exactly at bits 105–42 for any signedness. The adder adds c, and the sum
  register holds the result: bits 75–44 (low word), 107–76 (high word) or
  107–44 (wide).
- **Bypass:** a mux in front of `d_o` takes an ALU result from the ALU, a
  multiply's from the middle register's sum, and everything else from the
  output register. FMAs still take three cycles and SFU operations five.
  Multiplies can't take one cycle: the multiplier and the adder fill the first
  cycle, the lane's critical path.

For an ALU operation, then, `d_o` is the ALU's output rather than a
register's. The ALU shares its cycle with whatever consumes the result, as
the DICE PE's 0-cycle compare and bitwise units share theirs.

The lane has one result port. When two results are due in the same cycle,
the younger operation's is returned and the older one's is lost:

- an ALU operation issued two cycles after an FMA or one after a multiply;
- a multiply issued one cycle after an FMA;
- either one due in the same cycle as an SFU result.

An INT32 operation issued two cycles after an SFU operation is lost, as an
FMA is. In the target fabric each PE repeats one operation, so none of these
cases arises; an issuer that mixes modes must track which cycles `d_o` is
taken. The bypass assumes `ucc_fma`'s `out_ready_i` stays set, as `ucc_lane`
ties it.

The INT32 mode's own logic is the ALU, the bypass and operand muxes and its
control flip-flops; the multiplier gains one gate per row. A first version
returned ALU results two cycles after issue, through special-result register
bits that only the ALU result used.

## The FU: every operation behind one opcode

`ucc_lane` is the single FU of the UCC tile. Each cycle `valid_i` issues one
operation: `op_i` is a 7-bit opcode in one global map, and `rm_i` is the
rounding mode in FPnew's encoding (RNE 0, RTZ 1, RDN 2, RUP 3, RMM 4; the
codes 5–7 round to nearest even). A cycle with `valid_i` clear issues nothing
and returns nothing. The mode ports
of the earlier steps (`fp32_i`, `sfu_i`, `sfu_fn_i`, `int_i`, `int_op_i`) are
gone; their operations are opcodes now. The map is `ucc_pkg`'s, and
`opcodes.py` mirrors it:

| `op_i` | Operations |
| --- | --- |
| 0x00–0x1F | INT32 ALU: the `INT_*` codes 0–25 (26–31 return 0) |
| 0x20–0x3F | INT32 multiplies: bits 4–3 pick the low word, high word or 64-bit product, bit 2 adds c, bits 1–0 make b and a signed |
| 0x40–0x5F | FP64: the function in bits 4–0 |
| 0x60–0x7F | FP32: the function in bits 4–0 |

| Function | Operation | Latency | Unit |
| --- | --- | --- | --- |
| 0x00 FMA | a · b + c | 3 | FMA datapath |
| 0x01 ADD, 0x02 SUB | a + b, a − b | 3 | FMA datapath |
| 0x03 MUL | a · b | 3 | FMA datapath |
| 0x08 MIN, 0x09 MAX | IEEE 754-2019 minimumNumber and maximumNumber | 1 | compare unit |
| 0x0A NEG, 0x0B ABS | −a and \|a\|, the sign bit alone | 1 | compare unit |
| 0x0C–0x11 EQ, NE, LT, LE, GT, GE | 1 or 0 | 1 | compare unit |
| 0x12 CVT_F | from the other FP format | 2 | conversion unit |
| 0x13 CVT_S32, 0x14 CVT_U32 | from a signed or unsigned int32 | 2 | conversion unit |
| 0x15 TO_S32, 0x16 TO_U32 | to a signed or unsigned int32 | 2 | conversion unit |
| 0x18–0x1E, FP32 only | the SFU's functions in Vortex's encoding: rcp, rsqrt, ex2, lg2, sinpi, cospi, tanh | 5 | SFU front end and FMA datapath |
| 0x18–0x1F, FP64 half only | DPA-16: FP16 and BF16 × 16, TF32 × 8, FP8 and MXFP8 × 32, NVFP4, MXFP4 and FP4 × 64 (see [DPA-16](#dpa-16)) | 4 | TransDot's `dpa16_core` |

Codes the map does not name (FP functions 0x04–0x07, 0x17 and, in FP32,
0x1F) return 0 one cycle after issue. 0x04–0x06 were DIV, SQRT and RCP until
the divider was removed ([No divider](#no-divider)).

Every opcode is one operation. A 32-bit operation, FP32 or INT32, reads
bits 31–0 of its operands and ignores the upper words. FP32 results come back
NaN-boxed. INT32 results, compares (1 or 0, in either format) and conversions
to int32 come back zero-extended (a wide product fills all 64 bits). Until
2026-11-05 the INT32 ALU's operations and FP32 FMA, ADD, SUB, MUL, MIN, MAX,
NEG, ABS and the compares worked on two lanes, {lane 1, lane 0}
([One operation per opcode](#one-operation-per-opcode)).

The new operations come from cvfpu, the FPnew release the DICE v2 PE builds
its FPUs from, at the same commit (58ca3c3), with its files unmodified in
`vendor/cvfpu`:

- **Compare unit** (`rtl/ucc_fp_noncomp.sv`): `fpnew_noncomp` once in FP64
  and once in FP32, with no pipeline registers, after the input
  register. Its result goes to `d_o` through the bypass mux in the cycle after
  issue, as an INT32 ALU result does.
- **Conversion unit** (`rtl/ucc_fp_cast.sv`): `fpnew_cast_multi` for FP32,
  FP64 and INT32, with no pipeline registers, after the input register. Its
  result crosses the middle register in the special-result register, and
  leaves through the bypass mux two cycles after issue.
- **ADD, SUB and MUL** are FPnew's own forms on the FMA datapath: ADD and SUB
  are 1.0 · a ± b (a and b move to the b and c operands), and MUL adds a zero
  whose sign the rounding mode picks.

These follow FPnew's conventions, which are RISC-V's:

- a NaN result is the canonical quiet NaN, except that NEG and ABS change only
  the sign bit;
- an exact zero sum is +0, or −0 in RDN;
- when one operand of MIN or MAX is a NaN they return the other, and they
  order −0 below +0;
- every compare but NE is false when an operand is a NaN, and NE is true;
- a conversion to int32 rounds in `rm_i` and saturates out-of-range values. A
  NaN gives the largest integer, as RISC-V's `fcvt` does; PTX's `cvt` would
  give 0.

The rounding mode applies to FMA, ADD, SUB, MUL and the conversions. INT32
operations and the SFU's functions ignore it; the SFU rounds to nearest even.
`ucc_lane` returns no flags. `ucc_fma`'s `status_o` carries FPnew's for the
FMA path, the compare unit and the conversions, and none for the INT32
operations, DPA-16 or the SFU.

### Issue rules

The FU takes one operation per cycle and returns each result a fixed latency
after issue, on the one result port. Two rules decide which results come
back:

- **Collisions:** when two results are due in the same cycle, the younger
  operation's is returned and the older one's is lost. The bypass mux checks,
  in this order, the 1-cycle units (ALU, compare unit, unnamed codes), the
  2-cycle ones (multiplies, conversions), the output register's FMA-path
  result, DPA-16's and the output register's SFU result.
- **The SFU's slot:** an SFU function takes the input register two cycles
  after its issue, so any other operation issued then is lost. An SFU
  function issued then is not, since its own front end takes it. A lost
  operation returns nothing.

`opcodes.settle` applies these rules to a stream of operations, and the
regression checks every result they leave. In the target fabric each PE
repeats one operation, so collisions and the SFU's slot never arise. An issuer that
mixes operations must track the cycles `d_o` is taken.

`ucc_fma` clears `in_ready_o` in the SFU's slot for any operation but an SFU
function, so an issuer that follows its handshake holds the operation for a
cycle instead of losing it. `ucc_lane` has no ready port, as the baseline has
none. Defining `UCC_CHECK_ISSUE` in simulation makes either rule's breach an
`$error`: an operation issued while `in_ready_o` is clear, or two results due
in the same cycle (`ucc_fma`'s `issue_lost` and `result_hidden`). It is off by
default, since the regression's mixed streams break both rules on purpose.

`ucc_fma`'s `flush_i` drops every operation in flight, the SFU front end's
and DPA-16's included: no operation issued in or before the cycle it is set
returns a result after that cycle, and an SFU function flushed before its
slot leaves the slot free (`opcodes.fates`). `ucc_lane` ties it off.

## DPA-16

The FU computes `d = c + Σ a_i · b_i` in FP32, one operation per cycle, with
TransDot's multi-format `dpa16_core` (`nv_tc/dpa16` at 599aaa5, the core of
each DPA16 in dora-lab's `rta_dpa16` array), unmodified, in `vendor/transdot` with the
other TransDot files and the same provenance checks. `rtl/ucc_dpa16.sv`
instantiates it in that array's configuration (M=0, PIPE=1, ONLY=-1, SHARE=0,
RND=0). The format is in the opcode, 0x58 plus `dpa16_pkg::fmt_e`,
then the FU's two formats:

| `op_i` | Format | Products |
| --- | --- | ---: |
| 0x58 | FP16 | 16 |
| 0x59 | BF16 | 16 |
| 0x5A | TF32 (32-bit containers, bits 31–13 read) | 8 |
| 0x5B | FP8: E4M3 or E5M2 per side, `rm_i` bit 0 for a, bit 1 for b | 32 |
| 0x5C | NVFP4: E2M1 with a UE4M3 scale per 16 elements | 64 |
| 0x5D | MXFP4: E2M1 with an E8M0 scale per 32 elements, given per 16 | 64 |
| 0x5E | MXFP8: FP8 as in 0x5B, with one E8M0 scale per side for all 32 elements (an OCP MX block), in byte 0 | 32 |
| 0x5F | FP4: E2M1 without scales | 64 |

`a_i` and `b_i` are DPA-16's 256-bit vectors, and `sa_i` and `sb_i` their four
8-bit block scales, as TransDot's `dpa16_core` takes them. The scales are read
only in NVFP4, MXFP4 and MXFP8 (byte 0 alone), and every other operation reads
bits 63–0 of `a_i` and `b_i` alone. Inside the FU each operand is 288 bits,
{scales, vector}, so "bits 287–64" below are a vector's bits 255–64 and its
scales. (Until 2026-11-05 the scales rode in `a_i` and `b_i` themselves, which
were 288 bits wide.) c's bits 31–0 are the FP32 addend, and the
result is NaN-boxed, four cycles after issue. The numerics are TransDot's
(`dpa16_ref.py`): exact products, every term aligned to the largest anchor in a
27-bit window and truncated, one sum, truncation to FP32, the canonical NaN for
any NaN or infinity among the active inputs (scales included).

The two formats TransDot's core lacks use its own paths, and `rtl/ucc_fma.sv`
maps them onto those before the input register, so that the core and its tiles
see a registered format: FP4 runs as MXFP4 with every scale forced to 2^0, and
MXFP8 as FP8 with a registered flag. Mapping them after the input register
instead, in `rtl/ucc_dpa16.sv`, put the mapping between the opcode register
and the tiles' modes, on the critical path. MXFP8 adds the two scales'
exponents, (s_a − 127) + (s_b − 127) = soff, to every product's: one offset for all 32
products, since one MX block covers them. Instead of adding soff to 32 anchors,
`rtl/ucc_dpa16_core.sv` subtracts it from the addend's anchor and adds it back
to the result's exponent before normalization, which gives every term exactly
the shift it would have had. That costs three 12-bit adders (soff, the addend's
anchor and the result's exponent) and a 12-bit register, and a scale of 0xFF is
NaN, as in MXFP4. TransDot's own MX support, before its removal (e6537c8,
e9c057d), applied the same offset and left 0xFF as 2^128; OCP MX makes it NaN.
The reference (`dpa.mxfp8`) is TransDot's FP8 terms with soff added, and a test
checks that it is TransDot's FP8 when both scales are 2^0, that scales 2^k and
2^−k cancel, and that 2^k alone moves an exact result's exponent by k.

MXFP8 and FP4 keep TransDot's numerics, which their scales and wider ranges now
reach with ordinary data:

- overflow returns ±infinity, not the largest finite value that truncation
  would give;
- with c = 0, a result whose largest product lies below 2^−133 returns +0,
  although FP32 has a subnormal for it (the alignment floor at −133 that B200
  applies is not modelled); FP8 alone never got there, MXFP8 with small scales
  does;
- an FP4 or MXFP4 block's anchor is 2^(10 + the scales' exponents) whatever
  its products are, so c is kept only to 25 bits below that: with FP4's unit
  scales, to 2^−15 whenever any product is nonzero;
- an E5M2 infinity, like any infinity among the inputs, returns the canonical
  NaN, where OCP MX would return the infinity; MXFP8 follows OCP MX's block,
  scale and NaN-scale rules, not its infinities;
- a zero result is +0.

The core sits after the input register, whose operand register also holds
bits 63–0 of DPA-16's a and b and its c, so those 160 bits are shared. The
rest of a and b (bits 287–64) has its own register, which only DPA-16 reads (it loaded
every cycle in this step; it now loads only with a DPA-16 operation). Its result leaves the core's own output register through
the bypass mux; it is younger than an SFU function's and older than an
FMA's, so it wins against the first and loses to the second. An operation issued in the SFU's slot is lost, DPA-16 included.

This step shares only the operand registers and the result path. The FMA
datapath and DPA-16 differ in shape: the FMA forms one 53 × 53 product and
aligns one addend across a 163-bit frame, while DPA-16 forms 16 to 64 narrow
products in 16 12 × 12 tiles and aligns 33 terms in one 27-bit window. The
multiplier is the one large block both have, and the next step merges it
([One multiplier](#one-multiplier-the-fmas-product-on-dpa-16s-tiles)).

## One multiplier: the FMA's product on DPA-16's tiles

The FU has one set of multipliers: DPA-16's 16 tiles (TransDot's
`dpa16_mul12`, unmodified) also form the FMA's 53 × 53 product, and the Booth
multiplier is gone. `rtl/ucc_dpa16_core.sv` is TransDot's `dpa16_core` with
its tiles moved out to `ucc_tiles`: ports send the tiles' operands and modes
out and take their products back, and nothing else changed but the MXFP8 mode
added since ([DPA-16](#dpa-16); a test checks the difference). In a DPA-16 cycle the tiles take those operands. In any other
cycle, tile t = 4i + j multiplies the 12-bit chunk i of the FU's multiplicand
a by chunk j of b in full 12 × 12 mode. `ucc_tilemul` adds the 16 products at
2^(12 (i + j)) to two strips above bit 47, a[52:48] · b and a[47:0] · b[52:48],
in one sum. The modes map onto the tiles as they did onto the Booth rows:

- **FP64:** every tile on; the product is a × b.
- **2 × FP32:** the packing is unchanged ({x1 at bits 52–29, five zero bits,
  x0 at bits 23–0}). Chunks 0–1 hold lane 0 and chunks 2–3 lane 1's low bits,
  so the eight tiles that would multiply one lane by the other are off, and
  the strips read only lane 1's bits. The product holds a0 · b0 in bits 47–0
  and a1 · b1 in bits 105–58, as before.
- **INT32:** the integers stay at bits 52–21. The tiles and strips multiply
  unsigned, and for a signed operand whose sign bit is set one correction
  subtracts 2^53 times the other operand.
- **SFU:** the front end's operands have a new layout: a = xl² · 2^24 +
  xl · 2^4 and b = a1 · 2^24 + a2 · 2^4, a1 and a2 in two's complement. Only
  the eight tiles that multiply one half by the other are on, xl · a1 and
  xl² · a2; the b strip adds a1's top bits, and two corrections subtract a1's
  and a2's sign weights. The product is 2^28 (a1 · xl + a2 · xl²), the sum the
  Booth multiplier's two row groups formed.

The tiles' operand select is a flip-flop of its own (`inp_pipe_dpa_q`, loaded
with the input register) rather than a decode of the registered opcode. It is
set for a DPA-16 operation except in the SFU's slot, where the tiles serve the
SFU and the DPA-16 operation is lost, as every operation issued there is.

Every result is the same as before the merge. The tiled product equals the
Booth multiplier's in every mode: the regression's `ucc_mul_tiles` case checks
it on 114,042 products against its definition, the operation each stands for
and `bench/ucc_mul53.sv`.

## No divider

The FU has no divider. DIV, SQRT and RCP (FP functions 0x04–0x06) left the
map on 2026-11-04 and now return 0 one cycle after issue, as the other unnamed
codes do. The divider was large, and in the target fabric, where each PE
repeats one operation, a PE that divided took a new operand pair only every
12 (FP32) or 19 (FP64) cycles and held its whole pipeline to that rate. Division now runs
as GPUs run it, at one result per cycle: the SFU's rcp (rsqrt for a square root) on one PE, then FMA
steps on the next ones, a refinement and a correction of the last bit, as CUDA
compiles a correctly rounded divide around the MUFU's reciprocal. B200 has no
divider either. The sequence is the compiler's and the mapper's to build:
correct rounding in every case needs extra handling for very small and very
large divisors (CUDA takes a slower path for them), and FP64 needs a seed with
FP64's exponent range, since the SFU is FP32 only.

The divider it had was cvfpu's THMULTI option, `fpnew_divsqrt_th_64_multi`
around T-Head's C910 VFDSU (a radix-16 SRT), in FP32 and FP64, correctly
rounded in every mode, behind a wrapper that fixed its latency at 13 (FP32) or
20 (FP64) cycles; one operation ran at a time. DICE's FPUs select cvfpu's PULP
divider (`fpu_div_sqrt_mvp`) instead, which is not correctly rounded: on the
regression's 32,255 hard-case DIV, SQRT and RCP vectors, 1,991 of its results
were wrong (6.2%), 255 of them in RNE. It rounded some quotients and square
roots the wrong way, returned infinity on overflow where RTZ, RDN or RUP call
for the largest finite value, flushed some tiny results to zero, and had no
RMM, with cvfpu's wrapper handing it RDN and RUP swapped. `rtl/ucc_divsqrt.sv`,
the C910 sources and the divider's vectors are in dora-lab's git history
(`examples/devices/rta_ucc`, before 17feed1).

## The FMA's three cycles rebalanced

`fpnew_fma` puts the product, the addend's alignment and both 163-bit sums in
the FMA path's first cycle. With the product on DPA-16's tiles, that cycle
holds two carry-propagate sums before the 163-bit one: each tile's 24-bit
product, then `ucc_tilemul`'s sum of the 16 tiles and two strips. That crowded
the first cycle: to fit it, the tiles had to be built faster, and so larger.
So the FMA path's three cycles are now split differently, at the same latency:

| Cycle | `fpnew_fma`'s split | Now |
| --- | --- | --- |
| Input stage, to the middle register | product, addend alignment, the two 163-bit sums | product, addend alignment |
| Middle stage, to the output register | normalization, rounding, result assembly | the two 163-bit sums, normalization, the value before rounding |
| Output cycle, to `d_o` | the bypass mux | rounding and result assembly, then the bypass mux |

The middle register holds the product (106 bits) and the aligned addend (163
bits) in place of the sum (163 bits). The output register holds the value
before rounding, with what the rounding needs (`ucc_pkg::round_t`: the round
and sticky bits, the exact-zero sign rule's subtraction flag, whether the value
is a special result), in place of the result. Each FP32 lane's rounding is
split the same way, into `ucc_fp32_preround` in the middle stage and
`ucc_fp32_round` in the output cycle, and the SFU's rounding to FP32 moves to
the output cycle with the FP64 path's. INT32 multiplies, due two cycles after
issue, leave from the middle stage's sum. Every function and every latency is
unchanged.

The rounding now takes part of the output cycle, between the output register
and `d_o`: whatever consumes an FMA-path result shares that cycle with the
rounding, as it shares an ALU result's cycle with the ALU.

## Review fixes

A review of the RTL found no wrong result but eleven things to change: at the
FU's edges, in its power, and in its upkeep. Every function and every latency
is unchanged.

- **The SFU's slot.** `in_ready_o` is clear in the SFU's slot for any
  operation but an SFU function, where it used to accept the operation and
  drop it ([Issue rules](#issue-rules)).
- **Sideband.** `tag_o`, `mask_o` and `aux_o` are the returned result's
  operation's. DPA-16's travel with its three stages and an SFU function's
  with its front end; they used to come from the output register and from the
  operation the SFU's FMA displaced. `ucc_lane` ties them off.
- **The issue check.** Defining `UCC_CHECK_ISSUE` makes a breach of either
  issue rule a simulation error ([Issue rules](#issue-rules)).
- **Idle registers.** Only the operations that use the middle stage (the FMA
  path's, the SFU's FMA, multiplies and conversions) enter the middle
  register, so ALU, compare, DPA-16 and unnamed operations no longer load it
  with an unused FMA. The register for a's and b's bits 287–64 (vector bits
  255–64 and the block scales) loads only with a DPA-16 operation, and
  DPA-16's three stage registers only with the operation entering each
  (`en_i`, the core fork's one change besides the tiles and MXFP8;
  `test_dpa.py` checks the difference). A register that loads only with its
  operation is an enable flip-flop: a little more logic for less switching.
- **The FP64 path's control.** It is `ucc_fp32_ctrl`, `ucc_fp32_norm`,
  `ucc_fp32_preround` and `ucc_fp32_round` in FP64, in place of a second copy
  of `fpnew_fma`'s logic. The modules take the format as a parameter
  (`FpFormat`), with their widths from `ucc_pkg`'s functions. So the FP64 path
  also decides in the first cycle how its sum is normalized, and one exponent
  crosses the middle register instead of three: 25 flip-flops fewer. The SFU's
  zero sum is the FP64 `ucc_fp32_norm`'s `zero_o`.
- **The registered unit.** The opcode's unit (`ucc_pkg::unit_e`) is
  registered with the opcode, so nothing after the input register decodes the
  opcode again.
- **Parameters.** `ucc_fma`'s defaults are the one configuration it supports
  (FP64, three registers, distributed), and elaboration stops with `$fatal`
  on any other.
- **Comments.** The multiplier comments no longer describe the Booth
  multiplier's rows.

## Second review

A second review found eight things, fixed in bae9aea: two wrong results at
`ucc_fma`'s edges, missing flags, untested ports, three that cost power, and a
stale header.
`ucc_lane`'s functions and latencies are unchanged, except in rounding modes
5–7.

- **Rounding modes 5–7.** FPnew names RNE to RMM and ROD (5). For 6 and 7
  (7 is RISC-V's DYN) its rounding takes a don't-care that is 1, so every
  FMA-path result and conversion came out one ulp up, exact ones included.
  The codes 5–7 now round to nearest even (ROD too, which the references do
  not model). DPA-16 still reads bits 1–0 as its FP8 subtypes.
  `ucc_lane_rm_reserved` checks it.
- **Flush.** `flush_i` now also drops the SFU front end's operations and
  DPA-16's, which used to return their results after a flush
  ([Issue rules](#issue-rules)). `ucc_lane` ties it off.
- **Flags.** `status_o` carries the compare unit's and the conversions' flags
  (FPnew's; either lane's in FP32), which were 0.
- **Tests for `ucc_fma`'s ports.** The regression drives `ucc_fma` itself
  (`bench/ucc_fma_bench.sv`) and checks every cycle what `ucc_lane` cannot
  see: whether a result comes, its operation's tag, aux and mask,
  `in_ready_o`, `busy_o`, the flags, and the issue rules' two breaches. Two
  streams that keep the rules run again with `UCC_CHECK_ISSUE` defined
  ([Regression](#regression)).
- **Idle multiplier.** The multiplier's operand registers load only with an
  operation that uses the product (the FMA path's, the SFU's FMA and INT32
  multiplies), so the 16 tiles and their strips stay still under ALU,
  compare, conversion, DPA-16 and unnamed operations. The INT32 ALU's lane 0
  reads the operand register, as lane 1 does (see
  [One operation per opcode](#one-operation-per-opcode)), instead of the
  multiplier's operands.
- **Idle SFU front end.** Its two stages' registers and the ROM's read
  register load only with an SFU operation; they used to load every cycle,
  about 240 flip-flops.
- **DPA-16's format.** The registered format and MXFP8 flag load only with a
  DPA-16 operation, as its other registers do, so its first stage no longer
  switches formats under the other operations. The compare and conversion
  units still see every operation's operands: gating their inputs would add
  a gate to the 1-cycle path to `d_o`, which has no time to spare.
- **Header.** `ucc_lane`'s header no longer says its operand ports are the
  baseline's.

## One operation per opcode

The target fabric issues one 32-bit operation per PE, so the FU no longer runs
two. The INT32 ALU's operations and FP32 FMA, ADD, SUB, MUL, MIN, MAX, NEG, ABS
and the compares used to work on two lanes, {lane 1, lane 0}. Now each is one
operation of bits 31–0, as every other 32-bit operation already was, and the
upper words are ignored. FP32 results come back NaN-boxed. INT32 results and
compares, FP32 as well as FP64, come back zero-extended. These are the
conventions the ALU and the compare unit had before their second lanes. The
opcodes, latencies, II = 1 and the issue rules are unchanged.

- **ALU and compare unit.** The second `ucc_int_alu` and the compare unit's
  second FP32 `fpnew_noncomp` are gone. They were added after the FU took its
  single opcode map. The second ALU read lane 1's integers from the operand
  register, which since then holds a and b unchanged for ALU operations
  rather than constants that only multiplies need, so that lane needed no
  flip-flops and no logic before the input register.
- **FMA path.** The FP32 operation takes lane 0's place: its significands at
  bits 23–0 of the multiplier's operands, its frame at adder bits 75–0 with
  zeros above. Lane 1's `ucc_fp32_ctrl`, `ucc_fp32_norm`, `ucc_fp32_preround`
  and `ucc_fp32_round` are gone, and so is everything that kept the lanes
  apart:
  - the tiles' and strips' FP32 mode (`ucc_tiles`, `ucc_tilemul`); the tiles
    above bit 23 multiply zeros;
  - the split shifters: `ucc_split_shift` is now `ucc_shift`, a plain shifter,
    still a module of its own so that synthesis reports it;
  - the separator at bit 76, and the per-frame addend inversion, carry, sum
    selection, sign and 1-bit normalization.
- **FP32's control, folded into the FP64 path's.** The FP32 operation's
  first-cycle results cross the middle register in the FP64 path's fields:
  effective subtraction, tentative sign, normalization case, exponent and shift
  amount (widened), and special result. The middle register loses its per-lane
  fields, and the output register lane 1's rounding fields.
  - One adder, sum selection and final sign now serve both formats.
  - The addend is inverted across the whole width. Above the FP32 frame the
    product and the addend are 0, so a carry out of the frame runs up to bit
    164, and the sum's selection and sign are the frame's.
  - The addend's sticky bit is the FP64 path's too. The FP32 frame sits 29 bits
    up in the shifter, so the bits it shifts out land in the FP64 sticky field,
    and `ucc_fp32_ctrl` no longer computes one.
  - FP32 keeps its own `ucc_fp32_ctrl`, `ucc_fp32_norm`, `ucc_fp32_preround`
    and `ucc_fp32_round`, for its exponent range, subnormals and rounding
    position.
- **Regression.** Every FP32 and INT32 operand now has a random upper word,
  which the FU must ignore. The FP32 reference is `fpnew_fp32_lane`, one
  unmodified `fpnew_fma` in FP32, and its cases are `ucc_lane_fp32` and
  `ucc_lane_fma_rm_fp32`. `ucc_fma_status` adds two FP32 operations whose
  upper words would raise a flag that their bits 31–0 do not.

On 2026-11-05 all 24 cases matched: 2,540,005 results from `ucc_lane` and
920,857 compares of `ucc_fma`'s ports. Nine mutants were checked, one at a
time, and each makes every case it targets fail:

- the ALU reading the upper word, or sign-extending its result;
- FP32 reading c's upper word;
- FP32 inverting only its frame, as the two-lane FU did, so that the carry
  stops at bit 76;
- FP32 without the addend's sticky bit;
- FP32's 1-bit normalization reading the wrong carry bit;
- the FP32 result not NaN-boxed;
- FP32 compares NaN-boxed, or the FP32 compare unit reading the upper words.

## Files

In this folder (`hw/rtl/ucc`):

| Path | Contents |
| --- | --- |
| `vendor/transdot/` | The upstream files, unmodified, DPA-16's RTL and model (`nv_tc/dpa16`) included. `PROVENANCE.json` gives each file's git blob and SHA-256, and the tests check both. |
| `vendor/cvfpu/` | cvfpu's (FPnew's) compare unit and conversion unit, and both licenses, unmodified, at the commit DICE's copy has; the same provenance checks. |
| `ucc_pkg.sv` | `fpnew_fma`'s derived widths for either format, the FP32 constants and frame, the output register's rounding fields (`round_t`), the global opcode map with each opcode's unit (`unit_of`), and the INT32 operation codes. |
| `ucc_tiles.sv` | The FU's one set of multipliers: DPA-16's 16 tiles (TransDot's `dpa16_mul12`, unmodified), with DPA-16's operands or the FU's chunks, and the tiles the SFU's mode turns off. |
| `ucc_tilemul.sv` | The FU's 53 × 53 product from the tiles: two strips, one sum, and the INT32 and SFU sign corrections. |
| `ucc_int_alu.sv` | The INT32 mode's ALU: everything but the multiplies. |
| `ucc_fp_noncomp.sv` | The compare unit: `fpnew_noncomp` in FP64 and FP32 for MIN, MAX, NEG, ABS and the compares. |
| `ucc_fp_cast.sv` | The conversion unit: `fpnew_cast_multi` for FP32, FP64 and INT32. |
| `ucc_shift.sv` | The FMA path's addend and normalization shifters, a module of their own so that synthesis reports them separately. |
| `ucc_fp32_ctrl.sv`, `ucc_fp32_norm.sv`, `ucc_fp32_round.sv` | The FMA path's control, normalization and rounding in format `FpFormat` (from `fpnew_fma`, Solderpad, header kept): the FP32 operation's in FP32, and the FP64 path's in FP64. `ucc_fp32_round.sv` holds the rounding's two parts: `ucc_fp32_preround` in the middle stage and `ucc_fp32_round` in the output cycle. |
| `ucc_fma.sv` | `fpnew_fma` (Solderpad, header kept) with its three cycles rebalanced (the sums in the middle stage, the rounding after the output register), the tiled product, FP32 on the FP64 datapath, the SFU mode, the INT32 mode, the opcode decode (DPA-16's MXFP8 and FP4 mapped onto the core's paths), the compare and conversion units and DPA-16, and the bypass mux. |
| `ucc_dpa16_core.sv` | TransDot's `dpa16_core` with its 16 tiles moved out, to `ucc_tiles`, the MXFP8 mode and the stage registers' enables added, and nothing else changed (a test checks the difference). |
| `ucc_dpa16.sv` | DPA-16: `ucc_dpa16_core` with the FU's operand layout, MXFP8's flag and the tiles' ports. |
| `ucc_sfu.sv`, `ucc_sfu_rom.sv` | The SFU mode's front end: the MUFU's range reduction and coefficient ROM (from Vortex, Apache-2.0, header kept; a test checks the ROM against `hw/rtl/mufu/VX_mufu_rom.sv`). |
| `ucc_lane.sv` | The FU top: `ucc_fma` with three distributed registers, `valid_i`, `op_i` and `rm_i`, DPA-16's 256-bit `a_i` and `b_i`, and their block scales on `sa_i` and `sb_i`. |

In the unit test (`hw/unittest/ucc_lane`):

| Path | Contents |
| --- | --- |
| `Makefile` | Builds one Verilator executable per device under test from `main.cpp`, through `../common.mk`: `ucc_lane`, `ucc_lane_issue_checked` (`ucc_lane` with `UCC_CHECK_ISSUE`), `ucc_fma_bench`, `ucc_mul_tiles`, `fp64_fma_lane` and `fpnew_fp32_lane`; runs the tests and `verify`. |
| `main.cpp` | The testbench: drives one device from a case file, cycle by cycle, and compares every output its mask selects. |
| `ucc.vlt` | The lint waivers: the vendored files, and the style warnings the FU's RTL has as synthesized. |
| `bench/fpnew_fp32_lane.sv` | The FP32 reference: one unmodified `fpnew_fma` in FP32 with the baseline's pipeline, its result NaN-boxed. |
| `bench/ucc_mul_tiles.sv` | The FU's tiled product alone (`ucc_tiles` and `ucc_tilemul`), for the regression. |
| `bench/ucc_fma_bench.sv` | `ucc_fma` as `ucc_lane` builds it, with the handshake, flush, flags, tag, aux, mask and the issue rules' breaches brought out, for the regression. |
| `bench/ucc_mul53.sv` | The 53 × 53 Booth multiplier the tiles replaced, two multiplicand inputs, b and a signed or not, kept as the reference for the tiled product (from dora-lab's copy). |
| `ucc/paths.py` | Where the sources are in the Vortex tree. |
| `ucc/models.py` | The exact FMA reference for FP64 and FP32 (rational arithmetic, one rounding, FPnew's NaN and zero-sign rules), and libm's `fma` / `fmaf` as a cross-check. |
| `ucc/fpops.py` | The reference for every FP operation in every rounding mode (rational arithmetic, one rounding, FPnew's conventions), and the C library's results as a cross-check. |
| `ucc/opcodes.py` | The global opcode map, each opcode's unit and latency, `evaluate` (what the FU returns for any operation), and `fates` and `settle` (the issue rules, and `ucc_fma`'s flush). |
| `ucc/sfu.py` | The SFU mode's reference, Vortex's MUFU (its C model, `sw/common/mufu.cpp`, compiled on first use) and the MUFU regression's accuracy bounds. |
| `ucc/intops.py` | The INT32 mode's codes and reference, from the operations' definitions, with the RISC-V and PTX operations each code implements. |
| `ucc/vectors.py` | Every vector and expected result, without the simulator, and the FU's streams of operations; synthesis runs validated the preprocessed RTL with it too (dora-lab's copy, up to 88d6323). |
| `ucc/fuvectors.py` | The vectors for the FP operations beyond the FMA in RNE, a stream of every opcode, and the independent cross-checks of their expected results. |
| `ucc/dpa.py` | DPA-16's reference: TransDot's `dpa16_ref.py`, loaded from `vendor/transdot`, with the FU's operand layout, and MXFP8 and FP4 on its FP8 and MXFP4 paths. |
| `ucc/dpavectors.py` | DPA-16's vectors and streams, and the cross-check of its results against the exact dot product. |
| `ucc/verify.py` | Writes every case of the regression to a case file, runs each on its device's executable, and checks every compare and every case's count. |
| `ucc/tests/` | The sources, the FMA reference against known results and libm, the SFU's table and reference against Vortex's, the INT32 codes and reference against `ucc_pkg` and the RISC-V and PTX definitions, and the opcode map, issue rules and FP reference against `ucc_pkg`, known results and the C library, and DPA-16's reference against `dpa16_pkg`'s formats, its lane counts, the bits it ignores, TransDot's FP8 and MXFP4 for the FU's MXFP8 and FP4, and the exact dot product. No simulation. |

## Running

From the build directory (`../configure` again after pulling this unit in, so
that it is staged):

```bash
make -C hw/unittest/ucc_lane run
```

`run` builds the executables, runs the tests (pytest) and then `verify`. `test`
runs only the tests, and `verify` only the regression; `JOBS` sets how many
cases simulate at once (default: every core), and `OUT` where the case files,
logs and `summary.json` go (default: `run` in the unit's build directory).

## Regression

`verify` runs 25 cases, each on its device's executable: 22 on the five
devices, and 3 more on `ucc_lane` built with `UCC_CHECK_ISSUE` defined. Every UCC case is a stream of
operations, one per cycle (`opcodes`), and compares each result
`opcodes.latency(op)` cycles after issue.

**`ucc_mul_tiles`**, the FU's product alone (`ucc_tiles` in the FU's modes
feeding `ucc_tilemul`), one product per cycle, compared with its definition
(`vectors.tilemul`). Every product that stands for an operation is also
checked against that operation and against the result of the replaced Booth
multiplier (`vectors.mul53`):

- 40,361 FP64 products: all pairs of 19 corner values (zeros, ones, the top
  bit, each 12-bit chunk and each strip full, alternating bits), then random
  significands; also checked against a × b;
- 30,081 FP32 products, the significands at bits 23–0 (all pairs of 9 corner
  values, then random significands); also checked against a × b;
- 4,096 SFU products in the SFU's layout (every ROM entry with xl = 0, 1, all
  ones and five random values), also checked against 2^28 (a1 · xl + a2 · sq),
  and against the Booth multiplier's result for the SFU's old layout;
- 5,000 arbitrary operands in SFU mode;
- 13,024 INT32 products, 3,256 for each signedness of a and b (all pairs of 16
  corner values, then random words), also checked against a · b · 2^42;
- 5,000 arbitrary operands with a and b signed at random.

**FP64**: `fp64_fma_lane` (the baseline) and `ucc_lane_fp64` (opcode 0x40, RNE)
each stream 121,385 FMAs, one per cycle, and compare each result three cycles
later. These are the vectors the baseline was validated with before it was
synthesized: same
seed, same generator, and `verify` checks their SHA-256. They cover:

- all triples of 32 special encodings: zeros, subnormal and normal extremes,
  infinities, quiet and signalling NaNs, large and small powers of two;
- exact and near cancellation, overlapping and distant exponents, underflow
  into subnormals, overflow, and random encodings;
- MUL (c = −0) and ADD (a = 1.0) forms.

**FP32**: `fpnew_fp32_lane` (an unmodified `fpnew_fma`, its result NaN-boxed)
and `ucc_lane_fp32` (opcode 0x60, RNE) each stream 143,357 FMAs, each FP32
vector once, its operands under random upper words that the FU must ignore.
The vectors are the FP64 kinds in FP32, with the alignment ranges scaled to p = 24, plus
three directed kinds where a single bit decides the rounding:

- products exactly halfway between two FP32 values, with c 20 to 80 binades
  below them;
- subnormal × normal products, whose leading zeros let the round bit fall to
  the frame's lowest bits after cancellation;
- sums that need the 1-bit left normalization and land exactly halfway.

**`ucc_lane_mixed`** streams 40,000 operations, each FP64 or FP32 at random,
from the two sets above.

**SFU**: `ucc_lane_sfu` streams 52,749 SFU operations, one per cycle, and
compares each result five cycles later with `sfu.evaluate`. The operand's upper
word and b and c are random, and the lane must ignore them. The inputs cover,
for every function:

- special encodings and both ends of every binade;
- every ROM entry with xl zero, all ones and random;
- 6,000 random encodings.

They also cover function-specific edges: ex2 around integers and at its
overflow and underflow ends, sinpi and cospi at quarter turns and far out,
tanh at its passthrough and saturation exponents, and lg2 around 1.
Every expected result is checked against the Vortex MUFU regression's
accuracy bounds.

**`ucc_lane_mixed_sfu`** streams 40,000 operations: FP64 FMAs, FP32 FMAs and
SFU operations at random. It includes 8,840 FMAs issued in the cycle an
SFU operation takes, and checks that none of their results appears.

**INT32**: `ucc_lane_int` streams 93,184 INT32 operations, one per cycle, and
compares each result with `intops.evaluate` one cycle (ALU) or two (multiply)
later. Every one of the
64 codes, reserved ones included, takes all pairs of 16 corner words (zero,
one, the extremes of both signednesses, 31 and 32, alternating bits) and then
1,200 random operands: a quarter each any words, shift-like b, a = b, and small
values of either sign. Every operand has a random upper word, which the FU
must ignore.

**`ucc_lane_mixed_int`** streams 40,000 operations of all four kinds at
random and checks 27,292 results. The others are an FMA or INT32 operation
issued in the cycle an SFU operation takes, or a result due in the same cycle
as a younger operation's.

**Rounding modes**: `ucc_lane_fma_rm_fp64` and `ucc_lane_fma_rm_fp32` run the
FP64 and FP32 vectors above as FMAs in RTZ, RDN, RUP and RMM: 485,540 and
573,428 operations. `ucc_lane_add_sub_mul` (696,512 operations)
runs ADD and SUB in all five modes on about 22,000 operand pairs per format,
and MUL on every FMA vector's a and b in a random mode. The pairs are every
pair of 32 specials, then exponents inside and far outside the alignment
window, near and exact cancellation, b half an ulp of a (an exact tie) or near
it, sums at the overflow threshold, subnormal operands and random encodings.

**`ucc_lane_fp_cmp`** runs each of MIN, MAX, NEG, ABS and the six compares on
10,048 operand pairs (both formats): every pair of specials, equal values,
values and their negations, values of one exponent, neighbouring encodings and
random encodings, 100,480 operations in a random rounding mode, which they
ignore.

**`ucc_lane_fp_cvt`** runs 89,212 conversions, in every mode where they round:
FP64 to FP32 of values at, halfway between and just off halfway between FP32
values from zero through the subnormals to the overflow threshold; FP32 to
FP64; int32 to FP32 and FP64 (signed and unsigned) of corner integers, random
ones and integers whose FP32 rounding is a tie; and FP32 and FP64 to int32 of
values at, around and between integers, at the int32 ranges' ends, and
specials.

**`ucc_lane_dpa16`** streams 24,453 DPA-16 operations, one per cycle, the
format changing from one to the next, and compares each result four cycles
later with TransDot's `dpa16_ref.py`:

- directed operations first: in every format and FP8 subtype pair, all
  products 1.0 with c = 0, 1 and −1, which returns the lane count; then each
  lane alone, with a value that names it; then MXFP8's scales on their own: a
  NaN scale on one side or both, with terms and without, 0xFF only in the
  bytes MXFP8 does not read, one scale swept across its range against 2^0,
  soff at both ends, overflow by the scaled products and by their sum with c,
  that sum cancelling, and soff around the subnormal limit;
- then 3,000 random operations per format, their elements near 1.0, of any
  exponent, subnormal, tiny (products near FP32's subnormals), at the top of
  the range, zero, special or raw random bits; exact cancellations; sparse
  vectors; and block scales across their range (NVFP4, MXFP4 and MXFP8),
  specials included.

Every bit an operation ignores is random: TF32's low 13 bits, the scales
outside NVFP4 and MXFP4 (all four bytes in FP4, bytes 1–3 in MXFP8), the FP8
subtype bits outside FP8 and MXFP8, `rm_i`'s bit 2 and c's upper word.

**`ucc_lane_mixed_dpa16`** streams 30,000 cycles of DPA-16 (40% of them)
among FMAs, SFU functions, ALU, compare-unit and conversion operations and
multiplies, with idle cycles, so that DPA-16's result meets every other unit's
in the same cycle. Of its 27,760 operations it checks 18,661 results. The
issue rules remove the rest: 2,553 lost to the SFU's slot and 6,546 hidden by
a younger result.

**`ucc_lane_mixed_fu`** streams 60,000 cycles: operations of every unit drawn
from the cases above, DPA-16 included, reserved codes and idle cycles, at
random. Of its 54,039 operations it checks 36,592 results. The issue rules
remove the rest: 3,942 lost to the SFU's slot and 13,505 hidden by a younger
result.

**`ucc_lane_rm_reserved`** issues 6,000 operations again in the rounding modes
FPnew does not name: 3,000 FMA-path operations and 3,000 conversions, drawn
from the RNE ones of the cases above, in modes 5 (1,919), 6 (2,057) and 7
(2,024). Each must return its RNE result.

**`ucc_fma` itself.** `bench/ucc_fma_bench.sv` is `ucc_fma` as `ucc_lane`
builds it, with the ports `ucc_lane` leaves unconnected brought out. Its cases
compare every cycle with what the issue rules (`opcodes.fates`) leave:
`out_valid_o` where a result comes and, with it, the result and its
operation's tag (the issue cycle's index), aux and mask (random); `in_ready_o`,
clear in an SFU function's slot unless `op_i` is an SFU function; `busy_o`,
from an operation's issue to its result or its flush; `status_o`, 0 for the
units that raise no flag; and `ucc_fma`'s `issue_lost` and `result_hidden`.

- `ucc_fma_mixed_fu` runs `ucc_lane_mixed_fu`'s 60,000 cycles: 463,775
  compares.
- `ucc_fma_flush` runs them again with `flush_i` set in 1,542 random cycles
  (one in 40). Of the 54,039 operations, 3,038 are flushed, 3,737 lost to the
  SFU's slot (flushes free some), 12,435 hidden and 34,829 returned: 455,862
  compares.
- `ucc_fma_status` issues 34 directed operations, each alone, with the flags
  IEEE 754 and RISC-V give it: the FMA path's overflow, underflow, inexact
  and invalid cases, signalling and quiet compares, MIN and MAX with NaNs,
  conversions to and from int32 and between the formats, FP32 operations whose
  upper words would raise a flag that their bits 31–0 do not, and units that
  raise none: 1,220 compares.

**`UCC_CHECK_ISSUE`.** `ucc_lane_issue_checked` runs `ucc_lane_sfu` and
`ucc_lane_dpa16` again with `UCC_CHECK_ISSUE` defined. They keep the issue
rules and must run without an `$error`; a stream that breaks them stops at its
first breach. `ucc_lane_mixed_sfu_breach` checks that the check is armed: it
runs `ucc_lane_mixed_sfu`, which breaks the rules on purpose, on the same build,
and must stop at its first breach without a result.

Each new case was checked against the bugs it is for, one RTL mutant at a
time: DPA-16 or the SFU front end not flushed, the flags as they were,
rounding modes 5–7 passed to FPnew, and DPA-16's tag taken one stage early
each make the case that covers them fail.

In every UCC case, operand bits an operation does not read are random: an FP32
operand's upper word where the operation reads bits 31–0, and operands the
operation does not take. In the two mixed streams with DPA-16, a's and b's
bits above 63 are random too, in every operation but DPA-16's.

Every expected FMA result is cross-checked against libm's `fma` or `fmaf`
wherever that returns a non-NaN result (112,298 FP64 and 133,946 FP32
vectors), and for the MUL and ADD forms against Python's own `*` and `+`. The
new cases' expected results come from `opcodes.evaluate` and are checked
against the C library in RNE, RTZ, RDN and RUP (C has no RMM; a NaN from C
must be the canonical NaN here) and against Python's float comparisons:
1,502,800 such checks, none failing. Each DPA-16 result is checked against the
exact dot product, from the stream's own decoding of the elements: 4,764 are
exactly the exact value truncated to FP32 (no term lost a bit to the window),
17,265 lie within the window's truncation of it (n terms times the window's
LSB, plus one ulp), 2,127 are the canonical NaN of a special input and 297
are zero, none failing. The INT32 reference is checked against the RISC-V and
PTX definitions in the fast tests. On 2026-11-04, without the divider, all 18
cases matched every result: 2,533,284 from the FU. They all match again with
the FMA's three cycles rebalanced
([The FMA's three cycles rebalanced](#the-fmas-three-cycles-rebalanced)).
On 2026-11-05, after the [second review](#second-review), all 24 cases
matched: 2,539,284 results from `ucc_lane` (the 18 cases' and 6,000 in the
reserved rounding modes) and 920,593 compares of `ucc_fma`'s ports. With one
operation per opcode ([One operation per opcode](#one-operation-per-opcode))
all 24 match again: 2,540,005 results from `ucc_lane` and 920,857 compares of
`ucc_fma`'s ports.

The 2 × FP32 vectors were checked by breaking the lane boundaries one at a
time: the separator bit in either sum, the shifter's split, the clearing of
the bits outside the frames, lane 1's zero fill on the left normalization,
and the sticky boundary one bit either way. Three more bugs break the lane
state: rows 14–26 seeing lane 0's bits of a, the lane's normalization case
without `fpnew_fma`'s cancellation clause, and the lane always registering the
product's exponent. Each of these ten bugs makes `ucc_lane_fp32x2` and
`ucc_lane_mixed` fail. The last three vector kinds above were added because
the first vectors missed two of these bugs.

The SFU cases were checked the same way, with 13 bugs:

- no sign fill above the product;
- b read as unsigned;
- c with its implicit bit;
- c aligned one bit off;
- rounding without the sticky bits;
- the result's sign on zero sums;
- flush to zero one exponent late;
- the issued FMA's b kept in the SFU's cycle;
- the row groups split at bit 29;
- lg2's subtraction dropped;
- tanh's passthrough one bit off;
- the FP32 exponent bias off by one;
- the special values dropped.

Each makes `ucc_lane_sfu` and `ucc_lane_mixed_sfu` fail, and all ten earlier
bugs still fail with the SFU mode in place.

The INT32 cases were checked with 20 more bugs:

- a or b multiplied as unsigned;
- in `ucc_mul53`, a row's sign flipped by a negative multiplicand even when its
  digit is zero, or a never sign-extended;
- c aligned one bit off for a high word, given its implicit bit, or always
  added;
- the high word read from the low word's bits, the result's bit 0 one bit off,
  or a wide product read as a word;
- in the ALU: a signed compare without its overflow case, an arithmetic shift
  right that fills zeros, abs one off, czero.eqz swapped, or the integer read
  from the operand's low bits;
- no ALU bypass, no multiply bypass, the middle register's bypass taken by
  ALU operations too, or the older result returned when two are due;
- an INT32 operation kept in the cycle an SFU operation takes.

Each makes `ucc_lane_int` or `ucc_lane_mixed_int` fail, the two multiplier
bugs `ucc_mul53` too. All 23 earlier bugs still fail with the INT32 mode in
place, each now also failing `ucc_lane_mixed_int`.

The FU's new logic was checked with 43 more bugs:

- **Opcode decode:** the FMA path one code short (MUL dropped), FP64's SFU
  codes taken as SFU functions, unnamed codes run as INT32 operations, SUB
  without the negation, ADD and SUB with a and b swapped, MUL run as an FMA,
  and the SFU's FMA keeping the displaced operation's opcode.
- **Rounding modes:** `rm_i` ignored, the FP32 lanes always in RNE, the
  exact-zero sign rule dropped in FP64 or in FP32, and MUL's zero addend
  signed for RUP instead of RDN in FP64 or in FP32.
- **Compare unit:** NE not negated, GT computed as GE, ABS reading b, and no
  1-cycle bypass.
- **Conversion unit:** unsigned int32 read as signed, conversion to unsigned
  int32 done as signed, FP to FP from the same format, int32 results
  sign-extended, the rounding mode fixed to RNE, and no 2-cycle bypass.
- **Divider:** the rounding mode fixed to RNE, FP32 released one cycle late or
  early, busy one cycle short, RCP computing 2 / a or a / 1, SQRT run as DIV,
  every operation in FP64, the held result returned when the divider finishes
  in the release cycle, the release one cycle early, a start without
  `valid_i`, and the divider's result winning over the output register.
- **Output and issue:** the output register taking every non-INT32 result,
  and `valid_i` tied high.

- **Two lanes:** lane 1's ALU reading lane 0's a, or a in place of b; the ALU
  result zero-extended from lane 0; ALU operations registering the
  multiplies' constants instead of a and b; the compare unit's lane 1 reading
  lane 0's operands; and FP32 compare-unit results NaN-boxed from lane 0.

Each fails the regression: 41 on mismatched results, and two (FP32 released
early, every operation in FP64) on `ucc_divsqrt`'s simulation check that the
divider never finishes after its release. Six of them only
`ucc_lane_mixed_fu` catches: FP64's SFU codes, unnamed codes run as INT32,
busy one cycle short, a start without `valid_i`, the divider's result winning
and the output register taking every result. The 43 earlier bugs,
five of them retargeted at the new bypass code, still fail too: 86 bugs in
all.

DPA-16 was checked with 12 more bugs:

- the format read from the opcode's bits 3–1, a's and b's FP8 subtypes
  swapped, a's block scales read from b, a's bits 287–64 taken before the
  input register, b's read from a's register, c read from its upper word, the
  result not NaN-boxed, or taken one cycle early: `ucc_lane_dpa16` and both
  mixed streams fail;
- DPA-16's result winning over a younger FMA's, losing to an older SFU
  function's, or produced for a cycle that issued nothing: the two mixed
  streams catch these;
- 0x5E decoded as DPA-16 (before MXFP8 and FP4 took 0x5E and 0x5F):
  `ucc_lane_mixed_fu` caught it.

All 86 earlier bugs still fail with DPA-16 in place: 98 bugs in all, 95 on
mismatched results and three (FP32 released early, busy one cycle short,
every operation in FP64) on `ucc_divsqrt`'s simulation checks.

The merged multiplier was checked with 15 more bugs. Five of them replace
earlier bugs in the Booth multiplier and its row groups, which the FU no
longer has:

- in 2 × FP32, the tiles that multiply one lane by the other left on, or
  either strip reading lane 0's bits;
- tile 15's product placed 12 bits too high, or INT32's sign correction one
  bit off;
- in the SFU, a1's or a2's sign correction dropped, the b strip reading all
  of a's low half, the 2 × FP32 tile pattern, or a2 placed one bit off;
- for DPA-16, the tiles never given its operands, given them in the SFU's
  slot, never put in FP8 or FP4 mode, or left in FP4 mode in the FU's own
  cycles.

Each fails the regression. `ucc_mul_tiles` catches the nine in the product
itself, and the lane cases catch all 15. The 93 earlier bugs that remain still
fail with the merge in place, two of them (a or b multiplied as unsigned)
retargeted at the tiled product's signedness inputs: 108 bugs in all, 105 on
mismatched results and the same three on `ucc_divsqrt`'s simulation checks.

MXFP8 and FP4 were checked with 23 more bugs:

- in the core: soff's bias off by two, a's scale read twice, or byte 1 read
  instead of byte 0; the 0xFF NaN dropped, read from a alone, from byte 1, as
  an exclusive or of the two sides, or only when a term is nonzero; the
  result's exponent not moved by soff, or moved by the next operation's; the
  addend's anchor moved by +soff, or not at all;
- in the mapping before the input register: FP4's scales 126 or not forced,
  FP4 run as NVFP4 or not mapped, MXFP8 not flagged or flagged on code 7, and
  the format or the flag taken before the register;
- in the decode: the 5-bit compare that wraps (no DPA-16 at all), seven
  formats (0x5F unnamed), and DPA-16 decoded in the FP32 half too (0x7F).

Each fails the regression. Only the directed MXFP8 operations catch the
exclusive-or and term-gated NaN flags, and only `ucc_lane_mixed_fu` catches
the FP32 half's 0x7F. DPA-16's code bound is retired, since 0x5F is now its
last code, and its format-bits bug is retargeted at the mapping; the other
106 earlier bugs still fail: 130 bugs in all, 127 on mismatched results and
the same three on `ucc_divsqrt`'s simulation checks.

Removing the divider retires the 12 divider bugs listed above, the three that
failed on `ucc_divsqrt`'s simulation checks among them. The other 118 were
last run against the FU with its divider, on 2026-11-03, and have not been
rerun since.

The rebalanced FMA was checked with six more bugs: the FP32 lanes' signs
without their carry, both FP32 lanes rounded with lane 0's flags, an FP64
special result replaced by the value before rounding, the SFU's round bit one
bit low, its exponent without the rounding's carry, and its sticky bit without
the bits below the FP64 mantissa. The first five fail the regression: the FP32
ones in the 2 × FP32 cases, the FP64 one in the FP64 cases, the SFU ones in
`ucc_lane_sfu`, and each in every mixed stream that holds its operations. The
sixth is equivalent and every result matches: the FP64 path holds the SFU's
sum exactly, so the bits below the FP64 mantissa are always 0. The six were
first run with the rebalancing applied to the FU before MXFP8, FP4 and the
divider's removal, with the 108 bugs of that time, seven of them retargeted at
the moved code, and all 108 failed. On this FU only the six were rerun.
