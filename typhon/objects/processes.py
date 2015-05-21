from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.collections import ConstList
from typhon.objects.data import StrObject
from typhon.objects.root import Object


GETARGUMENTS_0 = getAtom(u"getArguments", 0)


class CurrentProcess(Object):

    def __init__(self, config):
        self.config = config

    def callAtom(self, atom, args):
        if atom is GETARGUMENTS_0:
            return ConstList([StrObject(arg.decode("utf-8"))
                              for arg in self.config.argv])

        raise Refused(self, atom, args)
