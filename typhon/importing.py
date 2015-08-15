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

from rpython.rlib.debug import debug_print
from rpython.rlib.jit import dont_look_inside

from typhon.errors import UserException
from typhon.load.trash import load
from typhon.nodes import Sequence, interactiveCompile
from typhon.objects.constants import NullObject
from typhon.optimizer import optimize
from typhon.smallcaps.machine import SmallCaps
from typhon.smallcaps.peephole import peephole


class ModuleCache(object):
    """
    A necessary evil.
    """

    def __init__(self):
        self.cache = {}

moduleCache = ModuleCache()


@dont_look_inside
def obtainModuleFromSource(source, inputScope, recorder, origin):
    with recorder.context("Deserialization"):
        term = Sequence(load(source)[:])

    with recorder.context("Optimization"):
        term = optimize(term)
    # debug_print("Optimized node:", term.repr())

    with recorder.context("Compilation"):
        code, topLocals = interactiveCompile(term, origin)
    # debug_print("Compiled code:", code.disassemble())

    with recorder.context("Optimization"):
        peephole(code)
    # debug_print("Optimized code:", code.disassemble())

    return code, topLocals


def obtainModule(path, inputScope, recorder):
    if path in moduleCache.cache:
        debug_print("Importing (cached):", path)
        return moduleCache.cache[path]

    debug_print("Importing:", path)
    source = open(path, "rb").read()
    code = obtainModuleFromSource(source, inputScope, recorder,
                                  path.decode('utf-8'))[0]

    # Cache.
    moduleCache.cache[path] = code
    return code


def evaluateWithTraces(code, scope):
    try:
        machine = SmallCaps.withDictScope(code, scope)
        machine.run()
        return machine.pop()
    except UserException as ue:
        debug_print("Caught exception:", ue.formatError())
        return None


def evaluateTerms(codes, scope):
    result = NullObject
    for code in codes:
        result = evaluateWithTraces(code, scope)
        if result is None:
            debug_print("Evaluation returned None!")
    return result


def evaluateRaise(codes, scope):
    """
    Like evaluateTerms, but does not catch exceptions.
    """

    env = None
    result = NullObject
    for code in codes:
        machine = SmallCaps.withDictScope(code, scope)
        machine.run()
        result = machine.pop()
        env = machine.env
    return result, env
