# encoding: utf-8

from typhon.autohelp import autohelp, method
from typhon.errors import UserException
from typhon.objects.auditors import (deepFrozenStamp, selfless,
                                     transparentStamp)
from typhon.objects.collections.helpers import asSet
from typhon.objects.collections.lists import wrapList
from typhon.objects.collections.sets import monteSet
from typhon.objects.constants import (TrueObject, FalseObject, NullObject,
                                      unwrapBool, wrapBool)
from typhon.objects.data import (BigInt, BytesObject, CharObject,
                                 DoubleObject, IntObject, StrObject)
from typhon.objects.ejectors import Ejector, throw
from typhon.errors import Ejecting, userError
from typhon.objects.refs import resolution
from typhon.objects.root import Object, audited
from typhon.objects.slots import FinalSlot, VarSlot


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
        if specimen is TrueObject or specimen is FalseObject:
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

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        return specimen

    @method("Bool", "Any")
    def supersetOf(self, guard):
        return True

    @method("List", "Any", "Any")
    def extractGuards(self, guard, ej):
        if isinstance(guard, AnyOfGuard):
            return guard.subguards
        else:
            throw(ej, StrObject(u"Not an AnyOf guard"))

    @method("Set")
    def getMethods(self):
        return monteSet()

    @method("Any", "*Any")
    def get(self, args):
        return AnyOfGuard(args)

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

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        for g in self.subguards:
            with Ejector() as cont:
                try:
                    return g.call(u"coerce", [specimen, cont])
                except Ejecting as e:
                    if e.ejector is cont:
                        continue
        throw(ej, StrObject(u"No subguards matched"))

    @method("Bool", "Any")
    def supersetOf(self, guard):
        for g in self.subguards:
            if not unwrapBool(g.call(u"supersetOf", [guard])):
                return False
        return True

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        return [anyGuard, StrObject(u"get"), wrapList(self.subguards),
                EMPTY_MAP]


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

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        from typhon.scopes.safe import theFinalSlotGuardMaker
        return [theFinalSlotGuardMaker, StrObject(u"get"),
                wrapList([self.valueGuard]), EMPTY_MAP]

    @method("Any")
    def getGuard(self):
        return self.valueGuard

    @method("Bool", "Any")
    def supersetOf(self, s):
        if isinstance(s, FinalSlot):
            return unwrapBool(self.valueGuard.call(u"supersetOf", [s._guard]))
        return False

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

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        from typhon.scopes.safe import theVarSlotGuardMaker
        return [theVarSlotGuardMaker, StrObject(u"get"),
                wrapList([self.valueGuard]), EMPTY_MAP]


@autohelp
@audited.DF
class FinalSlotGuardMaker(Guard):
    """
    A guard which emits makers of FinalSlots.
    """

    @method("Any", "Any", "Any")
    def extractGuard(self, specimen, ej):
        if specimen is self:
            return anyGuard
        elif isinstance(specimen, FinalSlotGuard):
            return specimen.valueGuard
        else:
            ej.call(u"run", [StrObject(u"Not a FinalSlot guard")])

    @method("Void")
    def getGuard(self):
        pass

    @method("Any", "Any")
    def get(self, guard):
        # XXX Coerce arg to Guard?
        return FinalSlotGuard(guard)

    @method("Bool", "Any")
    def supersetOf(self, guard):
        return isinstance(guard, FinalSlotGuard) or isinstance(guard,
                FinalSlotGuardMaker)

    def subCoerce(self, specimen):
        if isinstance(specimen, FinalSlot):
            return specimen


@autohelp
@audited.DF
class VarSlotGuardMaker(Guard):
    """
    A guard which admits makers of VarSlots.
    """

    @method("Any", "Any", "Any")
    def extractGuard(self, specimen, ej):
        if specimen is self:
            return anyGuard
        elif isinstance(specimen, VarSlotGuard):
            return specimen.valueGuard
        else:
            ej.call(u"run", [StrObject(u"Not a VarSlot guard")])

    @method("Void")
    def getGuard(self):
        pass

    @method("Any", "Any")
    def get(self, guard):
        # XXX Coerce arg to Guard?
        return VarSlotGuard(guard)

    @method("Bool", "Any")
    def supersetOf(self, guard):
        return isinstance(guard, VarSlotGuard) or isinstance(guard,
                VarSlotGuardMaker)

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

    def subCoerce(self, specimen):
        from typhon.objects.equality import optSame, EQUAL
        if optSame(specimen, self.value) is EQUAL:
            return specimen

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

    @method("Any", "Any")
    def get(self, guard):
        return SameGuard(guard)

    @method("Any", "Any", "Any")
    def extractValue(self, specimen, ej):
        if isinstance(specimen, SameGuard):
            return specimen.value
        else:
            ej.call(u"run", [StrObject(u"Not a Same guard")])

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

    @method("Any", "Any")
    def get(self, guard):
        return SubrangeGuard(guard)

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

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        return [subrangeGuardMaker, StrObject(u"get"),
                wrapList([self.superGuard]), EMPTY_MAP]

    @method("Bool", "Any")
    def audit(self, audition):
        from typhon.nodes import Noun, Method, Obj
        from typhon.objects.equality import optSame, EQUAL
        from typhon.objects.user import Audition
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
                                (self.superGuard.call(u"supersetOf",
                                    [resultGuard])
                                 is wrapBool(True))):
                                return True
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
        return False

    @method("Bool", "Any")
    def passes(self, specimen):
        return specimen.auditedBy(self)

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        if specimen.auditedBy(self):
            return specimen
        c = specimen.call(u"_conformTo", [self])
        if c.auditedBy(self):
            return c
        throw(ej, StrObject(u"%s does not conform to %s" % (
            specimen.toQuote(), self.toQuote())))
