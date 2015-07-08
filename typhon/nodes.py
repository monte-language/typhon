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

from collections import OrderedDict

from rpython.rlib.jit import elidable, elidable_promote
from rpython.rlib.rbigint import BASE10

from typhon.atoms import getAtom
from typhon.errors import LoadFailed
from typhon.objects.constants import NullObject
from typhon.objects.collections import ConstList
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.meta import MetaContext
from typhon.objects.user import ScriptObject
from typhon.pretty import Buffer, LineWriter
from typhon.smallcaps.code import Code
from typhon.smallcaps.ops import ops
from typhon.smallcaps.peephole import peephole


class Compiler(object):

    def __init__(self, initialFrame=None, initialGlobals=None,
                 availableClosure=None, fqn=u""):
        self.fqn = fqn
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
        self.locals = OrderedDict()
        self.scripts = []

    def makeCode(self):
        atoms = self.atoms.keys()
        frame = self.frame.keys()
        literals = self.literals.keys()
        globals = self.globals.keys()
        locals = self.locals.keys()

        code = Code(self.instructions, atoms, literals, globals, frame,
                    locals, self.scripts)
        # Run optimizations on code, including inner code.
        peephole(code)
        return code

    def canCloseOver(self, name):
        return name in self.frame or name in self.availableClosure

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

    def addLocal(self, name):
        if name not in self.locals:
            self.locals[name] = len(self.locals)
        return self.locals[name]

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


class InvalidAST(LoadFailed):
    """
    An AST was ill-formed.
    """


class Node(object):

    _immutable_ = True
    _attrs_ = "monteAST",

    monteAST = None

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

    def rewriteScope(self, scope):
        """
        Rewrite the scope definitions by altering names.
        """

        return self

    def usesName(self, name):
        """
        Whether a name is used within this node.
        """

        return False


class _Null(Node):

    _immutable_ = True
    _attrs_ = ()

    def pretty(self, out):
        out.write("null")

    def compile(self, compiler):
        compiler.literal(NullObject)

    def slowTransform(self, o):
        return NullObject


Null = _Null()


def nullToNone(node):
    return None if node is Null else node


class Int(Node):

    _immutable_ = True

    def __init__(self, bi):
        self.bi = bi

    def pretty(self, out):
        out.write(self.bi.format(BASE10))

    def compile(self, compiler):
        try:
            compiler.literal(IntObject(self.bi.toint()))
        except OverflowError:
            compiler.literal(BigInt(self.bi))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"LiteralExpr"),
                               IntObject(self.bi.toint())])


class Str(Node):

    _immutable_ = True

    def __init__(self, s):
        self._s = s

    def pretty(self, out):
        out.write('"%s"' % (self._s.encode("utf-8")))

    def compile(self, compiler):
        compiler.literal(StrObject(self._s))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"LiteralExpr"), StrObject(self._s)])


def strToString(s):
    if not isinstance(s, Str):
        raise InvalidAST("not a Str!")
    return s._s


class Double(Node):

    _immutable_ = True

    def __init__(self, d):
        self._d = d

    def pretty(self, out):
        out.write("%f" % self._d)

    def compile(self, compiler):
        compiler.literal(DoubleObject(self._d))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"LiteralExpr"),
                               DoubleObject(self._d)])


class Char(Node):

    _immutable_ = True

    def __init__(self, c):
        self._c = c

    def pretty(self, out):
        out.write("'%s'" % (self._c.encode("utf-8")))

    def compile(self, compiler):
        compiler.literal(CharObject(self._c))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"LiteralExpr"),
                               CharObject(self._c)])

class Tuple(Node):

    _immutable_ = True

    _immutable_fields_ = "_t[*]",

    def __init__(self, t):
        self._t = t

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

    def slowTransform(self, o):
        return ConstList([node.slowTransform(o) for node in self._t])

    def rewriteScope(self, scope):
        return Tuple([node.rewriteScope(scope) for node in self._t])

    def usesName(self, name):
        uses = False
        for node in self._t:
            if node.usesName(name):
                uses = True
        return uses

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


def tupleToList(t):
    if not isinstance(t, Tuple):
        raise InvalidAST("not a Tuple: " + t.__repr__())
    return t._t


class Assign(Node):

    _immutable_ = True

    def __init__(self, target, rvalue):
        self.target = target
        self.rvalue = rvalue

    @staticmethod
    def fromAST(target, rvalue):
        return Assign(nounToString(target), rvalue)

    def pretty(self, out):
        out.write(self.target.encode("utf-8"))
        out.write(" := ")
        self.rvalue.pretty(out)

    def transform(self, f):
        return f(Assign(self.target, self.rvalue.transform(f)))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"AssignExpr"),
                               Noun(self.target).slowTransform(o),
                               self.rvalue.slowTransform(o)])

    def rewriteScope(self, scope):
        # Read.
        newTarget = scope.getShadow(self.target)
        if newTarget is None:
            newTarget = self.target
        self = Assign(newTarget, self.rvalue.rewriteScope(scope))
        return self

    def usesName(self, name):
        return self.rvalue.usesName(name)

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
        if self.target in compiler.locals:
            index = compiler.locals[self.target]
            compiler.addInstruction("ASSIGN_LOCAL", index)
            # [rvalue]
        elif compiler.canCloseOver(self.target):
            index = compiler.addFrame(self.target)
            compiler.addInstruction("ASSIGN_FRAME", index)
            # [rvalue]
        else:
            index = compiler.addGlobal(self.target)
            compiler.addInstruction("ASSIGN_GLOBAL", index)
            # [rvalue]


class Binding(Node):

    _immutable_ = True

    def __init__(self, name):
        self.name = name

    @staticmethod
    def fromAST(noun):
        return Binding(nounToString(noun))

    def pretty(self, out):
        out.write("&&")
        out.write(self.name.encode("utf-8"))

    def transform(self, f):
        return f(self)

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"BindingExpr"),
                               Noun(self.name).slowTransform(o)])

    def rewriteScope(self, scope):
        # Read.
        newName = scope.getShadow(self.name)
        if newName is not None:
            self = Binding(newName)
        return self

    def compile(self, compiler):
        if self.name in compiler.locals:
            index = compiler.addLocal(self.name)
            compiler.addInstruction("BINDING_LOCAL", index)
            # [binding]
        elif compiler.canCloseOver(self.name):
            index = compiler.addFrame(self.name)
            compiler.addInstruction("BINDING_FRAME", index)
            # [binding]
        else:
            index = compiler.addGlobal(self.name)
            compiler.addInstruction("BINDING_GLOBAL", index)
            # [binding]


class Call(Node):

    _immutable_ = True

    def __init__(self, target, verb, args):
        self._target = target
        self._verb = verb
        assert isinstance(args, Tuple), "XXX should be fromAST instead"
        self._args = args

    @staticmethod
    def fromAST(target, verb, args):
        return Call(target, strToString(verb), args)

    def pretty(self, out):
        self._target.pretty(out)
        out.write(".")
        out.write(self._verb.encode("utf-8"))
        out.write("(")
        l = self._args._t
        if l:
            head = l[0]
            tail = l[1:]
            head.pretty(out)
            for item in tail:
                out.write(", ")
                item.pretty(out)
        out.write(")")

    def transform(self, f):
        return f(Call(self._target.transform(f), self._verb,
                      self._args.transform(f)))

    def slowTransform(self, o):
        return o.call(u"run",
                      [StrObject(u"MethodCallExpr"),
                       self._target.slowTransform(o),
                       StrObject(self._verb),
                       self._args.slowTransform(o)])

    def rewriteScope(self, scope):
        return Call(self._target.rewriteScope(scope), self._verb,
                    self._args.rewriteScope(scope))

    def usesName(self, name):
        return self._target.usesName(name) or self._args.usesName(name)

    def compile(self, compiler):
        self._target.compile(compiler)
        # [target]
        args = tupleToList(self._args)
        arity = len(args)
        for node in args:
            node.compile(compiler)
            # [target x0 x1 ...]
        compiler.call(self._verb, arity)
        # [retval]

class Def(Node):

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

    def slowTransform(self, o):
        return o.call(
            u"run",
            [StrObject(u"DefExpr"), self._p.slowTransform(o),
             (NullObject if self._e is None
              else self._e.slowTransform(o)),
             self._v.slowTransform(o)])

    def rewriteScope(self, scope):
        # Delegate to patterns.
        p = self._p.rewriteScope(scope)
        if self._e is None:
            e = None
        else:
            e = self._e.rewriteScope(scope)
        return Def(p, e, self._v.rewriteScope(scope))

    def usesName(self, name):
        rv = self._v.usesName(name)
        if self._e is not None:
            rv = rv or self._e.usesName(name)
        return rv

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


class Escape(Node):

    _immutable_ = True

    def __init__(self, pattern, node, catchPattern, catchNode):
        self._pattern = pattern
        self._node = node
        self._catchPattern = catchPattern
        self._catchNode = nullToNone(catchNode)

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

    def slowTransform(self, o):
        return o.call(u"run",
                      [StrObject(u"EscapeExpr"),
                       self._pattern.slowTransform(o),
                       self._node.slowTransform(o),
                       (NullObject if self._catchPattern is None
                        else self._catchPattern.slowTransform(o)),
                       (NullObject if self._catchNode is None
                        else self._catchNode.slowTransform(o))])

    def rewriteScope(self, scope):
        with scope:
            p = self._pattern.rewriteScope(scope)
            n = self._node.rewriteScope(scope)

        with scope:
            if self._catchPattern is None:
                cp = None
            else:
                cp = self._catchPattern.rewriteScope(scope)
            if self._catchNode is None:
                cn = None
            else:
                cn = self._catchNode.rewriteScope(scope)

        rv = Escape(p, n, cp, cn)
        return rv

    def usesName(self, name):
        rv = self._node.usesName(name)
        if self._catchNode is not None:
            rv = rv or self._catchNode.usesName(name)
        return rv

    def compile(self, compiler):
        ejector = compiler.markInstruction("EJECTOR")
        # [ej]
        compiler.literal(NullObject)
        # [ej null]
        self._pattern.compile(compiler)
        # []
        self._node.compile(compiler)
        # [retval]

        if self._catchNode is not None:
            jump = compiler.markInstruction("JUMP")

            # Control is resumed here by the ejector in case of ejection.
            compiler.patch(ejector)
            # [retval]
            compiler.literal(NullObject)
            # [retval null]
            self._catchPattern.compile(compiler)
            # []
            self._catchNode.compile(compiler)
            # [retval]
            compiler.patch(jump)
        else:
            compiler.patch(ejector)


class Finally(Node):

    _immutable_ = True

    def __init__(self, block, atLast):
        self._block = block
        self._atLast = atLast

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

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"FinallyExpr"),
                               self._block.slowTransform(o),
                               self._atLast.slowTransform(o)])

    def rewriteScope(self, scope):
        with scope:
            block = self._block.rewriteScope(scope)

        with scope:
            atLast = self._atLast.rewriteScope(scope)

        rv = Finally(block, atLast)
        return rv

    def usesName(self, name):
        return self._block.usesName(name) or self._atLast.usesName(name)

    def compile(self, compiler):
        unwind = compiler.markInstruction("UNWIND")
        self._block.compile(compiler)
        handler = compiler.markInstruction("END_HANDLER")
        compiler.patch(unwind)
        self._atLast.compile(compiler)
        compiler.addInstruction("POP", 0)
        dropper = compiler.markInstruction("END_HANDLER")
        compiler.patch(handler)
        compiler.patch(dropper)


class Hide(Node):

    _immutable_ = True

    def __init__(self, inner):
        self._inner = inner

    def pretty(self, out):
        out.writeLine("hide {")
        self._inner.pretty(out.indent())
        out.writeLine("}")

    def transform(self, f):
        return f(Hide(self._inner.transform(f)))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"HideExpr"),
                               self._inner.slowTransform(o)])

    def rewriteScope(self, scope):
        with scope:
            rv = Hide(self._inner.rewriteScope(scope))

        return rv

    def usesName(self, name):
        # XXX not technically correct due to Hide intentionally altering
        # scope resolution.
        return self._inner.usesName(name)

    def compile(self, compiler):
        self._inner.compile(compiler)


class If(Node):

    _immutable_ = True

    def __init__(self, test, then, otherwise):
        self._test = test
        self._then = then
        self._otherwise = otherwise

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

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"IfExpr"),
                               self._test.slowTransform(o),
                               self._then.slowTransform(o),
                               self._otherwise.slowTransform(o)])

    def rewriteScope(self, scope):
        with scope:
            rv = If(self._test.rewriteScope(scope),
                    self._then.rewriteScope(scope),
                    self._otherwise.rewriteScope(scope))

        return rv

    def usesName(self, name):
        rv = self._test.usesName(name) or self._then.usesName(name)
        return rv or self._otherwise.usesName(name)

    def compile(self, compiler):
        # BRANCH otherwise
        # ...
        # JUMP end
        # otherwise: ...
        # end: ...
        self._test.compile(compiler)
        # [condition]
        branch = compiler.markInstruction("BRANCH")
        self._then.compile(compiler)
        jump = compiler.markInstruction("JUMP")
        compiler.patch(branch)
        self._otherwise.compile(compiler)
        compiler.patch(jump)


class Matcher(Node):

    _immutable_ = True

    def __init__(self, pattern, block):
        if pattern is None:
            raise InvalidAST("Matcher pattern cannot be None")

        self._pattern = pattern
        self._block = block

    def pretty(self, out):
        out.write("match ")
        self._pattern.pretty(out)
        out.writeLine(" {")
        self._block.pretty(out.indent())
        out.writeLine("}")

    def transform(self, f):
        return f(Matcher(self._pattern, self._block.transform(f)))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"Matcher"),
                               self._pattern.slowTransform(o),
                               self._block.slowTransform(o)])

    def rewriteScope(self, scope):
        with scope:
            rv = Matcher(self._pattern.rewriteScope(scope),
                         self._block.rewriteScope(scope))

        return rv


class Meta(Node):

    _immutable_ = True

    _immutable_fields_ = "nature",

    def __init__(self, nature):
        self.nature = strToString(nature)
        if self.nature != u"Context":
            raise InvalidAST("Can't handle meta: %s" %
                             self.nature.encode("utf-8"))

    def pretty(self, out):
        out.write("meta.context()")

    def compile(self, compiler):
        compiler.literal(MetaContext())

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"MetaContextExpr")])


class Method(Node):

    _immutable_ = True

    _immutable_fields_ = "_ps[*]",

    def __init__(self, doc, verb, params, guard, block):
        self._d = doc
        self._verb = verb
        self._ps = params
        self._g = guard
        self._b = block

    @staticmethod
    def fromAST(doc, verb, params, guard, block):
        for param in params:
            if param is None:
                raise InvalidAST("Parameter patterns cannot be None")
        doc = doc._s if isinstance(doc, Str) else None
        return Method(doc, strToString(verb), params, guard, block)

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
        out.write(") :")
        self._g.pretty(out)
        out.writeLine(" {")
        self._b.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    def transform(self, f):
        return f(Method(self._d, self._verb, self._ps, self._g,
                        self._b.transform(f)))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"Method"),
                               NullObject if self._d is None else StrObject(self._d),
                               StrObject(self._verb),
                               ConstList([p.slowTransform(o) for p in self._ps]),
                               NullObject if self._g is None else self._g.slowTransform(o),
                               self._b.slowTransform(o)])

    def rewriteScope(self, scope):
        with scope:
            ps = [p.rewriteScope(scope) for p in self._ps]
            rv = Method(self._d, self._verb, ps,
                        self._g.rewriteScope(scope),
                        self._b.rewriteScope(scope))

        return rv

    def usesName(self, name):
        return self._b.usesName(name)


class Noun(Node):

    _immutable_ = True
    _immutable_Fields_ = "noun",

    def __init__(self, noun):
        self.name = noun

    @staticmethod
    def fromAST(noun):
        return Noun(strToString(noun))

    def pretty(self, out):
        out.write(self.name.encode("utf-8"))

    def rewriteScope(self, scope):
        # Read.
        newName = scope.getShadow(self.name)
        if newName is not None:
            self = Noun(newName)
        return self

    def usesName(self, name):
        return self.name == name

    def compile(self, compiler):
        if self.name in compiler.locals:
            index = compiler.addLocal(self.name)
            compiler.addInstruction("NOUN_LOCAL", index)
            # print "I think", self.name, "is local"
        elif compiler.canCloseOver(self.name):
            index = compiler.addFrame(self.name)
            compiler.addInstruction("NOUN_FRAME", index)
            # print "I think", self.name, "is frame"
        else:
            index = compiler.addGlobal(self.name)
            compiler.addInstruction("NOUN_GLOBAL", index)
            # print "I think", self.name, "is global"

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"NounExpr"), StrObject(self.name)])


def nounToString(n):
    if not isinstance(n, Noun):
        raise InvalidAST("Not a Noun")
    return n.name


class Obj(Node):

    _immutable_ = True

    _immutable_fields_ = "_implements[*]",

    def __init__(self, doc, name, objectAs, implements, script):
        self._d = doc
        self._n = name
        self._as = objectAs
        self._implements = implements
        self._script = script

    @staticmethod
    def fromAST(doc, name, auditors, script):
        if not (isinstance(name, FinalPattern) or isinstance(name, IgnorePattern)):
            raise InvalidAST("Kernel object pattern must be FinalPattern or IgnorePattern")

        auditors = tupleToList(auditors)
        if not isinstance(script, Script):
            raise InvalidAST("Object's script isn't a Script")

        doc = doc._s if isinstance(doc, Str) else None

        return Obj(doc, name, nullToNone(auditors[0]), auditors[1:], script)

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

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"ObjectExpr"),
                               NullObject if self._d is None else StrObject(self._d),
                               self._n.slowTransform(o),
                               NullObject if self._as is None else self._as.slowTransform(o),
                               ConstList([im.slowTransform(o) for im in  self._implements]),
                               self._script.slowTransform(o)])

    def rewriteScope(self, scope):
        # XXX as, implements
        return Obj(self._d, self._n.rewriteScope(scope), self._as,
                   self._implements, self._script.rewriteScope(scope))

    def usesName(self, name):
        return self._script.usesName(name)

    def compile(self, compiler):
        # Create a code object for this object.
        availableClosure = compiler.frame.copy()
        availableClosure.update(compiler.locals)
        numAuditors = len(self._implements) + 1
        oname = formatName(self._n)
        fqn = compiler.fqn + u"$" + oname
        self.codeScript = CodeScript(oname, self, numAuditors, availableClosure, self._d, fqn)
        self.codeScript.addScript(self._script, fqn)
        # The local closure is first to be pushed and last to be popped.
        for name in self.codeScript.closureNames:
            if name == self.codeScript.displayName:
                # Put in a null and patch it later via UserObject.patchSelf().
                compiler.literal(NullObject)
            elif name in compiler.locals:
                index = compiler.addLocal(name)
                compiler.addInstruction("BINDING_LOCAL", index)
            elif compiler.canCloseOver(name):
                index = compiler.addFrame(name)
                compiler.addInstruction("BINDING_FRAME", index)
            else:
                index = compiler.addGlobal(name)
                compiler.addInstruction("BINDING_GLOBAL", index)

        # Globals are pushed after closure, so they'll be popped first.
        for name in self.codeScript.globalNames:
            if name in compiler.locals:
                index = compiler.addLocal(name)
                compiler.addInstruction("BINDING_LOCAL", index)
            elif compiler.canCloseOver(name):
                index = compiler.addFrame(name)
                compiler.addInstruction("BINDING_FRAME", index)
            else:
                index = compiler.addGlobal(name)
                compiler.addInstruction("BINDING_GLOBAL", index)
        for stamp in reversed(self._implements):
            stamp.compile(compiler)
        if self._as is None:
            index = compiler.addGlobal(u"null")
            compiler.addInstruction("NOUN_GLOBAL", index)
        else:
            self._as.compile(compiler)
        index = compiler.addScript(self.codeScript)
        compiler.addInstruction("BINDOBJECT", index)
        if isinstance(self._n, IgnorePattern):
            compiler.addInstruction("POP", 0)
            compiler.addInstruction("POP", 0)
            compiler.addInstruction("POP", 0)
        elif isinstance(self._n, FinalPattern):
            slotIndex = compiler.addLocal(self._n._n)
            compiler.addInstruction("BINDFINALSLOT", slotIndex)


class CodeScript(object):

    _immutable_fields_ = ("displayName", "objectAst", "numAuditors", "closureNames",
                          "globalNames")

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

    def makeObject(self, closure, globals, auditors):
        obj = ScriptObject(self, globals, self.globalNames, closure,
                           self.closureNames, self.displayName, auditors, self.fqn)
        return obj

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
                            self.availableClosure, fqn=fqn)
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
        compiler = Compiler(self.closureNames, self.globalNames, fqn=fqn)
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


class Script(Node):

    _immutable_ = True

    _immutable_fields_ = "_methods[*]", "_matchers[*]"

    def __init__(self, extends, methods, matchers):
        # XXX Expansion removes 'extends' so it will always be null here.
        self._extends = extends
        self._methods = methods
        self._matchers = matchers

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

    def pretty(self, out):
        for method in self._methods:
            method.pretty(out)
        for matcher in self._matchers:
            matcher.pretty(out)

    def transform(self, f):
        methods = [method.transform(f) for method in self._methods]
        return f(Script(self._extends, methods, self._matchers))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"Script"),
                               NullObject,
                               ConstList([method.slowTransform(o)
                                          for method in self._methods]),
                               ConstList([method.slowTransform(o)
                                          for method in self._methods])])

    def rewriteScope(self, scope):
        methods = [m.rewriteScope(scope) for m in self._methods]
        matchers = [m.rewriteScope(scope) for m in self._matchers]
        return Script(self._extends, methods, matchers)

    def usesName(self, name):
        for method in self._methods:
            if method.usesName(name):
                return True
        for matcher in self._matchers:
            if matcher.usesName(name):
                return True
        return False


class Sequence(Node):

    _immutable_ = True

    _immutable_fields_ = "_l[*]",

    def __init__(self, l):
        self._l = l

    @staticmethod
    def fromAST(t):
        return Sequence(tupleToList(t))

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

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"SeqExpr"),
                               ConstList([node.slowTransform(o)
                                          for node in self._l])])

    def rewriteScope(self, scope):
        return Sequence([n.rewriteScope(scope) for n in self._l])

    def usesName(self, name):
        for node in self._l:
            if node.usesName(name):
                return True
        return False

    def compile(self, compiler):
        if self._l:
            for node in self._l[:-1]:
                node.compile(compiler)
                compiler.addInstruction("POP", 0)
            self._l[-1].compile(compiler)
        else:
            # If the sequence is empty, then it evaluates to null.
            compiler.literal(NullObject)


class Try(Node):

    _immutable_ = True

    def __init__(self, first, pattern, then):
        self._first = first
        self._pattern = pattern
        self._then = then

    def pretty(self, out):
        out.writeLine("try {")
        self._first.pretty(out.indent())
        out.writeLine("")
        out.write("} catch ")
        self._pattern.pretty(out)
        out.writeLine("{")
        self._then.pretty(out.indent())
        out.writeLine("")
        out.writeLine("}")

    def transform(self, f):
        return f(Try(self._first.transform(f), self._pattern,
            self._then.transform(f)))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"CatchExpr"),
                               self._first.slowTransform(o),
                               self._pattern.slowTransform(o),
                               self._then.slowTransform(o)])

    def rewriteScope(self, scope):
        with scope:
            first = self._first.rewriteScope(scope)

        with scope:
            rv = Try(first, self._pattern.rewriteScope(scope),
                     self._then.rewriteScope(scope))

        return rv

    def usesName(self, name):
        return self._first.usesName(name) or self._then.usesName(name)

    def compile(self, compiler):
        index = compiler.markInstruction("TRY")
        self._first.compile(compiler)
        end = compiler.markInstruction("END_HANDLER")
        compiler.patch(index)
        self._pattern.compile(compiler)
        self._then.compile(compiler)
        compiler.patch(end)


class Pattern(object):

    _immutable_ = True

    def __repr__(self):
        b = Buffer()
        self.pretty(LineWriter(b))
        return b.get()

    def repr(self):
        return self.__repr__()


class BindingPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun):
        self._noun = nounToString(noun)

    def pretty(self, out):
        out.write("&&")
        out.write(self._noun.encode("utf-8"))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"BindingPattern"),
                               Noun(self._noun).slowTransform(o)])

    def rewriteScope(self, scope):
        # Write.
        if scope.getSeen(self._noun) != -1:
            # Shadow.
            shadowed = scope.shadowName(self._noun)
            self = BindingPattern(Noun(shadowed))
        return self

    def compile(self, compiler):
        index = compiler.addLocal(self._noun)
        compiler.addInstruction("POP", 0)
        compiler.addInstruction("BIND", index)


class FinalPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun, guard):
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"FinalPattern"),
                               Noun(self._n).slowTransform(o),
                               (NullObject if self._g is None
                                else self._g.slowTransform(o))])

    def rewriteScope(self, scope):
        if self._g is None:
            g = None
        else:
            g = self._g.rewriteScope(scope)

        # Write.
        if scope.getSeen(self._n) != -1:
            # Shadow.
            shadowed = scope.shadowName(self._n)
            self = FinalPattern(Noun(shadowed), g)
        return self

    def compile(self, compiler):
        # [specimen ej]
        if self._g is None:
            index = compiler.addGlobal(u"Any")
            compiler.addInstruction("NOUN_GLOBAL", index)
            # [specimen ej guard]
        else:
            self._g.compile(compiler)
            # [specimen ej guard]
        index = compiler.addLocal(self._n)
        compiler.addInstruction("BINDFINALSLOT", index)
        # []


class IgnorePattern(Pattern):

    _immutable_ = True

    def __init__(self, guard):
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("_")
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def rewriteScope(self, scope):
        if self._g is None:
            return self
        return IgnorePattern(self._g.rewriteScope(scope))

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"IgnorePattern"),
                               (NullObject if self._g is None
                                else self._g.slowTransform(o))])

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


class ListPattern(Pattern):

    _immutable_ = True

    _immutable_fields_ = "_ps[*]",

    def __init__(self, patterns):
        self._ps = patterns

    @staticmethod
    def fromAST(patterns, tail):
        for p in patterns:
            if p is None:
                raise InvalidAST("List subpattern cannot be None")

        return ListPattern(patterns)

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

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"ListPattern"),
                               ConstList([item.slowTransform(o)
                                          for item in self._ps]),
                               NullObject])

    def rewriteScope(self, scope):
        ps = [p.rewriteScope(scope) for p in self._ps]
        return ListPattern(ps)

    def compile(self, compiler):
        # [specimen ej]
        compiler.addInstruction("LIST_PATT", len(self._ps))
        for patt in self._ps:
            # [specimen ej]
            patt.compile(compiler)


class VarPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun, guard):
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("var ")
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"VarPattern"),
                               Noun(self._n).slowTransform(o),
                               (NullObject if self._g is None
                                else self._g.slowTransform(o))])

    def rewriteScope(self, scope):
        if self._g is None:
            g = None
        else:
            g = self._g.rewriteScope(scope)

        # Write.
        if scope.getSeen(self._n) != -1:
            # Shadow.
            shadowed = scope.shadowName(self._n)
            self = VarPattern(Noun(shadowed), g)
        return self

    def compile(self, compiler):
        # [specimen ej]
        if self._g is None:
            index = compiler.addGlobal(u"Any")
            compiler.addInstruction("NOUN_GLOBAL", index)
            # [specimen ej guard]
        else:
            self._g.compile(compiler)
            # [specimen ej guard]
        index = compiler.addLocal(self._n)
        compiler.addInstruction("BINDVARSLOT", index)


class ViaPattern(Pattern):

    _immutable_ = True

    def __init__(self, expr, pattern):
        self._expr = expr
        if pattern is None:
            raise InvalidAST("Inner pattern of via cannot be None")
        self._pattern = pattern

    def pretty(self, out):
        out.write("via (")
        self._expr.pretty(out)
        out.write(") ")
        self._pattern.pretty(out)

    def slowTransform(self, o):
        return o.call(u"run", [StrObject(u"ViaPattern"),
                               self._expr.slowTransform(o),
                               self._pattern.slowTransform(o)])

    def rewriteScope(self, scope):
        return ViaPattern(self._expr.rewriteScope(scope),
                          self._pattern.rewriteScope(scope))

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


def formatName(p):
    if isinstance(p, FinalPattern):
        return p._n
    return u"_"
