"""ウラミチの効果音を作る。

素材の権利の心配がないよう、正弦波と雑音を合成して WAV を書き出す（Python の標準ライブラリだけを使う）。
音を変えたいときは、このファイルを直してから次のコマンドで作り直す。

    python3 scripts/make_sounds.py

出力先は app/assets/sounds/。22.05 kHz・16 bit・モノラル。
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "sounds"


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, decay=6.0, harmonics=((1, 1.0),), attack=0.004):
    """減衰する音。harmonics は (倍音の番号, 大きさ) の組"""
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * t) * min(1.0, t / attack)
        v = sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in harmonics)
        out.append(env * v)
    return out


def sweep(f0, f1, seconds, decay=8.0):
    """音の高さが f0 から f1 へ動く音"""
    n = int(RATE * seconds)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / RATE
        env = math.exp(-decay * t) * min(1.0, t / 0.003)
        out.append(env * math.sin(phase))
    return out


def noise(seconds, decay=40.0, seed=1):
    rnd = random.Random(seed)
    n = int(RATE * seconds)
    out, prev = [], 0.0
    for i in range(n):
        t = i / RATE
        # 軽く低域に寄せて、紙を叩いたような音にする
        prev = prev * 0.6 + rnd.uniform(-1, 1) * 0.4
        out.append(prev * math.exp(-decay * t))
    return out


def mix(*tracks):
    """(開始の秒, 音, 大きさ) を重ねる"""
    end = max(int(start * RATE) + len(s) for start, s, _ in tracks)
    out = [0.0] * end
    for start, s, gain in tracks:
        o = int(start * RATE)
        for i, v in enumerate(s):
            out[o + i] += v * gain
    return out


def write(name, samples, peak=0.7):
    top = max(abs(v) for v in samples) or 1.0
    # 終わりを短く絞って、ぷつっという音を防ぐ
    fade = int(RATE * 0.01)
    for i in range(fade):
        samples[-1 - i] *= i / fade
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(
            b"".join(struct.pack("<h", int(v / top * peak * 32767)) for v in samples)
        )


BELL = ((1, 1.0), (2, 0.35), (3, 0.12), (4.2, 0.08))

# チェックイン：印を「ぽん」と押す低い音のあとに、鈴のような和音
write(
    "stamp.wav",
    mix(
        (0.0, tone(110, 0.25, decay=18, harmonics=((1, 1.0), (2, 0.3))), 1.0),
        (0.0, noise(0.08, decay=60), 0.5),
        (0.12, tone(1318.5, 0.9, decay=4.5, harmonics=BELL), 0.35),
        (0.16, tone(1760.0, 0.9, decay=4.5, harmonics=BELL), 0.3),
    ),
)

# 実績の解除：ド・ミ・ソ・ドと上がる分散和音
write(
    "unlock.wav",
    mix(
        *[
            (i * 0.09, tone(f, 1.0, decay=3.5, harmonics=BELL), 0.4)
            for i, f in enumerate((523.25, 659.25, 783.99, 1046.5))
        ],
        (0.36, tone(1568.0, 0.9, decay=4.0, harmonics=BELL), 0.2),
    ),
)

# ★を付ける：短く高い音
write("star.wav", tone(1567.98, 0.18, decay=22, harmonics=((1, 1.0), (2, 0.25))))

# お気に入り：下から上へ2つの音
write(
    "favorite.wav",
    mix(
        (0.0, tone(880.0, 0.12, decay=25, harmonics=((1, 1.0), (2, 0.2))), 0.6),
        (0.07, tone(1318.5, 0.2, decay=16, harmonics=((1, 1.0), (2, 0.2))), 0.6),
    ),
)

# ボタン：ごく短いクリック
write("tap.wav", sweep(1800, 900, 0.035, decay=90), peak=0.45)

# 保存できた：やわらかい2音
write(
    "success.wav",
    mix(
        (0.0, tone(783.99, 0.25, decay=10, harmonics=BELL), 0.5),
        (0.09, tone(1174.66, 0.35, decay=8, harmonics=BELL), 0.5),
    ),
)

print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.wav"))))
