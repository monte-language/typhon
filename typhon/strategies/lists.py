# encoding: utf-8

from rpython.rlib.objectmodel import import_from_mixin

from typhon.objects.constants import NullObject
from typhon.objects.data import (BytesObject, CharObject, IntObject,
                                 StrObject, unwrapBytes, unwrapChar,
                                 unwrapInt, unwrapStr)
from typhon.objects.refs import UnconnectedRef
from typhon.rstrategies import rstrategies


class Strategy(object):
    """
    A plan for specializing storage.
    """

    __metaclass__ = rstrategies.StrategyMetaclass

    import_from_mixin(rstrategies.AbstractStrategy)
    import_from_mixin(rstrategies.SafeIndexingMixin)

    def strategy_factory(self):
        return strategyFactory


@rstrategies.strategy()
class GenericListStrategy(Strategy):
    """
    A list.
    """

    import_from_mixin(rstrategies.GenericStrategy)

    def default_value(self):
        return None


@rstrategies.strategy(generalize=[GenericListStrategy])
class NullListStrategy(Strategy):
    """
    A list with only nulls.
    """

    import_from_mixin(rstrategies.SingleValueStrategy)

    def value(self):
        return NullObject


def makeUnboxedListStrategy(cls, box, unbox, exemplar):
    """
    Create a strategy for unboxing a certain class.

    The class must be a subclass of Object.

    If there's not a homomorphism between the boxer and unboxer, you're going
    to have a bad time. Or, at the least, it's not going to typecheck.

    The boxer and unboxer can be elidable, but it's not necessary.

    The exemplar should be a prebuilt safe default value; it will be used to
    pre-fill lists that are overallocated.
    """

    @rstrategies.strategy(generalize=[GenericListStrategy])
    class UnboxedListStrategy(Strategy):
        """
        A list of some monomorphic unboxed type.
        """

        import_from_mixin(rstrategies.SingleTypeStrategy)

        contained_type = cls
        box = box
        unbox = box

        def wrap(self, value):
            return box(value)

        def unwrap(self, value):
            return unbox(value)

        def default_value(self):
            return exemplar

    return UnboxedListStrategy


def unboxUnconnectedRef(value):
    assert isinstance(value, UnconnectedRef), "Implementation detail"
    return value._problem

unboxedStrategies = [makeUnboxedListStrategy(cls, box, unbox, exemplar)
for (cls, box, unbox, exemplar) in [
    # Chars.
    (CharObject, CharObject, unwrapChar, CharObject(u'▲')),
    # Small ints.
    (IntObject, IntObject, unwrapInt, IntObject(42)),
    # Unicode strings.
    (StrObject, StrObject, unwrapStr, StrObject(u"▲")),
    # Bytestrings.
    (BytesObject, BytesObject, unwrapBytes, BytesObject("M")),
    # _booleanFlow-generated lists of unconnected refs.
    (UnconnectedRef, UnconnectedRef, unboxUnconnectedRef,
        UnconnectedRef(StrObject(u"Implementation detail leaked"))),
]]


@rstrategies.strategy(generalize=[NullListStrategy] + unboxedStrategies +
    [GenericListStrategy])
class EmptyListStrategy(Strategy):
    """
    A list with no elements.
    """

    import_from_mixin(rstrategies.EmptyStrategy)


class StrategyFactory(rstrategies.StrategyFactory):
    pass


strategyFactory = StrategyFactory(Strategy)
# strategyFactory.logger.activate()
