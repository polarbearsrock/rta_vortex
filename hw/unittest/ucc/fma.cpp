#ifdef FMA_DIRECT
#include "VVX_ucc_fma_standalone.h"
using DUT = VVX_ucc_fma_standalone;
#else
#include "VVX_ucc_fma_test.h"
using DUT = VVX_ucc_fma_test;
#endif
#include "verilated.h"
#include <fstream>
#include <iomanip>
#include <iostream>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 2) return 2;
    std::ifstream vectors(argv[1]);
    if (!vectors) return 2;
    DUT dut;
    unsigned a, b, c, op, rm, result, flags;
    unsigned count = 0, failures = 0;
    while (vectors >> std::hex >> a >> b >> c >> op >> rm >> result >> flags) {
        dut.a = a;
        dut.b = b;
        dut.c = c;
        dut.op = op;
        dut.rm = rm;
        dut.eval();
        if (dut.result != result || dut.flags != flags) {
            if (failures < 12) {
                std::cout << "mismatch " << std::hex << a << " " << b << " " << c
                          << " op=" << op << " rm=" << rm << " got=" << dut.result
                          << "/" << unsigned(dut.flags) << " expected=" << result << "/" << flags << "\n";
            }
            ++failures;
        }
        ++count;
    }
    std::cout << std::dec << (failures ? "FAIL" : "PASS") << " FMA/MUL/ADD/SUB: "
              << count << " cases, " << failures << " mismatches\n";
    return failures || count == 0;
}
