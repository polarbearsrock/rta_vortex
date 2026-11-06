"""Where the UCC FU's sources are in the Vortex tree: its RTL and the vendored upstream files (hw/rtl/ucc), this unit
test's benches, and Vortex's own MUFU (RTL, ROM and C model), which the SFU mode's reference reads."""

from pathlib import Path

HERE = Path(__file__).resolve().parent
VORTEX_HOME = HERE.parents[3]  # ucc -> ucc_lane -> unittest -> hw -> the repository
RTL = VORTEX_HOME / "hw" / "rtl" / "ucc"
TRANSDOT = RTL / "vendor" / "transdot"
CVFPU = RTL / "vendor" / "cvfpu"
BENCH = HERE.parent / "bench"
MUFU_RTL = VORTEX_HOME / "hw" / "rtl" / "mufu"
MUFU_SW = VORTEX_HOME / "sw" / "common"
