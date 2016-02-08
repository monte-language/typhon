# Type information for typed slots.

# Typed slots are an attempt to realize the benefits of "deslotification" as
# documented for the (hypothetical) E native code generator at
# http://www.erights.org/enative/varcases.html . We associate each name with a
# "slot", which is much like a standard Monte slot, but can be customized in
# storage for the type of slot. Slot types are annotated onto each name,
# providing information to the peephole optimizer and ensuring that frame
# accesses cannot be type-confused.

from typhon.enum import makeEnum

# The different kinds of syntactic slots:
# Final, implicit Any: def x
# Final, guarded: def x :G
# Var, implicit Any: var x
# Var, guarded: var x :G
# Binding: def &&x
finalAny, final, varAny, var, binding = makeEnum(u"depth",
    u"finalAny final varAny var binding".split())

class SlotType(object):
    """
    A type which describes the storage requirements of a slot.
    """

    _immutable_ = True

    def __init__(self, depth, escapes):
        self.depth = depth
        self.escapes = escapes

    def repr(self):
        return u"<slotType %s%s>" % (self.depth.repr,
                u" (escapes)" if self.escapes else u"")

    def escaping(self):
        """
        This slot, but eligible to escape its frame of definition by being
        closed over by some object.
        """

        return SlotType(self.depth, True)

    def withReifiedSlot(self):
        """
        This slot, but reified to the slot level.
        """

        return SlotType(binding, self.escapes)

    def withReifiedBinding(self):
        """
        This slot, but reified to the binding level.
        """

        return SlotType(binding, self.escapes)

    def guarded(self):
        """
        This slot, but with a guard.
        """

        if self.depth is finalAny:
            return SlotType(final, self.escapes)
        elif self.depth is varAny:
            return SlotType(var, self.escapes)

    def assignable(self):
        """
        Whether this slot could ever be assigned to at runtime.
        """

        return self.depth in (varAny, var, binding)
