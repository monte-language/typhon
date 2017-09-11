"""
Slot expression and pattern recovery.
"""

from typhon.nano.mast import SaveScriptIR

def recoverSlots(ast):
    ast = RemoveAssign().visitExpr(ast)
    return ast

NoAssignIR = SaveScriptIR.extend("NoAssign", [],
    {
        "Expr": {
            "-AssignExpr": None,
            "SlotExpr": [("name", "Noun")],
            "TempNounExpr": [("name", "Noun")],
        },
        "Patt": {
            "TempPatt": [("name", "Noun")],
        }
    }
)

class RemoveAssign(SaveScriptIR.makePassTo(NoAssignIR)):
    def visitAssignExpr(self, name, rvalue, span):
        rvalue = self.visitExpr(rvalue)
        # { def temp := rvalue; &name.put(temp); temp }
        temp = self.dest.TempNounExpr(u"_tempAssign", span)
        null = self.dest.NullExpr(span)
        return self.dest.HideExpr(self.dest.SeqExpr([
            self.dest.DefExpr(self.dest.TempPatt(u"_tempAssign", span), null,
                              rvalue, span),
            self.dest.CallExpr(self.dest.SlotExpr(name, span), u"put", [temp],
                               [], span), temp], span), span)
