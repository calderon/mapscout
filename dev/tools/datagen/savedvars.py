"""Reads a SavedVariables file of the game (Lua tables written by the client)
into Python values. Only what the game writes: tables with ["key"] = and
[number] = entries, list items, strings, numbers, true, false and nil."""

import re

TOKEN = re.compile(r'''\s*(?:(--[^\n]*)|("(?:\\.|[^"\\])*")|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|([A-Za-z_][A-Za-z0-9_]*)|(\S))''')
ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "r": "\r"}


def _tokens(text):
    position = 0
    while position < len(text):
        match = TOKEN.match(text, position)
        if not match or match.end() == position:
            break
        position = match.end()
        comment, string, number, name, symbol = match.groups()
        if comment:
            continue
        if string is not None:
            yield ("string", re.sub(r"\\(\d{1,3}|.)", _unescape, string[1:-1], flags=re.S))
        elif number is not None:
            yield ("number", float(number) if any(c in number for c in ".eE") else int(number))
        elif name is not None:
            yield ("name", name)
        elif symbol is not None:
            yield ("symbol", symbol)


def _unescape(match):
    code = match.group(1)
    if code.isdigit():
        return chr(int(code))
    return ESCAPES.get(code, code)


class _Parser:
    def __init__(self, text):
        self.tokens = list(_tokens(text))
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, kind=None, value=None):
        token = self.peek()
        if (kind and token[0] != kind) or (value is not None and token[1] != value):
            raise ValueError("expected %s %s, got %r" % (kind, value, token))
        self.i += 1
        return token

    def value(self):
        kind, value = self.take()
        if kind in ("string", "number"):
            return value
        if kind == "name" and value in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[value]
        if kind == "symbol" and value == "{":
            return self.table()
        raise ValueError("unexpected %r" % (value,))

    def table(self):
        result, items = {}, []
        while self.peek() != ("symbol", "}"):
            if self.peek() == ("symbol", "["):
                self.take("symbol", "[")
                key = self.value()
                self.take("symbol", "]")
                self.take("symbol", "=")
                result[key] = self.value()
            else:
                items.append(self.value())
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("symbol", "}")
        if items and not result:
            return items
        for n, item in enumerate(items, 1):
            result[n] = item
        return result

    def assignments(self):
        out = {}
        while self.peek()[0] == "name":
            name = self.take("name")[1]
            self.take("symbol", "=")
            out[name] = self.value()
        return out


def load(text):
    """{global name: value} for a SavedVariables file's text."""
    return _Parser(text).assignments()
