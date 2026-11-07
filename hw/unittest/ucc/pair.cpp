#include "VVX_paired_shift_jam.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VVX_paired_shift_jam dut;
    std::mt19937_64 rng(0x50414952);
    unsigned failures = 0;
    for (unsigned i = 0; i < 100000; ++i) {
        uint64_t input = rng() & ((uint64_t(1) << 52) - 1);
        unsigned low = i < 256 ? i : rng() & 255;
        unsigned high = rng() & 255;
        bool joined = i & 1;
        uint64_t expected = 0;
        unsigned sticky = 0;
        unsigned width = joined ? 52 : 26;
        unsigned lanes = joined ? 1 : 2;
        for (unsigned lane = 0; lane < lanes; ++lane) {
            uint64_t word = (input >> (lane*width)) & ((uint64_t(1) << width) - 1);
            unsigned shift = lane ? high : low;
            uint64_t shifted = shift >= width ? 0 : word >> shift;
            uint64_t lost = shift >= width ? word : word & ((uint64_t(1) << shift) - 1);
            expected |= shifted << (lane*width);
            sticky |= unsigned(lost != 0) << lane;
        }
        dut.data_in = input;
        dut.amount = (high << 8) | low;
        dut.joined = joined;
        dut.eval();
        if (dut.data_out != expected || dut.sticky != sticky) {
            if (failures < 8) {
                std::cout << "pair mismatch " << std::hex << input << " amount=" << unsigned(dut.amount)
                          << " joined=" << joined << " got=" << dut.data_out << "/" << unsigned(dut.sticky)
                          << " expected=" << expected << "/" << sticky << "\n";
            }
            ++failures;
        }
    }
    std::cout << (failures ? "FAIL" : "PASS") << " paired26/52 shifter:100000 cases\n";
    return failures != 0;
}
