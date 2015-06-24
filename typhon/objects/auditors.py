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
PASSES_1 = getAtom(u"passes", 1)
RUN_2 = getAtom(u"run", 2)


class DeepFrozenStamp(Object):
    """
    DeepFrozen's stamp.
    """

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        if atom is AUDIT_1:
            return wrapBool(True)
        raise Refused(self, atom, args)

deepFrozenStamp = DeepFrozenStamp()


@runnable(RUN_2, [deepFrozenStamp])
def auditedBy(args):
    """
    Whether an auditor has audited a specimen.
    """

    auditor = args[0]
    specimen = args[1]

    from typhon.objects.constants import wrapBool
    return wrapBool(specimen.auditedBy(auditor))


class TransparentStamp(Object):
    """
    Transparent's stamp.
    """

    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        if atom is AUDIT_1:
            return wrapBool(True)
        raise Refused(self, atom, args)

transparentStamp = TransparentStamp()


class TransparentGuard(Object):
    """
    Transparent's guard.
    """

    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        from typhon.objects.constants import NullObject
        if atom is PASSES_1:
            return wrapBool(transparentStamp in args[0].stamps)
        if atom is COERCE_2:
            if transparentStamp in args[0].stamps:
                return args[0]
            args[1].call("run", [NullObject])
            return NullObject
        raise Refused(self, atom, args)


class Selfless(Object):
    """
    An auditor over altruistic objects.

    Selfless objects are not yet well-defined.
    """

    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        from typhon.objects.constants import NullObject
        if atom is AUDIT_1:
            return wrapBool(True)
        if atom is PASSES_1:
            return wrapBool(selfless in args[0].stamps)
        if atom is COERCE_2:
            if selfless in args[0].stamps:
                return args[0]
            args[1].call(u"run", [NullObject])
            return NullObject
        raise Refused(self, atom, args)

selfless = Selfless()
