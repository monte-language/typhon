# encoding: utf-8

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.auditors import deepFrozenStamp, selfless, transparentStamp
from typhon.objects.collections import ConstList, ConstSet, monteDict
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, throw
from typhon.errors import Ejecting
from typhon.objects.refs import resolution
from typhon.objects.root import Object, audited
from typhon.objects.slots import FinalSlot, VarSlot

COERCE_2 = getAtom(u"coerce", 2)
EXTRACTGUARDS_2 = getAtom(u"extractGuards", 2)
EXTRACTGUARD_2 = getAtom(u"extractGuard", 2)
GETGUARD_0 = getAtom(u"getGuard", 0)
GETMETHODS_0 = getAtom(u"getMethods", 0)
GET_1 = getAtom(u"get", 1)
SUPERSETOF_1 = getAtom(u"supersetOf", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)


@autohelp
class Guard(Object):
    def coerce(self, specimen, ej):
        specimen = resolution(specimen)
        val = self.subCoerce(specimen)
        if val is None:
            newspec = specimen.call(u"_conformTo", [self])
            val = self.subCoerce(newspec)
            if val is None:
                throw(ej, StrObject(u"%s does not conform to %s" % (
                    specimen.toQuote(), self.toQuote())))
            else:
                return val
        else:
            return val

    def supersetOf(self, other):
        return wrapBool(False)

    def recv(self, atom, args):
        if atom is COERCE_2:
            return self.coerce(args[0], args[1])

        if atom is SUPERSETOF_1:
            return self.supersetOf(args[0])

        raise Refused(self, atom, args)


@autohelp
@audited.DF
class AnyGuard(Object):
    """
    A guard which admits the universal set.

    This object specializes to a guard which admits the union of its
    subguards: Any[X, Y, Z] =~ X ∪ Y ∪ Z
    """

    def toString(self):
        return u"Any"

    def recv(self, atom, args):
        if atom is COERCE_2:
            return args[0]

        if atom is SUPERSETOF_1:
            return wrapBool(True)

        if atom is EXTRACTGUARDS_2:
            g = args[0]
            ej = args[1]
            if isinstance(g, AnyOfGuard):
                return ConstList(g.subguards)
            else:
                ej.call(u"run", [StrObject(u"Not an AnyOf guard")])

        if atom is GETMETHODS_0:
            return ConstSet(monteDict())

        if atom.verb == u"get":
            return AnyOfGuard(args)

        raise Refused(self, atom, args)

anyGuard = AnyGuard()


# XXX EventuallyDeepFrozen?
@autohelp
@audited.Transparent
class AnyOfGuard(Object):
    """
    A guard which admits a union of its subguards.
    """
    _immutable_fields_ = 'subguards[*]',

    def __init__(self, subguards):
        self.subguards = subguards

    def toString(self):
        substrings = [subguard.toString() for subguard in self.subguards]
        return u"Any[%s]" % u", ".join(substrings)

    def recv(self, atom, args):
        if atom is COERCE_2:
            for g in self.subguards:
                with Ejector() as ej:
                    try:
                        return g.call(u"coerce", [args[0], ej])
                    except Ejecting as e:
                        if e.ejector is ej:
                            continue
            throw(args[1], StrObject(u"No subguards matched"))
        if atom is SUPERSETOF_1:
            for g in self.subguards:
                if not unwrapBool(g.call(u"supersetOf", [args[0]])):
                    return wrapBool(False)
            return wrapBool(True)

        if atom is _UNCALL_0:
            from typhon.objects.collections import EMPTY_MAP
            return ConstList([anyGuard, StrObject(u"get"),
                              ConstList(self.subguards), EMPTY_MAP])
        raise Refused(self, atom, args)


class FinalSlotGuard(Guard):
    """
    A guard which admits FinalSlots.
    """

    def __init__(self, valueGuard):
        self.valueGuard = valueGuard

    def auditorStamps(self):
        if self.valueGuard.auditedBy(deepFrozenStamp):
            return [deepFrozenStamp]
        else:
            return []

    def subCoerce(self, specimen):
        if (isinstance(specimen, FinalSlot) and
           self.valueGuard == specimen._guard or
           self.valueGuard.supersetOf(specimen.call(u"getGuard", []))):
            return specimen

    def recv(self, atom, args):
        if atom is GETGUARD_0:
            return self.valueGuard
        if atom is COERCE_2:
            return self.coerce(args[0], args[1])
        if atom is SUPERSETOF_1:
            s = args[0]
            if isinstance(s, FinalSlot):
                return self.valueGuard.call(u"supersetOf", [s._guard])
            return wrapBool(False)
        raise Refused(self, atom, args)

    def toString(self):
        return u"FinalSlot[" + self.valueGuard.toString() + u"]"


class VarSlotGuard(Guard):
    """
    A guard which admits VarSlots.
    """

    def __init__(self, valueGuard):
        self.valueGuard = valueGuard

    def auditorStamps(self):
        if self.valueGuard.auditedBy(deepFrozenStamp):
            return [deepFrozenStamp]
        else:
            return []

    def subCoerce(self, specimen):
        if (isinstance(specimen, VarSlot) and
           self.valueGuard == specimen._guard or
           self.valueGuard.supersetOf(specimen.call(u"getGuard", []))):
            return specimen


@audited.DF
class FinalSlotGuardMaker(Guard):
    """
    A guard which emits makers of FinalSlots.
    """

    def recv(self, atom, args):
        if atom is EXTRACTGUARD_2:
            specimen, ej = args[0], args[1]
            if specimen is self:
                return anyGuard
            elif isinstance(specimen, FinalSlotGuard):
                return specimen.valueGuard
            else:
                ej.call(u"run", [StrObject(u"Not a FinalSlot guard")])
        if atom is GETGUARD_0:
            return NullObject
        if atom is COERCE_2:
            return self.coerce(args[0], args[1])
        if atom is GET_1:
            # XXX Coerce arg to Guard?
            return FinalSlotGuard(args[0])
        if atom is SUPERSETOF_1:
            return wrapBool(isinstance(args[0], FinalSlotGuard) or
                            isinstance(args[0], FinalSlotGuardMaker))
        raise Refused(self, atom, args)

    def subCoerce(self, specimen):
        if isinstance(specimen, FinalSlot):
            return specimen


@audited.DF
class VarSlotGuardMaker(Guard):
    """
    A guard which admits makers of VarSlots.
    """

    def recv(self, atom, args):
        if atom is EXTRACTGUARD_2:
            specimen, ej = args[0], args[1]
            if specimen is self:
                return anyGuard
            elif isinstance(specimen, VarSlotGuard):
                return specimen.valueGuard
            else:
                ej.call(u"run", [StrObject(u"Not a VarSlot guard")])
        if atom is GETGUARD_0:
            return NullObject
        if atom is COERCE_2:
            return self.coerce(args[0], args[1])
        if atom is GET_1:
            # XXX Coerce arg to Guard?
            return VarSlotGuard(args[0])
        if atom is SUPERSETOF_1:
            return wrapBool(isinstance(args[0], VarSlotGuard) or
                            isinstance(args[0], VarSlotGuardMaker))
        raise Refused(self, atom, args)

    def subCoerce(self, specimen):
        if isinstance(specimen, VarSlot):
            return specimen


@audited.DF
class BindingGuard(Guard):
    """
    A guard which admits bindings.
    """

    def subCoerce(self, specimen):
        from typhon.objects.slots import Binding
        if isinstance(specimen, Binding):
            return specimen
