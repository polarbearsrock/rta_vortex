#!/usr/bin/env python3
"""Prove constant captures after finite homogeneous issue runs from arbitrary state."""
import argparse
from collections import defaultdict, deque
from functools import lru_cache
import itertools
import json
from pathlib import Path
import re

from b32_clockoff_data_pin_power import checked, dump
from b32_combinational_mapped_pin_support import truth_tables
from b32_mapped_constant_capture_screen import state_value
from b32_mapped_structural_parser import parse_netlist, load_power
from run_sm_corner import digest


def run(screen, power, profiles, out):
    assert not out.exists()
    checked(screen / 'result.json')
    manifest = json.loads((power / 'manifest.json').read_text())
    assert digest(power / 'mapped.v') == manifest['files']['mapped.v']
    models = json.loads((screen / 'models.json').read_text())
    tables = truth_tables(json.loads((screen / 'functions.json').read_text())['modules'])
    rows, _ = parse_netlist(power / 'mapped.v')
    cells = {n: (t, p) for t, n, p in rows}
    gates = {n: p for n, (t, p) in cells.items() if t == 'ICG'}
    clocks = {p['ck_out']: n for n, p in gates.items()}
    root_clocks = {p['ck_in'] for p in gates.values()}
    assert root_clocks == {'clk_i'}
    seq = {n: (t, p) for n, (t, p) in cells.items() if t != 'ICG' and models[t]['state']}
    comb = {n: (t, p) for n, (t, p) in cells.items() if t != 'ICG' and not models[t]['state']}
    readers = defaultdict(set)
    for n, (t, p) in comb.items():
        for pin in tables[t][0]:
            readers[p[pin]].add(n)
    for n, (t, p) in seq.items():
        assert models[t]['state']['clocked_on'] == 'CP'
        assert p['CP'] in root_clocks or p['CP'] in clocks
        assert models[t]['pins']['Q']['function'] == 'IQ'
        assert set(models[t]['state']) == {'next_state', 'clocked_on'}

    @lru_cache(None)
    def restrict(t, pin, values):
        inputs, outputs = tables[t]
        truth = outputs[pin]
        possible = {truth >> r & 1 for r in range(1 << len(inputs))
                    if all(v is None or (r >> i & 1) == v for i, v in enumerate(values))}
        return possible.pop() if len(possible) == 1 else None

    @lru_cache(None)
    def state_constant(expression, assignment):
        values = dict(assignment)
        unknown = [k for k, v in assignment if v is None]
        possible = {state_value(expression, values | dict(zip(unknown, bits)))
                    for bits in itertools.product([0, 1], repeat=len(unknown))}
        return possible.pop() if len(possible) == 1 else None

    drivers, state_outputs = {}, {}
    for name, (typ, pins) in cells.items():
        if typ == 'ICG':
            continue
        for pin, info in models[typ]['pins'].items():
            if info['direction'] != 'output':
                continue
            if models[typ]['state']:
                assert info['function'] in ('IQ', 'IQN')
                state_outputs[pins[pin]] = (name, info['function'] == 'IQN')
            else:
                drivers[pins[pin]] = (name, pin)
    banks = {}
    for tag, pattern in [('warmup', r'b32_gate_warmup_reg\[\d+\]')] + [
            ('op' + str(i), r'b32_gate_op_q' + str(i) + r'_reg\[\d+\]') for i in range(1, 6)]:
        bank = sorted(n for n in seq if re.fullmatch(pattern, n))
        assert len(bank) == (3 if tag == 'warmup' else 7)
        banks[tag] = bank

    def refine(inputs, current, warm_domain):
        proved, records, new_warm_domain = {}, {}, set()
        for tag, bank in banks.items():
            unknown = [n for n in bank if n not in current]
            assignments = [dict(zip(bank, bits)) for bits in warm_domain] if tag == 'warmup' else [
                {n: current[n] for n in bank if n in current} | dict(zip(unknown, bits))
                for bits in itertools.product([0, 1], repeat=len(unknown))]
            values = {n: set() for n in bank}
            for assignment in assignments:
                fixed = current | assignment
                @lru_cache(None)
                def evaluate(net):
                    if net.startswith("1'b"):
                        return int(net[-1])
                    if net in inputs:
                        return inputs[net]
                    if net in state_outputs:
                        name, inv = state_outputs[net]
                        value = fixed.get(name)
                        return None if value is None else value ^ inv
                    if net not in drivers:
                        return None
                    name, pin = drivers[net]
                    typ, pins = comb[name]
                    return restrict(typ, pin, tuple(evaluate(pins[p]) for p in tables[typ][0]))
                outputs = {}
                for n in bank:
                    typ, pins = seq[n]
                    expression = models[typ]['state']['next_state']
                    variables = sorted(set(re.findall(r'[A-Za-z_]\w*', expression)))
                    data = state_constant(expression, tuple((v, fixed.get(n) if v == 'IQ' else evaluate(pins[v])) for v in variables))
                    gate = clocks.get(pins['CP'])
                    en = 1 if gate is None else (1 if evaluate(gates[gate]['enable']) == 1 else 0 if evaluate(gates[gate]['enable']) == 0 else None)
                    assert gate is None or gates[gate]['test'] == "1'b0"
                    value = fixed.get(n) if en == 0 else data if en == 1 else data if data == fixed.get(n) else None
                    outputs[n] = value
                    values[n].add(value)
                if tag == 'warmup':
                    missing = [n for n in bank if outputs[n] is None]
                    for bits in itertools.product([0, 1], repeat=len(missing)):
                        row = outputs | dict(zip(missing, bits))
                        new_warm_domain.add(tuple(row[n] for n in bank))
            for n, possible in values.items():
                if len(possible) == 1 and None not in possible:
                    proved[n] = next(iter(possible))
            records[tag] = dict(enumerated_current_states=len(assignments),
                                proved_next_constants={n: proved[n] for n in bank if n in proved})
        return proved, records, new_warm_domain

    out.mkdir()
    operations = {}
    evidence = [Path(__file__).resolve(), screen / 'result.json', screen / 'models.json',
                screen / 'functions.json', power / 'manifest.json', power / 'mapped.v']
    for op, opcode in [('fma32', 0x60), ('add32', 0), ('mul32', 0x20), ('sfu_ex2', 0x7a)]:
        prof = checked(profiles / op / 'result.json')
        assert prof['reports']['leaf.rpt'] == digest(profiles / op / 'leaf.rpt')
        energy = load_power(profiles / op / 'leaf.rpt')
        inputs = dict(rst_ni=1, dpa_mode_i=0, valid_i=1)
        inputs.update({f'op_i[{i}]': opcode >> i & 1 for i in range(7)})
        state = {}
        warm_domain = set(itertools.product([0, 1], repeat=3))
        stages = []
        for age in range(13):
            known = {"1'b0": 0, "1'b1": 1} | inputs
            for n, value in state.items():
                typ, pins = seq[n]
                known[pins['Q']] = value
                if 'QN' in pins:
                    assert models[typ]['pins']['QN']['function'] == 'IQN'
                    known[pins['QN']] = 1 - value
            pending = deque(sorted(comb))
            queued = set(comb)
            while pending:
                n = pending.popleft()
                queued.remove(n)
                typ, pins = comb[n]
                ins, outs = tables[typ]
                context = tuple(known.get(pins[p]) for p in ins)
                for pin in outs:
                    value = restrict(typ, pin, context)
                    if value is None:
                        continue
                    net = pins[pin]
                    if net in known:
                        assert known[net] == value
                        continue
                    known[net] = value
                    for r in readers[net]:
                        if r not in queued:
                            pending.append(r)
                            queued.add(r)
            next_state, captures, enabled = {}, {}, {}
            for n, (typ, pins) in seq.items():
                expression = models[typ]['state']['next_state']
                variables = sorted(set(re.findall(r'[A-Za-z_]\w*', expression)))
                values = tuple((v, state.get(n) if v == 'IQ' else known.get(pins[v])) for v in variables)
                next_value = state_constant(expression, values)
                gate = clocks.get(pins['CP'])
                enable = 1 if gate is None else (1 if known.get(gates[gate]['enable']) == 1 or known.get(gates[gate]['test']) == 1 else 0 if known.get(gates[gate]['enable']) == known.get(gates[gate]['test']) == 0 else None)
                enabled[n] = enable
                if enable == 0:
                    if n in state:
                        next_state[n] = state[n]
                elif enable == 1:
                    if next_value is not None:
                        next_state[n] = next_value
                elif n in state and next_value == state[n]:
                    next_state[n] = state[n]
                if gate is not None and enable == 1 and n in state and next_value == state[n]:
                    captures[n] = dict(value=state[n], original_gate=gate, register_dynamic_pj=sum(energy[n]))
            refined, control_proof, next_warm_domain = refine(inputs, state, warm_domain)
            assert all(n not in next_state or next_state[n] == v for n, v in refined.items())
            next_state.update(refined)
            stages.append(dict(prior_matching_issues=age, constant_states=state,
                               control_cofactor_proof=control_proof, warmup_domain=sorted(warm_domain),
                               safe_constant_captures=captures, next_constant_states=next_state,
                               upper_dynamic_pj=sum(r['register_dynamic_pj'] for r in captures.values())))
            state = next_state
            warm_domain = next_warm_domain
        dump(out / (op + '.json'), dict(opcode=opcode, forced_current_inputs=inputs,
                                       initial_state='arbitrary', stages=stages))
        operations[op] = dict(opcode=opcode, stages=[{k: v for k, v in s.items() if k not in ['constant_states', 'next_constant_states', 'safe_constant_captures', 'control_cofactor_proof', 'warmup_domain']} | dict(bits=len(s['safe_constant_captures'])) for s in stages])
        evidence += [profiles / op / 'result.json', profiles / op / 'leaf.rpt', out / (op + '.json')]
        print('TEMPORAL_CONSTANTS', op, [(s['prior_matching_issues'], len(s['safe_constant_captures']), round(s['upper_dynamic_pj'], 6)) for s in stages], flush=True)
    dump(out / 'result.json', dict(complete=True, operations=operations, mapped_sha256=digest(power / 'mapped.v'),
        scope='Exhaustive local Boolean/next-state abstraction plus exact control-bank cofactors and a correlated 3-bit warmup domain; arbitrary initial registers and arbitrary operands each cycle. '
              'A capture is safe only under the full consecutive issue context and a matching current issue. '
              'No gate implementation, clock waveform proof or energy saving is claimed.',
        evidence_sha256={str(p): digest(p) for p in evidence}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['screen', 'power', 'profiles', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    run(*(getattr(args, n).resolve() for n in ['screen', 'power', 'profiles', 'out']))
