# encoding: utf-8

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.auditors import deepFrozenStamp, selfless, transparentStamp
from typhon.objects.collections import ConstList
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, throw
from typhon.errors import Ejecting
from typhon.objects.refs import resolution
from typhon.objects.root import Object
from typhon.objects.slots import FinalSlot, VarSlot

COERCE_2 = getAtom(u"coerce", 2)
EXTRACTGUARD_2 = getAtom(u"extractGuard", 2)
GET_1 = getAtom(u"get", 1)
GETGUARD_0 = getAtom(u"getGuard", 0)
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


@autohelp
class AnyGuard(Object):
    """
    A guard which admits the universal set.

    This object specializes to a guard which admits the union of its
    subguards: Any[X, Y, Z] =~ X ∪ Y ∪ Z
    """

    stamps = [deepFrozenStamp]

    def toString(self):
        return u"Any"

    def recv(self, atom, args):
        if atom is COERCE_2:
            return args[0]
        if atom is SUPERSETOF_1:
            return wrapBool(True)
        if atom.verb == u"get":
            return AnyOfGuard(args)
        raise Refused(self, atom, args)

anyGuard = AnyGuard()


@autohelp
class AnyOfGuard(Object):
    """
    A guard which admits a union of its subguards.
    """

    # XXX EventuallyDeepFrozen?
    stamps = [selfless, transparentStamp]

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
            return ConstList([anyGuard, StrObject(u"get"),
                              ConstList(self.subguards)])
        raise Refused(self, atom, args)


class FinalSlotGuard(Guard):
    """
    A guard which admits FinalSlots.
    """

    def __init__(self, valueGuard):
        self.valueGuard = valueGuard
        if self.valueGuard.auditedBy(deepFrozenStamp):
            self.stamps = [deepFrozenStamp]

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
        return u"FinalSlot[" + self.valueGuard.toString() + "]"


class VarSlotGuard(Guard):
    """
    A guard which admits VarSlots.
    """

    def __init__(self, valueGuard):
        self.valueGuard = valueGuard
        if self.valueGuard.auditedBy(deepFrozenStamp):
            self.stamps = [deepFrozenStamp]

    def subCoerce(self, specimen):
        if (isinstance(specimen, VarSlot) and
           self.valueGuard == specimen._guard or
           self.valueGuard.supersetOf(specimen.call(u"getGuard", []))):
            return specimen


class FinalSlotGuardMaker(Guard):
    """
    A guard which emits makers of FinalSlots.
    """

    stamps = [deepFrozenStamp]

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


class VarSlotGuardMaker(Guard):
    """
    A guard which admits makers of VarSlots.
    """

    stamps = [deepFrozenStamp]

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
