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

from rpython.rlib.jit import dont_look_inside
from rpython.rlib.rpath import rjoin

from typhon import log
from typhon.debug import debugPrint
from typhon.errors import LoadFailed, userError
from typhon.load.mast import loadMASTBytes
from typhon.load.nano import loadMASTBytes as nanoLoad
from typhon.nano.interp import evalMonte
from typhon.nodes import Expr, interactiveCompile
from typhon.objects.collections.lists import ConstList
from typhon.objects.root import Object
from typhon.smallcaps.peephole import peephole


class ModuleCache(object):
    """
    A necessary evil.
    """

    def __init__(self):
        self.cache = {}

moduleCache = ModuleCache()


def tryExtensions(filePath, recorder):
    # Leaving this in loop form in case we change formats again.
    for extension in [".mast"]:
        path = filePath + extension
        try:
            with open(path, "rb") as handle:
                debugPrint("Reading:", path)
                source = handle.read()
                mod = AstModule(recorder, path.decode('utf-8'))
                mod.load(source)
                return mod
        except IOError:
            continue
    return None


def obtainModule(libraryPaths, recorder, filePath):
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


class Module(Object):
    def __init__(self, recorder, origin):
        self.recorder = recorder
        self.origin = origin
        self.astSource = None
        self.smallcapsSource = None
        self.locals = {}


class AstModule(Module):
    def load(self, source):
        with self.recorder.context("Deserialization"):
            self.astSource = nanoLoad(source)

    @dont_look_inside
    def eval(self, env):
            return evalMonte(self.astSource, env, self.origin)


class SmallcapsModule(Module):
    def load(self, source):
        try:
            with self.recorder.context("Deserialization"):
                term = loadMASTBytes(source)
            if not isinstance(term, Expr):
                raise userError(u"A kernel-AST expression node is required")
        except LoadFailed:
            raise userError(u"Couldn't load invalid AST")
        return self.crunch(term)

    def crunch(self, term):
        with self.recorder.context("Compilation"):
            code, topLocals = interactiveCompile(term, self.origin)
        with self.recorder.context("Optimization"):
            peephole(code)
        self.smallcapsSource = code
        self.local = topLocals

    @dont_look_inside
    def eval(self, env):
        from typhon.scopes.boot import evalToPair
        return evalToPair(self.smallcapsSource, self.locals, env)
