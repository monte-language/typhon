from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.collections import ConstSet, monteDict
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object


GETARITY_0 = getAtom(u"getArity", 0)
GETMETHODS_0 = getAtom(u"getMethods", 0)
GETVERB_0 = getAtom(u"getVerb", 0)


class ComputedMethod(Object):
    """
    A method description.
    """

    _immutable_ = True

    def __init__(self, arity, verb):
        self.arity = arity
        self.verb = verb

    def recv(self, atom, args):
        if atom is GETARITY_0:
            return IntObject(self.arity)

        if atom is GETVERB_0:
            return StrObject(self.verb)

        raise Refused(self, atom, args)


@autohelp
class ComputedInterface(Object):
    """
    An interface generated on the fly for an object.
    """

    _immutable_fields_ = "atoms[*]",

    def __init__(self, obj):
        self.atoms = obj.respondingAtoms()

    def recv(self, atom, args):
        if atom is GETMETHODS_0:
            d = monteDict()
            for atom in self.atoms:
                d[ComputedMethod(atom.arity, atom.verb)] = None
            return ConstSet(d)

        raise Refused(self, atom, args)
