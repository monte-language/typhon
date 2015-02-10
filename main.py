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

import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.rpath import rjoin

from typhon.arguments import Configuration
from typhon.env import finalize
from typhon.errors import LoadFailed
from typhon.importing import evaluateTerms, obtainModule
from typhon.metrics import Recorder
from typhon.objects.collections import ConstMap, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr, StrObject
from typhon.objects.imports import addImportToScope
from typhon.prelude import registerGlobals
from typhon.reactor import Reactor
from typhon.scopes.safe import safeScope
from typhon.scopes.unsafe import unsafeScope
from typhon.vats import Vat, currentVat


def dirname(p):
    """Returns the directory component of a pathname"""
    i = p.rfind('/') + 1
    assert i >= 0, "Proven above but not detectable"
    head = p[:i]
    if head and head != '/'*len(head):
        head = head.rstrip('/')
    return head


def jitPolicy(driver):
    return JitPolicy()


def loadPrelude(config, recorder, vat):
    scope = safeScope()
    code = obtainModule(rjoin(config.libraryPath, "prelude.ty"), scope.keys(),
                        recorder)

    with recorder.context("Time spent in prelude"):
        result = evaluateTerms([code], finalize(scope))

    if result is None:
        print "Prelude returned None!?"
        return {}

    print "Prelude result:", result.toQuote()

    # Run unit tests.
    unittest = scope[u"unittest"]
    unittest.test()

    if isinstance(result, ConstMap):
        prelude = {}
        for key, value in unwrapMap(result).items():
            if isinstance(key, StrObject):
                prelude[unwrapStr(key)] = value
            else:
                print "Prelude map key", key, "isn't a string"
        return prelude

    print "Prelude didn't return map!?"
    return {}


def entryPoint(argv):
    recorder = Recorder()
    recorder.start()

    config = Configuration(argv)

    if len(config.argv) < 2:
        print "No file provided?"
        return 1

    # Intialize our vat.
    reactor = Reactor()
    reactor.usurpSignals()
    vat = Vat(reactor)
    currentVat.set(vat)

    try:
        prelude = loadPrelude(config, recorder, vat)
    except LoadFailed as lf:
        print lf
        return 1

    registerGlobals(prelude)

    scope = safeScope()
    scope.update(prelude)
    # Note the order of operations. addImportToScope() copies the scope that
    # it receives, so the unsafe scope will only be available to the
    # top-level script and not to any library code which is indirectly loaded
    # via import().
    addImportToScope(config.libraryPath, scope, recorder)
    scope.update(unsafeScope())

    try:
        code = obtainModule(config.argv[1], scope.keys(), recorder)
    except LoadFailed as lf:
        print lf
        return 1

    if config.loadOnly:
        # We are finished.
        return 0

    result = NullObject
    with recorder.context("Time spent in vats"):
        result = evaluateTerms([code], finalize(scope))
    if result is None:
        return 1
    print result.toQuote()

    # Run unit tests.
    unittest = scope[u"unittest"]
    unittest.test()

    try:
        # Run any remaining turns.
        while vat.hasTurns() or reactor.hasObjects():
            if vat.hasTurns():
                vat.takeSomeTurns(recorder)

            if reactor.hasObjects():
                # print "Performing I/O..."
                with recorder.context("Time spent in I/O"):
                    reactor.spin(vat.hasTurns())
    finally:
        recorder.stop()
        recorder.printResults()

    return 0


def target(*args):
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
