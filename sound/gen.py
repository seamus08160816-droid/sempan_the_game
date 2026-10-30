#!/usr/bin/env python3
"""셈판 효과음과 배경음을 합성해 sempan_the_game/Sounds/*.wav 로 만들어요.

녹음이나 외부 음원 없이 수식으로만 만든 소리라 저작권 걱정 없이 쓸 수 있어요.
같은 파일을 iOS 앱(번들)과 웹·안드로이드(web/build.py가 HTML에 넣어요)가 함께 써요.

사용법: python3 sound/gen.py <소리 이름...> 또는 --all   (필요: numpy)
"""
import pathlib
import sys
import wave
import zlib

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "sempan_the_game" / "Sounds"
SR = 22050          # 효과음 표본율
BGM_SR = 16000      # 배경음 표본율 (용량을 아끼려고 낮춰요)
rng = np.random.default_rng(7)  # 매번 같은 소리가 나오게 고정


# ---------- 기본 재료 ----------

def t_of(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env_exp(n, decay, sr=SR):
    """지수 감쇠 엔벨로프 (decay초마다 1/e)"""
    return np.exp(-np.arange(n) / sr / decay)


def attack(n, a, sr=SR):
    k = max(1, int(a * sr))
    e = np.ones(n)
    e[:k] = np.linspace(0, 1, k)
    return e


def sweep_phase(f0, f1, dur, curve=4.0, sr=SR):
    """f0 → f1 로 지수적으로 떨어지는 음높이의 위상"""
    t = t_of(dur, sr)
    f = f1 + (f0 - f1) * np.exp(-t * curve / dur)
    return 2 * np.pi * np.cumsum(f) / sr


def square(phase, duty=0.5):
    return np.where((phase / (2 * np.pi)) % 1 < duty, 1.0, -1.0)


def triangle(phase):
    x = (phase / (2 * np.pi)) % 1
    return 4 * np.abs(x - 0.5) - 1


def onepole_lp(x, cutoff, sr=SR):
    a = np.exp(-2 * np.pi * cutoff / sr)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def bandpass(x, lo, hi, sr=SR):
    return onepole_lp(x, hi, sr) - onepole_lp(x, lo, sr)


def crush(x, bits=6, hold=2):
    """옛 휴대용 게임기 느낌: 표본을 몇 개씩 붙잡고 비트 수를 줄여요"""
    y = np.repeat(x[::hold], hold)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(y * q) / q


def drive(x, amount):
    return np.tanh(x * amount) / np.tanh(amount)


def place(buf, x, at, sr=SR):
    i = int(at * sr)
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def normalize(x, peak=0.85):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def fade_out(x, dur, sr=SR):
    n = min(len(x), int(dur * sr))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def write(name, x, sr=SR):
    OUT.mkdir(parents=True, exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data.tobytes())
    print(f"{name}.wav  {len(x) / sr:.2f}s  {(len(data) * 2 + 44) / 1024:.0f} KB")


# ---------- 때리는 소리: 4단계 ----------
# 계산 소리(연필 톡)와 같은 재료로 시작해서 같은 공책 세계의 소리로 들리게 해요.
# 연필로 톡 + 손바닥으로 종이를 내리치는 "탁"(음이 뚝 떨어지는 타격감) 위에,
# 단계가 오를수록 더 높은 파열음과 두 번째 타격, 4단계는 종이가 찢어지며 연필심이 부러지는 소리가 더해져요.

def pencil(pitch=1900, gain=1.0):
    """tick()과 같은 연필 끝 소리"""
    n = int(0.06 * SR)
    noise = bandpass(rng.uniform(-1, 1, n), 1500, 6000) * env_exp(n, 0.008)
    blip = np.sin(2 * np.pi * pitch * t_of(0.06)) * env_exp(n, 0.012)
    return (noise * 1.2 + blip * 0.5) * gain


def hit(level):
    p = [
        dict(f0=300, f1=80, body=0.07, slap=0.06, tip=1900, tipg=0.55, hi=3000, drv=1.3),
        dict(f0=520, f1=95, body=0.09, slap=0.09, tip=2300, tipg=0.75, hi=4500, drv=1.8),
        dict(f0=900, f1=120, body=0.11, slap=0.13, tip=2800, tipg=0.95, hi=6500, drv=2.4),
        dict(f0=1400, f1=150, body=0.14, slap=0.18, tip=3400, tipg=1.15, hi=9000, drv=3.2),
    ][level - 1]
    dur = 0.3 + 0.3 * (level - 1)
    buf = np.zeros(int(dur * SR))

    def strike(at, gain, pitch=1.0):
        place(buf, pencil(p["tip"] * pitch, p["tipg"] * gain), at)
        n = int(p["body"] * SR * 2.5)
        ph = sweep_phase(p["f0"] * pitch, p["f1"] * pitch, n / SR, curve=5)
        body = (np.sin(ph) + 0.3 * triangle(ph * 2)) * env_exp(n, p["body"] * 0.5) * attack(n, 0.002)
        m = int(p["slap"] * SR * 2)
        slap = bandpass(rng.uniform(-1, 1, m), 500, p["hi"]) * env_exp(m, p["slap"] * 0.35)
        place(buf, body * 0.9 * gain, at + 0.004)
        place(buf, slap * 1.1 * gain, at + 0.002)

    strike(0, 1.0)
    if level >= 2:  # 책상이 울리는 낮은 "쿵"
        n = int(0.22 * SR)
        place(buf, np.sin(sweep_phase(140, 55, 0.22, curve=3)) * env_exp(n, 0.06) * attack(n, 0.003) * 0.7, 0.004)
    if level >= 3:  # 한 번 더 내리치는 소리와 높은 종이 파열음
        strike(0.05, 0.7, pitch=1.2)
        n = int(0.16 * SR)
        crack = rng.uniform(-1, 1, n)
        crack = crack - onepole_lp(crack, 3000)
        place(buf, crack * env_exp(n, 0.04) * (0.5 if level == 3 else 0.9), 0.01)
    if level >= 4:  # 종이 찢어지는 소리 + 연필심이 부러지며 튀는 높은 조각
        n = int(0.4 * SR)
        rip = np.zeros(n)
        k = 0
        while k < n:  # 잘게 끊기는 잡음 알갱이
            g = int(rng.uniform(0.004, 0.012) * SR)
            if rng.uniform() < 0.7:
                rip[k:k + g] += rng.uniform(-1, 1, len(rip[k:k + g])) * rng.uniform(0.4, 1)
            k += g
        rip = bandpass(rip, 1200, 7000) * env_exp(n, 0.14)
        place(buf, rip * 0.8, 0.06)
        n = int(0.6 * SR)
        boom = np.sin(sweep_phase(90, 40, 0.6, curve=2.5)) * env_exp(n, 0.16) * attack(n, 0.004)
        place(buf, boom * 0.6, 0.01)
        for k in range(8):
            at = 0.08 + k * 0.04 + rng.uniform(0, 0.02)
            f = 4600 - k * 260 + rng.uniform(-200, 200)
            ping = bell_tone(f, 0.08, 0.012, partials=((1, 1), (2.7, 0.3)))
            place(buf, ping * 0.35 * (1 - k / 10), at)
    out = drive(buf, p["drv"])
    return fade_out(normalize(out, 0.9), 0.03)


# ---------- 계산 한 줄: 연필로 톡 ----------

def tick():
    n = int(0.06 * SR)
    noise = bandpass(rng.uniform(-1, 1, n), 1500, 6000) * env_exp(n, 0.008)
    blip = np.sin(2 * np.pi * 1900 * t_of(0.06)) * env_exp(n, 0.012)
    return normalize(noise * 1.2 + blip * 0.5, 0.5)


# ---------- 강화 효과: 반짝 ----------

def bell_tone(f, dur, decay, partials=((1, 1), (2.01, 0.35), (3.02, 0.15)), sr=SR):
    t = t_of(dur, sr)
    n = len(t)
    x = sum(a * np.sin(2 * np.pi * f * r * t) * env_exp(n, decay / r ** 0.5, sr) for r, a in partials)
    return x * attack(n, 0.002, sr)


def sparkle():
    buf = np.zeros(int(0.45 * SR))
    for i, f in enumerate([1318.5, 1760, 2637]):
        place(buf, bell_tone(f, 0.35, 0.09) * (0.8 - i * 0.15), i * 0.045)
    return normalize(buf, 0.55)


def luck():
    buf = np.zeros(int(0.9 * SR))
    for i, f in enumerate([1046.5, 1318.5, 1568, 2093, 2637, 3136]):
        place(buf, bell_tone(f, 0.5, 0.14), i * 0.055)
    n = int(0.6 * SR)
    shimmer = (rng.uniform(-1, 1, n) - onepole_lp(rng.uniform(-1, 1, n), 5000)) * env_exp(n, 0.15)
    place(buf, shimmer * 0.25, 0.3)
    return normalize(buf, 0.7)


def miss():
    n = int(0.3 * SR)
    x = triangle(sweep_phase(420, 180, 0.3, curve=2)) * env_exp(n, 0.08) * attack(n, 0.004)
    return normalize(x, 0.4)


# ---------- 특전 고르기: 동전 짤랑 ----------

def coin_clink(f, dur=0.35):
    # 얇은 금속판의 비조화 배음
    return bell_tone(f, dur, 0.07, partials=((1, 1), (2.76, 0.5), (5.40, 0.25), (8.93, 0.12)))


def coins():
    buf = np.zeros(int(0.95 * SR))
    times = np.cumsum([0, 0.05, 0.07, 0.045, 0.08, 0.06, 0.09, 0.11])
    for k, at in enumerate(times):
        f = rng.uniform(2300, 4200)
        place(buf, coin_clink(f) * (1 - k * 0.09) * rng.uniform(0.7, 1.0), at + rng.uniform(0, 0.015))
    n = int(0.5 * SR)
    rattle = bandpass(rng.uniform(-1, 1, n), 3000, 9000) * env_exp(n, 0.12)
    place(buf, rattle * 0.12, 0.02)
    return normalize(buf, 0.75)


# ---------- 보스 앞: 무거운 종소리 ----------

def boss_bell():
    dur = 4.5
    buf = np.zeros(int(dur * SR))
    f = 98.0  # G2
    # 교회 종의 부분음: hum, prime, tierce(단3도), quint, nominal, ...
    partials = [(0.5, 0.9, 2.6), (1.0, 1.0, 1.8), (1.19, 0.6, 1.3), (1.5, 0.35, 1.0),
                (2.0, 0.55, 0.9), (2.51, 0.25, 0.55), (3.0, 0.2, 0.45), (4.07, 0.12, 0.3), (5.2, 0.08, 0.2)]
    t = t_of(dur)
    for r, a, d in partials:
        beat = 1 + 0.004 * np.sin(2 * np.pi * 0.7 * r * t)  # 살짝 맥놀이
        buf += a * np.sin(2 * np.pi * f * r * t * beat) * np.exp(-t / d)
    n = int(0.05 * SR)
    strike = onepole_lp(rng.uniform(-1, 1, n), 1800) * env_exp(n, 0.012)
    place(buf, strike * 1.5, 0)
    n = int(1.2 * SR)
    boom = np.sin(sweep_phase(70, 38, 1.2, curve=2)) * env_exp(n, 0.35)
    place(buf, boom * 0.9, 0)
    # 돌벽에 울리는 듯한 몇 번의 메아리
    dry = buf.copy()
    for k, (dl, g) in enumerate([(0.11, 0.35), (0.23, 0.25), (0.37, 0.18), (0.55, 0.12)]):
        place(buf, onepole_lp(dry, 1800 - k * 300) * g, dl)
    return fade_out(normalize(drive(buf * attack(len(buf), 0.003), 1.4), 0.9), 0.8)


# ---------- 업적: 짧은 팡파르 ----------

def fanfare():
    buf = np.zeros(int(1.3 * SR))
    notes = [(523.25, 0.0, 0.12), (659.25, 0.1, 0.12), (783.99, 0.2, 0.12), (1046.5, 0.32, 0.55)]
    for f, at, d in notes:
        n = int((d + 0.25) * SR)
        ph = 2 * np.pi * f * t_of(n / SR)
        tone = (0.6 * square(ph, 0.25) + 0.8 * triangle(ph)) * env_exp(n, d * 0.9) * attack(n, 0.004)
        place(buf, onepole_lp(tone, 4500) * 0.5, at)
    for i, f in enumerate([2093, 2637, 3136]):
        place(buf, bell_tone(f, 0.6, 0.18) * 0.35, 0.34 + i * 0.05)
    return normalize(buf, 0.7)


def chime():
    """도감 등록: 가벼운 두 음"""
    buf = np.zeros(int(0.5 * SR))
    place(buf, bell_tone(1568, 0.4, 0.12), 0)
    place(buf, bell_tone(2093, 0.4, 0.14), 0.07)
    return normalize(buf, 0.5)


# ---------- 카드: 스치는 소리, 놓는 소리, 버리는 소리 ----------

def swish():
    """종이 카드끼리 가볍게 스치는 "사삭": 부드럽게 올라오는 두 알갱이"""
    buf = np.zeros(int(0.16 * SR))
    for at, dur, gain in [(0.0, 0.05, 0.6), (0.04, 0.08, 1.0)]:
        n = int(dur * SR)
        grain = bandpass(rng.uniform(-1, 1, n), 900, 3000)
        e = np.sin(np.pi * np.arange(n) / n) ** 2  # 시작도 끝도 부드럽게
        place(buf, grain * e * gain, at)
    return normalize(onepole_lp(buf, 3500), 0.28)


def card_place():
    n = int(0.08 * SR)
    noise = bandpass(rng.uniform(-1, 1, n), 600, 4000) * env_exp(n, 0.012)
    thud = np.sin(sweep_phase(260, 120, 0.08, curve=3)) * env_exp(n, 0.02)
    return normalize(noise + thud * 0.6, 0.5)


def toss():
    n = int(0.3 * SR)
    noise = bandpass(rng.uniform(-1, 1, n), 900, 6000)
    e = np.minimum(1, np.arange(n) / (0.06 * SR)) * env_exp(n, 0.07)
    return normalize(noise * e, 0.45)


# ---------- 배경음: 잔잔한 모눈종이 루프 ----------

def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def bgm():
    sr = BGM_SR
    bpm = 96
    beat = 60 / bpm
    bars = 8
    length = int(bars * 4 * beat * sr)
    buf = np.zeros(length + sr * 2)  # 꼬리는 나중에 앞으로 돌려 붙여요 (끊김 없는 반복)

    def note(f, at, dur, kind, gain):
        n = int((dur + 0.4) * sr)
        t = np.arange(n) / sr
        ph = 2 * np.pi * f * t
        if kind == "bass":
            x = triangle(ph) * env_exp(n, dur * 0.8, sr) * attack(n, 0.006, sr)
        elif kind == "pluck":
            x = (0.5 * square(ph, 0.3) + triangle(ph)) * env_exp(n, 0.22, sr) * attack(n, 0.004, sr)
            x = onepole_lp(x, 2200, sr)
        elif kind == "lead":
            vib = 1 + 0.004 * np.sin(2 * np.pi * 5 * t) * np.minimum(1, t / 0.3)
            x = triangle(2 * np.pi * f * np.cumsum(vib) / sr) * np.minimum(1, t / 0.02)
            x *= np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.08))
            x = onepole_lp(x, 3000, sr)
        else:  # hat
            x = (rng.uniform(-1, 1, n) - onepole_lp(rng.uniform(-1, 1, n), 5000, sr)) * env_exp(n, 0.02, sr)
        place(buf, x * gain, at, sr)

    # Am - F - C - G - Am - F - Dm - E
    chords = [(57, [57, 60, 64]), (53, [53, 57, 60]), (48, [55, 60, 64]), (55, [55, 59, 62]),
              (57, [57, 60, 64]), (53, [53, 57, 60]), (50, [53, 57, 62]), (52, [56, 59, 64])]
    for b, (root, tones) in enumerate(chords):
        bar = b * 4 * beat
        note(midi(root - 12), bar, beat * 1.8, "bass", 0.55)
        note(midi(root - 12), bar + 2 * beat, beat * 1.5, "bass", 0.45)
        for k in range(4):  # 엇박 화음
            at = bar + k * beat + beat / 2
            for i, m in enumerate(tones):
                note(midi(m), at + i * 0.012, beat * 0.4, "pluck", 0.09)
        for k in range(8):
            note(0, bar + k * beat / 2, 0.02, "hat", 0.05 if k % 2 else 0.03)
    # 펜타토닉 선율 (박, 길이) — 두 마디씩 묻고 답해요
    melody = [
        (76, 0, 1), (74, 1, 0.5), (72, 1.5, 0.5), (69, 2, 1.5),
        (72, 4, 1), (74, 5, 1), (76, 6, 2),
        (79, 8, 1), (76, 9, 0.5), (74, 9.5, 0.5), (72, 10, 1.5),
        (74, 12, 0.5), (72, 12.5, 0.5), (71, 13, 1), (67, 14, 2),
        (76, 16, 1), (74, 17, 0.5), (72, 17.5, 0.5), (69, 18, 1.5),
        (72, 20, 1), (74, 21, 1), (72, 22, 2),
        (74, 24, 1), (72, 25, 0.5), (69, 25.5, 0.5), (65, 26, 1.5),
        (68, 28, 1), (71, 29, 1), (69, 30, 2),
    ]
    for m, b, d in melody:
        note(midi(m), b * beat, d * beat * 0.92, "lead", 0.16)
    loop = buf[:length].copy()
    loop[: len(buf) - length] += buf[length:]  # 꼬리를 앞으로
    return normalize(loop, 0.6)


SOUNDS = {
    **{f"hit{lv}": (lambda lv=lv: hit(lv), SR) for lv in range(1, 5)},
    "tick": (tick, SR), "sparkle": (sparkle, SR), "luck": (luck, SR), "miss": (miss, SR),
    "coins": (coins, SR), "bell": (boss_bell, SR), "fanfare": (fanfare, SR), "chime": (chime, SR),
    "swish": (swish, SR), "place": (card_place, SR), "toss": (toss, SR), "bgm": (bgm, BGM_SR),
}


def main():
    # 고친 소리만 다시 만들어요. 다른 소리 파일은 그대로 두어야 귀에 익은 소리가 바뀌지 않아요
    # 사용법: python3 sound/gen.py hit1 swish   /   전부: python3 sound/gen.py --all
    names = list(SOUNDS) if sys.argv[1:] == ["--all"] else sys.argv[1:]
    unknown = [n for n in names if n not in SOUNDS]
    if not names or unknown:
        print(f"다시 만들 소리 이름을 적어 주세요 (전부는 --all): {' '.join(SOUNDS)}")
        if unknown:
            print(f"모르는 이름: {' '.join(unknown)}")
        sys.exit(1)
    global rng
    for name in names:
        # 소리마다 따로 고정한 난수라서, 하나를 고쳐도 다른 소리가 바뀌지 않아요
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        fn, sr = SOUNDS[name]
        write(name, fn(), sr)


if __name__ == "__main__":
    main()
