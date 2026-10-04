#!/usr/bin/env python3
"""Render Plane Walker's original eight-bar scores without external samples."""

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import tempfile
import wave


RATE = 22050
TAU = math.tau
ROOT = Path(__file__).resolve().parents[2]
SCORES = [
    ("music_hub", 84, 62, "major", "calm"),
    ("music_training", 108, 64, "dorian", "pulse"),
    ("music_credits", 76, 60, "major", "calm"),
    ("music_victory", 96, 67, "major", "pulse"),
    ("music_defeat", 72, 57, "minor", "calm"),
    ("music_ruins_of_remnant", 88, 62, "minor", "explore"),
    ("music_void_forest", 80, 57, "dorian", "explore"),
    ("music_time_rift", 104, 64, "minor", "pulse"),
    ("music_plane_forge", 112, 55, "minor", "pulse"),
    ("music_throne_of_void", 76, 60, "minor", "explore"),
    ("music_boss_ruin_king", 116, 62, "minor", "battle"),
    ("music_boss_forest_heart", 108, 57, "dorian", "battle"),
    ("music_boss_time_sovereign", 120, 64, "minor", "battle"),
    ("music_boss_forge_colossus", 112, 55, "minor", "battle"),
    ("music_boss_void_throne", 104, 60, "minor", "battle"),
]
SCALES = {"major": (0, 2, 4, 5, 7, 9, 11), "minor": (0, 2, 3, 5, 7, 8, 10), "dorian": (0, 2, 3, 5, 7, 9, 10)}
LICENSE = """Plane Walker original music
SPDX-License-Identifier: CC0-1.0

All compositions, synthesis instruments and audio samples in this directory
are original project material rendered by tools/production_audio/generate_music.py.
No third-party recordings or samples are used. The project authors dedicate
these audio assets to the public domain under CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/
The renderer source remains under the repository's source-code license.
"""


def _degree(root, scale, degree):
    return root + scale[degree % 7] + 12 * (degree // 7)


def _voice(left, right, beat_seconds, start, length, midi, volume, pan, instrument):
    begin = round(start * beat_seconds * RATE)
    count = round(length * beat_seconds * RATE)
    frequency = 440 * 2 ** ((midi - 69) / 12)
    attack = min(count // 4, round(RATE * (0.12 if instrument == "pad" else 0.008)))
    release = min(count // 3, round(RATE * (0.32 if instrument == "pad" else 0.06)))
    for offset in range(min(count, len(left) - begin)):
        phase = TAU * frequency * offset / RATE
        if instrument == "pad":
            signal = (math.sin(phase) + 0.22 * math.sin(phase * 2) + 0.08 * math.sin(phase * 3)) / 1.3
        elif instrument == "bass":
            signal = 0.75 * math.sin(phase) + 0.25 * math.sin(phase * 2)
        else:
            signal = 0.68 * math.sin(phase) + 0.22 * math.sin(phase * 3) + 0.10 * math.sin(phase * 5)
        envelope = min(1.0, offset / max(1, attack), (count - 1 - offset) / max(1, release))
        if instrument == "bell":
            envelope *= math.exp(-3.0 * offset / max(1, count))
        sample = signal * envelope * volume
        left[begin + offset] += sample * (1 - pan)
        right[begin + offset] += sample * pan


def _drum(left, right, beat_seconds, start, kind, rng, volume):
    begin = round(start * beat_seconds * RATE)
    count = round(RATE * (0.19 if kind == "kick" else 0.065))
    for offset in range(min(count, len(left) - begin)):
        time = offset / RATE
        if kind == "kick":
            phase = TAU * (48 * time + 60 * (1 - math.exp(-time * 30)) / 30)
            sample = math.sin(phase) * math.exp(-time * 25)
        else:
            sample = rng.uniform(-1, 1) * math.exp(-time * 65)
        sample *= min(1.0, offset / 32) * min(1.0, (count - 1 - offset) / 128) * volume
        left[begin + offset] += sample * 0.55
        right[begin + offset] += sample * 0.45


def _render(score, output):
    cue, bpm, root, mode, arrangement = score
    seconds = 60 / bpm
    frames = round(32 * seconds * RATE)
    left, right = array("d", [0]) * frames, array("d", [0]) * frames
    scale = SCALES[mode]
    rng = random.Random(int(hashlib.sha256(cue.encode()).hexdigest()[:16], 16))
    progression = (0, 5, 3, 4) if mode == "major" else (0, 5, 2, 6)
    motif = (0, 2, 4, 2, 6, 4, 3, 1, 0, 4, 5, 4, 2, 1, 6, 1)
    motif_offset = rng.randrange(4)
    battle = arrangement == "battle"
    for bar in range(8):
        degree = progression[(bar // 2) % 4]
        for interval, pan in ((0, 0.22), (2, 0.5), (4, 0.78)):
            _voice(left, right, seconds, bar * 4, 3.90, _degree(root - 12, scale, degree + interval), 0.075, pan, "pad")
        bass_step = 0.5 if battle else 1.0
        for index in range(round(4 / bass_step)):
            note = _degree(root - 24, scale, degree + (4 if index % 4 == 3 else 0))
            _voice(left, right, seconds, bar * 4 + index * bass_step, bass_step * 0.85, note, 0.15, 0.5, "bass")
        melody_step = 0.5 if arrangement in ("pulse", "battle") else 1.0
        for index in range(round(4 / melody_step)):
            if arrangement == "calm" and index == 3 and bar % 2:
                continue
            melodic_degree = degree + motif[(bar * 4 + index + motif_offset) % len(motif)]
            note = _degree(root + 12, scale, melodic_degree)
            _voice(left, right, seconds, bar * 4 + index * melody_step, melody_step * 0.9, note, 0.13 if battle else 0.10, 0.38 if index % 2 else 0.62, "lead" if battle else "bell")
        if arrangement != "calm":
            for index in range(8):
                _drum(left, right, seconds, bar * 4 + index * 0.5, "hat", rng, 0.023 if battle else 0.009)
            for index in (0, 2) if not battle else (0, 1.5, 2, 3):
                _drum(left, right, seconds, bar * 4 + index, "kick", rng, 0.10 if battle else 0.06)
    peak = max(max(abs(x) for x in left), max(abs(x) for x in right))
    gain = min(2.0, 0.70 / peak)
    pcm = array("h")
    energy = 0.0
    for index, (first, second) in enumerate(zip(left, right)):
        edge = min(1.0, index / 64, (frames - 1 - index) / 64)
        for sample in (first, second):
            value = round(sample * gain * edge * 32767)
            pcm.append(value)
            energy += value * value
    if sys.byteorder != "little":
        pcm.byteswap()
    path = output / (cue + ".wav")
    with wave.open(str(path), "wb") as audio:
        audio.setparams((2, 2, RATE, frames, "NONE", "not compressed"))
        audio.writeframes(pcm.tobytes())
    return {"id": cue, "path": path.name, "bpm": bpm, "bars": 8, "root_midi": root,
            "mode": mode, "arrangement": arrangement, "sample_rate": RATE, "channels": 2,
            "frames": frames, "loop_begin": 0, "loop_end": frames,
            "rms": round(math.sqrt(energy / (frames * 2)) / 32768, 6),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def generate(output):
    output.mkdir(parents=True, exist_ok=True)
    cues = [_render(score, output) for score in SCORES]
    manifest = {"schema_id": "plane_walker_original_music_v1", "schema_version": 1,
                "license": "CC0-1.0", "renderer": "tools/production_audio/generate_music.py",
                "cues": cues}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    (output / "LICENSE.txt").write_text(LICENSE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/production/music")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory)
            generate(generated)
            for path in generated.iterdir():
                if not (args.output / path.name).is_file() or path.read_bytes() != (args.output / path.name).read_bytes():
                    raise SystemExit("Music asset mismatch: " + path.name)
        print("PASS: all fifteen original music cues reproduce")
    else:
        generate(args.output)
        print("Rendered fifteen original music cues: " + str(args.output))


if __name__ == "__main__":
    main()
