# encoding: utf-8

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import Refused, UserException
from typhon.objects.auditors import (deepFrozenStamp, selfless,
                                     transparentStamp)
from typhon.objects.collections.helpers import asSet
from typhon.objects.collections.lists import wrapList
from typhon.objects.collections.sets import ConstSet, monteSet
from typhon.objects.constants import (BoolObject, NullObject, unwrapBool,
                                      wrapBool)
from typhon.objects.data import (BigInt, BytesObject, CharObject,
                                 DoubleObject, IntObject, StrObject)
from typhon.objects.ejectors import Ejector, throw
from typhon.errors import Ejecting, userError
from typhon.objects.refs import resolution
from typhon.objects.root import Object, audited
from typhon.objects.slots import FinalSlot, VarSlot

AUDIT_1 = getAtom(u"audit", 1)
COERCE_2 = getAtom(u"coerce", 2)
EXTRACTGUARDS_2 = getAtom(u"extractGuards", 2)
EXTRACTGUARD_2 = getAtom(u"extractGuard", 2)
EXTRACTVALUE_2 = getAtom(u"extractValue", 2)
GETGUARD_0 = getAtom(u"getGuard", 0)
GETMETHODS_0 = getAtom(u"getMethods", 0)
GET_1 = getAtom(u"get", 1)
PASSES_1 = getAtom(u"passes", 1)
SUPERSETOF_1 = getAtom(u"supersetOf", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)


@autohelp
class Guard(Object):

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        specimen = resolution(specimen)
        val = self.subCoerce(specimen)
        if val is None:
            try:
                newspec = specimen.call(u"_conformTo", [self])
            except UserException:
                msg = u"%s threw exception while conforming to %s" % (
                        specimen.toQuote(), self.toQuote())
                throw(ej, StrObject(msg))
            else:
                val = self.subCoerce(newspec)
                if val is None:
                    throw(ej, StrObject(u"%s does not conform to %s" % (
                        specimen.toQuote(), self.toQuote())))
                else:
                    return val
        else:
            return val

    @method.py("Bool", "Any")
    def supersetOf(self, other):
        return False


@autohelp
@audited.DF
class BoolGuard(Guard):
    """
    The set of Boolean values: `[true, false].asSet()`

    This guard is unretractable.
    """

    def subCoerce(self, specimen):
        if isinstance(specimen, BoolObject):
            return specimen


@autohelp
@audited.DF
class StrGuard(Guard):
    """
    The set of string literals.

    This guard is unretractable.
    """

    def subCoerce(self, specimen):
        if isinstance(specimen, StrObject):
            return specimen


@autohelp
@audited.DF
class DoubleGuard(Guard):
    """
    The set of double literals.

    This guard is unretractable.
    """

    def subCoerce(self, specimen):
        if isinstance(specimen, DoubleObject):
            return specimen


@autohelp
@audited.DF
class CharGuard(Guard):
    """
    The set of character literals.

    This guard is unretractable.
    """

    def subCoerce(self, specimen):
        if isinstance(specimen, CharObject):
            return specimen


@autohelp
@audited.DF
class BytesGuard(Guard):
    """
    The set of bytestrings produced by `b__quasiParser` and `_makeBytes`.

    This guard is unretractable.
    """

    def subCoerce(self, specimen):
        if isinstance(specimen, BytesObject):
            return specimen


@autohelp
@audited.DF
class IntGuard(Guard):
    """
    The set of integer literals.

    This guard is unretractable.
    """

    def subCoerce(self, specimen):
        if (isinstance(specimen, IntObject) or
                isinstance(specimen, BigInt)):
            return specimen


@autohelp
@audited.DF
class VoidGuard(Guard):
    """
    The singleton set of null: `[null].asSet()`

    This guard is unretractable.
    """

    def toString(self):
        return u"Void"

    def subCoerce(self, specimen):
        if specimen is NullObject:
            return specimen


@autohelp
@audited.DF
class AnyGuard(Object):
    """
    A guard which admits the universal set.

    This object specializes to a guard which admits the union of its
    subguards: Any[X, Y, Z] =~ X ∪ Y ∪ Z

    This guard is unretractable.
    """

    def printOn(self, out):
        out.call(u"print", [StrObject(u"Any")])

    def recv(self, atom, args):
        if atom is COERCE_2:
            return args[0]

        if atom is SUPERSETOF_1:
            return wrapBool(True)

        if atom is EXTRACTGUARDS_2:
            g = args[0]
            ej = args[1]
            if isinstance(g, AnyOfGuard):
                return wrapList(g.subguards)
            else:
                ej.call(u"run", [StrObject(u"Not an AnyOf guard")])

        if atom is GETMETHODS_0:
            return ConstSet(monteSet())

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

    This guard is unretractable if, and only if, all of its subguards are
    unretractable.
    """

    _immutable_fields_ = 'subguards[*]',

    def __init__(self, subguards):
        self.subguards = subguards

    def printOn(self, out):
        out.call(u"print", [StrObject(u"Any[")])
        for i, subguard in enumerate(self.subguards):
            out.call(u"print", [subguard])
            if i < (len(self.subguards) - 1):
                out.call(u"print", [StrObject(u", ")])
        out.call(u"print", [StrObject(u"]")])

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
            from typhon.objects.collections.maps import EMPTY_MAP
            return wrapList([anyGuard, StrObject(u"get"),
                              wrapList(self.subguards), EMPTY_MAP])
        raise Refused(self, atom, args)


@autohelp
class FinalSlotGuard(Guard):
    """
    A guard which admits FinalSlots.
    """

    def __init__(self, valueGuard):
        self.valueGuard = valueGuard

    def auditorStamps(self):
        if self.valueGuard.auditedBy(deepFrozenStamp):
            return asSet([deepFrozenStamp, selfless, transparentStamp])
        else:
            return asSet([selfless, transparentStamp])

    def subCoerce(self, specimen):
        if (isinstance(specimen, FinalSlot) and
           self.valueGuard == specimen._guard or
           self.valueGuard.supersetOf(specimen.call(u"getGuard", []))):
            return specimen

    def recv(self, atom, args):
        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            from typhon.scopes.safe import theFinalSlotGuardMaker
            return wrapList([theFinalSlotGuardMaker, StrObject(u"get"),
                              wrapList([self.valueGuard]), EMPTY_MAP])

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

    def printOn(self, out):
        out.call(u"print", [StrObject(u"FinalSlot[")])
        out.call(u"print", [self.valueGuard]),
        out.call(u"print", [StrObject(u"]")])


@autohelp
class VarSlotGuard(Guard):
    """
    A guard which admits VarSlots.
    """

    def __init__(self, valueGuard):
        self.valueGuard = valueGuard

    def auditorStamps(self):
        if self.valueGuard.auditedBy(deepFrozenStamp):
            return asSet([deepFrozenStamp, selfless, transparentStamp])
        else:
            return asSet([selfless, transparentStamp])

    def subCoerce(self, specimen):
        if (isinstance(specimen, VarSlot) and
            self.valueGuard == specimen._guard or
            self.valueGuard.supersetOf(specimen.call(u"getGuard", []))):
            return specimen

    def recv(self, atom, args):
        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            from typhon.scopes.safe import theVarSlotGuardMaker
            return wrapList([theVarSlotGuardMaker, StrObject(u"get"),
                              wrapList([self.valueGuard]), EMPTY_MAP])
        raise Refused(self, atom, args)


@autohelp
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


@autohelp
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


@autohelp
@audited.DF
class BindingGuard(Guard):
    """
    A guard which admits bindings.
    """

    def subCoerce(self, specimen):
        from typhon.objects.slots import Binding
        if isinstance(specimen, Binding):
            return specimen


@autohelp
class SameGuard(Guard):
    """
    A guard which admits a single value.

    This guard is unretractable.
    """

    _immutable_fields_ = "value",

    def __init__(self, value):
        self.value = value

    def printOn(self, out):
        out.call(u"print", [StrObject(u"Same[")])
        out.call(u"print", [self.value])
        out.call(u"print", [StrObject(u"]")])

    def auditorStamps(self):
        # Pass on DF-ness if we got it from our value.
        if self.value.auditedBy(deepFrozenStamp):
            return asSet([deepFrozenStamp, selfless, transparentStamp])
        else:
            return asSet([selfless, transparentStamp])

    @method("Any")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        return wrapList([sameGuardMaker, StrObject(u"get"),
                          wrapList([self.value]), EMPTY_MAP])

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        from typhon.objects.equality import optSame, EQUAL
        if optSame(specimen, self.value) is EQUAL:
            return specimen
        # XXX throw properly
        ej.call(u"run", [wrapList([specimen, StrObject(u"is not"),
                                    self.value])])

    @method("Any")
    def getValue(self):
        return self.value


@autohelp
@audited.DF
class SameGuardMaker(Object):
    """
    When specialized, this object yields a guard which only admits precisely
    the object used to specialize it.

    In simpler terms, `Same[x]` will match only those objects `o` for which `o
    == x`.
    """

    def printOn(self, out):
        out.call(u"print", [StrObject(u"Same")])

    def recv(self, atom, args):
        if atom is GET_1:
            return SameGuard(args[0])

        if atom is EXTRACTVALUE_2:
            specimen, ej = args[0], args[1]
            if isinstance(specimen, SameGuard):
                return specimen.value
            else:
                ej.call(u"run", [StrObject(u"Not a Same guard")])
        raise Refused(self, atom, args)


sameGuardMaker = SameGuardMaker()


@autohelp
@audited.DF
class SubrangeGuardMaker(Object):
    """
    The maker of subrange guards.

    When specialized with a guard, this object produces a auditor for those
    guards which admit proper subsets of that guard.
    """

    def printOn(self, out):
        from typhon.objects.data import StrObject
        out.call(u"print", [StrObject(u"SubrangeGuard")])

    def recv(self, atom, args):
        if atom is GET_1:
            return SubrangeGuard(args[0])
        raise Refused(self, atom, args)


subrangeGuardMaker = SubrangeGuardMaker()


@autohelp
@audited.Transparent
class SubrangeGuard(Object):
    """
    An auditor specialized on a guard.

    This auditor proves that its specimens are guards, and that those guards
    admit proper subsets of what this auditor's guard admits.
    """

    def __init__(self, superguard):
        self.superGuard = superguard

    def printOn(self, out):
        from typhon.objects.data import StrObject
        out.call(u"print", [subrangeGuardMaker])
        out.call(u"print", [StrObject(u"[")])
        out.call(u"print", [self.superGuard])
        out.call(u"print", [StrObject(u"]")])

    def recv(self, atom, args):
        from typhon.nodes import Noun, Method, Obj
        from typhon.objects.equality import optSame, EQUAL
        from typhon.objects.user import Audition
        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            return wrapList([subrangeGuardMaker, StrObject(u"get"),
                              wrapList([self.superGuard]), EMPTY_MAP])

        if atom is AUDIT_1:
            audition = args[0]
            if not isinstance(audition, Audition):
                raise userError(u"not invoked with an Audition")
            ast = audition.ast
            if not isinstance(ast, Obj):
                raise userError(u"audition not created with an object expr")
            methods = ast._script._methods
            for m in methods:
                if isinstance(m, Method) and m._verb == u"coerce":
                    mguard = m._g
                    if isinstance(mguard, Noun):
                        rGSG = audition.getGuard(mguard.name)
                        if isinstance(rGSG, FinalSlotGuard):
                            rGSG0 = rGSG.valueGuard
                            if isinstance(rGSG0, SameGuard):
                                resultGuard = rGSG0.value

                                if (optSame(resultGuard, self.superGuard)
                                    is EQUAL or
                                    (SUPERSETOF_1
                                     in self.superGuard.respondingAtoms()
                                     and self.superGuard.call(u"supersetOf",
                                                              [resultGuard])
                                     is wrapBool(True))):
                                    return wrapBool(True)
                                raise userError(
                                    u"%s does not have a result guard implying "
                                    u"%s, but %s" % (audition.fqn,
                                                     self.superGuard.toQuote(),
                                                     resultGuard.toQuote()))
                            raise userError(u"%s does not have a determinable "
                                            u"result guard, but <& %s> :%s" % (
                                                audition.fqn, mguard.name,
                                                rGSG.toQuote()))
                    break
            return self
        if atom is PASSES_1:
            return wrapBool(args[0].auditedBy(self))
        if atom is COERCE_2:
            specimen, ej = args[0], args[1]
            if specimen.auditedBy(self):
                return specimen
            c = specimen.call(u"_conformTo", [self])
            if c.auditedBy(self):
                return c
            throw(ej, StrObject(u"%s does not conform to %s" % (
                specimen.toQuote(), self.toQuote())))

        raise Refused(self, atom, args)
