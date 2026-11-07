#!/usr/bin/env python3
"""Collect completed synthesis and independent test evidence for FMA reuse trials."""
import hashlib
import json
from pathlib import Path

from area_breakdown import breakdown
from report import measured

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build_ucc'
DOCS = ROOT / 'docs/proposals'


def record(path):
    return {'path': str(path.relative_to(ROOT)),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def rtl_result(name):
    folder = BUILD / name
    manifest = json.loads((folder / 'test_manifest.json').read_text())
    if manifest['status'] != 'passed':
        raise ValueError(f'RTL regression incomplete or failed: {folder}')
    result = {'build': name, 'manifest': record(folder / 'test_manifest.json'),
              'result': (folder / 'result.txt').read_text()}
    directed = folder / 'segmented_directed_manifest.json'
    if directed.exists():
        checks = json.loads(directed.read_text())
        if checks['returncode'] or 'PASS unified:' not in checks['result']:
            raise ValueError(f'Directed RTL regression failed: {folder}')
        if (checks['compiled_test_manifest_sha256'] != record(folder / 'test_manifest.json')['sha256']
                or checks['binary_sha256'] != record(folder / ('V' + manifest['top']))['sha256']):
            raise ValueError(f'Directed replay no longer matches the compiled build: {folder}')
        result['directed_manifest'] = record(directed)
        result['directed_result'] = checks['result']
    return result


def main():
    synth = BUILD / 'ucc_synth'
    baseline = measured(synth / 'VX_ucc_dpa16_comb')
    previous = measured(synth / 'VX_ucc_v4_anchor_crop_comb')
    variants = []
    for label, build in (
        ('window', 'ucc_v4_exact_exp_window'),
        ('segmented', 'ucc_v4_exact_exp_w64_segmented'),
        ('segmented_align', 'ucc_v4_exact_exp_w64_segmented_align_checked')):
        top = f'VX_ucc_v4_{label}_comb'
        measurement = measured(synth / top)
        if measurement['dpa_numeric_sources'] != baseline['dpa_numeric_sources']:
            raise ValueError('Baseline DPA numerical sources differ')
        gates = BUILD / f'ucc_gate_{label}' / 'manifest.json'
        gate = json.loads(gates.read_text())
        if (gate['returncode'] or gate['test_result'] != f"PASS gate simulation: {gate['checks']} checks"
                or gate['synthesis']['preprocessed_sha256'] != measurement['preprocessed_sha256']):
            raise ValueError(f'Mapped verification failed or does not match synthesis: {top}')
        test = rtl_result(build)
        if 'directed_manifest' not in test:
            raise ValueError(f'Missing directed replay: {build}')
        source_manifest = json.loads((synth / top / 'manifest.json').read_text())
        source_changes = [
            {'path': path, 'frozen_sha256': digest, 'current_sha256': record(ROOT / path)['sha256']}
            for path, digest in source_manifest['source_sha256'].items()
            if record(ROOT / path)['sha256'] != digest
        ]
        variants.append({
            'measurement': measurement, 'rtl': test,
            'gate_manifest': record(gates), 'gate_checks': gate['checks'],
            'current_source_differences': source_changes,
            'delta_vs_previous_exact_um2': measurement['area_um2'] - previous['area_um2'],
            'delta_vs_previous_exact_fraction': measurement['area_um2'] / previous['area_um2'] - 1,
            'overhead_vs_dpa_fraction': measurement['area_um2'] / baseline['area_um2'] - 1,
            'area_breakdown': breakdown(synth / top),
        })
    model = json.loads((BUILD / 'ucc_segmented_model/results.json').read_text())
    if model['first_failures']:
        raise ValueError('Mathematical model failed')
    winner = min([previous] + [v['measurement'] for v in variants if v['measurement']['timing_met']],
                 key=lambda m: m['area_um2'])
    configurations = {
        'VX_ucc_v4_anchor_crop_comb': {'FMA_STYLE': 3, 'WINDOW_NORM': 0},
        'VX_ucc_v4_window_comb': {'FMA_STYLE': 3, 'WINDOW_NORM': 1},
        'VX_ucc_v4_segmented_comb': {'FMA_STYLE': 4},
        'VX_ucc_v4_segmented_align_comb': {'FMA_STYLE': 5},
    }
    lint_path = BUILD / 'ucc_stream_window_default_lint.json'
    lint = json.loads(lint_path.read_text())
    if lint['returncode'] or lint['stream_source_sha256'] != record(ROOT / 'hw/rtl/ucc/VX_ucc_stream.sv')['sha256']:
        raise ValueError('Default exact stream elaboration failed or has a stale source hash')
    report = {
        'baseline': baseline, 'previous_exact': previous, 'variants': variants,
        'mathematical_model': model,
        'primitives': rtl_result('ucc_segments_final'),
        'protocol': [rtl_result('ucc_stream_window'), rtl_result('ucc_stream_segmented'),
                     rtl_result('ucc_stream_segmented_align')],
        'recommended_candidate': {
            'top': winner['top'], 'area_um2': winner['area_um2'],
            'stream_parameters': {'EXACT_FP': 1, 'EXP_STYLE': 1, **configurations[winner['top']]},
            'qualification': 'Minimum of the prior selected exact configuration and these three verified 5 ns candidates.',
        },
        'default_stream_elaboration': record(lint_path),
        'limitations': [
            'Differential verification, not an all-input formal proof.',
            '5 ns combinational ZeroWireload synthesis, not post-route or a 1 GHz pipeline.',
            'Source and gate evidence identify frozen revisions. First two snapshots precede disabled-by-default multiplier alignment routing; subsequent primitive begin/end style edits are covered by the final primitive test. No byte-identical resynthesis claim.',
            'Standard W64 general-vector expectations also have zero differences against the exact oracle; directed replay uses exact expectations directly.',
            'Retained hierarchy attribution is partial; flattened mux/control and arithmetic costs cannot be fully separated.',
        ],
    }
    target = DOCS / 'ucc_segmented_measurements.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    for variant in variants:
        m = variant['measurement']
        print(m['top'], m['area_um2'], m['data_path_ps'], m['slack_ps'],
              'delta', round(variant['delta_vs_previous_exact_um2'], 3))
    print(target)


if __name__ == '__main__':
    main()
