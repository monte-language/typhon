# Hello. Welcome to AutoHelp. We hope that you enjoy your stay. AutoHelp is
# undergoing an upgrade. AutoHelp will be upgraded to the latest version of
# Auto, and additionally to the latest version of Help. Nothing can escape
# upgraded AutoHelp.

import py

from typhon.atoms import getAtom
from typhon.errors import Refused


def method(rv, *args, **kwargs):
    "NOT_RPYTHON"

    # Mark methods that must be automatically helped. Record an unprocessed
    # tuple of (args, namedArgs, returnGuard).

    def deco(f):
        f._monteMethod_ = (args, kwargs, rv)
        return f
    return deco


unwrappers = {
    "Bool": "typhon.objects.constants",
    "Int": "typhon.objects.data",
    "List": "typhon.objects.collections.lists",
    "Map": "typhon.objects.collections.maps",
}

wrappers = {
    "Bool": "typhon.objects.constants",
    "Int": "typhon.objects.data",
    "List": "typhon.objects.collections.lists",
    "Map": "typhon.objects.collections.maps",
}


def alterMethods(cls):
    """
    Alter Monte methods on behalf of AutoHelp.

    Return the signatures of the altered methods.
    """

    atoms = []

    def nextName(nameIndex=[0]):
        name = "_%d" % nameIndex[0]
        nameIndex[0] += 1
        return name

    execNames = {"Refused": Refused}
    dispatchClauses = []
    # vars() returns a view that is corrupted if accessed during iteration.
    d = {}
    for c in reversed(cls.__mro__):
        d.update(vars(c))
    for attr, f in d.iteritems():
        try:
            args, kwargs, rv = f._monteMethod_
        except (AttributeError, ValueError):
            continue
        verb = attr.decode("utf-8")
        assignments = []
        if len(args) == 1 and args[0][0] == '*':
            # *args
            attr = "_%s_%s_star_args_" % (cls.__name__, attr)
            atomTest = "atom.verb == %r" % verb
            call = "self.%s(args)" % attr
        else:
            attr = "_%s_%s_%d_" % (cls.__name__, attr, len(args))
            atomName = nextName()
            execNames[atomName] = atom = getAtom(verb, len(args))
            atoms.append(atom)
            atomTest = "atom is %s" % atomName
            argNames = []
            for i, arg in enumerate(args):
                argName = nextName()
                argNames.append(argName)
                if arg == "Any":
                    # No unwrapping.
                    assignments.append("%s = args[%d]" % (argName, i))
                else:
                    unwrapperModule = unwrappers[arg]
                    unwrapper = "unwrap" + arg
                    assignments.append("from %s import %s" (unwrapperModule,
                        unwrapper))
                    assignments.append("%s = %s(args[%d])" % (argName,
                        unwrapper, i))
            call = "self.%s(%s)" % (attr, ",".join(argNames))
        retvals = []
        if rv == "Any":
            # No wrapping.
            retvals.append("return rv")
        elif rv == "Void":
            # Enforced correctness. Disobedience will not be tolerated.
            retvals.append("assert rv is None, 'habanero'")
            retvals.append("from typhon.objects.constants import NullObject")
            retvals.append("return NullObject")
        else:
            wrapperModule = wrappers[rv]
            wrapper = "wrap" + rv
            retvals.append("from %s import %s" % (wrapperModule, wrapper))
            retvals.append("return %s(rv)" % wrapper)
        dispatchClauses.append("""
 if %s:
  %s
  rv = %s
  %s
""" % (atomTest, ";".join(assignments), call, ";".join(retvals)))
        setattr(cls, attr, f)
    # Temporary. Soon, all classes shall receive AutoHelp, and no class will
    # have a handwritten recv().
    if dispatchClauses:
        exec py.code.Source("""
def recv(self, atom, args):
 %s
 raise Refused(self, atom, args)
""" % "\n".join(dispatchClauses)).compile() in execNames
        cls.recv = execNames["recv"]

    return atoms


def autohelp(cls):
    """
    AutoHelp is here to help.

    Do not mock AutoHelp. AutoHelp should not be engaged manually. AutoHelp is
    here to help.
    """

    atomList = alterMethods(cls)
    atomDict = {k: None for k in atomList}

    def respondingAtoms(self):
        return atomDict

    cls.respondingAtoms = respondingAtoms

    return cls
