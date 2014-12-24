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

from rpython.rlib.jit import elidable, promote, unroll_safe

from typhon.atoms import getAtom
from typhon.errors import Ejecting, Refused
from typhon.objects.collections import ConstList
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector
from typhon.objects.printers import Printer
from typhon.objects.root import Object


class ScriptMap(object):
    """
    A template for scripts.

    This is called a "map" because of the use of this sort of caching template
    structure in the classic optimizing Self compiler.
    """

    _immutable_ = True

    _immutable_fields_ = "_methods[*]",

    def __init__(self, name, script):
        self.name = name

        self._methods = {}

        # Dammit, RPython.
        from typhon.nodes import Script
        assert isinstance(script, Script)
        for method in script._methods:
            # God *dammit*, RPython.
            from typhon.nodes import Method
            assert isinstance(method, Method)

            verb = method._verb
            patterns = method._ps
            block = method._b
            size = method.frameSize

            arity = len(patterns)
            atom = getAtom(verb, arity)

            self._methods[atom] = patterns, block, size

        self.matchers = []
        for matcher in script._matchers:
            # Stupid RPython. :T
            from typhon.nodes import Matcher
            assert isinstance(matcher, Matcher)
            self.matchers.append((matcher._pattern, matcher._block,
                matcher.frameSize))

    def repr(self):
        ms = [atom.repr() for atom in self._methods.keys()]
        return "ScriptMap(%s, {%s})" % (self.name, ", ".join(ms))

    @elidable
    def lookup(self, atom):
        return self._methods.get(atom, (None, None, -1))


def runBlock(patterns, block, args, ej, env):
    """
    Run a block with an environment.
    """

    from typhon.nodes import evaluate

    with env as env:
        # Set up parameters from arguments.
        # We are assured that the counts line up by our caller.
        assert len(patterns) == len(args), "runBlock() called with bad args"
        for i, pattern in enumerate(patterns):
            promote(pattern).unify(args[i], ej, env)

        # Run the block.
        return evaluate(block, env)


class ScriptObject(Object):
    """
    A user-defined object.
    """

    _immutable_fields_ = "displayName", "_map"

    def __init__(self, displayName, scriptMap, env):
        self.displayName = displayName
        self._map = scriptMap
        self._env = env

    def env(self, size):
        return self._env.new(size)

    def toString(self):
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.displayName

    @unroll_safe
    def recv(self, atom, args):
        # Circular import here to get at the evaluation function.
        from typhon.nodes import evaluate

        patterns, block, frameSize = self._map.lookup(atom)

        if patterns is not None and block is not None:
            block = promote(block)
            # This ejector will be used to signal that the method was not
            # usable due to failed pattern matching of arguments to
            # parameters. Since it's possible that a matcher will match the
            # message, we don't want to give up if the method fails to match.
            with Ejector() as ej:
                try:
                    return runBlock(patterns, block, args, ej,
                            self.env(frameSize))
                except Ejecting as e:
                    if e.ejector is not ej:
                        # Oops, we caught another ejector! Let it go.
                        raise

        # Well, let's try the matchers.
        matchers = self._map.matchers
        message = ConstList([StrObject(atom.verb), ConstList(args)])

        for pattern, block, frameSize in matchers:
            with self.env(frameSize) as env:
                with Ejector() as ej:
                    try:
                        pattern.unify(message, ej, env)

                        # Run the block.
                        rv = evaluate(block, env)
                        return rv
                    except Ejecting as e:
                        # Is it the ejector that we created in this frame? If
                        # not, reraise.
                        if e.ejector is ej:
                            continue
                        raise

        # print "I am", self.repr(), "and I am refusing", atom
        # print "I would have accepted", self._map.repr()
        raise Refused(self, atom, args)
