#!/usr/bin/env python3
"""Sample all instruction groups and independent DPA vectors at mapped gate level."""
import argparse
from collections import defaultdict
from pathlib import Path
import random
import re
from gate_check import BUILD, prepare, integer_vectors, run_mapped


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('unit', choices=['dpa', 'approx', 'exact', 'csa', 'native'])
    parser.add_argument('--top')
    parser.add_argument('--label', default='')
    parser.add_argument('--groups', choices=['fma', 'int', 'aux', 'ex2', 'full'], default='full')
    parser.add_argument('--wide-polynomial', action='store_true')
    parser.add_argument('--compact-polynomial', action='store_true')
    args = parser.parse_args()
    if args.top and (not re.fullmatch(r'VX_ucc_[A-Za-z0-9_]+', args.top) or not args.label):
        parser.error('a top override requires a VX_ucc module name and a distinct label')
    if not re.fullmatch(r'[A-Za-z0-9_]*', args.label):
        parser.error('label must be alphanumeric')
    prepare()
    top = {'dpa':'VX_ucc_dpa16_comb', 'approx':'VX_ucc_v4_exp_comb',
           'exact':'VX_ucc_v4_exact_exp_comb', 'csa':'VX_ucc_v1_csa_comb', 'native':'VX_ucc_bf16x9_comb'}[args.unit]
    top = args.top or top
    obj = BUILD / ('ucc_gate_' + (args.label or args.unit))
    obj.mkdir(exist_ok=True)
    (obj/'result.txt').unlink(missing_ok=True)
    rng = random.Random(0x55434347)
    groups = defaultdict(list)
    if args.unit != 'dpa':
        folder = {'approx':'ucc_v4_exp_w64', 'exact':'ucc_v4_exact_exp', 'csa':'ucc_v1_csa', 'native':'ucc_native'}[args.unit]
        files = [BUILD/folder/'vectors.txt']
        if args.unit not in ('csa','native'):
            files.append(BUILD/folder/'aux_vectors.txt')
        for path in files:
            for line in path.read_text().splitlines():
                row = [int(x,16) for x in line.split()]
                if (args.wide_polynomial or args.compact_polynomial) and row[3] in (0x60, 0x61):
                    from ex2_reference import ex2
                    row[5] = ex2(row[0], narrow=args.unit == 'approx' and not args.wide_polynomial,
                                 natural=row[3] == 0x61, compact=args.compact_polynomial)
                groups[row[3]].append(row+[0]*(9-len(row)))
        if args.unit not in ('csa','native'):
            for row in integer_vectors():
                groups[row[3]].append(row)
    vectors = []
    for op, rows in sorted(groups.items()):
        if args.groups == 'fma' and op > 3:
            continue
        if args.groups == 'int' and not (op <= 3 or 0x10 <= op <= 0x2f):
            continue
        if args.groups == 'aux' and op > 0x43:
            continue
        if args.groups == 'ex2' and op > 0x60:
            continue
        chosen = rows[:32] + rng.sample(rows[32:], min(256,len(rows)-32))
        for a,b,c,op,rm,result,flags,predicate,immediate in chosen:
            vectors.append([0,0,0,0,0]+[0]*16+[a,b,c,op,rm,immediate,result,flags,predicate])
    tensor = defaultdict(list)
    for line in (BUILD/'ucc_dpa_model/vectors.txt').read_text().splitlines():
        row = [int(x,16) for x in line.split()]
        tensor[row[0]].append(row)
    for fmt, rows in sorted(tensor.items()):
        for row in rng.sample(rows,min(1024,len(rows))):
            fmt,mask,sa,sb,c = row[:5]
            vectors.append([1,fmt,mask,sa,sb]+row[5:21]+[0,0,c,0,0,0,row[21],0,0])
    rng.shuffle(vectors)
    (obj/'vectors.txt').write_text(''.join(' '.join(f'{x:x}' for x in row)+'\n' for row in vectors))
    arguments = ['mode','fmt','mask','sa','sb']+[f'av[{i}]' for i in range(8)]+[f'bv[{i}]' for i in range(8)]
    arguments += ['a','b','c','op','rm','immediate','expected','expected_flags','expected_predicate']
    netlist = (BUILD/'ucc_synth'/top/'mapped.v').read_text()
    header = netlist.split('module '+top+'(',1)[1].split(');',1)[0]
    def array_ports(name, signal, lanes, width):
        if '\\'+name+'[0]' in header:
            return ', '.join(f'.\\{name}[{i}] ({signal}[{i*width} +: {width}])' for i in range(lanes))
        return f'.{name}({signal})'
    scales = array_ports('scale_a','sa',4,8)+', '+array_ports('scale_b','sb',4,8)
    if args.unit == 'dpa':
        ports = '.fmt(fmt[4:0]), .mask(mask), .c(c), .result(result), '+scales
        ports += ', '+array_ports('a','av_flat',8,32)+', '+array_ports('b','bv_flat',8,32)
        ties = "assign flags=5'd0; assign predicate=1'b0;"
    else:
        ports = '.dpa(mode[0]), .fmt(fmt[4:0]), .mask(mask), .a(a), .b(b), .c(c), .result(result), .flags(flags), '+scales
        ports += ', '+array_ports('a_vec','av_flat',8,32)+', '+array_ports('b_vec','bv_flat',8,32)
        if args.unit != 'native':
            ports += ', .rm(rm[1:0])'
        if args.unit in ('csa','native'):
            ports += ', .op(op[1:0])'
            ties = "assign predicate=1'b0;"
        else:
            ports += ', .op(op[7:0]), .immediate(immediate[7:0]), .predicate(predicate)'
            ties = ''
    bench = '''`timescale 1ns/1ps
module ucc_gate_check;
    reg [31:0] mode,fmt,sa,sb,a,b,c,op,rm,immediate;
    reg [63:0] mask;
    reg [7:0][31:0] av,bv;
    wire [255:0] av_flat=av, bv_flat=bv;
    wire [31:0] result;
    wire [4:0] flags;
    wire predicate;
    reg [31:0] expected,expected_flags,expected_predicate;
    integer fd,status,count,failures;
    DUT dut (PORTS);
    TIES
    initial begin
        fd=$fopen("vectors.txt","r"); count=0; failures=0;
        if (!fd) $fatal(1,"missing vectors");
        while (!$feof(fd)) begin
            status=$fscanf(fd,"FORMAT",ARGS);
            if (status==30) begin
                #1;
                if (result !== expected || flags !== expected_flags[4:0] || predicate !== expected_predicate[0]) begin
                    if (failures<12) $display("mismatch mode=%h fmt=%h op=%h got=%h/%h/%h expected=%h/%h/%h",mode,fmt,op,result,flags,predicate,expected,expected_flags,expected_predicate);
                    failures=failures+1;
                end
                count=count+1;
            end else if (status != -1) $fatal(1,"bad vector record");
        end
        if (failures || !count) $fatal(1,"FAIL gate simulation: %0d/%0d mismatches",failures,count);
        $display("PASS gate simulation: %0d checks",count); $finish;
    end
endmodule
'''.replace('DUT',top).replace('PORTS',ports).replace('TIES',ties)
    bench = bench.replace('FORMAT',' '.join(['%h']*30)).replace('ARGS',','.join(arguments))
    run_mapped(BUILD/'ucc_synth'/top,obj,bench,len(vectors))


if __name__ == '__main__':
    main()
