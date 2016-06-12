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
import os

from typhon.autohelp import autohelp, method
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.exceptions import unsealException
from typhon.objects.files import makeFileResource
from typhon.objects.networking.dns import getAddrInfo
from typhon.objects.networking.endpoints import (makeTCP4ClientEndpoint,
                                                 makeTCP4ServerEndpoint)
from typhon.objects.networking.stdio import makeStdErr, makeStdIn, makeStdOut
from typhon.objects.processes import CurrentProcess, makeProcess
from typhon.objects.root import Object, audited
from typhon.objects.runtime import CurrentRuntime
from typhon.objects.slots import finalize
from typhon.objects.timeit import bench
from typhon.objects.timers import Timer
from typhon.vats import CurrentVatProxy


@autohelp
@audited.DF
class FindTyphonFile(Object):
    def __init__(self, paths):
        self.paths = paths

    @method("Any", "Str")
    def run(self, pname):
        for extension in [".ty", ".mast"]:
            path = pname.encode("utf-8") + extension
            for base in self.paths:
                fullpath = os.path.join(base, path)
                if os.path.exists(fullpath):
                    return StrObject(fullpath.decode("utf-8"))
        return NullObject


def unsafeScope(config):
    return finalize({
        u"Timer": Timer(),
        u"bench": bench(),
        u"currentProcess": CurrentProcess(config),
        u"currentRuntime": CurrentRuntime(),
        u"currentVat": CurrentVatProxy(),
        u"_findTyphonFile": FindTyphonFile(config.libraryPaths),
        u"getAddrInfo": getAddrInfo(),
        u"makeFileResource": makeFileResource(),
        u"makeProcess": makeProcess(),
        u"makeStdErr": makeStdErr(),
        u"makeStdIn": makeStdIn(),
        u"makeStdOut": makeStdOut(),
        u"makeTCP4ClientEndpoint": makeTCP4ClientEndpoint(),
        u"makeTCP4ServerEndpoint": makeTCP4ServerEndpoint(),
        u"unsealException": unsealException(),
    })
