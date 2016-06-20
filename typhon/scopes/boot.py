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
from typhon.autohelp import autohelp, method
from typhon.errors import LoadFailed, Refused, userError
from typhon.importing import (smallcapsFromAst, obtainModule,
                              obtainModuleFromSource)
from typhon.load.mast import loadMASTBytes
from typhon.load.nano import loadMASTBytes as realLoad
from typhon.nano.interp import (evalMonte, evalToPair as astEvalToPair,
                                scope2env)
from typhon.nodes import kernelAstStamp
from typhon.objects.auditors import deepFrozenStamp, transparentStamp
from typhon.objects.collections.lists import ConstList
from typhon.objects.collections.maps import ConstMap, monteMap
from typhon.objects.collections.sets import ConstSet
from typhon.objects.data import StrObject, unwrapBytes, wrapBool, unwrapStr
from typhon.objects.guards import (BoolGuard, BytesGuard, CharGuard,
                                   DoubleGuard, IntGuard, StrGuard, VoidGuard)
from typhon.objects.slots import Binding, finalize
from typhon.objects.root import Object, audited, runnable
from typhon.profile import profileTyphon
from typhon.smallcaps.machine import evaluateRaise

RUN_1 = getAtom(u"run", 1)


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


def evalToPair(code, topLocals, envMap):
    assert isinstance(envMap, ConstMap), "Implementation error"
    environment = {}
    for k, v in envMap.iteritems():
        s = unwrapStr(k)
        if not s.startswith("&&") or not isinstance(v, Binding):
            raise userError(u"scope map must be of the "
                            "form '[\"&&name\" => binding]'")
        environment[s[2:]] = v
    # Don't catch user exceptions; on traceback, we'll have a trail
    # auto-added that indicates that the exception came through
    # eval() or whatnot.
    result, machine = evaluateRaise([code], environment)
    if machine is not None:
        # XXX monteMap()
        d = monteMap()
        for k, vi in topLocals.items():
            d[StrObject(u"&&" + k)] = machine.local[vi]
        envMap = ConstMap(d).call(u"or", [envMap])
    return result, envMap


@autohelp
@audited.DF
class SmallCapsEval(Object):

    def __init__(self, recorder):
        self.recorder = recorder

    @method("Any", "Any", "Any", "Str")
    @profileTyphon("smallcapsEval.fromAST/3")
    def fromAST(self, ast, scope, name):
        code, topLocals = smallcapsFromAst(ast, self.recorder, name)
        return evalToPair(code, topLocals, scope)[0]

    # @method("Any", "Any", "Any")
    # @profileTyphon("smallcapsEval.run/2")
    # def run(self, bs, scope):
    #     code, topLocals = moduleFromString(bs, self.recorder)
    #     return evalToPair(code, topLocals, scope)[0]

    # @method("List", "Any", "Any")
    # @profileTyphon("smallcapsEval.evalToPair/2")
    # def evalToPair(self, bs, scope):
    #     code, topLocals = moduleFromString(bs, self.recorder)
    #     result, envMap = evalToPair(code, topLocals, scope)
    #     return [result, envMap]


@autohelp
@audited.DF
class GetMonteFile(Object):
    def __init__(self, paths, recorder):
        self.paths = paths
        self.recorder = recorder

    @method("Any", "Str")
    def run(self, pname):
        for extension in [".ty", ".mast"]:
            path = pname.encode("utf-8") + extension
            for base in self.paths:
                try:
                    with open(os.path.join(base, path), "rb") as handle:
                        source = handle.read()
                        with self.recorder.context("Deserialization"):
                            return loadMASTBytes(source)
                except IOError:
                    continue
        raise userError(u"Could not locate " + pname)

    @method("Any", "Str", "Map", _verb="run")
    def _run(self, pname, scope):
        code = obtainModule(self.paths, pname.encode("utf-8"), self.recorder)
        return evalMonte(code, scope2env(scope))[0]


@autohelp
@audited.DF
class AstEval(Object):

    def __init__(self, recorder):
        self.recorder = recorder

    @method("Any", "Any", "Any")
    @profileTyphon("astEval.run/2")
    def run(self, bs, scope):
        ast = realLoad(unwrapBytes(bs))
        return astEvalToPair(ast, scope)[0]

    @method("List", "Any", "Any")
    def evalToPair(self, bs, scope):
        ast = realLoad(unwrapBytes(bs))
        result, envMap = astEvalToPair(ast, scope)
        return [result, envMap]


def bootScope(paths, recorder):
    """
    "A beginning is the time for taking the most delicate care that the
     balances are correct."
    """
    sce = SmallCapsEval(recorder)
    ae = AstEval(recorder)
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
        u"smallcapsEval": sce,
        u"astEval": ae
    })
