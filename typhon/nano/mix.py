"""
Partial evaluation.

This version of mixing is based on two separate stages. First, we stir the
outer names into the AST, closing its object graph. Second, we perform
whatever partial evaluation we like on the AST.

The separation allows us to make the first part short and sweet.
"""

from typhon.nano.structure import SplitAuditorsIR

def mix(ast, outers):
    ast = FillOuters(outers).visitExpr(ast)
    return ast

MixIR = SplitAuditorsIR.extend("Mix",
    ["Object"],
    {
        "Expr": {
            "LiveExpr": [("obj", "Object")],
            "-OuterExpr": None,
        }
    }
)

class FillOuters(SplitAuditorsIR.makePassTo(MixIR)):

    def __init__(self, outers):
        self.outers = outers

    def visitOuterExpr(self, name, index):
        return self.dest.LiveExpr(self.outers[index])
