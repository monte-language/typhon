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
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.root import Object, runnable


AUDIT_1 = getAtom(u"audit", 1)
COERCE_2 = getAtom(u"coerce", 2)
PASSES_1 = getAtom(u"passes", 1)
RUN_2 = getAtom(u"run", 2)


@autohelp
class DeepFrozenStamp(Object):
    """
    DeepFrozen's stamp.
    """

    def recv(self, atom, args):
        from typhon.objects.data import StrObject
        if atom is AUDIT_1:
            from typhon.objects.constants import wrapBool
            return wrapBool(True)
        if atom is COERCE_2:
            if args[0].auditedBy(self):
                return args[0]
            args[1].call(u"run", [StrObject(u"Not DeepFrozen")])
        raise Refused(self, atom, args)

deepFrozenStamp = DeepFrozenStamp()
deepFrozenStamp.stamps = [deepFrozenStamp]


@runnable(RUN_2, [deepFrozenStamp])
def auditedBy(args):
    """
    Whether an auditor has audited a specimen.
    """
    from typhon.objects.refs import resolution

    auditor = args[0]
    specimen = args[1]

    from typhon.objects.constants import wrapBool
    return wrapBool(resolution(specimen).auditedBy(auditor))


@autohelp
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


@autohelp
class TransparentGuard(Object):
    """
    Transparent's guard.
    """

    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool, NullObject
        if atom is PASSES_1:
            return wrapBool(args[0].auditedBy(transparentStamp))

        if atom is COERCE_2:
            if args[0].auditedBy(transparentStamp):
                return args[0]
            from typhon.objects.ejectors import throw
            throw(args[1], NullObject)
            return NullObject

        raise Refused(self, atom, args)


@autohelp
class Selfless(Object):
    """A stamp for objects that do not wish to be compared by identity.

    Selfless objects are not comparable with == unless they implement some
    protocol for comparison (such as Transparent).
    """

    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        from typhon.objects.constants import NullObject
        if atom is AUDIT_1:
            return wrapBool(True)

        if atom is PASSES_1:
            return wrapBool(args[0].auditedBy(selfless))

        if atom is COERCE_2:
            if args[0].auditedBy(selfless):
                return args[0]
            from typhon.objects.ejectors import throw
            throw(args[1], NullObject)
            return NullObject

        raise Refused(self, atom, args)

selfless = Selfless()
