# Hello. Welcome to AutoHelp. We hope that you enjoy your stay. AutoHelp is
# undergoing an upgrade. AutoHelp will be upgraded to the latest version of
# Auto, and additionally to the latest version of Help. Nothing can escape
# upgraded AutoHelp.

import py

from typhon.atoms import getAtom
from typhon.errors import Refused


def method(rv, *args, **kwargs):
    """
    Mark a method as being exposed to Monte with a given type layout.

    The first type must be the return value.

    NOT_RPYTHON
    """

    # Mark methods that must be automatically helped. Record an unprocessed
    # tuple of (args, namedArgs, returnGuard).

    def deco(f):
        verb = kwargs.pop("_verb", f.__name__)
        # This method shall be isolated, repacked, wrapped, and helped.
        f._monteMethod_ = verb, args, kwargs, rv, False
        return f
    return deco

def method_py(rv, *args, **kwargs):
    """
    Like @method, but with the resulting method also being accessible via
    RPython.

    NOT_RPYTHON
    """

    def deco(f):
        verb = kwargs.pop("_verb", f.__name__)
        # This method shall be spared.
        f._monteMethod_ = verb, args, kwargs, rv, True
        return f
    return deco

# AutoHelp is working around a technical limitation of nomenclature.
method.py = method_py

def isStarArgs(args):
    return len(args) == 1 and args[0][0] == '*'

def repackMonteMethods(cls):
    """
    Adjust the internal locations of Monte methods.

    AutoHelp requires Monte methods to be in a particular location.

    NOT_RPYTHON
    """

    methods = {}
    # vars() returns a view which is corrupted by mutation during iteration.
    # AutoHelp introduces an inefficient workaround. Please add @autohelp to
    # the definition site of vars() so that AutoHelp may make vars() more
    # efficient.
    for k, v in vars(cls).copy().iteritems():
        if hasattr(v, "_monteMethod_"):
            verb, args, kwargs, rv, spare = v._monteMethod_
            if spare:
                # Remove the mark of AutoHelp from the method and permit it to
                # play in the valley with its brethren.
                del v._monteMethod_
            else:
                delattr(cls, k)
            if isStarArgs(args):
                k = "_%s_%s_star_args_" % (cls.__name__, k)
            else:
                k = "_%s_%s_%s_" % (cls.__name__, k, "_".join(args))
            methods[k] = v, verb, args, kwargs, rv
    cls._monteMethods_ = methods


wrappers = {
    "BigInt": "typhon.objects.data",
    "Bool": "typhon.objects.constants",
    "Bytes": "typhon.objects.data",
    "Char": "typhon.objects.data",
    "Double": "typhon.objects.data",
    "FingerList": "typhon.objects.collections.lists",
    "Int": "typhon.objects.data",
    "List": "typhon.objects.collections.lists",
    "Map": "typhon.objects.collections.maps",
    "Set": "typhon.objects.collections.sets",
    "Str": "typhon.objects.data",
}


def alterMethods(cls):
    """
    Alter Monte methods on behalf of AutoHelp.

    Return the signatures of the altered methods.

    NOT_RPYTHON
    """

    atoms = []
    imports = set()

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
    for attr, (f, verb, args, kwargs, rv) in d.iteritems():
        # The verb is now Unicode.
        verb = verb.decode("utf-8")
        assignments = []
        if isStarArgs(args):
            atomTest = "atom.verb == %r" % verb
            call = "self.%s(args)" % attr
        else:
            atomName = nextName()
            execNames[atomName] = atom = getAtom(verb, len(args))
            atoms.append(atom)
            atomTest = "atom is %s" % atomName
            argNames = []
            for i, arg in enumerate(args):
                argName = nextName()
                argNames.append(argName)
                assignments.append("%s = args[%d]" % (argName, i))
                if arg != "Any":
                    unwrapperModule = wrappers[arg]
                    pred = "is" + arg
                    imports.add("from %s import %s" % (unwrapperModule, pred))
                    atomTest += " and %s(args[%d])" % (pred, i)
                    unwrapper = "unwrap" + arg
                    imports.add("from %s import %s" % (unwrapperModule,
                        unwrapper))
                    assignments.append("%s = %s(%s)" % (argName, unwrapper,
                        argName))
            for k, v in kwargs.iteritems():
                kwargName = nextName()
                argNames.append("%s=%s" % (k, kwargName))
                assignments.append("%s = namedArgs.extractStringKey(%r, None)"
                        % (kwargName, k.decode("utf-8")))
                if v != "Any":
                    unwrapperModule = wrappers[v]
                    unwrapper = "unwrap" + v
                    imports.add("from %s import %s" % (unwrapperModule,
                        unwrapper))
                    assignments.append("%s = %s(%s) if %s is None else None" %
                            (kwargName, unwrapper, kwargName, kwargName))
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
            imports.add("from %s import %s" % (wrapperModule, wrapper))
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
def recvNamed(self, atom, args, namedArgs):
 %s
 %s
 rv = self.mirandaMethods(atom, args, namedArgs)
 if rv is None:
  raise Refused(self, atom, args)
 else:
  return rv
""" % (";".join(imports), "\n".join(dispatchClauses))).compile() in execNames
        cls.recvNamed = execNames["recvNamed"]

    return atoms


def autohelp(cls):
    """
    AutoHelp is here to help.

    Do not mock AutoHelp. AutoHelp should not be engaged manually. AutoHelp is
    here to help.

    NOT_RPYTHON
    """

    # Must only be done once.
    repackMonteMethods(cls)

    atomList = alterMethods(cls)
    atomDict = {k: None for k in atomList}

    def respondingAtoms(self):
        return atomDict

    cls.respondingAtoms = respondingAtoms

    return cls
