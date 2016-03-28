from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections.lists import wrapList
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throw
from typhon.objects.root import Object, runnable


RUN_2 = getAtom(u"run", 2)


def sealException(ue):
    val = ue.getPayload()
    trail = ue.trail
    if isinstance(val, SealedException):
        return val
    return SealedException(val, trail)


@autohelp
class SealedException(Object):
    """
    An exception.

    Sealed within this object are the details of an exceptional occurrence.
    """

    def __init__(self, value, trail):
        self.value = value
        self.trail = trail

    def toString(self):
        return u"<sealed exception>"


@runnable(RUN_2, _stamps=[deepFrozenStamp])
def unsealException(specimen, ej):
    """
    Unseal a specimen.
    """

    if isinstance(specimen, SealedException):
        trail = wrapList([StrObject(s) for s in specimen.trail])
        return wrapList([specimen.value, trail])
    throw(ej, StrObject(u"Cannot unseal non-thrown object"))
