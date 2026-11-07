#!/usr/bin/env python3
"""Measure independent-address EXP coefficient banks without throughput arbitration."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'hw/unittest/ucc'))
from run import BUILD, FLAGS, prepare, sources, verilator
from ex2_reference import coefficients as reference_coefficients
from gate_check import run_mapped
from report import measured
from coeff_cones import audit

OUT = BUILD / 'ucc_coeff_sharing'
STYLES = ('replica', 'array', 'plane')
GROUPS = (1, 2, 4, 8)
ORIGINAL = ROOT / 'hw/rtl/mufu/VX_mufu_rom.sv'
PACKAGE = ROOT / 'hw/rtl/ucc/VX_ucc_coeff_pkg.sv'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ensure_package():
    words = list(reversed([int(x, 16) for x in re.findall(r"72'h([0-9a-fA-F]+)", ORIGINAL.read_text())]))
    if len(words) != 512:
        raise ValueError('Unexpected canonical MUFU ROM layout')
    text = '// Generated from VX_mufu_rom.sv EX2 addresses 256--319 by coeff_sharing.py.\n'
    text += 'package VX_ucc_coeff_pkg;\n    localparam [64*72-1:0] EX2_WORDS = {\n'
    text += ',\n'.join(f"        72'h{x:018x}" for x in reversed(words[256:320]))
    text += '\n    };\nendpackage\n'
    if PACKAGE.exists() and PACKAGE.read_text() != text:
        raise ValueError('Generated EX2 coefficients differ from the canonical ROM')
    if not PACKAGE.exists():
        PACKAGE.write_text(text)


def common(config):
    return [verilator(), '-DVX_CFG_XLEN=32'] + [
        '-I' + str(p) for p in (config, BUILD / 'hw', ROOT / 'hw/rtl', ROOT / 'hw/rtl/libs')
    ] + [str(config / 'VX_config.vh')]


def packed_coefficient(index):
    a0, a1, a2 = reference_coefficients(index)
    return (a0 << 47) | ((a1 & ((1 << 27)-1)) << 20) | (a2 & ((1 << 20)-1))


def vectors(ports, exhaustive_pairs):
    rng = random.Random(0x434f4546 + ports)
    for address in range(64):
        yield [address] * ports
        yield [(address + 7*port) % 64 for port in range(ports)]
    if exhaustive_pairs:
        for left, right in itertools.combinations(range(ports), 2):
            for a in range(64):
                for b in range(64):
                    row = [(13*port + a + b) % 64 for port in range(ports)]
                    row[left], row[right] = a, b
                    yield row
    for _ in range(4096):
        yield [rng.randrange(64) for _ in range(ports)]


def write_vectors(path, ports, exhaustive_pairs):
    count = 0
    with path.open('w') as stream:
        for row in vectors(ports, exhaustive_pairs):
            indices = sum(value << (6*i) for i, value in enumerate(row))
            expected = sum(packed_coefficient(value) << (79*i) for i, value in enumerate(row))
            stream.write(f'{indices:x} {expected:x}\n')
            count += 1
    return count


def bank_bench(top, ports):
    return f'''`timescale 1ns/1ps
module ucc_gate_check;
    reg [{6*ports-1}:0] indices;
    wire [{79*ports-1}:0] coefficients;
    reg [{79*ports-1}:0] expected;
    integer fd, status, count;
    {top} dut (.indices(indices), .coefficients(coefficients));
    initial begin
        fd = $fopen("vectors.txt", "r");
        if (fd == 0) begin
            $fatal(1, "missing coefficient vectors");
        end
        count = 0;
        while (!$feof(fd)) begin
            status = $fscanf(fd, "%h %h", indices, expected);
            if (status == 2) begin
                #1;
                if (coefficients !== expected) begin
                    $fatal(1, "coefficient mismatch indices=%h got=%h expected=%h", indices, coefficients, expected);
                end
                count = count + 1;
            end else if (status != -1) begin
                $fatal(1, "bad vector record");
            end
        end
        $display("PASS gate simulation: %0d checks", count);
        $finish;
    end
endmodule
'''


def rtl(config):
    obj = OUT / 'rtl'
    obj.mkdir(parents=True, exist_ok=True)
    count = write_vectors(obj / 'vectors.txt', 8, True)
    instances, checks = [], []
    for ports in GROUPS:
        for style, name in enumerate(STYLES):
            suffix = f'{name}_{ports}'
            instances.append(f'wire [{79*ports-1}:0] out_{suffix};\n'
                f'VX_ucc_coeff_bank #(.PORTS({ports}), .STYLE({style})) dut_{suffix}'
                f' (.indices(indices[{6*ports-1}:0]), .coefficients(out_{suffix}));')
            checks.append(f'if (out_{suffix} !== expected[{79*ports-1}:0]) begin\n'
                          f'    $fatal(1, "RTL {suffix} mismatch at vector %0d", count);\nend')
    bench = bank_bench('VX_unused', 8)
    bench = bench.replace('wire [631:0] coefficients;', '')
    bench = bench.replace('VX_unused dut (.indices(indices), .coefficients(coefficients));', '\n'.join(instances))
    bench = re.sub(r'if \(coefficients !== expected\) begin.*?end', '\n'.join(checks), bench, flags=re.S)
    (obj / 'bench.sv').write_text(bench)
    srcs = sources('VX_ucc_coeff_bank')
    cxx = '/data/eda_tools/gcc-11/bin/g++'
    cxxlib = Path(subprocess.check_output([cxx, '-print-file-name=libstdc++.so'], text=True).strip()).parent
    cmd = common(config) + ['--cc', '--exe', '--main', '--timing', '--timescale', '1ns/1ps',
                           '--assert', '--top-module', 'ucc_gate_check', '--Mdir', str(obj),
                           '-CFLAGS', '-std=c++20', '-LDFLAGS', '-Wl,-rpath,' + str(cxxlib)]
    cmd += [str(p) for p in srcs] + [str(obj / 'bench.sv')]
    env = dict(os.environ)
    make = ['make', '-C', str(obj), '-f', 'Vucc_gate_check.mk', '-j4',
            'CXX=' + cxx, 'LINK=' + cxx, 'AR=/usr/bin/ar']
    with (obj / 'build.log').open('w') as log:
        subprocess.run(cmd, cwd=BUILD, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(make, cwd=BUILD, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = subprocess.run([str(obj / 'Vucc_gate_check')], cwd=obj, env=env, capture_output=True, text=True)
    (obj / 'result.txt').write_text(result.stdout + result.stderr)
    record = {'returncode': result.returncode, 'bank_input_vectors': count,
              'coefficient_checks': count * sum(GROUPS) * len(STYLES), 'result': result.stdout + result.stderr,
              'source_sha256': {str(p.relative_to(ROOT)): sha(p) for p in srcs},
              'vectors_sha256': sha(obj / 'vectors.txt'), 'command': cmd, 'make_command': make,
              'bench_sha256': sha(obj / 'bench.sv'), 'runner_sha256': sha(Path(__file__)),
              'binary_sha256': sha(obj / 'Vucc_gate_check'), 'oracle_source_sha256': sha(ORIGINAL)}
    (obj / 'manifest.json').write_text(json.dumps(record, indent=2) + '\n')
    print('RTL', record['coefficient_checks'], record['result'], flush=True)
    result.check_returncode()
    if f'PASS gate simulation: {count} checks' not in result.stdout:
        raise RuntimeError('RTL test did not finish')


def synth(config, ports, style):
    name = STYLES[style]
    top = f'VX_ucc_coeff_{name}_p{ports}'
    folder = BUILD / 'ucc_synth' / top
    if (folder / 'manifest.json').exists():
        measured(folder)
        print('Retaining completed frozen synthesis:', top, flush=True)
        return
    folder.mkdir(parents=True, exist_ok=True)
    wrapper = folder / 'wrapper.sv'
    wrapper.write_text(f'''module {top} (
    input wire [{6*ports-1}:0] indices,
    output wire [{79*ports-1}:0] coefficients
);
    VX_ucc_coeff_bank #(.PORTS({ports}), .STYLE({style})) bank (
        .indices(indices), .coefficients(coefficients)
    );
endmodule
''')
    srcs = sources('VX_ucc_coeff_bank') + [wrapper]
    cmd = common(config) + ['-E', '-P'] + [str(p) for p in srcs]
    with (folder / 'design.sv').open('w') as output:
        subprocess.run(cmd, cwd=BUILD, stdout=output, check=True)
    manifest = {'top': top, 'ports': ports, 'style': name, 'config_flags': FLAGS,
                'source_sha256': {str(p.relative_to(ROOT)): sha(p) for p in srcs},
                'preprocessed_sha256': sha(folder / 'design.sv'), 'config_sha256': sha(config / 'VX_config.vh'),
                'timing_budget_ns': 5.0, 'view': 'combinational', 'oracle_source_sha256': sha(ORIGINAL)}
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    shutil.copy2(ROOT / 'hw/syn/ucc/synth.tcl', folder / 'synth.tcl')
    env = dict(os.environ, UCC_TOP=top, UCC_RUN_DIR=str(folder))
    command = ('source /data/eda_tools/cadence/bashrc/genus.bashrc\n'
               'export CDS_LIC_FILE=${CDS_LIC_FILE:-27006@cadencels.s.uw.edu}\n'
               'genus -batch -files "$UCC_RUN_DIR/synth.tcl" -log genus')
    with (folder / 'run.log').open('w') as log:
        subprocess.run(['bash', '-c', command], cwd=folder, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    m = measured(folder)
    print('SYNTH', name, ports, m['area_um2'], m['data_path_ps'], flush=True)


def gate(ports, style):
    top = f'VX_ucc_coeff_{STYLES[style]}_p{ports}'
    obj = OUT / ('gate_' + top)
    obj.mkdir(parents=True, exist_ok=True)
    count = write_vectors(obj / 'vectors.txt', ports, ports == 2)
    run_mapped(BUILD / 'ucc_synth' / top, obj, bank_bench(top, ports), count)
    print('GATE', top, count, flush=True)


def report():
    tests = json.loads((OUT / 'rtl/manifest.json').read_text())
    if tests['returncode'] or f"PASS gate simulation: {tests['bank_input_vectors']} checks" not in tests['result']:
        raise ValueError('RTL verification failed')
    for path, digest in tests['source_sha256'].items():
        if sha(ROOT / path) != digest:
            raise ValueError('RTL verification sources changed: ' + path)
    measurements = []
    for ports in GROUPS:
        for name in STYLES:
            top = f'VX_ucc_coeff_{name}_p{ports}'
            folder = BUILD / 'ucc_synth' / top
            m = measured(folder)
            manifest = json.loads((folder / 'manifest.json').read_text())
            if manifest['oracle_source_sha256'] != sha(ORIGINAL):
                raise ValueError('Canonical coefficient table changed')
            for path, digest in manifest['source_sha256'].items():
                if sha(ROOT / path) != digest:
                    raise ValueError('Synthesis source changed: ' + path)
                if path in tests['source_sha256'] and tests['source_sha256'][path] != digest:
                    raise ValueError('RTL and synthesis source revisions differ: ' + path)
            gate_path = OUT / ('gate_' + top) / 'manifest.json'
            g = json.loads(gate_path.read_text())
            if (g['returncode'] or g['test_result'] != f"PASS gate simulation: {g['checks']} checks"
                    or g['synthesis']['preprocessed_sha256'] != m['preprocessed_sha256']):
                raise ValueError('Mapped evidence does not match: ' + top)
            cone = audit(folder / 'mapped.v', ports, m['cells']) if name != 'replica' else None
            if cone and cone['outputs_depending_on_another_pe_address']:
                raise ValueError('Unexpected cross-PE output dependency: ' + top)
            measurements.append({**m, 'ports': ports, 'style': name,
                'area_per_port_um2': m['area_um2'] / ports, 'lookups_per_cycle': ports,
                'gate_manifest': str(gate_path.relative_to(ROOT)), 'gate_checks': g['checks'],
                'gate_vectors_sha256': sha(gate_path.parent / 'vectors.txt'), 'mapped_cone_audit': cone})
    for m in measurements:
        one = next(x for x in measurements if x['ports'] == 1 and x['style'] == m['style'])
        local = next(x for x in measurements if x['ports'] == m['ports'] and x['style'] == 'replica')
        m['saving_vs_replicated_one_port_fraction'] = 1 - m['area_um2'] / (m['ports'] * one['area_um2'])
        m['saving_vs_same_group_original_fraction'] = 1 - m['area_um2'] / local['area_um2']
    result = {'measurements': measurements, 'rtl': tests,
        'gate_bank_vectors': sum(m['gate_checks'] for m in measurements),
        'gate_coefficient_checks': sum(m['gate_checks'] * m['ports'] for m in measurements),
        'minimum_area_per_port': min(measurements, key=lambda m: m['area_per_port_um2'])['top'],
        'recommendation': 'Keep local independently addressed selection logic. Four ports with the plane style have the smallest measured area per PE; the cone audit finds no cross-PE dynamic gate sharing in the array/plane candidates.',
        'report_generator_sha256': sha(Path(__file__)),
        'cone_audit_source_sha256': sha(Path(__file__).with_name('coeff_cones.py')),
        'scope': 'Coefficient-bank standard cells only; independent six-bit address per PE, no arbitration, no bank conflicts, no additional registers.',
        'limitations': ['5 ns standalone bank constraints, not a fresh full-UCC or post-route timing proof.',
                       'Constant-array sharing in RTL may replicate selection logic physically.',
                       'Compare group scaling within one style separately from single-port implementation changes.',
                       'Vectorless power is not workload power.']}
    target = ROOT / 'docs/proposals/ucc_coeff_sharing_measurements.json'
    target.write_text(json.dumps(result, indent=2) + '\n')
    for m in measurements:
        print(m['style'], m['ports'], m['area_um2'], m['area_per_port_um2'], m['data_path_ps'])
    print(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['rtl', 'synth', 'gate', 'report', 'all'])
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.jobs <= 4:
        parser.error('jobs must be in 1..4')
    ensure_package()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.action == 'report':
        report()
        return
    config = prepare()
    if args.action in ('rtl', 'all'):
        rtl(config)
    jobs = [(p, s) for p in GROUPS for s in range(len(STYLES))]
    if args.action in ('synth', 'all'):
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(synth, config, *job) for job in jobs]
            for future in futures:
                future.result()
    if args.action in ('gate', 'all'):
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(gate, *job) for job in jobs]
            for future in futures:
                future.result()
    if args.action == 'all':
        report()


if __name__ == '__main__':
    main()
