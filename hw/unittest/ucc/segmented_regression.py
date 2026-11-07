#!/usr/bin/env python3
"""Replay cancellation, subnormal and dominant-addend vectors on built UCC RTL."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build_ucc'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('builds', nargs='+', help='Completed run.py build directory names')
    args = parser.parse_args()
    sources = [BUILD / name for name in (
        'ucc_segmented_model/vectors.txt',
        'ucc_fma_window_sweep/ieee_vectors.txt',
        'ucc_anchor/dominance_vectors.txt')]
    aux = BUILD / 'ucc_exp_highprec/wide_vectors.txt'
    vectors = BUILD / 'ucc_segmented_model/combined_vectors.txt'
    vectors.write_bytes(b''.join(p.read_bytes() for p in sources))
    for name in args.builds:
        obj = BUILD / name
        manifest = obj / 'test_manifest.json'
        compiled = json.loads(manifest.read_text())
        if compiled['status'] != 'passed':
            raise RuntimeError(f'Full RTL regression must pass first: {obj}')
        binary = obj / ('V' + compiled['top'])
        command = [str(binary), str(vectors), str(aux)]
        result = subprocess.run(command, cwd=BUILD, capture_output=True, text=True)
        output = result.stdout + result.stderr
        (obj / 'segmented_directed_result.txt').write_text(output)
        record = {
            'command': command, 'returncode': result.returncode, 'result': output,
            'compiled_test_manifest': str(manifest),
            'compiled_test_manifest_sha256': sha(manifest), 'binary_sha256': sha(binary),
            'vectors_sha256': {str(p): sha(p) for p in [vectors, aux]},
            'fp_source_vectors_sha256': {str(p): sha(p) for p in sources},
        }
        (obj / 'segmented_directed_manifest.json').write_text(json.dumps(record, indent=2) + '\n')
        print(name, output, flush=True)
        result.check_returncode()


if __name__ == '__main__':
    main()
