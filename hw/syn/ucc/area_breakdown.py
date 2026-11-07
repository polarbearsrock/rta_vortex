#!/usr/bin/env python3
"""Attribute retained hierarchy without double counting flattened logic."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

from report import measured


def classify(path, module):
    if 'g_reconfigured_slices' in path or module.startswith('VX_ucc_mul_reducer'):
        return 'retained_reconfigurable_multiplier_reduction'
    if any(word in path for word in ('g_mul[', '.wtmul', 'sf_wtmul', '.multiplier', 'g_f8_mul[')):
        return 'retained_multiplier_logic'
    if module.startswith(('VX_csa_', 'VX_ks_adder', 'VX_popcount')):
        return 'retained_reduction_adders'
    if module.startswith(('VX_ucc_round', 'VX_tcu_tfr_norm', 'VX_lzc', 'VX_ucc_shift', 'VX_ucc_mul_align', 'VX_paired_shift', 'VX_partitioned_shift')):
        return 'retained_shift_normalize_round'
    if module.startswith('VX_tcu_tfr_max_exp'):
        return 'retained_exponent_ordering'
    if module.startswith(('VX_rom', 'VX_mufu_rom')):
        return 'retained_coefficient_rom'
    if module.startswith(('VX_ucc_boolean', 'VX_mux')):
        return 'retained_boolean_mux'
    if 'tensor_prepare' in path or '/mul/' in path or module.startswith(('VX_tcu_tfr_mul', 'VX_tcu_tfr_shared_mul')):
        return 'unattributed_tensor_preparation'
    return 'unattributed_other'


def breakdown(path):
    measurement = measured(path)
    nodes, stack = [], []
    pattern = re.compile(r'^(\s*)(\S+)\s+(?:(\S+)\s+)?(\d+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+ZeroWireload')
    for line in (path/'area_hier.rpt').read_text().splitlines():
        match = pattern.match(line)
        if not match:
            continue
        indent, instance, module, cells, area, _, _ = match.groups()
        depth = len(indent)
        while stack and stack[-1]['depth'] >= depth:
            stack.pop()
        name = (stack[-1]['path']+'/' if stack else '') + instance
        node = {'depth': depth, 'path': name, 'module': module or instance,
                'inclusive_um2': float(area), 'child_um2': 0.0, 'cells': int(cells)}
        if stack:
            stack[-1]['child_um2'] += node['inclusive_um2']
        nodes.append(node)
        stack.append(node)
    if not nodes or abs(nodes[0]['inclusive_um2']-measurement['area_um2']) > .001:
        raise ValueError('hierarchical area total does not match synthesis measurement')
    totals = defaultdict(float)
    for node in nodes:
        exclusive = node['inclusive_um2']-node.pop('child_um2')
        if exclusive < -.005:
            raise ValueError('child areas exceed parent: '+node['path'])
        node['exclusive_um2'] = round(exclusive, 6)
        node['category'] = classify(node['path'], node['module'])
        totals[node['category']] += exclusive
    if abs(sum(totals.values())-measurement['area_um2']) > .005:
        raise ValueError('exclusive area accounting failed')
    return {'top': measurement['top'], 'total_um2': measurement['area_um2'],
            'preprocessed_sha256': measurement['preprocessed_sha256'],
            'categories_um2': {key: round(value,6) for key,value in sorted(totals.items())},
            'limitation': ('Genus flattens arithmetic and control together. Retained categories are attributable '
                           'subsets, not complete functional costs. Zero/missing categories mean no separately '
                           'retained hierarchy; mux/control and normalization are also in the unattributed residual.'),
            'hierarchy': nodes}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('runs', nargs='+', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = {'measurements': [breakdown(path) for path in args.runs]}
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    for result in report['measurements']:
        print(result['top'], result['categories_um2'])


if __name__ == '__main__':
    main()
