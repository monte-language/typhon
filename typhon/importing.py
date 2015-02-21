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
from rpython.rlib.listsort import TimSort

from typhon.errors import UserException
from typhon.load import load
from typhon.nodes import Sequence, compile
from typhon.objects.constants import NullObject
from typhon.optimizer import optimize
from typhon.scope import Scope
from typhon.smallcaps.machine import SmallCaps


@dont_look_inside
def obtainModule(path, inputScope, recorder):
    with recorder.context("Deserialization"):
        term = Sequence(load(open(path, "rb").read())[:])

    # Unshadow.
    with recorder.context("Scope analysis"):
        TimSort(inputScope).sort()
        scope = Scope(inputScope)
        term = term.rewriteScope(scope)

    with recorder.context("Optimization"):
        term = optimize(term)
    # debug_print("Optimized node:", term.repr())

    with recorder.context("Compilation"):
        code = compile(term)
    # debug_print("Compiled code:", code.disassemble())

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
