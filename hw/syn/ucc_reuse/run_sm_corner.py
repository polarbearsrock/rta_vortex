#!/usr/bin/env python3
"""Re-synthesize frozen UCC RTL with the Vortex SM SDC and three MMMC views."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
SM = Path('/data2/jwang710/RTA_code/vortex_syn/fpu')
LIBS = Path('/data/eda_tools/script/pnr/tsmcn28/flow/setup/tsmcn28_libs.tcl')
GENUS = Path('/data/eda_tools/cadence/DDI251/GENUS251/bin/genus')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    baseline, run = args.baseline.resolve(), args.run_dir.resolve()
    old = json.loads((baseline / 'manifest.json').read_text())
    if digest(baseline / 'design.sv') != old['design_sha256']:
        raise RuntimeError('Frozen baseline RTL hash mismatch')
    top = old['top']
    elab = old.get('elaboration_parameters', {})
    dpa_stages = elab.get('DpaStages', 4)
    if top not in ('ucc_lane', 'ucc_dpa16_baseline'):
        raise RuntimeError('Expected frozen UCC or standalone DPA16 RTL')
    run.mkdir(parents=True, exist_ok=False)
    (run / 'db').mkdir()
    ref = run / 'reference'
    ref.mkdir()
    files = {'config.tcl': SM / 'config.tcl',
             'fpu_block_top.sdc': SM / 'constraints/fpu_block_top.sdc',
             'mmmc_build_macros.tcl': SM / 'syn/mmmc_build_macros.tcl',
             'run_genus.tcl': SM / 'syn/run_genus.tcl',
             'tsmcn28_libs.tcl': LIBS}
    for name, path in files.items():
        shutil.copyfile(path, ref / name)
    shutil.copyfile(baseline / 'design.sv', run / 'design.sv')
    shutil.copyfile(baseline / 'manifest.json', run / 'tt_manifest.json')
    sdc = files['fpu_block_top.sdc'].read_text()
    substitutions = {'[get_ports clk]': '[get_ports clk_i]',
                     '[get_ports {clk reset}]': '[get_ports {clk_i rst_ni}]',
                     '[get_ports reset]': '[get_ports rst_ni]'}
    for before, after in substitutions.items():
        if sdc.count(before) != 1:
            raise RuntimeError('Unexpected reference SDC: ' + before)
        sdc = sdc.replace(before, after)
    sdc = ('# ucc_lane port adaptation of reference/fpu_block_top.sdc.\n'
           '# rst_ni is held inactive for timing, matching the reference static-reset assumption.\n' +
           '\n'.join(line for line in sdc.splitlines() if not line.startswith('#')) + '\n')
    (run / 'ucc_lane.sdc').write_text(sdc)
    mmmc = files['mmmc_build_macros.tcl'].read_text()
    source = 'source [file join $::pnr_root flow setup tsmcn28_libs.tcl]'
    if mmmc.count(source) != 1:
        raise RuntimeError('Unexpected reference MMMC library source')
    (run / 'mmmc.tcl').write_text(mmmc.replace(source,
        'source [file join $run_dir reference tsmcn28_libs.tcl]'))
    shutil.copyfile(Path(__file__).with_name('synth_sm_corner.tcl'), run / 'synth.tcl')
    query = f'''set ::flow_root {{{SM}}}
source {{{ref / 'config.tcl'}}}
source {{{ref / 'tsmcn28_libs.tcl'}}}
foreach v $cfg(views) {{puts "VIEW\t[join $v ,]"}}
foreach c {{ss ff tt}} {{foreach p $tsmcn28_libs_by_corner($c) {{puts "LIB\t$c\t$p"}}}}
foreach p $tsmcn28_lefs {{puts "LEF\t$p"}}
foreach c {{setup hold tt}} {{puts "QRC\t$c\t$tsmcn28_qrc_by_corner($c)"}}
'''
    resolved = subprocess.check_output(['tclsh'], input=query, text=True)
    views, pdk = [], []
    for line in resolved.splitlines():
        fields = line.split('\t')
        if fields[0] == 'VIEW':
            views.append(fields[1].split(','))
        elif fields[0] in ('LIB', 'LEF', 'QRC'):
            path = Path(fields[-1])
            pdk.append({'kind': fields[0], 'corner': fields[1] if len(fields) == 3 else None,
                        'path': str(path), 'sha256': digest(path)})
    if views != [['SS.setup_view', 'ss', '125.0', 'setup', '1', '0'],
                 ['FF.hold_view', 'ff', '-40.0', 'hold', '0', '1'],
                 ['TT.extra_view', 'tt', '25.0', 'tt', '0', '1']]:
        raise RuntimeError('Reference three-view configuration changed')
    inputs = [run / 'design.sv', run / 'synth.tcl', run / 'mmmc.tcl', run / 'ucc_lane.sdc',
              run / 'tt_manifest.json', *sorted(ref.iterdir())]
    manifest = {
        'baseline_run': str(baseline), 'top': top,
        'design_sha256': old['design_sha256'], 'source_sha256': old['source_sha256'],
        'base_commit': old['base_commit'], 'genus_executable': str(GENUS),
        'parameters': ({'EnableFp64': 0, 'PackedIntLow': 1,
                        'CompactAccumulator': 1, 'FixedScalarAlign': 1, 'DpaStages': dpa_stages}
                       if top == 'ucc_lane' else
                       {'latency': dpa_stages, 'DpaStages': dpa_stages, 'tiles': 16,
                        'DPA_M': 0, 'DPA_PIPE': 1, 'DPA_RND': 0}),
        'elaboration_parameters': elab,
        'views': views, 'period_ns': 1.0, 'input_delay_ns': 0.30, 'output_delay_ns': 0.30,
        'clock_uncertainty_ns': 0.05, 'clock_transition_ns': 0.05,
        'max_transition_ns': 0.10, 'max_fanout': 32, 'driving_cell': 'BUFFD4BWP30P140',
        'output_load_pf': 0.005, 'reset_timing': 'rst_ni static, false path from reset',
        'generic_effort': 'medium', 'map_effort': 'high', 'opt_effort': 'high',
        'preserve_hierarchy': True, 'clock_gating': True, 'retiming': False,
        'physical_inputs': 'SM technology/cell LEFs and QRC corners; no placement or routing',
        'reference_files': {str(path): digest(path) for path in files.values()},
        'input_sha256': {str(path.relative_to(run)): digest(path) for path in inputs},
        'pdk_files': pdk,
    }
    (run / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if args.prepare_only:
        return
    env = dict(os.environ, UCC_RUN_DIR=str(run), UCC_TOP=top,
               UCC_ELAB_PARAMETERS=' '.join(f'{{{k} {v}}}' for k, v in elab.items()),
               CDS_LIC_FILE=os.environ.get('CDS_LIC_FILE', '27006@cadencels.s.uw.edu'))
    env.pop('CDN_SYNTH_ROOT', None)
    env['PATH'] = str(GENUS.parent) + ':' + env['PATH']
    with (run / 'run.log').open('w') as log:
        subprocess.run([str(GENUS), '-batch', '-files', 'synth.tcl', '-log', 'genus'],
                       cwd=run, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    if not (run / 'complete.txt').exists():
        raise RuntimeError('Genus did not finish all reports: ' + str(run))


if __name__ == '__main__':
    main()
