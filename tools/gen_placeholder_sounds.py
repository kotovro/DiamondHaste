"""Нейтральные звуковые заглушки Diamond Heist (F-001), синтезом.

Звуковое направление ещё не выбрано (docs/art/REFERENCES.md, «Звук»), поэтому вместо
файлов из паков — простые синтезированные звуки. Только стандартная библиотека Python.
Результат детерминирован (фиксированный seed): повторный запуск даёт те же байты.

Запуск из корня репозитория:
    python tools/gen_placeholder_sounds.py

Формат: WAV, PCM 16 бит, моно, 44 100 Гц. Петли (*_loop.wav) получают чанк smpl с
точками петли — импорт Godot (режим петли «Detect From WAV» по умолчанию) включает
петлю сам. Каждая петля периодична: последний записанный отсчёт равен первому, точка
конца петли стоит на нём, поэтому шва нет.

Строки лицензий — assets/LICENSES.md (собственные заглушки, уровень A).
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

RATE = 44100
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TAU = 2.0 * math.pi


# --- Общие части ---------------------------------------------------------------

def normalize(samples: list[float], peak: float) -> list[float]:
    top = max(abs(s) for s in samples) or 1.0
    k = peak / top
    return [s * k for s in samples]


def fade(samples: list[float], fade_in: float, fade_out: float) -> list[float]:
    n_in = int(fade_in * RATE)
    n_out = int(fade_out * RATE)
    out = list(samples)
    for i in range(min(n_in, len(out))):
        out[i] *= i / n_in
    for i in range(min(n_out, len(out))):
        out[len(out) - 1 - i] *= i / n_out
    return out


def smpl_chunk(loop_start: int, loop_end: int) -> bytes:
    """Чанк smpl с одной петлёй вперёд (тип 0)."""
    header = struct.pack(
        "<9I",
        0,  # manufacturer
        0,  # product
        int(1e9 / RATE),  # sample period, нс
        60,  # MIDI unity note
        0,  # MIDI pitch fraction
        0,  # SMPTE format
        0,  # SMPTE offset
        1,  # число петель
        0,  # sampler data
    )
    loop = struct.pack("<6I", 0, 0, loop_start, loop_end, 0, 0)
    body = header + loop
    return b"smpl" + struct.pack("<I", len(body)) + body


def write_wav(rel_path: str, samples: list[float], loop_end: int | None = None) -> None:
    path = os.path.join(ROOT, rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(round(s * 32767))))) for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    if loop_end is not None:
        # wave не умеет дописывать чанки: добавляем smpl и правим размер RIFF.
        with open(path, "r+b") as f:
            data = f.read()
            chunk = smpl_chunk(0, loop_end)
            data += chunk
            data = data[:4] + struct.pack("<I", len(data) - 8) + data[8:]
            f.seek(0)
            f.write(data)
            f.truncate()
    size = os.path.getsize(path)
    print(f"{rel_path}: {len(samples) / RATE:.2f} s, {size // 1024} KB")


# --- Звуки ---------------------------------------------------------------------

def laser_hum() -> tuple[list[float], int]:
    """Гудение луча: петля 1 с. Все частоты — целые герцы, значит, период ровно 1 с."""
    n = RATE  # длина петли в отсчётах
    partials = [(120, 1.0), (240, 0.45), (360, 0.25), (600, 0.08), (1800, 0.03)]
    out: list[float] = []
    for i in range(n + 1):  # +1: последний отсчёт равен первому, на нём конец петли
        t = i / RATE
        s = sum(a * math.sin(TAU * f * t) for f, a in partials)
        s *= 0.85 + 0.15 * math.sin(TAU * 3 * t)  # лёгкое «дыхание», 3 Гц — тоже целое
        out.append(s)
    return normalize(out, 0.6), n


def laser_tripped() -> list[float]:
    """Касание луча: резкий электрический треск ~0,35 с."""
    rng = random.Random(1001)
    n = int(0.35 * RATE)
    out: list[float] = []
    crackle = 0.0
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 14.0)
        if rng.random() < 0.02:
            crackle = rng.uniform(-1.0, 1.0)
        crackle *= 0.93
        buzz = 1.0 if math.sin(TAU * 180 * t) > 0 else -1.0  # квадрат 180 Гц
        zap = math.sin(TAU * (2400 - 3000 * t) * t)  # вниз по высоте
        noise = rng.uniform(-1.0, 1.0)
        out.append(env * (0.35 * buzz + 0.35 * zap + 0.3 * noise) + 0.6 * crackle * env)
    return normalize(fade(out, 0.002, 0.03), 0.85)


def section_alarm_siren() -> tuple[list[float], int]:
    """Сирена тревоги: петля 1 с, вой 600–1000 Гц.

    Частота f(t) = 800 + 200·sin(2πt), за период набегает ровно 800 циклов, гармоники
    кратны, значит, петля бесшовна.
    """
    n = RATE
    out: list[float] = []
    for i in range(n + 1):
        t = i / RATE
        # фаза = ∫f dt = 800t − 200·cos(2πt)/(2π) + 200/(2π)
        phase = 800.0 * t + (200.0 / TAU) * (1.0 - math.cos(TAU * t))
        s = (
            math.sin(TAU * phase)
            + 0.33 * math.sin(TAU * 3 * phase)
            + 0.2 * math.sin(TAU * 5 * phase)
        )
        out.append(s)
    return normalize(out, 0.6), n


def section_reset() -> list[float]:
    """Сброс секции: «перемотка» ~0,7 с — быстрый свип вниз с дрожанием плёнки."""
    rng = random.Random(2002)
    n = int(0.7 * RATE)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 1400.0 * math.exp(-t * 3.2) + 120.0
        f *= 1.0 + 0.06 * math.sin(TAU * 22 * t)  # дрожание
        phase += f / RATE
        tone = math.sin(TAU * phase) + 0.4 * math.sin(TAU * 2 * phase)
        hiss = rng.uniform(-1.0, 1.0) * 0.12
        env = min(1.0, t / 0.02) * (1.0 - t / 0.7) ** 1.5
        out.append(env * (tone + hiss))
    return normalize(fade(out, 0.0, 0.05), 0.7)


def main() -> None:
    hum, hum_end = laser_hum()
    write_wav("audio/sfx/laser/laser_hum_loop.wav", hum, hum_end)
    write_wav("audio/sfx/laser/laser_tripped_01.wav", laser_tripped())
    siren, siren_end = section_alarm_siren()
    write_wav("audio/sfx/section/section_alarm_siren_loop.wav", siren, siren_end)
    write_wav("audio/sfx/section/section_reset_01.wav", section_reset())


if __name__ == "__main__":
    main()
