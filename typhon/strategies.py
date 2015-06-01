from rpython.rlib.objectmodel import import_from_mixin

from typhon.objects.data import IntObject
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
        assert isinstance(value, IntObject)
        return value.getInt()


@rstrategies.strategy(generalize=[SmallIntListStrategy, GenericListStrategy])
class EmptyListStrategy(Strategy):
    """
    A list with no elements.
    """

    import_from_mixin(rstrategies.EmptyStrategy)


class StrategyFactory(rstrategies.StrategyFactory):
    pass


strategyFactory = StrategyFactory(Strategy)
