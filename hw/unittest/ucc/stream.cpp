#include "VVX_ucc_stream.h"
#include "verilated.h"
#include <cstdint>
#include <cstring>
#include <deque>
#include <iostream>
#include <random>

static uint32_t bits(float x) {
    uint32_t value;
    std::memcpy(&value, &x, sizeof value);
    return value;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    VVX_ucc_stream dut;
    std::mt19937 rng(0x55434353);
    struct Expected { uint32_t result; unsigned tag, flags, predicate; };
    std::deque<Expected> pending;
    unsigned accepted=0,retired=0,aborted=0,stalls=0,full_rate=0;
    unsigned flag_results=0,predicate_results=0;
    bool held=false;
    Expected offered{};
    auto payload_matches = [&]() {
        return !pending.empty() && dut.result_o==pending.front().result && dut.tag_o==pending.front().tag
            && dut.flags_o==pending.front().flags && dut.predicate_o==pending.front().predicate;
    };
    const unsigned formats[] = {1,2,3,4,5,10,11};
    const unsigned widths[] = {32,16,16,8,8,4,4};
    const unsigned ones[] = {0x1fc00,0x3c00,0x3f80,0x38,0x3c,2,2};
    for (unsigned cycle=0;cycle<12000;++cycle) {
        dut.clk=0;
        dut.rst_n=cycle != 0 && !(cycle>2000 && cycle%517==0);
        dut.valid_i=dut.rst_n && (held || (cycle<11990 && (cycle<1001 || rng()%4)));
        dut.ready_i=cycle<1001 || cycle>=11990 || (cycle%31>=8 && rng()%4);
        if (!held) {
            dut.tag_i=cycle & 255;
            dut.a_i=rng(); dut.b_i=rng(); dut.c_i=rng();
            dut.rounding_mode_i=0; dut.immediate_i=0;
            uint32_t expected;
            unsigned flags=0,predicate=0;
            dut.dpa_i=rng()%3==0;
            if (dut.dpa_i) {
                unsigned f=rng()%7;
                dut.fmt_i=formats[f];
                dut.mask_i=(uint64_t(rng())<<32)|rng();
                dut.scale_a_i=dut.scale_b_i=f==6 ? 0x38383838 : 0x7f7f7f7f;
                dut.c_i=bits(1.0f);
                uint32_t word=0;
                for (unsigned bit=0;bit<32;bit+=widths[f]) word|=ones[f]<<bit;
                for (unsigned i=0;i<8;++i) dut.a_vec_i[i]=dut.b_vec_i[i]=word;
                unsigned count=0;
                for (unsigned i=0;i<64;i+=widths[f]/4) count+=(dut.mask_i>>i)&1;
                expected=bits(float(count+1));
            } else {
                switch (rng()%10) {
                case 0: dut.opcode_i=0x10;expected=dut.a_i+dut.b_i;break;
                case 1: dut.opcode_i=0x11;expected=dut.a_i-dut.b_i;break;
                case 2: dut.opcode_i=0x52;expected=dut.a_i^dut.b_i;break;
                case 3: dut.opcode_i=0x04;expected=dut.a_i^0x80000000;break;
                case 4: dut.opcode_i=0x05;expected=dut.a_i&0x7fffffff;break;
                case 5:
                    dut.opcode_i=0x18;
                    if (rng()&1) dut.b_i=dut.a_i;
                    expected=predicate=dut.a_i==dut.b_i;
                    break;
                case 6:
                    dut.opcode_i=0;dut.a_i=0;dut.b_i=0x7f800000;dut.c_i=0x3f800000;
                    expected=0x7fc00000;flags=16;
                    break;
                case 7:
                    dut.opcode_i=0;dut.a_i=dut.b_i=dut.c_i=0x3f800000;
                    expected=0x40000000;
                    break;
                case 8:
                    dut.opcode_i=0x42;dut.a_i=0x4f000000;
                    expected=0x7fffffff;flags=16;
                    break;
                default:
                    dut.opcode_i=0x60+(rng()&1);dut.a_i=0;
                    expected=0x3f800000;
                    break;
                }
            }
            offered={expected,unsigned(dut.tag_i),flags,predicate};
        }
        dut.eval();
        if (dut.rst_n && dut.valid_o && dut.ready_i) {
            if (!payload_matches()) {
                std::cerr << "retirement mismatch at cycle " << cycle << "\n";
                return 1;
            }
            flag_results+=dut.flags_o!=0;predicate_results+=dut.predicate_o;
            pending.pop_front(); ++retired;
        }
        if (!dut.rst_n) {
            aborted+=pending.size(); pending.clear();held=false;
        } else if (dut.valid_i && dut.ready_o) {
            pending.push_back(offered); ++accepted;held=false;
            if (cycle<=1000) ++full_rate;
        } else if (dut.valid_i) {
            held=true;
        }
        if (dut.valid_o && !dut.ready_i) ++stalls;
        dut.clk=1; dut.eval();
        if (bool(dut.valid_o)!=!pending.empty()) return 1;
        if (dut.valid_o && !payload_matches()) {
            std::cerr << "registered payload mismatch at cycle " << cycle << "\n";
            return 1;
        }
    }
    if (!pending.empty() || full_rate!=1000 || accepted!=retired+aborted || !stalls || !flag_results || !predicate_results) return 1;
    std::cout << "PASS stream: " << accepted << " accepted, " << retired << " retired, "
        << aborted << " reset-discarded, " << stalls << " stalled cycles, 1000 consecutive II=1 acceptances, "
        << flag_results << " flagged and " << predicate_results << " predicate results\n";
}
