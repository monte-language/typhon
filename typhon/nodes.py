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

import inspect
import textwrap

from rpython.rlib.jit import elidable, unroll_safe
from rpython.rlib.listsort import make_timsort_class
from rpython.rlib.rbigint import BASE10

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import LoadFailed, WrongType, userError
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.constants import NullObject
from typhon.objects.collections.helpers import asSet
from typhon.objects.collections.lists import unwrapList, wrapList
from typhon.objects.collections.maps import EMPTY_MAP, monteMap
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject, promoteToBigInt, unwrapStr)
from typhon.objects.ejectors import throwStr
from typhon.objects.root import Object, audited
from typhon.pretty import Buffer, LineWriter
from typhon.profile import profileTyphon
from typhon.quoting import quoteChar, quoteStr


def lt0(a, b):
    return a[0] < b[0]

TimSort0 = make_timsort_class(lt=lt0)


class InvalidAST(LoadFailed):
    """
    An AST was ill-formed.
    """


@autohelp
@audited.DF
class KernelAstStamp(Object):

    @method("Bool", "Any")
    def audit(self, audition):
        return True

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        if specimen.auditedBy(self):
            return specimen
        throwStr(ej, u"coerce/2: Not a KernelAST node")

kernelAstStamp = KernelAstStamp()


def withMaker(cls):
    """
    Implements the SausageFactory design pattern.
    """
    nodeName = cls.__name__.decode("utf-8")
    if cls.__init__ is object.__init__:
        names = ()
    else:
        names = inspect.getargspec(cls.__init__).args[1:]
    signature = ", ".join(['"Any"'] * (len(names) + 1))
    verb = nodeName
    if getattr(cls, "fromMonte", None) is not None:
        verb += ".fromMonte"
    arglist = ", ".join(names)
    src = """\
    @autohelp
    @audited.DF
    class %sMaker(Object):
        def printOn(self, out):
            out.call(u"print", [StrObject(u"<kernel make%s>")])

        @method(%s)
        def run(self, %s):
            return %s(%s)
    """ % (nodeName, nodeName, signature, arglist, verb, arglist)
    d = globals()
    exec textwrap.dedent(src) in d
    cls.nodeMaker = d[nodeName + "Maker"]()
    return cls


@autohelp
class Node(Object):
    """
    An AST node, either an expression or a pattern.
    """

    def auditorStamps(self):
        return asSet([selfless, transparentStamp, kernelAstStamp])

    def printOn(self, out):
        out.call(u"print", [StrObject(self.repr().decode("utf-8"))])

    def __repr__(self):
        b = Buffer()
        self.pretty(LineWriter(b))
        return b.get()

    @elidable
    def repr(self):
        return self.__repr__()

    @method("Any")
    def canonical(self):
        return self

    @method("Void")
    def getSpan(self):
        pass

    @method("List")
    def _uncall(self):
        span = wrapList([NullObject])
        return [self.nodeMaker, StrObject(u"run"),
                self.uncall().call(u"add", [span]), EMPTY_MAP]


@unroll_safe
def wrapNameList(names):
    # unroll_safe justified by inputs always being immutable. ~ C.
    # XXX monteMap()
    d = monteMap()
    for name in names:
        d[StrObject(name)] = None
    return d


def orList(left, right):
    if len(left) < len(right):
        right, left = left, right
    rv = []
    for item in left:
        if item not in right:
            rv.append(item)
    return rv + right

def printList(names):
    return u"[%s]" % u", ".join(names)


def _nano():
    from typhon.nano.mast import MastIR
    return MastIR


@autohelp
@audited.DF
class StaticScope(Object):
    """
    The sets of names which occur within this scope.
    """

    _immutable_fields_ = "read[*]", "set[*]", "defs[*]", "vars[*]", "meta"

    def __init__(self, read, set, defs, vars, meta):
        self.read = read
        self.set = set
        self.defs = defs
        self.vars = vars
        self.meta = meta

    def toString(self):
        return u"<%s := %s =~ %s + var %s%s>" % (
            printList(self.set), printList(self.read), printList(self.defs),
            printList(self.vars), u" (meta)" if self.meta else u"")

    @method.py("Any", "Any")
    def add(self, right):
        if right is NullObject:
            return self
        if isinstance(right, StaticScope):
            rightNamesRead = [name for name in right.read
                              if name not in self.defs + self.vars]
            rightNamesSet = [name for name in right.set
                             if name not in self.vars]
            for name in rightNamesSet:
                if name in self.defs:
                    raise userError(u"Can't assign to final noun %s" % name)
            return StaticScope(orList(self.read, rightNamesRead),
                               orList(self.set, rightNamesSet),
                               orList(self.defs, right.defs),
                               orList(self.vars, right.vars),
                               self.meta or right.meta)
        else:
            raise WrongType(u"Not a static scope")

    @method.py("Any")
    def hide(self):
        return StaticScope(self.read, self.set, [], [], self.meta)

    def namesUsed(self):
        return self.read + self.set

    def outNames(self):
        return self.defs + self.vars

    @method("Set")
    def getNamesRead(self):
        return wrapNameList(self.read)

    @method("Set")
    def getNamesSet(self):
        return wrapNameList(self.set)

    @method("Set")
    def getDefNames(self):
        return wrapNameList(self.defs)

    @method("Set")
    def getVarNames(self):
        return wrapNameList(self.vars)

    @method("Bool")
    def getMetaStateExprFlag(self):
        return self.meta

    @method("Set", _verb="namesUsed")
    def _namesUsed(self):
        return wrapNameList(self.namesUsed())

    @method("Set", _verb="outNames")
    def _outNames(self):
        return wrapNameList(self.outNames())

emptyScope = StaticScope([], [], [], [], False)


class Expr(Node):
    """
    The root of all expressions.
    """

@autohelp
@audited.DF
class LiteralMaker(Object):

    def printOn(self, out):
        out.call(u"print", [StrObject(u"<makeLiteral>")])

    @method("Any", "Any")
    def run(self, o):
        if o is NullObject:
            return Null
        if isinstance(o, IntObject):
            return Int(promoteToBigInt(o))
        if isinstance(o, BigInt):
            try:
                return Int(o.bi)
            except OverflowError:
                pass
        if isinstance(o, StrObject):
            return Str(o.getString())
        if isinstance(o, DoubleObject):
            return Double(o.getDouble())
        if isinstance(o, CharObject):
            return Char(o.getChar())
        raise WrongType(u"Not a literal")

makeLiteral = LiteralMaker()

@autohelp
class _Null(Expr):

    nodeMaker = makeLiteral

    def uncall(self):
        return wrapList([NullObject])

    def pretty(self, out):
        out.write("null")

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    def asNano(self):
        return _nano().NullExpr()


Null = _Null()


def nullToNone(node):
    return None if node is Null else node


@autohelp
class Int(Expr):

    def __init__(self, bi):
        self.bi = bi

    nodeMaker = makeLiteral

    def uncall(self):
        try:
            return wrapList([IntObject(self.bi.toint())])
        except OverflowError:
            return wrapList([BigInt(self.bi)])

    def pretty(self, out):
        out.write(self.bi.format(BASE10))

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Any")
    def getValue(self):
        try:
            return IntObject(self.bi.toint())
        except OverflowError:
            return BigInt(self.bi)

    def asNano(self):
        return _nano().IntExpr(self.bi)


@autohelp
class Str(Expr):

    def __init__(self, s):
        self._s = s

    nodeMaker = makeLiteral

    def uncall(self):
        return wrapList([StrObject(self._s)])

    def pretty(self, out):
        out.write(quoteStr(self._s).encode("utf-8"))

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Str")
    def getValue(self):
        return self._s

    def asNano(self):
        return _nano().StrExpr(self._s)


def strToString(s):
    if not isinstance(s, Str):
        raise InvalidAST("not a Str!")
    return s._s


@autohelp
class Double(Expr):

    def __init__(self, d):
        self._d = d

    nodeMaker = makeLiteral

    def uncall(self):
        return wrapList([DoubleObject(self._d)])

    def pretty(self, out):
        out.write("%f" % self._d)

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Double")
    def getValue(self):
        return self._d

    def asNano(self):
        return _nano().DoubleExpr(self._d)


@autohelp
class Char(Expr):

    def __init__(self, c):
        self._c = c

    nodeMaker = makeLiteral

    def uncall(self):
        return wrapList([CharObject(self._c)])

    def pretty(self, out):
        out.write(quoteChar(self._c[0]).encode("utf-8"))

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Char")
    def getValue(self):
        return self._c

    def asNano(self):
        return _nano().CharExpr(self._c)


@autohelp
@withMaker
class Assign(Expr):

    def __init__(self, target, rvalue):
        self.target = target
        self.rvalue = rvalue

    @staticmethod
    def fromMonte(target, rvalue):
        return Assign(nounToString(target), rvalue)

    def uncall(self):
        return wrapList([Noun(self.target), self.rvalue])

    def pretty(self, out):
        out.write(self.target.encode("utf-8"))
        out.write(" := ")
        self.rvalue.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        scope = StaticScope([], [self.target], [], [], False)
        scope = scope.add(self.rvalue.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"AssignExpr"

    def asNano(self):
        return _nano().AssignExpr(self.target, self.rvalue.asNano())


@autohelp
@withMaker
class Binding(Expr):

    def __init__(self, name):
        self.name = name

    @staticmethod
    def fromMonte(noun):
        return Binding(nounToString(noun))

    def uncall(self):
        return wrapList([Noun(self.name)])

    def pretty(self, out):
        out.write("&&")
        out.write(self.name.encode("utf-8"))

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([self.name], [], [], [], False)

    @method("Str")
    def getNodeName(self):
        return u"BindingExpr"


@autohelp
@withMaker
class NamedArg(Expr):

    def __init__(self, key, value):
        self.key = key
        self.value = value

    def uncall(self):
        return wrapList([self.key, self.value])

    def pretty(self, out):
        self.key.pretty(out)
        out.write(" => ")
        self.value.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        return self.key.getStaticScope().add(self.value.getStaticScope())

    @method("Str")
    def getNodeName(self):
        return u"NamedArg"

    @method("Any")
    def getKey(self):
        return self.key

    @method("Any")
    def getValue(self):
        return self.value

    def asNano(self):
        return _nano().NamedArgExpr(self.key.asNano(), self.value.asNano())


@autohelp
@withMaker
class Call(Expr):

    def __init__(self, target, verb, args, namedArgs):
        self._target = target
        self._verb = verb
        self._args = args
        self._namedArgs = namedArgs

    @staticmethod
    def fromMonte(target, verb, args, namedArgList):
        namedArgs = unwrapList(namedArgList)
        for na in namedArgs:
            if not isinstance(na, NamedArg):
                raise InvalidAST("named args must be NamedArg nodes")
        return Call(target, strToString(verb), unwrapList(args),
                    namedArgs)

    def uncall(self):
        return wrapList([self._target, StrObject(self._verb),
                          wrapList(self._args),
                          wrapList(self._namedArgs)])

    def pretty(self, out):
        self._target.pretty(out)
        out.write(".")
        out.write(self._verb.encode("utf-8"))
        out.write("(")
        l = self._args
        na = self._namedArgs
        if l:
            head = l[0]
            tail = l[1:]
            head.pretty(out)
            for item in tail:
                out.write(", ")
                item.pretty(out)
        if na:
            if l:
                out.write(", ")
            head = na[0]
            head.pretty(out)
            for na in na[1:]:
                na.pretty(out)
        out.write(")")

    @method.py("Any")
    def getStaticScope(self):
        scope = self._target.getStaticScope()
        for expr in self._args:
            scope = scope.add(expr.getStaticScope())
        for na in self._namedArgs:
            scope = scope.add(na.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"MethodCallExpr"

    @method("Any")
    def getReceiver(self):
        return self._target

    @method("Str")
    def getVerb(self):
        return self._verb

    @method("List")
    def getArgs(self):
        return self._args

    @method("List")
    def getNamedArgs(self):
        return self._namedArgs

    def asNano(self):
        return _nano().CallExpr(self._target.asNano(),
                                self._verb,
                                [a.asNano() for a in self._args],
                                [na.asNano() for na in self._namedArgs])


@autohelp
@withMaker
class Def(Expr):

    def __init__(self, pattern, ejector, value):
        self._p = pattern
        self._e = ejector
        self._v = value

    @staticmethod
    def fromMonte(pattern, ejector, value):
        if pattern is None:
            raise InvalidAST("Def pattern cannot be None")

        return Def(pattern, nullToNone(ejector),
                value if value is not None else Null)

    def uncall(self):
        return wrapList([self._p,
                          self._e if self._e is not None else NullObject,
                          self._v])

    def pretty(self, out):
        if not isinstance(self._p, VarPattern):
            out.write("def ")
        self._p.pretty(out)
        if self._e is not None:
            out.write(" exit ")
            self._e.pretty(out)
        out.write(" := ")
        self._v.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        scope = self._p.getStaticScope()
        if self._e is not None:
            scope = scope.add(self._e.getStaticScope())
        scope = scope.add(self._v.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"DefExpr"

    def asNano(self):
        return _nano().DefExpr(
            self._p.asNano(),
            self._e.asNano() if self._e is not None else _nano().NullExpr(),
            self._v.asNano())


@autohelp
@withMaker
class Escape(Expr):

    def __init__(self, pattern, node, catchPattern, catchNode):
        self._pattern = pattern
        self._node = node
        self._catchPattern = catchPattern
        self._catchNode = nullToNone(catchNode)

    def uncall(self):
        return wrapList(
            [self._pattern, self._node,
             self._catchPattern if self._catchPattern is not None else NullObject,
             self._catchNode if self._catchNode is not None else NullObject])

    def pretty(self, out):
        out.write("escape ")
        self._pattern.pretty(out)
        out.writeLine(" {")
        self._node.pretty(out.indent())
        if self._catchPattern is not None and self._catchNode is not None:
            out.writeLine("")
            out.write("} catch ")
            self._catchPattern.pretty(out)
            out.writeLine(" {")
            self._catchNode.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        scope = self._pattern.getStaticScope()
        scope = scope.add(self._node.getStaticScope())
        scope = scope.hide()
        if self._catchNode is not None:
            catchScope = self._catchPattern.getStaticScope()
            catchScope = catchScope.add(self._catchNode.getStaticScope())
            scope = scope.add(catchScope.hide())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"EscapeExpr"

    def asNano(self):
        if self._catchPattern is not None and self._catchNode is not None:
            return _nano().EscapeExpr(
                self._pattern.asNano(),
                self._node.asNano(),
                self._catchPattern.asNano(),
                self._catchNode.asNano())
        else:
            return _nano().EscapeOnlyExpr(
                self._pattern.asNano(),
                self._node.asNano())


@autohelp
@withMaker
class Finally(Expr):

    def __init__(self, block, atLast):
        self._block = block
        self._atLast = atLast

    def uncall(self):
        return wrapList([self._block, self._atLast])

    def pretty(self, out):
        out.writeLine("try {")
        self._block.pretty(out.indent())
        out.writeLine("")
        out.writeLine("} finally {")
        self._atLast.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        scope = self._block.getStaticScope().hide()
        scope = scope.add(self._atLast.getStaticScope().hide())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"FinallyExpr"

    def asNano(self):
        return _nano().FinallyExpr(self._block.asNano(), self._atLast.asNano())

@autohelp
@withMaker
class Hide(Expr):

    def __init__(self, inner):
        self._inner = inner

    def uncall(self):
        return wrapList([self._inner])

    def pretty(self, out):
        out.writeLine("hide {")
        self._inner.pretty(out.indent())
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        return self._inner.getStaticScope().hide()

    @method("Str")
    def getNodeName(self):
        return u"HideExpr"

    def asNano(self):
        return _nano().HideExpr(self._inner.asNano())

@autohelp
@withMaker
class If(Expr):

    def __init__(self, test, then, otherwise):
        self._test = test
        self._then = then
        self._otherwise = otherwise

    def uncall(self):
        return wrapList([self._test, self._then, self._otherwise])

    def pretty(self, out):
        out.write("if (")
        self._test.pretty(out)
        out.writeLine(") {")
        self._then.pretty(out.indent())
        out.writeLine("")
        out.writeLine("} else {")
        self._otherwise.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        scope = self._test.getStaticScope()
        scope = scope.add(self._then.getStaticScope().hide())
        scope = scope.add(self._otherwise.getStaticScope().hide())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"IfExpr"

    def asNano(self):
        return _nano().IfExpr(self._test.asNano(), self._then.asNano(),
                              self._otherwise.asNano())

@autohelp
@withMaker
class Matcher(Expr):

    def __init__(self, pattern, block):
        if pattern is None:
            raise InvalidAST("Matcher pattern cannot be None")

        self._pattern = pattern
        self._block = block

    def uncall(self):
        return wrapList([self._pattern, self._block])

    def pretty(self, out):
        out.write("match ")
        self._pattern.pretty(out)
        out.writeLine(" {")
        self._block.pretty(out.indent())
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        scope = self._pattern.getStaticScope()
        scope = scope.add(self._block.getStaticScope())
        return scope.hide()

    @method("Str")
    def getNodeName(self):
        return u"Matcher"

    @method("Any")
    def getPattern(self):
        return self._pattern

    @method("Any")
    def getBody(self):
        return self._block

    def asNano(self):
        return _nano().MatcherExpr(self._pattern.asNano(), self._block.asNano())

@autohelp
@withMaker
class MetaContextExpr(Expr):

    def uncall(self):
        return wrapList([])

    def pretty(self, out):
        out.write("meta.context()")

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"MetaContextExpr"

    def asNano(self):
        return _nano().MetaContextExpr()

@autohelp
@withMaker
class MetaStateExpr(Expr):

    def pretty(self, out):
        out.write("meta.getState()")

    def uncall(self):
        return wrapList([])

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([], [], [], [], True)

    @method("Str")
    def getNodeName(self):
        return u"MetaStateExpr"

    def asNano(self):
        return _nano().MetaStateExpr()

@autohelp
@withMaker
class Method(Expr):

    _immutable_fields_ = ("_d", "_verb", "_ps[*]", "_namedParams[*]", "_g",
                          "_b")

    def __init__(self, doc, verb, params, namedParams, guard, block):
        self._d = doc
        self._verb = verb
        self._ps = params
        for np in namedParams:
            if not isinstance(np, NamedParam):
                raise InvalidAST("Named parameters must be NamedParam nodes")
        self._namedParams = namedParams
        self._g = nullToNone(guard)
        self._b = block

    @staticmethod
    def fromMonte(doc, verb, params, namedParams, guard, block):
        if doc is NullObject:
            d = u""
        else:
            d = unwrapStr(doc)
        return Method(d, unwrapStr(verb), unwrapList(params),
                      unwrapList(namedParams),
                      guard if guard is not NullObject else None, block)

    def uncall(self):
        return wrapList(
            [StrObject(self._d if self._d else u""), StrObject(self._verb),
             wrapList(self._ps), wrapList(self._namedParams),
             self._g if self._g is not None else NullObject,
             self._b])

    def pretty(self, out):
        out.write("method ")
        out.write(self._verb.encode("utf-8"))
        out.write("(")
        l = self._ps
        if l:
            head = l[0]
            tail = l[1:]
            head.pretty(out)
            for item in tail:
                out.write(", ")
                item.pretty(out)
        if self._namedParams:
            if l:
                out.write(", ")
            self._namedParams[0].pretty(out)
            for item in self._namedParams[1:]:
                out.write(", ")
                item.pretty(out)
        if self._g is None:
            out.writeLine(") {")
        else:
            out.write(") :")
            self._g.pretty(out)
            out.writeLine(" {")
        self._b.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        scope = emptyScope
        for patt in self._ps:
            scope = scope.add(patt.getStaticScope())
        for patt in self._namedParams:
            scope = scope.add(patt.getStaticScope())
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        scope = scope.add(self._b.getStaticScope())
        return scope.hide()

    @method("Str")
    def getNodeName(self):
        return u"Method"

    def getAtom(self):
        return getAtom(self._verb, len(self._ps))

    @method("List")
    def getParams(self):
        return self._ps

    @method("List")
    def getNamedParams(self):
        return self._namedParams

    @method("Any")
    def getResultGuard(self):
        return NullObject if self._g is None else self._g

    @method("Str")
    def getVerb(self):
        return self._verb

    @method("Any")
    def getBody(self):
        return self._b

    def asNano(self):
        return _nano().MethodExpr(
            self._d, self._verb,
            [p.asNano() for p in self._ps],
            [np.asNano() for np in self._namedParams],
            self._g.asNano() if self._g is not None else _nano().NullExpr(),
            self._b.asNano())


@autohelp
@withMaker
class Noun(Expr):

    _immutable_Fields_ = "noun",

    def __init__(self, noun):
        self.name = noun

    @staticmethod
    def fromMonte(noun):
        return Noun(strToString(noun))

    def uncall(self):
        return wrapList([StrObject(self.name)])

    def pretty(self, out):
        out.write(self.name.encode("utf-8"))

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([self.name], [], [], [], False)

    @method("Str")
    def getNodeName(self):
        return u"NounExpr"

    @method("Str")
    def getName(self):
        return self.name

    def asNano(self):
        return _nano().NounExpr(self.name)

def nounToString(n):
    if not isinstance(n, Noun):
        raise InvalidAST("Not a Noun")
    return n.name


@autohelp
@withMaker
class Obj(Expr):
    """
    An object.
    """

    _immutable_fields_ = "_d", "_n", "_as", "_implements[*]", "_script"

    def __init__(self, doc, name, objectAs, implements, script):
        self._d = doc
        self._n = name
        self._as = objectAs
        self._implements = implements
        self._script = script

    @staticmethod
    def fromMonte(doc, name, asExpr, auditors, script):
        if not (isinstance(name, FinalPattern) or isinstance(name, IgnorePattern)):
            raise InvalidAST("Kernel object pattern must be FinalPattern or IgnorePattern")

        if not isinstance(script, Script):
            raise InvalidAST("Object's script isn't a Script")

        doc = doc._s if isinstance(doc, Str) else None

        return Obj(doc, name, nullToNone(asExpr), unwrapList(auditors), script)

    def uncall(self):
        return wrapList(
            [StrObject(self._d if self._d else u""), self._n,
             self._as if self._as is not None else NullObject,
             wrapList(self._implements), self._script])

    def pretty(self, out):
        out.write("object ")
        self._n.pretty(out)
        if self._as is not None:
            out.write(" as ")
            self._as.pretty(out)
        if self._implements:
            out.write(" implements ")
            self._implements[0].pretty(out)
            for n in self._implements[1:]:
                out.write(", ")
                n.pretty(out)
        out.writeLine(" {")
        if self._d:
            out.indent().writeLine('"%s"' % self._d.encode("utf-8"))
        self._script.pretty(out.indent())
        out.writeLine("}")

    def asNano(self):
        return _nano().ObjectExpr(
            self._d,
            self._n.asNano(),
            ([self._as.asNano() if self._as is not None else _nano().NullExpr()] +
             [i.asNano() for i in self._implements]),
            [m.asNano() for m in self._script._methods],
            [m.asNano() for m in self._script._matchers])

    @method.py("Any")
    def getStaticScope(self):
        scope = self._n.getStaticScope()
        auditorScope = emptyScope
        if self._as is not None:
            auditorScope = self._as.getStaticScope()
        for expr in self._implements:
            auditorScope = auditorScope.add(expr.getStaticScope())
        scope = scope.add(auditorScope.hide())
        scope = scope.add(self._script.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"ObjectExpr"

    @method("Str")
    def getDocstring(self):
        return self._d if self._d else u""

    @method("Any")
    def getName(self):
        return self._n

    @method("Any")
    def getAsExpr(self):
        return self._as if self._as is not None else NullObject

    @method("List")
    def getAuditors(self):
         return self._implements

    @method("Any")
    def getScript(self):
        return self._script


@autohelp
@withMaker
class Script(Expr):

    _immutable_fields_ = "_methods[*]", "_matchers[*]", "_ss?"

    # Since scripts are typically the points at which static scope analysis is
    # done, it's useful to cache the static scope objects so that they don't
    # have to be constantly rebuilt. We use a quasi-immutable. ~ C.
    _ss = None

    def __init__(self, extends, methods, matchers):
        # XXX Expansion removes 'extends' so it will always be null here.
        self._extends = extends
        self._methods = methods
        self._matchers = matchers

    @staticmethod
    def fromMonte(extends, methods, matchers):
        extends = nullToNone(extends)
        methods = unwrapList(methods)
        for meth in methods:
            if not isinstance(meth, Method):
                raise InvalidAST("Script method isn't a Method")
        matchers = unwrapList(matchers)
        for matcher in matchers:
            if not isinstance(matcher, Matcher):
                raise InvalidAST("Script matcher isn't a Matcher")

        return Script(extends, methods, matchers)

    def uncall(self):
        return wrapList([NullObject, wrapList(self._methods),
                          wrapList(self._matchers)])

    def pretty(self, out):
        for meth in self._methods:
            meth.pretty(out)
        for matcher in self._matchers:
            matcher.pretty(out)

    @method.py("Any")
    @profileTyphon("Script.getStaticScope/0")
    def getStaticScope(self):
        if self._ss is None:
            scope = emptyScope
            for expr in self._methods:
                scope = scope.add(expr.getStaticScope())
            for expr in self._matchers:
                scope = scope.add(expr.getStaticScope())
            self._ss = scope
        return self._ss

    @method("Str")
    def getNodeName(self):
        return u"Script"

    @method("List")
    def getMethods(self):
        return self._methods

    @method("List")
    def getMatchers(self):
        return self._matchers

    @method("List", "Any")
    def getCompleteMatcher(self, ej):
        if self._matchers:
            matcher = self._matchers[-1]
            if isinstance(matcher, Matcher):
                pattern = matcher._pattern
                if pattern.refutable():
                    throwStr(ej, u"getCompleteMatcher/1: Ultimate matcher pattern is refutable")
                return [pattern, matcher._block]
        throwStr(ej, u"getCompleteMatcher/1: No matchers")

    @method("Any", "Str", "Any")
    def getMethodNamed(self, name, ej):
        for meth in self._methods:
            assert isinstance(meth, Method), "Method wasn't a method!?"
            if meth._verb == name:
                return meth
        throwStr(ej, u"getMethodNamed/2: No method named %s" % name)


@autohelp
@withMaker
class Sequence(Expr):

    _immutable_fields_ = "_l[*]",

    def __init__(self, l):
        exprs = []
        for ex in l:
            if (isinstance(ex, Sequence)):
                exprs.extend(ex._l)
            else:
                exprs.append(ex)
        self._l = exprs[:]

    @staticmethod
    def fromMonte(l):
        return Sequence(unwrapList(l))

    def uncall(self):
        return wrapList([wrapList(self._l)])

    def pretty(self, out):
        if not self._l:
            return

        init = self._l[:-1]
        last = self._l[-1]
        for item in init:
            item.pretty(out)
            out.writeLine("")
        last.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        scope = emptyScope
        for expr in self._l:
            scope = scope.add(expr.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"SeqExpr"

    @method("List")
    def getExprs(self):
        return self._l

    def asNano(self):
        return _nano().SeqExpr([it.asNano() for it in self._l])

@autohelp
@withMaker
class Try(Expr):

    def __init__(self, first, pattern, then):
        self._first = first
        self._pattern = pattern
        self._then = then

    def uncall(self):
        return wrapList([self._first, self._pattern, self._then])

    def pretty(self, out):
        out.writeLine("try {")
        self._first.pretty(out.indent())
        out.writeLine("")
        out.write("} catch ")
        self._pattern.pretty(out)
        out.writeLine(" {")
        self._then.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    @method.py("Any")
    def getStaticScope(self):
        scope = self._first.getStaticScope()
        catchScope = self._pattern.getStaticScope()
        catchScope = catchScope.add(self._then.getStaticScope())
        return scope.add(catchScope.hide())

    @method("Str")
    def getNodeName(self):
        return u"CatchExpr"

    def asNano(self):
        return _nano().TryExpr(self._first.asNano(),
                               self._pattern.asNano(),
                               self._then.asNano())


@autohelp
class Pattern(Expr):
    """
    The root of all patterns.
    """

    def __repr__(self):
        b = Buffer()
        self.pretty(LineWriter(b))
        return b.get()

    def repr(self):
        return self.__repr__()


@autohelp
@withMaker
class BindingPattern(Pattern):

    def __init__(self, noun):
        self._noun = nounToString(noun)

    def uncall(self):
        return wrapList([Noun(self._noun)])

    def pretty(self, out):
        out.write("&&")
        out.write(self._noun.encode("utf-8"))

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([], [], [], [self._noun], False)

    @method.py("Bool")
    def refutable(self):
        return False

    @method("Str")
    def getNodeName(self):
        return u"BindingPattern"

    def asNano(self):
        return _nano().BindingPatt(self._noun)


@autohelp
@withMaker
class FinalPattern(Pattern):

    def __init__(self, noun, guard):
        self._actualNoun = noun
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def uncall(self):
        return wrapList(
            [self._actualNoun,
             self._g if self._g is not None else NullObject])

    def pretty(self, out):
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        scope = StaticScope([], [], [self._n], [], False)
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        return scope

    @method.py("Bool")
    def refutable(self):
        return self._g is not None

    @method("Str")
    def getNodeName(self):
        return u"FinalPattern"

    @method("Any")
    def getNoun(self):
        return self._actualNoun

    @method("Any")
    def getGuard(self):
        if self._g is None:
            return NullObject
        return self._g

    def asNano(self):
        return _nano().FinalPatt(
            self._n,
            self._g.asNano() if self._g is not None else _nano().NullExpr()
        )


@autohelp
@withMaker
class IgnorePattern(Pattern):

    def __init__(self, guard):
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("_")
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def uncall(self):
        return wrapList([self._g if self._g is not None else NullObject])

    @method.py("Any")
    def getStaticScope(self):
        scope = emptyScope
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        return scope

    @method.py("Bool")
    def refutable(self):
        return self._g is not None

    @method("Str")
    def getNodeName(self):
        return u"IgnorePattern"

    def asNano(self):
        return _nano().IgnorePatt(
            self._g.asNano() if self._g is not None else _nano().NullExpr()
        )

@autohelp
@withMaker
class ListPattern(Pattern):

    _immutable_fields_ = "_ps[*]",

    def __init__(self, patterns, tail):
        self._ps = patterns

    @staticmethod
    def fromMonte(patterns, tail):
        patterns = unwrapList(patterns)
        for p in patterns:
            if p is None:
                raise InvalidAST("List subpattern cannot be None")

        if tail is not None:
            raise InvalidAST("Kernel list patterns have no tail")
        return ListPattern(patterns, None)

    def uncall(self):
        return wrapList([wrapList(self._ps), NullObject])

    def pretty(self, out):
        out.write("[")
        l = self._ps
        if l:
            head = l[0]
            tail = l[1:]
            head.pretty(out)
            for item in tail:
                out.write(", ")
                item.pretty(out)
        out.write("]")

    @method.py("Any")
    def getStaticScope(self):
        scope = emptyScope
        for patt in self._ps:
            scope = scope.add(patt.getStaticScope())
        return scope

    @method.py("Bool")
    def refutable(self):
        return True

    @method("Str")
    def getNodeName(self):
        return u"ListPattern"

    def asNano(self):
        return _nano().ListPatt([p.asNano() for p in self._ps])

@autohelp
@withMaker
class NamedParam(Pattern):

    _immutable_fields_ = "_k", "_p", "_default"

    def __init__(self, key, pattern, default):
        self._k = key
        if not isinstance(pattern, Pattern):
            raise InvalidAST("Named-arg pattern value must be a Pattern")
        self._p = pattern
        self._default = default

    def pretty(self, out):
        self._k.pretty(out)
        out.write(" => ")
        self._p.pretty(out)
        if self._default is not None:
            out.write(" := ")
            self._default.pretty(out)

    def uncall(self):
        return wrapList(
            [self._k, self._p,
             self._default if self._default is not None else NullObject])

    @method.py("Any")
    def getStaticScope(self):
        scope = self._k.getStaticScope().add(self._p.getStaticScope())
        if self._default is not None:
            scope = scope.add(self._default.getStaticScope())
        return scope

    @method("Any")
    def getKey(self):
        return self._k

    @method("Any")
    def getPattern(self):
        return self._p

    @method("Any", "Any")
    def getDefault(self, ej):
        if self._default is None:
            throwStr(ej, u"getDefault/1: Parameter has no default")
        return self._default

    def asNano(self):
        return _nano().NamedPattern(
            self._k.asNano(),
            self._p.asNano(),
            self._default.asNano() if self._default is not None else _nano().NullExpr()
        )


@autohelp
@withMaker
class VarPattern(Pattern):

    def __init__(self, noun, guard):
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def uncall(self):
        return wrapList(
            [Noun(self._n),
             self._g if self._g is not None else NullObject])

    def pretty(self, out):
        out.write("var ")
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        scope = StaticScope([], [], [], [self._n], False)
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        return scope

    @method.py("Bool")
    def refutable(self):
        return self._g is not None

    @method("Str")
    def getNodeName(self):
        return u"VarPattern"

    def asNano(self):
        return _nano().VarPatt(
            self._n,
            self._g.asNano() if self._g is not None else _nano().NullExpr()
        )

@autohelp
@withMaker
class ViaPattern(Pattern):

    def __init__(self, expr, pattern):
        self._expr = expr
        if pattern is None:
            raise InvalidAST("Inner pattern of via cannot be None")
        self._pattern = pattern

    def uncall(self):
        return wrapList([self._expr, self._pattern])

    def pretty(self, out):
        out.write("via (")
        self._expr.pretty(out)
        out.write(") ")
        self._pattern.pretty(out)

    @method.py("Any")
    def getStaticScope(self):
        return self._expr.getStaticScope().add(self._pattern.getStaticScope())

    @method.py("Bool")
    def refutable(self):
        return True

    @method("Str")
    def getNodeName(self):
        return u"ViaPattern"

    def asNano(self):
        return _nano().ViaPatt(self._expr.asNano(), self._pattern.asNano(), None)

def formatName(p):
    if isinstance(p, FinalPattern):
        return p._n
    return u"_"
