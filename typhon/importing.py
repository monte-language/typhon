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
from typhon.atoms import getAtom
from typhon.debug import debugPrint
from typhon.errors import Refused, UserException, userError
from typhon.load.mast import InvalidMAST, loadMASTBytes
from typhon.load.trash import load
from typhon.nodes import Sequence, interactiveCompile
from typhon.objects.collections.maps import ConstMap
from typhon.objects.collections.helpers import monteMap
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr
from typhon.objects.root import Object
from typhon.smallcaps.machine import SmallCaps
from typhon.smallcaps.peephole import peephole

IMPORT_1 = getAtom(u"import", 1)


class ModuleCache(object):
    """
    A necessary evil.
    """

    def __init__(self):
        self.cache = {}

moduleCache = ModuleCache()


class PackageEnv(Object):
    """
    A transitional object that provides something like the package-environment
    interface we want.
    """
    def __init__(self, importer, importList):
        self.importer = importer
        self.importList = importList

    def recv(self, atom, args):
        if atom is IMPORT_1:
            path = unwrapStr(args[0])
            # this is a hack, but the whole class is a hack :)
            if path == u"unittest":
                d = monteMap()
                d[args[0]] = self.importList.call(u"get", args)
                return ConstMap(d)
            return self.importer.performModule(path, self.importList)
        raise Refused(self, atom, args)


@dont_look_inside
def obtainModuleFromSource(source, recorder, origin):
    with recorder.context("Deserialization"):
        try:
            term = loadMASTBytes(source)
        except InvalidMAST as im:
            print "Load (mast) failed:", im
            term = Sequence(load(source)[:])

    with recorder.context("Compilation"):
        code, topLocals = interactiveCompile(term, origin)
    # debug_print("Compiled code:", code.disassemble())

    with recorder.context("Optimization"):
        peephole(code)
    # if origin == u"<eval>":
    #     debug_print("Optimized code:", code.disassemble())

    return code, topLocals


def tryExtensions(filePath, recorder):
    ### for extension in unrolling_iterable([".ty", ".mast"]):
    for extension in [".ty", ".mast"]:
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


def instantiateModule(importer, module, importList=None):
    """
    Instantiate a top-level module.
    """
    return module.call(u"run", [PackageEnv(importer, importList)],
                       namedArgs=importList)
