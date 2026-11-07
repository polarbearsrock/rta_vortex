#include "VVX_ucc_int_standalone.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VVX_ucc_int_standalone dut;
    std::mt19937 rng(0x55434349);
    const unsigned ops[] = {0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
        0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f,
        0x28,0x29,0x2a,0x2b,0x2c,0x2d,0x2e,0x2f,
        0x30,0x31,0x32,0x33,0x50,0x51,0x52,0x53,0x54,0x55,0x56};
    const uint32_t edges[] = {0,1,2,31,32,63,0x7fffffff,0x80000000,
        0x80000001,0xfffffffe,0xffffffff};
    unsigned count = 0, failures = 0;
    auto trial = [&](uint32_t x, uint32_t y, uint32_t z, unsigned op, unsigned imm) {
        uint32_t expected = 0;
        bool predicate = false;
        const bool lt = op & 0x20 ? x < y : int32_t(x) < int32_t(y);
        switch (op) {
        case 0x10: expected = x + y; break;
        case 0x11: expected = x - y; break;
        case 0x12: expected = 0u - x; break;
        case 0x13: expected = int32_t(x) < 0 ? 0u - x : x; break;
        case 0x14: expected = uint64_t(x) * y; break;
        case 0x15: expected = (uint64_t(x) * y) >> 32; break;
        case 0x16: expected = uint64_t(int64_t(int32_t(x)) * int32_t(y)) >> 32; break;
        case 0x17: expected = uint64_t(int64_t(int32_t(x)) * int64_t(y)) >> 32; break;
        case 0x18: case 0x28: expected = predicate = x == y; break;
        case 0x19: case 0x29: expected = predicate = x != y; break;
        case 0x1a: case 0x2a: expected = predicate = lt; break;
        case 0x1b: case 0x2b: expected = predicate = lt || x == y; break;
        case 0x1c: case 0x2c: expected = predicate = !lt && x != y; break;
        case 0x1d: case 0x2d: expected = predicate = !lt; break;
        case 0x1e: case 0x2e: expected = lt ? x : y; predicate = lt; break;
        case 0x1f: case 0x2f: expected = lt ? y : x; predicate = lt; break;
        case 0x30: expected = x << (y & 31); break;
        case 0x31: expected = x >> (y & 31); break;
        case 0x32: expected = int32_t(x) >> (y & 31); break;
        case 0x33: expected = x ? __builtin_clz(x) : 32; break;
        case 0x50: expected = x & y; break;
        case 0x51: expected = x | y; break;
        case 0x52: expected = x ^ y; break;
        case 0x53: expected = ~x; break;
        case 0x54:
            for (unsigned bit = 0; bit < 32; ++bit) {
                const unsigned index = (((x >> bit) & 1) << 2)
                    | (((y >> bit) & 1) << 1) | ((z >> bit) & 1);
                expected |= ((imm >> index) & 1u) << bit;
            }
            break;
        case 0x55: expected = z & 1 ? x : y; break;
        case 0x56: expected = x; break;
        }
        dut.a = x; dut.b = y; dut.c = z; dut.op = op; dut.immediate = imm;
        dut.eval();
        if (dut.result != expected || dut.predicate != predicate) {
            if (failures < 12) {
                std::cout << std::hex << "mismatch op=" << op << " a=" << x << " b=" << y
                    << " got=" << dut.result << "/" << unsigned(dut.predicate)
                    << " expected=" << expected << "/" << predicate << "\n";
            }
            ++failures;
        }
        ++count;
    };
    for (auto x : edges) for (auto y : edges) for (auto op : ops) trial(x,y,rng(),op,rng());
    for (unsigned i = 0; i < 200000; ++i) trial(rng(),rng(),rng(),ops[rng()%35],rng());
    std::cout << std::dec << (failures ? "FAIL" : "PASS") << " standalone INT: "
        << count << " checks, " << failures << " mismatches\n";
    return failures != 0;
}
