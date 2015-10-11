"""
The MAST format, version zero.
"""

from rpython.rlib.rbigint import rbigint
from rpython.rlib.rstruct.ieee import unpack_float
from rpython.rlib.runicode import str_decode_utf_8

from typhon.nodes import (Assign, Binding, BindingPattern, Call, Char, Def,
                          Double, Escape, FinalPattern, Finally, Hide, If,
                          Int, IgnorePattern, ListPattern, Matcher,
                          MetaContextExpr, MetaStateExpr, Method, NamedParam,
                          Noun, Null, Obj, Script, Sequence, Str, Try,
                          VarPattern, ViaPattern)


class InvalidMAST(Exception):
    """
    A MAST stream was invalid.
    """


MAGIC = "Mont\xe0MAST\x00"


class MASTStream(object):

    index = 0

    def __init__(self, bytes):
        self.bytes = bytes

    def exhausted(self):
        return self.index >= len(self.bytes)

    def nextByte(self):
        if self.exhausted():
            raise InvalidMAST("nextByte: Buffer underrun while streaming")
        rv = self.bytes[self.index]
        self.index += 1
        return rv

    def nextBytes(self, count):
        assert count > 0, "nextBytes: Implementation error"

        if self.exhausted():
            raise InvalidMAST("nextBytes: Buffer underrun while streaming")

        start = self.index
        assert start >= 0, "Non-negative proof"
        stop = self.index + count
        assert stop >= 0, "Non-negative proof"

        rv = self.bytes[start:stop]
        self.index = stop
        return rv

    def nextDouble(self):
        # Second parameter is the big-endian flag.
        return unpack_float(self.nextBytes(8), True)

    def nextVarInt(self):
        shift = 0
        bi = rbigint.fromint(0)
        cont = True
        while cont:
            b = ord(self.nextByte())
            bi = bi.or_(rbigint.fromint(b & 0x7f).lshift(shift))
            shift += 7
            cont = bool(b & 0x80)
        return bi

    def nextInt(self):
        try:
            return self.nextVarInt().toint()
        except OverflowError:
            raise InvalidMAST("String length overflows integer bounds")

    def nextStr(self):
        size = self.nextInt()
        if size == 0:
            return u""

        s = self.nextBytes(size)
        try:
            return s.decode('utf-8')
        except UnicodeDecodeError:
            raise InvalidMAST("Couldn't decode string %s" % s)


class MASTContext(object):

    def __init__(self, noisy=False):
        self.exprs = []
        self.patts = []
        self.noisy = noisy

    def __repr__(self):
        return "<Context(exprs=%r, patts=%r)>" % (self.exprs, self.patts)

    def exprAt(self, index):
        try:
            return self.exprs[index]
        except IndexError:
            raise InvalidMAST("Expr index %d is out of bounds" % index)

    def pattAt(self, index):
        try:
            return self.patts[index]
        except IndexError:
            raise InvalidMAST("Pattern index %d is out of bounds" % index)

    def nextExpr(self, stream):
        return self.exprAt(stream.nextInt())

    def nextExprs(self, stream):
        size = stream.nextInt()
        return [self.nextExpr(stream) for _ in range(size)]

    def nextPatt(self, stream):
        return self.pattAt(stream.nextInt())

    def nextPatts(self, stream):
        size = stream.nextInt()
        return [self.nextPatt(stream) for _ in range(size)]

    def nextNamedExprs(self, stream):
        size = stream.nextInt()
        return [(self.nextExpr(stream), self.nextExpr(stream))
                for _ in range(size)]

    def nextNamedPatts(self, stream):
        size = stream.nextInt()
        return [(self.nextExpr(stream), self.nextPatt(stream),
                 self.nextExpr(stream))
                for _ in range(size)]

    def decodeNextTag(self, stream):
        tag = stream.nextByte()
        if tag == 'L':
            # Literal.
            literalTag = stream.nextByte()
            if literalTag == 'C':
                # Character. Read bytes one-at-a-time until a code point has
                # been decoded successfully.
                buf = stream.nextByte()
                try:
                    rv, count = str_decode_utf_8(buf, len(buf), None)
                    while rv == u'':
                        buf += stream.nextByte()
                        rv, count = str_decode_utf_8(buf, len(buf), None)
                except UnicodeDecodeError:
                    raise InvalidMAST("Couldn't decode char %s" % buf)
                self.exprs.append(Char(rv))
            elif literalTag == 'D':
                # Double.
                self.exprs.append(Double(stream.nextDouble()))
            elif literalTag == 'I':
                # Int. Read a varint and un-zz it.
                bi = stream.nextVarInt()
                shifted = bi.rshift(1)
                if bi.int_and_(1).toint():
                    shifted = shifted.int_xor(-1)
                self.exprs.append(Int(shifted))
            elif literalTag == 'N':
                # Null.
                self.exprs.append(Null)
            elif literalTag == 'S':
                # Str.
                s = stream.nextStr()
                self.exprs.append(Str(s))
            else:
                raise InvalidMAST("Didn't know literal tag %s" % literalTag)
        elif tag == 'P':
            # Pattern.
            pattTag = stream.nextByte()
            if pattTag == 'F':
                # Final.
                name = stream.nextStr()
                guard = self.nextExpr(stream)
                self.patts.append(FinalPattern(Noun(name), guard))
            elif pattTag == 'I':
                # Ignore.
                guard = self.nextExpr(stream)
                self.patts.append(IgnorePattern(guard))
            elif pattTag == 'V':
                # Var.
                name = stream.nextStr()
                guard = self.nextExpr(stream)
                self.patts.append(VarPattern(Noun(name), guard))
            elif pattTag == 'L':
                # List.
                patts = self.nextPatts(stream)
                self.patts.append(ListPattern(patts, None))
            elif pattTag == 'A':
                # Via.
                expr = self.nextExpr(stream)
                patt = self.nextPatt(stream)
                self.patts.append(ViaPattern(expr, patt))
            elif pattTag == 'B':
                # Binding.
                name = stream.nextStr()
                self.patts.append(BindingPattern(Noun(name)))
            else:
                raise InvalidMAST("Didn't know pattern tag %s" % pattTag)
        elif tag == 'N':
            # Noun.
            s = stream.nextStr()
            self.exprs.append(Noun(s))
        elif tag == 'B':
            # Binding.
            s = stream.nextStr()
            self.exprs.append(Binding(s))
        elif tag == 'S':
            # Sequence.
            exprs = self.nextExprs(stream)
            self.exprs.append(Sequence(exprs))
        elif tag == 'C':
            # Call.
            target = self.nextExpr(stream)
            verb = stream.nextStr()
            args = self.nextExprs(stream)
            namedArgs = self.nextNamedExprs(stream)
            self.exprs.append(Call(target, verb, args, namedArgs))
        elif tag == 'D':
            # Def.
            patt = self.nextPatt(stream)
            exit = self.nextExpr(stream)
            expr = self.nextExpr(stream)
            self.exprs.append(Def(patt, exit, expr))
        elif tag == 'e':
            # Escape (no catch).
            escapePatt = self.nextPatt(stream)
            escapeExpr = self.nextExpr(stream)
            self.exprs.append(Escape(escapePatt, escapeExpr, None, None))
        elif tag == 'E':
            # Escape (with catch).
            escapePatt = self.nextPatt(stream)
            escapeExpr = self.nextExpr(stream)
            catchPatt = self.nextPatt(stream)
            catchExpr = self.nextExpr(stream)
            self.exprs.append(Escape(escapePatt, escapeExpr, catchPatt,
                                     catchExpr))
        elif tag == 'O':
            # Object with no script, just direct methods and matchers.
            doc = stream.nextStr()
            patt = self.nextPatt(stream)
            asExpr = self.nextExpr(stream)
            implements = self.nextExprs(stream)
            methods = self.nextExprs(stream)
            matchers = self.nextExprs(stream)
            self.exprs.append(Obj(doc, patt, asExpr, implements,
                                  Script(None, methods, matchers)))
        elif tag == 'M':
            # Method.
            doc = stream.nextStr()
            verb = stream.nextStr()
            patts = self.nextPatts(stream)
            namedPatts = [NamedParam(key, value, default)
                          for (key, value, default)
                          in self.nextNamedPatts(stream)]
            guard = self.nextExpr(stream)
            block = self.nextExpr(stream)
            self.exprs.append(Method(doc, verb, patts, namedPatts, guard,
                                     block))
        elif tag == 'R':
            # Matcher.
            patt = self.nextPatt(stream)
            block = self.nextExpr(stream)
            self.exprs.append(Matcher(patt, block))
        elif tag == 'A':
            # Assign.
            target = stream.nextStr()
            expr = self.nextExpr(stream)
            self.exprs.append(Assign(target, expr))
        elif tag == 'F':
            # Try/finally.
            tryExpr = self.nextExpr(stream)
            finallyExpr = self.nextExpr(stream)
            self.exprs.append(Finally(tryExpr, finallyExpr))
        elif tag == 'Y':
            # Try/catch.
            tryExpr = self.nextExpr(stream)
            catchPatt = self.nextPatt(stream)
            catchExpr = self.nextExpr(stream)
            self.exprs.append(Try(tryExpr, catchPatt, catchExpr))
        elif tag == 'H':
            # Hide.
            expr = self.nextExpr(stream)
            self.exprs.append(Hide(expr))
        elif tag == 'I':
            # If/then/else.
            cond = self.nextExpr(stream)
            cons = self.nextExpr(stream)
            alt = self.nextExpr(stream)
            self.exprs.append(If(cond, cons, alt))
        elif tag == 'T':
            # Meta state.
            self.exprs.append(MetaStateExpr())
        elif tag == 'X':
            # Meta context.
            self.exprs.append(MetaContextExpr())
        else:
            raise InvalidMAST("Didn't know tag %s" % tag)

        if self.noisy:
            if self.patts:
                print "Top pattern:", self.patts[-1]
            else:
                print "No patterns yet"
            if self.exprs:
                print "Top expression:", self.exprs[-1]
            else:
                print "No expressions yet"



def loadMASTHandle(handle, noisy=False):
    magic = handle.read(len(MAGIC))
    if magic != MAGIC:
        raise InvalidMAST("Wrong magic bytes '%s'" % magic)
    stream = MASTStream(handle.read())
    context = MASTContext(noisy)
    while not stream.exhausted():
        context.decodeNextTag(stream)
    return context.exprs[-1]


def loadMAST(path, noisy=False):
    with open(path, "rb") as handle:
        return loadMASTHandle(handle, noisy)
