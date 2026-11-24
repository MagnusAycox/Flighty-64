#!/usr/bin/env python3
"""
Mockups (skärmbilder) av nivå 3, banan ovanifrån.

Ritar sex lägen med samma grafik som spelet använder (tools/gfx_level3.py)
och samma regler som en C64: multicolor-block i fyra färger, 12x21
multicolor-sprites, hires-sprites för fallskärmen och gubben i selen.

Kör:  python3 tools/mockup_level3.py [utkatalog]    (standard: docs/niva3)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from emu import PALETTE                              # noqa: E402
import make_gfx                                      # noqa: E402
from gfx_level3 import (META, SPR, HIRES, JUMPER_LAYERS,  # noqa: E402
                        BG, C1, C2, CR)

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'docs', 'niva3')
BORDER = 0
CHAR_COL = {'.': BG, 'l': C1, 'b': C2, 'k': CR}

for name, _, rows in make_gfx.SPRITES:
    if name in ('TD_BULLET', 'TD_BOOM0', 'TD_BOOM1'):
        SPR[name[3:]] = rows            # nivå 3:s versioner (svart $d025)


def pal(i):
    return PALETTE[i & 15]


def load_font():
    p = os.path.join(ROOT, 'build', 'openroms', 'chargen_openroms.rom')
    return open(p, 'rb').read() if os.path.exists(p) else None


FONT = load_font()


def screen_code(ch):
    if 'A' <= ch <= 'Z':
        return ord(ch) - 64
    return ord(ch)


class Canvas:
    def __init__(self):
        from PIL import Image
        self.img = Image.new('RGB', (384, 272), pal(BORDER))
        self.px = self.img.load()

    def fill_play(self):
        for y in range(200):
            for x in range(320):
                self.px[32 + x, 36 + y] = (0, 0, 0)

    def map(self, rows, yofs=0):
        """rows: strängar med 20 metatiles; ritas från teckenrad 2."""
        top = 16  # pixelrad (rad 2)
        for my, row in enumerate(rows):
            # sista taggtrådsblocket i en rad får stolpe till höger
            row = ''.join('Z' if t == 'X' and (i + 1 == len(row) or row[i + 1] != 'X') else t
                          for i, t in enumerate(row))
            for mx, t in enumerate(row):
                art = META[t]
                for ry in range(16):
                    y = top + my * 16 + ry + yofs
                    if not (16 <= y < 200):
                        continue
                    for rx in range(8):
                        c = CHAR_COL[art[ry][rx]]
                        for d in (0, 1):
                            self.px[32 + mx * 16 + rx * 2 + d, 36 + y] = pal(c)

    def text(self, row, col, s, color):
        for i, ch in enumerate(s):
            code = screen_code(ch)
            for ry in range(8):
                bits = FONT[code * 8 + ry] if FONT else 0
                for rx in range(8):
                    x, y = 32 + (col + i) * 8 + rx, 36 + row * 8 + ry
                    if bits & (0x80 >> rx):
                        self.px[x, y] = pal(color)
                    else:
                        self.px[x, y] = pal(0)

    def hires(self, name, x, y, color):
        for ry, row in enumerate(HIRES[name]):
            for rx, ch in enumerate(row):
                if ch == '#':
                    px, py = 32 + x + rx, 36 + y + ry
                    if 32 <= px < 352 and 52 <= py < 236:
                        self.px[px, py] = pal(color)

    def sprite(self, name, x, y, color, xexp=False, yexp=False, flipv=False):
        rows = SPR[name]
        if flipv:
            rows = rows[::-1]
        sx, sy = (2 if xexp else 1), (2 if yexp else 1)
        for ry, row in enumerate(rows):
            for rx, ch in enumerate(row.ljust(12, '.')):
                if ch == '.':
                    continue
                c = {'w': 0, 'b': color, 's': 10}[ch]     # $d025 svart, $d026 hud
                for dy in range(sy):
                    for dx in range(2 * sx):
                        px = 32 + x + (rx * 2 * sx) + dx
                        py = 36 + y + ry * sy + dy
                        if 32 <= px < 352 and 52 <= py < 236:
                            self.px[px, py] = pal(c)

    def hud(self, lvl, wave, gr, msg=None):
        if msg:
            self.text(0, (40 - len(msg)) // 2, msg, 7)
            return
        self.text(0, 1, "SCORE", 14)
        self.text(0, 7, "004270", 1)
        self.text(0, 14, "LV", 14)
        self.text(0, 17, "%02d-%d" % (lvl, wave), 5)
        self.text(0, 22, "LIVES", 14)
        self.text(0, 28, "3", 1)
        self.text(0, 30, "GRENADE", 14)
        self.text(0, 38, str(gr), 7)

    def save(self, path, caption=None):
        from PIL import Image, ImageDraw
        img = self.img.resize((768, 544), Image.NEAREST)
        if caption:
            out = Image.new('RGB', (768, 584), (24, 24, 24))
            out.paste(img, (0, 0))
            ImageDraw.Draw(out).text((12, 556), caption, fill=(230, 230, 230))
            img = out
        img.save(path)


def scene_parachute():
    c = Canvas()
    c.fill_play()
    c.map([
        "T.,T..T.,.T..,T..T.T",
        ".T..,....,...,..T..,",
        "..,..S.S.........,..",
        "T....,..,..T..,....T",
        ".,......,....,...,..",
        "..T..,......,....T..",
        ",.....,..,......,..T",
        ".T..........,...,...",
        "..,..T..,.....T.....",
        ".,.....,..,.....,.T.",
        "T..,......,..,......",
        "..T..,..T......,.T..",
    ])
    c.hud(3, 1, 0, msg="LEVEL 03  -  DROP ZONE")
    # skärmen står still; fallskärmen sjunker, skuggan glider in under den
    c.sprite('SHADOW', 140, 162, 0)
    for name, dx, dy in (('CANOPY_TL', 0, 0), ('CANOPY_TR', 24, 0),
                         ('CANOPY_BL', 0, 21), ('CANOPY_BR', 24, 21)):
        c.hires(name, 128 + dx, 18 + dy, 1)       # fyra vita hires-sprites
    # tre hires-lager på samma koordinater (lägst spritenummer ritas överst)
    for _ch, _col in reversed(JUMPER_LAYERS):
        c.hires('JUMPER_' + _ch.upper(), 140, 59, _col)
    return c


def scene_wave1():
    c = Canvas()
    c.fill_play()
    c.map([
        "T..T.,..T..,..T.,..T",
        ".,..T......,......T.",
        "T.......SS......,..T",
        ".T..,........,...T..",
        "..,.....T......,....",
        "T....,......,..SS..T",
        ".SS......,.......T..",
        "T...,..T.....,......",
        "..T.........,...,.T.",
        ",.....,..,......,...",
        "T..,..T......,..T..T",
        "..T......,.......T..",
    ])
    c.hud(3, 1, 0)
    c.sprite('ENEMY_DOWN', 60, 22, 9)
    c.sprite('ENEMY_DOWN', 196, 46, 9)
    c.sprite('ENEMY_DOWN', 262, 30, 9)
    c.sprite('EBULLET', 70, 60, 1)
    c.sprite('EBULLET', 70, 94, 1)
    c.sprite('EBULLET', 206, 88, 1)
    c.sprite('PLAYER_UP2', 150, 150, 3)
    c.sprite('BULLET', 158, 118, 7)
    c.sprite('BULLET', 158, 82, 7)
    return c


def scene_wave2():
    c = Canvas()
    c.fill_play()
    c.map([
        ".T..,..T......T..,.T",
        "T......,..SS.......T",
        "..,.T.........,..T..",
        ".......T..,.........",
        "T.,..........T..,..T",
        "...T...,..O.......T.",
        ".,.....T.......,....",
        "T..C.......,..T....T",
        ".....,..T.........,.",
        "..T.......,....SS...",
        "T....,.........,..T.",
        ".,..T....,..T.......",
    ])
    c.hud(3, 2, 3)
    c.sprite('ENEMY_DOWN', 90, 28, 9)
    c.sprite('ENEMY_DOWN', 236, 40, 9)
    c.sprite('EBULLET', 92, 66, 1)      # snett ned vänster
    c.sprite('EBULLET', 108, 66, 1)     # rakt ned
    c.sprite('EBULLET', 124, 66, 1)     # snett ned höger
    c.sprite('EBULLET', 232, 84, 1)
    c.sprite('BOOM1', 156, 70, 7)       # granaten slår ned
    c.sprite('GRENADE', 168, 104, 13)   # nästa granat på väg upp
    c.sprite('SHADOW', 168, 136, 0)
    c.sprite('PLAYER_UP', 160, 150, 3)
    return c


def scene_wave4():
    c = Canvas()
    c.fill_play()
    c.map([
        "T.XXXXX..XXXXXX..T.T",
        ".......,..........,.",
        "T..T......T....,..T.",
        "XXX...XXXXXXX...XXXX",
        ".,..,.....,....,....",
        "..T....C.......T...,",
        "T....,..XXX..,.....T",
        ".SS........,....SS..",
        "....XXX.....XXX.....",
        ".,.....,..T.....,..T",
        "T..T.......,...T....",
        "..,.....T......,..T.",
    ])
    c.hud(3, 4, 2)
    c.sprite('ENEMY_DOWN', 120, 16, 9)
    c.sprite('ENEMY_THROW', 220, 64, 9)
    c.sprite('GRENADE', 200, 96, 13)
    c.sprite('SHADOW', 196, 122, 0)
    c.sprite('EBULLET', 130, 54, 1)
    c.sprite('PLAYER_UP', 166, 160, 3)
    c.sprite('BULLET', 174, 128, 7)
    return c


def scene_gate():
    c = Canvas()
    c.fill_play()
    c.map([
        "WWWWWWWWWghWWWWWWWWW",
        "VVVVVVVVVijVVVVVVVVV",
        "..T...S........S..T.",
        "T.......,..,......,T",
        "..,..T........T.....",
        ".T.......O.......,..",
        "....,.........,..T..",
        "T..T....,..C.......T",
        ".,.........,....,...",
        "...T..,........T..,.",
        "T......,..,.........",
        ".,..T........,..T..T",
    ])
    c.hud(3, 4, 1)
    c.sprite('BOOM1', 152, 30, 7)
    c.sprite('ENEMY_DOWN', 40, 40, 9)
    c.sprite('ENEMY_DOWN', 270, 44, 9)
    c.sprite('EBULLET', 50, 78, 1)
    c.sprite('PLAYER_UP', 150, 150, 3)
    return c


def scene_clear():
    c = Canvas()
    c.fill_play()
    c.map([
        "WWWWWWWWWRRWWWWWWWWW",
        "VVVVVVVVVrrVVVVVVVVV",
        "..T...S........S..T.",
        "T.......,..,......,T",
        "..,..T........T.....",
        ".T.......O.......,..",
        "....,.........,..T..",
        "T..T....,..........T",
        ".,.........,....,...",
        "...T..,........T..,.",
        "T......,..,.........",
        ".,..T........,..T..T",
    ])
    c.hud(3, 4, 0, msg="STAGE CLEAR!  BONUS 500")
    c.sprite('PLAYER_UP', 150, 40, 3)
    return c


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    shots = [
        ('1_fallskarm.png', scene_parachute()),
        ('2_vag1.png', scene_wave1()),
        ('3_vag2_granat.png', scene_wave2()),
        ('4_vag4_taggtrad.png', scene_wave4()),
        ('5_porten.png', scene_gate()),
        ('6_stage_clear.png', scene_clear()),
    ]
    for name, c in shots:
        c.save(os.path.join(OUT, name))
        print(name)
    # översikt med alla sex bilderna
    from PIL import Image
    ims = [Image.open(os.path.join(OUT, n)).resize((384, 272)) for n, _ in shots]
    sheet = Image.new('RGB', (768, 816))
    for k, im in enumerate(ims):
        sheet.paste(im, ((k % 2) * 384, (k // 2) * 272))
    sheet.save(os.path.join(OUT, 'oversikt.png'))
    print('oversikt.png')
