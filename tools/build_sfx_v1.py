"""Synthesize the first soft sound effects for the desktop shop (sfx_v1).

Pure Python (stdlib `wave`, `math`, `struct`); no numpy or external assets.
Every sound is deterministic, 16-bit mono 22050 Hz, normalized to a quiet peak
at or below -6 dBFS, and starts/ends with a short fade so it never clicks.

    py -3 tools/build_sfx_v1.py

Writes assets/audio/sfx_v1/*.wav and manifest.json (the generation parameters
and measured peaks). Run Godot --headless --import afterwards to refresh the
.import files.
"""
from __future__ import annotations

import hashlib
import json
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio" / "sfx_v1"
RATE = 22050
MAX_PEAK_DBFS = -6.0
FADE_IN = 0.004  # seconds
FADE_OUT = 0.025

# Note frequencies (equal temperament, A4 = 440 Hz).
B5, C6, E6, G6, C7, E7 = 987.77, 1046.50, 1318.51, 1567.98, 2093.00, 2637.02
C5, E5, G5 = 523.25, 659.25, 783.99

SOUNDS = {
    "coin": {
        "description": "판매 동전: 맑은 두 음(B5→E6), 짧은 종소리 감쇠",
        "duration": 0.15,
        "peak_dbfs": -10.0,
        "voices": [
            {"start": 0.000, "freq": B5, "length": 0.060, "decay": 0.030, "harmonics": [1.0, 0.0, 0.18]},
            {"start": 0.045, "freq": E6, "length": 0.105, "decay": 0.045, "harmonics": [1.0, 0.0, 0.15]},
        ],
    },
    "brew_done": {
        "description": "제조 완료: 위로 미끄러지는 작은 거품 4개",
        "duration": 0.30,
        "peak_dbfs": -12.0,
        "voices": [
            {"start": 0.000, "freq": 360.0, "glide": 1.55, "length": 0.070, "decay": 0.028, "harmonics": [1.0]},
            {"start": 0.065, "freq": 500.0, "glide": 1.45, "length": 0.065, "decay": 0.025, "harmonics": [1.0]},
            {"start": 0.135, "freq": 430.0, "glide": 1.60, "length": 0.070, "decay": 0.027, "harmonics": [1.0]},
            {"start": 0.205, "freq": 620.0, "glide": 1.40, "length": 0.090, "decay": 0.030, "harmonics": [1.0]},
        ],
    },
    "expedition_return": {
        "description": "원정 귀환: 짧은 3음 아르페지오(C5-E5-G5), 부드러운 삼각파 느낌",
        "duration": 0.50,
        "peak_dbfs": -10.0,
        "voices": [
            {"start": 0.00, "freq": C5, "length": 0.26, "decay": 0.10, "harmonics": [1.0, 0.0, 0.11, 0.0, 0.04]},
            {"start": 0.11, "freq": E5, "length": 0.26, "decay": 0.10, "harmonics": [1.0, 0.0, 0.11, 0.0, 0.04]},
            {"start": 0.22, "freq": G5, "length": 0.28, "decay": 0.12, "harmonics": [1.0, 0.0, 0.11, 0.0, 0.04]},
        ],
    },
    "unlock": {
        "description": "기념·해금: 높은 반짝임 4음(C6-E6-G6-C7) + 은은한 떨림과 E7 잔향",
        "duration": 0.60,
        "peak_dbfs": -11.0,
        "voices": [
            {"start": 0.00, "freq": C6, "length": 0.22, "decay": 0.07, "harmonics": [1.0, 0.25], "tremolo": 11.0},
            {"start": 0.07, "freq": E6, "length": 0.22, "decay": 0.07, "harmonics": [1.0, 0.25], "tremolo": 11.0},
            {"start": 0.14, "freq": G6, "length": 0.24, "decay": 0.08, "harmonics": [1.0, 0.25], "tremolo": 11.0},
            {"start": 0.21, "freq": C7, "length": 0.39, "decay": 0.14, "harmonics": [1.0, 0.20], "tremolo": 9.0},
            {"start": 0.27, "freq": E7, "length": 0.33, "decay": 0.10, "harmonics": [0.45], "tremolo": 13.0},
        ],
    },
}


def voice_sample(voice: dict, t: float) -> float:
    """One voice at local time t (seconds since its start)."""
    if t < 0.0 or t >= voice["length"]:
        return 0.0
    # Pitch glide (bubbles): exponential sweep from freq to freq*glide; integrate for phase.
    glide = voice.get("glide", 1.0)
    f0 = voice["freq"]
    length = voice["length"]
    if glide != 1.0:
        k = math.log(glide) / length
        phase = 2.0 * math.pi * f0 * (math.exp(k * t) - 1.0) / k
    else:
        phase = 2.0 * math.pi * f0 * t
    value = 0.0
    for index, gain in enumerate(voice["harmonics"]):
        if gain:
            value += gain * math.sin(phase * (index + 1))
    # 3 ms attack per voice, then an exponential decay; ends at zero by length.
    attack = min(1.0, t / 0.003)
    envelope = attack * math.exp(-t / voice["decay"])
    tail = min(1.0, (length - t) / 0.012)
    tremolo = voice.get("tremolo", 0.0)
    if tremolo:
        envelope *= 0.82 + 0.18 * math.cos(2.0 * math.pi * tremolo * t)
    return value * envelope * tail


def render(spec: dict) -> list[float]:
    count = int(round(spec["duration"] * RATE))
    samples = []
    for n in range(count):
        t = n / RATE
        samples.append(sum(voice_sample(v, t - v["start"]) for v in spec["voices"]))
    # Global click guard: fade in/out on the whole clip.
    fade_in = int(FADE_IN * RATE)
    fade_out = int(FADE_OUT * RATE)
    for n in range(count):
        gain = 1.0
        if n < fade_in:
            gain = n / fade_in
        if n >= count - fade_out:
            gain = min(gain, (count - 1 - n) / fade_out)
        samples[n] *= gain
    return samples


def normalize(samples: list[float], peak_dbfs: float) -> list[int]:
    assert peak_dbfs <= MAX_PEAK_DBFS
    raw_peak = max(abs(s) for s in samples)
    target = 32767.0 * (10.0 ** (peak_dbfs / 20.0))
    scale = target / raw_peak
    return [int(round(s * scale)) for s in samples]


def write_wav(path: Path, pcm: list[int]) -> None:
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(b"".join(struct.pack("<h", value) for value in pcm))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": "sfx_v1",
        "generator": "tools/build_sfx_v1.py (stdlib wave/math only, deterministic)",
        "format": {"container": "wav", "encoding": "pcm_s16le", "channels": 1, "sample_rate": RATE},
        "max_peak_dbfs": MAX_PEAK_DBFS,
        "fade_seconds": {"in": FADE_IN, "out": FADE_OUT, "per_voice_attack": 0.003, "per_voice_tail": 0.012},
        "status": "candidate: synthesized and machine-checked; not yet heard on real speakers",
        "sounds": {},
    }
    for name, spec in SOUNDS.items():
        pcm = normalize(render(spec), spec["peak_dbfs"])
        path = OUT / f"{name}.wav"
        write_wav(path, pcm)
        peak = max(abs(v) for v in pcm)
        measured = 20.0 * math.log10(peak / 32767.0)
        assert measured <= MAX_PEAK_DBFS + 1e-9, (name, measured)
        assert pcm[0] == 0 and abs(pcm[-1]) <= 1, (name, pcm[0], pcm[-1])
        manifest["sounds"][name] = {
            "file": f"{name}.wav",
            "description": spec["description"],
            "duration_seconds": spec["duration"],
            "frames": len(pcm),
            "target_peak_dbfs": spec["peak_dbfs"],
            "measured_peak_dbfs": round(measured, 3),
            "voices": spec["voices"],
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        print(f"{name}: {len(pcm)} frames, {spec['duration']:.2f}s, peak {measured:.2f} dBFS")
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
