"""
Escape elision for several common cases of escape-expr.
"""

from typhon.nano.scopes import SCOPE_LOCAL, BoundNounsIR

def elideEscapes(ast):
    ast = ElideMethodReturn().visitExpr(ast)
    return ast

class FindUsage(BoundNounsIR.makePassTo(BoundNounsIR)):

    found = False

    def __init__(self, index):
        self.index = index

    def visitLocalExpr(self, name, index):
        if index == self.index:
            self.found = True
        return self.dest.LocalExpr(name, index)

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast,
                        layout):
        frameNames = layout.frameNames
        for name, (position, scope, index, severity) in frameNames.items():
            if scope is SCOPE_LOCAL and index == self.index:
                self.found = True
                break
        return self.dest.ObjectExpr(doc, patt, auditors, methods, matchers,
                                    mast, layout)

class ElideMethodReturn(BoundNounsIR.makePassTo(BoundNounsIR)):

    def pattIndex(self, patt):
        if isinstance(patt, self.dest.NounPatt):
            return patt.index
        elif isinstance(patt, self.dest.FinalSlotPatt):
            return patt.index
        elif isinstance(patt, self.dest.FinalBindingPatt):
            return patt.index
        else:
            return -1

    # XXX common code with t.n.auditors
    def unwrappingGet(self, expr):
        if (isinstance(expr, self.dest.CallExpr) and
                expr.verb == u"get" and
                len(expr.args) == len(expr.namedArgs) == 0):
            # Looks like a slot/binding .get/0 to me!
            return expr.obj
        return expr

    def visitEscapeOnlyExpr(self, patt, body):
        patt = self.visitPatt(patt)
        body = self.visitExpr(body)

        index = self.pattIndex(patt)
        if index == -1:
            # Nope, weird pattern.
            return self.dest.EscapeOnlyExpr(patt, body)

        if isinstance(body, self.dest.SeqExpr):
            exprs = body.exprs
            for i, expr in enumerate(exprs):
                if isinstance(expr, self.dest.CallExpr):
                    # Let's see what we called.
                    obj = expr.obj
                    # Bindings...
                    obj = self.unwrappingGet(obj)
                    # ...and slots.
                    obj = self.unwrappingGet(obj)
                    # We're looking for the locals.
                    if (isinstance(obj, self.dest.LocalExpr) and
                            obj.index == index):
                        # Hit! Check the rest of the call.
                        if (expr.verb == u"run" and len(expr.args) == 1 and
                                len(expr.namedArgs) == 0):
                            # Okay. Let's do the slice and return what's left.
                            seq = self.dest.SeqExpr(exprs[:i] + expr.args)
                            fu = FindUsage(index)
                            fu.visitExpr(seq)
                            if fu.found:
                                return self.dest.EscapeOnlyExpr(patt, seq)
                            else:
                                return seq
        return self.dest.EscapeOnlyExpr(patt, body)
