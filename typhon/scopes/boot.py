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
from typhon.objects.collections import ConstList, ConstMap, ConstSet
from typhon.objects.data import (CharObject, DoubleObject, IntObject,
                                 StrObject, wrapBool)
from typhon.objects.root import runnable


RUN_1 = getAtom(u"run", 1)


@runnable(RUN_1)
def isChar(args):
    return wrapBool(isinstance(args[0], CharObject))

@runnable(RUN_1)
def isDouble(args):
    return wrapBool(isinstance(args[0], DoubleObject))

@runnable(RUN_1)
def isInt(args):
    return wrapBool(isinstance(args[0], IntObject))

@runnable(RUN_1)
def isStr(args):
    return wrapBool(isinstance(args[0], StrObject))

@runnable(RUN_1)
def isList(args):
    return wrapBool(isinstance(args[0], ConstList))

@runnable(RUN_1)
def isMap(args):
    return wrapBool(isinstance(args[0], ConstMap))

@runnable(RUN_1)
def isSet(args):
    return wrapBool(isinstance(args[0], ConstSet))


def bootScope():
    return {
        u"isChar": isChar(),
        u"isDouble": isDouble(),
        u"isInt": isInt(),
        u"isStr": isStr(),

        u"isList": isList(),
        u"isMap": isMap(),
        u"isSet": isSet(),
    }
