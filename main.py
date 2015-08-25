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
from rpython.rlib import rvmprof
from rpython.rlib.debug import debug_print
from rpython.rlib.jit import JitHookInterface, set_user_param
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
from typhon.objects.timeit import benchmarkSettings
from typhon.prelude import registerGlobals
from typhon.profile import csp
from typhon.reactor import Reactor
from typhon.scopes.boot import bootScope
from typhon.scopes.safe import safeScope
from typhon.scopes.unsafe import unsafeScope
from typhon.vats import Vat, VatManager, scopedVat


def dirname(p):
    """Returns the directory component of a pathname"""
    i = p.rfind('/') + 1
    assert i >= 0, "Proven above but not detectable"
    head = p[:i]
    if head and head != '/'*len(head):
        head = head.rstrip('/')
    return head


def runScopeTests(scope):
    # Run unit tests.
    if u"unittest" in scope:
        unittest = scope[u"unittest"]
        unittest.test()
    else:
        print "Tried to run scope tests, but 'unittest' wasn't in scope."


def loadPrelude(config, recorder, vat):
    scope = safeScope()
    # For the prelude (and only the prelude), permit the boot scope.
    scope.update(bootScope(recorder))

    # Boot imports.
    scope = addImportToScope(config.libraryPath, scope, recorder)

    code = obtainModule(rjoin(config.libraryPath, "prelude.ty"), scope.keys(),
                        recorder)

    with recorder.context("Time spent in prelude"):
        result = evaluateTerms([code], finalize(scope))

    if result is None:
        print "Prelude returned None!?"
        return {}

    runScopeTests(scope)

    # debug_print("Prelude result:", result.toQuote())

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


def runUntilDone(vatManager, reactor, recorder):
    # This may take a while.
    anyVatHasTurns = vatManager.anyVatHasTurns()
    while anyVatHasTurns or reactor.hasObjects():
        # print "Vats:", vatManager.vats
        for vat in vatManager.vats:
            if vat.hasTurns():
                # print "Vat", vat, "has some turns"
                with scopedVat(vat) as vat:
                    with recorder.context("Time spent in vats"):
                        vat.takeSomeTurns()

        anyVatHasTurns = vatManager.anyVatHasTurns()

        if reactor.hasObjects():
            with recorder.context("Time spent in I/O"):
                try:
                    reactor.spin(anyVatHasTurns)
                except UserException as ue:
                    debug_print("Caught exception while reacting:",
                            ue.formatError())


class profiling(object):

    def __init__(self, path):
        self.path = path

    def __enter__(self):
        self.handle = open(self.path, "wb")
        try:
            rvmprof.enable(self.handle.fileno(), 0.00042)
        except rvmprof.VMProfError:
            print "Couldn't enable vmprof :T"

    def __exit__(self, *args):
        try:
            rvmprof.disable()
        except rvmprof.VMProfError:
            print "Couldn't disable vmprof >:T"
        self.handle.close()


def entryPoint(argv):
    recorder = Recorder()
    recorder.start()

    config = Configuration(argv)

    if len(config.argv) < 2:
        print "No file provided?"
        return 1

    # Pass user configuration to the JIT.
    set_user_param(None, config.jit)

    # Intialize our first vat.
    reactor = Reactor()
    reactor.usurpSignals()
    vatManager = VatManager()
    vat = Vat(vatManager, reactor)
    vatManager.vats.append(vat)

    try:
        with scopedVat(vat) as vat:
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
    scope.update(unsafeScope(config))

    try:
        code = obtainModule(config.argv[1], scope.keys(), recorder)
    except LoadFailed as lf:
        print lf
        return 1

    if config.loadOnly:
        # We are finished.
        return 0

    if config.profile:
        csp.enable()

    if not config.benchmark:
        benchmarkSettings.disable()

    with profiling("vmprof.log"):
        debug_print("Taking initial turn in script...")
        result = NullObject
        with recorder.context("Time spent in vats"):
            with scopedVat(vat):
                result = evaluateTerms([code], finalize(scope))
        if result is None:
            return 1
        # print result.toQuote()

        # Run unit tests.
        runScopeTests(scope)

        # Exit status code.
        rv = 0

        try:
            runUntilDone(vatManager, reactor, recorder)
        except SystemExit as se:
            rv = se.code
        finally:
            recorder.stop()
            recorder.printResults()

            if config.profile:
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


def target(driver, *args):
    driver.exe_name = "mt-typhon"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
