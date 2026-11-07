#include "VVX_ucc_baseline_test.h"
#include "verilated.h"
#include <cstdint>
#include <cstring>
#include <deque>
#include <iostream>
#include <random>
#include <stdexcept>

static uint32_t bits(float x) {
    uint32_t u;
    std::memcpy(&u, &x, 4);
    return u;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VVX_ucc_baseline_test dut;
    std::mt19937 rng(0x55434316);
    const unsigned formats[] = {1, 2, 3, 4, 5, 10, 11};
    const unsigned ones[] = {0x1fc00, 0x3c00, 0x3f80, 0x38, 0x3c, 2, 2};
    const unsigned widths[] = {32, 16, 16, 8, 8, 4, 4};
    std::deque<uint32_t> pending;
    unsigned compared = 0, mathematical = 0, stalls = 0;
    dut.clk = 0;
    dut.reset = 1;
    dut.enable = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.reset = 0;
    for (unsigned cycle = 0; cycle < 20000; ++cycle) {
        dut.clk = 0;
        unsigned f = rng() % 7;
        dut.fmt = formats[f];
        dut.mask = (uint64_t(rng()) << 32) | rng();
        dut.scale_a = dut.scale_b = f == 6 ? 0x38383838 : 0x7f7f7f7f;
        dut.c = rng();
        for (unsigned j = 0; j < 8; ++j) {
            dut.a[j] = rng();
            dut.b[j] = rng();
        }
        const bool directed = cycle < 700;
        if (directed) {
            dut.c = bits(1.0f);
            for (unsigned j = 0; j < 8; ++j) {
                uint32_t word = 0;
                for (unsigned k = 0; k < 32; k += widths[f]) {
                    word |= ones[f] << k;
                }
                dut.a[j] = dut.b[j] = word;
            }
        }
        dut.enable = (rng() % 5) != 0;
        dut.eval();
        if (directed) {
            unsigned count = 0;
            const unsigned stride = widths[f] / 4;
            for (unsigned j = 0; j < 64; j += stride) {
                count += (dut.mask >> j) & 1;
            }
            uint32_t expected = bits(float(count + 1));
            if (dut.comb_result != expected) {
                std::cerr << "mathematical mismatch format " << formats[f]
                          << " got " << std::hex << dut.comb_result
                          << " expected " << expected << std::endl;
                return 1;
            }
            ++mathematical;
        }
        uint32_t before = dut.pipe_result;
        if (dut.enable) pending.push_back(dut.comb_result);
        dut.clk = 1;
        dut.eval();
        if (dut.enable && pending.size() >= 4) {
            if (dut.pipe_result != pending.front()) {
                std::cerr << "pipeline mismatch cycle " << cycle << " got "
                          << std::hex << dut.pipe_result << " expected "
                          << pending.front() << std::endl;
                return 1;
            }
            pending.pop_front();
            ++compared;
        } else if (!dut.enable) {
            if (dut.pipe_result != before) throw std::runtime_error("stall changed result");
            ++stalls;
        }
    }
    std::cout << "PASS baseline: " << compared << " pipeline comparisons, "
              << mathematical << " mathematical checks, " << stalls << " stalls\n";
}
