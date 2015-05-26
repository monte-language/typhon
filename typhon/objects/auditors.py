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

from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.root import Object, runnable

AUDIT_1 = getAtom(u"audit", 1)
COERCE_2 = getAtom(u"coerce", 2)
RUN_2 = getAtom(u"run", 2)


@runnable(RUN_2)
def auditedBy(args):
    auditor = args[0]
    specimen = args[1]

    return specimen.auditedBy(auditor)


class DeepFrozenStamp(Object):

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        if atom is AUDIT_1:
            return wrapBool(True)
        raise Refused(self, atom, args)

deepFrozenStamp = DeepFrozenStamp()
