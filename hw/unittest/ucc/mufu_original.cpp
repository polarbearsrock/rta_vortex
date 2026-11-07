#include "VVX_ucc_mufu_original_test.h"
#include "verilated.h"
#include <deque>
#include <iostream>
#include <random>

int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    VVX_ucc_mufu_original_test dut;
    std::mt19937 rng(0x4d554655);
    std::deque<uint32_t> pending;
    unsigned count=0,stalls=0;
    dut.clk=0;dut.reset=1;dut.enable=0;dut.eval();
    dut.clk=1;dut.eval();dut.reset=0;
    for (unsigned cycle=0;cycle<20000;++cycle) {
        dut.clk=0;dut.a=rng();dut.fn=rng()%8;dut.enable=rng()%5!=0;dut.eval();
        uint32_t previous=dut.pipe_result;
        if (dut.enable) pending.push_back(dut.comb_result);
        dut.clk=1;dut.eval();
        if (dut.enable && pending.size()>=7) {
            if (dut.pipe_result!=pending.front()) {
                std::cerr << "MUFU pipeline mismatch cycle=" << cycle << std::hex
                    << " actual=" << dut.pipe_result << " expected=" << pending.front() << "\n";
                return 1;
            }
            pending.pop_front();++count;
        } else if (!dut.enable) {
            if (dut.pipe_result!=previous) return 1;
            ++stalls;
        }
    }
    std::cout << "PASS original MUFU combinational view: " << count << " pipeline comparisons, " << stalls << " stalls\n";
}
