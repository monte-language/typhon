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

from typhon.objects.exceptions import unsealException
from typhon.objects.files import makeFileResource
from typhon.objects.networking.endpoints import (makeTCP4ClientEndpoint,
                                                 makeTCP4ServerEndpoint)
from typhon.objects.networking.stdio import makeStdErr, makeStdIn, makeStdOut
from typhon.objects.processes import CurrentProcess, makeProcess
from typhon.objects.timeit import bench
from typhon.objects.timers import Timer
from typhon.vats import CurrentVatProxy


def unsafeScope(config):
    return {
        u"Timer": Timer(),
        u"bench": bench(),
        u"currentProcess": CurrentProcess(config),
        u"currentVat": CurrentVatProxy(),
        u"makeFileResource": makeFileResource(),
        u"makeProcess": makeProcess(),
        u"makeStdErr": makeStdErr(),
        u"makeStdIn": makeStdIn(),
        u"makeStdOut": makeStdOut(),
        u"makeTCP4ClientEndpoint": makeTCP4ClientEndpoint(),
        u"makeTCP4ServerEndpoint": makeTCP4ServerEndpoint(),
        u"unsealException": unsealException(),
    }
