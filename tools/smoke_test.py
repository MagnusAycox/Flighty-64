#!/usr/bin/env python3
"""
Automatiskt röktest för Flighty 64 (utan KickAssembler/VICE).

1. Bygger src/main.asm med tools/ka_subset.py
2. Kör spelet i tools/emu.py med en enkel "bot" som spelar:
   meny -> springfas (4 vågor) -> rymdskepp -> flygfas (4 vågor)
   -> landning -> nivå 2 -> game over -> topplista
3. Kontrollerar att inget kraschar, att alla faser och alla monstertyper
   dyker upp och att en bildruta aldrig tar mer CPU-tid än vad som finns.

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
    monsters = set()
    for f in range(9000):
        c.joy = bot(c, f)
        c.ram[addr(c, 'lives')] = 3          # oändliga liv under testet
        c.run_frame()
        ph = peek(c, 'phase')
        st = (peek(c, 'level'), ph, peek(c, 'wave'))
        if st not in seen:
            print("bildruta %5d: nivå %d, fas %d, våg %d" % ((f,) + st))
            seen.add(st)
        for i in range(5):
            monsters.add(peek(c, 'M_TYPE', i))
        # skärmbild när spelaren och ett av de nya monstren syns
        def shown(types):
            for n in range(3, 8):
                x = c.io[n * 2] + (256 if c.io[0x10] & (1 << n) else 0)
                if c.io[0x15] & (1 << n) and 80 < x < 300 and peek(c, 'M_TYPE', n - 3) in types:
                    return True
            return False
        ok = shots and c.io[0x15] & 1 and peek(c, 'pState') == 0 and peek(c, 'waveCol') > 40
        if ok and ph == 0 and 'run' not in taken and shown((5, 6)) and peek(c, 'B_ON', 0):
            c.render(os.path.join(shots, 'run.png'))
            taken.add('run')
        if ok and ph == 2 and 'fly' not in taken and shown((7,)) and peek(c, 'B_ON', 0):
            c.render(os.path.join(shots, 'fly.png'))
            taken.add('fly')
        if peek(c, 'level') == 2 and peek(c, 'wave') == 1:
            break
    phases = {p for _, p, _ in seen}
    assert phases == {0, 1, 2, 3}, "alla faser nåddes inte: %s" % phases
    assert peek(c, 'level') == 2, "nivå 2 nåddes inte"
    assert {1, 2, 5, 6, 7} <= monsters, "alla monstertyper syntes inte: %s" % monsters
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
