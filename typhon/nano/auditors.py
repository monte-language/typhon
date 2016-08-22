# -*- coding: utf-8 -*-

"""
Static discharge of auditors.
"""

from typhon.nano.scopes import BoundNounsIR

def dischargeAuditors(ast):
    ast = DischargeDF().visitExpr(ast)
    return ast

DeepFrozenIR = BoundNounsIR.extend("DeepFrozen", [],
    {
        "Expr": {
            "LiveExpr": [("obj", None)],
        },
    }
)

class DischargeDF(BoundNounsIR.makePassTo(DeepFrozenIR)):
    pass
