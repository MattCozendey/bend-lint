"""Install pinned NVIDIA NVRTC libraries locally; no system Python packages."""
from pathlib import Path
import hashlib
import json
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1] / '.tools' / 'cuda'
PACKAGES = [
    ('nvidia-cuda-nvrtc-cu12', '12.9.86', '210cf05005a447e29214e9ce50851e83fc5f4358df8b453155d5e1918094dcb4'),
    ('nvidia-cuda-runtime-cu12', '12.9.79', '25bba2dfb01d48a9b59ca474a1ac43c6ebf7011f1b0b8cc44f54eb6ac48a96c3'),
]
ROOT.mkdir(parents=True, exist_ok=True)
for package, version, digest in PACKAGES:
    with urllib.request.urlopen(f'https://pypi.org/pypi/{package}/{version}/json') as response:
        metadata = json.load(response)
    wheel = next(f for f in metadata['urls'] if f['digests']['sha256'] == digest)
    archive = ROOT / wheel['filename']
    if not archive.exists():
        print(f'Downloading {package} {version} ({wheel["size"] // 1000000} MB)', flush=True)
        urllib.request.urlretrieve(wheel['url'], archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Checksum mismatch: {archive}')
    with zipfile.ZipFile(archive) as source:
        # Only NVIDIA's headers and libraries; no Python package installation.
        for name in source.namelist():
            parts = Path(name).parts
            if '..' in parts or name.startswith('/'):
                raise SystemExit('Unsafe archive entry')
            if name.startswith('nvidia/'):
                source.extract(name, ROOT)
for directory in ['include', 'lib64']:
    (ROOT / directory).mkdir(exist_ok=True)
for package in ['cuda_runtime', 'cuda_nvrtc']:
    for source_dir, target_dir in [('include', 'include'), ('lib', 'lib64')]:
        for source in (ROOT / 'nvidia' / package / source_dir).iterdir():
            target = ROOT / target_dir / source.name
            if not target.exists():
                target.symlink_to(source)
link = ROOT / 'lib64' / 'libnvrtc.so'
if not link.exists():
    link.symlink_to('libnvrtc.so.12')
print(f'CUDA_HOME={ROOT}', flush=True)
