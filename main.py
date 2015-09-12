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
from rpython.rlib import rsignal
from rpython.rlib import rvmprof
from rpython.rlib.debug import debug_print
from rpython.rlib.jit import JitHookInterface, set_user_param
from rpython.rlib.rpath import rjoin

from typhon import ruv
from typhon.arguments import Configuration
from typhon.env import finalize
from typhon.errors import LoadFailed, UserException
from typhon.importing import evaluateTerms, obtainModule
from typhon.metrics import Recorder
from typhon.objects.collections import ConstMap, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr, StrObject
from typhon.objects.imports import addImportToScope
from typhon.objects.tests import TestCollector
from typhon.objects.timeit import benchmarkSettings
from typhon.prelude import registerGlobals
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


def loadPrelude(config, recorder, vat):
    scope = safeScope()
    # For the prelude (and only the prelude), permit the boot scope.
    bootTC = TestCollector()
    scope.update(bootScope(recorder, bootTC))

    # Boot imports.
    scope = addImportToScope(config.libraryPath, scope, recorder, bootTC)

    code = obtainModule(rjoin(config.libraryPath, "prelude.ty"), recorder)

    with recorder.context("Time spent in prelude"):
        result = evaluateTerms([code], finalize(scope))

    if result is None:
        print "Prelude returned None!?"
        return {}


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


def runUntilDone(vatManager, uv_loop, recorder):
    # This may take a while.
    anyVatHasTurns = vatManager.anyVatHasTurns()
    while anyVatHasTurns or ruv.loopAlive(uv_loop):
        for vat in vatManager.vats:
            if vat.hasTurns():
                with scopedVat(vat) as vat:
                    with recorder.context("Time spent in vats"):
                        vat.takeSomeTurns()

        if ruv.loopAlive(uv_loop):
            with recorder.context("Time spent in I/O"):
                try:
                    if anyVatHasTurns:
                        # More work to be done, so don't block.
                        remaining = ruv.run(uv_loop, ruv.RUN_NOWAIT)
                    else:
                        # No more work to be done, so blocking is fine.
                        remaining = ruv.run(uv_loop, ruv.RUN_ONCE)
                except UserException as ue:
                    debug_print("Caught exception while reacting:",
                            ue.formatError())

        anyVatHasTurns = vatManager.anyVatHasTurns()


class profiling(object):

    def __init__(self, path, enabled):
        self.path = path
        self.enabled = enabled

    def __enter__(self):
        if not self.enabled:
            return

        self.handle = open(self.path, "wb")
        try:
            rvmprof.enable(self.handle.fileno(), 0.00042)
        except rvmprof.VMProfError:
            print "Couldn't enable vmprof :T"

    def __exit__(self, *args):
        if not self.enabled:
            return

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

    # Intialize our loop.
    uv_loop = ruv.alloc_loop()

    # Usurp SIGPIPE, as libuv does not handle it.
    rsignal.pypysig_ignore(rsignal.SIGPIPE)

    # Initialize our first vat.
    vatManager = VatManager()
    vat = Vat(vatManager, uv_loop)
    vatManager.vats.append(vat)

    # Update loop timing information. Until the loop really gets going, we
    # have to do this ourselves in order to get the timing correct for early
    # timers.
    ruv.update_time(uv_loop)
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
    collectTests = TestCollector()
    scope = addImportToScope(config.libraryPath, scope, recorder, collectTests)
    scope.update(unsafeScope(config, collectTests))
    try:
        code = obtainModule(config.argv[1], recorder)
    except LoadFailed as lf:
        print lf
        return 1

    if config.loadOnly:
        # We are finished.
        return 0

    if not config.benchmark:
        benchmarkSettings.disable()

    with profiling("vmprof.log", config.profile):
        # Update loop timing information.
        ruv.update_time(uv_loop)
        debug_print("Taking initial turn in script...")
        result = NullObject
        with recorder.context("Time spent in vats"):
            with scopedVat(vat):
                result = evaluateTerms([code], finalize(scope))
        if result is None:
            return 1

        # Exit status code.
        rv = 0

        # Update loop timing information.
        ruv.update_time(uv_loop)
        try:
            runUntilDone(vatManager, uv_loop, recorder)
        except SystemExit as se:
            rv = se.code
        finally:
            recorder.stop()
            recorder.printResults()

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
