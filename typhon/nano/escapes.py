"""
Escape elision for several common cases of escape-expr.
"""

from typhon.nano.scopes import BoundNounsIR

def elideEscapes(ast):
    ast = ElideUnusedEscapes().visitExpr(ast)
    return ast

class ElideUnusedEscapes(BoundNounsIR.makePassTo(BoundNounsIR)):
    pass
