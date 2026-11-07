#!/usr/bin/env python3
"""Attribute flattened coefficient-bank cells to independently addressed PE outputs."""
from collections import deque
from functools import lru_cache
import hashlib
from pathlib import Path
import re


@lru_cache(maxsize=1)
def cell_outputs():
    root = Path('/data2/tools-additional/pdk/N28/installed/standard_cell/TSMCHOME/digital/Front_End/verilog')
    outputs = {}
    for suffix in ('', 'hvt', 'lvt'):
        name = 'tcbn28hpcplusbwp30p140' + suffix
        text = (root / (name + '_110a') / (name + '.v')).read_text()
        for module, body in re.findall(r'\bmodule\s+(\w+)\s*\(.*?\);(.*?)\bendmodule', text, re.S):
            pins = re.findall(r'\boutput\s+([^;]+);', body)
            outputs[module] = {pin.strip() for declaration in pins for pin in declaration.split(',')}
    return outputs


def audit(path, ports, expected_cells):
    text = path.read_text()
    if len(re.findall(r'^module\s', text, re.M)) != 1:
        raise ValueError('Cone audit requires a flattened netlist: ' + str(path))
    graph, cells = {}, []
    outputs = cell_outputs()
    for cell, instance, body in re.findall(r'^  (\w+)\s+(\S+)\((.*?)\);', text, re.M | re.S):
        if cell not in outputs:
            raise ValueError('Unknown mapped cell: ' + cell)
        pins = dict(re.findall(r'\.(\w+)\s*\(\s*([^()]+?)\s*\)', body))
        ins = [net for pin, net in pins.items() if pin not in outputs[cell]]
        outs = [net for pin, net in pins.items() if pin in outputs[cell]]
        if not outs:
            raise ValueError('Cell has no known output: ' + instance)
        cells.append((instance, outs))
        for net in outs:
            if net in graph:
                raise ValueError('Multiple drivers: ' + net)
            graph[net] = ins
    if len(cells) != expected_cells:
        raise ValueError(f'Parsed {len(cells)} cells but synthesis reports {expected_cells}')
    for lhs, rhs in re.findall(r'^  assign\s+(.*?)\s*=\s*(.*?);', text, re.M):
        if lhs in graph:
            raise ValueError('Multiple assignment drivers: ' + lhs)
        graph[lhs] = [rhs]

    @lru_cache(maxsize=None)
    def inputs(net):
        if re.fullmatch(r"\d+'[bB][01]+", net):
            return 0
        match = re.fullmatch(r'indices\[(\d+)\]', net)
        if match:
            index = int(match[1])
            if index >= 6*ports:
                raise ValueError('Input index out of range')
            return 1 << (index // 6)
        if net not in graph:
            raise ValueError('Unrecognized or undriven net: ' + net)
        result = 0
        for upstream in graph[net]:
            result |= inputs(upstream)
        return result

    consumers = {}
    pending = deque()
    wrong = []
    for bit in range(79*ports):
        net = f'coefficients[{bit}]'
        mask = 1 << (bit // 79)
        if inputs(net) & ~mask:
            wrong.append(net)
        consumers[net] = mask
        pending.append(net)
    while pending:
        net = pending.popleft()
        for upstream in graph.get(net, []):
            before = consumers.get(upstream, 0)
            after = before | consumers[net]
            if after != before:
                consumers[upstream] = after
                pending.append(upstream)
    dynamic = shared = mixed = 0
    for _, nets in cells:
        input_mask = consumer_mask = 0
        for net in nets:
            input_mask |= inputs(net)
            consumer_mask |= consumers.get(net, 0)
        dynamic += bool(input_mask)
        shared += bool(input_mask) and consumer_mask.bit_count() > 1
        mixed += input_mask.bit_count() > 1
    return {
        'netlist_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'mapped_cells': len(cells), 'dynamic_cells': dynamic,
        'dynamic_cells_feeding_multiple_pes': shared,
        'cells_depending_on_multiple_pe_addresses': mixed,
        'outputs_depending_on_another_pe_address': wrong,
        'method': 'Structural input/output cone attribution using cell pin directions from installed TSMC Verilog models; constants excluded from dynamic sharing.',
    }
