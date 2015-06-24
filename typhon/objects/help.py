# encoding: utf-8

from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object


RUN_1 = getAtom(u"run", 1)


def dedent(paragraph):
    """
    RPython-friendly Unicode text dedent.
    """

    pieces = [s.strip(u" ") for s in paragraph.split(u"\n")]
    return u"\n".join([piece for piece in pieces if piece])


class Help(Object):
    """
    A gentle introspection assistant.
    """

    def toString(self):
        return u"\n".join([
            u"To obtain information about an object, type:",
            u"    ▲> help(anObject)",
        ])

    def recv(self, atom, args):
        if atom is RUN_1:
            specimen = args[0]
            lines = []

            lines.append(u"Object type: %s" %
                    specimen.__class__.__name__.decode("utf-8"))

            doc = specimen.docString()
            if doc is not None:
                lines.append(dedent(doc))

            atoms = specimen.respondingAtoms()
            if atoms:
                for atom in atoms:
                    lines.append(u"Method: %s/%d" % (atom.verb, atom.arity))
            else:
                lines.append(u"No methods declared")

            return StrObject(u"\n".join(lines))

        raise Refused(self, atom, args)
