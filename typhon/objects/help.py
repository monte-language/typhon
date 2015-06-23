from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.data import StrObject
from typhon.objects.root import Object


RUN_1 = getAtom(u"run", 1)


class Help(Object):
    """
    A gentle introspection assistant.
    """

    def recv(self, atom, args):
        if atom is RUN_1:
            specimen = args[0]
            lines = []

            lines.append(u"Object type: %s" %
                    specimen.__class__.__name__.decode("utf-8"))

            for atom in specimen.respondingAtoms():
                lines.append(u"Method: %s/%d" % (atom.verb, atom.arity))

            return StrObject(u"\n".join(lines))

        raise Refused(self, atom, args)
