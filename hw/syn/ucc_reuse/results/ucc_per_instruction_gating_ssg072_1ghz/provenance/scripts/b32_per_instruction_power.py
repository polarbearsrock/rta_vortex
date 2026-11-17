#!/usr/bin/env python3
"""Measure per-instruction gating after removal of fixed-opcode run detectors."""
import argparse
import copy
import json
import re
from pathlib import Path
import shutil

import b32_power
from b32_sfu_truncated_power import validate_power_oracle
from run_sm_corner import digest


def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def checked(path):
    value = json.loads(path.read_text())
    for name, sha in value.get('evidence_sha256', {}).items():
        assert digest(Path(name)) == sha, name
    return value


def run(candidate, check, parent, timing, contract, out):
    assert not out.exists()
    record = checked(candidate / 'candidate.json')
    verified = checked(check / 'result.json')
    measured = checked(timing / 'result.json')
    assert record['run_history_removed'] and len(record['history_registers_removed']) == 15
    assert record['arithmetic_registers_preserved']
    assert record['constant_folding_exact_after_disabling_optional_skip']
    assert verified['passed'] and verified['gate_replay'] and verified['checks'] >= 143744
    assert measured['complete'] and not measured['optimization_performed']
    assert record['mapped_sha256'] == verified['mapped_sha256'] == measured['mapped_sha256'] == digest(candidate / 'mapped.v')
    original = json.loads((parent / 'manifest.json').read_text())
    assert digest(parent / 'mapped.v') == record['parent_mapped_sha256']
    workloads = ['fma32', 'add32', 'mul32', 'sfu_ex2']
    assert set(workloads) <= set(original['workloads'])
    out.mkdir(parents=True)
    for name, sha in original['files'].items():
        assert digest(parent / name) == sha, name
        shutil.copy2(candidate / name if name == 'mapped.v' else parent / name, out / name)
    manifest = copy.deepcopy(original)
    manifest.update(synthesis=str(candidate), parent_synthesis=original['synthesis'],
                    created_utc=b32_power.now(), workloads=workloads,
                    gate_simulation={}, results={},
                    files={name: digest(out / name) for name in original['files']},
                    timing_unmeasured=False, final_goal_accepted=False,
                    reference_rtl_only=True,
                    scope='Fixed-opcode run detectors removed; existing per-instruction pipeline gating retained. Native RTL is reference; '
                          'only mapped.v changes. Timing is measured separately without optimization.',
                    mapped_candidate_validation=dict(candidate=str(candidate / 'candidate.json'),
                                                     gate_check=str(check / 'result.json')),
                    mapped_eco_measurement=dict(parent_power=str(parent),
                                               parent_manifest_sha256=digest(parent / 'manifest.json'),
                                               unchanged_testbench_vectors_constraints=True,
                                               synthesis_launched=False),
                    preparation_driver_sha256=digest(Path(__file__).resolve()))
    manifest.pop('execution_driver_sha256', None)
    dump(out / 'manifest.json', manifest)
    validate_power_oracle(out)
    from b32_fixed_four_power_flow import compare_inputs
    limits = checked(contract)
    compare_inputs(out, limits)
    b32_power.execute(out)
    prior = json.loads((parent / 'energy.json').read_text())['workloads']
    energy = json.loads((out / 'energy.json').read_text())['workloads']
    rows = {}
    for op in workloads:
        actual, old = energy[op], prior[op]
        assert actual['cells'] == record['cells'] == measured['cell_count']
        assert (actual['window_ps'], actual['operations']) == (old['window_ps'], old['operations'])
        rows[op] = dict(dynamic_pj_per_op=actual['dynamic_pj_per_op'],
                        parent_dynamic_pj_per_op=old['dynamic_pj_per_op'],
                        leakage_mw=actual['leakage_mw'], parent_leakage_mw=old['leakage_mw'],
                        dynamic_ratio_to_parent=actual['dynamic_pj_per_op'] / old['dynamic_pj_per_op'])
    files = [Path(__file__).resolve(), candidate / 'candidate.json', check / 'result.json',
             timing / 'result.json', contract, parent / 'manifest.json', parent / 'energy.json',
             out / 'manifest.json', out / 'status.json', out / 'energy.json']
    files += [out / f'power_{op}' / 'result.json' for op in workloads]
    total = sum(r['dynamic_pj_per_op'] for r in rows.values())
    groups = {}
    for mode in ['dpa', 'cuda']:
        found = {}
        for line in (timing / ('qor_' + mode + '.rpt')).read_text().splitlines():
            m = re.fullmatch(r'\s*(?:(\w+\.SS\.setup_view)\s+)?(\w+)\s+(No paths|[-\d.]+)\s+([-\d.]+)\s+(\d+)\s*', line)
            if m:
                found[m[2]] = dict(wns_ps=None if m[3]=='No paths' else float(m[3]), tns_ps=float(m[4]), violations=int(m[5]))
        assert set(found)=={'clk','cg_enable_group_clk','default'}
        groups[mode]=found
    result = dict(complete=True, operations=rows, fixed_four_sum_pj=total,
                  cuda_ratio=total / sum(limits['baseline_total_pj_per_op'][op] for op in workloads),
                  setup_groups=groups, run_history_removed=True,
                  synthesis_launched=False, selected_changed=False, objective_complete=False,
                  cell_count=record['cells'], cell_area_um2=measured['cell_area_um2'],
                  worst_slack_ps=measured['worst_slack_ps'], drv_violation_rows=measured['drv_violation_rows'],
                  scope='Fresh Joules on unchanged fixed-operation vectors. Dynamic energy excludes leakage. '
                        'No selection or qualification inferred from local screening or energy alone.',
                  evidence_sha256={str(p): digest(p) for p in files})
    dump(out / 'comparison.json', result)
    print('PER_INSTRUCTION_POWER_COMPLETE', json.dumps({k: v for k, v in result.items() if k != 'evidence_sha256'}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['candidate', 'check', 'parent', 'timing', 'contract', 'out']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    run(*(getattr(args, name).resolve() for name in ['candidate', 'check', 'parent', 'timing', 'contract', 'out']))
