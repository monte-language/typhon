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

import os
import sys

from rpython.jit.codewriter.policy import JitPolicy
from rpython.rlib.debug import debug_print
from rpython.rlib.jit import JitHookInterface
from rpython.rlib.rpath import rjoin

from typhon.arguments import Configuration
from typhon.env import finalize
from typhon.errors import LoadFailed, UserException
from typhon.importing import evaluateTerms, obtainModule
from typhon.metrics import Recorder
from typhon.objects.collections import ConstMap, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr, StrObject
from typhon.objects.imports import addImportToScope
from typhon.prelude import registerGlobals
from typhon.profile import csp
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
    scope = addImportToScope(config.libraryPath, scope, recorder)
    scope.update(unsafeScope())

    try:
        code = obtainModule(config.argv[1], scope.keys(), recorder)
    except LoadFailed as lf:
        print lf
        return 1

    if config.loadOnly:
        # We are finished.
        return 0

    if not config.profile:
        csp.disable()

    result = NullObject
    with recorder.context("Time spent in vats"):
        result = evaluateTerms([code], finalize(scope))
    if result is None:
        return 1
    print result.toQuote()

    # Run unit tests.
    unittest = scope[u"unittest"]
    unittest.test()

    # Exit status code.
    rv = 0

    try:
        # Run any remaining turns. This may take a while.
        while vat.hasTurns() or reactor.hasObjects():
            if vat.hasTurns():
                with recorder.context("Time spent in vats"):
                    vat.takeSomeTurns()

            if reactor.hasObjects():
                with recorder.context("Time spent in I/O"):
                    try:
                        reactor.spin(vat.hasTurns())
                    except UserException as ue:
                        debug_print("Caught exception while reacting:",
                                ue.formatError())
    except SystemExit as se:
        rv = se.code
    finally:
        recorder.stop()

        if config.profile:
            recorder.printResults()

            # Print out flame graph information.
            with open("flames.txt", "wb") as handle:
                csp.writeFlames(handle)

    return 0


def writePerfMap(s):
    path = "/tmp/perf-%d.map" % os.getpid()
    fd = os.open(path, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0777)
    os.write(fd, s)
    os.close(fd)


class TyphonJitHooks(JitHookInterface):

    def after_compile(self, debug_info):
        s = "%x %x %s\n" % (debug_info.asminfo.asmaddr,
                            debug_info.asminfo.asmlen,
                            "<Typhon JIT trace>")
        writePerfMap(s)

    def after_compile_bridge(self, debug_info):
        s = "%x %x %s\n" % (debug_info.asminfo.asmaddr,
                            debug_info.asminfo.asmlen,
                            "<Typhon JIT bridge>")
        writePerfMap(s)


def jitpolicy(driver):
    return JitPolicy(TyphonJitHooks())


def target(*args):
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
