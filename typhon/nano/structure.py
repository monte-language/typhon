"""
Structural refactoring to improve the efficiency of the AST interpreter.
"""

from typhon.atoms import getAtom
from typhon.nano.scopes import ReifyMetaIR

def refactorStructure(ast):
    ast = SplitScript().visitExpr(ast)
    ast = MakeAtoms().visitExpr(ast)
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
