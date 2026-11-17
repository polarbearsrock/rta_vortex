#!/usr/bin/env python3
"""Remove optional run detectors, then fold constants without moving arithmetic state."""
import argparse
from collections import Counter
from functools import lru_cache
import json
from pathlib import Path
import re

from b32_combinational_mapped_pin_support import truth_tables
from b32_mapped_structural_parser import parse_netlist, declarations
from run_sm_corner import digest


def run(parent, catalogs, out):
    assert not out.exists()
    mapped = parent / 'mapped.v'
    meta = json.loads((parent / 'candidate.json').read_text())
    assert digest(mapped) == meta['mapped_sha256']
    rows, outputs = parse_netlist(mapped)
    cells = {n: (t, dict(p)) for t, n, p in rows}
    models = json.loads((parent / 'models.json').read_text())
    tables = {}
    for catalog in catalogs:
        cm = json.loads((catalog / 'models.json').read_text())
        ct = truth_tables(json.loads((catalog / 'functions.json').read_text())['modules'])
        for typ, table in ct.items():
            if typ in models:
                assert cm[typ] == models[typ]
                tables[typ] = table
    assert all(t in tables for t, p in cells.values() if t != 'ICG' and not models[t]['state'])
    histories = {n: (t, p) for n, (t, p) in cells.items()
                 if re.fullmatch(r'b32_constant_run_(fma32|mul32|sfu_ex2)_history_[0-4]', n)}
    assert len(histories) == 15
    known = {"1'b0": 0, "1'b1": 1}
    for n, (t, p) in histories.items():
        assert models[t]['state'] == {'clocked_on': 'CP', 'next_state': 'D'}
        assert set(p) == {'CP', 'D', 'Q'}
        known[p['Q']] = 0
    @lru_cache(None)
    def restrict(typ, output, vals):
        ins, outs = tables[typ]
        possible = {outs[output] >> row & 1 for row in range(1 << len(ins))
                    if all(v is None or (row >> i & 1) == v for i, v in enumerate(vals))}
        return possible.pop() if len(possible) == 1 else None
    top_comb = {n: (t, p) for n, (t, p) in cells.items()
                if '/' not in n and t != 'ICG' and not models[t]['state']}
    while True:
        count = len(known)
        for n, (t, p) in top_comb.items():
            ins, outs = tables[t]
            vals = tuple(known.get(p[k]) for k in ins)
            for pin in outs:
                val = restrict(t, pin, vals)
                if val is not None:
                    assert p[pin] not in known or known[p[pin]] == val
                    known[p[pin]] = val
        if len(known) == count:
            break
    assert not outputs.intersection(known), 'Do not replace architectural output drivers'
    aliases, removed = {}, set(histories)
    bypassed = {}
    for n, (t, p) in cells.items():
        if t == 'ICG' and known.get(p['enable']) == 1 and known.get(p['test']) == 0:
            assert n.count('/') == 1
            aliases[p['ck_out']] = p['ck_in']
            bypassed[n] = p
            removed.add(n)
    assert all(f'b32_constant_run_capture_{i}/RC_CGIC_INST' in bypassed for i in range(19))
    def replace_net(net):
        seen = set()
        while net in aliases:
            assert net not in seen
            seen.add(net); net = aliases[net]
        return "1'b" + str(known[net]) if net in known else net
    for n, (t, p) in top_comb.items():
        if all(p[k] in known for k in tables[t][1]):
            removed.add(n)
    expected = {}
    for n, (t, p) in cells.items():
        if n in removed:
            continue
        inputs = set(p) - {'ck_out'} if t == 'ICG' else {k for k, d in models[t]['pins'].items() if d['direction'] == 'input'}
        expected[n] = (t, {k: replace_net(v) if k in inputs else v for k, v in p.items()})
    while True:
        readers = Counter(v for n, (t, p) in expected.items() for k, v in p.items()
                          if (t == 'ICG' and k != 'ck_out') or (t != 'ICG' and models[t]['pins'][k]['direction'] == 'input'))
        dead = set()
        for n, (t, p) in expected.items():
            if t == 'ICG':
                if not readers[p['ck_out']] and n.count('/') == 1:
                    dead.add(n)
            elif '/' not in n and not models[t]['state']:
                if all(not readers[p[k]] and p[k] not in outputs for k in tables[t][1]):
                    dead.add(n)
        if not dead:
            break
        removed |= dead
        for n in dead: del expected[n]
    source = mapped.read_text()
    modules = {m[1]: m for m in re.finditer(r'\bmodule\s+(\w+)\s*\((.*?)\);(.*?)\bendmodule', source, re.S)}
    top = modules['ucc_b32_pipe5']
    pattern = re.compile(r'^\s*([A-Za-z_]\w*)\s+(\\?[^\s(]+)\s*\((\s*\..*?)\);', re.S | re.M)
    pin_pattern = re.compile(r'(\.([A-Za-z_]\w*)\s*\()([^()]*)(\))')
    substitutions = {n: replace_net(n) for n in set(known) | set(aliases) if replace_net(n) != n}
    net_pattern = re.compile(r'(?<![A-Za-z0-9_$])(?:' + '|'.join(re.escape(n) for n in sorted(substitutions, key=len, reverse=True)) + r')(?![A-Za-z0-9_$])')
    def rewrite(match):
        typ, name = match[1], match[2].lstrip('\\')
        full = name + '/RC_CGIC_INST' if typ.startswith('RC_CG_MOD') else name
        if full in removed: return ''
        if typ in modules:
            ins = set()
            for m in re.finditer(r'^\s*input\s+(?:\[\d+:\d+\]\s*)?([^;]+);', modules[typ][3], re.M):
                ins.update(v.strip() for v in m[1].split(','))
        else:
            ins = {k for k, d in models[typ]['pins'].items() if d['direction'] == 'input'}
        def pin(m):
            return m[1] + (net_pattern.sub(lambda v: substitutions[v[0]], m[3]) if m[2] in ins else m[3]) + m[4]
        return pin_pattern.sub(pin, match[0])
    modified = pattern.sub(rewrite, top[0])
    out.mkdir()
    (out / 'mapped.v').write_text(source[:top.start()] + modified + source[top.end():])
    actual, actual_outputs = parse_netlist(out / 'mapped.v')
    actual = {n: (t, p) for t, n, p in actual}
    assert actual == expected and outputs == actual_outputs
    assert all(not n.startswith('b32_constant_run_') or 'history_' not in n for n in actual)
    before_ff = {n for n, (t, p) in cells.items() if t != 'ICG' and models[t]['state']}
    after_ff = {n for n, (t, p) in actual.items() if t != 'ICG' and models[t]['state']}
    assert after_ff == before_ff - histories.keys()
    files = [Path(__file__).resolve(), mapped, parent / 'models.json', parent / 'candidate.json']
    files += [c / n for c in catalogs for n in ['models.json', 'functions.json']]
    record = dict(immediate_parent=str(parent), parent_mapped_sha256=digest(mapped),
        mapped_sha256=digest(out / 'mapped.v'), run_history_removed=True,
        history_registers_removed=sorted(histories), constant_folded_nets=len(known)-2,
        removed_cells=sorted(removed), redundant_clock_gates_bypassed=bypassed,
        original_cells=len(cells), cells=len(actual), flops=len(after_ff),
        clock_gates=sum(t == 'ICG' for t,p in actual.values()),
        arithmetic_registers_preserved=True, arithmetic_pipeline_locations_unchanged=True,
        constant_folding_exact_after_disabling_optional_skip=True,
        scope='Disable all three optional five-issue detectors; exact combinational constant folding and removal of dead control follows. Existing per-instruction enables and arithmetic state remain. This is not yet a functional/timing/power qualification.',
        evidence_sha256={str(p): digest(p) for p in files})
    (out / 'candidate.json').write_text(json.dumps(record,indent=2)+'\n')
    (out / 'models.json').write_text(json.dumps(models,indent=2)+'\n')
    print('REMOVED_RUN_HISTORY',len(histories),'CELLS',len(cells),len(actual),'FLOPS',len(after_ff),'ICGS',record['clock_gates'],flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--parent',type=Path,required=True)
    p.add_argument('--catalog',action='append',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    a=p.parse_args(); run(a.parent.resolve(),[c.resolve() for c in a.catalog],a.out.resolve())
