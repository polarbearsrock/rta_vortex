#!/usr/bin/env python3
"""Gate proven constant register banks after five matching issue cycles."""
import argparse
from collections import defaultdict
import itertools
import json
from pathlib import Path
import re

from b32_clockoff_data_pin_power import checked, dump
from b32_combinational_mapped_pin_support import truth_tables
from b32_mapped_clock_domain_cones import analyze
from b32_mapped_structural_parser import parse_netlist
from run_sm_corner import digest


TYPES = ['AN2D1BWP30P140LVT', 'OR2D1BWP30P140LVT', 'INVD1BWP30P140LVT',
         'XOR2D1BWP30P140LVT', 'DFQD1BWP30P140LVT', 'INVD0BWP30P140LVT', 'INVD2BWP30P140LVT', 'BUFFD4BWP30P140LVT']
OPS = [('fma32', 0x60), ('mul32', 0x20), ('sfu_ex2', 0x7a)]


def run(parent, proof, screen, power, out):
    assert not out.exists()
    meta = checked(parent / 'candidate.json')
    proven = checked(proof / 'result.json')
    assert proven['mapped_sha256'] == digest(power / 'mapped.v')
    assert meta['immediate_parent_mapped_sha256'] == proven['mapped_sha256']
    assert meta['inverse_reconstructs_parent'] and meta['liberty_pin_and_state_functions_equal']
    assert meta['identical_driver_functions_proved']
    graph = analyze(parent / 'mapped.v', power / 'manifest.json', TYPES)
    cells, models = graph['cells'], graph['models']
    old_cells = {n: (t, p) for t, n, p in parse_netlist(power / 'mapped.v')[0]}
    registers = defaultdict(dict)
    for op, opcode in OPS:
        p = checked(proof / (op + '.json'))
        stages = p['stages']
        assert p['opcode'] == opcode and p['initial_state'] == 'arbitrary'
        assert stages[-1]['constant_states'] == stages[-1]['next_constant_states']
        for stage in stages:
            domain = stage['warmup_domain']
            warm = sorted(n for n in old_cells if re.fullmatch(r'b32_gate_warmup_reg\[\d+\]', n))
            for row in domain:
                assert all(n not in stage['constant_states'] or stage['constant_states'][n] == v for n, v in zip(warm, row))
        for name, row in stages[5]['safe_constant_captures'].items():
            assert all(s['safe_constant_captures'].get(name, {}).get('value') == row['value'] for s in stages[5:])
            assert cells[name] == old_cells[name]
            registers[name][op] = row
    banks = defaultdict(list)
    for name, contexts in registers.items():
        gates = {r['original_gate'] for r in contexts.values()}
        assert len(gates) == 1
        banks[next(iter(gates)), tuple(contexts)].append(name)
    chosen = [dict(original_gate=gate, operations=list(ops), registers=sorted(names),
                   upper_register_energy_pj=sum(registers[n][op]['register_dynamic_pj'] for n in names for op in ops))
              for (gate, ops), names in sorted(banks.items()) if len(names) >= 4]
    assert len(chosen) == 19 and sum(len(r['registers']) for r in chosen) == 256
    assert models['DFQD1BWP30P140LVT']['state'] == {'clocked_on': 'CP', 'next_state': 'D'}
    assert models['DFQD1BWP30P140LVT']['pins']['Q']['function'] == 'IQ'
    tables = truth_tables(json.loads((screen / 'functions.json').read_text())['modules'])
    funcs = {'AN2D1BWP30P140LVT': lambda v: v['A1'] & v['A2'],
             'OR2D1BWP30P140LVT': lambda v: v['A1'] | v['A2'],
             'INVD1BWP30P140LVT': lambda v: 1 - v['I'],
             'XOR2D1BWP30P140LVT': lambda v: v['A1'] ^ v['A2']}
    for typ in ['INVD0BWP30P140LVT', 'INVD2BWP30P140LVT', 'BUFFD4BWP30P140LVT']:
        functions = [p['function'] for p in models[typ]['pins'].values() if p['direction'] == 'output']
        assert len(functions) == 1 and re.sub(r'[()\s]', '', functions[0]) == ('I' if typ.startswith('BUFF') else '!I')
    for typ, fn in funcs.items():
        ins, outputs = tables[typ]
        assert len(outputs) == 1
        truth = next(iter(outputs.values()))
        assert all((truth >> r & 1) == fn({p: r >> i & 1 for i, p in enumerate(ins)}) for r in range(1 << len(ins)))
    for bits in itertools.product([0, 1], repeat=5):
        for reset, match in [(0, 0), (1, 0), (1, 1)]:
            enable = (not reset) or any(b != match for b in bits)
            next_bits = (match, *bits[:-1]) if reset else (0,) * 5
            assert (next_bits if enable else bits) == next_bits
    added, wires = [], set()
    prefix = 'b32_constant_run_'
    assert not any(n.startswith(prefix) for n in cells)
    def add(typ, tag, pins, output='Z'):
        name = prefix + tag
        net = name + '_net'
        assert name not in cells and net not in wires
        wires.add(net)
        added.append((typ, name, dict(pins, **{output: net})))
        return net
    def inv(net, tag):
        return add('INVD1BWP30P140LVT', tag, dict(I=net), 'ZN')
    def tree(inputs, kind, tag):
        work, level = list(inputs), 0
        assert work
        while len(work) > 1:
            following = []
            for i in range(0, len(work), 2):
                if i + 1 == len(work):
                    following.append(work[i])
                else:
                    following.append(add(kind, f'{tag}_{level}_{i//2}', dict(A1=work[i], A2=work[i+1])))
            work, level = following, level + 1
        return work[0]
    def icg(tag, enable, clock):
        name = prefix + tag
        net = name + '_clock'
        wires.add(net)
        added.append(('ICG', name + '/RC_CGIC_INST', dict(enable=enable, ck_in=clock, ck_out=net, test="1'b0")))
        return net
    aliases = {f'op_i[{i}]': (f'op_i[{i}]', 0, []) for i in range(7)}
    aliases['valid_i'] = ('valid_i', 0, [])
    while True:
        changed = False
        for name, (typ, pins) in cells.items():
            if set(pins) not in [{'I', 'Z'}, {'I', 'ZN'}] or pins['I'] not in aliases:
                continue
            output = next(pin for pin in pins if pin != 'I')
            function = re.sub(r'[()\s]', '', models[typ]['pins'][output]['function'])
            if function not in ['I', '!I'] or pins[output] in aliases:
                continue
            source, polarity, chain = aliases[pins['I']]
            aliases[pins[output]] = (source, polarity ^ (function == '!I'), chain + [name])
            changed = True
        if not changed:
            break
    selected_taps = ['n_39575', 'n_18278', 'n_6551', 'n_9213', 'n_5969', 'n_47182', 'n_3428', 'n_8973']
    tap_proofs = {}
    def isolated_tap(net, source, tag):
        actual_source, polarity, chain = aliases[net]
        assert actual_source == source and chain
        first = add('INVD0BWP30P140LVT', tag + '_isolate', dict(I=net), 'ZN')
        second = add('INVD2BWP30P140LVT', tag + '_drive', dict(I=first), 'ZN')
        third = add('INVD2BWP30P140LVT', tag + '_opposite', dict(I=second), 'ZN')
        tap_proofs[source] = dict(net=net, polarity=polarity, unary_identity_chain=chain)
        return (third, second) if polarity else (second, third)
    true_opcode, not_opcode = [], []
    for i, net in enumerate(selected_taps[:7]):
        pos, neg = isolated_tap(net, f'op_i[{i}]', f'op_{i}')
        true_opcode.append(pos)
        not_opcode.append(neg)
    valid, unused_negative_valid = isolated_tap(selected_taps[7], 'valid_i', 'valid')
    reset = add('BUFFD4BWP30P140LVT', 'reset_buffer', dict(I='rst_ni'))
    not_reset = inv(reset, 'not_reset')
    not_mode = inv('dpa_mode_i', 'not_tensor')
    common = tree([reset, valid, not_mode], 'AN2D1BWP30P140LVT', 'eligible')
    events, history_banks = {}, []
    for op, opcode in OPS:
        match = tree([common] + [true_opcode[i] if opcode >> i & 1 else not_opcode[i] for i in range(7)], 'AN2D1BWP30P140LVT', op + '_match')
        history = [prefix + op + '_history_' + str(i) + '_q' for i in range(5)]
        wires.update(history)
        mismatches = [add('XOR2D1BWP30P140LVT', op + '_mismatch_' + str(i), dict(A1=match, A2=q)) for i, q in enumerate(history)]
        enable = tree([not_reset] + mismatches, 'OR2D1BWP30P140LVT', op + '_history_enable')
        clock = icg(op + '_history_gate', enable, 'clk_i')
        for i, q in enumerate(history):
            data = match if i == 0 else add('AN2D1BWP30P140LVT', op + '_history_reset_' + str(i), dict(A1=reset, A2=history[i-1]))
            added.append(('DFQD1BWP30P140LVT', prefix + op + '_history_' + str(i), dict(D=data, CP=clock, Q=q)))
        events[op] = tree([match] + history, 'AN2D1BWP30P140LVT', op + '_event')
        history_banks.append(dict(operation=op, opcode=opcode, current_match=match, history=history, clock=clock, enable=enable, event=events[op]))
    changes = {}
    allow_by_set = {}
    for i, bank in enumerate(chosen):
        ops = tuple(bank['operations'])
        if ops not in allow_by_set:
            skip = tree([events[op] for op in ops], 'OR2D1BWP30P140LVT', 'skip_' + str(i))
            allow_by_set[ops] = inv(skip, 'allow_' + str(i))
        allow = allow_by_set[ops]
        original_clock = graph['gates'][bank['original_gate']]['ck_out']
        clock = icg('capture_' + str(i), allow, original_clock)
        bank.update(clock=clock, allow=allow)
        for name in bank['registers']:
            assert name not in changes and cells[name][1]['CP'] == original_clock
            changes[name] = dict(before=original_clock, after=clock)
    source = (parent / 'mapped.v').read_text()
    top = re.search(r'\bmodule ucc_b32_pipe5\b.*?\bendmodule', source, re.S)
    assert top
    edited = set()
    def rewrite(match):
        name = match[2].lstrip('\\')
        text = match[0]
        if name in changes:
            text, count = re.subn(r'(\.CP\s*\()\s*[^()]*?(\))', lambda m: m[1] + changes[name]['after'] + m[2], text)
            assert count == 1
            edited.add(name)
        return text
    rewritten = re.sub(r'^\s*([A-Za-z_]\w*)\s+(\\?[^\s(]+)\s*\(\s*\.[\s\S]*?\);', rewrite, top[0], flags=re.M)
    assert edited == set(changes)
    decl = '\n  wire ' + ', '.join(sorted(wires)) + ';\n'
    instances = []
    for typ, name, pins in added:
        if typ == 'ICG':
            typ, name = 'RC_CG_MOD', name.removesuffix('/RC_CGIC_INST')
        instances.append('  ' + typ + ' ' + name + '(' + ', '.join('.' + pin + '(' + net + ')' for pin, net in pins.items()) + ');')
    header_end = rewritten.index(');') + 2
    rewritten = rewritten[:header_end] + decl + rewritten[header_end:]
    rewritten = rewritten.replace('endmodule', '\n'.join(instances) + '\nendmodule')
    rewritten = source[:top.start()] + rewritten + source[top.end():]
    out.mkdir()
    (out / 'mapped.v').write_text(rewritten)
    actual, outputs = parse_netlist(out / 'mapped.v')
    expected = {n: (t, dict(p)) for n, (t, p) in cells.items()}
    for n, change in changes.items():
        expected[n][1]['CP'] = change['after']
    expected.update({n: (t, p) for t, n, p in added})
    assert {n: (t, p) for t, n, p in actual} == expected and outputs == graph['outputs']
    inverse = {n: (t, dict(p)) for n, (t, p) in expected.items() if n in cells}
    for n, change in changes.items():
        inverse[n][1]['CP'] = change['before']
    assert inverse == cells
    files = [Path(__file__).resolve(), parent / 'candidate.json', parent / 'mapped.v', proof / 'result.json', screen / 'functions.json',
             screen / 'result.json', power / 'manifest.json', out / 'mapped.v', *graph['libraries']]
    files += [proof / (op + '.json') for op, _ in OPS]
    record = dict(parent_power=str(power), immediate_parent=str(parent), parent_mapped_sha256=digest(parent / 'mapped.v'),
        mapped_sha256=digest(out / 'mapped.v'), cells=len(actual), added_registers=15, added_clock_gates=22,
        modified_register_clocks=len(changes), original_data_logic_and_pins_unchanged=True,
        inverse_reconstructs_parent=True, selected_changed=False, objective_complete=False,
        numerical_and_latency_contract_unchanged=True, history_banks=history_banks, banks=chosen, control_input_taps=tap_proofs,
        temporal_capture_proof=dict(passed=True, arbitrary_initial_reference_state=True, arbitrary_operand_values_each_cycle=True,
            prior_matching_issues=5, current_matching_issue_required=True, abstract_fixed_point_checked=True,
            controller_skip_identity_exhaustive=True, actual_library_primitive_functions_checked=True,
            clock_waveform_check_pending=True, physical_timing_pending=True,
            scope='Induction composition of constant next-state cofactors, matching-issue history and preserved original data graph; not whole-netlist sequential formal equivalence.'),
        evidence_sha256={str(p): digest(p) for p in files})
    dump(out / 'candidate.json', record)
    print('TEMPORAL_CAPTURE_MAPPING_PREPARED', len(actual), len(changes), len(added), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['parent', 'proof', 'screen', 'power', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    run(*(getattr(args, n).resolve() for n in ['parent', 'proof', 'screen', 'power', 'out']))
