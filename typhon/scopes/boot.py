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

from typhon.atoms import getAtom
from typhon.env import finalize
from typhon.errors import Refused, userError
from typhon.importing import evaluateTerms, obtainModuleFromSource
from typhon.objects.auditors import deepFrozenStamp, transparentStamp
from typhon.objects.collections import (ConstList, ConstMap, ConstSet,
                                        unwrapList, unwrapMap)
from typhon.objects.constants import BoolObject, NullObject
from typhon.objects.guards import anyGuard
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject, unwrapInt, unwrapStr, wrapBool)
from typhon.objects.root import Object, runnable
from typhon.prelude import registerGlobals

RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


@runnable(RUN_1, [deepFrozenStamp])
def isBool(args):
    return wrapBool(isinstance(args[0], BoolObject))


@runnable(RUN_1, [deepFrozenStamp])
def isChar(args):
    return wrapBool(isinstance(args[0], CharObject))


@runnable(RUN_1, [deepFrozenStamp])
def isDouble(args):
    return wrapBool(isinstance(args[0], DoubleObject))


@runnable(RUN_1, [deepFrozenStamp])
def isInt(args):
    return wrapBool(isinstance(args[0], IntObject)
                    or isinstance(args[0], BigInt))


@runnable(RUN_1, [deepFrozenStamp])
def isStr(args):
    return wrapBool(isinstance(args[0], StrObject))


@runnable(RUN_1, [deepFrozenStamp])
def isList(args):
    return wrapBool(isinstance(args[0], ConstList))


@runnable(RUN_1, [deepFrozenStamp])
def isMap(args):
    return wrapBool(isinstance(args[0], ConstMap))


@runnable(RUN_1, [deepFrozenStamp])
def isSet(args):
    return wrapBool(isinstance(args[0], ConstSet))


class TyphonEval(Object):

    def __init__(self, recorder):
        self.recorder = recorder

    def recv(self, atom, args):
        if atom is RUN_2:
            source = "".join([chr(unwrapInt(i)) for i in unwrapList(args[0])])
            environment = {}
            for k, v in unwrapMap(args[1]).items():
                environment[unwrapStr(k)] = v
            code = obtainModuleFromSource(source, environment.keys(),
                                          self.recorder)
            result = evaluateTerms([code], finalize(environment))
            if result is None:
                raise userError(u"Error while evaluating dynamic source")
            return result

        raise Refused(self, atom, args)


@runnable(RUN_1)
def installAstBuilder(args):
    registerGlobals({u"astBuilder": args[0]})
    return NullObject

registerGlobals({u"astBuilder": NullObject})


def bootScope(recorder):
    return {
        u"isBool": isBool(),
        u"isChar": isChar(),
        u"isDouble": isDouble(),
        u"isInt": isInt(),
        u"isStr": isStr(),

        u"isList": isList(),
        u"isMap": isMap(),
        u"isSet": isSet(),

        u"DeepFrozenStamp": deepFrozenStamp,
        u"TransparentStamp": transparentStamp,

        u"typhonEval": TyphonEval(recorder),
        u"_installASTBuilder": installAstBuilder(),
    }
