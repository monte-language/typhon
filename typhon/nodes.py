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
from collections import OrderedDict

from rpython.rlib import rvmprof
from rpython.rlib.jit import elidable, elidable_promote, look_inside_iff
from rpython.rlib.listsort import make_timsort_class
from rpython.rlib.objectmodel import specialize
from rpython.rlib.rbigint import BASE10

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import LoadFailed, Refused, userError
from typhon.objects.auditors import deepFrozenStamp, selfless, transparentStamp
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.collections import (ConstList, ConstSet, EMPTY_MAP,
                                        monteDict, unwrapList)
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject, promoteToBigInt, unwrapStr)
from typhon.objects.ejectors import throw
from typhon.objects.meta import MetaContext
from typhon.objects.root import Object
from typhon.objects.user import Audition, BusyObject, QuietObject
from typhon.pretty import Buffer, LineWriter
from typhon.quoting import quoteChar, quoteStr
from typhon.smallcaps.code import Code
from typhon.smallcaps.ops import ops
from typhon.smallcaps.peephole import peephole


ADD_1 = getAtom(u"add", 1)
AUDIT_1 = getAtom(u"audit", 1)
CANONICAL_0 = getAtom(u"canonical", 0)
COERCE_2 = getAtom(u"coerce", 2)
GETARGS_0 = getAtom(u"getArgs", 0)
GETASEXPR_0 = getAtom(u"getAsExpr", 0)
GETAUDITORS_0 = getAtom(u"getAuditors", 0)
GETBODY_0 = getAtom(u"getBody", 0)
GETDEFNAMES_0 = getAtom(u"getDefNames", 0)
GETDEFAULT_1 = getAtom(u"getDefault", 1)
GETDOCSTRING_0 = getAtom(u"getDocstring", 0)
GETEXPRS_0 = getAtom(u"getExprs", 0)
GETGUARD_0 = getAtom(u"getGuard", 0)
GETKEY_0 = getAtom(u"getKey", 0)
GETMETASTATEEXPRFLAG_0 = getAtom(u"getMetaStateExprFlag", 0)
GETMETHODNAMED_2 = getAtom(u"getMethodNamed", 2)
GETMETHODS_0 = getAtom(u"getMethods", 0)
GETNAMESREAD_0 = getAtom(u"getNamesRead", 0)
GETNAMESSET_0 = getAtom(u"getNamesSet", 0)
GETNAME_0 = getAtom(u"getName", 0)
GETNAMEDARGS_0 = getAtom(u"getNamedArgs", 0)
GETNAMEDPATTERNS_0 = getAtom(u"getNamedPatterns", 0)
GETNODENAME_0 = getAtom(u"getNodeName", 0)
GETNOUN_0 = getAtom(u"getNoun", 0)
GETPATTERN_0 = getAtom(u"getPattern", 0)
GETPATTERNS_0 = getAtom(u"getPatterns", 0)
GETRECEIVER_0 = getAtom(u"getReceiver", 0)
GETRESULTGUARD_0 = getAtom(u"getResultGuard", 0)
GETSCRIPT_0 = getAtom(u"getScript", 0)
GETSPAN_0 = getAtom(u"getSpan", 0)
GETSTATICSCOPE_0 = getAtom(u"getStaticScope", 0)
GETVALUE_0 = getAtom(u"getValue", 0)
GETVARNAMES_0 = getAtom(u"getVarNames", 0)
GETVERB_0 = getAtom(u"getVerb", 0)
HIDE_0 = getAtom(u"hide", 0)
NAMESUSED_0 = getAtom(u"namesUsed", 0)
OUTNAMES_0 = getAtom(u"outNames", 0)
RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
RUN_3 = getAtom(u"run", 3)
RUN_4 = getAtom(u"run", 4)
RUN_5 = getAtom(u"run", 5)
RUN_6 = getAtom(u"run", 6)
UNCALL_0 = getAtom(u"_uncall", 0)

def lt0(a, b):
    return a[0] < b[0]

TimSort0 = make_timsort_class(lt=lt0)


class LocalScope(object):
    def __init__(self, parent):
        self.map = OrderedDict()
        self.children = []
        self.parent = parent
        if parent is not None:
            self.offset = parent.getOffset()
            parent.addChildScope(self)
        else:
            self.offset = 0

    def size(self):
        siz = len(self.map)
        for ch in self.children:
            siz += ch.size()
        return siz

    def getOffset(self):
        return self.offset + self.size()

    def addChildScope(self, child):
        self.children.append(child)

    def add(self, name):
        i = self.getOffset()
        if name in self.map:
            raise InvalidAST(name.encode("utf-8") +
                             " is already defined in this scope")
        self.map[name] = i
        return i

    def find(self, name):
        i = self.map.get(name, -1)
        if i == -1:
            if self.parent is not None:
                return self.parent.find(name)
        return i

    def _nameList(self):
        names = [(i, k) for k, i in self.map.items()]
        for ch in self.children:
            names.extend(ch._nameList())
        return names

    def nameList(self):
        names = self._nameList()
        TimSort0(names).sort()
        assert [i for i, k in names] == range(len(names))
        return [k for i, k in names]


class Compiler(object):

    def __init__(self, initialFrame=None, initialGlobals=None,
                 availableClosure=None, fqn=u"", methodName=u"<noMethod>"):
        self.fqn = fqn
        self.methodName = methodName

        self.instructions = []

        if initialFrame is None:
            self.frame = OrderedDict()
        else:
            self.frame = initialFrame

        if initialGlobals is None:
            self.globals = OrderedDict()
        else:
            self.globals = initialGlobals
        # print "Initial frame:", self.frame.keys()
        # print "Initial globals:", self.globals.keys()

        if availableClosure is None:
            self.availableClosure = OrderedDict()
        else:
            self.availableClosure = availableClosure
            # print "Available closure:", self.availableClosure.keys()

        self.atoms = OrderedDict()
        self.literals = OrderedDict()
        self.locals = LocalScope(None)
        self.scripts = []

    def pushScope(self):
        c = Compiler(initialFrame=self.frame, initialGlobals=self.globals,
                     availableClosure=self.availableClosure, fqn=self.fqn,
                     methodName=self.methodName)
        c.instructions = self.instructions
        c.atoms = self.atoms
        c.literals = self.literals
        c.locals = LocalScope(self.locals)
        c.scripts = self.scripts

        return c

    def makeCode(self):
        atoms = self.atoms.keys()
        frame = self.frame.keys()
        literals = self.literals.keys()
        globals = self.globals.keys()
        locals = self.locals.nameList()

        code = Code(self.fqn, self.methodName, self.instructions, atoms,
                    literals, globals, frame, locals, self.scripts)

        # Register the code for profiling.
        rvmprof.register_code(code, Code.profileName)

        # Run optimizations on code, including inner code.
        peephole(code)
        return code

    def canCloseOver(self, name):
        return name in self.frame or name in self.availableClosure

    @specialize.arg(1)
    def addInstruction(self, name, index):
        self.instructions.append((ops[name], index))

    def addAtom(self, verb, arity):
        atom = getAtom(verb, arity)
        if atom not in self.atoms:
            self.atoms[atom] = len(self.atoms)
        return self.atoms[atom]

    def addGlobal(self, name):
        if name not in self.globals:
            self.globals[name] = len(self.globals)
        return self.globals[name]

    def addFrame(self, name):
        if name not in self.frame:
            self.frame[name] = len(self.frame)
        return self.frame[name]

    def addLiteral(self, literal):
        if literal not in self.literals:
            self.literals[literal] = len(self.literals)
        return self.literals[literal]

    def addScript(self, script):
        index = len(self.scripts)
        self.scripts.append(script)
        return index

    def literal(self, literal):
        index = self.addLiteral(literal)
        self.addInstruction("LITERAL", index)

    def call(self, verb, arity):
        atom = self.addAtom(verb, arity)
        self.addInstruction("CALL", atom)

    def callMap(self, verb, arity, lenNamedArgs):
        atom = self.addAtom(verb, arity)
        self.addInstruction("BUILD_MAP", lenNamedArgs)
        self.addInstruction("CALL_MAP", atom)

    @specialize.arg(1)
    def markInstruction(self, name):
        index = len(self.instructions)
        self.addInstruction(name, 0)
        return index

    def patch(self, index):
        inst, _ = self.instructions[index]
        self.instructions[index] = inst, len(self.instructions)


def compile(node, origin):
    compiler = Compiler(fqn=origin)
    node.compile(compiler)
    return compiler.makeCode()


def interactiveCompile(node, origin):
    compiler = Compiler(fqn=origin)
    node.compile(compiler)
    return compiler.makeCode(), compiler.locals.map


class InvalidAST(LoadFailed):
    """
    An AST was ill-formed.
    """


@autohelp
class KernelAstStamp(Object):
    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        if atom is AUDIT_1:
            from typhon.objects.constants import wrapBool
            return wrapBool(True)
        if atom is COERCE_2:
            if args[0].auditedBy(self):
                return args[0]
            args[1].call(u"run", [StrObject(u"Not a KernelAst node")])
        raise Refused(self, atom, args)

kernelAstStamp = KernelAstStamp()


def withMaker(cls):
    """
    Implements the SausageFactory design pattern.
    """
    nodeName = cls.__name__.decode("utf-8")
    names = inspect.getargspec(cls.__init__).args[1:]
    verb = nodeName
    if getattr(cls, "fromMonte", None) is not None:
        verb += ".fromMonte"
    elif getattr(cls, "fromAST", None) is not None:
        verb += ".fromAST"
    arglist = u", ".join([u"args[%s]" % i for i in range(len(names))])
    runverb = 'RUN_%s' % len(names)
    src = """\
    class %sMaker(Object):
        stamps = [deepFrozenStamp]
        def printOn(self, out):
            out.call(u"print", [StrObject(u"<kernel make%s>")])
        def recv(self, atom, args):
            if atom is %s:
                return %s(%s)
            raise Refused(self, atom, args)
    """ % (nodeName, nodeName, runverb, verb, arglist)
    d = globals()
    exec textwrap.dedent(src) in d
    cls.nodeMaker = d[nodeName + "Maker"]()
    return cls


class Node(Object):
    """
    An AST node, either an expression or a pattern.
    """

    _immutable_ = True

    stamps = [selfless, transparentStamp, kernelAstStamp]

    def printOn(self, out):
        out.call(u"print", [StrObject(self.repr().decode("utf-8"))])

    def __repr__(self):
        b = Buffer()
        self.pretty(LineWriter(b))
        return b.get()

    @elidable
    def repr(self):
        return self.__repr__()

    def transform(self, f):
        """
        Apply the given transformation to all children of this node, and this
        node, bottom-up.
        """

        return f(self)

    def recv(self, atom, args):
        if atom is CANONICAL_0:
            return self
        if atom is GETSPAN_0:
            return NullObject
        if atom is UNCALL_0:
            span = ConstList([NullObject])
            return ConstList([self.nodeMaker, StrObject(u"run"),
                              self.uncall().call(u"add", [span]), EMPTY_MAP])
        raise Refused(self, atom, args)


def wrapNameList(names):
    d = monteDict()
    for name in names:
        d[StrObject(name)] = None
    return ConstSet(d)


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


@autohelp
class StaticScope(Object):
    """
    The sets of names which occur within this scope.
    """

    _immutable_ = True
    _immutable_fields_ = "read[*]", "set[*]", "defs[*]", "vars[*]", "meta"
    stamps = [deepFrozenStamp]
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
    def hide(self):
        return StaticScope(self.read, self.set, [], [], self.meta)

    def recv(self, atom, args):
        if atom is GETNAMESREAD_0:
            return wrapNameList(self.read)

        if atom is GETNAMESSET_0:
            return wrapNameList(self.set)

        if atom is GETDEFNAMES_0:
            return wrapNameList(self.defs)

        if atom is GETVARNAMES_0:
            return wrapNameList(self.vars)

        if atom is GETMETASTATEEXPRFLAG_0:
            return wrapBool(self.meta)

        if atom is HIDE_0:
            return self.hide()

        if atom is ADD_1:
            return self.add(args[0])

        if atom is NAMESUSED_0:
            return wrapNameList(self.read + self.set)

        if atom is OUTNAMES_0:
            return wrapNameList(self.defs + self.vars)

        raise Refused(self, atom, args)

emptyScope = StaticScope([], [], [], [], False)


class Expr(Node):
    """
    The root of all expressions.
    """

    _immutable_ = True

@autohelp
class LiteralMaker(Object):
    stamps = [deepFrozenStamp]
    def printOn(self, out):
        out.call(u"print", [StrObject(u"<makeLiteral>")])

    def recv(self, atom, args):
        if atom is RUN_1:
            o = args[0]
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
        raise Refused(self, atom, args)

makeLiteral = LiteralMaker()

@autohelp
class _Null(Expr):

    _immutable_ = True

    nodeMaker = makeLiteral

    def uncall(self):
        return ConstList([NullObject])

    def pretty(self, out):
        out.write("null")

    def compile(self, compiler):
        compiler.literal(NullObject)

    def getStaticScope(self):
        return emptyScope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"LiteralExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)

Null = _Null()


def nullToNone(node):
    return None if node is Null else node


@autohelp
class Int(Expr):

    _immutable_ = True

    def __init__(self, bi):
        self.bi = bi

    nodeMaker = makeLiteral

    def uncall(self):
        try:
            return ConstList([IntObject(self.bi.toint())])
        except OverflowError:
            return ConstList([BigInt(self.bi)])

    def pretty(self, out):
        out.write(self.bi.format(BASE10))

    def compile(self, compiler):
        try:
            compiler.literal(IntObject(self.bi.toint()))
        except OverflowError:
            compiler.literal(BigInt(self.bi))

    def getStaticScope(self):
        return emptyScope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"LiteralExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()


        if atom is GETVALUE_0:
            try:
                return IntObject(self.bi.toint())
            except OverflowError:
                return BigInt(self.bi)

        return Expr.recv(self, atom, args)


@autohelp
class Str(Expr):

    _immutable_ = True

    def __init__(self, s):
        self._s = s

    nodeMaker = makeLiteral

    def uncall(self):
        return ConstList([StrObject(self._s)])

    def pretty(self, out):
        out.write(quoteStr(self._s).encode("utf-8"))

    def compile(self, compiler):
        compiler.literal(StrObject(self._s))

    def getStaticScope(self):
        return emptyScope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"LiteralExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETVALUE_0:
            return StrObject(self._s)

        return Expr.recv(self, atom, args)


def strToString(s):
    if not isinstance(s, Str):
        raise InvalidAST("not a Str!")
    return s._s


class Double(Expr):

    _immutable_ = True

    def __init__(self, d):
        self._d = d

    nodeMaker = makeLiteral

    def uncall(self):
        return ConstList([DoubleObject(self._d)])

    def pretty(self, out):
        out.write("%f" % self._d)

    def compile(self, compiler):
        compiler.literal(DoubleObject(self._d))

    def getStaticScope(self):
        return emptyScope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"LiteralExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETVALUE_0:
            return DoubleObject(self._d)

        return Expr.recv(self, atom, args)


@autohelp
class Char(Expr):

    _immutable_ = True

    def __init__(self, c):
        self._c = c

    nodeMaker = makeLiteral

    def uncall(self):
        return ConstList([CharObject(self._c)])

    def pretty(self, out):
        out.write(quoteChar(self._c[0]).encode("utf-8"))

    def compile(self, compiler):
        compiler.literal(CharObject(self._c))

    def getStaticScope(self):
        return emptyScope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"LiteralExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETVALUE_0:
            return CharObject(self._c)

        return Expr.recv(self, atom, args)


@autohelp
class Tuple(Expr):

    _immutable_ = True

    _immutable_fields_ = "_t[*]",

    def __init__(self, t):
        from typhon.scopes.safe import theMakeList
        self._t = t
        self.nodeMaker = theMakeList

    def uncall(self):
        return ConstList(self._t)

    def pretty(self, out):
        out.write("[")
        l = self._t
        if l:
            head = l[0]
            tail = l[1:]
            head.pretty(out)
            for item in tail:
                out.write(", ")
                item.pretty(out)
        out.write("]")

    def transform(self, f):
        # I don't care if it's cheating. It's elegant and simple and pretty.
        return f(Tuple([node.transform(f) for node in self._t]))

    def compile(self, compiler):
        size = len(self._t)
        makeList = compiler.addGlobal(u"__makeList")
        compiler.addInstruction("NOUN_FRAME", makeList)
        # [__makeList]
        for node in self._t:
            node.compile(compiler)
            # [__makeList x0 x1 ...]
        compiler.call(u"run", size)
        # [ConstList]

    def getStaticScope(self):
        scope = emptyScope
        for expr in self._t:
            scope = scope.add(expr.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"MethodCallExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


def tupleToList(t):
    if not isinstance(t, Tuple):
        raise InvalidAST("not a Tuple: " + t.__repr__())
    return t._t


@autohelp
@withMaker
class Assign(Expr):

    _immutable_ = True

    def __init__(self, target, rvalue):
        self.target = target
        self.rvalue = rvalue

    @staticmethod
    def fromAST(target, rvalue):
        return Assign(nounToString(target), rvalue)

    def uncall(self):
        return ConstList([Noun(self.target), self.rvalue])

    def pretty(self, out):
        out.write(self.target.encode("utf-8"))
        out.write(" := ")
        self.rvalue.pretty(out)

    def transform(self, f):
        return f(Assign(self.target, self.rvalue.transform(f)))

    def compile(self, compiler):
        self.rvalue.compile(compiler)
        # [rvalue]
        compiler.addInstruction("DUP", 0)
        # [rvalue rvalue]
        # It's unknown yet whether the assignment is to a local slot or an
        # (outer) frame slot, or even to a global frame slot. Check to see
        # whether the name is already known to be local; if not, then it must
        # be in the outer frame. Unless it's not in there, in which case it
        # must be global.
        localIndex = compiler.locals.find(self.target)
        if localIndex >= 0:
            compiler.addInstruction("ASSIGN_LOCAL", localIndex)
            # [rvalue]
        elif compiler.canCloseOver(self.target):
            index = compiler.addFrame(self.target)
            compiler.addInstruction("ASSIGN_FRAME", index)
            # [rvalue]
        else:
            index = compiler.addGlobal(self.target)
            compiler.addInstruction("ASSIGN_GLOBAL", index)
            # [rvalue]

    def getStaticScope(self):
        scope = StaticScope([], [self.target], [], [], False)
        scope = scope.add(self.rvalue.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"AssignExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Binding(Expr):

    _immutable_ = True

    def __init__(self, name):
        self.name = name

    @staticmethod
    def fromAST(noun):
        return Binding(nounToString(noun))

    def uncall(self):
        return ConstList([Noun(self.name)])

    def pretty(self, out):
        out.write("&&")
        out.write(self.name.encode("utf-8"))

    def transform(self, f):
        return f(self)

    def compile(self, compiler):
        localIndex = compiler.locals.find(self.name)
        if localIndex >= 0:
            compiler.addInstruction("BINDING_LOCAL", localIndex)
            # [binding]
        elif compiler.canCloseOver(self.name):
            index = compiler.addFrame(self.name)
            compiler.addInstruction("BINDING_FRAME", index)
            # [binding]
        else:
            index = compiler.addGlobal(self.name)
            compiler.addInstruction("BINDING_GLOBAL", index)
            # [binding]

    def getStaticScope(self):
        return StaticScope([self.name], [], [], [], False)

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"BindingExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class NamedArg(Expr):
    _immutable_ = True

    def __init__(self, key, value):
        self.key = key
        self.value = value

    def uncall(self):
        return ConstList([self.key, self.value])

    def pretty(self, out):
        self.key.pretty(out)
        out.write(" => ")
        self.value.pretty(out)

    def transform(self, f):
        return f(NamedArg(self.key.transform(f), self.value.transform(f)))

    def getStaticScope(self):
        return self.key.getStaticScope().add(self.value.getStaticScope())

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"NamedArg")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETKEY_0:
            return self.key

        if atom is GETVALUE_0:
            return self.value
        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Call(Expr):

    _immutable_ = True

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

    @staticmethod
    def fromAST(target, verb, args, namedArgs):
        if not isinstance(args, Tuple):
            raise InvalidAST("args must be a tuple")
        if not isinstance(namedArgs, Tuple):
            raise InvalidAST("namedArgs must be a tuple")
        nargs = []
        for pair in namedArgs._t:
            if not (isinstance(pair, Tuple) and len(pair._t) == 2):
                raise InvalidAST("namedArgs must contain key/value pairs")
            k, patt = pair._t
            nargs.append(NamedArg(k, patt))
        return Call(target, strToString(verb), args._t, nargs)

    def uncall(self):
        return ConstList([self._target, StrObject(self._verb),
                          ConstList(self._args),
                          ConstList(self._namedArgs)])

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

    def transform(self, f):
        return f(Call(self._target.transform(f), self._verb,
                      [arg.transform(f) for arg in self._args],
                      [narg.transform(f) for narg in self._namedArgs]))

    def compile(self, compiler):
        self._target.compile(compiler)
        # [target]
        args = self._args
        arity = len(args)
        for node in args:
            node.compile(compiler)
            # [target x0 x1 ...]
        namedArgs = self._namedArgs
        namedArity = len(namedArgs)
        if namedArity == 0:
            compiler.call(self._verb, arity)
        else:
            for na in namedArgs:
                if not isinstance(na, NamedArg):
                    raise InvalidAST("named arg not a NamedArg node")
                # Compile the key...
                na.key.compile(compiler)
                # ...and the value.
                na.value.compile(compiler)
            compiler.callMap(self._verb, arity, namedArity)
        # [retval]

    def getStaticScope(self):
        scope = self._target.getStaticScope()
        for expr in self._args:
            scope = scope.add(expr.getStaticScope())
        for na in self._namedArgs:
            scope = scope.add(na.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"MethodCallExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETRECEIVER_0:
            return self._target

        if atom is GETVERB_0:
            return StrObject(self._verb)

        if atom is GETARGS_0:
            return ConstList(self._args)

        if atom is GETNAMEDARGS_0:
            return ConstList(self._namedArgs)

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Def(Expr):

    _immutable_ = True

    def __init__(self, pattern, ejector, value):
        self._p = pattern
        self._e = ejector
        self._v = value

    @staticmethod
    def fromAST(pattern, ejector, value):
        if pattern is None:
            raise InvalidAST("Def pattern cannot be None")

        return Def(pattern, nullToNone(ejector),
                value if value is not None else Null)

    def uncall(self):
        return ConstList([self._p,
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

    def transform(self, f):
        return f(Def(self._p, self._e, self._v.transform(f)))

    def compile(self, compiler):
        self._v.compile(compiler)
        # [value]
        compiler.addInstruction("DUP", 0)
        # [value value]
        if self._e is None:
            compiler.literal(NullObject)
            # [value value null]
        else:
            self._e.compile(compiler)
            # [value value ej]
        self._p.compile(compiler)
        # [value]

    def getStaticScope(self):
        scope = self._p.getStaticScope()
        if self._e is not None:
            scope = scope.add(self._e.getStaticScope())
        scope = scope.add(self._v.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"DefExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Escape(Expr):

    _immutable_ = True

    def __init__(self, pattern, node, catchPattern, catchNode):
        self._pattern = pattern
        self._node = node
        self._catchPattern = catchPattern
        self._catchNode = nullToNone(catchNode)

    def uncall(self):
        return ConstList(
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

    def transform(self, f):
        # We have to write some extra code here since catchNode could be None.
        if self._catchNode is None:
            catchNode = None
        else:
            catchNode = self._catchNode.transform(f)

        return f(Escape(self._pattern, self._node.transform(f),
            self._catchPattern, catchNode))

    def compile(self, compiler):
        ejector = compiler.markInstruction("EJECTOR")
        # [ej]
        compiler.literal(NullObject)
        # [ej null]
        subc = compiler.pushScope()
        self._pattern.compile(subc)
        # []
        self._node.compile(subc)
        # [retval]

        if self._catchNode is not None:
            jump = compiler.markInstruction("JUMP")

            # Control is resumed here by the ejector in case of ejection.
            compiler.patch(ejector)
            # [retval]
            compiler.literal(NullObject)
            # [retval null]
            subc2 = compiler.pushScope()
            self._catchPattern.compile(subc2)
            # []
            self._catchNode.compile(subc2)
            # [retval]
            compiler.patch(jump)
        else:
            compiler.patch(ejector)

    def getStaticScope(self):
        scope = self._pattern.getStaticScope()
        scope = scope.add(self._node.getStaticScope())
        scope = scope.hide()
        if self._catchNode is not None:
            catchScope = self._catchPattern.getStaticScope()
            catchScope = catchScope.add(self._catchNode.getStaticScope())
            scope = scope.add(catchScope.hide())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"EscapeExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Finally(Expr):

    _immutable_ = True

    def __init__(self, block, atLast):
        self._block = block
        self._atLast = atLast

    def uncall(self):
        return ConstList([self._block, self._atLast])

    def pretty(self, out):
        out.writeLine("try {")
        self._block.pretty(out.indent())
        out.writeLine("")
        out.writeLine("} finally {")
        self._atLast.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    def transform(self, f):
        return f(Finally(self._block.transform(f), self._atLast.transform(f)))

    def compile(self, compiler):
        unwind = compiler.markInstruction("UNWIND")
        subc = compiler.pushScope()
        self._block.compile(subc)
        handler = compiler.markInstruction("END_HANDLER")
        compiler.patch(unwind)
        self._atLast.compile(subc)
        compiler.addInstruction("POP", 0)
        dropper = compiler.markInstruction("END_HANDLER")
        compiler.patch(handler)
        compiler.patch(dropper)

    def getStaticScope(self):
        scope = self._block.getStaticScope().hide()
        scope = scope.add(self._atLast.getStaticScope().hide())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"FinallyExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Hide(Expr):

    _immutable_ = True

    def __init__(self, inner):
        self._inner = inner

    def uncall(self):
        return ConstList([self._inner])

    def pretty(self, out):
        out.writeLine("hide {")
        self._inner.pretty(out.indent())
        out.writeLine("}")

    def transform(self, f):
        return f(Hide(self._inner.transform(f)))

    def compile(self, compiler):
        self._inner.compile(compiler.pushScope())

    def getStaticScope(self):
        return self._inner.getStaticScope().hide()

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"HideExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class If(Expr):

    _immutable_ = True

    def __init__(self, test, then, otherwise):
        self._test = test
        self._then = then
        self._otherwise = otherwise

    def uncall(self):
        return ConstList([self._test, self._then, self._otherwise])

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

    def transform(self, f):
        return f(If(self._test.transform(f), self._then.transform(f),
            self._otherwise.transform(f)))

    def compile(self, compiler):
        # BRANCH otherwise
        # ...
        # JUMP end
        # otherwise: ...
        # end: ...
        subc = compiler.pushScope()
        self._test.compile(subc)
        # [condition]
        branch = compiler.markInstruction("BRANCH")
        self._then.compile(subc.pushScope())
        jump = compiler.markInstruction("JUMP")
        compiler.patch(branch)
        self._otherwise.compile(subc.pushScope())
        compiler.patch(jump)

    def getStaticScope(self):
        scope = self._test.getStaticScope()
        scope = scope.add(self._then.getStaticScope().hide())
        scope = scope.add(self._otherwise.getStaticScope().hide())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"IfExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Matcher(Expr):

    _immutable_ = True

    def __init__(self, pattern, block):
        if pattern is None:
            raise InvalidAST("Matcher pattern cannot be None")

        self._pattern = pattern
        self._block = block

    def uncall(self):
        return ConstList([self._pattern, self._block])

    def pretty(self, out):
        out.write("match ")
        self._pattern.pretty(out)
        out.writeLine(" {")
        self._block.pretty(out.indent())
        out.writeLine("}")

    def transform(self, f):
        return f(Matcher(self._pattern, self._block.transform(f)))

    def getStaticScope(self):
        scope = self._pattern.getStaticScope()
        scope = scope.add(self._block.getStaticScope())
        return scope.hide()

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"Matcher")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class MetaContextExpr(Expr):

    _immutable_ = True

    def uncall(self):
        return ConstList([])

    def pretty(self, out):
        out.write("meta.context()")

    def compile(self, compiler):
        compiler.literal(MetaContext())

    def getStaticScope(self):
        return emptyScope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"MetaContextExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class MetaStateExpr(Expr):

    _immutable_ = True

    def pretty(self, out):
        out.write("meta.getState()")

    def uncall(self):
        return ConstList([])

    def compile(self, compiler):
        # XXX should this produce outers + locals when outside an object expr?
        for k, v in compiler.frame.iteritems():
            compiler.literal(StrObject(k))
            compiler.addInstruction("BINDING_FRAME", v)
        compiler.addInstruction("BUILD_MAP", len(compiler.frame))

    def getStaticScope(self):
        return StaticScope([], [], [], [], True)

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"MetaStateExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Method(Expr):

    _immutable_ = True

    _immutable_fields_ = "_ps[*]",

    def __init__(self, doc, verb, params, namedParams, guard, block):
        self._d = doc
        self._verb = verb
        self._ps = params
        for np in namedParams:
            if not isinstance(np, NamedParam):
                raise InvalidAST("Named parameters must be NamedParam nodes")
        self._namedParams = namedParams
        self._g = guard
        self._b = block

    @staticmethod
    def fromAST(doc, verb, params, namedParams, guard, block):
        for param in params:
            if param is None:
                raise InvalidAST("Parameter patterns cannot be None")
        for np in namedParams:
            if not isinstance(np, NamedParam):
                raise InvalidAST("Named parameters must be NamedParam nodes")
        doc = doc._s if isinstance(doc, Str) else None
        return Method(doc, strToString(verb), params, namedParams, guard, block)

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
        return ConstList(
            [StrObject(self._d if self._d else u""), StrObject(self._verb),
             ConstList(self._ps), ConstList(self._namedParams), self._g,
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
        out.write(") :")
        self._g.pretty(out)
        out.writeLine(" {")
        self._b.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    def transform(self, f):
        return f(Method(self._d, self._verb, self._ps, self._namedParams, self._g,
                        self._b.transform(f)))

    def getStaticScope(self):
        scope = emptyScope
        for patt in self._ps:
            scope = scope.add(patt.getStaticScope())
        for patt in self._namedParams:
            scope = scope.add(patt.getStaticScope())
        scope = scope.add(self._g.getStaticScope())
        scope = scope.add(self._b.getStaticScope())
        return scope.hide()

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"MethodExpr")

        if atom is GETPATTERNS_0:
            return ConstList(self._ps)

        if atom is GETNAMEDPATTERNS_0:
            return ConstList(self._namedParams)

        if atom is GETRESULTGUARD_0:
            return NullObject if self._g is None else self._g

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETVERB_0:
            return StrObject(self._verb)

        if atom is GETBODY_0:
            return self._b

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Noun(Expr):

    _immutable_ = True
    _immutable_Fields_ = "noun",

    def __init__(self, noun):
        self.name = noun

    @staticmethod
    def fromAST(noun):
        return Noun(strToString(noun))

    def uncall(self):
        return ConstList([StrObject(self.name)])

    def pretty(self, out):
        out.write(self.name.encode("utf-8"))

    def compile(self, compiler):
        localIndex = compiler.locals.find(self.name)
        if localIndex >= 0:
            compiler.addInstruction("NOUN_LOCAL", localIndex)
            # print "I think", self.name, "is local"
        elif compiler.canCloseOver(self.name):
            index = compiler.addFrame(self.name)
            compiler.addInstruction("NOUN_FRAME", index)
            # print "I think", self.name, "is frame"
        else:
            index = compiler.addGlobal(self.name)
            compiler.addInstruction("NOUN_GLOBAL", index)
            # print "I think", self.name, "is global"

    def getStaticScope(self):
        return StaticScope([self.name], [], [], [], False)

    def recv(self, atom, args):
        if atom is GETNAME_0:
            return StrObject(self.name)

        if atom is GETNODENAME_0:
            return StrObject(u"NounExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)



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

    _immutable_ = True

    _immutable_fields_ = "_implements[*]",

    def __init__(self, doc, name, objectAs, implements, script):
        self._d = doc
        self._n = name
        self._as = objectAs
        self._implements = implements
        self._script = script

    @staticmethod
    def fromMonte(doc, name, asExpr, auditors, script):
        return Obj.fromAST(doc, name, Tuple([asExpr] + unwrapList(auditors)), script)

    @staticmethod
    def fromAST(doc, name, auditors, script):
        if not (isinstance(name, FinalPattern) or isinstance(name, IgnorePattern)):
            raise InvalidAST("Kernel object pattern must be FinalPattern or IgnorePattern")

        auditors = tupleToList(auditors)
        if not isinstance(script, Script):
            raise InvalidAST("Object's script isn't a Script")

        doc = doc._s if isinstance(doc, Str) else None

        return Obj(doc, name, nullToNone(auditors[0]), auditors[1:], script)

    def uncall(self):
        return ConstList(
            [StrObject(self._d if self._d else u""), self._n,
             self._as if self._as is not None else NullObject,
             ConstList(self._implements), self._script])

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

    def transform(self, f):
        return f(Obj(self._d, self._n, self._as, self._implements,
                     self._script.transform(f)))

    def compile(self, compiler):
        # Create a code object for this object.
        availableClosure = compiler.frame.copy()
        availableClosure.update(compiler.locals.map)
        numAuditors = len(self._implements) + 1
        oname = formatName(self._n)
        fqn = compiler.fqn + u"$" + oname
        self.codeScript = CodeScript(oname, self, numAuditors,
                                     availableClosure, self._d, fqn)
        self.codeScript.addScript(self._script, fqn)
        # The local closure is first to be pushed and last to be popped.
        for name in self.codeScript.closureNames:
            if name == self.codeScript.displayName:
                # Put in a null and patch it later via UserObject.patchSelf().
                compiler.literal(NullObject)
                continue
            localIndex = compiler.locals.find(name)
            if localIndex >= 0:
                compiler.addInstruction("BINDING_LOCAL", localIndex)
            elif compiler.canCloseOver(name):
                index = compiler.addFrame(name)
                compiler.addInstruction("BINDING_FRAME", index)
            else:
                index = compiler.addGlobal(name)
                compiler.addInstruction("BINDING_GLOBAL", index)

        # Globals are pushed after closure, so they'll be popped first.
        for name in self.codeScript.globalNames:
            localIndex = compiler.locals.find(name)
            if localIndex >= 0:
                compiler.addInstruction("BINDING_LOCAL", localIndex)
            elif compiler.canCloseOver(name):
                index = compiler.addFrame(name)
                compiler.addInstruction("BINDING_FRAME", index)
            else:
                index = compiler.addGlobal(name)
                compiler.addInstruction("BINDING_GLOBAL", index)
        subc = compiler.pushScope()
        if self._as is None:
            index = compiler.addGlobal(u"null")
            compiler.addInstruction("NOUN_GLOBAL", index)
        else:
            self._as.compile(subc)
        for stamp in self._implements:
            stamp.compile(subc)
        index = compiler.addScript(self.codeScript)
        compiler.addInstruction("BINDOBJECT", index)
        if isinstance(self._n, IgnorePattern):
            compiler.addInstruction("POP", 0)
            compiler.addInstruction("POP", 0)
            compiler.addInstruction("POP", 0)
        elif isinstance(self._n, FinalPattern):
            slotIndex = compiler.locals.add(self._n._n)
            compiler.addInstruction("BINDFINALSLOT", slotIndex)
        else:
            # Bail!?
            assert False, "Shouldn't happen"

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

    def recv(self, atom, args):
        if atom is GETDOCSTRING_0:
            return StrObject(self._d if self._d else u"")

        if atom is GETNAME_0:
            return self._n

        if atom is GETASEXPR_0:
            return self._as if self._as is not None else NullObject

        if atom is GETAUDITORS_0:
             return ConstList(self._implements)

        if atom is GETSCRIPT_0:
            return self._script

        if atom is GETNODENAME_0:
            return StrObject(u"ObjectExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


class CodeScript(object):

    _immutable_fields_ = ("displayName", "fqn", "objectAst", "numAuditors",
                          "closureNames", "globalNames")

    def __init__(self, displayName, objectAst, numAuditors, availableClosure,
                 doc, fqn):
        self.displayName = displayName
        self.objectAst = objectAst
        self.availableClosure = availableClosure
        self.numAuditors = numAuditors
        self.doc = doc
        self.fqn = fqn
        # Objects can close over themselves. Here we merely make sure that the
        # display name is in the available closure, but we don't close over
        # ourselves unless requested during compilation. (If we don't make the
        # display name available, then the compiler will think that it's not
        # in scope!)
        self.availableClosure[displayName] = 42

        self.methods = {}
        self.methodDocs = {}
        self.matchers = []

        self.closureNames = OrderedDict()
        self.globalNames = OrderedDict()

        self.auditions = {}

    def makeObject(self, closure, globals, auditors):
        if len(self.closureNames):
            obj = BusyObject(self, globals, closure, auditors)
        else:
            obj = QuietObject(self, globals, auditors)
        return obj

    # Picking 3 for the common case of:
    # `as DeepFrozen implements Selfless, Transparent`
    @look_inside_iff(lambda self, auditors, guards: len(auditors) <= 3)
    def audit(self, auditors, guards):
        with Audition(self.fqn, self.objectAst, guards, self.auditions) as audition:
            for a in auditors:
                audition.ask(a)
        return audition.approvers

    @elidable
    def selfIndex(self):
        """
        The index at which this codescript's objects should reference
        themselves, or -1 if the objects are not self-referential.
        """

        return self.closureNames.get(self.displayName, -1)

    def addScript(self, script, fqn):
        assert isinstance(script, Script)
        for method in script._methods:
            assert isinstance(method, Method)
            self.addMethod(method, fqn)
        for matcher in script._matchers:
            assert isinstance(matcher, Matcher)
            self.addMatcher(matcher, fqn)

    def addMethod(self, method, fqn):
        verb = method._verb
        arity = len(method._ps)
        compiler = Compiler(self.closureNames, self.globalNames,
                            self.availableClosure, fqn=fqn, methodName=verb)
        # [... specimen1 ej1 specimen0 ej0 namedArgs]
        for np in method._namedParams:
            np.compile(compiler)
        compiler.addInstruction("POP", 0)
        # [... specimen1 ej1 specimen0 ej0]
        for param in method._ps:
            # [... specimen1 ej1]
            param.compile(compiler)
            # []
        method._b.compile(compiler)
        # [retval]
        if method._g is not Null:
            # [retval]
            method._g.compile(compiler)
            # [retval guard]
            compiler.addInstruction("SWAP", 0)
            # [guard retval]
            compiler.literal(NullObject)
            # [guard retval null]
            compiler.call(u"coerce", 2)
            # [coerced]

        code = compiler.makeCode()
        atom = getAtom(verb, arity)
        self.methods[atom] = code
        if method._d is not None:
            self.methodDocs[atom] = method._d

    def addMatcher(self, matcher, fqn):
        compiler = Compiler(self.closureNames, self.globalNames,
                            self.availableClosure, fqn=fqn,
                            methodName=u"<matcher>")
        # [[verb, args] ej]
        matcher._pattern.compile(compiler)
        # []
        matcher._block.compile(compiler)
        # [retval]

        code = compiler.makeCode()
        self.matchers.append(code)

    @elidable_promote()
    def lookupMethod(self, atom):
        return self.methods.get(atom, None)

@autohelp
@withMaker
class Script(Expr):

    _immutable_ = True

    _immutable_fields_ = "_methods[*]", "_matchers[*]"

    def __init__(self, extends, methods, matchers):
        # XXX Expansion removes 'extends' so it will always be null here.
        self._extends = extends
        self._methods = methods
        self._matchers = matchers

    @staticmethod
    def fromMonte(extends, methods, matchers):
        return Script.fromAST(extends, Tuple(unwrapList(methods)),
                              Tuple(unwrapList(matchers)))

    @staticmethod
    def fromAST(extends, methods, matchers):
        extends = nullToNone(extends)
        methods = tupleToList(methods)
        for method in methods:
            if not isinstance(method, Method):
                raise InvalidAST("Script method isn't a Method")
        if matchers is Null:
            matchers = []
        else:
            matchers = tupleToList(matchers)
        for matcher in matchers:
            if not isinstance(matcher, Matcher):
                raise InvalidAST("Script matcher isn't a Matcher")

        return Script(extends, methods, matchers)

    def uncall(self):
        return ConstList([NullObject, ConstList(self._methods),
                          ConstList(self._matchers)])

    def pretty(self, out):
        for method in self._methods:
            method.pretty(out)
        for matcher in self._matchers:
            matcher.pretty(out)

    def transform(self, f):
        methods = [method.transform(f) for method in self._methods]
        return f(Script(self._extends, methods, self._matchers))

    def getStaticScope(self):
        scope = emptyScope
        for expr in self._methods:
            scope = scope.add(expr.getStaticScope())
        for expr in self._matchers:
            scope = scope.add(expr.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETMETHODNAMED_2:
            name = unwrapStr(args[0])
            for method in self._methods:
                assert isinstance(method, Method), "Method wasn't a method!?"
                if method._verb == name:
                    return method
            ej = args[1]
            throw(ej, StrObject(u"No method named %s" % name))

        if atom is GETNODENAME_0:
            return StrObject(u"ScriptExpr")

        if atom is GETMETHODS_0:
            return ConstList(self._methods)

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Sequence(Expr):

    _immutable_ = True

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

    @staticmethod
    def fromAST(t):
        return Sequence(tupleToList(t))

    def uncall(self):
        return ConstList([ConstList(self._l)])

    def pretty(self, out):
        if not self._l:
            return

        init = self._l[:-1]
        last = self._l[-1]
        for item in init:
            item.pretty(out)
            out.writeLine("")
        last.pretty(out)

    def transform(self, f):
        return f(Sequence([node.transform(f) for node in self._l]))

    def compile(self, compiler):
        if self._l:
            for node in self._l[:-1]:
                node.compile(compiler)
                compiler.addInstruction("POP", 0)
            self._l[-1].compile(compiler)
        else:
            # If the sequence is empty, then it evaluates to null.
            compiler.literal(NullObject)

    def getStaticScope(self):
        scope = emptyScope
        for expr in self._l:
            scope = scope.add(expr.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"SeqExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        if atom is GETEXPRS_0:
            return ConstList(self._l)

        return Expr.recv(self, atom, args)


@autohelp
@withMaker
class Try(Expr):

    _immutable_ = True

    def __init__(self, first, pattern, then):
        self._first = first
        self._pattern = pattern
        self._then = then

    def uncall(self):
        return ConstList([self._first, self._pattern, self._then])

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

    def transform(self, f):
        return f(Try(self._first.transform(f), self._pattern,
            self._then.transform(f)))

    def compile(self, compiler):
        index = compiler.markInstruction("TRY")
        self._first.compile(compiler.pushScope())
        end = compiler.markInstruction("END_HANDLER")
        compiler.patch(index)
        subc = compiler.pushScope()
        self._pattern.compile(subc)
        self._then.compile(subc)
        compiler.patch(end)

    def getStaticScope(self):
        scope = self._first.getStaticScope()
        catchScope = self._pattern.getStaticScope()
        catchScope = catchScope.add(self._then.getStaticScope())
        return scope.add(catchScope.hide())

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"CatchExpr")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Expr.recv(self, atom, args)


@autohelp
class Pattern(Expr):
    """
    The root of all patterns.
    """

    _immutable_ = True

    def __repr__(self):
        b = Buffer()
        self.pretty(LineWriter(b))
        return b.get()

    def repr(self):
        return self.__repr__()


@autohelp
@withMaker
class BindingPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun):
        self._noun = nounToString(noun)

    def uncall(self):
        return ConstList([Noun(self._noun)])

    def pretty(self, out):
        out.write("&&")
        out.write(self._noun.encode("utf-8"))

    def compile(self, compiler):
        index = compiler.locals.add(self._noun)
        compiler.addInstruction("POP", 0)
        compiler.addInstruction("BIND", index)

    def getStaticScope(self):
        return StaticScope([], [], [], [self._noun], False)

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"BindingPattern")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)


@autohelp
@withMaker
class FinalPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun, guard):
        self._actualNoun = noun
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def uncall(self):
        return ConstList(
            [self._actualNoun,
             self._g if self._g is not None else NullObject])

    def pretty(self, out):
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def compile(self, compiler):
        # [specimen ej]
        if self._g is None:
            index = compiler.addGlobal(u"Any")
            compiler.addInstruction("NOUN_GLOBAL", index)
            # [specimen ej guard]
        else:
            self._g.compile(compiler)
            # [specimen ej guard]
        index = compiler.locals.add(self._n)
        compiler.addInstruction("BINDFINALSLOT", index)
        # []

    def getStaticScope(self):
        scope = StaticScope([], [], [self._n], [], False)
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"FinalPattern")
        if atom is GETNOUN_0:
            return self._actualNoun
        if atom is GETGUARD_0:
            if self._g is None:
                return NullObject
            return self._g
        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)


@autohelp
@withMaker
class IgnorePattern(Pattern):

    _immutable_ = True

    def __init__(self, guard):
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("_")
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def uncall(self):
        return ConstList([self._g if self._g is not None else NullObject])

    def compile(self, compiler):
        # [specimen ej]
        if self._g is None:
            compiler.addInstruction("POP", 0)
            # [specimen]
            compiler.addInstruction("POP", 0)
            # []
        else:
            self._g.compile(compiler)
            # [specimen ej guard]
            compiler.addInstruction("ROT", 0)
            compiler.addInstruction("ROT", 0)
            # [guard specimen ej]
            compiler.call(u"coerce", 2)
            # [result]
            compiler.addInstruction("POP", 0)
            # []

    def getStaticScope(self):
        scope = emptyScope
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"IgnorePattern")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)


@autohelp
@withMaker
class ListPattern(Pattern):

    _immutable_ = True

    _immutable_fields_ = "_ps[*]",

    def __init__(self, patterns, tail):
        self._ps = patterns

    @staticmethod
    def fromMonte(patterns, tail):
        return ListPattern.fromAST(unwrapList(patterns), tail)

    @staticmethod
    def fromAST(patterns, tail):
        for p in patterns:
            if p is None:
                raise InvalidAST("List subpattern cannot be None")

        if tail is not None:
            raise InvalidAST("Kernel list patterns have no tail")
        return ListPattern(patterns, None)

    def uncall(self):
        return ConstList([ConstList(self._ps), NullObject])

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

    def compile(self, compiler):
        # [specimen ej]
        compiler.addInstruction("LIST_PATT", len(self._ps))
        for patt in self._ps:
            # [specimen ej]
            patt.compile(compiler)

    def getStaticScope(self):
        scope = emptyScope
        for patt in self._ps:
            scope = scope.add(patt.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"ListPattern")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)

@autohelp
@withMaker
class NamedParam(Pattern):

    _immutable_ = True

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
        return ConstList(
            [self._k, self._p,
             self._default if self._default is not None else NullObject])

    def getStaticScope(self):
        scope = self._k.getStaticScope().add(self._p.getStaticScope())
        if self._default is not None:
            scope = scope.add(self._default.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETKEY_0:
            return self._k

        if atom is GETPATTERN_0:
            return self._p

        if atom is GETDEFAULT_1:
            if self._default is None:
                throw(args[0], StrObject(u"Parameter has no default"))
            return self._default

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)

    def compile(self, compiler):
        # [argmap]
        compiler.addInstruction("DUP", 0)
        self._k.compile(compiler)
        # [argmap argmap0 key]
        if self._default is Null:
            compiler.addInstruction("NAMEDARG_EXTRACT", 0)
        else:
            useDefault = compiler.markInstruction("NAMEDARG_EXTRACT_OPTIONAL")
            compiler.addInstruction("POP", 0)
            self._default.compile(compiler)
            compiler.patch(useDefault)
        # [argmap specimen]
        throwIdx = compiler.addGlobal(u"throw")
        compiler.addInstruction("NOUN_GLOBAL", throwIdx)
        # [argmap specimen ej]
        self._p.compile(compiler)
        # [argmap]


@autohelp
@withMaker
class VarPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun, guard):
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def uncall(self):
        return ConstList(
            [Noun(self._n),
             self._g if self._g is not None else NullObject])

    def pretty(self, out):
        out.write("var ")
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def compile(self, compiler):
        # [specimen ej]
        if self._g is None:
            index = compiler.addGlobal(u"Any")
            compiler.addInstruction("NOUN_GLOBAL", index)
            # [specimen ej guard]
        else:
            self._g.compile(compiler)
            # [specimen ej guard]
        index = compiler.locals.add(self._n)
        compiler.addInstruction("BINDVARSLOT", index)

    def getStaticScope(self):
        scope = StaticScope([], [], [], [self._n], False)
        if self._g is not None:
            scope = scope.add(self._g.getStaticScope())
        return scope

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"VarPattern")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)


@autohelp
@withMaker
class ViaPattern(Pattern):

    _immutable_ = True

    def __init__(self, expr, pattern):
        self._expr = expr
        if pattern is None:
            raise InvalidAST("Inner pattern of via cannot be None")
        self._pattern = pattern

    def uncall(self):
        return ConstList([self._expr, self._pattern])

    def pretty(self, out):
        out.write("via (")
        self._expr.pretty(out)
        out.write(") ")
        self._pattern.pretty(out)

    def compile(self, compiler):
        # [specimen ej]
        compiler.addInstruction("DUP", 0)
        # [specimen ej ej]
        compiler.addInstruction("ROT", 0)
        # [ej ej specimen]
        compiler.addInstruction("SWAP", 0)
        # [ej specimen ej]
        self._expr.compile(compiler)
        # [ej specimen ej examiner]
        compiler.addInstruction("ROT", 0)
        compiler.addInstruction("ROT", 0)
        # [ej examiner specimen ej]
        compiler.call(u"run", 2)
        # [ej specimen]
        compiler.addInstruction("SWAP", 0)
        # [specimen ej]
        self._pattern.compile(compiler)

    def getStaticScope(self):
        return self._expr.getStaticScope().add(self._pattern.getStaticScope())

    def recv(self, atom, args):
        if atom is GETNODENAME_0:
            return StrObject(u"ViaPattern")

        if atom is GETSTATICSCOPE_0:
            return self.getStaticScope()

        return Pattern.recv(self, atom, args)


def formatName(p):
    if isinstance(p, FinalPattern):
        return p._n
    return u"_"
