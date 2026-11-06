// Copyright © 2019-2026
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// s2chitni & Claude (AI-generated)
//
// The UCC FU's regression testbench: one device under test (UCC_TOP_<module>, one executable per device), driven
// from case files that ucc/verify.py writes. A case file is
//
//   ucc_case <name> <module>
//   ports <input> ... | <output> ...
//   <input> ... <compare mask> <expected output> ...      one line per cycle, every field in hex
//
// Each cycle drives the inputs, settles, compares the outputs that the mask selects (bit k: output k), then takes
// one clock edge: a result due L cycles after issue is compared on the line L after the issuing one, and a
// combinational device's on the same line. A case stops at its first mismatch. Each case runs on a fresh model.
//
// usage: <device> <case file> ...
// prints per case: UCC_DONE case=<name> cycles=<n> compares=<n> bad=<cycle or -1>, after a UCC_MISMATCH line if one

#include "verilated.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <functional>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#if defined(UCC_TOP_ucc_lane)
#include "Vucc_lane.h"
using Device = Vucc_lane;
#define UCC_MODULE "ucc_lane"
#define UCC_CLOCK clk_i
#define UCC_PORTS(IN, OUT)                                                                                         \
  IN(rst_ni, 1) IN(a_i, 256) IN(b_i, 256) IN(sa_i, 32) IN(sb_i, 32) IN(c_i, 64) IN(valid_i, 1) IN(op_i, 7)          \
  IN(rm_i, 3) OUT(d_o, 64)
#elif defined(UCC_TOP_ucc_fma_bench)
#include "Vucc_fma_bench.h"
using Device = Vucc_fma_bench;
#define UCC_MODULE "ucc_fma_bench"
#define UCC_CLOCK clk_i
#define UCC_PORTS(IN, OUT)                                                                                         \
  IN(rst_ni, 1) IN(a_i, 256) IN(b_i, 256) IN(sa_i, 32) IN(sb_i, 32) IN(c_i, 64) IN(valid_i, 1) IN(op_i, 7)          \
  IN(rm_i, 3) IN(flush_i, 1) IN(tag_i, 16) IN(aux_i, 16) IN(mask_i, 1)                                              \
  OUT(d_o, 64) OUT(status_o, 5) OUT(tag_o, 16) OUT(aux_o, 16) OUT(mask_o, 1) OUT(valid_o, 1) OUT(ready_o, 1)         \
  OUT(busy_o, 1) OUT(lost_o, 1) OUT(hidden_o, 1)
#elif defined(UCC_TOP_ucc_mul_tiles)
#include "Vucc_mul_tiles.h"
using Device = Vucc_mul_tiles;
#define UCC_MODULE "ucc_mul_tiles"
#define UCC_PORTS(IN, OUT)                                                                                         \
  IN(a_i, 53) IN(b_i, 53) IN(sfu_i, 1) IN(a_signed_i, 1) IN(b_signed_i, 1) OUT(p_o, 106)
#elif defined(UCC_TOP_fp64_fma_lane) || defined(UCC_TOP_fpnew_fp32_lane)
#if defined(UCC_TOP_fp64_fma_lane)
#include "Vfp64_fma_lane.h"
using Device = Vfp64_fma_lane;
#define UCC_MODULE "fp64_fma_lane"
#else
#include "Vfpnew_fp32_lane.h"
using Device = Vfpnew_fp32_lane;
#define UCC_MODULE "fpnew_fp32_lane"
#endif
#define UCC_CLOCK clk_i
#define UCC_PORTS(IN, OUT) IN(rst_ni, 1) IN(a_i, 64) IN(b_i, 64) IN(c_i, 64) OUT(d_o, 64)
#else
#error "Define UCC_TOP_<module> for the device under test"
#endif

namespace {

using Words = std::vector<uint32_t>;

// A port of any width, as 32-bit words, least significant first
template <typename T> void put(T& signal, const Words& w) {
  signal = T(sizeof(T) > 4 ? uint64_t(w[1]) << 32 | w[0] : w[0]);
}
template <std::size_t N> void put(VlWide<N>& signal, const Words& w) {
  for (std::size_t i = 0; i < N; ++i) signal[i] = w[i];
}
template <typename T> void get(const T& signal, Words& w) {
  w[0] = uint32_t(signal);
  if (sizeof(T) > 4) w[1] = uint32_t(uint64_t(signal) >> 32);
}
template <std::size_t N> void get(const VlWide<N>& signal, Words& w) {
  for (std::size_t i = 0; i < N; ++i) w[i] = signal[i];
}

struct Port {
  std::string name;
  int width;
  std::function<void(Device&, const Words&)> set;
  std::function<void(const Device&, Words&)> read;
};

struct Ports {
  std::vector<Port> in, out;
  Ports() {
#define UCC_IN(n, w) in.push_back({#n, w, [](Device& d, const Words& v) { put(d.n, v); }, nullptr});
#define UCC_OUT(n, w) out.push_back({#n, w, nullptr, [](const Device& d, Words& v) { get(d.n, v); }});
    UCC_PORTS(UCC_IN, UCC_OUT)
#undef UCC_IN
#undef UCC_OUT
  }
};

// Parses a hex field (hex digits only) into width bits; fails if it is anything else or the value is wider
bool parse(const std::string& text, int width, Words& w) {
  if (text.empty() || !std::all_of(text.begin(), text.end(), [](unsigned char c) { return std::isxdigit(c); })) {
    return false;
  }
  std::fill(w.begin(), w.end(), 0u);
  std::size_t digits = text.size(), word = 0;
  for (std::size_t end = digits; end > 0; ++word) {
    std::size_t begin = end >= 8 ? end - 8 : 0;
    uint32_t value = uint32_t(std::stoul(text.substr(begin, end - begin), nullptr, 16));
    if (word >= w.size()) {
      if (value) return false;
    } else {
      w[word] = value;
    }
    end = begin;
  }
  if (width % 32) {
    uint32_t top = w[(width - 1) / 32], keep = (1u << (width % 32)) - 1;
    if (top & ~keep) return false;
  }
  return true;
}

std::string hex(const Words& w) {
  std::string s;
  char buf[9];
  bool lead = true;
  for (std::size_t i = w.size(); i-- > 0;) {
    if (lead && w[i] == 0 && i > 0) continue;
    std::snprintf(buf, sizeof(buf), lead ? "%x" : "%08x", w[i]);
    s += buf;
    lead = false;
  }
  return s;
}

bool same(const Words& a, const Words& b, int width) {
  for (std::size_t i = 0; i < a.size(); ++i) {
    uint32_t keep = (int(i) == (width - 1) / 32 && width % 32) ? (1u << (width % 32)) - 1 : ~0u;
    if ((a[i] ^ b[i]) & keep) return false;
  }
  return true;
}

[[noreturn]] void fail(const std::string& file, uint64_t line, const std::string& why) {
  std::fprintf(stderr, "%s:%llu: %s\n", file.c_str(), static_cast<unsigned long long>(line), why.c_str());
  std::exit(2);
}

// Runs one case file on a fresh model
bool run(const std::string& file, int argc, char** argv) {
  std::ifstream in(file);
  if (!in) fail(file, 0, "cannot open");
  std::string line, tag, name, module;
  uint64_t number = 0;
  std::getline(in, line), ++number;
  std::istringstream(line) >> tag >> name >> module;
  if (tag != "ucc_case" || module != UCC_MODULE) fail(file, number, "not a case for " UCC_MODULE);
  const Ports ports;
  std::getline(in, line), ++number;
  {
    std::istringstream header(line);
    std::string word;
    header >> word;
    std::string expected = "ports";
    for (auto& p : ports.in) expected += " " + p.name;
    expected += " |";
    for (auto& p : ports.out) expected += " " + p.name;
    std::string got = "ports";
    while (header >> word) got += " " + word;
    if (got != expected) fail(file, number, "ports differ: " + got + " / " + expected);
  }

  auto context = std::make_unique<VerilatedContext>();
  context->commandArgs(argc, argv);
  auto device = std::make_unique<Device>(context.get());
  std::vector<Words> inputs, expected, actual;
  for (auto& p : ports.in) inputs.emplace_back(std::size_t(p.width + 31) / 32);
  for (auto& p : ports.out) {
    expected.emplace_back(std::size_t(p.width + 31) / 32);
    actual.emplace_back(std::size_t(p.width + 31) / 32);
  }
  Words mask(1);
#ifdef UCC_CLOCK
  device->UCC_CLOCK = 0;
#endif
  int64_t cycle = 0, bad = -1;
  uint64_t compares = 0;
  std::vector<std::string> fields;
  for (; std::getline(in, line); ++cycle) {
    ++number;
    fields.clear();
    std::istringstream row(line);
    for (std::string f; row >> f;) fields.push_back(f);
    if (fields.size() != ports.in.size() + 1 + ports.out.size()) fail(file, number, "wrong number of fields");
    for (std::size_t k = 0; k < ports.in.size(); ++k) {
      if (!parse(fields[k], ports.in[k].width, inputs[k])) fail(file, number, "too wide for " + ports.in[k].name);
      ports.in[k].set(*device, inputs[k]);
    }
    if (!parse(fields[ports.in.size()], int(ports.out.size()), mask)) fail(file, number, "bad compare mask");
    context->time(uint64_t(cycle) * 10);
    device->eval();
    for (std::size_t k = 0; k < ports.out.size(); ++k) {
      if (!(mask[0] >> k & 1)) continue;
      const Port& p = ports.out[k];
      if (!parse(fields[ports.in.size() + 1 + k], p.width, expected[k])) fail(file, number, "too wide for " + p.name);
      p.read(*device, actual[k]);
      ++compares;
      if (!same(actual[k], expected[k], p.width)) {
        std::printf("UCC_MISMATCH case=%s cycle=%lld port=%s dut=%s ref=%s\n", name.c_str(),
                    static_cast<long long>(cycle), p.name.c_str(), hex(actual[k]).c_str(), hex(expected[k]).c_str());
        bad = cycle;
      }
    }
    if (bad >= 0) break;
#ifdef UCC_CLOCK
    context->time(uint64_t(cycle) * 10 + 5);
    device->UCC_CLOCK = 1;
    device->eval();
    device->UCC_CLOCK = 0;
    device->eval();
#endif
  }
  device->final();
  std::printf("UCC_DONE case=%s cycles=%lld compares=%llu bad=%lld\n", name.c_str(),
              static_cast<long long>(bad >= 0 ? bad + 1 : cycle), static_cast<unsigned long long>(compares),
              static_cast<long long>(bad));
  std::fflush(stdout);
  return bad < 0;
}

} // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <case file> ...\n", argv[0]);
    return 2;
  }
  bool ok = true;
  for (int i = 1; i < argc; ++i) {
    if (argv[i][0] == '+') continue;  // Verilator's runtime options
    ok = run(argv[i], argc, argv) && ok;
  }
  return ok ? 0 : 1;
}
