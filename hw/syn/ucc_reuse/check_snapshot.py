#!/usr/bin/env python3
"""Verify a published snapshot or replay its unchanged mixed-operation bench."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root):
    manifest = json.loads((root / 'package_manifest.json').read_text())
    for name, expected in manifest['files'].items():
        assert digest(root / name) == expected, name
    for name, entry in json.loads((root / 'source_archive.json').read_text()).items():
        data = (root / name).read_bytes()
        if entry['compression'] == 'gzip':
            data = gzip.decompress(data)
        assert hashlib.sha256(data).hexdigest() == entry['source_sha256'], name
    mapped_sha = digest(root / 'implementation/mapped.v')
    assert mapped_sha == manifest['mapped_sha256']
    check = json.loads((root / 'validation/result.json').read_text())
    assert check['mapped_sha256'] == mapped_sha and check['passed']
    assert check['checks'] == 144656 and check['additional_hot_mul_resets'] == 16
    energy = json.loads((root / 'provenance/scalar_comparison.json').read_text())
    contract = json.loads((root / 'provenance/contract.json').read_text())
    ops = contract['scalar_equal_weight_streams']
    ratio = sum(energy['operations'][op]['dynamic_pj_per_op'] for op in ops) / sum(
        contract['baseline_total_pj_per_op'][op] for op in ops)
    assert abs(ratio - energy['cuda_ratio']) < 1e-12
    if manifest.get('goal_complete'):
        checkpoint = json.loads((root / 'provenance/checkpoint.json').read_text())
        tensor = json.loads((root / 'provenance/dpa_result.json').read_text())
        timing = json.loads((root / 'timing/result.json').read_text())
        reset = json.loads((root / 'validation/reset_entry/result.json').read_text())
        assert checkpoint['goal_complete'] and checkpoint['run_history_removed']
        assert checkpoint['mapped_sha256'] == timing['mapped_sha256'] == reset['mapped_sha256'] == mapped_sha
        assert checkpoint['cell_area_um2'] == timing['cell_area_um2'] < contract['area_limit_um2']
        assert ratio < contract['strict_ratio_limit'] and not checkpoint['retiming']
        assert reset['passed'] and reset['reset_cases'] == 2560
        assert all(g['violations'] == 0 and (g['wns_ps'] is None or g['wns_ps'] >= 0)
                   for row in checkpoint['setup_groups'].values() for g in row.values())
        assert all(n == 0 for row in timing['drv_violation_rows'].values() for n in row.values())
        assert set(tensor['rows']) == set(contract['required_dpa_streams'])
        assert all(r['ratio'] < 1.05 for r in tensor['rows'].values())
    print('SNAPSHOT_VERIFIED', root.name, len(manifest['files']),
          'files; CUDA ratio', ratio, flush=True)
    return manifest


def replay(root, out, xrun, cell_models):
    verify(root)
    assert not out.exists(), out
    recorded = json.loads((root / 'validation/cell_models.json').read_text())
    models = cell_models or [Path(name) for name in recorded]
    assert models and all(path.is_file() for path in models)
    if not cell_models:
        for path in models:
            assert digest(path) == recorded[str(path)], path
    out.mkdir(parents=True)
    for name in ['bench.sv', 'reference.sv']:
        shutil.copy2(root / 'validation' / name, out / name)
    (out / 'vectors.txt').write_bytes(gzip.decompress((root / 'validation/vectors.txt.gz').read_bytes()))
    command = [xrun, '-64bit', '-sv', '-timescale', '1ns/1ps', '-top',
               'b32_schedule_tb', '-sequdp_nba_delay', '+delay_mode_zero',
               str(root / 'implementation/mapped.v'), 'reference.sv', 'bench.sv',
               '+NORMAL_AFTER_SFU_MASK=2', '+SFU_AFTER_NORMAL_MASK=0']
    for path in models:
        command += ['-v', str(path.resolve())]
    with (out / 'run.log').open('w') as log:
        subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT, check=True)
    log = (out / 'run.log').read_text()
    assert 'SCHEDULE_PASS' in log and '*E,' not in log and '*F,' not in log
    print(next(line for line in log.splitlines() if 'SCHEDULE_PASS' in line))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--replay-out', type=Path)
    parser.add_argument('--xrun', default=os.environ.get('XRUN', 'xrun'))
    parser.add_argument('--cell-model', action='append', type=Path)
    args = parser.parse_args()
    if args.replay_out:
        replay(args.snapshot.resolve(), args.replay_out.resolve(), args.xrun, args.cell_model)
    else:
        verify(args.snapshot.resolve())
