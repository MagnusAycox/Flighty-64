#!/usr/bin/env python3
"""
vice_test.py - provkör Flighty 64 i riktiga VICE (x64sc, cykelexakt)
och styr spelet via VICE:s binära monitor.

Skriptet:
  1. startar x64sc (utan fönster via xvfb-run om DISPLAY saknas)
  2. stannar emulatorn en gång per bildruta, när spelet läst joysticken
     (rts i readJoy), läser spelets minne, skriver joystickens värde i
     spelets variabler joy/joyNew och fortsätter
  3. sparar skärmbilder direkt från VIC-II:s bildbuffert

Kräver: x64sc (VICE 3.5 eller senare), Python 3 med Pillow, och C64-ROM:ar.
ROM:arna anges med --roms KATALOG som innehåller kernal, basic och chargen
(filnamnen i --kernal/--basic/--chargen). De fria MEGA65 Open ROMs fungerar
(hämtas med tools/get_openroms.sh). Saknas DISPLAY startas en virtuell
skärm med Xvfb.

Efter nivå 1-2 hoppar testet till slutet av nivå 2 och spelar nivå 3
(banan ovanifrån) med en vägsökande bot (--skip-level3 hoppar över den).

Exempel:
  tools/get_openroms.sh
  python3 tools/vice_test.py --roms build/openroms

  # med originalens ROM:ar från en vanlig VICE-installation:
  python3 tools/vice_test.py --roms /usr/lib/vice/C64 \
      --kernal kernal-901227-03.bin --basic basic-901226-01.bin \
      --chargen chargen-906143-02.bin
"""
import argparse
import json
import os
import socket
import struct
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

PORT = 6502


class Monitor:
    """Minimal klient för VICE:s binära monitor (API version 2)."""

    def __init__(self, port):
        for _ in range(100):
            try:
                self.s = socket.create_connection(('127.0.0.1', port), timeout=30)
                break
            except OSError:
                time.sleep(0.2)
        else:
            raise RuntimeError("kom inte åt VICE:s binära monitor")
        self.req = 0
        self.pending_events = []

    def _recv(self, n):
        buf = b''
        while len(buf) < n:
            chunk = self.s.recv(n - len(buf))
            if not chunk:
                raise RuntimeError("VICE stängde anslutningen")
            buf += chunk
        return buf

    def read_msg(self):
        head = self._recv(12)
        stx, api, length, rtype, err, rid = struct.unpack('<BBIBBI', head)
        body = self._recv(length)
        return rtype, err, rid, body

    def cmd(self, ctype, body=b''):
        self.req += 1
        rid = self.req
        self.s.sendall(struct.pack('<BBIIB', 2, 2, len(body), rid, ctype) + body)
        while True:
            rtype, err, r, b = self.read_msg()
            if r == rid:
                if err:
                    raise RuntimeError("monitorfel %02x på kommando %02x" % (err, ctype))
                return b
            if rtype == 0x62:       # spara bara "stopped"-händelser
                self.pending_events.append((rtype, b))

    def wait_event(self, wanted):
        while True:
            for i, (rtype, b) in enumerate(self.pending_events):
                if rtype == wanted:
                    del self.pending_events[i]
                    return b
            rtype, err, rid, b = self.read_msg()
            if rtype == wanted:
                return b

    def banks(self):
        b = self.cmd(0x82)
        n = struct.unpack('<H', b[:2])[0]
        out, pos = {}, 2
        for _ in range(n):
            size = b[pos]
            bid, nlen = struct.unpack('<HB', b[pos + 1:pos + 4])
            out[b[pos + 4:pos + 4 + nlen].decode()] = bid
            pos += 1 + size
        return out

    def mem_get(self, start, end, bank):
        b = self.cmd(0x01, struct.pack('<BHHBH', 0, start, end, 0, bank))
        return b[2:]

    def mem_set(self, start, data, bank):
        self.cmd(0x02, struct.pack('<BHHBH', 0, start, start + len(data) - 1, 0, bank) + bytes(data))

    def checkpoint(self, addr):
        b = self.cmd(0x12, struct.pack('<HHBBBB', addr, addr, 1, 1, 4, 0))
        return struct.unpack('<I', b[:4])[0]

    def checkpoint_enable(self, num, on):
        self.cmd(0x15, struct.pack('<IB', num, 1 if on else 0))

    def stop(self):
        self.cmd(0x81)                  # ping: stannar emulatorn

    def reg_ids(self):
        b = self.cmd(0x83, b'\x00')
        n = struct.unpack('<H', b[:2])[0]
        out, pos = {}, 2
        for _ in range(n):
            size = b[pos]
            rid, bits, nlen = b[pos + 1], b[pos + 2], b[pos + 3]
            out[b[pos + 4:pos + 4 + nlen].decode()] = rid
            pos += 1 + size
        return out

    def set_reg(self, rid, value):
        self.cmd(0x32, struct.pack('<BHBBH', 0, 1, 3, rid, value))

    def resume(self):
        self.cmd(0xaa)
        # "stopped"-händelser som kom före svaret hör till tidigare kommandon
        self.pending_events.clear()

    def palette(self):
        b = self.cmd(0x91, b'\x01')
        n = struct.unpack('<H', b[:2])[0]
        pal, pos = [], 2
        for _ in range(n):
            size = b[pos]
            pal.append(tuple(b[pos + 1:pos + 4]))
            pos += 1 + size
        return pal

    def display(self):
        b = self.cmd(0x84, b'\x01\x00')
        hdr = struct.unpack('<I', b[:4])[0]
        w, h, xo, yo, iw, ih, bpp = struct.unpack('<HHHHHHB', b[4:17])
        blen = struct.unpack('<I', b[17:21])[0]
        start = 4 + hdr                 # hdr = antal byte före bildbufferten
        return w, h, xo, yo, iw, ih, b[start:start + blen]

    def quit(self):
        try:
            self.cmd(0xbb)
        except Exception:
            pass


class Game:
    def __init__(self, mon, syms):
        self.mon = mon
        self.syms = syms
        self.ram = mon.banks().get('ram', 0)
        self.pal = None

    def addr(self, name):
        return self.syms['consts'].get(name, self.syms['labels'].get(name))

    def peek(self, name, ofs=0):
        a = self.addr(name) + ofs
        return self.mon.mem_get(a, a, self.ram)[0]

    def poke(self, name, value, ofs=0):
        self.mon.mem_set(self.addr(name) + ofs, [value], self.ram)

    def screenshot(self, path):
        from PIL import Image
        if self.pal is None:
            self.pal = self.mon.palette()
        w, h, xo, yo, iw, ih, buf = self.mon.display()
        img = Image.frombytes('P', (w, h), buf)
        flat = []
        for r, g, b in self.pal:
            flat += [r, g, b]
        img.putpalette(flat + [0] * (768 - len(flat)))
        m = 16                          # ta med lite av ramen
        img = img.crop((xo - m, yo - m, xo + iw + m, yo + ih + m)).convert('RGB')
        img = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
        img.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--roms', required=True)
    ap.add_argument('--kernal', default='kernal_generic.rom')
    ap.add_argument('--basic', default='basic_generic.rom')
    ap.add_argument('--chargen', default='chargen_openroms.rom')
    ap.add_argument('--out', default=os.path.join(ROOT, 'build', 'vice'))
    ap.add_argument('--frames', type=int, default=6500)
    ap.add_argument('--skip-level3', action='store_true', help='hoppa över nivå 3')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    prg = os.path.join(ROOT, 'build', 'flighty64.prg')
    sym = os.path.join(ROOT, 'build', 'flighty64.sym.json')
    r = subprocess.run([sys.executable, os.path.join(HERE, 'ka_subset.py'),
                        os.path.join(ROOT, 'src', 'main.asm'), '-o', prg, '--sym', sym])
    if r.returncode:
        sys.exit("Bygget misslyckades")
    with open(sym) as f:
        syms = json.load(f)

    cmd = ['x64sc', '-default', '-refreshonbreak', '-sounddev', 'dummy',
           '-kernal', os.path.join(a.roms, a.kernal),
           '-basic', os.path.join(a.roms, a.basic),
           '-chargen', os.path.join(a.roms, a.chargen),
           '-autostartprgmode', '1', '+drive8truedrive',
           '-binarymonitor', '-binarymonitoraddress', 'ip4://127.0.0.1:%d' % PORT,
           '-autostart', prg]
    env = dict(os.environ)
    xvfb = None
    if not env.get('DISPLAY'):          # ingen skärm: starta en virtuell
        xvfb = subprocess.Popen(['Xvfb', ':77', '-screen', '0', '1024x768x24'],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        env['DISPLAY'] = ':77'
        time.sleep(1)
    log = open(os.path.join(a.out, 'vice.log'), 'w')
    proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env)
    try:
        run(a, syms, Monitor(PORT))
    finally:
        for p in (proc, xvfb):
            if p:
                p.kill()
                p.wait()


def run(a, syms, mon):
    from smoke_test import bot as emu_bot  # samma enkla spelare som i smoke_test
    g = Game(mon, syms)
    labels = syms['labels']
    # Stanna en gång per bildruta vid rts i readJoy och skriv joystickens
    # värde i joy/joyNew (samma sak som readJoy räknar fram ur $dc00).
    stop_pc = labels['readJoy'] + 19
    for _ in range(150):            # vänta tills autostart har laddat programmet
        mon.stop()
        if mon.mem_get(stop_pc, stop_pc, g.ram)[0] == 0x60:
            break
        mon.resume()
        time.sleep(0.2)
    else:
        raise RuntimeError("programmet laddades aldrig")
    cp = mon.checkpoint(stop_pc)
    mon.resume()
    joy = [0]
    prev = [0]

    def frame():
        while True:
            b = mon.wait_event(0x62)    # "stopped"
            if struct.unpack('<H', b[:2])[0] == stop_pc:
                break
            mon.resume()                # något annat stoppade: fortsätt
        if joy[0] or prev[0]:
            mon.mem_set(g.addr('joy'), [joy[0], prev[0], joy[0] & ~prev[0] & 0xff], g.ram)
        prev[0] = joy[0]

    def snap(name):
        # VICE lägger bara ut bilden när emulatorn får gå fritt en stund,
        # så stoppet stängs av medan skärmbilden tas.
        mon.checkpoint_enable(cp, False)
        mon.resume()
        time.sleep(0.3)
        mon.stop()
        g.screenshot(os.path.join(a.out, name))
        mon.checkpoint_enable(cp, True)
        mon.resume()
        frame()

    # vänta in menyn
    frame()
    for _ in range(80):
        mon.resume()
        frame()
    assert g.peek('gameState') == 0, "menyn visas inte"
    snap('menu.png')
    for i in range(6):
        snap('logo%d.png' % i)
    print("meny OK, skärmbilder i", a.out)

    # starta spelet
    joy[0] = 16
    for _ in range(3):
        mon.resume()
        frame()
    joy[0] = 0
    for _ in range(3):
        mon.resume()
        frame()
    assert g.peek('gameState') == 1, "spelet startade inte"

    class View:                     # gör att smoke_test.bot kan läsa VICE:s minne
        def __init__(self):
            self.syms = syms
            self.ram = Ram()

    class Ram:
        def __getitem__(self, i):
            return mon.mem_get(i, i, g.ram)[0]

    view = View()
    seen = set()
    shots = {}
    for f in range(a.frames):
        joy[0] = emu_bot(view, f)
        g.poke('lives', 3)
        mon.resume()
        frame()
        st = (g.peek('level'), g.peek('phase'), g.peek('wave'))
        if st not in seen:
            seen.add(st)
            print("bildruta %5d: nivå %d, fas %d, våg %d" % ((f,) + st))
            shots[st] = f + 60      # skärmbild en stund in i vågen
        for key, when in list(shots.items()):
            if f == when:
                snap('lv%d_fas%d_vag%d.png' % key)
        if st[0] == 2 and st[2] == 1:
            break

    if not a.skip_level3:
        run_level3(a, g, mon, frame, snap, joy)
    print("VICE-testet klart")
    mon.quit()


def run_level3(a, g, mon, frame, snap, joy):
    """Nivå 3: hoppa till slutet av flygfasen på nivå 2 och spela banan
    ovanifrån (samma vägsökande bot som smoke_test)."""
    from smoke_test import TdView, td_bot

    def get(name, n):
        ad = g.addr(name)
        return mon.mem_get(ad, ad + n - 1, g.ram)

    def step():
        mon.resume()
        frame()

    g.poke('phase', 2)
    g.poke('wave', 3)
    g.poke('waveCol', 159)
    for f in range(800):
        g.poke('lives', 3)
        g.poke('invuln', 10)
        step()
        if g.peek('tdOn'):
            break
    assert g.peek('tdOn') == 1 and g.peek('level') == 3, "nivå 3 startade inte"
    print("nivå 3: startade (PREPARE TO JUMP)")
    joy[0] = 0
    for f in range(400):
        step()
        if f == 60:
            snap('lv3_fallskarm.png')
        if g.peek('tdState') == 2:
            break
    assert g.peek('tdState') == 2, "landade aldrig"
    print("nivå 3: landade")
    seen = set()
    for f in range(a.frames):
        joy[0] = td_bot(TdView(get), f)
        g.poke('lives', 3)
        step()
        st = (g.peek('level'), g.peek('tdOn'), g.peek('wave'), g.peek('tdState'))
        if st not in seen:
            seen.add(st)
            print("bildruta %5d: nivå %d, ovanifrån %d, våg %d, läge %d" % ((f,) + st))
            if st[1] and st[3] == 2:
                for _ in range(200):
                    joy[0] = td_bot(TdView(get), f)
                    step()
                snap('lv3_vag%d.png' % (st[2] + 1))
            if st[1] and st[3] == 3:
                snap('lv3_clear.png')
        if st[0] == 4 and st[1] == 0:
            break
    assert g.peek('level') == 4 and g.peek('tdOn') == 0, "nivå 4 startade inte efter nivå 3"
    print("nivå 3: klar, nivå 4 startade")


if __name__ == '__main__':
    main()
