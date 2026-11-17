#!/usr/bin/env python3
"""Adopt a sized netlist only after whole-graph and Liberty state identity checks."""
import argparse
from pathlib import Path
import shutil

from b32_clockoff_data_pin_power import checked, dump
from b32_mapped_clock_domain_cones import analyze
from b32_mapped_structural_parser import parse_netlist
from run_sm_corner import digest


def run(parent, sizing, power, out):
    assert not out.exists()
    meta, result = checked(parent / 'candidate.json'), checked(sizing / 'result.json')
    assert result['complete'] and result['source_mapped_sha256'] == meta['mapped_sha256']
    assert digest(parent / 'mapped.v') == meta['mapped_sha256']
    assert digest(sizing / 'checked.v') == result['mapped_sha256']
    changes = checked(sizing / 'master_changes.json')['resized_cells']
    rows, outputs = parse_netlist(parent / 'mapped.v')
    original = {n: (t, p) for t, n, p in rows}
    graph = analyze(sizing / 'checked.v', power / 'manifest.json', {row['before'] for row in changes.values()})
    models = graph['models']
    for name, row in changes.items():
        assert original[name][0] == row['before'] and graph['cells'][name][0] == row['after']
        assert models[row['before']] == models[row['after']], (name, row)
    expected = {n: (changes[n]['after'] if n in changes else t, pins) for n, (t, pins) in original.items()}
    assert graph['cells'] == expected and graph['outputs'] == outputs
    restored = {n: (changes[n]['before'] if n in changes else t, pins) for n, (t, pins) in expected.items()}
    assert restored == original
    assert sum('CP' in pins for t, pins in expected.values()) == 4516
    assert sum(t == 'ICG' for t, pins in expected.values()) == 170
    out.mkdir()
    shutil.copy2(sizing / 'checked.v', out / 'mapped.v')
    dump(out / 'models.json', models)
    files = [Path(__file__).resolve(), Path(__file__).with_name('b32_mapped_clock_domain_cones.py'),
             parent / 'candidate.json', parent / 'mapped.v', sizing / 'result.json',
             sizing / 'master_changes.json', power / 'manifest.json', out / 'models.json',
             out / 'mapped.v', *graph['libraries']]
    record = dict(meta)
    record.update(immediate_parent=str(parent), immediate_parent_mapped_sha256=meta['mapped_sha256'],
        mapped_sha256=result['mapped_sha256'], cells=len(expected), local_boolean_master_changes=changes,
        local_master_state_identity_proved=True, liberty_pin_and_state_functions_equal=True,
        local_boolean_master_identity_proved=False, identical_driver_functions_proved=True,
        inverse_reconstructs_parent=True, original_connectivity_unchanged=True,
        all_clock_and_register_pins_unchanged=True, added_registers=0,
        resized_cells=changes, cloned_drivers={}, final_sizing_flow=str(sizing),
        scope='All changed masters have identical actual SSG Liberty pin and state functions, including three sized flip-flops. The full flattened graph preserves every cell name, pin connection, clock, register and output; reversing masters exactly reconstructs the parent. Fresh function, physical and energy checks required.',
        evidence_sha256={str(p): digest(p) for p in files})
    dump(out / 'candidate.json', record)
    print('SIZED_GRAPH_AND_STATE_IDENTITY_PROVED', len(changes), result['cell_area_um2'], flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['parent', 'sizing', 'power', 'out']:
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    run(*(getattr(a, name).resolve() for name in ['parent', 'sizing', 'power', 'out']))
