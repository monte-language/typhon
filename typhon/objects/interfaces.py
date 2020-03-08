from typhon.autohelp import autohelp, method
from typhon.objects.constants import NullObject
from typhon.objects.collections.sets import monteSet
from typhon.objects.data import StrObject
from typhon.objects.root import Object


@autohelp
class ComputedMethod(Object):
    """
    A method description.
    """

    _immutable_fields_ = "arity", "docstring", "verb"

    def __init__(self, arity, docstring, verb):
        self.arity = arity
        self.docstring = docstring
        self.verb = verb

    def toString(self):
        return u"<computed message %s/%d>" % (self.verb, self.arity)

    @method("Int")
    def getArity(self):
        return self.arity

    @method("Any")
    def getDocstring(self):
        if self.docstring is not None:
            return StrObject(self.docstring)
        return NullObject

    @method("Str")
    def getVerb(self):
        return self.verb


@autohelp
class ComputedInterface(Object):
    """
    An interface generated on the fly for an object.
    """

    _immutable_fields_ = "atoms", "docstring", "fqn"

    def __init__(self, obj):
        self.atoms = obj.respondingAtoms()
        self.docstring = obj.docString()
        self.fqn = obj.getFQN()

    def toString(self):
        return u"<interface from %s>" % self.fqn

    @method("Any")
    def getDocstring(self):
        if self.docstring is not None:
            return StrObject(self.docstring)
        return NullObject

    @method("Set")
    def getMethods(self):
        d = monteSet()
        for atom, docstring in self.atoms.iteritems():
            d[ComputedMethod(atom.arity, docstring, atom.verb)] = None
        return d
