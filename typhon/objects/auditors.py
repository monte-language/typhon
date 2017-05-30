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
from rpython.rlib.objectmodel import compute_identity_hash

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import Ejecting, userError
# Can't use audited, even thought it's importable; calling it causes a circle.
from typhon.objects.collections.helpers import asSet
from typhon.objects.root import Object, runnable
from typhon.profile import profileTyphon


RUN_2 = getAtom(u"run", 2)


@autohelp
class DeepFrozenStamp(Object):
    """
    DeepFrozen's stamp.
    """

    def computeHash(self, depth):
        return compute_identity_hash(self)

    def auditorStamps(self):
        # Have you ever felt that sense of mischief and wonder as much as when
        # looking at this line? ~ C.
        return asSet([self])

    @method("Bool", "Any")
    def audit(self, audition):
        return True

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        if specimen.auditedBy(self):
            return specimen
        from typhon.objects.ejectors import throwStr
        throwStr(ej, u"coerce/2: Not DeepFrozen")

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
    def computeHash(self, depth):
        return compute_identity_hash(self)

    def auditorStamps(self):
        return asSet([deepFrozenStamp])

    @method("Bool", "Any")
    def audit(self, audition):
        return True

transparentStamp = TransparentStamp()


@autohelp
class SealedPortrayal(Object):
    """
    Sealed within this object is the portrayal of a Semitransparent object.
    """

    def __init__(self, p):
        self.portrayal = p

    def toString(self):
        return u"<sealed portrayal>"


@autohelp
class SemitransparentStamp(Object):
    """
    Semitransparent's stamp.

    Semitransparent objects are transparent to the equalizer and DeepFrozen
    auditor alone.  This allows for structural equality and DeepFrozen auditing
    of objects that attenuate authority. (If, in future, other objects need to
    inspect Semitransparent object structure, an unsealer can be added to the
    unsafe scope.)
    """
    def computeHash(self, depth):
        return compute_identity_hash(self)

    def auditorStamps(self):
        return asSet([deepFrozenStamp])

    @method("Any", "Any")
    def seal(self, p):
        return SealedPortrayal(p)

    @method("Bool", "Any")
    def audit(self, audition):
        return True


semitransparentStamp = SemitransparentStamp()


@autohelp
class TransparentGuard(Object):
    """
    Transparent's guard.
    """
    def computeHash(self, depth):
        return compute_identity_hash(self)

    def auditorStamps(self):
        return asSet([deepFrozenStamp])

    @method("Bool", "Any")
    def passes(self, specimen):
        return specimen.auditedBy(transparentStamp)

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        if specimen.auditedBy(transparentStamp):
            return specimen
        from typhon.objects.constants import NullObject
        from typhon.objects.ejectors import throw
        throw(ej, NullObject)
        return NullObject


@autohelp
class Selfless(Object):
    """
    A stamp for incomparable objects.

    `Selfless` objects are generally not equal to any objects but themselves.
    They may choose to implement alternative comparison protocols such as
    `Transparent`.
    """

    def computeHash(self, depth):
        return compute_identity_hash(self)

    def auditorStamps(self):
        return asSet([deepFrozenStamp])

    @method("Bool", "Any")
    def audit(self, audition):
        return True

    @method("Bool", "Any")
    def passes(self, specimen):
        return specimen.auditedBy(self)

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        if specimen.auditedBy(self):
            return specimen
        from typhon.objects.constants import NullObject
        from typhon.objects.ejectors import throw
        throw(ej, NullObject)
        return NullObject

selfless = Selfless()


def checkDeepFrozen(specimen, seen, ej, root):
    from typhon.objects.collections.lists import unwrapList
    from typhon.objects.collections.maps import ConstMap
    from typhon.objects.ejectors import throwStr
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
          (specimen.auditedBy(transparentStamp))
          or specimen.auditedBy(semitransparentStamp)):
        portrayal = specimen.call(u"_uncall", [])
        if specimen.auditedBy(semitransparentStamp):
            if isinstance(portrayal, SealedPortrayal):
                portrayal = portrayal.portrayal
            else:
                throwStr(ej, u"Semitransparent portrayal was not sealed!")

        portrayalList = unwrapList(portrayal, ej)
        if len(portrayalList) != 4:
            throwStr(ej, u"Transparent object gave bad portrayal")
            return
        checkDeepFrozen(portrayalList[0], seen, ej, root)
        checkDeepFrozen(portrayalList[1], seen, ej, root)
        args = unwrapList(portrayalList[2], ej)
        for item in args:
            checkDeepFrozen(item, seen, ej, root)
        namedArgs = portrayalList[3]
        if not isinstance(namedArgs, ConstMap):
            throwStr(ej, u"Transparent object gave bad portrayal")
            return
        for k, v in namedArgs.iteritems():
            checkDeepFrozen(k, seen, ej, root)
            checkDeepFrozen(v, seen, ej, root)
    else:
        if specimen is root:
            message = root.toQuote() + u" is not DeepFrozen"
        else:
            message = (root.toQuote() + u" is not DeepFrozen because " +
                    specimen.toQuote() + u"is not")
        throwStr(ej, u"audit/1: " + message)


def deepFrozenSupersetOf(guard):
    from typhon.objects.collections.helpers import monteMap
    from typhon.objects.collections.lists import unwrapList
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
        with Ejector() as ej:
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
        with Ejector() as ej:
            try:
                subGuard = superGuard.call(u"extractGuard", [guard, ej])
                return deepFrozenSupersetOf(subGuard)
            except Ejecting as e:
                # Just keep going.
                if e.ejector is not ej:
                    raise
    for pairGuardName in [u"Map", u"Pair"]:
        pairGuard = getGlobalValue(pairGuardName)
        if pairGuard is None:
            continue
        with Ejector() as ej:
            try:
                guardPair = pairGuard.call(u"extractGuards", [guard, ej])
                l = unwrapList(guardPair, ej)
                if len(l) == 2:
                    return deepFrozenSupersetOf(l[0]) and deepFrozenSupersetOf(l[1])
            except Ejecting as e:
                if e.ejector is not ej:
                    raise
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

    def computeHash(self, depth):
        return compute_identity_hash(self)

    def auditorStamps(self):
        return asSet([deepFrozenStamp])

    @method("Bool", "Any")
    @profileTyphon("DeepFrozen.audit/1")
    def audit(self, audition):
        from typhon.objects.user import Audition
        if not isinstance(audition, Audition):
            raise userError(u"not an Audition")

        from typhon.metrics import globalRecorder
        with globalRecorder().context("Audition (DF)"):
            auditDeepFrozen(audition)
            audition.ask(deepFrozenStamp)
            return False

    @method.py("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        from typhon.objects.collections.helpers import monteMap
        from typhon.objects.constants import NullObject
        from typhon.objects.ejectors import theThrower
        if ej is NullObject:
            ej = theThrower
        checkDeepFrozen(specimen, monteMap(), ej, specimen)
        return specimen

    @method("Bool", "Any")
    def supersetOf(self, guard):
        return deepFrozenSupersetOf(guard)

    def printOn(self, out):
        from typhon.objects.data import StrObject
        out.call(u"print", [StrObject(u"DeepFrozen")])


deepFrozenGuard = DeepFrozen()
