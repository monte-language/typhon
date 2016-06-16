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
from rpython.rlib.jit import elidable, unroll_safe
from rpython.rlib.listsort import make_timsort_class
from rpython.rlib.objectmodel import specialize
from rpython.rlib.rbigint import BASE10

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.enum import makeEnum
from typhon.errors import LoadFailed, WrongType, userError
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.constants import NullObject
from typhon.objects.collections.helpers import asSet
from typhon.objects.collections.lists import unwrapList, wrapList
from typhon.objects.collections.maps import EMPTY_MAP, monteMap
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject, promoteToBigInt, unwrapStr)
from typhon.objects.ejectors import throw
from typhon.objects.meta import MetaContext
from typhon.objects.root import Object, audited
from typhon.pretty import Buffer, LineWriter
from typhon.quoting import quoteChar, quoteStr
from typhon.smallcaps.code import Code, CodeScript
from typhon.smallcaps.ops import ops
from typhon.smallcaps.peephole import peephole
from typhon.smallcaps.slots import SlotType, binding, finalAny, varAny


def lt0(a, b):
    return a[0] < b[0]

TimSort0 = make_timsort_class(lt=lt0)


DEPTH_NOUN, DEPTH_SLOT, DEPTH_BINDING = makeEnum(u"extent",
    u"noun slot binding".split())

def deepen(old, new):
    if old is DEPTH_BINDING or new is DEPTH_BINDING:
        return DEPTH_BINDING
    if old is DEPTH_SLOT or new is DEPTH_SLOT:
        return DEPTH_SLOT
    return DEPTH_NOUN

depthMap = {
    "ASSIGN": DEPTH_NOUN,
    "BINDING": DEPTH_BINDING,
    "NOUN": DEPTH_NOUN,
}

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

    def add(self, name, slotType):
        i = self.getOffset()
        if name in self.map:
            raise InvalidAST(name.encode("utf-8") +
                             " is already defined in this scope")
        # print "Adding", name, "at slot", i, "and depth", depth.repr
        self.map[name] = i, slotType
        return i

    def find(self, name, newDepth):
        i, slotType = self.map.get(name, (-1, None))
        if i == -1:
            if self.parent is not None:
                return self.parent.find(name, newDepth)
            # Not found.
            return -1
        if newDepth is DEPTH_BINDING:
            # print "Reifying binding for", name, "at slot", i
            slotType = slotType.withReifiedBinding()
            self.map[name] = i, slotType
        elif newDepth is DEPTH_SLOT:
            # print "Reifying slot for", name, "at slot", i
            slotType = slotType.withReifiedSlot()
            self.map[name] = i, slotType
        return i

    def escaping(self, name):
        i, slotType = self.map.get(name, (-1, None))
        if i == -1:
            # And what if the parent is None? Then it implies that the slot
            # type is some sort of global binding, which is already as
            # reified/deoptimized as it can get. ~ C.
            if self.parent is not None:
                self.parent.escaping(name)
        else:
            slotType = slotType.escaping()
            self.map[name] = i, slotType

    def _nameList(self):
        names = [(i, k, d) for k, (i, d) in self.map.items()]
        for ch in self.children:
            names.extend(ch._nameList())
        return names

    def nameList(self):
        names = self._nameList()
        TimSort0(names).sort()
        l = []
        for index, (i, k, d) in enumerate(names):
            # This invariant was established by the sort routine above.
            assert index == i
            l.append((k, d))
        return l

    def nameMap(self):
        d = {}
        for k, (v, _) in self.map.iteritems():
            d[k] = v
        return d


class Compiler(object):

    # The number of checkpoints that we've incurred in this frame.
    checkpoints = 0

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

    def makeCode(self, startingDepth=0):
        atoms = self.atoms.keys()
        frame = self.frame.keys()
        literals = self.literals.keys()
        globals = self.globals.keys()
        locals = self.locals.nameList()
        scripts = [(script.freeze(), cs, gs)
                   for (script, cs, gs) in self.scripts]

        code = Code(self.fqn, self.methodName, self.instructions, atoms,
                    literals, globals, frame, locals, scripts, startingDepth)
        code.checkpoints = self.checkpoints

        # Register the code for profiling.
        rvmprof.register_code(code, lambda code: code.profileName)

        # Run optimizations on code, including inner code.
        peephole(code)
        return code

    def canCloseOver(self, name):
        return name in self.frame or name in self.availableClosure

    @specialize.call_location()
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

    def addScript(self, script, closureLabels, globalLabels):
        index = len(self.scripts)
        self.scripts.append((script, closureLabels, globalLabels))
        return index

    def chooseFrame(self, name, accessType):
        """
        Choose which frame type and index a name should have.

        If this is the first use of this name in the current frame, then a new
        frame location will be chosen for the name.
        """

        # It's unknown yet whether the assignment is to a local slot or an
        # (outer) frame slot, or even to a global frame slot. Check to see
        # whether the name is already known to be local; if not, then it must
        # be in the outer frame. Unless it's not in there, in which case it
        # must be global.
        localIndex = self.locals.find(name, depthMap[accessType])
        if localIndex >= 0:
            return "LOCAL", localIndex
        elif self.canCloseOver(name):
            index = self.addFrame(name)
            return "FRAME", index
        else:
            index = self.addGlobal(name)
            return "GLOBAL", index

    @specialize.arg(2)
    def accessFrame(self, name, accessType):
        """
        Interact with the frame.
        """

        frameType, frameIndex = self.chooseFrame(name, accessType)
        self.addInstruction("%s_%s" % (accessType, frameType), frameIndex)

    def literal(self, literal):
        index = self.addLiteral(literal)
        self.addInstruction("LITERAL", index)

    def call(self, verb, arity):
        # Checkpoint before the call.
        self.checkpoints += 1
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
    return compiler.makeCode(), compiler.locals.nameMap()


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
        # XXX bad eject
        ej.call(u"run", [StrObject(u"Not a KernelAst node")])

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

    def compile(self, compiler):
        compiler.literal(NullObject)

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

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

    def compile(self, compiler):
        try:
            compiler.literal(IntObject(self.bi.toint()))
        except OverflowError:
            compiler.literal(BigInt(self.bi))

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


@autohelp
class Str(Expr):

    def __init__(self, s):
        self._s = s

    nodeMaker = makeLiteral

    def uncall(self):
        return wrapList([StrObject(self._s)])

    def pretty(self, out):
        out.write(quoteStr(self._s).encode("utf-8"))

    def compile(self, compiler):
        compiler.literal(StrObject(self._s))

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Str")
    def getValue(self):
        return self._s


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

    def compile(self, compiler):
        compiler.literal(DoubleObject(self._d))

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Double")
    def getValue(self):
        return self._d


@autohelp
class Char(Expr):

    def __init__(self, c):
        self._c = c

    nodeMaker = makeLiteral

    def uncall(self):
        return wrapList([CharObject(self._c)])

    def pretty(self, out):
        out.write(quoteChar(self._c[0]).encode("utf-8"))

    def compile(self, compiler):
        compiler.literal(CharObject(self._c))

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"LiteralExpr"

    @method("Char")
    def getValue(self):
        return self._c


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

    def compile(self, compiler):
        self.rvalue.compile(compiler)
        # [rvalue]
        compiler.addInstruction("DUP", 0)
        # [rvalue rvalue]
        compiler.accessFrame(self.target, "ASSIGN")
        # [rvalue]

    @method.py("Any")
    def getStaticScope(self):
        scope = StaticScope([], [self.target], [], [], False)
        scope = scope.add(self.rvalue.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"change"


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

    def compile(self, compiler):
        compiler.accessFrame(self.name, "BINDING")
        # [binding]

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

    @method.py("Any")
    def getStaticScope(self):
        scope = self._block.getStaticScope().hide()
        scope = scope.add(self._atLast.getStaticScope().hide())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"FinallyExpr"


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

    def compile(self, compiler):
        self._inner.compile(compiler.pushScope())

    @method.py("Any")
    def getStaticScope(self):
        return self._inner.getStaticScope().hide()

    @method("Str")
    def getNodeName(self):
        return u"HideExpr"


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

    @method.py("Any")
    def getStaticScope(self):
        scope = self._test.getStaticScope()
        scope = scope.add(self._then.getStaticScope().hide())
        scope = scope.add(self._otherwise.getStaticScope().hide())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"IfExpr"


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


@autohelp
@withMaker
class MetaContextExpr(Expr):

    def uncall(self):
        return wrapList([])

    def pretty(self, out):
        out.write("meta.context()")

    def compile(self, compiler):
        compiler.literal(MetaContext())

    @method.py("Any")
    def getStaticScope(self):
        return emptyScope

    @method("Str")
    def getNodeName(self):
        return u"MetaContextExpr"


@autohelp
@withMaker
class MetaStateExpr(Expr):

    def pretty(self, out):
        out.write("meta.getState()")

    def uncall(self):
        return wrapList([])

    def compile(self, compiler):
        # XXX should this produce outers + locals when outside an object expr?
        for k, v in compiler.frame.iteritems():
            compiler.literal(StrObject(k))
            compiler.addInstruction("BINDING_FRAME", v)
        compiler.addInstruction("BUILD_MAP", len(compiler.frame))

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([], [], [], [], True)

    @method("Str")
    def getNodeName(self):
        return u"MetaStateExpr"


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
             wrapList(self._ps), wrapList(self._namedParams), self._g,
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
        return u"MethodExpr"

    def getAtom(self):
        return getAtom(self._verb, len(self._ps))

    @method("List")
    def getPatterns(self):
        return self._ps

    @method("List")
    def getNamedPatterns(self):
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

    def compile(self, compiler):
        compiler.accessFrame(self.name, "NOUN")

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([self.name], [], [], [], False)

    @method("Str")
    def getNodeName(self):
        return u"NounExpr"

    @method("Str")
    def getName(self):
        return self.name


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

    def compile(self, compiler):
        # Create a code object for this object.
        availableClosure = compiler.frame.copy()
        availableClosure.update(compiler.locals.nameMap())
        numAuditors = len(self._implements) + 1
        oname = formatName(self._n)
        fqn = compiler.fqn + u"$" + oname
        codeScript = CompilingScript(oname, self, numAuditors,
                                     availableClosure, self._d, fqn)
        # Compile all of our script pieces.
        codeScript.addScript(self._script, fqn)
        # And now tally up and prepare our closure and globals.
        closureLabels = []
        for name in codeScript.closureNames:
            if name == codeScript.displayName:
                closureLabels.append((None, -1))
            else:
                closureLabels.append(compiler.chooseFrame(name, "BINDING"))
                compiler.locals.escaping(name)

        globalLabels = []
        for name in codeScript.globalNames:
            globalLabels.append(compiler.chooseFrame(name, "BINDING"))
            compiler.locals.escaping(name)

        subc = compiler.pushScope()
        if self._as is None:
            index = compiler.addGlobal(u"null")
            compiler.addInstruction("NOUN_GLOBAL", index)
        else:
            self._as.compile(subc)
        for stamp in self._implements:
            stamp.compile(subc)
        index = compiler.addScript(codeScript, closureLabels, globalLabels)
        compiler.addInstruction("BINDOBJECT", index)
        # [obj obj ej auditor]
        if isinstance(self._n, IgnorePattern):
            compiler.addInstruction("POP", 0)
            compiler.addInstruction("POP", 0)
            compiler.addInstruction("POP", 0)
        elif isinstance(self._n, FinalPattern):
            # XXX we could support more general guarding here.
            slotIndex = compiler.locals.add(self._n._n, SlotType(binding, False))
            compiler.addInstruction("BINDFINALSLOT", slotIndex)
        else:
            # Bail!?
            assert False, "Shouldn't happen"

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


class CompilingScript(object):

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

    def freeze(self):
        return CodeScript(self.displayName, self.objectAst, self.numAuditors,
                          self.doc, self.fqn, self.methods, self.methodDocs,
                          self.matchers[:], self.closureNames,
                          self.globalNames)

    def addScript(self, script, fqn):
        assert isinstance(script, Script)
        for meth in script._methods:
            assert isinstance(meth, Method)
            self.addMethod(meth, fqn)
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
            # Zero stack effect; they all extract from the map and assign to
            # the environment.
            np.compile(compiler)
        # [... specimen1 ej1 specimen0 ej0 namedArgs]
        compiler.addInstruction("POP", 0)
        # [... specimen1 ej1 specimen0 ej0]
        for param in method._ps:
            # [... specimen1 ej1]
            param.compile(compiler)
            # []
        method._b.compile(compiler)
        # [retval]
        if method._g is not None:
            # [retval]
            method._g.compile(compiler)
            # [retval guard]
            compiler.addInstruction("SWAP", 0)
            # [guard retval]
            compiler.literal(NullObject)
            # [guard retval null]
            compiler.call(u"coerce", 2)
            # [coerced]

        # The starting depth is two (specimen and ejector) for each param, as
        # well as one for the named map, which is unconditionally passed.
        code = compiler.makeCode(startingDepth=arity * 2 + 1)
        atom = method.getAtom()
        self.methods[atom] = code
        if method._d is not None:
            self.methodDocs[atom] = method._d

    def addMatcher(self, matcher, fqn):
        compiler = Compiler(self.closureNames, self.globalNames,
                            self.availableClosure, fqn=fqn,
                            methodName=u"<matcher>")
        # [message ej]
        matcher._pattern.compile(compiler)
        # []
        matcher._block.compile(compiler)
        # [retval]

        code = compiler.makeCode(startingDepth=2)
        self.matchers.append(code)

@autohelp
@withMaker
class Script(Expr):

    _immutable_fields_ = "_methods[*]", "_matchers[*]"

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
    def getStaticScope(self):
        scope = emptyScope
        for expr in self._methods:
            scope = scope.add(expr.getStaticScope())
        for expr in self._matchers:
            scope = scope.add(expr.getStaticScope())
        return scope

    @method("Str")
    def getNodeName(self):
        return u"ScriptExpr"

    @method("List")
    def getMethods(self):
        return self._methods

    @method("List", "Any")
    def getCompleteMatcher(self, ej):
        if self._matchers:
            matcher = self._matchers[-1]
            if isinstance(matcher, Matcher):
                pattern = matcher._pattern
                if pattern.refutable():
                    throw(ej, StrObject(u"getCompleteMatcher/1: Ultimate matcher pattern is refutable"))
                return [pattern, matcher._block]
        throw(ej, StrObject(u"getCompleteMatcher/1: No matchers"))

    @method("Any", "Str", "Any")
    def getMethodNamed(self, name, ej):
        for meth in self._methods:
            assert isinstance(meth, Method), "Method wasn't a method!?"
            if meth._verb == name:
                return meth
        throw(ej, StrObject(u"getMethodNamed/2: No method named %s" % name))


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

    def compile(self, compiler):
        if self._l:
            for node in self._l[:-1]:
                node.compile(compiler)
                compiler.addInstruction("POP", 0)
            self._l[-1].compile(compiler)
        else:
            # If the sequence is empty, then it evaluates to null.
            compiler.literal(NullObject)

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

    def compile(self, compiler):
        index = compiler.markInstruction("TRY")
        self._first.compile(compiler.pushScope())
        end = compiler.markInstruction("END_HANDLER")
        compiler.patch(index)
        subc = compiler.pushScope()
        # [problem ej]
        self._pattern.compile(subc)
        # []
        self._then.compile(subc)
        compiler.patch(end)

    @method.py("Any")
    def getStaticScope(self):
        scope = self._first.getStaticScope()
        catchScope = self._pattern.getStaticScope()
        catchScope = catchScope.add(self._then.getStaticScope())
        return scope.add(catchScope.hide())

    @method("Str")
    def getNodeName(self):
        return u"CatchExpr"


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

    def compile(self, compiler):
        index = compiler.locals.add(self._noun, SlotType(binding, False))
        compiler.addInstruction("POP", 0)
        compiler.addInstruction("BIND", index)

    @method.py("Any")
    def getStaticScope(self):
        return StaticScope([], [], [], [self._noun], False)

    @method.py("Bool")
    def refutable(self):
        return False

    @method("Str")
    def getNodeName(self):
        return u"BindingPattern"


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

    def compile(self, compiler):
        slotType = SlotType(finalAny, False)
        # [specimen ej]
        if self._g is None:
            compiler.addInstruction("POP", 0)
            # [specimen]
            index = compiler.locals.add(self._n, slotType)
            compiler.addInstruction("BINDANYFINAL", index)
            # []
        else:
            slotType = slotType.guarded()
            self._g.compile(compiler)
            # [specimen ej guard]
            index = compiler.locals.add(self._n, slotType)
            compiler.addInstruction("BINDFINALSLOT", index)
            # []
        # []

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

    def compile(self, compiler):
        # [specimen ej]
        compiler.addInstruction("LIST_PATT", len(self._ps))
        for patt in self._ps:
            # [specimen ej]
            patt.compile(compiler)

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
            throw(ej, StrObject(u"Parameter has no default"))
        return self._default

    def compile(self, compiler):
        # [argmap]
        compiler.addInstruction("DUP", 0)
        # [argmap argmap]
        self._k.compile(compiler)
        # [argmap argmap key]
        if self._default is Null:
            compiler.addInstruction("NAMEDARG_EXTRACT", 0)
            # [argmap value]
        else:
            useDefault = compiler.markInstruction("NAMEDARG_EXTRACT_OPTIONAL")
            # [argmap null]
            compiler.addInstruction("POP", 0)
            # [argmap]
            self._default.compile(compiler)
            # [argmap default]
            compiler.patch(useDefault)
        # [argmap specimen]
        compiler.literal(NullObject)
        # [argmap specimen ej]
        self._p.compile(compiler)
        # [argmap]


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

    def compile(self, compiler):
        slotType = SlotType(varAny, False)
        # [specimen ej]
        if self._g is None:
            compiler.addInstruction("POP", 0)
            # [specimen]
            index = compiler.locals.add(self._n, slotType)
            compiler.addInstruction("BINDANYVAR", index)
            # []
        else:
            slotType = slotType.guarded()
            self._g.compile(compiler)
            # [specimen ej guard]
            index = compiler.locals.add(self._n, slotType)
            compiler.addInstruction("BINDVARSLOT", index)
            # []
        # []

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

    @method.py("Any")
    def getStaticScope(self):
        return self._expr.getStaticScope().add(self._pattern.getStaticScope())

    @method.py("Bool")
    def refutable(self):
        return True

    @method("Str")
    def getNodeName(self):
        return u"ViaPattern"


def formatName(p):
    if isinstance(p, FinalPattern):
        return p._n
    return u"_"
