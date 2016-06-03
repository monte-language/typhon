from typhon.nano.mast import SaveScriptIR

"""
Static scope analysis, in several passes:
 * De Bruijn indices
 * Frame specialization
 * Escape analysis
 * Slot specialization
 * Deslotification
"""

DeBruijnIR = SaveScriptIR.extend("De Bruijn", ["Index", "-Noun"],
    {
        "Expr": {
            "AssignExpr": [("index", "Index"), ("rvalue", "Expr")],
            "BindingExpr": [("index", "Index")],
            "NounExpr": [("index", "Index")],
        },
        "Patt": {
            "BindingPatt": [("index", "Index")],
            "FinalPatt": [("index", "Index"), ("guard", "Expr")],
            "VarPatt": [("index", "Index"), ("guard", "Expr")],
        },
    }
)

class AssignDeBruijn(SaveScriptIR.makePassTo(DeBruijnIR)):

    def __init__(self):
        self.scopeStack = [[]]

    def boundNames(self):
        return self.scopeStack[-1]

    def push(self):
        self.scopeStack.append([])

    def pop(self):
        return self.scopeStack.pop()

    def visitNoun(self, name):
        boundNames = self.boundNames()
        try:
            return boundNames.index(name)
        except ValueError:
            rv = len(boundNames)
            boundNames.append(name)
            return rv
