# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

from rpython.rlib.rstruct.ieee import unpack_float
from rpython.rlib.runicode import str_decode_utf_8

from typhon.errors import LoadFailed
from typhon.nodes import (Assign, Binding, BindingPattern, Call, Char, Def,
                          Double, Escape, FinalPattern, Finally, Hide, If,
                          Int, IgnorePattern, ListPattern, Matcher, Method,
                          Noun, Null, Obj, Script, Sequence, Str, Try, Tuple,
                          VarPattern, ViaPattern)
from typhon.pretty import Buffer, LineWriter


# The largest tuple arity that we'll willingly decode.
MAX_ARITY = 1024


def unshift(byte):
    return chr((ord(byte[0]) - 32) % 256)


def unshiftBytes(bs):
    rv = ''
    for b in bs:
        rv += unshift(b)
    return rv


class InvalidStream(LoadFailed):
    """
    A stream was invalid.
    """


class Stream(object):

    _counter = 0

    def __init__(self, items):
        self._items = items

    def done(self):
        return self._counter >= len(self._items)

    def nextItem(self):
        if self._counter >= len(self._items):
            raise InvalidStream("Buffer underrun while streaming")
        rv = self._items[self._counter]
        self._counter += 1
        return rv

    def rewind(self):
        self._counter -= 1

    def nextByte(self):
        return ord(unshift(self.nextItem()))

    def slice(self, count):
        if self._counter + count > len(self._items):
            raise InvalidStream("Buffer underrun while streaming")

        # RPython non-negative slice proofs.
        start = self._counter
        end = start + count
        if end <= 0:
            raise InvalidStream("Negative count while slicing: %d" % count)
        if start < 0:
            raise InvalidStream("Inconceivable!")

        rv = self._items[start:end]
        self._counter += count
        return rv

    def nextShort(self):
        return self.nextByte() << 8 | self.nextByte()

    def nextDouble(self):
        # Second parameter is the big-endian flag.
        bs = unshiftBytes(self.slice(8))
        return unpack_float(bs, True)

    def nextVarInt(self):
        shift = 0
        i = 0
        cont = True
        while cont:
            b = self.nextByte()
            i |= (b & 0x7f) << shift
            shift += 7
            cont = bool(b & 0x80)
        return i


def zzd(i):
    return (i // 2) ^ -1 if i & 1 else i // 2


# The kinds for primitive nodes.
NULL, TRUE, FALSE, STR, FLOAT, CHAR, INT, TUPLE, BAG, ATTR = range(10)

kernelNodeInfo = {
    10: 'LiteralExpr',
    11: 'NounExpr',
    12: 'BindingExpr',
    13: 'SeqExpr',
    14: 'MethodCallExpr',
    15: 'Def',
    16: 'Escape',
    17: 'Object',
    18: 'Script',
    19: 'Method',
    20: 'Matcher',
    21: 'Assign',
    22: 'Finally',
    23: 'KernelTry',
    24: 'HideExpr',
    25: 'If',
    33: 'Character',
}

patternInfo = {
    27: 'Final',
    28: 'Ignore',
    29: 'Var',
    30: 'List',
    31: 'Via',
    32: 'Binding',
}


def loadPatternList(stream):
    kind = stream.nextByte()

    if kind != TUPLE:
        raise InvalidStream("Pattern list was not actually a list!")

    arity = stream.nextVarInt()
    if arity > MAX_ARITY:
        raise LoadFailed("Arity %d is unreasonable" % arity)

    return [loadPattern(stream) for _ in range(arity)]


def loadPattern(stream):
    kind = stream.nextByte()

    if kind == NULL:
        return None

    tag = patternInfo.get(kind, None)
    if tag is None:
        raise LoadFailed("Unknown pattern kind %d" % kind)

    if tag == "Binding":
        return BindingPattern(loadTerm(stream))

    elif tag == "Final":
        return FinalPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "Ignore":
        return IgnorePattern(loadTerm(stream))

    elif tag == "List":
        return ListPattern(loadPatternList(stream), loadPattern(stream))

    elif tag == "Var":
        return VarPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "Via":
        return ViaPattern(loadTerm(stream), loadPattern(stream))

    raise LoadFailed("Unknown pattern tag %s (implementation error)" % tag)


def loadTerm(stream):
    kind = stream.nextByte()

    if kind == NULL:
        return Null
    elif kind == STR:
        size = stream.nextVarInt()
        # Special-case zero-length strings to avoid confusing Stream.slice().
        if size == 0:
            return Str(u"")
        s = stream.slice(size)
        try:
            rv = s.decode('utf-8')
        except UnicodeDecodeError:
            raise LoadFailed("Couldn't decode string %s" % s)
        return Str(rv)
    elif kind == FLOAT:
        return Double(stream.nextDouble())
    elif kind == CHAR:
        buf = stream.nextItem()
        try:
            rv, count = str_decode_utf_8(buf, len(buf), None)
            while rv == u'':
                buf += stream.nextItem()
                rv, count = str_decode_utf_8(buf, len(buf), None)
        except UnicodeDecodeError:
            raise LoadFailed("Couldn't decode char %s" % buf)
        return Char(rv)
    elif kind == INT:
        return Int(zzd(stream.nextVarInt()))
    elif kind == TUPLE:
        arity = stream.nextVarInt()
        if arity > MAX_ARITY:
            raise LoadFailed("Arity %d is unreasonable" % arity)

        return Tuple([loadTerm(stream) for _ in range(arity)])

    # Well, that's it for the primitives. Let's lookup the tag.
    tag = kernelNodeInfo.get(kind, None)
    if tag is None:
        raise LoadFailed("Unknown kind %d" % kind)

    if tag == "Assign":
        return Assign.fromAST(loadTerm(stream), loadTerm(stream))

    elif tag == "BindingExpr":
        return Binding.fromAST(loadTerm(stream))

    elif tag == "Character":
        # Characters should always contain a single .char. term which can
        # stand alone in RPython.
        string = loadTerm(stream)
        if not isinstance(string, Str):
            raise InvalidStream("Character node contained non-string")
        if len(string._s) != 1:
            raise InvalidStream("Character node contained extra characters")
        return Char(string._s[0])

    elif tag == "Def":
        return Def.fromAST(loadPattern(stream), loadTerm(stream),
                loadTerm(stream))

    elif tag == "Escape":
        return Escape(loadPattern(stream), loadTerm(stream),
                loadPattern(stream), loadTerm(stream))

    elif tag == "Finally":
        return Finally(loadTerm(stream), loadTerm(stream))

    elif tag == "HideExpr":
        return Hide(loadTerm(stream))

    elif tag == "If":
        return If(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "KernelTry":
        return Try(loadTerm(stream), loadPattern(stream), loadTerm(stream))

    elif tag == "LiteralExpr":
        # LiteralExprs always contain one single literal; consume and return
        # that literal.
        return loadTerm(stream)

    elif tag == "Matcher":
        return Matcher(loadPattern(stream), loadTerm(stream))

    elif tag == "Method":
        return Method.fromAST(loadTerm(stream), loadTerm(stream),
                loadPatternList(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "MethodCallExpr":
        return Call(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "NounExpr":
        return Noun.fromAST(loadTerm(stream))

    elif tag == "Object":
        return Obj.fromAST(loadTerm(stream), loadPattern(stream),
                loadTerm(stream), loadTerm(stream))

    elif tag == "Script":
        return Script.fromAST(loadTerm(stream), loadTerm(stream),
                loadTerm(stream))

    elif tag == "SeqExpr":
        # SeqExprs contain one single tuple; consume and return the tuple
        # wrapped in a Sequence.
        return Sequence.fromAST(loadTerm(stream))

    raise LoadFailed("Unknown tag %s (implementation error)" % tag)


def load(data):
    stream = Stream(data)
    terms = []
    while not stream.done():
        term = loadTerm(stream)

        # print "Loaded term:"
        # b = Buffer()
        # term.pretty(LineWriter(b))
        # print b.get()

        terms.append(term)
    return terms


def loadModule(data):
    stream = Stream(data)
    tag = 0x22
    magic = stream.nextByte()
    if magic != tag:
        raise LoadFailed("Module magic was %d (expected %d)" % (magic, tag))

    imports = loadPatternList(stream)
    exports = []
    exportTerms = loadTerm(stream)
    if not isinstance(exportTerms, Tuple):
        raise LoadFailed("Modules must export a list of zero or more Nouns")

    for export in exportTerms._t:
        if not isinstance(export, Noun):
            raise LoadFailed("Modules may only export Nouns")

        exports.append(export.name)
    body = loadTerm(stream)

    # print "Loaded term:"
    # b = Buffer()
    # body.pretty(LineWriter(b))
    # print b.get()

    return imports, exports, body
