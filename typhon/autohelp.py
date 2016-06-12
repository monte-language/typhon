# Hello. Welcome to AutoHelp. We hope that you enjoy your stay. AutoHelp is
# undergoing an upgrade. AutoHelp will be upgraded to the latest version of
# Auto, and additionally to the latest version of Help. Nothing can escape
# upgraded AutoHelp.

import py

from typhon.atoms import getAtom
from typhon.errors import Refused


def method(rv, *args, **kwargs):
    "NOT_RPYTHON"

    verb = kwargs.pop("_verb", "run")

    # Mark methods that must be automatically helped. Record an unprocessed
    # tuple of (args, namedArgs, returnGuard).

    def deco(f):
        # This method shall be isolated, repacked, wrapped, and helped.
        f._monteMethod_ = verb, args, kwargs, rv, False
        return f
    return deco

def method_py(rv, *args, **kwargs):
    "NOT_RPYTHON"

    verb = kwargs.pop("_verb", "run")

    def deco(f):
        # This method shall be spared.
        f._monteMethod_ = verb, args, kwargs, rv, True
        return f
    return deco

# AutoHelp is working around a technical limitation of nomenclature.
method.py = method_py

def repackMonteMethods(cls):
    """
    Adjust the internal locations of Monte methods.

    AutoHelp requires Monte methods to be in a particular location.
    """

    methods = {}
    # vars() returns a view which is corrupted by mutation during iteration.
    # AutoHelp introduces an inefficient workaround. Please add @autohelp to
    # the definition site of vars() so that AutoHelp may make vars() more
    # efficient.
    for k, v in vars(cls).copy().iteritems():
        if hasattr(v, "_monteMethod_"):
            verb, args, kwargs, rv, spare = v._monteMethod_
            methods[k] = v, args, kwargs, rv
            if spare:
                # Remove the mark of AutoHelp from the method and permit it to
                # play in the valley with its brethren.
                del v._monteMethod_
            else:
                delattr(cls, k)
    cls._monteMethods_ = methods


unwrappers = {
    "Bool": "typhon.objects.constants",
    "Int": "typhon.objects.data",
    "List": "typhon.objects.collections.lists",
    "Map": "typhon.objects.collections.maps",
    "Str": "typhon.objects.data",
}

wrappers = {
    "Bool": "typhon.objects.constants",
    "Int": "typhon.objects.data",
    "List": "typhon.objects.collections.lists",
    "Map": "typhon.objects.collections.maps",
    "Str": "typhon.objects.data",
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
    d = {}
    # Walk the MRO and harvest Monte methods. The repacker has already placed
    # them in the correct location.
    for c in reversed(cls.__mro__):
        if hasattr(c, "_monteMethods_"):
            d.update(c._monteMethods_)
    for attr, (f, args, kwargs, rv) in d.iteritems():
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
                    assignments.append("from %s import %s" % (unwrapperModule,
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

    # Must only be done once.
    repackMonteMethods(cls)

    atomList = alterMethods(cls)
    atomDict = {k: None for k in atomList}

    def respondingAtoms(self):
        return atomDict

    cls.respondingAtoms = respondingAtoms

    return cls
