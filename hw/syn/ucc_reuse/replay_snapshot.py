#!/usr/bin/env python3
"""Recheck published timing or regenerate a checked Joules operation waveform."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

from check_snapshot import digest, verify


def run(root, out, operation, timing, xrun, genus, joules):
    manifest = verify(root)
    assert not out.exists()
    env = dict(os.environ)
    out.mkdir(parents=True)
    if timing:
        for name in ['timing.tcl', 'flow.tcl', 'mmmc.tcl', 'dpa.sdc', 'cuda.sdc']:
            shutil.copy2(root / 'timing' / name, out / name)
        shutil.copytree(root / 'timing/reference', out / 'reference')
        shutil.copy2(root / 'implementation/mapped.v', out / 'input.v')
        measured = json.loads((root / 'timing/result.json').read_text())
        checkpoint = json.loads((root / 'provenance/checkpoint.json').read_text())
        env.update(UCC_RUN_DIR=str(out), UCC_EXPECTED_CELLS=str(measured['cell_count']),
                   UCC_EXPECTED_ICGS=str(checkpoint['clock_gates']))
        with (out / 'driver.log').open('w') as log:
            subprocess.run([genus, '-batch', '-files', 'timing.tcl', '-log', 'genus'],
                           cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        assert (out / 'complete.txt').exists()
        print('TIMING_IMPORT_COMPLETE', out)
        return
    streams = json.loads((root / 'power/streams.json').read_text())
    selected = streams[operation]
    source = root / 'power' / operation
    for name in ['tb.sv', 'vectors.txt', 'power.tcl', 'power.sdc', 'libraries_power.tcl']:
        shutil.copy2(source / name, out / name)
    shutil.copy2(root / 'implementation/mapped.v', out / 'mapped.v')
    models = json.loads((root / 'validation/cell_models.json').read_text())
    for name, sha in models.items():
        assert digest(Path(name)) == sha, name
    vcd = selected['operation'] + '.vcd'
    command = [xrun, '-64bit', '-sv', '-access', '+rwc', '-timescale', '1ps/1ps',
               '-top', 'tb', 'mapped.v', 'tb.sv', '-sequdp_nba_delay', '+delay_mode_zero']
    for name in models:
        command += ['-v', name]
    command += ['+vectors=vectors.txt', '+vcd=' + vcd, '+mode=' + str(selected['dpa_mode'])]
    with (out / 'simulation.log').open('w') as log:
        subprocess.run(command, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    text = (out / 'simulation.log').read_text()
    assert 'ENERGY_SIM_DONE' in text and 'mismatches=0' in text
    assert 'WINDOW_START 109000' in text and 'WINDOW_END 1109000' in text
    assert '*E,' not in text and '*F,' not in text
    with (out / 'joules.log').open('w') as log:
        subprocess.run([joules, '-common_ui', '-batch', '-overwrite', '-files',
                        'power.tcl', '-log', 'power.log'], cwd=out, env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    assert 'ENERGY_POWER_DONE' in (out / 'joules.log').read_text()
    result = dict(operation=operation, complete=True, mapped_sha256=manifest['mapped_sha256'],
                  original_vcd_sha256=selected['vcd_sha256'], regenerated_vcd_sha256=digest(out / vcd),
                  window_ps=selected['window_ps'], gate_checked=True,
                  power_report=str(out / 'power.rpt'), annotation_report=str(out / 'annotation.rpt'))
    (out / 'replay.json').write_text(json.dumps(result, indent=2) + '\n')
    print('POWER_REPLAY_COMPLETE', operation, out)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--timing', action='store_true')
    group.add_argument('--operation')
    parser.add_argument('--xrun', default=os.environ.get('XRUN', 'xrun'))
    parser.add_argument('--genus', default=os.environ.get('GENUS', 'genus'))
    parser.add_argument('--joules', default=os.environ.get('JOULES', 'joules'))
    args = parser.parse_args()
    run(args.snapshot.resolve(), args.out.resolve(), args.operation, args.timing,
        args.xrun, args.genus, args.joules)
