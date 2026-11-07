#ifdef MUFU_DIRECT
#include "VVX_ucc_mufu_standalone.h"
using DUT = VVX_ucc_mufu_standalone;
#else
#include "VVX_ucc_fpu_standalone.h"
using DUT = VVX_ucc_fpu_standalone;
#endif
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    DUT dut;
    unsigned count = 0, failures = 0;
    for (int file = 1; file < argc; ++file) {
        std::ifstream input(argv[file]);
        if (!input) return 2;
        std::string line;
        while (std::getline(input, line)) {
            unsigned a, b, c, op, rm, expected, flags, predicate = 0;
            std::istringstream record(line);
            if (!(record >> std::hex >> a >> b >> c >> op >> rm >> expected >> flags)) return 2;
            record >> predicate;
#ifdef MUFU_DIRECT
            if (op != 0x60 && op != 0x61) continue;
#else
            if (!(op <= 0x0f || (op >= 0x40 && op <= 0x43))) continue;
            dut.b = b; dut.c = c; dut.rm = rm;
#endif
            dut.a = a; dut.op = op;
            dut.eval();
            if (dut.result != expected || dut.flags != flags || dut.predicate != predicate) {
                if (failures < 12) {
                    std::cout << std::hex << "mismatch a=" << a << " b=" << b << " c=" << c
                        << " op=" << op << " rm=" << rm << " got=" << dut.result << "/"
                        << unsigned(dut.flags) << "/" << unsigned(dut.predicate)
                        << " expected=" << expected << "/" << flags << "/" << predicate << "\n";
                }
                ++failures;
            }
            ++count;
        }
    }
    std::cout << std::dec << (failures ? "FAIL" : "PASS") << " standalone scalar: "
        << count << " checks, " << failures << " mismatches\n";
    return failures || !count;
}
