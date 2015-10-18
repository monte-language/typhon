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

from typhon import ruv
from typhon.arguments import Configuration
from typhon.errors import LoadFailed, UserException
from typhon.importing import evaluateTerms, instantiateModule, obtainModule
from typhon.metrics import Recorder
from typhon.objects.collections import ConstMap, monteDict, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject, unwrapStr
from typhon.objects.guards import anyGuard
from typhon.objects.imports import Import, addImportToScope
from typhon.objects.refs import resolution
from typhon.objects.slots import FinalBinding
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
    scope = addImportToScope(config.libraryPaths, scope, recorder, bootTC)

    code = obtainModule(config.libraryPaths, "prelude", recorder)
    with recorder.context("Time spent in prelude"):
        result = evaluateTerms([code], scope)

    if result is None:
        print "Prelude returned None!?"
        return {}


    # debug_print("Prelude result:", result.toQuote())

    if isinstance(result, ConstMap):
        prelude = {}
        for key, value in unwrapMap(result).items():
            if isinstance(key, StrObject):
                s = unwrapStr(key)
                if not s.startswith(u"&&"):
                    print "Prelude map key", s, "doesn't start with '&&'"
                else:
                    prelude[s[2:]] = value
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
        except rvmprof.VMProfError as vmpe:
            print "Couldn't enable vmprof:", vmpe.msg

    def __exit__(self, *args):
        if not self.enabled:
            return

        try:
            rvmprof.disable()
        except rvmprof.VMProfError as vmpe:
            print "Couldn't disable vmprof:", vmpe.msg
        self.handle.close()


def runModule(exports, scope):
    """
    Run a main entrypoint.
    """

    if not isinstance(exports, ConstMap):
        return None

    main = exports.objectMap.get(StrObject(u"main"), None)
    if main is None:
        return None

    namedArgs = monteDict()
    reflectedUnsafeScope = monteDict()
    for k, b in scope.iteritems():
        v = b.getValue()
        namedArgs[StrObject(k)] = v
        reflectedUnsafeScope[StrObject(u"&&" + k)] = b
    rus = ConstMap(reflectedUnsafeScope)
    reflectedUnsafeScope[StrObject(u"&&unsafeScope")] = FinalBinding(
        rus, anyGuard)
    namedArgs[StrObject(u"unsafeScope")] = rus
    return main.call(u"run", [], ConstMap(namedArgs))


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
    DF = prelude[u"DeepFrozen"].getValue()
    collectTests = TestCollector()
    ss = scope.copy()
    ss[u"import"] = FinalBinding(
        Import(config.libraryPaths, ss, recorder, collectTests),
        DF)
    reflectedSS = monteDict()
    for k, b in ss.iteritems():
        reflectedSS[StrObject(u"&&" + k)] = b
    ss[u"safeScope"] = FinalBinding(ConstMap(reflectedSS), DF)
    reflectedSS[StrObject(u"&&safeScope")] = ss[u"safeScope"]
    scope[u"safeScope"] = ss[u"safeScope"]
    scope[u"import"] = ss[u"import"]
    scope.update(unsafeScope(config, collectTests))
    try:
        code = obtainModule([""], config.argv[1], recorder)
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
                result = evaluateTerms([code], ss)
        if result is None:
            return 1

        # Exit status code.
        exitStatus = 0

        # Were we started with a script or a module? Check to see if it's a
        # module. Note that this'll instantiate the module.
        with scopedVat(vat):
            debug_print("Instantiating module...")
            try:
                module = instantiateModule(result)
                # Hey, we've got a module! Run it.
                ruv.update_time(uv_loop)
                debug_print("Running module...")
                rv = runModule(module, scope)
            except UserException as ue:
                debug_print("Caught exception while instantiating:",
                            ue.formatError())
                return 1
        # Update loop timing information.
        ruv.update_time(uv_loop)
        try:
            runUntilDone(vatManager, uv_loop, recorder)
            rv = resolution(rv) if rv is not None else NullObject
            if isinstance(rv, IntObject):
                exitStatus = rv.getInt()
        except SystemExit as se:
            pass
            # Huh, apparently this doesn't work. Wonder why/why not.
            # exitStatus = se.code
        finally:
            recorder.stop()
            recorder.printResults()

    return exitStatus


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
