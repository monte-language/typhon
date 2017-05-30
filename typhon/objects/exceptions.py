from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import UserException
from typhon.objects.auditors import (SealedPortrayal, deepFrozenStamp,
                                     selfless, semitransparentStamp)
from typhon.objects.collections.helpers import asSet
from typhon.objects.collections.lists import wrapList
from typhon.objects.collections.maps import EMPTY_MAP
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throwStr
from typhon.objects.root import Object, runnable

RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


def sealException(ue):
    val = ue.getPayload()
    if isinstance(val, SealedException):
        return val
    else:
        return SealedException(ue)


@autohelp
class SealedException(Object):
    """
    An exception.

    Sealed within this object are the details of an exceptional occurrence.
    """

    def __init__(self, ue):
        self.ue = ue

    def toString(self):
        return u"<sealed exception>"

    def auditorStamps(self):
        return asSet([selfless, semitransparentStamp])

    @method("Any")
    def _uncall(self):
        return SealedPortrayal(wrapList([
            makeSealedException, StrObject(u"run"),
            wrapList([self.ue.getPayload()]), EMPTY_MAP]))


@runnable(RUN_1, _stamps=[deepFrozenStamp])
def _makeSealedException(e):
    """
    Seal an exception.
    """
    return SealedException(UserException(e))


makeSealedException = _makeSealedException()


@runnable(RUN_2, _stamps=[deepFrozenStamp])
def unsealException(specimen, ej):
    """
    Unseal a specimen.
    """

    if isinstance(specimen, SealedException):
        ue = specimen.ue
        trail = wrapList([StrObject(s) for s in ue.formatTrail()])
        return wrapList([ue.getPayload(), trail])
    throwStr(ej, u"Cannot unseal non-thrown object")
