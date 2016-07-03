"""
Structural refactoring to improve the efficiency of the AST interpreter.
"""

from rpython.rlib import rvmprof

from typhon.atoms import getAtom
from typhon.nano.scopes import ReifyMetaIR

def refactorStructure(ast):
    ast = SplitScript().visitExpr(ast)
    ast = MakeAtoms().visitExpr(ast)
    ast = MakeProfileNames().visitExpr(ast)
    return ast

SplitScriptIR = ReifyMetaIR.extend("SplitScript", [],
    {
        "Expr": {
            "ObjectExpr": [("doc", None), ("patt", "Patt"),
                           ("auditors", "Expr*"), ("script", "Script"),
                           ("mast", None), ("layout", None)],
        },
        "Script": {
            "ScriptExpr": [("methods", "Method*"),
                           ("matchers", "Matcher*")],
        },
    }
)

class SplitScript(ReifyMetaIR.makePassTo(SplitScriptIR)):

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast,
            layout):
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        methods = [self.visitMethod(method) for method in methods]
        matchers = [self.visitMatcher(matcher) for matcher in matchers]
        script = self.dest.ScriptExpr(methods, matchers)
        return self.dest.ObjectExpr(doc, patt, auditors, script, mast, layout)

AtomIR = SplitScriptIR.extend("Atom", [],
    {
        "Expr": {
            "CallExpr": [("obj", "Expr"), ("atom", None), ("args", "Expr*"),
                         ("namedArgs", "NamedArg*")],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("atom", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr"), ("localSize", None)],
        },
    }
)

class MakeAtoms(SplitScriptIR.makePassTo(AtomIR)):

    def visitCallExpr(self, obj, verb, args, namedArgs):
        obj = self.visitExpr(obj)
        atom = getAtom(verb, len(args))
        args = [self.visitExpr(arg) for arg in args]
        namedArgs = [self.visitNamedArg(namedArg) for namedArg in namedArgs]
        return self.dest.CallExpr(obj, atom, args, namedArgs)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body,
                        localSize):
        atom = getAtom(verb, len(patts))
        patts = [self.visitPatt(patt) for patt in patts]
        namedPatts = [self.visitNamedPatt(namedPatt) for namedPatt in
                namedPatts]
        guard = self.visitExpr(guard)
        body = self.visitExpr(body)
        return self.dest.MethodExpr(doc, atom, patts, namedPatts, guard, body,
                                    localSize)

ProfileNameIR = AtomIR.extend("ProfileName",
    ["ProfileName"],
    {
        "Method": {
            "MethodExpr": [("profileName", "ProfileName"), ("doc", None),
                           ("atom", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr"), ("localSize", None)],
        },
        "Matcher": {
            "MatcherExpr": [("profileName", "ProfileName"), ("patt", "Patt"),
                            ("body", "Expr"), ("localSize", None)],
        },
    }
)

# super() doesn't work in RPython, so this is a way to get at the default
# implementations of the pass methods. ~ C.
_MakeProfileNames = AtomIR.makePassTo(ProfileNameIR)
class MakeProfileNames(_MakeProfileNames):
    """
    Prebuild the strings which identify code objects to the profiler.

    This must be the last pass before evaluation, or else profiling will not
    work because the wrong objects will have been registered.
    """

    def __init__(self):
        # NB: self.objectNames cannot be empty unless we somehow obtain a
        # method/matcher without a body. ~ C.
        self.objectNames = []

    def visitObjectExpr(self, doc, patt, auditors, script, mast, layout):
        # Push, do the recursion, pop.
        if isinstance(patt, self.src.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        self.objectNames.append((objName.encode("utf-8"),
            layout.fqn.encode("utf-8").split("$")[0]))
        rv = _MakeProfileNames.visitObjectExpr(self, doc, patt, auditors,
                script, mast, layout)
        self.objectNames.pop()
        return rv

    def makeProfileName(self, inner):
        name, fqn = self.objectNames[-1]
        return "mt:%s.%s:1:%s" % (name, inner, fqn)

    def visitMethodExpr(self, doc, atom, patts, namedPatts, guard, body,
            localSize):
        # NB: `atom.repr` is tempting but wrong. ~ C.
        description = "%s/%d" % (atom.verb.encode("utf-8"), atom.arity)
        profileName = self.makeProfileName(description)
        patts = [self.visitPatt(patt) for patt in patts]
        namedPatts = [self.visitNamedPatt(namedPatt) for namedPatt in
                namedPatts]
        guard = self.visitExpr(guard)
        body = self.visitExpr(body)
        rv = self.dest.MethodExpr(profileName, doc, atom, patts, namedPatts,
                guard, body, localSize)
        rvmprof.register_code(rv, lambda method: method.profileName)
        return rv

    def visitMatcherExpr(self, patt, body, localSize):
        profileName = self.makeProfileName("matcher")
        patt = self.visitPatt(patt)
        body = self.visitExpr(body)
        rv = self.dest.MatcherExpr(profileName, patt, body, localSize)
        rvmprof.register_code(rv, lambda matcher: matcher.profileName)
        return rv

# Register the interpreted code classes with vmprof.
rvmprof.register_code_object_class(ProfileNameIR.MethodExpr,
        lambda method: method.profileName)
rvmprof.register_code_object_class(ProfileNameIR.MatcherExpr,
        lambda matcher: matcher.profileName)
