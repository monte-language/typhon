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
from typhon.autohelp import autohelp
from typhon.env import finalize
from typhon.errors import Refused
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections import ConstMap, monteDict, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject, unwrapStr
from typhon.objects.root import Object
from typhon.objects.tests import UnitTest
from typhon.importing import evaluateTerms, instantiateModule, obtainModule


RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
SCRIPT_1 = getAtom(u"script", 1)
SCRIPT_2 = getAtom(u"script", 2)


@autohelp
class Import(Object):
    """
    An importer of foreign objects from faraway modules.

    The imported module automatically is granted a safe scope.
    """

    stamps = [deepFrozenStamp]

    def __init__(self, path, scope, recorder, testCollector):
        self.path = path
        self.scope = scope
        self.recorder = recorder
        self.testCollector = testCollector

    @dont_look_inside
    def performModule(self, path, importList=None):
        p = path.encode("utf-8")
        p += ".ty"

        term = obtainModule(rjoin(self.path, p), self.recorder)

        # Get module.
        module = evaluateTerms([term], finalize(self.scope))

        scope = monteDict()
        scope[StrObject(u"import")] = self
        scope[StrObject(u"unittest")] = UnitTest(path, self.testCollector)
        if importList is not None:
            assert isinstance(importList, ConstMap)
            scope.update(importList.objectMap)

        # Instantiate the module.
        mapping = instantiateModule(module, ConstMap(scope))

        if mapping is None:
            debug_print("Result was None :c")
            return NullObject
        return mapping

    @dont_look_inside
    def performScript(self, path, extraScope=None):
        p = path.encode("utf-8")
        p += ".ty"

        # Transitive imports.
        scope = addImportToScope(self.path, self.scope, self.recorder,
                                 self.testCollector)
        if extraScope is not None:
            scope.update(extraScope)

        scope[u'unittest'] = UnitTest(path, self.testCollector)
        # Attempt the import.
        term = obtainModule(rjoin(self.path, p), self.recorder)

        # Get results.
        result = evaluateTerms([term], finalize(scope))

        if result is None:
            debug_print("Result was None :c")
            return NullObject
        return result

    def recv(self, atom, args):
        if atom is RUN_1:
            path = unwrapStr(args[0])
            return self.performModule(path)

        if atom is RUN_2:
            path = unwrapStr(args[0])
            return self.performModule(path, importList=args[1])

        if atom is SCRIPT_1:
            path = unwrapStr(args[0])
            return self.performScript(path, None)

        if atom is SCRIPT_2:
            path = unwrapStr(args[0])
            scope = unwrapMap(args[1])

            d = {}
            for k, v in scope.items():
                d[unwrapStr(k)] = scope[k]

            return self.performScript(path, d)

        raise Refused(self, atom, args)


def addImportToScope(path, scope, recorder, testCollector):
    scope = scope.copy()
    scope[u"import"] = Import(path, scope, recorder, testCollector)
    return scope
