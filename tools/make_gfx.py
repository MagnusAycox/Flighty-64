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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

VIC_BANK = 0x4000
SPRITE_BASE_ADDR = 0x5000     # spritedata kopieras hit vid start
FIRST_CHAR = 64               # egna tecken: 64 och uppåt

LOGO_WIDTH = 272              # "SOFTWARE OF SWEDEN": 16 bokstäver x 16 px + 2 mellanslag x 8 px
LOGO_SWAY = 31                # svängning 0-31 pixlar (38-kolumnsfönstret är 304 px)
FLAG_BAR_W = 6
FLAG_X_MAX = (LOGO_WIDTH - FLAG_BAR_W) // 2   # tabellen lagrar x/2
BOUNCE = 19                   # 24 rader hög logo - 5 rader balk

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

# Spegelvända gubbar (springer åt vänster)
_by_name = {n: (a, r) for n, a, r in SPRITES}
_mirrored = [(n.replace("RUN", "RUNL").replace("JUMP", "JUMPL"), a, [row[::-1] for row in r])
             for n, a, r in SPRITES if n in ("RUN0", "RUN1", "JUMP")]
SPRITES = SPRITES[:3] + _mirrored + SPRITES[3:]

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
    const.append("")
    for i, (name, _) in enumerate(CHARS):
        const.append(".const CH_%-8s = %d" % (name, FIRST_CHAR + i))
    const.append("")
    const.append(".const GFX_CHARS_LEN   = %d" % (len(CHARS) * 8))
    const.append(".const GFX_SPRITES_LEN = %d" % (len(SPRITES) * 64))
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
    data.append("")
    data.append("// ---------------------------------------------------------------")
    data.append("// Sinustabell för flygande monster (64 steg, 0..40)")
    data.append("// ---------------------------------------------------------------")
    data.append("sineTab:")
    sine = [int(round(20 + 20 * math.sin(2 * math.pi * i / 64))) for i in range(64)]
    data += fmt_bytes(sine, 16)
    data.append("")

    # Tabeller för startskärmens logo (256 steg per period)
    data.append("// Logons svängning i sidled: 0-%d pixlar (hel sinusperiod)" % LOGO_SWAY)
    data.append("swayTab:")
    data += fmt_bytes([int(round(LOGO_SWAY / 2 * (1 + math.sin(2 * math.pi * i / 256))))
                       for i in range(256)], 16)
    data.append("// Flaggans lodräta balk, x/2 inom texten (hel sinus: mjuka vändningar)")
    data.append("flagXTab:")
    data += fmt_bytes([int(round(FLAG_X_MAX / 2 * (1 + math.sin(2 * math.pi * i / 256 - math.pi / 2))))
                       for i in range(256)], 16)
    data.append("// Flaggans vågräta balk: översta raden 0-%d. Halv sinus (|sin|):" % BOUNCE)
    data.append("// skarp vändning i nederkant, mjuk i överkant")
    data.append("bounceTab:")
    data += fmt_bytes([int(round(BOUNCE * (1 - math.sin(math.pi * i / 256))))
                       for i in range(256)], 16)
    data.append("")

    with open(os.path.join(SRC, "gfx_const.asm"), "w") as f:
        f.write("\n".join(const) + "\n")
    with open(os.path.join(SRC, "gfx_data.asm"), "w") as f:
        f.write("\n".join(data) + "\n")
    print("Wrote gfx_const.asm and gfx_data.asm")


if __name__ == "__main__":
    main()
