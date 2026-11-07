#ifdef UCC_V1_CSA
#include "VVX_ucc_v1_csa_test.h"
using DUT = VVX_ucc_v1_csa_test;
#elif defined(UCC_V4_EXACT_EXP)
#include "VVX_ucc_v4_exact_exp_test.h"
using DUT = VVX_ucc_v4_exact_exp_test;
#elif defined(UCC_V4_EXP)
#include "VVX_ucc_v4_exp_test.h"
using DUT = VVX_ucc_v4_exp_test;
#elif defined(UCC_V4_SMALL)
#include "VVX_ucc_v4_small_test.h"
using DUT = VVX_ucc_v4_small_test;
#elif defined(UCC_V4_PAIRED)
#include "VVX_ucc_v4_paired_test.h"
using DUT = VVX_ucc_v4_paired_test;
#elif defined(UCC_V4_NATIVE)
#include "VVX_ucc_v4_native_test.h"
using DUT = VVX_ucc_v4_native_test;
#elif defined(UCC_NATIVE)
#include "VVX_ucc_native_test.h"
using DUT = VVX_ucc_native_test;
#elif defined(UCC_V4)
#include "VVX_ucc_v4_test.h"
using DUT = VVX_ucc_v4_test;
#elif defined(UCC_V3)
#include "VVX_ucc_v3_test.h"
using DUT = VVX_ucc_v3_test;
#elif defined(UCC_V2)
#include "VVX_ucc_v2_test.h"
using DUT = VVX_ucc_v2_test;
#else
#include "VVX_ucc_v1_test.h"
using DUT = VVX_ucc_v1_test;
#endif
#include "verilated.h"
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) return 2;
    std::ifstream vectors(argv[1]);
    if (!vectors) return 2;
    DUT dut;
    std::mt19937 rng(0x55434331);
    const unsigned formats[] = {1, 2, 3, 4, 5, 10, 11};
    unsigned a, b, c, op, rm, result, flags;
    unsigned count = 0, failures = 0, dpa_count = 0;
    auto tensor_trial = [&]() {
        dut.dpa = 1;
        dut.fmt = formats[rng() % 7];
        dut.mask = (uint64_t(rng()) << 32) | rng();
        dut.scale_a = rng();
        dut.scale_b = rng();
        dut.c = rng();
        for (unsigned i = 0; i < 8; ++i) {
            dut.a_vec[i] = rng();
            dut.b_vec[i] = rng();
        }
        dut.eval();
        if (dut.result != dut.reference_result) {
            if (failures < 12) {
                std::cout << "DPA mismatch fmt=" << unsigned(dut.fmt) << " c=" << std::hex << dut.c
                          << " got=" << dut.result << " expected=" << dut.reference_result << "\n";
            }
            ++failures;
        }
        ++dpa_count;
    };
    while (vectors >> std::hex >> a >> b >> c >> op >> rm >> result >> flags) {
        if ((count & 15) == 0) tensor_trial();
        dut.dpa = 0;
        dut.a = a;
        dut.b = b;
        dut.c = c;
        dut.op = op;
        dut.rm = rm;
        dut.eval();
        if (dut.result != result || dut.flags != flags) {
            if (failures < 12) {
                std::cout << "scalar mismatch " << std::hex << a << " " << b << " " << c
                          << " op=" << op << " rm=" << rm << " got=" << dut.result
                          << "/" << unsigned(dut.flags) << " expected=" << result << "/" << flags << "\n";
            }
            ++failures;
        }
        ++count;
    }
    while (dpa_count < 30000) tensor_trial();
#ifdef UCC_V2
    unsigned integer_count = 0;
    const unsigned integer_ops[] = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                                   0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
                                   0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f};
    const uint32_t edges[] = {0, 1, 2, 0x7fffffff, 0x80000000, 0x80000001, 0xfffffffe, 0xffffffff};
    auto integer_trial = [&](uint32_t x, uint32_t y, unsigned opcode) {
        uint32_t expected = 0;
        bool predicate = false;
        bool lt = (opcode & 0x20) ? x < y : int32_t(x) < int32_t(y);
        switch (opcode) {
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
        }
        dut.dpa = 0;
        dut.a = x;
        dut.b = y;
        dut.op = opcode;
        dut.eval();
        if (dut.result != expected || dut.predicate != predicate || dut.flags != 0) {
            if (failures < 12) {
                std::cout << "integer mismatch " << std::hex << x << " " << y << " op=" << opcode
                          << " got=" << dut.result << "/" << unsigned(dut.predicate)
                          << " expected=" << expected << "/" << predicate << "\n";
            }
            ++failures;
        }
        ++integer_count;
    };
    for (auto x : edges) for (auto y : edges) for (auto opcode : integer_ops) integer_trial(x, y, opcode);
    for (unsigned i = 0; i < 100000; ++i) {
        if ((i & 255) == 0) tensor_trial();
        integer_trial(rng(), rng(), integer_ops[rng() % 24]);
    }
    std::cout << std::dec << "Integer checks: " << integer_count << "\n";
#endif
#ifdef UCC_V3
    if (argc != 3) return 2;
    std::ifstream auxiliary(argv[2]);
    unsigned expected_predicate, auxiliary_count = 0;
    while (auxiliary >> std::hex >> a >> b >> c >> op >> rm >> result >> flags >> expected_predicate) {
#ifdef UCC_V4
        unsigned immediate;
        if (!(auxiliary >> immediate)) return 2;
        dut.immediate = immediate;
#endif
        if ((auxiliary_count & 255) == 0) tensor_trial();
        dut.dpa = 0;
        dut.a = a;
        dut.b = b;
        dut.c = c;
        dut.op = op;
        dut.rm = rm;
        dut.eval();
        if (dut.result != result || dut.flags != flags || dut.predicate != expected_predicate) {
            if (failures < 12) {
                std::cout << "auxiliary mismatch " << std::hex << a << " " << b << " op=" << op << " rm=" << rm
                          << " got=" << dut.result << "/" << unsigned(dut.flags) << "/" << unsigned(dut.predicate)
                          << " expected=" << result << "/" << flags << "/" << expected_predicate << "\n";
            }
            ++failures;
        }
        ++auxiliary_count;
    }
    if (!auxiliary_count) return 2;
    std::cout << std::dec << "Shift, conversion and FP comparison checks: " << auxiliary_count << "\n";
#endif
    std::cout << std::dec << (failures ? "FAIL" : "PASS") << " unified: " << count
              << " scalar and " << dpa_count << " DPA cases, " << failures << " mismatches\n";
    return failures || count == 0;
}
