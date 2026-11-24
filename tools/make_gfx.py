#!/usr/bin/env python3
"""
Genererar grafikdata för Flighty 64 från ASCII-konst.

Skapar:
  src/gfx_const.asm  - spritepekare, teckenkoder och kollisionsboxar (.const)
  src/gfx_data.asm   - tecken- och spritedata (.byte) + sinustabell

Kör:  python3 tools/make_gfx.py

Multicolor-sprites (12 x 21 "feta" pixlar):
  '.' = 00 transparent
  'w' = 01 $d025 (delad färg 1, vit)
  'b' = 10 spritens egen färg ($d027+n)
  's' = 11 $d026 (delad färg 2, ljusröd)

Multicolor-tecken (4 x 8 "feta" pixlar):
  '.' = 00 $d021 bakgrund
  'r' = 01 $d022 (sten)
  'd' = 10 $d023 (sprickor/skuggor)
  'g' = 11 färg-RAM (mossa/kristaller)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gfx_level3 as L3    # noqa: E402  grafiken för nivå 3 (banan ovanifrån)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

VIC_BANK = 0x8000
SPRITE_BASE_ADDR = 0xA000     # spritedata kopieras hit vid start ($9000-$9fff = tecken-ROM för VIC)
FIRST_CHAR = 64               # egna tecken: 64 och uppåt

LOGO_WIDTH = 272              # "SOFTWARE OF SWEDEN": 16 bokstäver x 16 px + 2 mellanslag x 8 px
LOGO_WAVE = 7                 # bokstävernas våg: 0-7 pixlar (finscroll per rasterlinje)
FLAG_BAR_W = 6
LOGO_ROWS = 24                # logons höjd i rasterlinjer
FLAG_BAR_H = 5                # vågräta balkens normala tjocklek
FLOOR = LOGO_ROWS - FLAG_BAR_H  # balkens översta rad när den ligger på golvet (19)
# Studsarna: höjd i rader över golvet. Bollen tappar fart för varje studs
# och får sedan en ny knuff (som när man dribblar en basketboll).
BOUNCES = [19, 13, 8, 4]
BOUNCE_T19 = 46               # bildrutor i luften för den högsta studsen

SPR_MAP = {'.': 0, 'w': 1, 'b': 2, 's': 3}
CHR_MAP = {'.': 0, 'r': 1, 'd': 2, 'g': 3}


def pad_sprite(rows, align="bottom"):
    rows = [r.ljust(12, '.') for r in rows]
    assert all(len(r) == 12 for r in rows), rows
    assert len(rows) <= 21, len(rows)
    empty = '.' * 12
    missing = 21 - len(rows)
    if align == "bottom":
        rows = [empty] * missing + rows
    elif align == "center":
        top = missing // 2
        rows = [empty] * top + rows + [empty] * (missing - top)
    else:
        rows = rows + [empty] * missing
    return rows


# ----------------------------------------------------------------- sprites
SPRITES = [
    ("RUN0", "bottom", [
        "....bbbb....",
        "...bbbbbb...",
        "...ssssss...",
        "...swsssw...",
        "...ssssss...",
        "....ssss....",
        ".....bb.....",
        "...bbbbbb...",
        "..bbbbbbbb..",
        "..b.bbbb.bs.",
        "..s.bbbb..ww",
        "....bbbb....",
        "....wwww....",
        "....bbbbb...",
        "...bb...bb..",
        "...bb...bb..",
        "..bb.....bb.",
        "..bb.....bb.",
        ".ww.......ww",
    ]),
    ("RUN1", "bottom", [
        "....bbbb....",
        "...bbbbbb...",
        "...ssssss...",
        "...swsssw...",
        "...ssssss...",
        "....ssss....",
        ".....bb.....",
        "...bbbbbb...",
        "..bbbbbbbb..",
        "..b.bbbb.bs.",
        "..s.bbbb..ww",
        "....bbbb....",
        "....wwww....",
        "....bbbb....",
        ".....bb.....",
        ".....bbb....",
        "....bb.bb...",
        "....bb.bb...",
        "....ww.ww...",
    ]),
    ("JUMP", "bottom", [
        "..s.bbbb....",
        "..bbbbbbb...",
        "..bssssss...",
        "...swsssw...",
        "...ssssss...",
        "....ssss....",
        ".....bb.....",
        "...bbbbbb...",
        "...bbbbbbb..",
        "....bbbb.bs.",
        "....bbbb..ww",
        "....bbbb....",
        "....wwww....",
        "...bbbbbb...",
        "..bb....bb..",
        ".bb......bb.",
        ".ww......ww.",
        "............",
        "............",
    ]),
    ("SHIP0", "top", [
        "............",
        "............",
        "............",
        "............",
        "............",
        ".bb.........",
        ".bbb........",
        ".bbbb..www..",
        "sbbbbbbwwwb.",
        "sbbbbbbbbbbb",
        "sbbbbbbbbbb.",
        ".bbbbbbbbb..",
        ".bbb........",
        ".bb.........",
    ]),
    ("SHIP1", "top", [
        "............",
        "............",
        "............",
        "............",
        "............",
        ".bb.........",
        ".bbb........",
        "wbbbb..www..",
        "ssbbbbbwwwb.",
        "ssbbbbbbbbbb",
        "ssbbbbbbbbb.",
        "wbbbbbbbbb..",
        ".bbb........",
        ".bb.........",
    ]),
    ("WALK0", "bottom", [
        "....bbbb....",
        "...bbbbbb...",
        "..bwwbbwwb..",
        "..bwsbbwsb..",
        ".bbbbbbbbbb.",
        ".bbssssssbb.",
        ".bbbwbbwbbb.",
        ".bbbbbbbbbb.",
        "..bbbbbbbb..",
        "..bb....bb..",
        "..bb.....bb.",
        ".sss.....sss",
    ]),
    ("WALK1", "bottom", [
        "............",
        "....bbbb....",
        "...bbbbbb...",
        "..bwwbbwwb..",
        "..bwsbbwsb..",
        ".bbbbbbbbbb.",
        ".bbssssssbb.",
        ".bbbwbbwbbb.",
        "..bbbbbbbb..",
        "...bb..bb...",
        "...bb..bb...",
        "..sss..sss..",
    ]),
    ("BAT0", "top", [
        "b..........b",
        "bb........bb",
        "bbb..bb..bbb",
        "bbbbbbbbbbbb",
        ".bbbwbbwbbb.",
        "..bbbbbbbb..",
        "...bssssb...",
        "....bbbb....",
        ".....bb.....",
    ]),
    ("BAT1", "top", [
        "............",
        "............",
        ".....bb.....",
        "..bbbbbbbb..",
        ".bbbwbbwbbb.",
        "bbbbbbbbbbbb",
        "bb.bssssb.bb",
        "b...bbbb...b",
        ".....bb.....",
    ]),
    ("BULLET", "top", [
        ".bb.........",
        "bwwb........",
        "bwwb........",
        ".bb.........",
    ]),
    ("BOOM0", "center", [
        ".....s......",
        "..s..b..s...",
        "...s.b.s....",
        "....sws.....",
        ".bbswwwsbb..",
        "....sws.....",
        "...s.b.s....",
        "..s..b..s...",
        ".....s......",
    ]),
    ("BOOM1", "center", [
        "s....b....s.",
        ".s...s...s..",
        "..s..b..s...",
        "...b.w.b....",
        "....www.....",
        "bsbwwwwwbsb.",
        "....www.....",
        "...b.w.b....",
        "..s..b..s...",
        ".s...s...s..",
        "s....b....s.",
    ]),
    ("FLOAT0", "top", [
        "...bbbbbb...",
        "..bbbbbbbb..",
        ".bbwwbbwwbb.",
        ".bbwsbbwsbb.",
        ".bbbbbbbbbb.",
        ".bbbbssbbbb.",
        ".bbbbbbbbbb.",
        "..b.b..b.b..",
        "..b.b..b.b..",
        ".b..b..b..b.",
        ".b...b..b.b.",
        "..b..b.b..b.",
    ]),
    ("FLOAT1", "top", [
        "...bbbbbb...",
        "..bbbbbbbb..",
        ".bbwwbbwwbb.",
        ".bbwsbbwsbb.",
        ".bbbbbbbbbb.",
        ".bbbbssbbbb.",
        ".bbbbbbbbbb.",
        "..b.b..b.b..",
        ".b..b..b..b.",
        ".b.b..b..b..",
        "..b.b..b.b..",
        "..b..b..b.b.",
    ]),
    ("HOP0", "bottom", [
        "..ww....ww..",
        ".wsw....wsw.",
        ".bbbbbbbbbb.",
        "bbbbbbbbbbbb",
        "bbssssssssbb",
        "bbbbbbbbbbbb",
        ".bbbbbbbbbb.",
        "bb.bb..bb.bb",
        "s..s....s..s",
    ]),
    ("HOP1", "bottom", [
        "..ww....ww..",
        ".wsw....wsw.",
        ".bbbbbbbbbb.",
        "bbbbbbbbbbbb",
        "bbbssssssbbb",
        ".bbbbbbbbbb.",
        "..bbbbbbbb..",
        "..b.b..b.b..",
        ".b..b..b..b.",
        ".b..b..b..b.",
        "ss........ss",
    ]),
    ("SEEK0", "center", [
        ".....s......",
        ".s...b...s..",
        "..bbbbbbb...",
        "..bwwwwwb...",
        "sbbwwsswbbs.",
        "..bwwwwwb...",
        "..bbbbbbb...",
        ".s...b...s..",
        ".....s......",
    ]),
    ("SEEK1", "center", [
        "...s...s....",
        "....bbb.....",
        "..bbbbbbb...",
        "s.bwwwwwb.s.",
        ".bbwwsswbb..",
        "s.bwwwwwb.s.",
        "..bbbbbbb...",
        "....bbb.....",
        "...s...s....",
    ]),
]

# Flaggans lodräta gula balk på startskärmen. Hires-sprite: 'sss' = 6 pixlar.
# Bara 12 rader data; med höjdförstoring blir den exakt 24 rader hög.
SPRITES.append(("FLAGBAR", "top", ["sss........."] * 12))
# Samma balk ihoptryckt mot en vägg: 4 pixlar bred
SPRITES.append(("FLAGBAR4", "top", ["ss.........."] * 12))

# Spegelvända gubbar (springer åt vänster)
_by_name = {n: (a, r) for n, a, r in SPRITES}
_mirrored = [(n.replace("RUN", "RUNL").replace("JUMP", "JUMPL"), a, [row[::-1] for row in r])
             for n, a, r in SPRITES if n in ("RUN0", "RUN1", "JUMP")]
SPRITES = SPRITES[:3] + _mirrored + SPRITES[3:]

# Nivå 3: multicolor-sprites (gfx_level3.SPR) under nya namn
for _src, _dst in (('PLAYER_UP', 'TD_PLAYER0'), ('PLAYER_UP2', 'TD_PLAYER1'),
                   ('ENEMY_DOWN', 'TD_ENEMY0'), ('ENEMY_DOWN2', 'TD_ENEMY1'),
                   ('ENEMY_THROW', 'TD_ENEMYT'), ('GSHADOW', 'TD_GSHADOW'),
                   ('SHADOW', 'TD_SHADOW'), ('GRENADE', 'TD_GRENADE'),
                   ('EBULLET', 'TD_EBULLET')):
    SPRITES.append((_dst, "top", L3.SPR[_src]))

# Hires-sprites (24x21, '#' = spritens färg): fallskärmen (2x2 sprites) och
# gubben i selen (tre lager med en färg var på samma koordinater).
HIRES_SPRITES = [(name, L3.HIRES[name]) for name in (
    'CANOPY_TL', 'CANOPY_TR', 'CANOPY_BL', 'CANOPY_BR',
    'JUMPER_K', 'JUMPER_S', 'JUMPER_C')]

# Kollisionsboxar (union av ramar)
BOXES = {
    "RUN": ["RUN0", "RUN1", "JUMP"],
    "SHIP": ["SHIP0", "SHIP1"],
    "WALK": ["WALK0", "WALK1"],
    "BAT": ["BAT0", "BAT1"],
    "BULLET": ["BULLET"],
    "FLOAT": ["FLOAT0", "FLOAT1"],
    "HOP": ["HOP0", "HOP1"],
    "SEEK": ["SEEK0", "SEEK1"],
    "TDPL": ["TD_PLAYER0", "TD_PLAYER1"],
}

# ----------------------------------------------------------------- tecken
CHARS = [
    ("ROCK0", [
        "rrrd",
        "rrdr",
        "rrrr",
        "drrr",
        "rdrr",
        "rrrr",
        "rrrd",
        "rrrr",
    ]),
    ("ROCK1", [
        "rrrr",
        "rdrr",
        "drrr",
        "rrrr",
        "rrrd",
        "rrdr",
        "rrrr",
        "drrr",
    ]),
    ("ROCK2", [
        "rdrr",
        "rrrr",
        "rrrd",
        "rrdr",
        "rrrr",
        "drrr",
        "rrrr",
        "rrdr",
    ]),
    ("ROCK3", [
        "rrrr",
        "rrrd",
        "rrdr",
        "rrrr",
        "rdrr",
        "drrr",
        "rrrr",
        "rrrd",
    ]),
    ("CEIL0", [
        "rrdr",
        "rrrr",
        "drrd",
        "rrr.",
        ".rr.",
        ".rd.",
        "..r.",
        "....",
    ]),
    ("CEIL1", [
        "rdrr",
        "rrrr",
        "rrdr",
        ".rrr",
        ".dr.",
        ".r..",
        ".r..",
        "....",
    ]),
    ("FLOOR0", [
        "g..g",
        "gggg",
        "gggg",
        "rgrg",
        "rrrr",
        "rdrr",
        "rrrr",
        "rrrd",
    ]),
    ("FLOOR1", [
        ".g..",
        "gg.g",
        "gggg",
        "grgr",
        "rrrr",
        "rrdr",
        "rrrr",
        "drrr",
    ]),
    ("SPIKE", [
        "....",
        "....",
        ".g..",
        ".g.g",
        "gg.g",
        "gggg",
        "dddd",
        "dddd",
    ]),
]


def encode_row(row, mapping, width):
    assert len(row) == width, row
    val = 0
    for ch in row:
        val = (val << 2) | mapping[ch]
    return val


def sprite_bytes(rows):
    out = []
    for r in rows:
        left, mid, right = r[0:4], r[4:8], r[8:12]
        out += [encode_row(left, SPR_MAP, 4),
                encode_row(mid, SPR_MAP, 4),
                encode_row(right, SPR_MAP, 4)]
    out.append(0)  # 64:e byten
    assert len(out) == 64
    return out


def hires_bytes(rows):
    assert len(rows) == 21 and all(len(r) == 24 for r in rows)
    out = []
    for r in rows:
        v = int(''.join('1' if c == '#' else '0' for c in r), 2)
        out += [(v >> 16) & 255, (v >> 8) & 255, v & 255]
    out.append(0)
    return out


def level3_chars():
    """Nivå 3: tecken per teckenkod (8 byte var) och blocktabeller."""
    m = {'.': 0, 'l': 1, 'b': 2, 'k': 3}
    chars = {}
    for key, name, code in L3.TILE_ORDER:
        art = L3.META[key]
        assert len(art) == 16 and all(len(r) == 8 for r in art), key
        for k, (ry, rx) in enumerate(((0, 0), (0, 4), (8, 0), (8, 4))):
            chars[code + k] = [encode_row(art[ry + y][rx:rx + 4], m, 4) for y in range(8)]
    return chars


def bbox(rows):
    xs, ys = [], []
    for y, r in enumerate(rows):
        for c, ch in enumerate(r):
            if ch != '.':
                xs += [c * 2, c * 2 + 1]
                ys.append(y)
    return min(xs), max(xs), min(ys), max(ys)


def fmt_bytes(vals, per_line=12):
    lines = []
    for i in range(0, len(vals), per_line):
        chunk = vals[i:i + per_line]
        lines.append("    .byte " + ", ".join("$%02x" % v for v in chunk))
    return lines


def bounce_frames():
    """Flaggans vågräta balk bildruta för bildruta: (översta rad, tjocklek)."""
    tops, heights = [], []
    for h in BOUNCES:
        t_air = int(round(BOUNCE_T19 * math.sqrt(h / 19.0)))
        # golvkontakt: ihoptryckt, sedan på väg tillbaka
        tops += [LOGO_ROWS - 3, LOGO_ROWS - 4]
        heights += [3, 4]
        for t in range(1, t_air):
            y = h * (1 - (2.0 * t / t_air - 1) ** 2)       # parabel, 0 vid golvet
            top = FLOOR - int(round(y))
            if y < 0.3 * h and top >= 1:                    # snabbt nära golvet: utsträckt
                tops.append(top - 1)
                heights.append(FLAG_BAR_H + 1)
            else:
                tops.append(top)
                heights.append(FLAG_BAR_H)
    assert len(tops) < 256
    assert all(0 <= t and t + hh <= LOGO_ROWS for t, hh in zip(tops, heights))
    return tops, heights


def main():
    padded = {}
    for name, align, rows in SPRITES:
        padded[name] = pad_sprite(rows, align)

    const = []
    data = []
    const.append("// GENERERAD FIL - ändra tools/make_gfx.py och kör om den.")
    const.append("// Spritepekare, teckenkoder och kollisionsboxar.")
    const.append("")
    ptr0 = (SPRITE_BASE_ADDR - VIC_BANK) // 64
    for i, (name, _, _) in enumerate(SPRITES):
        const.append(".const SPR_%-8s = %d" % (name, ptr0 + i))
    for i, (name, _) in enumerate(HIRES_SPRITES):
        const.append(".const SPR_%-8s = %d   // hires" % (name, ptr0 + len(SPRITES) + i))
    const.append("")
    for i, (name, _) in enumerate(CHARS):
        const.append(".const CH_%-8s = %d" % (name, FIRST_CHAR + i))
    const.append("")
    const.append(".const GFX_CHARS_LEN   = %d" % (len(CHARS) * 8))
    const.append(".const BOUNCE_LEN      = %d   // bildrutor i flaggans studsserie" % len(bounce_frames()[0]))
    const.append(".const GFX_SPRITES_LEN = %d" % ((len(SPRITES) + len(HIRES_SPRITES)) * 64))
    const.append("")
    const.append("// Nivå 3: block (metatiles) och teckenkoder")
    for i, (key, name, code) in enumerate(L3.TILE_ORDER):
        const.append(".const MT_%-9s = %d   // '%s', tecken %d-%d" % (name, i, key, code, code + 3))
    const.append(".const NUM_MT          = %d" % len(L3.TILE_ORDER))
    const.append(".const TD_PASS_FIRST   = %d   // passerbart" % L3.TD_PASS_FIRST)
    const.append(".const TD_CRATE_FIRST  = %d   // låda" % L3.TD_CRATE_FIRST)
    const.append(".const TD_WIRE_FIRST   = %d   // taggtråd (farlig)" % L3.TD_WIRE_FIRST)
    const.append(".const TD_SOLID_FIRST  = %d   // stoppar gubben" % L3.TD_SOLID_FIRST)
    l3 = level3_chars()
    b1 = [c for c in l3 if c < 128]
    b2 = [c for c in l3 if c >= 128]
    assert b1 == list(range(min(b1), max(b1) + 1)) and b2 == list(range(min(b2), max(b2) + 1))
    const.append(".const TD_CHARS1_FIRST = %d" % min(b1))
    const.append(".const TD_CHARS1_LEN   = %d" % (len(b1) * 8))
    const.append(".const TD_CHARS2_FIRST = %d" % min(b2))
    const.append(".const TD_CHARS2_LEN   = %d" % (len(b2) * 8))
    const.append("")
    const.append("// Kollisionsboxar i spritepixlar (inklusive), union av alla ramar")
    for bname, frames in BOXES.items():
        boxes = [bbox(padded[f]) for f in frames]
        l = min(b[0] for b in boxes)
        r = max(b[1] for b in boxes)
        t = min(b[2] for b in boxes)
        b = max(b[3] for b in boxes)
        const.append(".const BOX_%s_L = %d" % (bname, l))
        const.append(".const BOX_%s_R = %d" % (bname, r))
        const.append(".const BOX_%s_T = %d" % (bname, t))
        const.append(".const BOX_%s_B = %d" % (bname, b))
    const.append("")

    data.append("// GENERERAD FIL - ändra tools/make_gfx.py och kör om den.")
    data.append("")
    data.append("// ---------------------------------------------------------------")
    data.append("// Egna tecken (multicolor) - tecken %d och uppåt" % FIRST_CHAR)
    data.append("// ---------------------------------------------------------------")
    data.append("// (kopieras till teckensetet vid start)")
    data.append("gfxChars:")
    for name, rows in CHARS:
        data.append("// %s" % name)
        vals = [encode_row(r, CHR_MAP, 4) for r in rows]
        for r, v in zip(rows, vals):
            data.append("    .byte %%%s    // %s" % (format(v, "08b"), r))
    data.append("")
    data.append("// ---------------------------------------------------------------")
    data.append("// Sprites (multicolor, 64 byte per sprite)")
    data.append("// ---------------------------------------------------------------")
    data.append("// (kopieras till $%04x vid start)" % SPRITE_BASE_ADDR)
    data.append("gfxSprites:")
    for name, _, _ in SPRITES:
        rows = padded[name]
        data.append("// %s" % name)
        vals = sprite_bytes(rows)
        for y, r in enumerate(rows):
            b = vals[y * 3:y * 3 + 3]
            data.append("    .byte %%%s, %%%s, %%%s    // %s" % (
                format(b[0], "08b"), format(b[1], "08b"), format(b[2], "08b"), r))
        data.append("    .byte 0")
    for name, rows in HIRES_SPRITES:
        data.append("// %s (hires)" % name)
        vals = hires_bytes(rows)
        for y, r in enumerate(rows):
            b = vals[y * 3:y * 3 + 3]
            data.append("    .byte %%%s, %%%s, %%%s    // %s" % (
                format(b[0], "08b"), format(b[1], "08b"), format(b[2], "08b"), r))
        data.append("    .byte 0")
    data.append("")
    data.append("// ---------------------------------------------------------------")
    data.append("// Nivå 3: tecken för banan ovanifrån (kopieras till teckensetet)")
    data.append("// ---------------------------------------------------------------")
    names = {code + k: "%s %s" % (name, ("TL", "TR", "BL", "BR")[k])
             for key, name, code in L3.TILE_ORDER for k in range(4)}
    for label, codes in (("gfxTdChars1", b1), ("gfxTdChars2", b2)):
        data.append("%s:" % label)
        for c in codes:
            data.append("    .byte " + ", ".join("$%02x" % v for v in l3[c]) + "    // %d %s" % (c, names[c]))
    data.append("// Blocktabeller: teckenkod för övre vänster/höger, nedre vänster/höger")
    for label, k in (("mtTL", 0), ("mtTR", 1), ("mtBL", 2), ("mtBR", 3)):
        data.append("%s:" % label)
        data += fmt_bytes([code + k for _, _, code in L3.TILE_ORDER], 20)
    data.append("")
    data.append("// ---------------------------------------------------------------")
    data.append("// Sinustabell för flygande monster (64 steg, 0..40)")
    data.append("// ---------------------------------------------------------------")
    data.append("sineTab:")
    sine = [int(round(20 + 20 * math.sin(2 * math.pi * i / 64))) for i in range(64)]
    data += fmt_bytes(sine, 16)
    data.append("")

    # Tabeller för startskärmens logo (256 steg per period)
    data.append("// Bokstävernas våg: $d016-finscroll 0-%d per rasterlinje (64 steg per period)" % LOGO_WAVE)
    data.append("waveTab:")
    data += fmt_bytes([int(round(LOGO_WAVE / 2 * (1 + math.sin(2 * math.pi * i / 64))))
                       for i in range(64)], 16)
    # Flaggans vågräta balk: en serie parabelstudsar (konstant tyngdkraft).
    # Per bildruta: översta raden och tjockleken. I golvkontakten trycks
    # balken ihop (3 och 4 rader), nära golvet där farten är hög sträcks den
    # ut till 6 rader. Tiden i luften växer med roten ur höjden.
    tops, heights = bounce_frames()
    data.append("// Flaggans vågräta balk: %d bildrutor, %d studsar (höjd %s rader)." % (
        len(tops), len(BOUNCES), ", ".join(map(str, BOUNCES))))
    data.append("// bounceTop = översta raden 0-23, bounceH = tjocklek i rader")
    data.append("bounceTop:")
    data += fmt_bytes(tops, 16)
    data.append("bounceH:")
    data += fmt_bytes(heights, 16)
    data.append("")

    with open(os.path.join(SRC, "gfx_const.asm"), "w", encoding="utf-8") as f:
        f.write("\n".join(const) + "\n")
    with open(os.path.join(SRC, "gfx_data.asm"), "w", encoding="utf-8") as f:
        f.write("\n".join(data) + "\n")
    print("Wrote gfx_const.asm and gfx_data.asm")


if __name__ == "__main__":
    main()
