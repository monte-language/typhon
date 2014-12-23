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

from rpython.rlib.jit import assert_green, elidable, jit_debug, unroll_safe

from typhon.errors import Ejecting, LoadFailed, UserException
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.data import CharObject, DoubleObject, IntObject, StrObject
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.slots import VarSlot
from typhon.objects.user import ScriptMap, ScriptObject
from typhon.pretty import Buffer, LineWriter, OneLine


def evaluate(node, env):
    # Want to see nodes in JIT traces? Uncomment these two lines. ~ C.
    assert_green(node)
    jit_debug(node.repr())
    try:
        return node.evaluate(env)
    except UserException as ue:
        crumb = node.__class__.__name__.decode("utf-8")
        out = OneLine()
        node.pretty(out)
        ue.trail.append((crumb, out.getLine().decode("utf-8")))
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

    def transform(self, f):
        """
        Apply the given transformation to all children of this node, and this
        node, bottom-up.
        """

        return f(self)

    def rewriteScope(self, seen, shadows):
        """
        Rewrite the scope definitions by altering names.

        Nodes should use the `seen` scope to determine whether they are
        shadowing, and the `shadows` scope to fix old shadows.
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
        return ConstList([evaluate(item, env) for item in self._t])

    def transform(self, f):
        # I don't care if it's cheating. It's elegant and simple and pretty.
        return f(Tuple([node.transform(f) for node in self._t]))

    def rewriteScope(self, seen, shadows):
        return Tuple([node.rewriteScope(seen, shadows) for node in self._t])

    def usesName(self, name):
        uses = False
        for node in self._t:
            if node.usesName(name):
                uses = True
        return uses


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
        value = evaluate(self.rvalue, env)
        env.update(self.target, value)
        return value

    def transform(self, f):
        return f(Assign(self.target, self.rvalue.transform(f)))

    def rewriteScope(self, seen, shadows):
        # Read.
        newTarget = shadows.get(self.target)
        if newTarget is None:
            newTarget = self.target
        return Assign(newTarget, self.rvalue.rewriteScope(seen, shadows))

    def usesName(self, name):
        return self.rvalue.usesName(name)


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

    def evaluate(self, env):
        return env.bindingFor(self.name)

    def transform(self, f):
        return f(self)

    def rewriteScope(self, seen, shadows):
        # Read.
        newName = shadows.get(self.name)
        if newName is None:
            return self
        return Binding(newName)


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
        target = evaluate(self._target, env)
        verb = evaluate(self._verb, env)
        # XXX figure out a better runtime exception for this
        assert isinstance(verb, StrObject), "non-Str verb"
        args = evaluate(self._args, env)

        return target.call(verb._s, unwrapList(args))

    def transform(self, f):
        return f(Call(self._target.transform(f), self._verb.transform(f),
            self._args.transform(f)))

    def rewriteScope(self, seen, shadows):
        return Call(self._target.rewriteScope(seen, shadows),
                    self._verb.rewriteScope(seen, shadows),
                    self._args.rewriteScope(seen, shadows))

    def usesName(self, name):
        rv = self._target.usesName(name) or self._verb.usesName(name)
        return rv or self._args.usesName(name)


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
        rval = evaluate(self._v, env)

        if self._e is None:
            ejector = None
        else:
            ejector = evaluate(self._e, env)

        self._p.unify(rval, ejector, env)
        return rval

    def transform(self, f):
        return f(Def(self._p, self._e, self._v.transform(f)))

    def rewriteScope(self, seen, shadows):
        # Delegate to patterns.
        p = self._p.rewriteScope(seen, shadows)
        if self._e is None:
            e = None
        else:
            e = self._e.rewriteScope(seen, shadows)
        return Def(p, e, self._v.rewriteScope(seen, shadows))

    def usesName(self, name):
        rv = self._v.usesName(name)
        if self._e is not None:
            rv = rv or self._e.usesName(name)
        return rv


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
            rv = None

            with env as newEnv:
                self._pattern.unify(ej, None, newEnv)

                try:
                    return evaluate(self._node, newEnv)
                except Ejecting as e:
                    # Is it the ejector that we created in this frame? If not,
                    # reraise.
                    if e.ejector is ej:
                        # If no catch, then return as-is.
                        rv = e.value
                    else:
                        raise

            # If we have no catch block, then let's just return the value that
            # we captured earlier.
            if self._catchNode is None:
                return rv

            # Else, let's set up another frame and handle the catch block.
            with env as newEnv:
                self._catchPattern.unify(rv, None, newEnv)
                return evaluate(self._catchNode, newEnv)

    def transform(self, f):
        # We have to write some extra code here since catchNode could be None.
        if self._catchNode is None:
            catchNode = None
        else:
            catchNode = self._catchNode.transform(f)

        return f(Escape(self._pattern, self._node.transform(f),
            self._catchPattern, catchNode))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                p = self._pattern.rewriteScope(seen, shadows)
                n = self._node.rewriteScope(seen, shadows)

        with seen:
            with shadows:
                if self._catchPattern is None:
                    cp = None
                else:
                    cp = self._catchPattern.rewriteScope(seen, shadows)
                if self._catchNode is None:
                    cn = None
                else:
                    cn = self._catchNode.rewriteScope(seen, shadows)

        return Escape(p, n, cp, cn)

    def usesName(self, name):
        rv = self._node.usesName(name)
        if self._catchNode is not None:
            rv = rv or self._catchNode.usesName(name)
        return rv


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
                rv = evaluate(self._block, env)
            return rv
        finally:
            with env as env:
                evaluate(self._atLast, env)

    def transform(self, f):
        return f(Finally(self._block.transform(f), self._atLast.transform(f)))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                return Finally(self._block.rewriteScope(seen, shadows),
                               self._atLast.rewriteScope(seen, shadows))

    def usesName(self, name):
        return self._block.usesName(name) or self._atLast.usesName(name)


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

    def transform(self, f):
        return f(Hide(self._inner.transform(f)))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                return Hide(self._inner.rewriteScope(seen, shadows))

    def usesName(self, name):
        # XXX not technically correct due to Hide intentionally altering
        # scope resolution.
        return self._inner.usesName(name)


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
            whether = evaluate(self._test, env)

            if unwrapBool(whether):
                return evaluate(self._then, env)
            else:
                return evaluate(self._otherwise, env)

    def transform(self, f):
        return f(If(self._test.transform(f), self._then.transform(f),
            self._otherwise.transform(f)))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                return If(self._test.rewriteScope(seen, shadows),
                          self._then.rewriteScope(seen, shadows),
                          self._otherwise.rewriteScope(seen, shadows))

    def usesName(self, name):
        rv = self._test.usesName(name) or self._then.usesName(name)
        return rv or self._otherwise.usesName(name)


class Matcher(Node):

    _immutable_ = True

    def __init__(self, pattern, block):
        self._pattern = pattern
        self._block = block

    def pretty(self, out):
        out.write("match ")
        self._pattern.pretty(out)
        out.writeLine(":")
        self._block.pretty(out.indent())
        out.writeLine("")

    def transform(self, f):
        return f(Matcher(self._pattern, self._block.transform(f)))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                return Matcher(self._pattern.rewriteScope(seen, shadows),
                               self._block.rewriteScope(seen, shadows))


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

    def transform(self, f):
        return f(Method(self._d, self._verb, self._ps, self._g,
            self._b.transform(f)))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                ps = [p.rewriteScope(seen, shadows) for p in self._ps]
                return Method(self._d, self._verb, ps,
                              self._g.rewriteScope(seen, shadows),
                              self._b.rewriteScope(seen, shadows))

    def usesName(self, name):
        return self._b.usesName(name)


class Noun(Node):

    _immutable_ = True

    def __init__(self, noun):
        self.name = strToString(noun)

    def pretty(self, out):
        out.write(self.name.encode("utf-8"))

    def evaluate(self, env):
        return env.get(self.name)

    def rewriteScope(self, seen, shadows):
        # Read.
        newName = shadows.get(self.name)
        if newName is None:
            return self
        return Noun(Str(newName))

    def usesName(self, name):
        return self.name == name


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

        # Create a cached map which will be reused for all objects created
        # from this node.
        self._cachedMap = ScriptMap(name.__repr__(), self._script)

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
        # Hmm. Objects need to have access to themselves within their scope...
        rv = ScriptObject(formatName(self._n), self._cachedMap, env.freeze())
        # ...but fortunately, objects don't contain any evaluations while
        # being created, and it's always possible to perform the assignment
        # into the environment afterwards.
        self._n.unify(rv, None, rv.env())
        # Oh, and assign it into the outer environment too.
        self._n.unify(rv, None, env)
        return rv

    def transform(self, f):
        return f(Obj(self._d, self._n, self._as, self._implements,
            self._script.transform(f)))

    def rewriteScope(self, seen, shadows):
        # XXX as, implements
        return Obj(self._d, self._n.rewriteScope(seen, shadows), self._as,
                   self._implements, self._script.rewriteScope(seen, shadows))

    def usesName(self, name):
        return self._script.usesName(name)


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

    def transform(self, f):
        methods = [method.transform(f) for method in self._methods]
        return f(Script(self._extends, methods, self._matchers))

    def rewriteScope(self, seen, shadows):
        methods = [m.rewriteScope(seen, shadows) for m in self._methods]
        matchers = [m.rewriteScope(seen, shadows) for m in self._matchers]
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
        for item in self._l:
            item.pretty(out)
            out.writeLine("")

    @unroll_safe
    def evaluate(self, env):
        rv = NullObject
        for node in self._l:
            rv = evaluate(node, env)
        return rv

    def transform(self, f):
        return f(Sequence([node.transform(f) for node in self._l]))

    def rewriteScope(self, seen, shadows):
        return Sequence([n.rewriteScope(seen, shadows) for n in self._l])

    def usesName(self, name):
        for node in self._l:
            if node.usesName(name):
                return True
        return False


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
                return evaluate(self._first, env)
        except UserException:
            with env as env:
                # XXX Exception information can't be leaked back into Monte;
                # seal it properly instead of using null here.
                if self._pattern.unify(NullObject, None, env):
                    return evaluate(self._then, env)
                else:
                    raise

    def transform(self, f):
        return f(Try(self._first.transform(f), self._pattern,
            self._then.transform(f)))

    def rewriteScope(self, seen, shadows):
        with seen:
            with shadows:
                first = self._first.rewriteScope(seen, shadows)

        with seen:
            with shadows:
                return Try(first, self._pattern.rewriteScope(seen, shadows),
                           self._then.rewriteScope(seen, shadows))

    def usesName(self, name):
        return self._first.usesName(name) or self._then.usesName(name)


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

    def unify(self, specimen, ejector, env):
        env.recordBinding(self._noun, specimen)

    def rewriteScope(self, seen, shadows):
        # Write.
        if seen.get(self._noun):
            # Shadow.
            shadowed = shadowName(self._noun, shadows)
            return BindingPattern(Noun(Str(shadowed)))
        else:
            seen.put(self._noun, self._noun)
            return self


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

    def unify(self, specimen, ejector, env):
        if self._g is None:
            rv = specimen
        else:
            # Get the guard.
            guard = evaluate(self._g, env)

            # Since this is a final assignment, we can run the specimen through
            # the guard once and for all, right now.
            rv = guard.call(u"coerce", [specimen, ejector])

        env.final(self._n, rv)

    def rewriteScope(self, seen, shadows):
        if self._g is None:
            g = None
        else:
            g = self._g.rewriteScope(seen, shadows)

        # Write.
        if seen.get(self._n):
            # Shadow.
            shadowed = shadowName(self._n, shadows)
            return FinalPattern(Noun(Str(shadowed)), g)
        else:
            seen.put(self._n, self._n)
            return self


class IgnorePattern(Pattern):

    _immutable_ = True

    def __init__(self, guard):
        self._g = nullToNone(guard)

    def pretty(self, out):
        out.write("_")
        if self._g is not None:
            out.write(" :")
            self._g.pretty(out)

    def unify(self, specimen, ejector, env):
        # We don't have to do anything, unless somebody put a guard on an
        # ignore pattern. Who would do such a thing?
        if self._g is not None:
            guard = evaluate(self._g, env)
            guard.call(u"coerce", [specimen, ejector])

    def rewriteScope(self, seen, shadows):
        if self._g is None:
            return self
        return IgnorePattern(self._g.rewriteScope(seen, shadows))


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
    def unify(self, specimen, ejector, env):
        patterns = self._ps
        tail = self._t

        # Can't unify lists and non-lists.
        if not isinstance(specimen, ConstList):
            throw(ejector, StrObject(u"Can't unify lists and non-lists"))

        items = unwrapList(specimen)

        # If we have no tail, then unification isn't going to work if the
        # lists are of differing lengths.
        if tail is None and len(patterns) != len(items):
            throw(ejector, StrObject(u"Lists are different lengths"))

        # Even if there's a tail, there must be at least as many elements in
        # the pattern list as there are in the specimen list.
        elif len(patterns) > len(items):
            throw(ejector, StrObject(u"List is too short"))

        # Actually unify. Because of the above checks, this shouldn't run
        # ragged.
        for i, pattern in enumerate(patterns):
            pattern.unify(items[i], ejector, env)

        # And unify the tail as well.
        if tail is not None:
            remainder = ConstList(items[len(patterns):])
            tail.unify(remainder, ejector, env)

    def rewriteScope(self, seen, shadows):
        ps = [p.rewriteScope(seen, shadows) for p in self._ps]
        if self._t is None:
            t = None
        else:
            t = self._t.rewriteScope(seen, shadows)
        return ListPattern(ps, t)


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

    def unify(self, specimen, ejector, env):
        if self._g is None:
            rv = VarSlot(specimen)
        else:
            # Get the guard.
            guard = evaluate(self._g, env)

            # Generate a slot.
            rv = guard.call(u"makeSlot", [specimen])

        # Add the slot to the environment.
        env.recordSlot(self._n, rv)

    def rewriteScope(self, seen, shadows):
        if self._g is None:
            g = None
        else:
            g = self._g.rewriteScope(seen, shadows)

        # Write.
        if seen.get(self._n):
            # Shadow.
            shadowed = shadowName(self._n, shadows)
            return VarPattern(Noun(Str(shadowed)), g)
        else:
            seen.put(self._n, self._n)
            return self


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

    def unify(self, specimen, ejector, env):
        # This one always bamboozles me, so I'll spell out what it's doing.
        # The via pattern takes an expression and another pattern, and passes
        # the specimen into the expression along with an ejector. The
        # expression can reject the specimen by escaping, or it can transform
        # the specimen and return a new specimen which is then applied to the
        # inner pattern.
        examiner = evaluate(self._expr, env)
        self._pattern.unify(examiner.call(u"run", [specimen, ejector]),
                ejector, env)

    def rewriteScope(self, seen, shadows):
        return ViaPattern(self._expr.rewriteScope(seen, shadows),
                          self._pattern.rewriteScope(seen, shadows))


def formatName(p):
    if isinstance(p, FinalPattern):
        return p._n
    return u"_"


def shadowName(name, shadows):
    shadowed = name + u"_"
    while shadows.get(shadowed) is not None:
        shadowed += u"_"
    shadows.put(name, shadowed)
    return shadowed
