# Hello. Welcome to AutoHelp. We hope that you enjoy your stay. Please do take
# advantage of our fine resorts, and visit our local tourist attractions, like
# our lakes of fire, baths of blood, and frozen wastelands.

import inspect

from typhon.atoms import Atom

def harvest(cls, name):
    """
    The harvester is here to help AutoHelp.
    """

    if hasattr(cls, name):
        func = getattr(cls, name).__func__
        return func.__code__.co_names
    else:
        return ()

def autohelp(cls):
    """
    AutoHelp is here to help.

    Do not mock AutoHelp. AutoHelp should not be engaged manually. AutoHelp is
    here to help.
    """

    names = harvest(cls, "recv")
    # Collections try to hide their atoms from AutoHelp. Collections will be
    # harvested.
    names += harvest(cls, "_recv")

    module = inspect.getmodule(cls)
    availableAtoms = inspect.getmembers(module,
                                        lambda obj: isinstance(obj, Atom))
    availableAtoms = dict(availableAtoms)

    atoms = {}
    for name in names:
        if name in availableAtoms:
            atoms[availableAtoms[name]] = None

    def respondingAtoms(self):
        return atoms

    cls.respondingAtoms = respondingAtoms

    return cls
