#include "VVX_ucc_dpa16_comb.h"
#include "verilated.h"
#include <fstream>
#include <iostream>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) return 2;
    std::ifstream input(argv[1]);
    VVX_ucc_dpa16_comb dut;
    unsigned count = 0, failures = 0, counts[12] = {}, errors[12] = {};
    unsigned fmt, sa, sb, c, expected;
    uint64_t mask;
    while (input >> std::hex >> fmt >> mask >> sa >> sb >> c) {
        dut.fmt = fmt; dut.mask = mask; dut.scale_a = sa; dut.scale_b = sb; dut.c = c;
        for (unsigned i = 0; i < 8; ++i) input >> dut.a[i];
        for (unsigned i = 0; i < 8; ++i) input >> dut.b[i];
        input >> expected;
        if (!input) return 2;
        dut.eval();
        if (dut.result != expected) {
            if (errors[fmt] < 4) std::cout << "mismatch fmt=" << std::dec << fmt
                << " row=" << count << std::hex << " sa=" << sa << " sb=" << sb
                << " got=" << dut.result << " expected=" << expected << "\n";
            ++failures; ++errors[fmt];
        }
        ++count; ++counts[fmt];
    }
    for (unsigned fmt = 0; fmt < 12; ++fmt) if (counts[fmt]) {
        std::cout << std::dec << "format " << fmt << ": " << errors[fmt] << "/" << counts[fmt] << " mismatches\n";
    }
    std::cout << (failures ? "FAIL" : "PASS") << " independent DPA: " << count << " cases\n";
    return failures || !count;
}
