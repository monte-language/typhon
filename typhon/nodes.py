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

from rpython.rlib.jit import elidable, unroll_safe

from typhon.errors import Ejecting, LoadFailed, UserException
from typhon.objects import ScriptObject
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import BoolObject, NullObject
from typhon.objects.data import CharObject, DoubleObject, IntObject, StrObject
from typhon.objects.ejectors import Ejector
from typhon.pretty import Buffer, LineWriter, OneLine


def evaluate(node, env):
    try:
        return node.evaluate(env)
    except UserException as ue:
        crumb = node.__class__.__name__
        out = OneLine()
        node.pretty(out)
        ue.trail.append((crumb, out.getLine()))
        raise


class InvalidAST(LoadFailed):
    """
    An AST was ill-formed.
    """


class Node(object):

    _immutable_ = True
    _attrs_ = ()

    def __repr__(self):
        b = Buffer()
        self.pretty(LineWriter(b))
        return b.get()

    @elidable
    def repr(self):
        return self.__repr__()

    def pretty(self, out):
        raise NotImplementedError

    def evaluate(self, env):
        raise NotImplementedError


class _Null(Node):

    _immutable_ = True
    _attrs_ = ()

    def pretty(self, out):
        out.write("null")

    def evaluate(self, env):
        return NullObject


Null = _Null()


def nullToNone(node):
    return None if node is Null else node


class Int(Node):

    _immutable_ = True

    def __init__(self, i):
        self._i = i

    def pretty(self, out):
        out.write("%d" % self._i)

    def evaluate(self, env):
        return IntObject(self._i)


class Str(Node):

    _immutable_ = True

    def __init__(self, s):
        self._s = s

    def pretty(self, out):
        out.write('"%s"' % (self._s.encode("utf-8")))

    def evaluate(self, env):
        return StrObject(self._s)


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

    def evaluate(self, env):
        return DoubleObject(self._d)


class Char(Node):

    _immutable_ = True

    def __init__(self, c):
        self._c = c

    def pretty(self, out):
        out.write("'%s'" % (self._c.encode("utf-8")))

    def evaluate(self, env):
        return CharObject(self._c)


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

    @unroll_safe
    def evaluate(self, env):
        return ConstList([item.evaluate(env) for item in self._t])


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

    def evaluate(self, env):
        value = self.rvalue.evaluate(env)
        env.update(self.target, value)
        return value


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


class Call(Node):

    _immutable_ = True

    def __init__(self, target, verb, args):
        self._target = target
        self._verb = verb
        self._args = args

    def pretty(self, out):
        self._target.pretty(out)
        out.write(".")
        self._verb.pretty(out)
        out.write("(")
        self._args.pretty(out)
        out.write(")")

    def evaluate(self, env):
        # There's a careful order of operations here. First we have to
        # evaluate the target, then the verb, and finally the arguments.
        # Once we do all that, we make the actual call.
        target = self._target.evaluate(env)
        verb = self._verb.evaluate(env)
        assert isinstance(verb, StrObject), "non-Str verb"
        args = self._args.evaluate(env)

        return target.recv(verb._s, unwrapList(args))


class Def(Node):

    _immutable_ = True

    def __init__(self, pattern, ejector, value):
        self._p = pattern
        self._e = ejector
        self._v = value

    @staticmethod
    def fromAST(pattern, ejector, value):
        return Def(pattern, nullToNone(ejector),
                value if value is not None else Null)

    def pretty(self, out):
        out.write("def ")
        self._p.pretty(out)
        if self._e is not None:
            out.write(" exit ")
            self._e.pretty(out)
        out.write(" := ")
        self._v.pretty(out)
        out.writeLine("")

    def evaluate(self, env):
        rval = self._v.evaluate(env)
        # We don't care about whether we only get partway through the pattern
        # unification here before exiting on failure, since we're going to
        # exit this scope on failure before those names can even be used.
        if not self._p.unify(rval, env):
            # XXX if self._p is None
            raise RuntimeError
        return rval


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
        out.writeLine(":")
        self._node.pretty(out.indent())
        if self._catchNode is not None:
            out.write("catch ")
            self._catchPattern.pretty(out)
            out.writeLine(":")
            self._catchNode.pretty(out.indent())

    def evaluate(self, env):
        with Ejector() as ej:
            with env as env:
                if not self._pattern.unify(ej, env):
                    raise RuntimeError

                try:
                    return self._node.evaluate(env)
                except Ejecting as e:
                    # Is it the ejector that we created in this frame? If not,
                    # reraise.
                    if e.ejector is ej:
                        return e.value
                    raise


class Finally(Node):

    _immutable_ = True

    def __init__(self, block, atLast):
        self._block = block
        self._atLast = atLast

    def pretty(self, out):
        out.writeLine("try:")
        self._block.pretty(out.indent())
        out.writeLine("")
        out.writeLine("finally:")
        self._atLast.pretty(out.indent())

    def evaluate(self, env):
        # Use RPython's exception handling system to ensure the execution of
        # the atLast block after exiting the main block.
        try:
            with env as env:
                rv = self._block.evaluate(env)
            return rv
        finally:
            with env as env:
                self._atLast.evaluate(env)


class Hide(Node):

    _immutable_ = True

    def __init__(self, inner):
        self._inner = inner

    def pretty(self, out):
        out.writeLine("hide:")
        self._inner.pretty(out.indent())

    def evaluate(self, env):
        with env as env:
            return evaluate(self._inner, env)


class If(Node):

    _immutable_ = True

    def __init__(self, test, then, otherwise):
        self._test = test
        self._then = then
        self._otherwise = otherwise

    def pretty(self, out):
        out.write("if (")
        self._test.pretty(out)
        out.writeLine("):")
        self._then.pretty(out.indent())
        out.writeLine("")
        out.writeLine("else:")
        self._otherwise.pretty(out.indent())

    def evaluate(self, env):
        # If is a short-circuiting expression. We construct zero objects in
        # the branch that is not chosen.
        with env as env:
            whether = self._test.evaluate(env)
            if isinstance(whether, BoolObject):
                with env as env:
                    if whether.isTrue():
                        return self._then.evaluate(env)
                    else:
                        return self._otherwise.evaluate(env)
            else:
                raise TypeError("non-Boolean in conditional expression")


class Matcher(Node):

    _immutable_ = True

    def __init__(self, pattern, block):
        self._pattern = pattern
        self._block = block


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
        out.writeLine(":")
        self._b.pretty(out.indent())
        out.writeLine("")


class Noun(Node):

    _immutable_ = True

    def __init__(self, noun):
        self.name = strToString(noun)

    def pretty(self, out):
        out.write(self.name.encode("utf-8"))

    def evaluate(self, env):
        return env.get(self.name)


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
        auditors = tupleToList(auditors)
        if not isinstance(script, Script):
            raise InvalidAST("Object's script isn't a Script")

        return Obj(doc, name, nullToNone(auditors[0]), auditors[1:], script)

    def pretty(self, out):
        out.write("object ")
        self._n.pretty(out)
        # XXX doc, as, implements
        out.writeLine(":")
        self._script.pretty(out.indent())

    def evaluate(self, env):
        rv = ScriptObject(self._script, env)
        self._n.unify(rv, env)
        return rv


class Script(Node):

    _immutable_ = True

    _immutable_fields_ = "_methods[*]", "_matchers[*]"

    def __init__(self, extends, methods, matchers):
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

        return Script(extends, methods, matchers)

    def pretty(self, out):
        for method in self._methods:
            method.pretty(out)
        for matcher in self._matchers:
            matcher.pretty(out)


class Sequence(Node):

    _immutable_ = True

    _immutable_fields_ = "_l[*]",

    def __init__(self, l):
        self._l = l

    @staticmethod
    def fromAST(t):
        return Sequence(tupleToList(t))

    def pretty(self, out):
        for item in self._l:
            item.pretty(out)
            out.writeLine("")

    @unroll_safe
    def evaluate(self, env):
        rv = NullObject
        for node in self._l:
            rv = evaluate(node, env)
        return rv


class Try(Node):

    _immutable_ = True

    def __init__(self, first, pattern, then):
        self._first = first
        self._pattern = pattern
        self._then = then

    def pretty(self, out):
        out.writeLine("try:")
        self._first.pretty(out.indent())
        out.writeLine("")
        out.write("catch ")
        self._pattern.pretty(out)
        out.writeLine(":")
        self._then.pretty(out.indent())

    def evaluate(self, env):
        # Try the first block, and if an exception is raised, pattern-match it
        # against the catch-pattern in the then-block.
        try:
            with env as env:
                return self._first.evaluate(env)
        except UserException:
            with env as env:
                # XXX Exception information can't be leaked back into Monte;
                # seal it properly instead of using null here.
                if self._pattern.unify(NullObject, env):
                    return self._then.evaluate(env)
                else:
                    raise


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

class FinalPattern(Pattern):

    _immutable_ = True

    def __init__(self, noun, guard):
        self._n = nounToString(noun)
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("def ")
        out.write(self._n.encode("utf-8"))
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)


    def unify(self, specimen, env):
        env.final(self._n, specimen)
        return True


class IgnorePattern(Pattern):

    _immutable_ = True

    def __init__(self, guard):
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("_")
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def unify(self, specimen, env):
        return True


class ListPattern(Pattern):

    _immutable_ = True

    _immutable_fields_ = "_ps[*]",

    def __init__(self, patterns, tail):
        self._ps = patterns
        self._t = tail

    def pretty(self, out):
        out.write("[")
        for pattern in self._ps:
            pattern.pretty(out)
            out.write(", ")
        out.write("]")
        if self._t is not None:
            out.write(" | ")
            self._t.pretty(out)

    @unroll_safe
    def unify(self, specimen, env):
        patterns = self._ps
        tail = self._t

        # Can't unify lists and non-lists.
        if not isinstance(specimen, ConstList):
            return False
        items = unwrapList(specimen)

        # If we have no tail, then unification isn't going to work if the
        # lists are of differing lengths.
        if tail is None and len(patterns) != len(items):
            return False
        # Even if there's a tail, there must be at least as many elements in
        # the pattern list as there are in the specimen list.
        elif len(patterns) > len(items):
            return False

        # Actually unify. Because of the above checks, this shouldn't run
        # ragged.
        for i, pattern in enumerate(patterns):
            pattern.unify(items[i], env)

        # And unify the tail as well.
        if tail is not None:
            remainder = ConstList(items[len(patterns):])
            tail.unify(remainder, env)

        return True


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

    def unify(self, specimen, env):
        env.variable(self._n, specimen)
        return True


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

    def unify(self, specimen, env):
        # This one always bamboozles me, so I'll spell out what it's doing.
        # The via pattern takes an expression and another pattern, and passes
        # the specimen into the expression along with an ejector. The
        # expression can reject the specimen by escaping, or it can transform
        # the specimen and return a new specimen which is then applied to the
        # inner pattern.
        examiner = self._expr.evaluate(env)
        self._pattern.unify(examiner.recv(u"run", [specimen]), env)
        return True
