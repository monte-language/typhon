# Copyright (C) 2015 Google Inc. All rights reserved.
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

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.env import finalize
from typhon.errors import LoadFailed, Refused, userError
from typhon.importing import (codeFromAst, evaluateRaise, obtainModule,
                              obtainModuleFromSource)
from typhon.load.mast import InvalidMAST, loadMASTBytes
from typhon.load.trash import load
from typhon.nodes import Sequence, kernelAstStamp
from typhon.objects.auditors import deepFrozenStamp, transparentStamp
from typhon.objects.collections.lists import ConstList
from typhon.objects.collections.maps import ConstMap, monteMap, unwrapMap
from typhon.objects.collections.sets import ConstSet
from typhon.objects.data import StrObject, unwrapBytes, wrapBool, unwrapStr
from typhon.objects.guards import (BoolGuard, BytesGuard, CharGuard,
                                   DoubleGuard, IntGuard, StrGuard, VoidGuard)
from typhon.objects.root import Object, audited, runnable
from typhon.objects.tests import UnitTest

EVALTOPAIR_2 = getAtom(u"evalToPair", 2)
FROMAST_3 = getAtom(u"fromAST", 3)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


@runnable(RUN_1, [deepFrozenStamp])
def isList(specimen):
    return wrapBool(isinstance(specimen, ConstList))


@runnable(RUN_1, [deepFrozenStamp])
def isMap(specimen):
    return wrapBool(isinstance(specimen, ConstMap))


@runnable(RUN_1, [deepFrozenStamp])
def isSet(specimen):
    return wrapBool(isinstance(specimen, ConstSet))


def moduleFromString(source, recorder):
    source = unwrapBytes(source)

    # *Do* catch this particular exception, as it is not a
    # UserException and thus will kill the process (!!!) if allowed to
    # propagate. ~ C.
    try:
        code, topLocals = obtainModuleFromSource(source, recorder, u"<eval>")
    except LoadFailed:
        raise userError(u"Couldn't load invalid AST")
    return code, topLocals


def evalToPair(code, topLocals, envMap, bindingNames=False):
    environment = {}
    if bindingNames:
        for k, v in unwrapMap(envMap).items():
            s = unwrapStr(k)
            if not s.startswith("&&"):
                raise userError(u"evalMonteFile scope map must be of the "
                                "form '[\"&&name\" => binding]'")
            environment[s[2:]] = v
    else:
        for k, v in unwrapMap(envMap).items():
            environment[unwrapStr(k)] = v
    # Don't catch user exceptions; on traceback, we'll have a trail
    # auto-added that indicates that the exception came through
    # eval() or whatnot.
    result, newEnv = evaluateRaise([code], environment)
    if newEnv is not None:
        # XXX monteMap()
        d = monteMap()
        for k, vi in topLocals.items():
            # Wow, rude.
            d[StrObject(k)] = newEnv.local[vi].getBinding()
        addendum = ConstMap(d)
        envMap = addendum._or(envMap)
    return result, envMap


@autohelp
@audited.DF
class TyphonEval(Object):

    def __init__(self, recorder):
        self.recorder = recorder

    def recv(self, atom, args):
        if atom is FROMAST_3:
            code, topLocals = codeFromAst(args[0], self.recorder,
                                          unwrapStr(args[2]))
            return evalToPair(code, topLocals, args[1], True)[0]
        if atom is RUN_2:
            code, topLocals = moduleFromString(args[0], self.recorder)
            return evalToPair(code, topLocals, args[1])[0]
        if atom is EVALTOPAIR_2:
            code, topLocals = moduleFromString(args[0], self.recorder)
            result, envMap = evalToPair(code, topLocals, args[1])
            return ConstList([result, envMap])
        raise Refused(self, atom, args)


@autohelp
@audited.DF
class GetMonteFile(Object):
    def __init__(self, paths, recorder):
        self.paths = paths
        self.recorder = recorder

    def recv(self, atom, args):
        if atom is RUN_1:
            pname = unwrapStr(args[0])
            for extension in [".ty", ".mast"]:
                path = pname.encode("utf-8") + extension
                for base in self.paths:
                    try:
                        with open(os.path.join(base, path), "rb") as handle:
                            source = handle.read()
                            with self.recorder.context("Deserialization"):
                                try:
                                    term = loadMASTBytes(source)
                                except InvalidMAST as im:
                                    print "Load (mast) failed:", im
                                    term = Sequence(load(source)[:])
                                return term
                    except IOError:
                        continue
            raise userError(u"Could not locate " + pname)

        if atom is RUN_2:
            scope = unwrapMap(args[1])
            d = {}
            for k, v in scope.items():
                s = unwrapStr(k)
                if not s.startswith("&&"):
                    raise userError(u"evalMonteFile scope map must be of the "
                                    "form '[\"&&name\" => binding]'")
                d[s[2:]] = scope[k]

            code = obtainModule(self.paths, unwrapStr(args[0]).encode("utf-8"),
                                self.recorder)
            return evaluateRaise([code], d)[0]
        raise Refused(self, atom, args)


def bootScope(paths, recorder, collectTests):
    """
    "A beginning is the time for taking the most delicate care that the
     balances are correct."
    """
    return finalize({
        u"isList": isList(),
        u"isMap": isMap(),
        u"isSet": isSet(),
        u"Bool": BoolGuard(),
        u"Bytes": BytesGuard(),
        u"Char": CharGuard(),
        u"Double": DoubleGuard(),
        u"Int": IntGuard(),
        u"Str": StrGuard(),
        u"Void": VoidGuard(),

        u"KernelAstStamp": kernelAstStamp,

        u"DeepFrozenStamp": deepFrozenStamp,
        u"TransparentStamp": transparentStamp,

        u"getMonteFile": GetMonteFile(paths, recorder),
        u"typhonEval": TyphonEval(recorder),
        u"unittest": UnitTest(u"<boot>", collectTests),
    })
