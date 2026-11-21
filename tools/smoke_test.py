#!/usr/bin/env python3
"""
Automatiskt röktest för Flighty 64 (utan KickAssembler/VICE).

1. Bygger src/main.asm med tools/ka_subset.py
2. Kör spelet i tools/emu.py med en enkel "bot" som spelar:
   meny -> springfas -> rymdskepp -> flygfas -> game over -> topplista
3. Kontrollerar att inget kraschar, att alla faser nås och att en
   bildruta aldrig tar mer CPU-tid än vad som finns.

Kör:  python3 tools/smoke_test.py [--shots katalog]
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import emu  # noqa: E402

PRG = os.path.join(ROOT, 'build', 'flighty64.prg')
SYM = os.path.join(ROOT, 'build', 'flighty64.sym.json')
FRAME_CYCLES = 312 * 63


def addr(c, name):
    return c.syms['consts'].get(name, c.syms['labels'].get(name))


def peek(c, name, ofs=0):
    return c.ram[addr(c, name) + ofs]


def column(c, x):
    fine = peek(c, 'fine')
    base = peek(c, 'ringBase')
    t = x - 24 - fine
    col = 0 if t < 0 else min(40, t >> 3)
    i = (base + col) & 63
    return peek(c, 'RING_CEILY', i), peek(c, 'RING_FLOORY', i)


def bot(c, f):
    """En enkel spelare: skjuter hela tiden, hoppar inför hinder, flyger i mitten."""
    px, py, phase = peek(c, 'px'), peek(c, 'py'), peek(c, 'phase')
    j = 16 if f % 12 < 6 else 0
    if phase != 2:
        feet = py + 21
        for dx in (20, 28, 36, 44):
            _, fy = column(c, px + dx)
            if fy < feet or fy == 255:
                j |= 1
        if px < 70:
            j |= 8
        if px > 100:
            j |= 4
    else:
        c1, f1 = column(c, px + 40)
        c2, f2 = column(c, px + 12)
        mid = (max(c1, c2) + min(f1, f2)) // 2 - 10
        if py > mid + 2:
            j |= 1
        elif py < mid - 2:
            j |= 2
        if px < 60:
            j |= 8
        if px > 80:
            j |= 4
    return j


def main():
    shots = None
    if '--shots' in sys.argv:
        shots = sys.argv[sys.argv.index('--shots') + 1]
        os.makedirs(shots, exist_ok=True)

    r = subprocess.run([sys.executable, os.path.join(HERE, 'ka_subset.py'),
                        os.path.join(ROOT, 'src', 'main.asm'), '-o', PRG, '--sym', SYM])
    if r.returncode:
        sys.exit("Bygget misslyckades")

    c = emu.load(PRG, SYM)
    for _ in range(30):
        c.run_frame()
    assert peek(c, 'gameState') == 0, "menyn visas inte"
    if shots:
        c.render(os.path.join(shots, 'menu.png'))

    # starta
    c.joy = 16
    c.run_frame()
    c.joy = 0
    for _ in range(3):
        c.run_frame()
    assert peek(c, 'gameState') == 1, "spelet startade inte"
    c.frame_busy.clear()

    seen = set()
    taken = set()
    for f in range(4000):
        c.joy = bot(c, f)
        c.ram[addr(c, 'lives')] = 3          # oändliga liv under testet
        c.run_frame()
        ph = peek(c, 'phase')
        if ph not in seen:
            print("bildruta %5d: fas %d" % (f, ph))
            seen.add(ph)
        # skärmbild när spelaren och minst ett monster syns
        visible = c.io[0x15] & 1 and peek(c, 'pState') == 0 and any(
            c.io[0x15] & (1 << n) and 60 < c.io[n * 2] + (256 if c.io[0x10] & (1 << n) else 0) < 300
            for n in range(3, 8))
        if shots and visible and ph == 0 and f > 500 and 'run' not in taken:
            c.render(os.path.join(shots, 'run.png'))
            taken.add('run')
        if shots and visible and ph == 2 and f > 2600 and 'fly' not in taken:
            c.render(os.path.join(shots, 'fly.png'))
            taken.add('fly')
        if ph == 2 and f > 3200:
            break
    assert seen == {0, 1, 2}, "alla faser nåddes inte: %s" % seen
    busy = max(c.frame_busy[2:])
    print("mest CPU-tid i en bildruta: %d cykler (%.0f%%)" % (busy, 100.0 * busy / FRAME_CYCLES))
    assert busy < FRAME_CYCLES, "en bildruta tog för lång tid"

    # ge en topplisteplacering och låt spelaren dö
    s = addr(c, 'score')
    c.ram[s:s + 3] = bytes([0x00, 0x47, 0x11])
    c.ram[addr(c, 'lives')] = 1
    c.ram[addr(c, 'invuln')] = 0
    c.joy = 0
    for _ in range(2000):
        c.run_frame()
        if peek(c, 'gameState') == 2:
            break
    assert peek(c, 'gameState') == 2, "game over kom aldrig"
    for _ in range(220):
        c.run_frame()
    assert peek(c, 'hsPos') < 10, "resultatet hamnade inte på topplistan"
    for _ in range(3):                      # tre tryck på fire = "AAA"
        c.joy = 16
        c.run_frame()
        c.joy = 0
        c.run_frame()
    for _ in range(10):
        c.run_frame()
    assert peek(c, 'gameState') == 0, "kom inte tillbaka till menyn"
    pos = peek(c, 'hsPos')
    name = bytes(c.ram[addr(c, 'hsName') + pos * 3: addr(c, 'hsName') + pos * 3 + 3])
    assert name == b'\x01\x01\x01', "namnet sparades inte: %r" % name
    print("topplistan: plats %d, namn AAA" % (pos + 1))
    print("OK")


if __name__ == '__main__':
    main()
