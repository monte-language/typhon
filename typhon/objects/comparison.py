# encoding: utf-8

from typhon.autohelp import autohelp, method
from typhon.objects.root import Object

@autohelp
class _Incomparable(Object):
    """
    A comparison which is not relatable to zero.
    """

    def toString(self):
        return u"<incomparable>"

    @method("Bool")
    def aboveZero(self):
        return False

    @method("Bool")
    def atLeastZero(self):
        return False

    @method("Bool")
    def atMostZero(self):
        return False

    @method("Bool")
    def belowZero(self):
        return False

    @method("Bool")
    def isZero(self):
        return False

Incomparable = _Incomparable()
