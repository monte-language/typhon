# encoding: utf-8

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object


RUN_1 = getAtom(u"run", 1)
_CONFORMTO_1 = getAtom(u"_conformTo", 1)
_PRINTON_1 = getAtom(u"_printOn", 1)
_RESPONDSTO_2 = getAtom(u"_respondsTo", 2)
_SEALEDDISPATCH_1 = getAtom(u"_sealedDispatch", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)


mirandaAtoms = [
    _CONFORMTO_1,
    _PRINTON_1,
    _RESPONDSTO_2,
    _SEALEDDISPATCH_1,
    _UNCALL_0,
    _WHENMORERESOLVED_1,
]


def dedent(paragraph):
    """
    RPython-friendly Unicode text dedent.
    """

    pieces = [s.strip(u" ") for s in paragraph.split(u"\n")]
    return u"\n".join([piece for piece in pieces if piece])


@autohelp
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
                    if atom not in mirandaAtoms:
                        lines.append(u"Method: %s/%d" % (atom.verb,
                                                         atom.arity))
            else:
                lines.append(u"No methods declared")

            return StrObject(u"\n".join(lines))

        raise Refused(self, atom, args)
