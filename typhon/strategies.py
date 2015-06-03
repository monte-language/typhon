from rpython.rlib.objectmodel import import_from_mixin

from typhon.objects.constants import (BoolObject, FalseObject, NullObject,
                                      unwrapBool, wrapBool)
from typhon.objects.data import IntObject
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


@rstrategies.strategy(generalize=[GenericListStrategy])
class SmallIntListStrategy(Strategy):
    """
    A list with only ints which are able to fit into machine words.
    """

    import_from_mixin(rstrategies.SingleTypeStrategy)

    contained_type = IntObject

    def default_value(self):
        return IntObject(42)

    def wrap(self, value):
        return IntObject(value)

    def unwrap(self, value):
        return value.getInt()


@rstrategies.strategy(generalize=[GenericListStrategy])
class BooleanFlowStrategy(Strategy):
    """
    A list of unconnected refs.
    """

    import_from_mixin(rstrategies.SingleTypeStrategy)

    contained_type = UnconnectedRef

    def default_value(self):
        return UnconnectedRef(u"Implementation detail leaked")

    def wrap(self, value):
        return UnconnectedRef(value)

    def unwrap(self, value):
        assert isinstance(value, UnconnectedRef), "Implementation detail"
        return value._problem


@rstrategies.strategy(generalize=[BooleanFlowStrategy, GenericListStrategy])
class BoolListStrategy(Strategy):
    """
    A list with only booleans.
    """

    import_from_mixin(rstrategies.SingleTypeStrategy)

    contained_type = BoolObject

    def default_value(self):
        return FalseObject

    def wrap(self, value):
        return wrapBool(value)

    def unwrap(self, value):
        return unwrapBool(value)


@rstrategies.strategy(generalize=[NullListStrategy, SmallIntListStrategy,
                                  BooleanFlowStrategy, BoolListStrategy,
                                  GenericListStrategy])
class EmptyListStrategy(Strategy):
    """
    A list with no elements.
    """

    import_from_mixin(rstrategies.EmptyStrategy)


class StrategyFactory(rstrategies.StrategyFactory):
    pass


strategyFactory = StrategyFactory(Strategy)
# strategyFactory.logger.activate()
