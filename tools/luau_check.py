#!/usr/bin/env python3
"""
luau_check.py - lightweight Luau syntax checker + undefined-global linter.

Used as a fallback when luau-analyze / selene are not available.
It implements a recursive-descent parser for the Luau grammar (including type
annotations, compound assignment, continue, if-expressions, string interpolation
and generics) and reports:
  * syntax errors (with line numbers)
  * reads/writes of globals that are not in the known Roblox/executor allow-list
  * locals shadowing/unused are NOT reported (keeps noise down)

Usage:  python3 tools/luau_check.py file1.lua [file2.lua ...]
Exit code 1 on any problem.
"""
import re
import sys

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

KNOWN_GLOBALS = set("""
game workspace script plugin shared _G _VERSION Instance Enum Color3 Vector2 Vector3 Vector2int16 Vector3int16
UDim UDim2 CFrame TweenInfo ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint
NumberRange Rect Font Ray RaycastParams OverlapParams BrickColor PhysicalProperties DateTime Random
SharedTable Faces Axes Region3 Region3int16 PathWaypoint DockWidgetPluginGuiInfo CatalogSearchParams
task math string table coroutine os utf8 buffer bit32 debug vector
print warn error assert pcall xpcall typeof type tostring tonumber pairs ipairs next select unpack
rawget rawset rawequal rawlen setmetatable getmetatable require tick time wait delay spawn newproxy
gcinfo collectgarbage settings UserSettings stats elapsedTime version loadstring getfenv setfenv
gethui getgenv getrenv setclipboard toclipboard set_clipboard writefile readfile isfile isfolder makefolder
listfiles delfile delfolder appendfile syn protectgui protect_gui cloneref identifyexecutor getexecutorname
Drawing fluxus KRNL_LOADED request http_request http
""".split())


class LuauError(Exception):
    def __init__(self, msg, line):
        super().__init__(f"line {line}: {msg}")
        self.line = line


class Tok:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind, self.value, self.line = kind, value, line

    def __repr__(self):
        return f"Tok({self.kind},{self.value!r},{self.line})"


OPS = sorted([
    "...", "..=", "//=", "==", "~=", "<=", ">=", "..", "::", "->", "+=", "-=", "*=", "/=", "%=", "^=", "//",
    "+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".",
    "?", "|", "&", "@",
], key=len, reverse=True)

NUM_RE = re.compile(r"0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?")
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def long_bracket(src, i):
    """If src[i] starts a long bracket ([[ or [==[), return (level, start_of_content) else None."""
    m = re.match(r"\[(=*)\[", src[i:])
    if not m:
        return None
    return len(m.group(1)), i + m.end()


def tokenize(src):
    toks = []
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if src.startswith("--", i):
            lb = long_bracket(src, i + 2)
            if lb:
                level, start = lb
                close = "]" + "=" * level + "]"
                j = src.find(close, start)
                if j < 0:
                    raise LuauError("unfinished long comment", line)
                line += src.count("\n", i, j)
                i = j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        if c == "[":
            lb = long_bracket(src, i)
            if lb:
                level, start = lb
                close = "]" + "=" * level + "]"
                j = src.find(close, start)
                if j < 0:
                    raise LuauError("unfinished long string", line)
                toks.append(Tok("string", src[start:j], line))
                line += src.count("\n", i, j)
                i = j + len(close)
                continue
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\":
                    if j + 1 < n and src[j + 1] == "z":
                        j += 2
                        while j < n and src[j] in " \t\r\n":
                            if src[j] == "\n":
                                line += 1
                            j += 1
                        continue
                    if j + 1 < n and src[j + 1] == "\n":
                        line += 1
                    j += 2
                    continue
                if src[j] == "\n":
                    raise LuauError("unfinished string", line)
                j += 1
            if j >= n:
                raise LuauError("unfinished string", line)
            toks.append(Tok("string", src[i + 1:j], line))
            i = j + 1
            continue
        if c == "`":
            # interpolated string: collect expressions inside {} and tokenize them recursively
            j = i + 1
            start_line = line
            parts = []
            while j < n and src[j] != "`":
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == "{":
                    depth, k = 1, j + 1
                    while k < n and depth:
                        if src[k] == "{":
                            depth += 1
                        elif src[k] == "}":
                            depth -= 1
                        k += 1
                    parts.append(src[j + 1:k - 1])
                    j = k
                    continue
                if src[j] == "\n":
                    line += 1
                j += 1
            if j >= n:
                raise LuauError("unfinished interpolated string", start_line)
            t = Tok("istring", parts, start_line)
            toks.append(t)
            i = j + 1
            continue
        m = NUM_RE.match(src, i)
        if m and (c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit())):
            toks.append(Tok("number", m.group(0), line))
            i = m.end()
            continue
        m = NAME_RE.match(src, i)
        if m:
            w = m.group(0)
            toks.append(Tok("kw" if w in KEYWORDS else "name", w, line))
            i = m.end()
            continue
        for op in OPS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, line))
                i += len(op)
                break
        else:
            raise LuauError(f"unexpected character {c!r}", line)
    toks.append(Tok("eof", "<eof>", line))
    return toks


BINARY_PRI = {
    "or": (1, 1), "and": (2, 2),
    "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3), "~=": (3, 3), "==": (3, 3),
    "..": (5, 4),
    "+": (6, 6), "-": (6, 6),
    "*": (7, 7), "/": (7, 7), "//": (7, 7), "%": (7, 7),
    "^": (10, 9),
}
UNARY_PRI = 8
COMPOUND = {"+=", "-=", "*=", "/=", "//=", "%=", "^=", "..="}


class Scope:
    def __init__(self, parent=None):
        self.parent = parent
        self.names = set()

    def has(self, name):
        s = self
        while s:
            if name in s.names:
                return True
            s = s.parent
        return False


class Parser:
    def __init__(self, toks, extra_globals=()):
        self.toks = toks
        self.p = 0
        self.scope = Scope()
        self.problems = []
        self.globals = KNOWN_GLOBALS | set(extra_globals)
        self.type_names = set()

    # ---- token helpers
    @property
    def t(self):
        return self.toks[self.p]

    def peek(self, k=1):
        return self.toks[min(self.p + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.p]
        self.p += 1
        return t

    def check(self, value, kind=None):
        t = self.t
        return t.value == value and (kind is None or t.kind == kind) and t.kind in ("op", "kw", "name")

    def accept(self, value):
        if self.t.kind in ("op", "kw") and self.t.value == value:
            self.p += 1
            return True
        return False

    def expect(self, value, opener=None):
        if not self.accept(value):
            extra = f" (to close '{opener[0]}' at line {opener[1]})" if opener else ""
            raise LuauError(f"expected '{value}' near '{self.t.value}'{extra}", self.t.line)

    def name(self):
        t = self.t
        if t.kind != "name":
            raise LuauError(f"expected identifier near '{t.value}'", t.line)
        self.p += 1
        return t.value

    # ---- scopes
    def push(self):
        self.scope = Scope(self.scope)

    def pop(self):
        self.scope = self.scope.parent

    def declare(self, name):
        self.scope.names.add(name)

    def use(self, name, line, write=False):
        if not self.scope.has(name) and name not in self.globals:
            self.problems.append(f"line {line}: {'write to' if write else 'unknown'} global '{name}'")

    # ---- blocks
    def block(self, terminators):
        while True:
            t = self.t
            if t.kind == "eof" or (t.kind == "kw" and t.value in terminators):
                return
            if t.kind == "kw" and t.value == "return":
                self.next()
                if not (self.t.kind == "eof" or (self.t.kind == "kw" and self.t.value in terminators) or self.check(";")):
                    self.explist()
                self.accept(";")
                continue
            self.statement()
            self.accept(";")

    def statement(self):
        t = self.t
        line = t.line
        if t.kind == "kw":
            v = t.value
            if v == "local":
                self.next()
                if self.accept("function"):
                    n = self.name()
                    self.declare(n)
                    self.funcbody(line)
                    return
                names = []
                while True:
                    names.append(self.name())
                    if self.accept(":"):
                        self.type_()
                    if not self.accept(","):
                        break
                if self.accept("="):
                    self.explist()
                for n in names:
                    self.declare(n)
                return
            if v == "function":
                self.next()
                n = self.name()
                self.use(n, line)
                while self.accept("."):
                    self.name()
                is_method = False
                if self.accept(":"):
                    self.name()
                    is_method = True
                self.funcbody(line, is_method)
                return
            if v == "if":
                self.next()
                self.expr()
                self.expect("then")
                self.push(); self.block({"elseif", "else", "end"}); self.pop()
                while self.accept("elseif"):
                    self.expr()
                    self.expect("then")
                    self.push(); self.block({"elseif", "else", "end"}); self.pop()
                if self.accept("else"):
                    self.push(); self.block({"end"}); self.pop()
                self.expect("end", ("if", line))
                return
            if v == "while":
                self.next()
                self.expr()
                self.expect("do")
                self.push(); self.block({"end"}); self.pop()
                self.expect("end", ("while", line))
                return
            if v == "do":
                self.next()
                self.push(); self.block({"end"}); self.pop()
                self.expect("end", ("do", line))
                return
            if v == "for":
                self.next()
                n1 = self.name()
                if self.accept(":"):
                    self.type_()
                if self.accept("="):
                    self.expr(); self.expect(","); self.expr()
                    if self.accept(","):
                        self.expr()
                    self.expect("do")
                    self.push(); self.declare(n1)
                    self.block({"end"}); self.pop()
                    self.expect("end", ("for", line))
                    return
                names = [n1]
                while self.accept(","):
                    names.append(self.name())
                    if self.accept(":"):
                        self.type_()
                self.expect("in")
                self.explist()
                self.expect("do")
                self.push()
                for n in names:
                    self.declare(n)
                self.block({"end"}); self.pop()
                self.expect("end", ("for", line))
                return
            if v == "repeat":
                self.next()
                self.push()
                self.block({"until"})
                self.expect("until", ("repeat", line))
                self.expr()
                self.pop()
                return
            if v == "break":
                self.next()
                return
            if v in ("return",):
                raise LuauError("unexpected return", line)
            raise LuauError(f"unexpected keyword '{v}'", line)
        if t.kind == "name":
            nx = self.peek()
            if t.value == "continue" and not (nx.kind in ("string", "istring") or (nx.kind == "op" and nx.value in
                                              ("(", ".", "[", ":", "=", ",", "{") or nx.value in COMPOUND)):
                self.next()
                return
            if t.value in ("type", "export") and self.peek().kind == "name":
                if t.value == "export":
                    self.next()
                    if not (self.t.kind == "name" and self.t.value == "type"):
                        raise LuauError("expected 'type' after export", line)
                self.next()
                tname = self.name()
                self.type_names.add(tname)
                if self.accept("<"):
                    self.generic_list()
                self.expect("=")
                self.type_()
                return
        # expression statement / assignment
        targets = [self.suffixedexp(stmt=True)]
        while self.accept(","):
            targets.append(self.suffixedexp(stmt=True))
        if self.accept("="):
            for kind, info in targets:
                if kind == "call":
                    raise LuauError("cannot assign to function call", line)
                if kind == "name":
                    self.use(info, line, write=True)
            self.explist()
            return
        if self.t.kind == "op" and self.t.value in COMPOUND:
            if targets[0][0] == "name":
                self.use(targets[0][1], line)
            self.next()
            self.expr()
            return
        if len(targets) != 1 or targets[0][0] != "call":
            raise LuauError(f"syntax error near '{self.t.value}' (incomplete statement)", self.t.line)

    def funcbody(self, line, is_method=False):
        if self.accept("<"):
            self.generic_list()
        self.expect("(")
        self.push()
        if is_method:
            self.declare("self")
        if not self.check(")"):
            while True:
                if self.accept("..."):
                    if self.accept(":"):
                        self.type_(allow_pack=True)
                    break
                self.declare(self.name())
                if self.accept(":"):
                    self.type_()
                if not self.accept(","):
                    break
        self.expect(")")
        if self.accept(":"):
            self.return_type()
        self.block({"end"})
        self.expect("end", ("function", line))
        self.pop()

    def generic_list(self):
        while True:
            if self.accept("..."):
                pass
            else:
                self.name()
                self.accept("...")
            if self.accept("="):
                self.type_()
            if not self.accept(","):
                break
        self.expect(">")

    # ---- types
    def return_type(self):
        self.type_(allow_pack=True)

    def type_(self, allow_pack=False):
        self.simple_type(allow_pack)
        while True:
            if self.accept("?"):
                continue
            if self.accept("|") or self.accept("&"):
                self.simple_type(allow_pack)
                continue
            break

    def simple_type(self, allow_pack=False):
        t = self.t
        if t.kind == "kw" and t.value in ("nil", "true", "false"):
            self.next(); return
        if t.kind == "string":
            self.next(); return
        if self.accept("..."):
            self.type_()
            return
        if t.kind == "name":
            if t.value == "typeof" and self.peek().value == "(":
                self.next(); self.expect("("); self.expr(); self.expect(")"); return
            self.next()
            if self.accept("."):
                self.name()
            if self.accept("<"):
                if not self.check(">"):
                    while True:
                        self.type_(allow_pack=True)
                        if not self.accept(","):
                            break
                self.expect(">")
            return
        if self.accept("{"):
            if self.accept("}"):
                return
            # array type or table type
            if not (self.t.kind == "name" and self.peek().value == ":") and not self.check("[") \
                    and not (self.t.kind == "name" and self.t.value in ("read", "write") and self.peek().kind == "name"):
                self.type_()
                self.expect("}")
                return
            while not self.check("}"):
                if self.t.kind == "name" and self.t.value in ("read", "write") and self.peek().kind == "name":
                    self.next()
                if self.accept("["):
                    self.type_(); self.expect("]"); self.expect(":"); self.type_()
                else:
                    self.name(); self.expect(":"); self.type_()
                if not (self.accept(",") or self.accept(";")):
                    break
            self.expect("}")
            return
        if self.check("<") or self.check("("):
            if self.accept("<"):
                self.generic_list()
            self.expect("(")
            if not self.check(")"):
                while True:
                    if self.t.kind == "name" and self.peek().value == ":" and self.peek(2).value != ":":
                        self.next(); self.next()
                    self.type_(allow_pack=True)
                    if not self.accept(","):
                        break
            self.expect(")")
            if self.accept("->"):
                self.return_type()
            return
        raise LuauError(f"expected type near '{t.value}'", t.line)

    # ---- expressions
    def explist(self):
        self.expr()
        while self.accept(","):
            self.expr()

    def expr(self, limit=0):
        t = self.t
        if (t.kind == "kw" and t.value == "not") or (t.kind == "op" and t.value in ("-", "#")):
            self.next()
            self.expr(UNARY_PRI)
        else:
            self.simpleexp()
        while True:
            t = self.t
            op = t.value if t.kind in ("op", "kw") else None
            if op in BINARY_PRI and BINARY_PRI[op][0] > limit:
                self.next()
                self.expr(BINARY_PRI[op][1])
            else:
                break

    def simpleexp(self):
        t = self.t
        if t.kind in ("number", "string"):
            self.next()
        elif t.kind == "istring":
            self.next()
            for part in t.value:
                sub = Parser(tokenize(part), self.globals)
                sub.scope = self.scope
                sub.expr()
                if sub.t.kind != "eof":
                    raise LuauError("bad interpolation expression", t.line)
                self.problems.extend(sub.problems)
        elif t.kind == "kw" and t.value in ("nil", "true", "false"):
            self.next()
        elif t.kind == "op" and t.value == "...":
            self.next()
        elif t.kind == "kw" and t.value == "function":
            self.next()
            self.funcbody(t.line)
        elif t.kind == "op" and t.value == "{":
            self.table()
        elif t.kind == "kw" and t.value == "if":
            self.next()
            self.expr(); self.expect("then"); self.expr()
            while self.accept("elseif"):
                self.expr(); self.expect("then"); self.expr()
            self.expect("else")
            self.expr()
        else:
            self.suffixedexp()
        if self.accept("::"):
            self.type_()

    def table(self):
        line = self.t.line
        self.expect("{")
        while not self.check("}"):
            if self.accept("["):
                self.expr(); self.expect("]"); self.expect("="); self.expr()
            elif self.t.kind == "name" and self.peek().value == "=" and self.peek().kind == "op":
                self.next(); self.next(); self.expr()
            else:
                self.expr()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}", ("{", line))

    def primaryexp(self):
        t = self.t
        if t.kind == "name":
            self.next()
            return ("name", t.value, t.line)
        if self.accept("("):
            self.expr()
            self.expect(")", ("(", t.line))
            return ("paren", None, t.line)
        raise LuauError(f"unexpected symbol near '{t.value}'", t.line)

    def suffixedexp(self, stmt=False):
        kind, info, line = self.primaryexp()
        first_name = info if kind == "name" else None
        kinds = []
        while True:
            t = self.t
            if t.kind == "op" and t.value == ".":
                self.next(); self.name(); kinds.append("index")
            elif t.kind == "op" and t.value == "[":
                self.next(); self.expr(); self.expect("]"); kinds.append("index")
            elif t.kind == "op" and t.value == ":" and self.peek().kind == "name":
                self.next(); self.name(); self.args(); kinds.append("call")
            elif (t.kind == "op" and t.value in ("(", "{")) or t.kind in ("string", "istring"):
                if t.kind == "op" and t.value == "(" and t.line != self.toks[self.p - 1].line:
                    raise LuauError("ambiguous syntax: function call on new line", t.line)
                self.args(); kinds.append("call")
            else:
                break
        if first_name is not None and (kinds or not stmt):
            # a bare statement target is checked by the caller (write / compound)
            self.use(first_name, line)
        if not kinds:
            return (kind if kind == "name" else "expr", first_name)
        return (kinds[-1], first_name)

    def args(self):
        t = self.t
        if t.kind in ("string", "istring"):
            self.simpleexp()
            return
        if t.value == "{":
            self.table()
            return
        self.expect("(")
        if not self.check(")"):
            self.explist()
        self.expect(")", ("(", t.line))


def check_source(src, extra_globals=()):
    toks = tokenize(src)
    p = Parser(toks, extra_globals)
    p.block(set())
    if p.t.kind != "eof":
        raise LuauError(f"unexpected '{p.t.value}' (unbalanced 'end'?)", p.t.line)
    return p.problems


def main(argv):
    bad = False
    extra = ()
    files = []
    for a in argv:
        if a.startswith("--globals="):
            extra = tuple(a.split("=", 1)[1].split(","))
        else:
            files.append(a)
    for f in files:
        with open(f, encoding="utf-8") as fh:
            src = fh.read()
        if src.startswith("#!") or src.startswith("--!"):
            pass
        try:
            problems = check_source(src, extra)
        except LuauError as e:
            print(f"{f}: SYNTAX ERROR {e}")
            bad = True
            continue
        for pr in problems:
            print(f"{f}: {pr}")
            bad = True
        if not problems:
            print(f"{f}: OK")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
