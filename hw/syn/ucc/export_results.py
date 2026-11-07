#!/usr/bin/env python3
"""Export compact, reproducible UCC evidence without tool installations or PDK files."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile

from report import measured

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build_ucc'
DEST = ROOT / 'docs/proposals/ucc_results'
TOPS = [
    'VX_ucc_dpa16_comb',
    'VX_ucc_v4_const_unpaired_comb', 'VX_ucc_v4_compact_unpaired_comb',
    'VX_ucc_v4_anchor_crop_comb', 'VX_ucc_v4_window_comb',
    'VX_ucc_v4_segmented_comb', 'VX_ucc_v4_segmented_align_comb',
    'VX_ucc_int_standalone', 'VX_ucc_fpu_standalone', 'VX_ucc_mufu_standalone',
] + [f'VX_ucc_coeff_{style}_p{ports}' for ports in (1, 2, 4, 8) for style in ('replica', 'array', 'plane')]
SYNTH_FILES = ('design.sv', 'manifest.json', 'area.rpt', 'timing.rpt', 'qor.rpt',
               'area_hier.rpt', 'power_vectorless.rpt', 'mapped.sdc', 'complete.txt', 'synth.tcl')
TESTS = (
    'ucc_v4_exp_w64_const_unpaired', 'ucc_v4_exp_w64_compact_unpaired',
    'ucc_v4_exact_exp_anchor_crop', 'ucc_v4_exact_exp_window',
    'ucc_v4_exact_exp_w64_segmented', 'ucc_v4_exact_exp_w64_segmented_align_checked',
    'ucc_stream_window', 'ucc_stream_segmented', 'ucc_stream_segmented_align', 'ucc_segments_final',
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def archive(name, entries):
    raw = io.BytesIO()
    hashes = {}
    with gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as stream:
            for relative, path in sorted(entries.items()):
                data = path.read_bytes()
                header = tarfile.TarInfo(relative)
                header.size = len(data)
                header.mode = 0o644
                stream.addfile(header, io.BytesIO(data))
                hashes[relative] = digest(data)
    data = raw.getvalue()
    target = DEST / name
    if target.exists() and target.read_bytes() != data:
        raise ValueError('Refusing to overwrite different archived evidence: ' + str(target))
    target.write_bytes(data)
    with tarfile.open(target, 'r:gz') as stream:
        for member in stream:
            if digest(stream.extractfile(member).read()) != hashes[member.name]:
                raise ValueError('Archive verification failed: ' + member.name)
    return {'archive': name, 'sha256': digest(data), 'bytes': len(data), 'files_sha256': hashes}


def main():
    DEST.mkdir(exist_ok=True)
    bundles, measurements = [], {}
    for top in TOPS:
        folder = BUILD / 'ucc_synth' / top
        measurement = measured(folder)
        measurements[top] = measurement
        record = archive(top + '.tar.gz', {f'{top}/{name}': folder / name for name in SYNTH_FILES})
        record['measurement'] = measurement
        bundles.append(record)

    evidence = {}
    for name in TESTS:
        folder = BUILD / name
        manifest = json.loads((folder / 'test_manifest.json').read_text())
        if manifest['status'] != 'passed':
            raise ValueError('Cannot export failed/incomplete RTL evidence: ' + name)
        for filename in ('test_manifest.json', 'result.txt', 'segmented_directed_manifest.json',
                         'segmented_directed_result.txt', 'dominance_highprec_manifest.json',
                         'dominance_highprec_result.txt', 'subnormal_highprec_manifest.json',
                         'subnormal_highprec_result.txt', 'highprec_manifest.json', 'highprec_result.txt'):
            path = folder / filename
            if path.exists():
                evidence[str(path.relative_to(BUILD))] = path

    gate_manifests = list(BUILD.glob('ucc_gate_*/manifest.json'))
    gate_manifests += list((BUILD / 'ucc_coeff_sharing').glob('gate_*/manifest.json'))
    for path in gate_manifests:
        manifest = json.loads(path.read_text())
        measurement = manifest.get('synthesis', {})
        top = measurement.get('top')
        if top not in measurements or measurement.get('preprocessed_sha256') != measurements[top]['preprocessed_sha256']:
            continue
        if manifest['returncode'] or not manifest['test_result'].startswith('PASS gate simulation:'):
            raise ValueError('Cannot export failed mapped evidence: ' + str(path))
        evidence[str(path.relative_to(BUILD))] = path
        result = path.with_name('result.txt')
        evidence[str(result.relative_to(BUILD))] = result

    for filename in ('ucc_coeff_sharing/rtl/manifest.json', 'ucc_coeff_sharing/rtl/result.txt',
                     'ucc_segmented_model/results.json', 'ucc_stream_window_default_lint.json',
                     'ucc_reference/result.json'):
        path = BUILD / filename
        evidence[filename] = path
    bundles.append(archive('verification.tar.gz', evidence))
    index = {
        'scope': 'Selected frozen RTL/synthesis snapshots and passed verification evidence. See parent Markdown/JSON reports for all candidate measurements.',
        'excluded': ['PDK/library model contents', 'EDA executables', 'mapped netlists', 'build binaries', 'large generated vector files'],
        'bundles': bundles,
    }
    (DEST / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    print(f'Exported and hash-verified {len(bundles)} bundles, {sum(b["bytes"] for b in bundles)} compressed bytes')


if __name__ == '__main__':
    main()
