# Hello. Welcome to AutoHelp. We hope that you enjoy your stay. Please do take
# advantage of our fine resorts, and visit our local tourist attractions, like
# our lakes of fire, baths of blood, and frozen wastelands.

import inspect

from typhon.atoms import Atom, getAtom

def autohelp(cls):
    """
    AutoHelp is here to help.

    Do not mock AutoHelp. AutoHelp should not be engaged manually. AutoHelp is
    here to help.

    AutoHelp can recover docstrings from @method-decorated methods. The
    recovery process is automatic and, in most cases, painless. AutoHelp will
    not administer any anesthetic. AutoHelp is here to help.
    """

    recv = cls.recv.__func__
    names = recv.__code__.co_names

    # Retrieve atoms defined from module scope.
    module = inspect.getmodule(cls)
    availableAtoms = inspect.getmembers(module,
                                        lambda obj: isinstance(obj, Atom))
    availableAtoms = dict(availableAtoms)

    # Discover atoms from recv().
    atoms = {}
    for name in names:
        if name in availableAtoms:
            atoms[availableAtoms[name]] = None

    # Synthesize atoms from @methods.
    methods = inspect.getmembers(cls,
                                 lambda attr: hasattr(attr, "_monteMethod_"))
    for name, method in methods:
        verb, argumentTypes, resultTypes = method._monteMethod_
        atom = getAtom(verb, len(argumentTypes))
        doc = method.__doc__.decode("utf-8") if method.__doc__ else None
        atoms[atom] = doc

    def respondingAtoms(self):
        return atoms

    cls.respondingAtoms = respondingAtoms

    return cls
