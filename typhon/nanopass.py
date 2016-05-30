import py

from rpython.rlib.unroll import unrolling_iterable

def freezeField(field, ty):
    if ty and ty.endswith("*"):
        # List.
        return field + "[*]"
    return field

class IR(object):
    """
    An intermediate representation.
    """

    _immutable_ = True
    _immutable_fields = "terminals[*]", "nonterms"

    def __init__(self, terminals, nonterms):
        self.terminals = terminals
        self.nonterms = nonterms

        for nonterm, constructors in nonterms.iteritems():
            # Construct a superclass which every constructor will inherit
            # from.
            class NT(object):
                _immutable_ = True
            NT.__name__ = nonterm

            def build(constructor, pieces):
                class Constructor(NT):
                    _immutable_ = True
                    _immutable_fields_ = [freezeField(field, ty)
                                          for field, ty
                                          in pieces.iteritems()]

                    def __init__(self, *args):
                        for i, piece in unrolling_iterable(enumerate(pieces)):
                            setattr(self, piece, args[i])
                Constructor.__name__ = constructor
                setattr(self, constructor, Constructor)

            for constructor, pieces in constructors.iteritems():
                build(constructor, pieces)

    def makePassTo(self, ir):
        """
        Construct a class for a visitor-pattern pass between this IR and the
        next IR.
        """

        attrs = { "src": self, "dest": ir }
        for terminal in self.terminals:
            def visitor(x):
                return x
            visitor.__name__ = terminal
            attrs[terminal] = visitor

        for nonterm, constructors in self.nonterms.iteritems():
            conClasses = []
            for constructor, pieces in constructors.iteritems():
                visitName = "visit%s" % constructor
                # Recurse on non-terminals by type. Untyped elements are
                # assumed to not be recursive.
                mods = []
                for piece, ty in pieces.iteritems():
                    if ty:
                        if ty.endswith('*'):
                            # List of elements.
                            ty = ty[:-1]
                            s = "%s = [self.visit%s(x) for x in %s]" % (piece,
                                    ty, piece)
                        else:
                            s = "%s = self.visit%s(%s)" % (piece, ty, piece)
                        mods.append(s)
                params = {
                    "args": ",".join(pieces),
                    "name": visitName,
                    "constructor": constructor,
                    "mods": ";".join(mods)
                }
                d = {}
                exec py.code.Source("""
                    def %(name)s(self, %(args)s):
                        %(mods)s
                        return self.dest.%(constructor)s(%(args)s)
                """ % params).compile() in d
                attrs[visitName] = d[visitName]
                specimenPieces = ",".join("specimen.%s" % k for k in pieces)
                callVisit = "self.%s(%s)" % (visitName, specimenPieces)
                conClasses.append((constructor, callVisit))
            # Construct subordinate clauses for the visitor on this
            # constructor.
            d = {}
            clauses = []
            for constructor, callVisit in conClasses:
                clauses.append("if isinstance(specimen, self.src.%s): return %s" %
                        (constructor, callVisit))
            params = {
                "name": nonterm,
                "clauses": "\n    ".join(clauses),
            }
            exec py.code.Source("""
def visit%(name)s(self, specimen):
    %(clauses)s
    assert False, "Implementation error"
            """ % params).compile() in d
            attrs.update(d)

        return type("Pass", (object,), attrs)

    def extend(self, terminals, nonterms):
        ts = self.terminals[:]
        for t in terminals:
            if t.startswith("-"):
                # Removal.
                t = t[1:]
                # I wanted to put an assert here, but list.remove() raises
                # ValueError already, so it's not a problem. ~ C.
                ts.remove(t)
            else:
                # Addition.
                ts.append(t)
        nts = self.nonterms.copy()
        for nt, constructors in nonterms.iteritems():
            # Recurse into every constructor, if we already have the
            # non-terminal. Otherwise, just copy the new thing wholesale.
            if nt in nts:
                for constructor, pieces in constructors.iteritems():
                    if constructor.startswith("-"):
                        # Removal.
                        constructor = constructor[1:]
                        # As before, raise if not found.
                        del nts[nt][constructor]
                    else:
                        # Addition to a possibly-already-extant constructor.
                        # We'll overwrite the old constructor with the new.
                        nts[nt][constructor] = pieces
            else:
                nts[nt] = constructors
        return IR(ts, nts)

MastIR = IR(
    ["Noun"],
    {
        "Expr": {
            "NullExpr": {},
            "IntExpr": { "i": None },
            "NounExpr": { "noun": "Noun" },
            "HideExpr": { "body": "Expr" },
            "SeqExpr": { "exprs": "Expr*" },
        },
        "Patt": {
            "FinalPatt": { "noun": "Noun", "guard": "Expr" },
        },
    }
)

class IncPass(MastIR.makePassTo(MastIR)):

    def visitIntExpr(self, i):
        return self.dest.IntExpr(i + 1)

NoHideIR = MastIR.extend([], {"Expr": {"-HideExpr": None}})

class RemoveHide(MastIR.makePassTo(NoHideIR)):

    def visitHideExpr(self, body):
        return self.visitExpr(body)
