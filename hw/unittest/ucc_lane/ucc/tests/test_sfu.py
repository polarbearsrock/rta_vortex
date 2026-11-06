"""The SFU mode's table and reference against Vortex's MUFU."""

import random
import re

import pytest
from .. import sfu
from ..paths import MUFU_RTL, RTL


def table_words(path):
    return re.findall(r"72'h([0-9a-f]+)", path.read_text())


def test_rom_is_vortex_table():
    """ucc_sfu_rom holds VX_mufu_rom's 512 words, in the same order."""
    ours = table_words(RTL / "ucc_sfu_rom.sv")
    assert len(ours) == 512
    assert ours == table_words(MUFU_RTL / "VX_mufu_rom.sv")


def test_model_table_matches_rom():
    """The model's coefficients (mufu_tables.h) are the ROM words' fields."""
    entries, _ = sfu.table()
    for index, word in enumerate(sfu.rom_words()):
        a1 = word >> 19 & (1 << 24) - 1
        a2 = word & (1 << 19) - 1
        fields = (
            (word >> 43) << 2,
            (a1 - (a1 >> 23 << 24)) << 2,
            (a2 - (a2 >> 18 << 19)) << 1,
        )
        assert fields == entries[index], index


def test_sums_never_negative():
    """a0 + a1 xl + a2 xl^2 >= 0 over every entry's whole interval, so the FP64
    path's effective addition never meets a negative sum (lg2's negative
    results are its exponent's, handled as a subtraction)."""
    entries, _ = sfu.table()
    top = (1 << 18) - 1
    for a0, a1, a2 in entries:
        candidates = {0, top}
        if a2 > 0:  # interior minimum of the parabola in xl
            vertex = -a1 * (1 << 18) // (2 * a2)
            candidates |= {min(top, max(0, vertex + d)) for d in range(-2, 3)}
        for xl in candidates:
            assert (a0 << 18) + a1 * xl + a2 * (xl * xl >> 18) >= 0, (a0, a1, a2, xl)


@pytest.mark.parametrize("fn", range(7), ids=lambda f: sfu.NAMES[f])
def test_within_mufu_bounds(fn):
    """The Vortex MUFU regression's accuracy bound holds for random inputs."""
    rng = random.Random(fn)
    for _ in range(4000):
        x = rng.getrandbits(32) if rng.getrandbits(1) else rng.getrandbits(1) << 31 | rng.randrange(96, 160) << 23 | rng.getrandbits(23)
        assert sfu.accurate(fn, x, sfu.evaluate(fn, x)), f"{sfu.NAMES[fn]} {x:08x}"


def test_specials_match_mufu():
    """Special inputs give the MUFU's results exactly."""
    values = [0, 1, 0x7FFFFF, 0x800000, 0x3F800000, 0x7F7FFFFF, 0x7F800000, 0x7F800001, 0x7FC00000]
    for fn in range(8):
        for x in values + [v | sfu.SIGN for v in values]:
            if sfu.reduce(fn, x).special:
                assert sfu.evaluate(fn, x) == sfu.mufu(fn, x), (fn, f"{x:08x}")


def test_close_to_mufu():
    """Away from the special values the UCC differs from the MUFU only by its
    single rounding: by one unit in the last place for rcp, rsqrt and ex2."""
    rng = random.Random(7)
    for fn in (sfu.RCP, sfu.RSQRT, sfu.EX2):
        for _ in range(4000):
            x = rng.getrandbits(1) << 31 | rng.randrange(100, 150) << 23 | rng.getrandbits(23)
            y, m = sfu.evaluate(fn, x), sfu.mufu(fn, x)
            assert y >> 31 == m >> 31 and abs(y - m) <= 1, (sfu.NAMES[fn], f"{x:08x}", f"{y:08x}", f"{m:08x}")
