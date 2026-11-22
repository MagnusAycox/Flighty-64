#!/usr/bin/env python3
"""
Automatiskt röktest för Flighty 64 (utan KickAssembler/VICE).

1. Bygger src/main.asm med tools/ka_subset.py
2. Kör spelet i tools/emu.py med en enkel "bot" som spelar:
   meny (logo-effekten) -> springfas (4 vågor) -> rymdskepp -> flygfas (4 vågor)
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

    # startskärmens logo: blå/gul flagga i logons rasterlinjer, svart utanför
    bars = set()
    row6 = []
    sprite_x = set()
    gif = []
    for f in range(128):
        c.run_frame()
        d021 = [c.line_regs[line][4] & 15 for line in range(55, 87)]
        assert d021[:4] == [0] * 4 and d021[-4:] == [0] * 4, "färgbyte utanför logon: %s" % d021
        inside = d021[4:28]
        assert set(inside) == {6, 7}, "logon ska ha blå och gul: %s" % inside
        assert inside.count(7) == 5, "vågräta balken ska vara 5 rader"
        bars.add(inside.index(7))
        # rulltexten på rad 6 (rasterlinje 99-106) har egen finscroll
        d016 = [c.line_regs[line][1] & 0x1f for line in range(97, 109)]
        assert d016[0] == d016[1] == 0x08 and d016[-1] == 0x08, "fel $d016 runt rulltexten: %s" % d016
        assert len(set(d016[2:10])) == 1 and d016[2] < 8, "rulltextens $d016 ska vara 38 kolumner + finscroll: %s" % d016
        row6.append(bytes(c.ram[addr(c, 'SCREEN_A') + 240: addr(c, 'SCREEN_A') + 280]))
        sprite_x.add(c.io[0] | ((c.io[0x10] & 1) << 8))
        if shots and f % 2 == 0:
            from PIL import Image
            c.render(os.path.join(shots, '.frame.png'), scale=1)
            gif.append(Image.open(os.path.join(shots, '.frame.png')).crop((32, 24, 352, 104)).convert('P'))
    assert c.io[0x1b] & 1 and c.io[0x17] & 1, "flaggbalken ska vara höjdförstorad och bakom texten"
    assert len(set(row6)) > 20, "rulltexten rör sig inte"
    assert any(b'\x02\x19\x20\x12\x0f\x0e' in r for r in row6), "krediten syns inte i rulltexten"
    assert min(bars) == 0 and max(bars) == 19, "balken studsar inte hela vägen: %s" % sorted(bars)
    assert max(sprite_x) - min(sprite_x) > 200, "lodräta balken rör sig inte i sidled"
    print("logo: vågrät balk rad %d-%d, lodrät balk x %d-%d" % (min(bars), max(bars), min(sprite_x), max(sprite_x)))
    if shots:
        os.remove(os.path.join(shots, '.frame.png'))
        gif = [im.resize((640, 160)) for im in gif]
        gif[0].save(os.path.join(shots, 'logo.gif'), save_all=True, append_images=gif[1:],
                    duration=40, loop=0)

    # starta
    c.joy = 16
    c.run_frame()
    c.joy = 0
    for _ in range(3):
        c.run_frame()
    assert peek(c, 'gameState') == 1, "spelet startade inte"
    assert c.io[0x1b] == 0 and c.io[0x17] == 0 and c.io[0x1c] == 0xff, "spritelägen inte återställda"
    assert peek(c, 'logoOn') == 0, "logons raster körs fortfarande"
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
