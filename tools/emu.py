#!/usr/bin/env python3
"""
emu.py - en minimal C64-testmiljö för Flighty 64 (inte en riktig emulator).

Kör 6502-koden med py65 och emulerar just det spelet behöver:
  * raster-räknare och raster-IRQ ($d012/$d019/$d01a), med badlines
  * joystick i port 2 ($dc00) från ett skript
  * $01-bankning (tecken-ROM ersätts av ett eget testtypsnitt)
  * renderar skärmen (teckenläge, multicolor, finscroll, sprites) till PNG

Används för att provköra och ta skärmdumpar utan VICE.
"""
import json
import os
import sys

from py65.devices.mpu6502 import MPU

CYCLES_PER_LINE = 63
LINES = 312

PALETTE = [
    (0, 0, 0), (255, 255, 255), (104, 55, 43), (112, 164, 178),
    (111, 61, 134), (88, 141, 67), (53, 40, 121), (184, 199, 111),
    (111, 79, 37), (67, 57, 0), (154, 103, 89), (68, 68, 68),
    (108, 108, 108), (154, 210, 132), (108, 94, 181), (149, 149, 149),
]


def make_font():
    """Eget 8x8-typsnitt (bara för skärmdumpar) med C64-skärmkodsordning."""
    from PIL import Image, ImageDraw, ImageFont
    font = None
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf"]:
        if os.path.exists(p):
            font = ImageFont.truetype(p, 9)
            break
    rom = bytearray(4096)
    for code in range(64):
        if code == 0:
            ch = '@'
        elif code <= 26:
            ch = chr(64 + code)
        elif code < 32:
            ch = '[£]^_'[code - 27] if code - 27 < 5 else ' '
        else:
            ch = chr(code)
        img = Image.new('1', (8, 8), 0)
        d = ImageDraw.Draw(img)
        if font:
            d.text((0, -2), ch, fill=1, font=font)
        for y in range(8):
            v = 0
            for x in range(8):
                if img.getpixel((x, y)):
                    v |= 0x80 >> x
            rom[code * 8 + y] = v
    return rom


class C64:
    def __init__(self, prg, syms):
        self.ram = bytearray(65536)
        self.io = bytearray(4096)
        self.charrom = make_font()
        load = prg[0] | (prg[1] << 8)
        self.ram[load:load + len(prg) - 2] = prg[2:]
        self.ram[1] = 0x37
        self.syms = syms
        self.cycles = 0
        self.line = 0
        self.irq_latch = 0
        self.raster_cmp = 0
        self.joy = 0          # bitar: 1 upp 2 ned 4 vänster 8 höger 16 fire
        self.line_regs = [None] * LINES
        self.frame = 0
        self.mpu = MPU(memory=self, pc=syms['labels']['start'])
        self.mpu.sp = 0xff
        self.mpu.p |= self.mpu.INTERRUPT
        self.wait_pc = syms['labels']['waitLoop']
        self.frame_busy = []  # cykler från waitFrame-retur till nästa waitLoop
        self._busy_start = None

    # --- minnesgränssnitt för py65
    def __len__(self):
        return 65536

    def io_visible(self):
        p = self.ram[1] & 7
        return (p & 3) != 0 and (p & 4) != 0

    def charrom_visible(self):
        p = self.ram[1] & 7
        return (p & 3) != 0 and (p & 4) == 0

    def __getitem__(self, a):
        if isinstance(a, slice):
            return [self[i] for i in range(*a.indices(65536))]
        if 0xd000 <= a <= 0xdfff:
            if self.io_visible():
                return self.read_io(a)
            if self.charrom_visible():
                return self.charrom[a - 0xd000]
        if a >= 0xe000 and (self.ram[1] & 2):
            raise RuntimeError("KERNAL-ROM läst på $%04x (ska vara avslagen)" % a)
        return self.ram[a]

    def __setitem__(self, a, v):
        if isinstance(a, slice):
            for i, x in zip(range(*a.indices(65536)), v):
                self[i] = x
            return
        v &= 0xff
        if 0xd000 <= a <= 0xdfff and self.io_visible():
            self.write_io(a, v)
            return
        self.ram[a] = v

    def read_io(self, a):
        r = a & 0xfff
        if r < 0x400:
            r &= 0x3f
            if r == 0x12:
                return self.line & 0xff
            if r == 0x11:
                return (self.io[0x11] & 0x7f) | ((self.line >> 8) << 7)
            if r == 0x19:
                return self.irq_latch | (0x80 if self.irq_latch & self.io[0x1a] & 0x0f else 0) | 0x70
            return self.io[r]
        if 0xc00 <= r < 0xd00:   # CIA1
            rr = r & 0x0f
            if rr == 0:
                return (~self.joy) & 0xff
            if rr == 1:
                return 0xff
            if rr == 0x0d:
                return 0
            return self.io[0xc00 + rr]
        if 0xd00 <= r < 0xe00:
            return 0
        if 0x400 <= r < 0x800:   # SID
            return 0
        return self.io[r]

    def write_io(self, a, v):
        r = a & 0xfff
        if r < 0x400:
            r &= 0x3f
            if r == 0x12:
                self.raster_cmp = (self.raster_cmp & 0x100) | v
            elif r == 0x11:
                self.raster_cmp = (self.raster_cmp & 0xff) | ((v & 0x80) << 1)
            elif r == 0x19:
                self.irq_latch &= ~v & 0x0f
                return
            self.io[r] = v
            return
        self.io[r] = v

    # --- körning
    def snapshot_line(self):
        self.line_regs[self.line] = (self.io[0x11], self.io[0x16], self.io[0x18],
                                     self.io[0x20], self.io[0x21], self.io[0x22], self.io[0x23])

    def run_frame(self):
        target = (self.frame + 1) * LINES * CYCLES_PER_LINE
        mpu = self.mpu
        ram = self.ram
        while self.cycles < target:
            pc = mpu.pc
            if ram[pc] == 0x00 and not (0xd000 <= pc <= 0xdfff):
                raise RuntimeError("BRK på $%04x (frame %d)" % (pc, self.frame))
            if pc == self.wait_pc + 4:
                self._busy_start = self.cycles
            elif pc == self.wait_pc and self._busy_start is not None:
                self.frame_busy.append(self.cycles - self._busy_start)
                self._busy_start = None
            before = mpu.processorCycles
            mpu.step()
            self.advance(mpu.processorCycles - before)
            if self.irq_latch & self.io[0x1a] & 1 and not (mpu.p & mpu.INTERRUPT):
                before = mpu.processorCycles
                mpu.irq()
                self.advance(mpu.processorCycles - before)
        self.frame += 1

    def advance(self, c):
        self.cycles += c
        new_line = (self.cycles // CYCLES_PER_LINE) % LINES
        while self.line != new_line:
            self.line = (self.line + 1) % LINES
            self.snapshot_line()
            # badline: CPU stoppas 40 cykler
            yscroll = self.io[0x11] & 7
            if (self.io[0x11] & 0x10) and 0x30 <= self.line <= 0xf7 and (self.line & 7) == yscroll:
                self.cycles += 40
            if self.line == self.raster_cmp:
                self.irq_latch |= 1

    # --- rendering
    def render(self, path, scale=2):
        from PIL import Image
        W, H = 384, 272
        img = Image.new('RGB', (W, H))
        px = img.load()
        top_line = 16          # bildens rad 0 = rasterlinje 16
        left = 24 + 32 - 24    # x=32 i bilden = spritekoordinat 24... förenkla
        for y in range(H):
            line = y + top_line
            regs = self.line_regs[line % LINES] or (0x1b, 0x08, 0x14, 14, 6, 0, 0)
            d011, d016, d018, d020, d021, d022, d023 = regs
            border = PALETTE[d020 & 15]
            for x in range(W):
                px[x, y] = border
            if not (d011 & 0x10):
                continue
            yscroll = d011 & 7
            first = 0x33 if d011 & 8 else 0x37
            last = 0xfb if d011 & 8 else 0xf7
            if not (first <= line < last):
                continue
            rowline = line - 0x30 - yscroll
            if rowline < 0:
                continue
            row, cy = rowline // 8, rowline % 8
            if row > 24:
                continue
            xscroll = d016 & 7
            mc = d016 & 0x10
            x0 = 32 if d016 & 8 else 39
            x1 = 352 if d016 & 8 else 343
            screen = ((d018 >> 4) & 15) * 0x400
            charset = ((d018 >> 1) & 7) * 0x800
            bg = PALETTE[d021 & 15]
            for x in range(x0, x1):
                px[x, y] = bg
            for sx in range(320):
                X = sx + xscroll
                if X >= 320:
                    continue
                col = sx // 8
                cx = sx % 8
                code = self.ram[screen + row * 40 + col]
                color = self.io[0x800 + row * 40 + col] & 15
                caddr = charset + code * 8 + cy
                if 0x1000 <= caddr < 0x2000:
                    bits = self.charrom[caddr - 0x1000]
                else:
                    bits = self.ram[caddr]
                ix = 32 + X
                if ix < x0 or ix >= x1:
                    continue
                if mc and color & 8:
                    pair = (bits >> (6 - (cx & 6))) & 3
                    c = [d021, d022, d023, color & 7][pair]
                    if pair:
                        px[ix, y] = PALETTE[c & 15]
                else:
                    if bits & (0x80 >> cx):
                        px[ix, y] = PALETTE[color]
            # sprites
            en = self.io[0x15]
            for n in range(7, -1, -1):
                if not en & (1 << n):
                    continue
                sy = self.io[1 + n * 2]
                dy = line - sy
                if not (0 <= dy < 21):
                    continue
                sxp = self.io[n * 2] | (0x100 if self.io[0x10] & (1 << n) else 0)
                ptr = self.ram[screen + 0x3f8 + n]
                base = ptr * 64 + dy * 3
                b = (self.ram[base] << 16) | (self.ram[base + 1] << 8) | self.ram[base + 2]
                colr = self.io[0x27 + n] & 15
                smc = self.io[0x1c] & (1 << n)
                for i in range(24):
                    if smc:
                        pair = (b >> (22 - (i & ~1))) & 3
                        if not pair:
                            continue
                        c = [0, self.io[0x25], colr, self.io[0x26]][pair]
                    else:
                        if not (b >> (23 - i)) & 1:
                            continue
                        c = colr
                    ix = sxp - 24 + 32 + i
                    if x0 <= ix < x1:
                        px[ix, y] = PALETTE[c & 15]
        if scale != 1:
            img = img.resize((W * scale, H * scale), Image.NEAREST)
        img.save(path)

    def peek(self, name):
        s = self.syms['consts'].get(name, self.syms['labels'].get(name))
        return self.ram[s]


def load(prg_path, sym_path):
    with open(prg_path, 'rb') as f:
        prg = f.read()
    with open(sym_path) as f:
        syms = json.load(f)
    return C64(prg, syms)


if __name__ == '__main__':
    c = load(sys.argv[1], sys.argv[2])
    for i in range(int(sys.argv[3]) if len(sys.argv) > 3 else 100):
        c.run_frame()
    c.render('out.png')
