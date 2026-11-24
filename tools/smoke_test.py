#!/usr/bin/env python3
"""
Automatiskt röktest för Flighty 64 (utan KickAssembler/VICE).

1. Bygger src/main.asm med tools/ka_subset.py
2. Kör spelet i tools/emu.py med en enkel "bot" som spelar:
   meny (logo-effekten) -> springfas (4 vågor) -> rymdskepp -> flygfas (4 vågor)
   -> landning -> nivå 2 -> game over -> topplista
   och sedan nivå 3 (banan ovanifrån): slutet av nivå 2 -> "PREPARE TO
   JUMP" -> fallskärmshopp -> 4 vågor -> STAGE CLEAR -> nivå 4
3. Kontrollerar att inget kraschar, att alla faser och alla monstertyper
   dyker upp och att en bildruta aldrig tar mer CPU-tid än vad som finns.

Kör:  python3 tools/smoke_test.py [--shots katalog] [--level3]
      (--level3: bara testet av nivå 3)
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


class TdView:
    """Det nivå 3-boten behöver veta, läst ur minnet via get(namn, antal)."""

    def __init__(self, get):
        self.get = get
        st = get('tdState', 1)[0]
        self.state = st
        self.px = get('px', 1)[0] + 256 * get('pxHi', 1)[0]
        self.py = get('py', 1)[0]
        self.fine = get('tdFine', 1)[0]
        self.wrow = get('tdWrow', 1)[0]
        self.ring = get('MAP_RING', 64 * 40) if st == 2 else None

    def char_at(self, x, y):
        """Samma uträkning som tdCharAt i topdown.asm."""
        line = y + 1
        top = 64 + self.fine
        row = self.wrow + 1 if line < top else self.wrow - ((line - top) >> 3)
        col = max(0, min(39, (x - 24) >> 3))
        return self.ring[(row & 63) * 40 + col]

    def solid(self, x, y):
        return self.char_at(x, y) >= 192


TD_BOX = ((6, 4), (17, 4), (6, 16), (17, 16))     # samma hörn som tdBlocked


_td_plan = {'path': [], 'key': None, 'idle': 0}


def td_bot(v, f):
    """Nivå 3: hitta en väg (bredden först, rutnät på 4 pixlar) från gubben
    till överkanten av spelplanen där banan kan scrolla vidare, och följ den
    tills den är gången (eller banan har scrollat)."""
    if v.state != 2:
        return 0
    j = 16 if f % 10 < 2 else 0
    plan = _td_plan

    def free(x, y):
        return not any(v.solid(x + a, y + b) for a, b in TD_BOX)

    key = (v.wrow, v.fine)
    if plan['key'] != key or not plan['path'] or plan['idle'] > 8:
        plan['key'] = key
        plan['idle'] = 0
        plan['path'] = td_find_path(v, free)
    path = plan['path']
    while path and path[0] == (v.px, v.py):
        path.pop(0)
        plan['idle'] = 0
    if not path:
        if v.py <= 120 and free(v.px, v.py - 1):
            return j | 1        # vid överkanten: uppåt (banan scrollar)
        return j | 2            # ingen väg syns: backa
    nx, ny = path[0]
    plan['idle'] += 1
    if nx < v.px:
        j |= 4
    elif nx > v.px:
        j |= 8
    if ny < v.py:
        j |= 1
    elif ny > v.py:
        j |= 2
    return j


def td_find_path(v, free):
    """Bredden först från gubben till en plats vid överkanten där han kan gå
    uppåt. Rutnät på 4 pixlar, vägen returneras som en lista positioner."""
    step = 4
    start = (v.px, v.py)
    prev = {start: None}
    queue = [start]
    goal = None
    i = 0
    while i < len(queue):
        x, y = queue[i]
        i += 1
        if y <= 120 and free(x, y - 1):
            goal = (x, y)
            break
        for nx, ny in ((x, max(120, y - step)), (max(24, x - step), y),
                       (min(320, x + step), y), (x, min(222, y + step))):
            if (nx, ny) not in prev and free(nx, ny):
                prev[(nx, ny)] = (x, y)
                queue.append((nx, ny))
    if goal is None:
        return []
    path = []
    node = goal
    while node != start:
        path.append(node)
        node = prev[node]
    path.reverse()
    # dela upp i steg om 1 pixel (spelaren går 1 pixel per bildruta och axel)
    fine, (x, y) = [], start
    for nx, ny in path:
        while (x, y) != (nx, ny):
            x += (nx > x) - (nx < x)
            y += (ny > y) - (ny < y)
            fine.append((x, y))
    return fine


def emu_reader(c):
    def get(name, n):
        a = addr(c, name)
        return bytes(c.ram[a:a + n])
    return get


def test_level3(shots=None):
    """Nivå 3: övergången från nivå 2, hoppet, vågorna och nivå 4."""
    c = emu.load(PRG, SYM)
    for _ in range(20):
        c.run_frame()
    c.ram[addr(c, 'debugLevel')] = 2
    c.joy = 16
    c.run_frame()
    c.joy = 0
    for _ in range(3):
        c.run_frame()
    assert peek(c, 'level') == 2 and peek(c, 'tdOn') == 0, "nivå 2 startade inte"
    # hoppa till slutet av flygfasen på nivå 2
    c.ram[addr(c, 'phase')] = 2
    c.ram[addr(c, 'wave')] = 3
    c.ram[addr(c, 'waveCol')] = 159
    for f in range(600):
        c.ram[addr(c, 'lives')] = 3
        c.ram[addr(c, 'invuln')] = 10
        c.run_frame()
        if peek(c, 'tdOn'):
            break
    assert peek(c, 'tdOn') == 1 and peek(c, 'level') == 3, "nivå 3 startade inte efter nivå 2"
    print("nivå 3: startade efter %d bildrutor (PREPARE TO JUMP)" % f)
    c.frame_busy.clear()

    # fallskärmshoppet: gubben sjunker, åtta sprites (4 kupol, 3 lager, skugga)
    ys = []
    for f in range(400):
        c.joy = 8 if 30 < f < 50 else 0
        c.run_frame()
        if peek(c, 'tdState') == 0 and (ys or peek(c, 'py') < 110):   # efter tdStart
            ys.append(peek(c, 'py'))
            if len(ys) == 20:
                assert c.io[0x15] == 0xff, "fallskärmen ska använda alla 8 sprites"
                assert c.io[0x1c] == 0x80, "fallskärm och gubbe ska vara hires, skuggan multicolor"
                if shots:
                    c.render(os.path.join(shots, 'niva3_fallskarm.png'))
        if peek(c, 'tdState') == 2:
            break
    assert peek(c, 'tdState') == 2, "landade aldrig"
    assert ys == sorted(ys) and ys[-1] - ys[0] > 60, "gubben sjunker inte"
    print("nivå 3: landade efter %d bildrutor" % f)

    # spela: banan scrollar, vågorna byts, STAGE CLEAR, nivå 4
    seen = set()
    wrow0, stuck, last_wrow = peek(c, 'tdWrow'), 0, None
    for f in range(9000):
        v = TdView(emu_reader(c))
        c.joy = td_bot(v, f)
        c.ram[addr(c, 'lives')] = 3
        c.run_frame()
        st = (peek(c, 'level'), peek(c, 'tdOn'), peek(c, 'wave'), peek(c, 'tdState'))
        if st not in seen:
            print("bildruta %5d: nivå %d, ovanifrån %d, våg %d, läge %d" % ((f,) + st))
            seen.add(st)
        if peek(c, 'tdOn') and peek(c, 'tdState') == 2:
            # HUD-raden 25 rader/yscroll 3, spelplanen 24 rader/yscroll = tdFine
            d011_hud = c.line_regs[52][0]
            d011_play = c.line_regs[100][0]
            assert d011_hud == 0x1b, "HUD-radens $d011: %02x" % d011_hud
            assert d011_play & 0x18 == 0x10, "spelplanens $d011: %02x" % d011_play
            w = peek(c, 'tdWrow')
            stuck = stuck + 1 if w == last_wrow else 0
            last_wrow = w
            if stuck >= 600 and shots:
                c.render(os.path.join(shots, 'niva3_fast.png'))
            assert stuck < 600, "boten har fastnat vid världsrad %d" % w
            if shots and f == 700:
                c.render(os.path.join(shots, 'niva3_spel.png'))
        if peek(c, 'level') == 4 and peek(c, 'tdOn') == 0:
            break
    assert peek(c, 'level') == 4 and peek(c, 'tdOn') == 0 and peek(c, 'phase') == 0, \
        "nivå 4 (springfas) startade inte efter nivå 3"
    assert {s[2] for s in seen if s[1]} == {0, 1, 2, 3}, "alla vågor på nivå 3 nåddes inte"
    busy = max(c.frame_busy[2:])
    print("nivå 3: klar efter %d bildrutor, mest CPU-tid %d cykler (%.0f%%)" % (
        f, busy, 100.0 * busy / FRAME_CYCLES))
    assert busy < FRAME_CYCLES, "en bildruta tog för lång tid"


def main():
    shots = None
    if '--shots' in sys.argv:
        shots = sys.argv[sys.argv.index('--shots') + 1]
        os.makedirs(shots, exist_ok=True)

    r = subprocess.run([sys.executable, os.path.join(HERE, 'ka_subset.py'),
                        os.path.join(ROOT, 'src', 'main.asm'), '-o', PRG, '--sym', SYM])
    if r.returncode:
        sys.exit("Bygget misslyckades")
    if '--level3' in sys.argv:
        test_level3(shots)
        print("OK")
        return

    c = emu.load(PRG, SYM)
    for _ in range(30):
        c.run_frame()
    assert peek(c, 'gameState') == 0, "menyn visas inte"
    if shots:
        c.render(os.path.join(shots, 'menu.png'))

    # startskärmens logo: blå/gul flagga i logons rasterlinjer, svart utanför,
    # bokstäverna böljar (egen finscroll per rasterlinje). Korset studsar:
    # vågräta balken mellan topp och golv (ihoptryckt vid golvet), lodräta
    # balken med jämn fart mellan väggarna (ihoptryckt vid väggen)
    wave = c.ram[addr(c, 'waveTab'):addr(c, 'waveTab') + 64]
    sym_spr = addr(c, 'SPR_FLAGBAR4')
    bars = []
    sprite_ptr = []
    row6 = []
    sprite_x = []
    gif = []
    for f in range(1024):
        c.run_frame()
        d021 = [c.line_regs[line][4] & 15 for line in range(55, 87)]
        assert d021[:4] == [0] * 4 and d021[-4:] == [0] * 4, "färgbyte utanför logon: %s" % d021
        inside = d021[4:28]
        assert set(inside) == {6, 7}, "logon ska ha blå och gul: %s" % inside
        top, n = inside.index(7), inside.count(7)
        assert 3 <= n <= 6 and inside[top:top + n] == [7] * n, "vågräta balken ska vara 3-6 rader i ett stycke: %s" % inside
        bars.append((top, n))
        d016 = [c.line_regs[line][1] for line in range(59, 83)]
        assert all(v & 0xf8 == 0 for v in d016), "logon ska vara 38 kolumner: %s" % d016
        xs = [v & 7 for v in d016]
        assert any(all(xs[i] == wave[(p + 3 * i) & 63] for i in range(24)) for p in range(64)),             "bokstäverna följer inte sinusvågen: %s" % xs
        assert c.line_regs[83][1] == 0x08, "menyn under logon ska ha 40 kolumner utan scroll"
        # rulltexten på rad 6 (rasterlinje 99-106) har egen finscroll
        d016 = [c.line_regs[line][1] & 0x1f for line in range(97, 109)]
        assert d016[0] == d016[1] == 0x08 and d016[-1] == 0x08, "fel $d016 runt rulltexten: %s" % d016
        assert len(set(d016[2:10])) == 1 and d016[2] < 8, "rulltextens $d016 ska vara 38 kolumner + finscroll: %s" % d016
        row6.append(bytes(c.ram[addr(c, 'SCREEN_A') + 240: addr(c, 'SCREEN_A') + 280]))
        sprite_x.append(c.io[0] | ((c.io[0x10] & 1) << 8))
        sprite_ptr.append(c.ram[addr(c, 'SCREEN_A') + 0x3f8])
        if shots and f < 300 and f % 2 == 0:
            from PIL import Image
            c.render(os.path.join(shots, '.frame.png'), scale=1)
            gif.append(Image.open(os.path.join(shots, '.frame.png')).crop((32, 24, 352, 104)).convert('P'))
    assert c.io[0x1b] & 1 and c.io[0x17] & 1, "flaggbalken ska vara höjdförstorad och bakom texten"
    assert len(set(row6)) > 20, "rulltexten rör sig inte"
    assert any(b'\x02\x19\x20\x12\x0f\x0e' in r for r in row6), "krediten syns inte i rulltexten"
    assert min(t for t, _ in bars) == 0, "balken studsar inte ända upp"
    floor = [(t, n) for t, n in bars if t + n == 24]
    assert any(n == 3 for _, n in floor), "balken trycks inte ihop mot golvet"
    assert sum(1 for t, n in bars if (t, n) == (21, 3)) >= 7, "för få studsar mot golvet"
    # ihoptryckt är balken 4 px bred, annars 6. Kanten mot väggen ligger
    # kvar, så minst en av kanterna flyttar högst 1 px per bildruta.
    right = [x + (4 if p == sym_spr else 6) for x, p in zip(sprite_x, sprite_ptr)]
    for i in range(len(sprite_x) - 1):
        assert min(abs(sprite_x[i + 1] - sprite_x[i]), abs(right[i + 1] - right[i])) <= 1,             "lodräta balken hoppar vid bildruta %d" % i
    steps = [b - a for a, b in zip(sprite_x, sprite_x[1:])]
    assert max(sprite_x) - min(sprite_x) > 260, "lodräta balken rör sig inte över hela texten"
    # vändningar bara vid väggarna, och där är balken ihoptryckt
    moving = [d for d in steps if d]
    turns = [i for i, (a, b) in enumerate(zip(moving, moving[1:])) if (a > 0) != (b > 0)]
    assert len(turns) >= 3, "lodräta balken studsar inte mellan väggarna"
    squashed = {x for x, p in zip(sprite_x, sprite_ptr) if p == sym_spr}
    assert squashed and all(x in (min(sprite_x), max(sprite_x)) for x in squashed),         "lodräta balken ska bara tryckas ihop vid väggarna: %s" % sorted(squashed)
    print("logo: vågrät balk rad 0-23 (%d golvstudsar), lodrät balk x %d-%d, %d väggstudsar" % (
        sum(1 for b in bars if b == (21, 3)), min(sprite_x), max(sprite_x), len(turns)))
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

    test_level3(shots)
    print("OK")


if __name__ == '__main__':
    main()
