#!/usr/bin/env python3
"""Compare exact GPU reference states with a saved shader and an integer oracle."""
from fractions import Fraction
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def oracle(cr, ci, bits, steps):
    scale = 1 << bits
    half = scale // 2
    zr = zi = 0
    for _ in range(steps):
        rr = (zr*zr+half)//scale
        ii = (zi*zi+half)//scale
        cross = (abs(zr*zi)+half)//scale
        if (zr < 0) != (zi < 0):
            cross = -cross
        zr, zi = rr-ii+cr, 2*cross+ci
    return zr, zi


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path, help='Preserved precision.metal file')
    parser.add_argument('--output', type=Path, default=Path('evidence/fused-reference/exact-state.json'))
    options = parser.parse_args()
    baseline = options.baseline.resolve()
    candidate = ROOT/'precision.metal'
    output = ROOT/options.output
    output.parent.mkdir(parents=True, exist_ok=True)
    build = ROOT/'.build'
    build.mkdir(exist_ok=True)
    driver = build/'precision-state-test'
    subprocess.run(['clang', '-O2', '-fobjc-arc', str(ROOT/'precision-test.m'),
                    '-framework', 'Foundation', '-framework', 'Metal', '-o', str(driver)], check=True)

    rows = []
    with tempfile.TemporaryDirectory(prefix='mandelbrot-exact-reference-') as folder:
        source = Path(folder)/'input.bin'
        for bits in (48, 144, 256, 320, 512, 1088, 3424, 5424, 5440, 5456, 8192, 16384):
            for label, real, imag in (
                ('seahorse', Fraction('-.743643887037151'), Fraction('.131825904205330')),
                ('negative_imaginary', Fraction('-.122561166876'), Fraction('-.744861766619')),
                ('carry_edge', Fraction(-(1 << bits)+1, 1 << bits), Fraction(1, 1 << bits)),
            ):
                limbs, points, chunk = bits//16+1, 129, 37
                cr = int(abs(real)*(1 << bits)) * (-1 if real < 0 else 1)
                ci = int(abs(imag)*(1 << bits)) * (-1 if imag < 0 else 1)
                data = struct.pack('<6I', limbs, points, int(cr < 0), int(ci < 0), 0, points)
                for coordinate in (cr, ci):
                    data += b''.join(struct.pack('<I', (abs(coordinate) >> (16*i)) & 65535) for i in range(limbs))
                source.write_bytes(data)
                outputs = [subprocess.run([str(driver), str(source), str(shader), '128', str(chunk), '--state'],
                                          capture_output=True, check=True).stdout for shader in (baseline, candidate)]
                assert outputs[0] == outputs[1], (bits, label, 'baseline differs')
                count = struct.unpack('<I', outputs[1][:4])[0]
                assert count == points, (bits, label, 'unexpected escaped reference')
                state = struct.unpack('<'+'I'*(2*limbs+2), outputs[1][4+8*count:])
                values = []
                for axis in range(2):
                    magnitude = sum(state[axis*limbs+i] << (16*i) for i in range(limbs))
                    values.append(-magnitude if state[2*limbs+axis] else magnitude)
                # The cooperative kernel stops at the final emitted point, z[count-1].
                assert tuple(values) == oracle(cr, ci, bits, points-1), (bits, label, 'integer oracle differs')
                rows.append(dict(bits=bits, center_case=label, reference_points=points, recurrence_steps=points-1,
                                 lanes=128, chunk=chunk, baseline_orbit_and_state_identical=True,
                                 integer_oracle_exact=True, sha256=hashlib.sha256(outputs[1]).hexdigest()))
            print(json.dumps({'bits': bits, 'cases_passed': 3}), flush=True)

    output.write_text(json.dumps({
        'base_shader_sha256': hashlib.sha256(baseline.read_bytes()).hexdigest(),
        'candidate_shader_sha256': hashlib.sha256(candidate.read_bytes()).hexdigest(),
        'method': 'Compare every emitted reference float plus exact final real/imaginary fixed-point limbs and signs; independently compute final state using Python integers with nearest fixed-point product rounding.',
        'cases': rows,
    }, indent=2)+'\n')


if __name__ == '__main__':
    main()
