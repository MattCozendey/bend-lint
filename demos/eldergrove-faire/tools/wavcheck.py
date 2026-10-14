# wavcheck.py in.wav out.png: levels per second, clipping, and a picture
# (waveform on top, a spectrogram below) of a mono 16-bit WAV, to review the
# synthesizer without listening. Standard library only.
import sys, struct, zlib, math

data = open(sys.argv[1], 'rb').read()
rate = struct.unpack('<I', data[24:28])[0]
pcm = struct.unpack('<%dh' % ((len(data) - 44) // 2), data[44:])
n = len(pcm)
print('rate', rate, 'seconds', n / rate)
for s in range(int(n / rate)):
    seg = pcm[s * rate:(s + 1) * rate]
    peak = max(abs(v) for v in seg)
    rms = math.sqrt(sum(v * v for v in seg) / len(seg))
    clip = sum(1 for v in seg if abs(v) >= 31999)
    print(f'{s:2d}s peak {peak:6d} rms {rms:7.0f} clipped {clip}')

# autocorrelation pitch of a slice (melody check)
def pitch(start, length=2048):
    seg = pcm[start:start + length]
    best, lag_best = -1e18, 0
    for lag in range(20, 400):
        c = sum(seg[i] * seg[i + lag] for i in range(0, length - lag, 2))
        if c > best:
            best, lag_best = c, lag
    return rate / lag_best if lag_best else 0
for t in [0.05, 0.4, 0.8, 1.2]:
    print(f'pitch near {t}s: {pitch(int(t * rate)):.1f} Hz')

# picture: 1000 x 300, waveform (100 px) + spectrogram (200 px, 0-5.5 kHz)
W, H = 1000, 300
img = [[(20, 20, 30)] * W for _ in range(H)]
per = n // W
for x in range(W):
    seg = pcm[x * per:(x + 1) * per]
    lo, hi = min(seg), max(seg)
    y0 = 50 - int(hi / 32768 * 50); y1 = 50 - int(lo / 32768 * 50)
    for y in range(max(0, y0), min(100, y1 + 1)):
        img[y][x] = (120, 220, 140)
N = 256
win = [0.5 - 0.5 * math.cos(2 * math.pi * i / N) for i in range(N)]
for x in range(W):
    c = x * per
    seg = pcm[c:c + N]
    if len(seg) < N: break
    for k in range(0, 64):  # bins up to rate/4
        re = im = 0.0
        for i in range(0, N, 2):
            v = seg[i] * win[i]
            a = 2 * math.pi * k * i / N
            re += v * math.cos(a); im -= v * math.sin(a)
        mag = math.log10(1 + math.hypot(re, im)) / 6.5
        g = max(0, min(255, int(mag * 255)))
        for dy in range(3):
            y = 299 - (k * 3 + dy)
            if y >= 100:
                img[y][x] = (g, g // 2, 255 - g // 2 if g else 30)
def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
raw = b''.join(b'\x00' + bytes(v for px in row for v in px) for row in img)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')
open(sys.argv[2], 'wb').write(png)
