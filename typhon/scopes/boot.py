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
from typhon.errors import userError
from typhon.importing import AstModule, obtainModule
from typhon.load.nano import loadMASTBytes as realLoad
from typhon.nano.mast import ASTWrapper, BuildKernelNodes, theASTBuilder
from typhon.nano.interp import (evalToPair as astEvalToPair,
                                scope2env)
from typhon.nodes import Expr, kernelAstStamp
from typhon.objects.auditors import (deepFrozenStamp, semitransparentStamp,
                                     transparentStamp)
from typhon.objects.collections.lists import ConstList
from typhon.objects.collections.maps import ConstMap
from typhon.objects.collections.sets import ConstSet
from typhon.objects.data import unwrapBytes, wrapBool
from typhon.objects.guards import (BoolGuard, BytesGuard, CharGuard,
                                   DoubleGuard, IntGuard, StrGuard, VoidGuard)
from typhon.objects.slots import finalize
from typhon.objects.root import Object, audited, runnable
from typhon.profile import profileTyphon

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
    assert isinstance(source, bytes)
    mod = AstModule(recorder, u"<eval>")
    mod.load(source)
    return mod


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
                        mod = AstModule(self.recorder, pname)
                        mod.load(source)
                        return mod
                except IOError:
                    continue
        raise userError(u"Could not locate " + pname)

    @method("Any", "Str", "Map", _verb="run")
    def _run(self, pname, scope):
        module = obtainModule(self.paths, self.recorder, pname.encode("utf-8"))
        return module.eval(scope2env(scope))[0]


@autohelp
@audited.DF
class AstEval(Object):

    def __init__(self, recorder):
        self.recorder = recorder

    @method("Any", "Any", "Any", "Str")
    @profileTyphon("typhonAstEval.run/3")
    def run(self, ast, scope, filename):
        if not isinstance(ast, ASTWrapper.Expr):
            raise userError(u"Expected a Typhon kernel AST expression")
        return astEvalToPair(ast._ast, scope, filename, False)[0]

    @method("List", "Any", "Any", "Str", inRepl="Bool")
    def evalToPair(self, ast, scope, filename, inRepl=False):
        if not isinstance(ast, ASTWrapper.Expr):
            raise userError(u"Expected a Typhon kernel AST expression")
        result, envMap = astEvalToPair(ast._ast, scope, filename, inRepl)
        return [result, envMap]


@autohelp
@audited.DF
class AstEval0(Object):

    def __init__(self, recorder):
        self.recorder = recorder

    @method("Any", "Any", "Any")
    @profileTyphon("typhonAstEval.run/2")
    def run(self, bs, scope):
        ast = realLoad(unwrapBytes(bs))
        return astEvalToPair(ast, scope, u"<eval>")[0]

    @method("List", "Any", "Any", inRepl="Bool")
    def evalToPair(self, bs, scope, inRepl=False):
        ast = realLoad(unwrapBytes(bs))
        result, envMap = astEvalToPair(ast, scope, u"<eval>", inRepl)
        return [result, envMap]


@runnable(RUN_1, [deepFrozenStamp])
def loadMAST(bs):
    return BuildKernelNodes().visitExpr(realLoad(unwrapBytes(bs)))


@runnable(RUN_1, [deepFrozenStamp])
def loadMAST(bs):
    return BuildKernelNodes().visitExpr(realLoad(unwrapBytes(bs)))


def bootScope(paths, recorder):
    """
    "A beginning is the time for taking the most delicate care that the
     balances are correct."
    """

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
        u"SemitransparentStamp": semitransparentStamp,

        u"getMonteFile": GetMonteFile(paths, recorder),
        u"loadMAST": loadMAST(),
        u"typhonAstEval": ae,
        u"typhonAstBuilder": theASTBuilder,
        u"astEval": AstEval0(recorder)
    })
