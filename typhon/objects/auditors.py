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
from typhon.errors import Ejecting, Refused, userError
# Can't use audited, even thought it's importable; calling it causes a circle.
from typhon.objects.root import Object, runnable
from typhon.profile import profileTyphon


AUDIT_1 = getAtom(u"audit", 1)
COERCE_2 = getAtom(u"coerce", 2)
PASSES_1 = getAtom(u"passes", 1)
RUN_2 = getAtom(u"run", 2)
SUPERSETOF_1 = getAtom(u"supersetOf", 1)


@autohelp
class DeepFrozenStamp(Object):
    """
    DeepFrozen's stamp.
    """

    def auditorStamps(self):
        # Have you ever felt that sense of mischief and wonder as much as when
        # looking at this line? ~ C.
        return [self]

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


@runnable(RUN_2, [deepFrozenStamp])
def auditedBy(auditor, specimen):
    """
    Whether an auditor has audited a specimen.
    """
    from typhon.objects.refs import resolution
    from typhon.objects.constants import wrapBool
    return wrapBool(resolution(specimen).auditedBy(auditor))


@autohelp
class TransparentStamp(Object):
    """
    Transparent's stamp.
    """

    def auditorStamps(self):
        return [deepFrozenStamp]

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

    def auditorStamps(self):
        return [deepFrozenStamp]

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
    """
    A stamp for incomparable objects.

    `Selfless` objects are generally not equal to any objects but themselves.
    They may choose to implement alternative comparison protocols such as
    `Transparent`.
    """

    def auditorStamps(self):
        return [deepFrozenStamp]

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


def checkDeepFrozen(specimen, seen, ej, root):
    from typhon.objects.collections.lists import ConstList
    from typhon.objects.collections.maps import ConstMap
    from typhon.objects.data import StrObject
    from typhon.objects.equality import TraversalKey
    from typhon.objects.refs import Promise, isBroken
    key = TraversalKey(specimen)
    if key in seen:
        return
    seen[key] = None
    if isinstance(specimen, Promise):
        specimen = specimen.resolution()
    if specimen.auditedBy(deepFrozenStamp):
        return
    elif isBroken(specimen):
        checkDeepFrozen(specimen.optProblem(), seen, ej, root)
        return
    elif (specimen.auditedBy(selfless) and
          specimen.auditedBy(transparentStamp)):
        portrayal = specimen.call(u"_uncall", [])
        if not (isinstance(portrayal, ConstList) and
                portrayal.size() == 4):
            ej.call(u"run", [StrObject(u"can't happen: transparent object "
                                       "gave bad portrayal")])
            return
        checkDeepFrozen(portrayal.strategy.fetch(portrayal, 0), seen, ej, root)
        checkDeepFrozen(portrayal.strategy.fetch(portrayal, 1), seen, ej, root)
        args = portrayal.strategy.fetch(portrayal, 2)
        if not isinstance(args, ConstList):
            ej.call(u"run", [StrObject(u"can't happen: transparent object "
                                       "gave bad portrayal")])
            return
        for item in args.strategy.fetch_all(args):
            checkDeepFrozen(item, seen, ej, root)
        namedArgs = portrayal.strategy.fetch(portrayal, 3)
        if not isinstance(namedArgs, ConstMap):
            ej.call(u"run", [StrObject(u"can't happen: transparent object "
                                       "gave bad portrayal")])
            return
        for k, v in namedArgs.objectMap.iteritems():
            checkDeepFrozen(k, seen, ej, root)
            checkDeepFrozen(v, seen, ej, root)
    else:
        if specimen is root:
            ej.call(u"run", [StrObject(root.toQuote() +
                                       u" is not DeepFrozen")])
        else:
            ej.call(u"run", [StrObject(root.toQuote() +
                                       u" is not DeepFrozen because " +
                                       specimen.toQuote() + u"is not")])


def deepFrozenSupersetOf(guard):
    from typhon.objects.collections.helpers import monteMap
    from typhon.objects.collections.lists import ConstList
    from typhon.objects.constants import wrapBool
    from typhon.objects.ejectors import Ejector
    from typhon.objects.refs import Promise
    from typhon.objects.guards import (
        AnyOfGuard, BoolGuard, BytesGuard, CharGuard, DoubleGuard,
        FinalSlotGuard, IntGuard, SameGuard, StrGuard, SubrangeGuard,
        VoidGuard)
    from typhon.prelude import getGlobalValue
    if guard is deepFrozenGuard:
        return True
    if guard is deepFrozenStamp:
        return True
    if isinstance(guard, Promise):
        guard = guard.resolution()
    if isinstance(guard, BoolGuard):
        return True
    if isinstance(guard, BytesGuard):
        return True
    if isinstance(guard, CharGuard):
        return True
    if isinstance(guard, DoubleGuard):
        return True
    if isinstance(guard, IntGuard):
        return True
    if isinstance(guard, StrGuard):
        return True
    if isinstance(guard, VoidGuard):
        return True

    if isinstance(guard, SameGuard):
        ej = Ejector()
        try:
            v = guard.value
            checkDeepFrozen(v, monteMap(), ej, v)
            return True
        except Ejecting:
            return False

    if isinstance(guard, FinalSlotGuard):
        return deepFrozenSupersetOf(guard.valueGuard)
    for superGuardName in [u"List", u"NullOk", u"Set"]:
        superGuard = getGlobalValue(superGuardName)
        if superGuard is None:
            continue
        ej = Ejector()
        try:
            subGuard = superGuard.call(u"extractGuard", [guard, ej])
            return deepFrozenSupersetOf(subGuard)
        except Ejecting:
            # XXX lets other ejectors get through
            pass
    for pairGuardName in [u"Map", u"Pair"]:
        pairGuard = getGlobalValue(pairGuardName)
        if pairGuard is None:
            continue
        ej = Ejector()
        try:
            guardPair = pairGuard.call(u"extractGuards", [guard, ej])
            if isinstance(guardPair, ConstList) and guardPair.size() == 2:
                return (
                    (deepFrozenSupersetOf(guardPair.strategy.fetch(
                        guardPair, 0))) and
                    (deepFrozenSupersetOf(guardPair.strategy.fetch(
                        guardPair, 1))))
        except Ejecting:
            # XXX lets other ejectors get through
            pass
    if (SubrangeGuard(deepFrozenGuard).call(u"passes", [guard])
            is wrapBool(True)):
        return True
    if isinstance(guard, AnyOfGuard):
        for g in guard.subguards:
            if not deepFrozenSupersetOf(g):
                return False
        return True
    return False


def auditDeepFrozen(audition):
    from typhon.nodes import FinalPattern, Obj
    from typhon.objects.user import Audition
    from typhon.objects.printers import toString
    if not isinstance(audition, Audition):
        raise userError(u"not invoked with an Audition")
    ast = audition.ast
    if not isinstance(ast, Obj):
        raise userError(u"audition not created with an object expr")
    n = ast._n
    if isinstance(n, FinalPattern):
        objName = ast._n._n
    else:
        objName = None
    ss = ast._script.getStaticScope()
    namesUsed = ss.read + ss.set
    errors = []
    for name in namesUsed:
        if name == objName:
            continue
        guard = audition.getGuard(name)
        if not deepFrozenSupersetOf(guard):
            errors.append(u'"%s" in the lexical scope of %s does not have a '
                          u'guard implying DeepFrozen, but %s' %
                          (name, audition.fqn, toString(guard)))
    if len(errors) > 0:
        raise userError(u'\n'.join(errors))


@autohelp
class DeepFrozen(Object):
    """
    Auditor and guard for transitive immutability.
    """

    def auditorStamps(self):
        return [deepFrozenStamp]

    @profileTyphon("DeepFrozen.audit/1")
    def audit(self, audition):
        auditDeepFrozen(audition)
        audition.ask(deepFrozenStamp)
        return False

    def recv(self, atom, args):
        from typhon.objects.constants import wrapBool
        from typhon.objects.collections.helpers import monteMap
        from typhon.objects.user import Audition
        if atom is AUDIT_1:
            audition = args[0]
            if not isinstance(audition, Audition):
                raise userError(u"not an Audition")
            return wrapBool(self.audit(audition))

        if atom is COERCE_2:
            from typhon.objects.constants import NullObject
            from typhon.objects.ejectors import theThrower
            ej = args[1]
            if ej is NullObject:
                ej = theThrower
            checkDeepFrozen(args[0], monteMap(), ej, args[0])
            return args[0]

        if atom is SUPERSETOF_1:
            return wrapBool(deepFrozenSupersetOf(args[0]))
        raise Refused(self, atom, args)

    def printOn(self, out):
        from typhon.objects.data import StrObject
        out.call(u"print", [StrObject(u"DeepFrozen")])


deepFrozenGuard = DeepFrozen()
