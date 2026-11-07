#!/usr/bin/env python3
"""Check mapped N28 cells against references using installed PDK models and Xcelium."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'hw/unittest/ucc'))
from run import BUILD, prepare
from report import measured


def integer_vectors():
    rng = random.Random(0x55434349)
    edges = [0,1,2,31,32,63,0x7fffffff,0x80000000,0x80000001,0xfffffffe,0xffffffff]
    ops = list(range(0x10,0x20)) + list(range(0x28,0x30))
    inputs = [(a,b,op) for a in edges for b in edges for op in ops]
    inputs += [(rng.getrandbits(32),rng.getrandbits(32),rng.choice(ops)) for _ in range(100000)]
    for a,b,op in inputs:
        sx, sy = a-(1<<32) if a>>31 else a, b-(1<<32) if b>>31 else b
        lt = a < b if op & 0x20 else sx < sy
        predicate = 0
        if op == 0x10: value = a+b
        elif op == 0x11: value = a-b
        elif op == 0x12: value = -a
        elif op == 0x13: value = abs(sx)
        elif op == 0x14: value = a*b
        elif op == 0x15: value = (a*b)>>32
        elif op == 0x16: value = (sx*sy)>>32
        elif op == 0x17: value = (sx*b)>>32
        else:
            predicate = int([a==b,a!=b,lt,lt or a==b,not lt and a!=b,not lt,lt,lt][op&7])
            value = (a if lt else b) if op&7 == 6 else (b if lt else a) if op&7 == 7 else predicate
        yield [a,b,0,op,0,value&0xffffffff,0,predicate,0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('unit', choices=['int', 'fpu', 'mufu'])
    parser.add_argument('--ex2-only', action='store_true')
    args = parser.parse_args()
    if args.ex2_only and args.unit != 'mufu':
        parser.error('--ex2-only requires the mufu unit')
    prepare()
    top = 'VX_ucc_' + args.unit + '_standalone'
    if args.ex2_only:
        top = 'VX_ucc_ex2_standalone'
    synth = BUILD / 'ucc_synth' / top
    measurement = measured(synth)
    obj = BUILD / ('ucc_gate_' + ('ex2' if args.ex2_only else args.unit))
    obj.mkdir(exist_ok=True)
    (obj / 'result.txt').unlink(missing_ok=True)
    files = []
    if args.unit == 'fpu':
        files += [BUILD / 'ucc_fpu_direct/vectors.txt', BUILD / 'ucc_fpu_direct/aux_vectors.txt']
    elif args.unit == 'mufu':
        files += [BUILD / 'ucc_mufu_direct/aux_vectors.txt']
    else:
        files += [BUILD / 'ucc_v4_small_w64/aux_vectors.txt']
    vectors = list(integer_vectors()) if args.unit == 'int' else []
    for file in files:
        for line in file.read_text().splitlines():
            row = [int(x,16) for x in line.split()]
            op = row[3]
            if args.ex2_only and op != 0x60:
                continue
            accepted = (op in [0x60,0x61]) if args.unit == 'mufu' else (op < 0x10 or 0x40 <= op <= 0x43) if args.unit == 'fpu' else (0x30 <= op <= 0x33 or 0x50 <= op <= 0x56)
            if accepted:
                vectors.append(row + [0]*(9-len(row)))
    (obj/'vectors.txt').write_text(''.join(' '.join(f'{x:x}' for x in row)+'\n' for row in vectors))
    ports = '.a(a), .op(op[7:0]), .result(result), .predicate(predicate)'
    ports += ', .b(b), .c(c), .immediate(immediate[7:0])' if args.unit == 'int' else ', .flags(flags)'
    if args.unit == 'fpu':
        ports += ', .b(b), .c(c), .rm(rm[1:0])'
    bench = """`timescale 1ns/1ps
module ucc_gate_check;
    reg [31:0] a,b,c,op,rm,immediate;
    wire [31:0] result;
    wire [4:0] flags;
    wire predicate;
    integer fd,status,count,failures;
    reg [31:0] expected,expected_flags,expected_predicate;
    DUT dut (PORTS);
    TIE_FLAGS
    initial begin
        fd=$fopen("vectors.txt","r"); count=0; failures=0;
        if (!fd) $fatal(1,"missing vectors");
        while (!$feof(fd)) begin
            status=$fscanf(fd,"%h %h %h %h %h %h %h %h %h",a,b,c,op,rm,expected,expected_flags,expected_predicate,immediate);
            if (status == 9) begin
                #1;
                if (result !== expected || flags !== expected_flags[4:0] || predicate !== expected_predicate[0]) begin
                    if (failures<12) $display("mismatch a=%h b=%h op=%h result=%h/%h/%h expected=%h/%h/%h",a,b,op,result,flags,predicate,expected,expected_flags,expected_predicate);
                    failures=failures+1;
                end
                count=count+1;
            end else if (status != -1) $fatal(1,"bad vector record");
        end
        if (failures || !count) $fatal(1,"FAIL gate simulation: %0d/%0d mismatches",failures,count);
        $display("PASS gate simulation: %0d checks",count);
        $finish;
    end
endmodule
""".replace('DUT',top).replace('PORTS',ports).replace('TIE_FLAGS',"assign flags=5'd0;" if args.unit=='int' else '')
    run_mapped(synth, obj, bench, len(vectors))


def simulation_netlist(source, obj):
    # Parameterized ROM names can exceed Xcelium's identifier limit.
    original = source.read_text()
    tokens = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\\[^\s]+|[A-Za-z_$][A-Za-z0-9_$]*', re.S)
    names = {}

    def shorten(match):
        token = match.group()
        if len(token) <= 200 or token.startswith(('//', '/*', '"')):
            return token
        name = 'ucc_id_' + hashlib.sha256(token.encode()).hexdigest()[:24]
        if name in original:
            raise RuntimeError('netlist identifier collision')
        names[token] = name
        return name

    renamed = tokens.sub(shorten, original)
    reverse = {new: old for old, new in names.items()}
    if len(reverse) != len(names) or tokens.sub(lambda m: reverse.get(m.group(), m.group()), renamed) != original:
        raise RuntimeError('netlist identifier rename is not reversible')
    target = obj / 'mapped_sim.v'
    target.write_text(renamed)
    evidence = {'original_sha256': hashlib.sha256(original.encode()).hexdigest(),
                'simulation_sha256': hashlib.sha256(renamed.encode()).hexdigest(),
                'renamed_identifiers': len(names), 'reversible_rename_verified': True}
    (obj/'netlist_names.json').write_text(json.dumps({'evidence': evidence, 'names': names}, indent=2)+'\n')
    return target, evidence


def run_mapped(synth, obj, bench, checks):
    measurement = measured(synth)
    (obj/'bench.sv').write_text(bench)
    netlist, rename_evidence = simulation_netlist(synth/'mapped.v', obj)
    libroot = Path('/data2/tools-additional/pdk/N28/installed/standard_cell/TSMCHOME/digital/Front_End/verilog')
    xroot = Path('/data/eda_tools/cadence/XCELIUM2209')
    cmd = [str(xroot/'tools.lnx86/inca/bin/xrun'), '-64bit', '-sv', '-timescale', '1ns/1ps', '-top', 'ucc_gate_check',
           str(netlist), str(obj/'bench.sv'), '-l', 'xrun.log']
    for suffix in ['', 'hvt', 'lvt']:
        name = 'tcbn28hpcplusbwp30p140' + suffix
        cmd += ['-v', str(libroot / (name + '_110a') / (name + '.v'))]
    env = dict(os.environ)
    env['CDS_LIC_FILE'] = env.get('CDS_LIC_FILE','27006@cadencels.s.uw.edu')
    env['PATH'] = str(xroot/'tools/bin')+':'+str(xroot/'tools/inca/bin')+':'+env['PATH']
    with (obj/'build.log').open('w') as log:
        result = subprocess.run(cmd,cwd=obj,env=env,stdout=log,stderr=subprocess.STDOUT)
    log = (obj/'build.log').read_text()
    outcome = '\n'.join(line for line in log.splitlines() if re.match(r'^PASS gate simulation:', line)
                        or re.match(r'^mismatch ', line) or '*E,' in line or '*F,' in line)
    (obj/'result.txt').write_text(outcome+'\n')
    (obj/'manifest.json').write_text(json.dumps({'synthesis':measurement,'returncode':result.returncode,
        'checks':checks,'test_result':outcome,'netlist_rename':rename_evidence,
        'method':'Xcelium zero-delay simulation with installed TSMC Verilog cell models'},indent=2)+'\n')
    print(outcome)
    result.check_returncode()
    if not re.search(r'^PASS gate simulation: '+str(checks)+r' checks$', outcome, re.M):
        raise RuntimeError('simulation did not report the expected successful check count')


if __name__ == '__main__':
    main()
