#!/usr/bin/env python3
"""Paired cold-reference and warm native-frame timings against a saved worker."""
from fractions import Fraction
from pathlib import Path
from datetime import datetime
import argparse, hashlib, json, platform, re, statistics, struct, subprocess, time
from camera import packet
from render import read_exact

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('baseline', type=Path, help='Saved worker with adjacent worker.gpu')
parser.add_argument('--repeats', type=int, default=7)
parser.add_argument('--output', type=Path, default=Path('evidence/fused-reference/production.json'))
options = parser.parse_args()
output = ROOT / options.output
output.parent.mkdir(parents=True, exist_ok=True)
width, height, iterations = 2200, 1560, 16384
paths = (options.baseline.resolve(), ROOT / 'Mandelbrot.app/Contents/MacOS/worker')
logs = [open(output.parent / f'worker-{i}.log', 'w+') for i in range(2)]
workers = [subprocess.Popen([str(path), '--gpu', 'on'], stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, stderr=logs[i]) for i, path in enumerate(paths)]
rows = []


def tile(index, command, x=0, y=0):
    log = logs[index]
    log.seek(0, 2)
    offset = log.tell()
    worker = workers[index]
    started = time.perf_counter()
    worker.stdin.write(f'T 1 {x} {y} 256\n'.encode() + command)
    worker.stdin.flush()
    header = struct.unpack('<IIIIdIIII', read_exact(worker.stdout, 40))
    pixels = read_exact(worker.stdout, header[3])
    elapsed = (time.perf_counter() - started) * 1000
    assert header[5] == 1 and header[8] == 1, header
    log.seek(offset)
    fields = dict(re.findall(r'(\w+)=([^\s]+)', log.read()))
    log.seek(0, 2)
    return header, pixels, elapsed, fields


def percentile95(values):
    return sorted(values)[max(0, (95 * len(values) + 99) // 100 - 1)]


def record(row):
    rows.append(row)
    print(json.dumps(row), flush=True)


scenes = [
    ('generic320', '-.743643887037151', '.131825904205330', '1e-68'),
    ('generic1088', '-.743643887037151', '.131825904205330', '1e-300'),
    ('generic3424', '-.743643887037151', '.131825904205330', '1e-1000'),
    ('parabolic320', '-.75', '0', '1e-68'),
    ('period3-interior320', '-.122561166876', '.744861766619', '1e-68'),
]

try:
    prime = packet(Fraction(0), Fraction(1), Fraction('1e-68'), width, height, 16, .4, True)
    for index in range(2):
        tile(index, prime)
    for name, real, imaginary, span in scenes:
        command = packet(Fraction(real), Fraction(imaginary), Fraction(span), width, height,
                         iterations, .4, True)
        hashes = set()
        for repeat in range(options.repeats):
            for index in ((0, 1) if repeat % 2 == 0 else (1, 0)):
                tile(index, prime)  # Evict the single reference cache outside the measurement.
                header, pixels, elapsed, fields = tile(index, command)
                assert fields['reference_cache'] == 'miss', fields
                digest = hashlib.sha256(pixels).hexdigest()
                hashes.add(digest)
                record(dict(scene=name, mode='cold-reference-tile', implementation=('baseline', 'candidate')[index],
                            repeat=repeat, center=[real, imaginary], span=span, bits=header[7],
                            iterations=iterations, full_width=width, full_height=height,
                            width=header[1], height=header[2], total_ms=elapsed, repairs=header[6],
                            reference_gpu_ms=float(fields['reference_GPU_ms']),
                            reference_wall_ms=float(fields['reference_wall_ms']),
                            pixel_gpu_ms=float(fields['pixels_GPU_ms']), sha256=digest))
        assert len(hashes) == 1, (name, hashes)
    for name, real, imaginary, span, budget in [
        ('generic320', '-.743643887037151', '.131825904205330', '1e-68', iterations),
        ('antenna320', '0', '1', '1e-68', iterations),
        ('antenna1088', '0', '1', '1e-300', iterations),
        ('generic144', '-.743643887037151', '.131825904205330', '1e-7', 2785),
    ]:
        command = packet(Fraction(real), Fraction(imaginary), Fraction(span), width, height, budget, .4, True)
        for index in range(2):
            tile(index, command)
        hashes = set()
        for repeat in range(options.repeats):
            for index in ((0, 1) if repeat % 2 == 0 else (1, 0)):
                pixels = bytearray(width * height * 4)
                times = []
                started = time.perf_counter()
                for y in range(0, height, 256):
                    for x in range(0, width, 256):
                        header, data, elapsed, fields = tile(index, command, x, y)
                        assert fields['reference_cache'] == 'hit', fields
                        times.append(elapsed)
                        tw, th = header[1:3]
                        for yy in range(th):
                            pixels[((y + yy) * width + x) * 4:((y + yy) * width + x + tw) * 4] = data[yy * tw * 4:(yy + 1) * tw * 4]
                elapsed = (time.perf_counter() - started) * 1000
                digest = hashlib.sha256(pixels).hexdigest()
                hashes.add(digest)
                record(dict(scene=name, mode='warm-native-frame', implementation=('baseline', 'candidate')[index],
                            repeat=repeat, center=[real, imaginary], span=span, bits=header[7], iterations=budget,
                            width=width, height=height, total_ms=elapsed, tile_p50_ms=statistics.median(times),
                            tile_p95_ms=percentile95(times), sha256=digest))
        assert len(hashes) == 1, (name, hashes)
finally:
    for worker in workers:
        worker.stdin.close()
    for worker in workers:
        worker.wait(timeout=30)
    for log in logs:
        log.close()

summary = []
for scene, mode in dict.fromkeys((row['scene'], row['mode']) for row in rows):
    stats = {}
    for implementation in ('baseline', 'candidate'):
        values = [row['total_ms'] for row in rows if (row['scene'], row['mode'], row['implementation']) == (scene, mode, implementation)]
        stats[implementation] = dict(median_ms=statistics.median(values), p95_ms=percentile95(values))
    summary.append(dict(scene=scene, mode=mode, speedup=stats['baseline']['median_ms'] / stats['candidate']['median_ms'], **stats))
result = dict(measured_at=datetime.now().astimezone().isoformat(),
              hardware=subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
              memory_bytes=int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
              os=platform.platform(), backend='Metal', bend=subprocess.check_output(['bend', '--version'], text=True).strip(),
              baseline_commit='956195108f1ee2c9ce6deabd6f2a45d13b9afd05', workers=1, tile_size=256, repeats=options.repeats,
              shader_sha256=hashlib.sha256((ROOT / 'precision.metal').read_bytes()).hexdigest(),
              worker_sha256={label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in zip(('baseline', 'candidate'), paths)},
              timing='Cold reference excludes process and shader startup; warm full frame includes tiles, GPU work, packing, IPC and stitching. One sample per native backing pixel.',
              rows=rows, summary=summary)
output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(summary, indent=2))
