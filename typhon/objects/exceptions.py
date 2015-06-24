from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throw
from typhon.objects.root import Object, runnable


RUN_2 = getAtom(u"run", 2)


@autohelp
class SealedException(Object):
    """
    An exception.

    Sealed within this object are the details of an exceptional occurrence.
    """

    def __init__(self, value):
        self.value = value

    def toString(self):
        return u"<sealed exception>"


@runnable(RUN_2)
def unsealException(args):
    """
    Unseal a specimen.
    """

    specimen = args[0]
    ej = args[1]

    if isinstance(specimen, SealedException):
        return specimen.value
    throw(ej, StrObject(u"Cannot unseal non-thrown object"))
