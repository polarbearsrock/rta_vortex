#ifdef SEPARATE_SHIFT
#include "VVX_ucc_shift_separate.h"
using Dut = VVX_ucc_shift_separate;
#else
#include "VVX_ucc_shift_shared.h"
using Dut = VVX_ucc_shift_shared;
#endif
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Dut dut;
    std::mt19937 rng(0x53484654);
    for (unsigned t = 0; t < 100000; ++t) {
        uint32_t words[4];
        uint8_t amounts[4];
        dut.amount = 0;
        for (unsigned q = 0; q < 4; ++q) {
            words[q] = dut.data_in[q] = rng();
            amounts[q] = t < 1024 ? t % 256 : rng() % 256;
            dut.amount |= uint32_t(amounts[q]) << (q * 8);
        }
        dut.mode = rng() % 4;
        dut.left = rng() & 1;
        dut.fill = rng() & 15;
        dut.eval();
        const unsigned width = dut.mode == 0 ? 128 : dut.mode == 1 ? 64 : 32;
        for (unsigned bit = 0; bit < 128; ++bit) {
            unsigned base = (bit / width) * width;
            int offset = int(bit - base);
            unsigned amount = amounts[base / 32];
            int src = dut.left ? offset - int(amount) : offset + int(amount);
            unsigned expected = !dut.left && ((dut.fill >> (base / 32)) & 1);
            if (src >= 0 && src < int(width)) {
                unsigned index = base + unsigned(src);
                expected = (words[index / 32] >> (index % 32)) & 1;
            }
            unsigned got = (dut.data_out[bit / 32] >> (bit % 32)) & 1;
            if (got != expected) {
                std::cerr << "shift mismatch trial " << t << " bit " << bit << std::endl;
                return 1;
            }
        }
    }
    std::cout << "PASS partitioned shifter: 100000 cases, all 256 shift amounts, both directions, all modes and fills\n";
}
