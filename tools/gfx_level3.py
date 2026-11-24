#!/usr/bin/env python3
"""
Grafik för nivå 3 (banan ovanifrån), delad mellan tools/make_gfx.py
(som gör assemblerdata av den) och tools/mockup_level3.py (skärmbilder).

  * Block (metatiles): 2x2 multicolor-tecken = 8x16 "feta" pixlar.
    '.' = $d021 (gräs, grön)   'l' = $d022 (ljusgrön)
    'b' = $d023 (brun)         'k' = färg-RAM (svart, samma i hela banan)
  * Multicolor-sprites 12x21: '.', 'w' = $d025, 'b' = egen färg,
    's' = $d026. På nivå 3 är $d025 svart (konturer, gevär, kängor) och
    $d026 ljusröd (hud).
  * Hires-sprites 24x21: '#' = spritens färg.
"""
import math

BG, C1, C2, CR = 5, 13, 9, 0       # grön, ljusgrön, brun, svart

# ------------------------------------------------------------ metatiles 8x16
META = {
    '.': [
        "........", "........", "..l.....", "........", "........", ".....l..",
        "........", "........", "........", ".l......", "........", "........",
        "......l.", "........", "...l....", "........"],
    ',': [
        "........", ".....l..", "........", "........", ".l......", "........",
        "........", "......l.", "........", "........", "...l....", "........",
        "........", ".l......", "........", "........"],
    'T': [  # träd/buske uppifrån, skugga nere till höger
        "..llll..", ".llllll.", "llll.lll", "llllllll", "ll.lllll", "llllll.l",
        "lllllllk", "l.llllkk", "lllll.lk", "llllllkk", ".lllllk.", "..lllkk.",
        "...kkk..", "....k...", "........", "........"],
    'S': [  # sandsäckar
        "........", "........", "bbbkbbbk", "bbbkbbbk", "kkkkkkkk", "bkbbbkbb",
        "bkbbbkbb", "kkkkkkkk", "bbbkbbbk", "bbbkbbbk", "kkkkkkkk", "kkkkkkkk",
        "........", "........", "........", "........"],
    'C': [  # öppen trälåda snett uppifrån, de gröna granaterna syns
        "........", "kkkkkkkk", "kbbbbbbk", "kllkkllk", "kllkkllk", "kkkllkkk",
        "kbkllkbk", "kkkkkkkk", "kbbbbbbk", "kbkbbkbk", "kbbbbbbk", "kbkbbkbk",
        "kbbbbbbk", "kkkkkkkk", ".kkkkkkk", "........"],
    # Taggtråd: stolpar med tre trådar och taggar. Läggs i rad till stängsel;
    # sista blocket i en rad får en stolpe även till höger ('Z').
    'X': [
        "bb......", "bbk...k.", "kkkkkkkk", "bb.k...k", "bb......", "bbk...k.",
        "kkkkkkkk", "bb.k...k", "bb......", "bbk...k.", "kkkkkkkk", "bb.k...k",
        "bb......", "kk......", ".k......", "........"],
    'Z': [
        "bb....bb", "bbk...bb", "kkkkkkkk", "bb.k..bb", "bb....bb", "bbk...bb",
        "kkkkkkkk", "bb.k..bb", "bb....bb", "bbk...bb", "kkkkkkkk", "bb.k..bb",
        "bb....bb", "kk....kk", ".k.....k", "........"],
    # Muren: tegelmönster med period 8 rader, så att block kan staplas
    # utan skarv. 'W' = övre raden, 'V' = nedre raden med skugga mot gräset.
    'W': [
        "kkkkkkkk", "bbbkbbbb", "bbbkbbbb", "bbbkbbbb",
        "kkkkkkkk", "bbbbbbbk", "bbbbbbbk", "bbbbbbbk",
        "kkkkkkkk", "bbbkbbbb", "bbbkbbbb", "bbbkbbbb",
        "kkkkkkkk", "bbbbbbbk", "bbbbbbbk", "bbbbbbbk"],
    'V': [
        "kkkkkkkk", "bbbkbbbb", "bbbkbbbb", "bbbkbbbb",
        "kkkkkkkk", "bbbbbbbk", "bbbbbbbk", "bbbbbbbk",
        "kkkkkkkk", "bbbkbbbb", "bbbkbbbb", "bbbkbbbb",
        "kkkkkkkk", "kkkkkkkk", "k.k.k.k.", "........"],
    # Porten: 2x2 block (32x32 px). G/H = övre vänster/höger, I/J = nedre.
    'G': [
        "kkkkkkkk", "kkkkkkkk", "kkbkbkbk", "kkbkbkbk", "kkbkbkbk", "kkkkkkkk",
        "kkbkbkbk", "kkbkbkbk", "kkbkbkbk", "kkbkbkbk", "kkbkbkbk", "kkbkbkbk",
        "kkbkbkbk", "kkbkbkbk", "kkbkbkbk", "kkbkbkbk"],
    'I': [
        "kkbkbkbk", "kkbkbkbk", "kkkkkkkk", "kkbkbkbk", "kkbkbkbk", "kkbkbkbk",
        "kkbkbkbk", "kkbkbkbk", "kkbkbkbk", "kkkkkkkk", "kkbkbkbk", "kkbkbkbk",
        "kkkkkkkk", "kkkkkkkk", "k.k.k.k.", "........"],
    # skadad port (sprickor och lösa plankor)
    'g': [
        "kkkkkkkk", "kkkkkkkk", "kkbkbkbk", "kkbkkkbk", "kkbkbkkk", "kkkkkkkk",
        "kkbkbkbk", "kkkkbkbk", "kkbkbkbk", "kkbkbkkk", "kkbkkkbk", "kkkkbkbk",
        "kkbkbkbk", "kkbkbkbk", "kkkkbkbk", "kkbkbkbk"],
    'i': [
        "kkbkbkkk", "kkbkbkbk", "kkkkkkkk", "kkbkkkbk", "kkkkbkbk", "kkbkbkbk",
        "kkbkbkkk", "kkbkbkbk", "kkkkbkbk", "kkkkkkkk", "kkbkbkbk", "kkbkkkbk",
        "kkkkkkkk", "kkkkkkkk", "k.k.k.k.", "........"],
    # sprängd port: öppning med grus
    'R': [
        "kkkkkkkk", ".k..b...", "..bkb.k.", ".b.....b", "k..bk...", "..k..b.k",
        ".b.k....", "....bk..", "k.b...b.", "..k.b..k", ".b...k..", "...b..b.",
        "k..k....", "..b...k.", ".k..b...", "........"],
    'r': [
        "........", ".k..b...", "..b...k.", ".b.k...b", "k...k...", "..k..b.k",
        ".b......", "....bk..", "k.b.....", "..k.b..k", ".b...k..", "...b....",
        "k..k....", "........", "........", "........"],
    'O': [  # krater efter granat
        "........", "........", "..kkkk..", ".kbbbbk.", "kbb..bbk", "kb....bk",
        "kbb..bbk", ".kbbbbk.", "..kkkk..", "........", "........", "........",
        "........", "........", "........", "........"],
}
for _l, _r in (('G', 'H'), ('I', 'J'), ('g', 'h'), ('i', 'j')):
    META[_r] = [row[::-1] for row in META[_l]]


# ------------------------------------------------------------ sprites 12x21
SPR = {
    'PLAYER_UP': [
        "............",
        ".......w....",
        ".......w....",
        "....wwww....",
        "...wbbbbw...",
        "...wbbbbw...",
        "....wssw....",
        "...wbbbbw...",
        "..wbbwwbbw..",
        "..wbwbbwbw..",
        "..wbwbbwbw..",
        "..wbbwwbbw..",
        "..wsbbbbsw..",
        "...wwwwww...",
        "...wbbbbw...",
        "...wbw.wbw..",
        "...wbw.wbw..",
        "...wbw.www..",
        "...wbw......",
        "...www......",
    ],
    'PLAYER_UP2': [
        "............",
        ".......w....",
        ".......w....",
        "....wwww....",
        "...wbbbbw...",
        "...wbbbbw...",
        "....wssw....",
        "...wbbbbw...",
        "..wbbwwbbw..",
        "..wbwbbwbw..",
        "..wbwbbwbw..",
        "..wbbwwbbw..",
        "..wsbbbbsw..",
        "...wwwwww...",
        "...wbbbbw...",
        "...wbw.wbw..",
        "...wbw.wbw..",
        "...www.wbw..",
        ".......wbw..",
        ".......www..",
    ],
    'ENEMY_DOWN': [
        "............",
        "....wwww....",
        "...wbbbbw...",
        "..wwbbbbww..",
        "...wssssw...",
        "...wwssww...",
        "....wssw....",
        "...wbbbbw...",
        "..wbbbbbbw..",
        "..wswwwwsww.",
        "..wbbbbbbw..",
        "..wbbbbbbw..",
        "...wwwwww...",
        "...wbbbbw...",
        "...wbw.wbw..",
        "...wbw.wbw..",
        "...wbw.www..",
        "...wbw......",
        "...www......",
    ],
    'ENEMY_DOWN2': [
        "............",
        "....wwww....",
        "...wbbbbw...",
        "..wwbbbbww..",
        "...wssssw...",
        "...wwssww...",
        "....wssw....",
        "...wbbbbw...",
        "..wbbbbbbw..",
        "..wswwwwsww.",
        "..wbbbbbbw..",
        "..wbbbbbbw..",
        "...wwwwww...",
        "...wbbbbw...",
        "...wbw.wbw..",
        "...wbw.wbw..",
        "...www.wbw..",
        ".......wbw..",
        ".......www..",
    ],
    'GSHADOW': [
        "............",
        "....bb......",
        "...bbbb.....",
        "....bb......",
    ],
    'ENEMY_THROW': [
        ".........ww.",
        "....wwww.ww.",
        "...wbbbbwsw.",
        "..wwbbbbwbw.",
        "...wssssw.bw",
        "...wwsswwbw.",
        "....wsswwbw.",
        "...wbbbbbbw.",
        "..wbbbbbbw..",
        "..wswwwww...",
        "..wbbbbbbw..",
        "..wbbbbbbw..",
        "...wwwwww...",
        "...wbbbbw...",
        "...wbw.wbw..",
        "...wbw.wbw..",
        "...www.www..",
    ],
    'HANG': [  # gubben i selen, sedd bakifrån/underifrån
        "....w..w....",
        "....w..w....",
        "....s..s....",
        "...bsbbsb...",
        "...bwwwwb...",
        "...bwwwwb...",
        "....bbbb....",
        "...bbbbbb...",
        "..bbbbbbbb..",
        "..sbbbbbbs..",
        "...bbbbbb...",
        "...bb..bb...",
        "...bb..bb...",
        "...bb..bb...",
        "...ss..ss...",
    ],
    'SHADOW': [
        "...bbbbbb...",
        ".bbbbbbbbbb.",
        "bbbbbbbbbbbb",
        ".bbbbbbbbbb.",
        "...bbbbbb...",
    ],
    # Explosion: gul kärna ('b'), ljusröd ring ('s'), svart rök ('w')
    'BOOM0': [
        "............",
        ".....s......",
        "...s.ss.s...",
        "....sbbs....",
        "..ssbbbbss..",
        "...sbbbbs...",
        "..ssbbbbss..",
        "....sbbs....",
        "...s.ss.s...",
        ".....s......",
    ],
    'BOOM1': [
        "..w..s...w..",
        "....sss.....",
        ".s.sbbbss.s.",
        "..sbbbbbbs..",
        ".ssbbbbbbbs.",
        "..sbbbbbbss.",
        ".ssbbbbbbs..",
        "..sbbbbbbs..",
        ".s.ssbbss.s.",
        "....sss.....",
        "..w..s...w..",
    ],
    'GRENADE': [
        "....ww......",
        "...wbbw.....",
        "...wbbw.....",
        "....ww......",
    ],
    'EBULLET': [
        ".ss.........",
        "sbbs........",
        ".ss.........",
    ],
}


def make_canopy():
    """Fallskärmen: vit hires-bild 48x42 pixlar (fyra hires-sprites, 2x2).
    Kupol sedd snett underifrån/söderifrån. Sömmarna (genomskinliga) går i
    bågar från toppen ned till en bågad kant med fickor; linorna går från
    sömmarnas nederkant ned till gubbens händer.
    Returnerar fyra listor med 21 strängar à 24 tecken ('#' = vit pixel)."""
    import math
    W, H = 48, 42
    img = [[0] * W for _ in range(H)]
    cx, yeq, R, HD, E = 23.5, 18.0, 23.0, 17.0, 3.0

    def rim_bottom(phi):                     # kantens underkant med fickor
        k = 12                               # antal fickor över fronten
        bulge = abs(math.sin((phi + math.pi / 2) * k / 2))
        return yeq + E * math.cos(phi) + 1.6 * bulge

    for y in range(H):                       # fyll kupolen
        for x in range(W):
            dx = (x + 0.5 - cx) / R
            if abs(dx) > 1:
                continue
            phi = math.asin(dx)
            top = yeq - HD * math.sqrt(max(0.0, 1 - dx * dx))
            if top <= y + 0.5 <= rim_bottom(phi):
                img[y][x] = 1

    def clear(px, py):
        if 0 <= px < W and 0 <= py < H:
            img[py][px] = 0

    seams = [math.radians(a) for a in (-75, -52, -28, 0, 28, 52, 75)]
    for phi in seams:                        # sömmar: meridianer från toppen
        for i in range(200):
            lam = math.radians(90 * i / 199)  # 90 = toppen, 0 = kanten
            x = cx + R * math.cos(lam) * math.sin(phi)
            y = yeq - HD * math.sin(lam) + E * math.cos(lam) * math.cos(phi)
            if i > 12:                        # lite luft vid toppen
                clear(int(x), int(y))
    for i in range(300):                     # fickornas ring nära kanten
        phi = -math.pi / 2 + math.pi * i / 299
        lam = math.radians(16)
        x = cx + R * math.cos(lam) * math.sin(phi)
        y = yeq - HD * math.sin(lam) + E * math.cos(lam) * math.cos(phi)
        clear(int(x), int(y))

    def line(x0, y0, x1, y1):                # linor (Bresenham)
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            if 0 <= x0 < W and 0 <= y0 < H:
                img[y0][x0] = 1
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    for phi in seams:
        x = cx + R * math.sin(phi)
        y = rim_bottom(phi)
        hand = 21 if phi < 0 else (26 if phi > 0 else 23)
        line(x, y, hand, H - 1)

    rows = [''.join('#' if v else '.' for v in r) for r in img]
    tl = [r[:24] for r in rows[:21]]
    tr = [r[24:] for r in rows[:21]]
    bl = [r[:24] for r in rows[21:]]
    br = [r[24:] for r in rows[21:]]
    return tl, tr, bl, br


HIRES = {}

# Gubben i selen under hoppet: tre hires-sprites (en färg var) på samma
# koordinater ger hires-upplösning med tre färger.
#   k = svart (hjälm, sele, kängor)  s = ljusröd (händer, nacke)  c = cyan (uniform)
JUMPER = [
    ".........s....s.........",
    ".........ss..ss.........",
    ".........cc..cc.........",
    ".........cc..cc.........",
    ".........ckkkkc.........",
    "........cckkkkcc........",
    "........ckkkkkkc........",
    "........ckkkkkkc........",
    "........cksssskc........",
    ".......cccckkcccc.......",
    ".......ckcccccckc.......",
    ".......ckcccccckc.......",
    ".......ckckkkkckc.......",
    ".......ckcccccckc.......",
    "........kkcccckk........",
    "........ccc..ccc........",
    "........cc....cc........",
    "........cc....cc........",
    "........cc....cc........",
    "........kk....kk........",
    "........kkk...kkk.......",
]
assert all(len(r) == 24 for r in JUMPER) and len(JUMPER) == 21
JUMPER_LAYERS = (('k', 0), ('s', 10), ('c', 3))   # färg per lager (svart överst)
for _ch, _col in JUMPER_LAYERS:
    HIRES['JUMPER_' + _ch.upper()] = [''.join('#' if c == _ch else '.' for c in r) for r in JUMPER]
HIRES['CANOPY_TL'], HIRES['CANOPY_TR'], HIRES['CANOPY_BL'], HIRES['CANOPY_BR'] = make_canopy()


# Teckenkoder för varje block (4 tecken: övre vänster/höger, nedre vänster/höger).
# Passerbara block ligger på 88-111, lådan på 108, taggtråden på 112-119
# och allt som stoppar gubben på 192 och uppåt.
TILE_ORDER = [
    # nyckel, namn,       teckenkod
    ('.', 'GRASS0',   88),
    (',', 'GRASS1',   92),
    ('O', 'CRATER',   96),
    ('R', 'RUBBLE_T', 100),
    ('r', 'RUBBLE_B', 104),
    ('C', 'CRATE',    108),
    ('X', 'WIRE',     112),
    ('Z', 'WIRE_END', 116),
    ('T', 'TREE',     192),
    ('S', 'SANDBAG',  196),
    ('W', 'WALL',     200),
    ('V', 'WALL_B',   204),
    ('G', 'GATE_TL',  208),
    ('H', 'GATE_TR',  212),
    ('I', 'GATE_BL',  216),
    ('J', 'GATE_BR',  220),
    ('g', 'GATED_TL', 224),
    ('h', 'GATED_TR', 228),
    ('i', 'GATED_BL', 232),
    ('j', 'GATED_BR', 236),
]
TD_PASS_FIRST, TD_CRATE_FIRST, TD_WIRE_FIRST, TD_SOLID_FIRST = 88, 108, 112, 192
