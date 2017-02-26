from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections.lists import wrapList
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throwStr
from typhon.objects.root import Object, runnable


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
