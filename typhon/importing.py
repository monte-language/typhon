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
from rpython.rlib.rpath import rjoin

from typhon import log
from typhon.debug import debugPrint
from typhon.errors import UserException, userError
from typhon.load.mast import loadMASTBytes
from typhon.nodes import Expr, interactiveCompile
from typhon.objects.constants import NullObject
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
def obtainModuleFromSource(source, recorder, origin):
    with recorder.context("Deserialization"):
        term = loadMASTBytes(source)
    return codeFromAst(term, recorder, origin)


@dont_look_inside
def codeFromAst(term, recorder, origin):
    if not isinstance(term, Expr):
        raise userError(u"A kernel-AST expression node is required")
    with recorder.context("Compilation"):
        code, topLocals = interactiveCompile(term, origin)
    # debug_print("Compiled code:", code.disassemble())

    with recorder.context("Optimization"):
        peephole(code)
    # if origin == u"<eval>":
    #     debug_print("Optimized code:", code.disassemble())

    return code, topLocals


def tryExtensions(filePath, recorder):
    # Leaving this in loop form in case we change formats again.
    for extension in [".mast"]:
        path = filePath + extension
        try:
            with open(path, "rb") as handle:
                debugPrint("Reading:", path)
                source = handle.read()
                return obtainModuleFromSource(source, recorder,
                                              path.decode('utf-8'))[0]
        except IOError:
            continue
    return None


def obtainModule(libraryPaths, filePath, recorder):
    for libraryPath in libraryPaths:
        path = rjoin(libraryPath, filePath)

        if path in moduleCache.cache:
            log.log(["import"], u"Importing %s (cached)" %
                    path.decode("utf-8"))
            return moduleCache.cache[path]

        log.log(["import"], u"Importing %s" % path.decode("utf-8"))
        code = tryExtensions(path, recorder)
        if code is None:
            continue

        # Cache.
        moduleCache.cache[path] = code
        return code
    else:
        log.log(["import", "error"], u"Failed to import from %s" %
                filePath.decode("utf-8"))
        debugPrint("Failed to import:", filePath)
        raise userError(u"Module '%s' couldn't be found" %
                        filePath.decode("utf-8"))


def evaluateTerms(codes, scope):
    result = NullObject
    for code in codes:
        try:
            machine = SmallCaps.withDictScope(code, scope)
            machine.run()
            result = machine.pop()
        except UserException as ue:
            debug_print("Caught exception:", ue.formatError())
    return result


def evaluateRaise(codes, scope):
    """
    Like evaluateTerms, but does not catch exceptions.
    """

    machine = None
    result = NullObject
    for code in codes:
        machine = SmallCaps.withDictScope(code, scope)
        machine.run()
        result = machine.pop()
    return result, machine
