# encoding: utf-8

from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.constants import wrapBool
from typhon.objects.root import Object

ABOVEZERO_0 = getAtom(u"aboveZero", 0)
ATLEASTZERO_0 = getAtom(u"atLeastZero", 0)
ATMOSTZERO_0 = getAtom(u"atMostZero", 0)
BELOWZERO_0 = getAtom(u"belowZero", 0)
ISZERO_0 = getAtom(u"isZero", 0)

class _Incomparable(Object):
    """
    A comparison which is not relatable to zero.
    """

    def toString(self):
        return u"<incomparable>"

    def recv(self, atom, args):
        if atom in (ABOVEZERO_0, ATLEASTZERO_0, ATMOSTZERO_0, BELOWZERO_0,
                    ISZERO_0):
            return wrapBool(False)
        raise Refused(self, atom, args)

Incomparable = _Incomparable()
