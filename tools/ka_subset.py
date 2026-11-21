#!/usr/bin/env python3
"""
ka_subset.py - en liten 6502-assembler för den delmängd av
KickAssembler-syntax som Flighty 64 använder.

Detta ersätter INTE KickAssembler - det är ett test-/CI-verktyg så att
källkoden kan byggas och provköras (tools/emu.py) där Java/KickAss saknas.
Den är medvetet strikt: allt den inte känner igen ger ett fel.

Stöder:
  labels (name:), multi-labels (!name: / !: med !name+ !name- !+ !-)
  .const / .label, *= adress ["namn"], .byte .word .text .fill .align
  .encoding "screencode_upper"/"screencode_mixed", #import "fil"
  .for (var i=a; i<b; i++) { ... }
  BasicUpstart2(label)
  alla legala 6502-instruktioner och adresseringssätt

Användning:
  python3 tools/ka_subset.py src/main.asm -o build/flighty64.prg [--sym build/flighty64.sym.json]
"""
import json
import os
import re
import sys


class AsmError(Exception):
    pass


# ---------------------------------------------------------------- opcodes
# mode: imp acc imm zp zpx zpy abs abx aby ind izx izy rel
OPS = {
    'adc': {'imm': 0x69, 'zp': 0x65, 'zpx': 0x75, 'abs': 0x6d, 'abx': 0x7d, 'aby': 0x79, 'izx': 0x61, 'izy': 0x71},
    'and': {'imm': 0x29, 'zp': 0x25, 'zpx': 0x35, 'abs': 0x2d, 'abx': 0x3d, 'aby': 0x39, 'izx': 0x21, 'izy': 0x31},
    'asl': {'acc': 0x0a, 'zp': 0x06, 'zpx': 0x16, 'abs': 0x0e, 'abx': 0x1e},
    'bcc': {'rel': 0x90}, 'bcs': {'rel': 0xb0}, 'beq': {'rel': 0xf0}, 'bmi': {'rel': 0x30},
    'bne': {'rel': 0xd0}, 'bpl': {'rel': 0x10}, 'bvc': {'rel': 0x50}, 'bvs': {'rel': 0x70},
    'bit': {'zp': 0x24, 'abs': 0x2c},
    'brk': {'imp': 0x00},
    'clc': {'imp': 0x18}, 'cld': {'imp': 0xd8}, 'cli': {'imp': 0x58}, 'clv': {'imp': 0xb8},
    'cmp': {'imm': 0xc9, 'zp': 0xc5, 'zpx': 0xd5, 'abs': 0xcd, 'abx': 0xdd, 'aby': 0xd9, 'izx': 0xc1, 'izy': 0xd1},
    'cpx': {'imm': 0xe0, 'zp': 0xe4, 'abs': 0xec},
    'cpy': {'imm': 0xc0, 'zp': 0xc4, 'abs': 0xcc},
    'dec': {'zp': 0xc6, 'zpx': 0xd6, 'abs': 0xce, 'abx': 0xde},
    'dex': {'imp': 0xca}, 'dey': {'imp': 0x88},
    'eor': {'imm': 0x49, 'zp': 0x45, 'zpx': 0x55, 'abs': 0x4d, 'abx': 0x5d, 'aby': 0x59, 'izx': 0x41, 'izy': 0x51},
    'inc': {'zp': 0xe6, 'zpx': 0xf6, 'abs': 0xee, 'abx': 0xfe},
    'inx': {'imp': 0xe8}, 'iny': {'imp': 0xc8},
    'jmp': {'abs': 0x4c, 'ind': 0x6c},
    'jsr': {'abs': 0x20},
    'lda': {'imm': 0xa9, 'zp': 0xa5, 'zpx': 0xb5, 'abs': 0xad, 'abx': 0xbd, 'aby': 0xb9, 'izx': 0xa1, 'izy': 0xb1},
    'ldx': {'imm': 0xa2, 'zp': 0xa6, 'zpy': 0xb6, 'abs': 0xae, 'aby': 0xbe},
    'ldy': {'imm': 0xa0, 'zp': 0xa4, 'zpx': 0xb4, 'abs': 0xac, 'abx': 0xbc},
    'lsr': {'acc': 0x4a, 'zp': 0x46, 'zpx': 0x56, 'abs': 0x4e, 'abx': 0x5e},
    'nop': {'imp': 0xea},
    'ora': {'imm': 0x09, 'zp': 0x05, 'zpx': 0x15, 'abs': 0x0d, 'abx': 0x1d, 'aby': 0x19, 'izx': 0x01, 'izy': 0x11},
    'pha': {'imp': 0x48}, 'php': {'imp': 0x08}, 'pla': {'imp': 0x68}, 'plp': {'imp': 0x28},
    'rol': {'acc': 0x2a, 'zp': 0x26, 'zpx': 0x36, 'abs': 0x2e, 'abx': 0x3e},
    'ror': {'acc': 0x6a, 'zp': 0x66, 'zpx': 0x76, 'abs': 0x6e, 'abx': 0x7e},
    'rti': {'imp': 0x40}, 'rts': {'imp': 0x60},
    'sbc': {'imm': 0xe9, 'zp': 0xe5, 'zpx': 0xf5, 'abs': 0xed, 'abx': 0xfd, 'aby': 0xf9, 'izx': 0xe1, 'izy': 0xf1},
    'sec': {'imp': 0x38}, 'sed': {'imp': 0xf8}, 'sei': {'imp': 0x78},
    'sta': {'zp': 0x85, 'zpx': 0x95, 'abs': 0x8d, 'abx': 0x9d, 'aby': 0x99, 'izx': 0x81, 'izy': 0x91},
    'stx': {'zp': 0x86, 'zpy': 0x96, 'abs': 0x8e},
    'sty': {'zp': 0x84, 'zpx': 0x94, 'abs': 0x8c},
    'tax': {'imp': 0xaa}, 'tay': {'imp': 0xa8}, 'tsx': {'imp': 0xba}, 'txa': {'imp': 0x8a},
    'txs': {'imp': 0x9a}, 'tya': {'imp': 0x98},
}
SIZE = {'imp': 1, 'acc': 1, 'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2, 'abs': 3, 'abx': 3,
        'aby': 3, 'ind': 3, 'izx': 2, 'izy': 2, 'rel': 2}
ZP_OF = {'abs': 'zp', 'abx': 'zpx', 'aby': 'zpy'}


def screencode(ch, enc):
    o = ord(ch)
    if enc == 'screencode_upper':
        if 'A' <= ch <= 'Z':
            return o - 64
        if 'a' <= ch <= 'z':
            raise AsmError("gemener i screencode_upper-text: %r" % ch)
    else:  # screencode_mixed (KickAss default)
        if 'a' <= ch <= 'z':
            return o - 96
        if 'A' <= ch <= 'Z':
            return o
    if ch == '@':
        return 0
    if ch in '[]':
        return {'[': 27, ']': 29}[ch]
    if 32 <= o <= 63:
        return o
    raise AsmError("tecken %r stöds inte" % ch)


# ---------------------------------------------------------------- lexing
def strip_comments(text):
    out = []
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if text.startswith('//', i):
            while i < n and text[i] != '\n':
                i += 1
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2)
            if j < 0:
                raise AsmError("oavslutad /* kommentar")
            out.append('\n' * text.count('\n', i, j))
            i = j + 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


class Stmt:
    def __init__(self, text, where):
        self.text = text
        self.where = where


def load_lines(path, seen):
    path = os.path.abspath(path)
    with open(path, encoding='utf-8') as f:
        text = strip_comments(f.read())
    lines = []
    for no, line in enumerate(text.split('\n'), 1):
        lines.append((line.rstrip(), "%s:%d" % (os.path.relpath(path), no), os.path.dirname(path)))
    return lines


def expand(lines, env, seen, out):
    """Hanterar #import och .for. env = loopvariabler."""
    i = 0
    while i < len(lines):
        raw, where, d = lines[i]
        s = raw.strip()
        for k, v in env.items():
            s = re.sub(r'\b%s\b' % re.escape(k), str(v), s)
        i += 1
        if not s:
            continue
        m = re.match(r'#import\s+"([^"]+)"$', s)
        if m:
            p = os.path.join(d, m.group(1))
            if os.path.abspath(p) in seen:
                continue
            seen.add(os.path.abspath(p))
            expand(load_lines(p, seen), env, seen, out)
            continue
        m = re.match(r'\.for\s*\(\s*var\s+(\w+)\s*=\s*([^;]+);\s*(\w+)\s*<\s*([^;]+);\s*(\w+)\s*\+\+\s*\)\s*\{$', s)
        if m:
            var, a, var2, b, var3 = m.groups()
            if not (var == var2 == var3):
                raise AsmError("%s: .for-variabel stämmer inte" % where)
            depth = 1
            body = []
            while i < len(lines):
                r2, w2, d2 = lines[i]
                t2 = r2.strip()
                i += 1
                if t2.endswith('{'):
                    depth += 1
                if t2 == '}':
                    depth -= 1
                    if depth == 0:
                        break
                body.append((r2, w2, d2))
            else:
                raise AsmError("%s: .for saknar }" % where)
            ctx = Ctx.current
            av = ctx.eval_const(a, where)
            bv = ctx.eval_const(b, where)
            for v in range(av, bv):
                e2 = dict(env)
                e2[var] = v
                expand(body, e2, seen, out)
            continue
        if s.startswith('.for'):
            raise AsmError("%s: .for-form stöds inte: %s" % (where, s))
        # .const måste kunna utvärderas tidigt (för .for-gränser)
        m = re.match(r'\.(const|label)\s+(\w+)\s*=\s*(.+)$', s)
        if m:
            Ctx.current.define_const(m.group(2), m.group(3), where)
        out.append(Stmt(s, where))


# ---------------------------------------------------------------- context
class Ctx:
    current = None

    def __init__(self):
        self.consts = {}
        self.labels = {}
        self.multi = {}       # name -> list of (stmt_index, addr)
        Ctx.current = self

    def define_const(self, name, expr, where):
        if name in self.consts:
            raise AsmError("%s: %s definierad två gånger" % (where, name))
        self.consts[name] = self.eval_const(expr, where)

    def eval_const(self, expr, where):
        v = self.evaluate(expr, where, idx=None, allow_undef=False)
        return v

    def evaluate(self, expr, where, idx, allow_undef):
        expr = expr.strip()
        lohi = None
        if expr.startswith('<') or expr.startswith('>'):
            lohi = expr[0]
            expr = expr[1:].strip()
        toks = re.findall(r'\$[0-9a-fA-F]+|%[01]+|\d+|!\w*[+-]|[A-Za-z_]\w*|<<|>>|[-+*/&|^()~]|\S', expr)
        py = []
        undefined = False
        for t in toks:
            if t.startswith('$'):
                py.append(str(int(t[1:], 16)))
            elif t.startswith('%'):
                py.append(str(int(t[1:], 2)))
            elif t[0].isdigit():
                py.append(t)
            elif t.startswith('!'):
                name, dirn = t[1:-1], t[-1]
                v = self.resolve_multi(name, dirn, idx)
                if v is None:
                    if not allow_undef:
                        raise AsmError("%s: okänd multi-label %s" % (where, t))
                    undefined = True
                    v = 0
                py.append(str(v))
            elif re.match(r'[A-Za-z_]', t):
                if t in self.consts:
                    py.append(str(self.consts[t]))
                elif t in self.labels:
                    py.append(str(self.labels[t]))
                else:
                    if not allow_undef:
                        raise AsmError("%s: okänd symbol %s" % (where, t))
                    undefined = True
                    py.append('0')
            elif t in ('+', '-', '*', '/', '&', '|', '^', '(', ')', '<<', '>>', '~'):
                py.append(t)
            else:
                raise AsmError("%s: kan inte tolka uttrycket %r" % (where, expr))
        try:
            v = eval(' '.join(py), {'__builtins__': {}}, {})
        except Exception as e:
            raise AsmError("%s: fel i uttrycket %r: %s" % (where, expr, e))
        if isinstance(v, float):
            if v != int(v):
                if undefined:
                    v = int(v)
                else:
                    raise AsmError("%s: uttrycket %r ger inte ett heltal (%s)" % (where, expr, v))
            v = int(v)
        if lohi == '<':
            v &= 0xff
        elif lohi == '>':
            v = (v >> 8) & 0xff
        if undefined:
            return None
        return v

    def resolve_multi(self, name, dirn, idx):
        lst = self.multi.get(name, [])
        if dirn == '+':
            for si, addr in lst:
                if si > idx:
                    return addr
        else:
            for si, addr in reversed(lst):
                if si < idx:
                    return addr
        return None


# ---------------------------------------------------------------- assembler
def split_operand_list(s):
    parts, cur, depth, in_str = [], '', 0, False
    for c in s:
        if in_str:
            cur += c
            if c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ',' and depth == 0:
            parts.append(cur.strip())
            cur = ''
            continue
        cur += c
    if cur.strip():
        parts.append(cur.strip())
    return parts


def parse_mode(mn, op):
    op = op.strip()
    if op == '':
        if 'imp' in OPS[mn]:
            return 'imp', None
        if 'acc' in OPS[mn]:
            return 'acc', None
        raise AsmError("operand saknas")
    if op.lower() == 'a' and 'acc' in OPS[mn]:
        return 'acc', None
    if 'rel' in OPS[mn]:
        return 'rel', op
    if op.startswith('#'):
        return 'imm', op[1:]
    m = re.match(r'\((.+)\)\s*,\s*[yY]$', op)
    if m:
        return 'izy', m.group(1)
    m = re.match(r'\((.+),\s*[xX]\s*\)$', op)
    if m:
        return 'izx', m.group(1)
    if mn == 'jmp' and op.startswith('(') and op.endswith(')'):
        return 'ind', op[1:-1]
    m = re.match(r'(.+),\s*([xXyY])$', op)
    if m:
        return ('abx' if m.group(2).lower() == 'x' else 'aby'), m.group(1)
    return 'abs', op


def assemble(main_path):
    ctx = Ctx()
    stmts = []
    seen = {os.path.abspath(main_path)}
    expand(load_lines(main_path, seen), {}, seen, stmts)

    decisions = {}
    encoding = 'screencode_mixed'
    segments = []

    def run(pass_no):
        nonlocal encoding
        encoding = 'screencode_mixed'
        mem = {}
        pc = None
        if pass_no == 1:
            ctx.multi = {}
        for idx, st in enumerate(stmts):
            s = st.text
            where = st.where
            # labels
            while True:
                m = re.match(r'(!?\w*)\s*:(?!=)\s*(.*)$', s)
                if not m or (m.group(1) == '' ):
                    break
                name = m.group(1)
                if pc is None:
                    raise AsmError("%s: label före *=" % where)
                if name.startswith('!'):
                    if pass_no == 1:
                        ctx.multi.setdefault(name[1:], []).append((idx, pc))
                else:
                    if pass_no == 1:
                        if name in ctx.labels or name in ctx.consts:
                            raise AsmError("%s: %s definierad två gånger" % (where, name))
                        ctx.labels[name] = pc
                    elif ctx.labels[name] != pc:
                        raise AsmError("%s: label %s flyttade sig mellan passen" % (where, name))
                s = m.group(2).strip()
            if not s:
                continue

            def emit(b):
                nonlocal pc
                if pass_no == 2:
                    if pc in mem:
                        raise AsmError("%s: minnesöverlapp på $%04x" % (where, pc))
                    if not (0 <= b <= 255):
                        raise AsmError("%s: bytevärde utanför 0-255: %d" % (where, b))
                    mem[pc] = b
                pc += 1

            def ev(expr):
                v = ctx.evaluate(expr, where, idx, allow_undef=(pass_no == 1))
                return v

            if re.match(r'\.(const|label)\b', s):
                continue
            m = re.match(r'\*\s*=\s*([^"]+?)\s*("([^"]*)")?$', s)
            if m:
                pc = ctx.eval_const(m.group(1), where)
                if pass_no == 2:
                    segments.append((m.group(3) or '', pc))
                continue
            m = re.match(r'BasicUpstart2\((\w+)\)$', s)
            if m:
                pc = 0x0801
                target = ev(m.group(1))
                digits = str(target if target is not None else 2061)
                if len(digits) != 4:
                    raise AsmError("%s: BasicUpstart2-adressen måste ha 4 siffror" % where)
                nxt = 0x0801 + 2 + 2 + 1 + len(digits) + 1
                for b in [nxt & 0xff, nxt >> 8, 10, 0, 0x9e] + [ord(c) for c in digits] + [0, 0, 0]:
                    emit(b)
                pc = 0x080d
                continue
            m = re.match(r'\.encoding\s+"(\w+)"$', s)
            if m:
                if m.group(1) not in ('screencode_upper', 'screencode_mixed'):
                    raise AsmError("%s: encoding stöds inte" % where)
                encoding = m.group(1)
                continue
            m = re.match(r'\.(byte|by)\s+(.+)$', s)
            if m:
                for part in split_operand_list(m.group(2)):
                    v = ev(part)
                    emit(0 if v is None else v)
                continue
            m = re.match(r'\.word\s+(.+)$', s)
            if m:
                for part in split_operand_list(m.group(1)):
                    v = ev(part)
                    v = 0 if v is None else v
                    emit(v & 0xff)
                    emit((v >> 8) & 0xff)
                continue
            m = re.match(r'\.text\s+"([^"]*)"$', s)
            if m:
                for ch in m.group(1):
                    emit(screencode(ch, encoding))
                continue
            m = re.match(r'\.fill\s+(.+)$', s)
            if m:
                parts = split_operand_list(m.group(1))
                n = ctx.eval_const(parts[0], where)
                v = ev(parts[1])
                for _ in range(n):
                    emit(0 if v is None else v)
                continue
            m = re.match(r'\.align\s+(.+)$', s)
            if m:
                a = ctx.eval_const(m.group(1), where)
                while pc % a:
                    emit(0)
                continue
            if s.startswith('.') or s.startswith('#'):
                raise AsmError("%s: okänt direktiv: %s" % (where, s))

            m = re.match(r'([a-zA-Z]{3})\b\s*(.*)$', s)
            if not m or m.group(1).lower() not in OPS:
                raise AsmError("%s: okänd instruktion: %s" % (where, s))
            mn = m.group(1)
            if mn != mn.lower():
                raise AsmError("%s: skriv instruktioner med gemener: %s" % (where, s))
            try:
                mode, expr = parse_mode(mn, m.group(2))
            except AsmError as e:
                raise AsmError("%s: %s" % (where, e))
            table = OPS[mn]
            val = ev(expr) if expr is not None else None
            if pass_no == 1:
                if mode in ZP_OF and val is not None and 0 <= val < 256 and ZP_OF[mode] in table:
                    mode = ZP_OF[mode]
                decisions[idx] = mode
            else:
                if mode in ZP_OF:
                    mode = decisions[idx]
            if mode not in table:
                raise AsmError("%s: %s stöder inte adresseringssättet %s" % (where, mn, mode))
            emit(table[mode])
            if mode == 'rel':
                if pass_no == 2:
                    off = val - (pc + 1)
                    if not (-128 <= off <= 127):
                        raise AsmError("%s: branch utom räckhåll (%d)" % (where, off))
                    emit(off & 0xff)
                else:
                    emit(0)
            elif SIZE[mode] == 2:
                v = 0 if val is None else val
                if pass_no == 2 and not (0 <= v <= 255):
                    raise AsmError("%s: värdet %d får inte plats i en byte" % (where, v))
                emit(v & 0xff)
            elif SIZE[mode] == 3:
                v = 0 if val is None else val
                if pass_no == 2 and not (0 <= v <= 0xffff):
                    raise AsmError("%s: adressen %d utanför 0-$ffff" % (where, v))
                emit(v & 0xff)
                emit((v >> 8) & 0xff)
        return mem

    run(1)
    mem = run(2)
    return mem, ctx, segments


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('source')
    ap.add_argument('-o', '--output', required=True)
    ap.add_argument('--sym')
    a = ap.parse_args()
    try:
        mem, ctx, segments = assemble(a.source)
    except AsmError as e:
        print("FEL:", e, file=sys.stderr)
        sys.exit(1)
    lo, hi = min(mem), max(mem)
    data = bytes([lo & 0xff, lo >> 8]) + bytes(mem.get(i, 0) for i in range(lo, hi + 1))
    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    with open(a.output, 'wb') as f:
        f.write(data)
    syms = dict(ctx.consts)
    syms.update(ctx.labels)
    if a.sym:
        with open(a.sym, 'w') as f:
            json.dump({'labels': ctx.labels, 'consts': ctx.consts}, f, indent=1, sort_keys=True)
    # segmentöversikt
    code_end = max(a for a in mem if a < 0x2000)
    print("OK: $%04x-$%04x (%d byte). Kod slutar på $%04x." % (lo, hi, len(data) - 2, code_end))
    for name, addr in segments:
        print("  segment %-12s $%04x" % (name or '-', addr))


if __name__ == '__main__':
    main()
