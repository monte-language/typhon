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

from typhon.atoms import getAtom
from typhon.env import finalize
from typhon.errors import Refused
from typhon.objects.collections import unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr
from typhon.objects.root import Object
from typhon.importing import evaluateTerms, obtainModule


RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


class Import(Object):

    def __init__(self, path, scope, recorder):
        self.path = path
        self.scope = scope
        self.recorder = recorder

    @dont_look_inside
    def performImport(self, path, extraScope=None):
        p = path.encode("utf-8")
        p += ".ty"

        # Transitive imports.
        scope = addImportToScope(self.path, self.scope, self.recorder)
        if extraScope is not None:
            scope.update(extraScope)

        # Attempt the import.
        term = obtainModule(rjoin(self.path, p), scope.keys(),
                            self.recorder)

        # Get results.
        with self.recorder.context("Time spent in vats"):
            result = evaluateTerms([term], finalize(scope))

        if result is None:
            debug_print("Result was None :c")
            return NullObject
        return result

    def recv(self, atom, args):
        if atom is RUN_1:
            path = unwrapStr(args[0])
            return self.performImport(path, None)

        if atom is RUN_2:
            path = unwrapStr(args[0])
            scope = unwrapMap(args[1])

            d = {}
            for k, v in scope.items():
                d[unwrapStr(k)] = scope[k]

            return self.performImport(path, d)

        raise Refused(self, atom, args)


def addImportToScope(path, scope, recorder):
    scope = scope.copy()
    scope[u"import"] = Import(path, scope, recorder)
    return scope
