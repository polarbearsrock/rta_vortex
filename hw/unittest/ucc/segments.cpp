#include "VVX_ucc_segments_test.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VVX_ucc_segments_test dut;
    std::mt19937 rng(0x5345474d);
    using U128 = __uint128_t;
    for (unsigned test = 0; test < 200000; ++test) {
        dut.reduce_mode = test & 1;
        U128 product = 0;
        for (unsigned i = 0; i < 3; ++i) {
            dut.a[i] = rng() & 2047;
            dut.b[i] = rng() & 2047;
        }
        for (unsigned i = 0; i < 9; ++i) {
            dut.partials[i] = rng() & 0x3fffff;
            product += U128(dut.partials[i]) << (11*((i/3)+(i%3)));
        }
        for (unsigned i = 0; i < 3; ++i) dut.data[i] = rng();
        dut.amount = test & 4095;
        dut.left = (test >> 12) & 1;
        dut.fill = (test >> 13) & 1;
        dut.negatives = rng() & 0x1ffff;
        dut.c_sig = rng() & 0xffffff;
        int distance = int(test & 4095)-2048;
        dut.c_distance = distance & 4095;
        uint64_t sum = __builtin_popcount(dut.negatives);
        for (unsigned i = 0; i < 17; ++i) {
            uint64_t operand = (uint64_t(rng()) << 32) | rng();
            dut.operands[2*i] = uint32_t(operand);
            dut.operands[2*i+1] = uint32_t(operand >> 32);
            sum += operand;
        }
        dut.eval();
        uint64_t c_shifted = distance < 0 ? (distance <= -64 ? 0 : uint64_t(dut.c_sig) << -distance)
                                         : (distance >= 64 ? 0 : uint64_t(dut.c_sig) >> distance);
        bool c_sticky = distance > 0 && (distance >= 24 ? dut.c_sig != 0 : (dut.c_sig & ((1u << distance)-1)) != 0);
        if (dut.c_aligned != c_shifted || dut.c_sticky != c_sticky) {
            std::cerr << "multiplier alignment " << test << " distance " << distance << '\n'; return 1;
        }
        for (unsigned i = 0; i < 3; ++i) {
            uint32_t expected = dut.reduce_mode ? uint32_t(product >> (22*i)) & 0x3fffff : dut.a[i]*dut.b[i];
            if (dut.products[i] != expected) { std::cerr << "reducer " << test << " lane " << i << '\n'; return 1; }
        }
        U128 input = (U128(dut.data[2]) << 64) | (uint64_t(dut.data[1]) << 32) | dut.data[0];
        for (unsigned i = 0; i < 2; ++i) {
            unsigned width = 64+16*i, shift = dut.amount;
            U128 mask = (U128(1) << width)-1;
            U128 value = input & mask;
            U128 shifted;
            bool sticky = false;
            if (dut.left) shifted = shift >= width ? 0 : (value << shift) & mask;
            else {
                shifted = shift >= width ? (dut.fill ? mask : 0) : value >> shift;
                if (dut.fill && shift && shift < width) shifted |= mask ^ ((U128(1) << (width-shift))-1);
                sticky = shift >= width ? value != 0 : shift && (value & ((U128(1) << shift)-1));
            }
            if (uint32_t(dut.shifted >> (32*i)) != uint32_t(shifted) || ((dut.sticky >> i)&1) != sticky) {
                std::cerr << "window " << test << " width " << width << '\n'; return 1;
            }
        }
        bool sign = sum >> 63;
        if (dut.sum != sum || dut.sign != sign || dut.magnitude != (sign ? -sum : sum)) {
            std::cerr << "accumulator " << test << '\n'; return 1;
        }
    }
    std::cout << "PASS segments: 200000 mode-switch cases; 600000 multiplier/reduction outputs, 400000 shift/sticky outputs, 200000 signed accumulations, 200000 multiplier-assisted alignments\n";
}
