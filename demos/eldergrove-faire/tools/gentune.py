# gentune.py: the Eldergrove waltz (an original tune) as Bend lookup tables
# for sound.bend. Writes tools/tune.bend.txt to paste between the markers.
#
# 32 bars of 3/4, six eighths a bar. A token is a note (C5, F#4 ...), '.'
# (the previous note continues) or '-' (rest). Each bar also names a chord
# for the oom-pah accompaniment.
import math

A = [  # A section, bars 1-16
 ("E5 . G5 . G5 .", "C"), ("E5 . D5 . C5 .", "C"), ("D5 . E5 . F5 .", "G7"), ("G5 . . . . .", "G7"),
 ("F5 . E5 . D5 .", "G7"), ("B4 . C5 . D5 .", "G7"), ("E5 . D5 . C5 .", "C"), ("C5 . . . . .", "C"),
 ("G5 . A5 . G5 .", "C"), ("E5 . C5 . E5 .", "C"), ("F5 . A5 . F5 .", "F"), ("E5 . . . . .", "C"),
 ("D5 . E5 . F5 .", "G7"), ("G5 . F5 . D5 .", "G7"), ("C5 . E5 . D5 .", "C"), ("C5 . . . - -", "C"),
]
B = [  # B section, bars 17-32
 ("A5 . . . G5 .", "F"), ("F5 . A5 . C6 .", "F"), ("C6 . B5 . A5 .", "Am"), ("G5 . . . . .", "G7"),
 ("F5 . E5 . D5 .", "Dm"), ("E5 . G5 . C6 .", "C"), ("B5 . A5 . G5 .", "G7"), ("A5 . . . . .", "Am"),
 ("A5 . . . G5 .", "F"), ("F5 . A5 . C6 .", "F"), ("D6 . C6 . A5 .", "F"), ("G5 . . . . .", "C"),
 ("E5 . F5 . G5 .", "C"), ("A5 . G5 . E5 .", "Am"), ("D5 . E5 . D5 .", "G7"), ("C5 . . . - -", "C"),
]
CHORDS = {  # bass note, then three chord tones
 "C": (48, 60, 64, 67), "G7": (43, 59, 62, 65), "F": (41, 57, 60, 65),
 "Am": (45, 57, 60, 64), "Dm": (50, 62, 65, 69),
}
NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}

def midi(tok):
    name, octave = tok[:-1], int(tok[-1])
    return 12 * (octave + 1) + NAMES[name]

steps = []   # per eighth: (pitch, back, length)
chords = []
for bar, (mel, ch) in enumerate(A + B):
    toks = mel.split()
    assert len(toks) == 6, (bar, mel)
    chords.append(CHORDS[ch])
    for i, tok in enumerate(toks):
        if tok == '-':
            steps.append((0, 0, 1))
            continue
        if tok == '.':
            j = i
            while toks[j] == '.':
                j -= 1
            start = j
        else:
            start = i
        k = start + 1
        while k < 6 and toks[k] == '.':
            k += 1
        steps.append((midi(toks[start]), i - start, k - start))

out = []
out.append("# the melody, one entry an eighth: pitch | (eighths since the note began) << 8 | (its length) << 12")
out.append("def Tune.step(+s: U32) -> U32:")
out.append("  match s:")
for s, (p, back, ln) in enumerate(steps):
    out.append(f"    case {s}:")
    out.append(f"      {p | (back << 8) | (ln << 12)}")
out.append("    case _:")
out.append("      0")
out.append("")
out.append("# each bar's chord: bass | tone << 8 | tone << 16 | tone << 24")
out.append("def Tune.chord(+b: U32) -> U32:")
out.append("  match b:")
for b, (bass, c1, c2, c3) in enumerate(chords):
    out.append(f"    case {b}:")
    out.append(f"      {bass | (c1 << 8) | (c2 << 16) | (c3 << 24)}")
out.append("    case _:")
out.append("      0")
out.append("")
out.append("# a pitch's phase step per sample at 22050 Hz (2^32 * f / 22050)")
out.append("def Tune.inc(+m: U32) -> U32:")
out.append("  match m:")
for m in range(24, 109):
    f = 440.0 * 2 ** ((m - 69) / 12)
    out.append(f"    case {m}:")
    out.append(f"      {int(round(f * 2**32 / 22050)) & 0xFFFFFFFF}")
out.append("    case _:")
out.append("      0")
open('tools/tune.bend.txt', 'w', newline='\n').write('\n'.join(out) + '\n')
print(len(steps), 'steps,', len(chords), 'bars')
