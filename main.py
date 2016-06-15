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
from rpython.rlib import rsignal
from rpython.rlib import rvmprof
from rpython.rlib.debug import debug_print
from rpython.rlib.jit import set_user_param

from typhon import rsodium, ruv
from typhon.arguments import Configuration
from typhon.debug import enableDebugPrint, TyphonJitHooks
from typhon.errors import LoadFailed, UserException
from typhon.importing import evaluateTerms, obtainModule
from typhon.log import log
from typhon.metrics import globalRecorder
from typhon.objects.auditors import deepFrozenGuard
from typhon.objects.collections.maps import ConstMap, monteMap, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject, unwrapStr
from typhon.objects.guards import anyGuard
from typhon.objects.refs import resolution
from typhon.objects.slots import finalBinding
from typhon.objects.timeit import benchmarkSettings
from typhon.prelude import registerGlobals
from typhon.profile import registerProfileTyphon
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
    scope.update(bootScope(config.libraryPaths, recorder))
    registerGlobals({u"Bool": scope[u"Bool"],
                     u"Bytes": scope[u"Bytes"],
                     u"Char": scope[u"Char"],
                     u"Double": scope[u"Double"],
                     u"Int": scope[u"Int"],
                     u"Str": scope[u"Str"],
                     u"Void": scope[u"Void"]})

    code = obtainModule(config.libraryPaths, "prelude", recorder)
    with recorder.context("Time spent in prelude"):
        result = evaluateTerms([code], scope)

    assert result is not None, "Prelude returned None"
    assert isinstance(result, ConstMap), "Prelude returned non-Map"

    prelude = {}
    for key, value in unwrapMap(result).items():
        s = unwrapStr(key)
        assert s.startswith(u"&&"), "Prelude key doesn't start with &&"
        prelude[s[2:]] = value
    log(["info", "prelude"], u"Loaded the prelude")
    return prelude


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
                        ruv.run(uv_loop, ruv.RUN_NOWAIT)
                    else:
                        # No more work to be done, so blocking is fine.
                        ruv.run(uv_loop, ruv.RUN_ONCE)
                except UserException as ue:
                    debug_print("Caught exception while reacting:",
                            ue.formatError())

        anyVatHasTurns = vatManager.anyVatHasTurns()


class profiling(object):

    def __init__(self, path, enabled):
        self.path = path
        self.enabled = enabled

    def __enter__(self):
        # We can only enter once, since we must register the profile handles,
        # and that is a one-time sort of thing.
        if not self.enabled:
            return

        self.handle = open(self.path, "wb")
        try:
            # Turn on vmprof, and *then* register the profile handles.
            rvmprof.enable(self.handle.fileno(), 0.00042)
            registerProfileTyphon()
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


def cleanUpEverything():
    """
    Put back any ambient-authority mutable global state that we may have
    altered.
    """

    try:
        ruv.TTYResetMode()
    except ruv.UVError as uve:
        print "ruv.TTYResetMode() failed:", uve.repr()


def runTyphon(argv):
    # Start metrics.
    recorder = globalRecorder()
    recorder.start()

    # Initialize libsodium.
    if rsodium.init() < 0:
        print "Couldn't initialize libsodium!"
        return 1

    config = Configuration(argv)

    if config.verbose:
        enableDebugPrint()

    config.enableLogging()

    if len(config.argv) < 2:
        print "No file provided?"
        return 1

    # Pass user configuration to the JIT.
    set_user_param(None, config.jit)

    # Intialize our loop.
    uv_loop = ruv.alloc_loop()

    # Usurp SIGPIPE, as libuv does not handle it.
    rsignal.pypysig_ignore(rsignal.SIGPIPE)

    # Initialize our first vat. It shall be immortal.
    vatManager = VatManager()
    vat = Vat(vatManager, uv_loop, checkpoints=-1)
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
    ss = scope.copy()
    reflectedSS = monteMap()
    for k, b in ss.iteritems():
        reflectedSS[StrObject(u"&&" + k)] = b
    ss[u"safeScope"] = finalBinding(ConstMap(reflectedSS), deepFrozenGuard)
    reflectedSS[StrObject(u"&&safeScope")] = ss[u"safeScope"]
    scope[u"safeScope"] = ss[u"safeScope"]
    scope.update(unsafeScope(config))
    reflectedUnsafeScope = monteMap()
    unsafeScopeDict = {}
    for k, b in scope.iteritems():
        reflectedUnsafeScope[StrObject(u"&&" + k)] = b
        unsafeScopeDict[k] = b
    rus = finalBinding(ConstMap(reflectedUnsafeScope), anyGuard)
    reflectedUnsafeScope[StrObject(u"&&unsafeScope")] = rus
    unsafeScopeDict[u"unsafeScope"] = rus
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
                result = evaluateTerms([code], unsafeScopeDict)
        if result is None:
            return 1

        # Exit status code.
        exitStatus = 0
        # Update loop timing information.
        ruv.update_time(uv_loop)
        try:
            runUntilDone(vatManager, uv_loop, recorder)
            rv = resolution(result) if result is not None else NullObject
            if isinstance(rv, IntObject):
                exitStatus = rv.getInt()
        except SystemExit:
            pass
            # Huh, apparently this doesn't work. Wonder why/why not.
            # exitStatus = se.code
        finally:
            recorder.stop()
            recorder.printResults()

    # Clean up and exit.
    cleanUpEverything()
    return exitStatus


def entryPoint(argv):
    """
    A wrapper that refuses to let errors pass silently.
    """

    try:
        return runTyphon(argv)
    except EnvironmentError as ee:
        print "RPython EnvironmentError:", ee.strerror, ee.filename
        print "If you can reproduce this, please send me a test case."
        raise
    except ruv.UVError as uve:
        print "RPython UVError:", uve.repr()
        print "If you can reproduce this, please send me a test case."
        raise


def jitpolicy(driver):
    return JitPolicy(TyphonJitHooks())


def target(driver, *args):
    driver.exe_name = "mt-typhon"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
