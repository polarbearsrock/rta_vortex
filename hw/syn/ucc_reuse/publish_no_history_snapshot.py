#!/usr/bin/env python3
"""Package the selected mapping, frozen inputs and reports without build caches."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def publish(checkpoint, out):
    assert not out.exists()
    record = json.loads(checkpoint.read_text())
    assert record['goal_complete'] and record['each_dpa_pass']
    candidate = Path(record['candidate'])
    assert sha((candidate / 'mapped.v').read_bytes()) == record['mapped_sha256']
    power = candidate.with_name(candidate.name + '_power')
    timing = candidate.with_name(candidate.name + '_timing')
    check = candidate.with_name(candidate.name + '_check')
    reset = candidate.with_name(candidate.name + '_reset_entry')
    dpa = Path(record['dpa_measurement']).parent
    contract = next(Path(p) for p in record['evidence_sha256']
                    if Path(p).name == 'power_goal_contract_no_run_area46000_20261117.json')
    out.mkdir(parents=True)
    sources = {}

    def copy(source, name, compress=False):
        data = source.read_bytes()
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(gzip.compress(data, mtime=0) if compress else data)
        sources[name] = dict(source=str(source), source_sha256=sha(data),
                             compression='gzip' if compress else 'none')

    def generated(name, data):
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, indent=2) + '\n')

    copy(candidate / 'mapped.v', 'implementation/mapped.v')
    copy(power / 'design.sv', 'implementation/native_reference.sv')
    for name in ['latency_policy.json', 'numerical_policy.json']:
        copy(power / name, 'implementation/' + name)
    for label, source in [('validation', check), ('validation/reset_entry', reset)]:
        for name in ['bench.sv', 'reference.sv', 'result.json']:
            copy(source / name, label + '/' + name)
        vectors = 'pairs.txt' if source == reset else 'vectors.txt'
        copy(source / vectors, label + '/' + vectors + '.gz', True)
        copy(source / 'run.log', label + '/run.log.gz', True)
    pm = json.loads((power / 'manifest.json').read_text())
    generated('validation/cell_models.json', pm['gate_models_sha256'])
    for p in timing.iterdir():
        if p.is_file() and p.suffix in ['.tcl', '.sdc', '.rpt', '.json', '.txt']:
            compress = p.stat().st_size > 1_000_000
            copy(p, 'timing/' + p.name + ('.gz' if compress else ''), compress)
    for p in (timing / 'reference').rglob('*'):
        if p.is_file():
            assert p.suffix in ['.tcl', '.sdc']
            copy(p, 'timing/reference/' + str(p.relative_to(timing / 'reference')))
    for name, source in {
        'checkpoint.json': checkpoint, 'contract.json': contract,
        'scalar_comparison.json': power / 'comparison.json',
        'dpa_result.json': dpa / 'result.json',
        'candidate.json': candidate / 'candidate.json',
        'repair_identity.json': candidate / 'proof.json',
        'physical_icg_audit.json': candidate / 'physical_icg_audit.json',
        'fixed_cut_lineage_audit.json': candidate / 'fixed_cut_lineage_audit.json',
    }.items():
        copy(source, 'provenance/' + name)
    streams = {}
    workloads = [(op, power, op, 0) for op in pm['workloads']]
    for selector in range(4):
        source = dpa / ('power' if selector == 0 else f'fp8_rm{selector}')
        manifest = json.loads((source / 'manifest.json').read_text())
        for op in manifest['workloads']:
            name = op if selector == 0 else op + f'_rm{selector}'
            workloads.append((name, source, op, int(op != 'idle')))
    for name, source, op, mode in workloads:
        assert name not in streams
        manifest = json.loads((source / 'manifest.json').read_text())
        sim = manifest['gate_simulation'][op]
        streams[name] = dict(operation=op, dpa_mode=mode, source=str(source),
                             vcd_sha256=sim['vcd_sha256'], window_ps=sim['window_ps'])
        for filename in ['power.tcl', 'power.sdc', 'libraries_power.tcl',
                         'power.rpt', 'annotation.rpt', 'result.json']:
            copy(source / ('power_' + op) / filename, f'power/{name}/{filename}')
        copy(source / 'tb.sv', f'power/{name}/tb.sv')
        copy(source / (op + '.txt'), f'power/{name}/vectors.txt')
        copy(source / (op + '.sim.log'), f'power/{name}/simulation.log')
    generated('power/streams.json', streams)
    limits = json.loads(contract.read_text())
    for label, path in limits['baseline_final_design_rule_reports'].items():
        copy(Path(path), f'baseline/{label}_design_rule_audit.json')
    for label, path in limits['baseline_source_runs'].items():
        source = Path(path)
        if label != 'dpa5':
            copy(source / 'manifest.json', f'baseline/{label}/source_manifest.json')
            source = source / 'power'
        for filename in ['energy.json', 'manifest.json']:
            copy(source / filename, f'baseline/{label}/{filename}')
    for selector, path in limits['baseline_fp8_source_runs'].items():
        for filename in ['energy.json', 'manifest.json']:
            copy(Path(path) / filename, f'baseline/fp8_rm{selector}/{filename}')
    generated('source_archive.json', sources)
    generated('package_manifest.json', dict(
        mapped_sha256=record['mapped_sha256'], goal_complete=True,
        cell_area_um2=record['cell_area_um2'], cuda_ratio=record['cuda_ratio'],
        source_checkpoint=str(checkpoint), private_pdk_contents_included=False,
        files={str(p.relative_to(out)): sha(p.read_bytes()) for p in out.rglob('*') if p.is_file()}))
    print('PUBLISHED_SNAPSHOT', out, len(sources), 'source files')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    publish(args.checkpoint.resolve(), args.out.resolve())
