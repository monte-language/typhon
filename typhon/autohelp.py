# Hello. Welcome to AutoHelp. We hope that you enjoy your stay. Please do take
# advantage of our fine resorts, and visit our local tourist attractions, like
# our lakes of fire, baths of blood, and frozen wastelands.

import inspect

from typhon.atoms import Atom

def autohelp(cls):
    recv = cls.recv.__func__
    names = recv.__code__.co_names

    module = inspect.getmodule(cls)
    availableAtoms = inspect.getmembers(module,
                                        lambda obj: isinstance(obj, Atom))
    availableAtoms = dict(availableAtoms)

    atoms = []
    for name in names:
        if name in availableAtoms:
            atoms.append(availableAtoms[name])

    def respondingAtoms(self):
        return atoms

    cls.respondingAtoms = respondingAtoms

    return cls
