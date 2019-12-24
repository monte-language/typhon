"""
The MAST format, version zero, nanopass version.
"""

from rpython.rlib.rbigint import rbigint
from rpython.rlib.rstruct.ieee import unpack_float
from rpython.rlib.runicode import str_decode_utf_8

from typhon.nano.mast import MastIR
from typhon.spans import Span


class InvalidMAST(Exception):
    """
    A MAST stream was invalid.
    """


MAGIC = "Mont\xe0MAST"


class MASTStream(object):

    index = 0

    def __init__(self, bytes, withSpans, source):
        self.bytes = bytes
        self.withSpans = withSpans
        self.source = source

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
        try:
            return unpack_float(self.nextBytes(8), True)
        except ValueError:
            raise InvalidMAST("Couldn't decode invalid double")

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

    def nextSpan(self):
        # Version 0 doesn't have spans.
        if not self.withSpans:
            return None

        b = self.nextByte()
        # Span or blob?
        if b == 'S':
            oneToOne = True
        elif b == 'B':
            oneToOne = False
        else:
            raise InvalidMAST("Couldn't decode span tag %s" % b)
        return Span(self.source, oneToOne, self.nextInt(), self.nextInt(),
                    self.nextInt(), self.nextInt())


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
        expr = self.exprAt(stream.nextInt())
        if not isinstance(expr, MastIR.Expr):
            raise InvalidMAST("Expected expr")
        return expr

    def nextExprs(self, stream):
        size = stream.nextInt()
        return [self.nextExpr(stream) for _ in range(size)]

    def nextMethods(self, stream):
        size = stream.nextInt()
        rv = [self.exprAt(stream.nextInt()) for _ in range(size)]
        for method in rv:
            if not isinstance(method, MastIR.MethodExpr):
                raise InvalidMAST("Expected method")
        return rv

    def nextMatchers(self, stream):
        size = stream.nextInt()
        rv = [self.exprAt(stream.nextInt()) for _ in range(size)]
        for matcher in rv:
            if not isinstance(matcher, MastIR.MatcherExpr):
                raise InvalidMAST("Expected matcher")
        return rv

    def nextPatt(self, stream):
        return self.pattAt(stream.nextInt())

    def nextPatts(self, stream):
        size = stream.nextInt()
        return [self.nextPatt(stream) for _ in range(size)]

    def nextNamedExprs(self, stream):
        size = stream.nextInt()
        return [MastIR.NamedArgExpr(self.nextExpr(stream),
                                    self.nextExpr(stream),
                                    None)
                for _ in range(size)]

    def nextNamedPatts(self, stream):
        size = stream.nextInt()
        return [(self.nextExpr(stream), self.nextPatt(stream),
                 self.nextExpr(stream))
                for _ in range(size)]

    def decodeNextTag(self, stream):
        tag = stream.nextByte()
        if self.noisy:
            print "Tag:", tag

        if tag == 'L':
            # Literal.
            literalTag = stream.nextByte()
            if self.noisy:
                print "Literal tag:", literalTag

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
                self.exprs.append(MastIR.CharExpr(rv, stream.nextSpan()))
            elif literalTag == 'D':
                # Double.
                self.exprs.append(MastIR.DoubleExpr(stream.nextDouble(),
                    stream.nextSpan()))
            elif literalTag == 'I':
                # Int. Read a varint and un-zz it.
                bi = stream.nextVarInt()
                shifted = bi.rshift(1)
                if bi.int_and_(1).toint():
                    shifted = shifted.int_xor(-1)
                self.exprs.append(MastIR.IntExpr(shifted, stream.nextSpan()))
            elif literalTag == 'N':
                # Null.
                self.exprs.append(MastIR.NullExpr(stream.nextSpan()))
            elif literalTag == 'S':
                # Str.
                s = stream.nextStr()
                self.exprs.append(MastIR.StrExpr(s, stream.nextSpan()))
            else:
                raise InvalidMAST("Didn't know literal tag %s" % literalTag)
        elif tag == 'P':
            # Pattern.
            pattTag = stream.nextByte()
            if self.noisy:
                print "Pattern tag:", pattTag

            if pattTag == 'F':
                # Final.
                name = stream.nextStr()
                guard = self.nextExpr(stream)
                self.patts.append(MastIR.FinalPatt(name, guard, stream.nextSpan()))
            elif pattTag == 'I':
                # Ignore.
                guard = self.nextExpr(stream)
                self.patts.append(MastIR.IgnorePatt(guard, stream.nextSpan()))
            elif pattTag == 'V':
                # Var.
                name = stream.nextStr()
                guard = self.nextExpr(stream)
                self.patts.append(MastIR.VarPatt(name, guard, stream.nextSpan()))
            elif pattTag == 'L':
                # List.
                patts = self.nextPatts(stream)
                self.patts.append(MastIR.ListPatt(patts, stream.nextSpan()))
            elif pattTag == 'A':
                # Via.
                expr = self.nextExpr(stream)
                patt = self.nextPatt(stream)
                self.patts.append(MastIR.ViaPatt(expr, patt, stream.nextSpan()))
            elif pattTag == 'B':
                # Binding.
                name = stream.nextStr()
                self.patts.append(MastIR.BindingPatt(name, stream.nextSpan()))
            else:
                raise InvalidMAST("Didn't know pattern tag %s" % pattTag)
        elif tag == 'N':
            # Noun.
            s = stream.nextStr()
            self.exprs.append(MastIR.NounExpr(s, stream.nextSpan()))
        elif tag == 'B':
            # Binding.
            s = stream.nextStr()
            self.exprs.append(MastIR.BindingExpr(s, stream.nextSpan()))
        elif tag == 'S':
            # Sequence.
            exprs = self.nextExprs(stream)
            self.exprs.append(MastIR.SeqExpr(exprs, stream.nextSpan()))
        elif tag == 'C':
            # Call.
            target = self.nextExpr(stream)
            verb = stream.nextStr()
            args = self.nextExprs(stream)
            namedArgs = self.nextNamedExprs(stream)
            self.exprs.append(MastIR.CallExpr(target, verb, args, namedArgs, stream.nextSpan()))
        elif tag == 'D':
            # Def.
            patt = self.nextPatt(stream)
            exit = self.nextExpr(stream)
            expr = self.nextExpr(stream)
            self.exprs.append(MastIR.DefExpr(patt, exit, expr, stream.nextSpan()))
        elif tag == 'e':
            # Escape (no catch).
            escapePatt = self.nextPatt(stream)
            escapeExpr = self.nextExpr(stream)
            self.exprs.append(MastIR.EscapeOnlyExpr(escapePatt, escapeExpr, stream.nextSpan()))
        elif tag == 'E':
            # Escape (with catch).
            escapePatt = self.nextPatt(stream)
            escapeExpr = self.nextExpr(stream)
            catchPatt = self.nextPatt(stream)
            catchExpr = self.nextExpr(stream)
            self.exprs.append(MastIR.EscapeExpr(escapePatt, escapeExpr,
                                                catchPatt, catchExpr, stream.nextSpan()))
        elif tag == 'O':
            # Object with no script, just direct methods and matchers.
            doc = stream.nextStr()
            patt = self.nextPatt(stream)
            asExpr = self.nextExpr(stream)
            implements = self.nextExprs(stream)
            methods = self.nextMethods(stream)
            matchers = self.nextMatchers(stream)
            self.exprs.append(MastIR.ObjectExpr(doc, patt,
                                                [asExpr] + implements,
                                                methods, matchers, stream.nextSpan()))
        elif tag == 'M':
            # Method.
            doc = stream.nextStr()
            verb = stream.nextStr()
            patts = self.nextPatts(stream)
            namedPatts = [MastIR.NamedPattern(key, value, default, None)
                          for (key, value, default)
                          in self.nextNamedPatts(stream)]
            guard = self.nextExpr(stream)
            block = self.nextExpr(stream)
            self.exprs.append(MastIR.MethodExpr(doc, verb, patts, namedPatts,
                                                guard, block, stream.nextSpan()))
        elif tag == 'R':
            # Matcher.
            patt = self.nextPatt(stream)
            block = self.nextExpr(stream)
            self.exprs.append(MastIR.MatcherExpr(patt, block, stream.nextSpan()))
        elif tag == 'A':
            # Assign.
            target = stream.nextStr()
            expr = self.nextExpr(stream)
            self.exprs.append(MastIR.AssignExpr(target, expr, stream.nextSpan()))
        elif tag == 'F':
            # Try/finally.
            tryExpr = self.nextExpr(stream)
            finallyExpr = self.nextExpr(stream)
            self.exprs.append(MastIR.FinallyExpr(tryExpr, finallyExpr, stream.nextSpan()))
        elif tag == 'Y':
            # Try/catch.
            tryExpr = self.nextExpr(stream)
            catchPatt = self.nextPatt(stream)
            catchExpr = self.nextExpr(stream)
            self.exprs.append(MastIR.TryExpr(tryExpr, catchPatt, catchExpr, stream.nextSpan()))
        elif tag == 'H':
            # Hide.
            expr = self.nextExpr(stream)
            self.exprs.append(MastIR.HideExpr(expr, stream.nextSpan()))
        elif tag == 'I':
            # If/then/else.
            cond = self.nextExpr(stream)
            cons = self.nextExpr(stream)
            alt = self.nextExpr(stream)
            self.exprs.append(MastIR.IfExpr(cond, cons, alt, stream.nextSpan()))
        elif tag == 'T':
            # Meta state.
            self.exprs.append(MastIR.MetaStateExpr(stream.nextSpan()))
        elif tag == 'X':
            # Meta context.
            self.exprs.append(MastIR.MetaContextExpr(stream.nextSpan()))
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


def loadMASTBytes(bs, filename, noisy=False):
    if not bs.startswith(MAGIC):
        raise InvalidMAST("Wrong magic bytes '%s'" % bs[:len(MAGIC)])
    bs = bs[len(MAGIC):]

    version = ord(bs[0])
    bs = bs[1:]
    if version == 0:
        withSpans = False
    elif version == 1:
        withSpans = True
    else:
        raise InvalidMAST("Unsupported MAST version '%d'" % version)

    try:
        stream = MASTStream(bs, withSpans, filename)
        context = MASTContext(noisy)
        while not stream.exhausted():
            context.decodeNextTag(stream)
    except MemoryError:
        raise InvalidMAST("Insufficient memory to decode MAST")

    try:
        return context.exprs[-1]
    except IndexError:
        raise InvalidMAST("No expressions in MAST")
