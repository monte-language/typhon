import py

from rpython.rlib.unroll import unrolling_iterable


class CompilerFailed(Exception):
    """
    An invariant in the compiler failed.
    """

    def __init__(self, problem, span):
        self.problem = problem
        self.span = span

    def __str__(self):
        return self.formatError().encode("utf-8")

    def formatError(self):
        l = [
            u"Compiler invariant failed" #: " + self.problem,
        ]
        # if self.span is not None:
        #     l += [
        #         u"In file '%s'" % self.span.source,
        #         u"Line %d, column %d" % (self.span.startLine,
        #                                  self.span.startCol),
        #     ]
        return u"\n".join(l)


def freezeField(field, ty):
    if ty and ty.endswith("*"):
        # List.
        return field + "[*]"
    return field

def increment(x=[0]):
    x[0] += 1
    return x[0]

def makeIR(name, terminals, nonterms):
    irAttrs = {
        "_immutable_": True,
        "_immutable_fields_": ("terminals[*]", "nonterms"),
        "terminals": terminals,
        "nonterms": nonterms,
    }

    # The parent class of all nonterminals. Important for manipulating
    # ASTs in RPython.
    class NonTerminal(object):
        _immutable_ = True
    # Please do *not* access this class outside of this implementation; it
    # won't end well. ~ C.
    irAttrs["_NonTerminal"] = NonTerminal

    for nonterm, constructors in nonterms.iteritems():
        # Construct a superclass which every constructor will inherit
        # from.
        class NT(NonTerminal):
            _immutable_ = True
        NT.__name__ = name + "~" + nonterm + str(increment())
        irAttrs[nonterm] = NT

        def build(constructor, pieces):
            ipieces = unrolling_iterable(enumerate(pieces))
            class Constructor(NT):
                _immutable_ = True
                _immutable_fields_ = [freezeField(field, ty)
                                      for field, ty in pieces]

                def __init__(self, *args):
                    for i, (piece, _) in ipieces:
                        setattr(self, piece, args[i])

                def asTree(self):
                    "NOT_RPYTHON"
                    l = [constructor]
                    for piece, ty in pieces:
                        if ty is None:
                            l.append(getattr(self, piece))
                        elif ty.endswith("*"):
                            l.append([x.asTree() for x in getattr(self, piece)])
                        else:
                            try:
                                l.append(getattr(self, piece).asTree())
                            except:
                                l.append(getattr(self, piece))
                    return l

            Constructor.__name__ = name + "~" + constructor + str(increment())
            irAttrs[constructor] = Constructor

        for constructor, pieces in constructors.iteritems():
            build(constructor, pieces)

    def makePassTo(self, ir):
        """
        Construct a class for a visitor-pattern pass between this IR and the
        next IR.
        """

        attrs = { "src": self, "dest": ir }
        for terminal in self.terminals:
            def visitor(self, x):
                return x
            name = "visit" + terminal
            visitor.__name__ = name
            attrs[name] = visitor

        for nonterm, constructors in self.nonterms.iteritems():
            conClasses = []
            for constructor, pieces in constructors.iteritems():
                visitName = "visit%s" % constructor
                # Recurse on non-terminals by type. Untyped elements are
                # assumed to not be recursive.
                mods = []
                for piece, ty in pieces:
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
                    "args": ",".join(p[0] for p in pieces),
                    "name": visitName,
                    "constructor": constructor,
                    "mods": ";".join(mods)
                }
                if ir is None:
                    # This pass extracts some sort of summary but does not
                    # create more IR. Force the caller to override every
                    # non-terminal.
                    def mustImplement(self, *args):
                        "NOT_RPYTHON"
                        import pdb; pdb.set_trace()
                        raise NotImplementedError("rutabaga")
                    attrs[visitName] = mustImplement
                else:
                    d = {}
                    exec py.code.Source("""
                        def %(name)s(self, %(args)s):
                            %(mods)s
                            return self.dest.%(constructor)s(%(args)s)
                    """ % params).compile() in d
                    attrs[visitName] = d[visitName]
                    attrs[visitName].__name__ += str(increment())
                specimenPieces = ",".join("specimen.%s" % p[0] for p in pieces)
                callVisit = "self.%s(%s)" % (visitName, specimenPieces)
                conClasses.append((constructor, callVisit))
            # Construct subordinate clauses for the visitor on this
            # non-terminal.
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
    assert isinstance(specimen, self.src._NonTerminal), "cabbage"
    %(clauses)s
    assert False, "radish"
            """ % params).compile() in d
            attrs.update(d)

        def errorWithSpan(self, problem, span):
            """
            Throw a fatal error with span information.
            """

            raise CompilerFailed(problem, span)
        attrs["errorWithSpan"] = errorWithSpan

        Pass = type("Pass", (object,), attrs)
        # This isn't really a knot so much as a quick and easy way to access
        # the original implementations of the pass's methods. ~ C.
        Pass.super = Pass
        return Pass
    irAttrs["makePassTo"] = makePassTo

    def extend(self, name, terminals, nonterms):
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
        # Dammit Python.
        nts = self.nonterms.copy()
        for nt, constructors in nonterms.iteritems():
            # Recurse into every constructor, if we already have the
            # non-terminal. Otherwise, just copy the new thing wholesale.
            if nt.startswith("-"):
                # Remove the entire non-terminal.
                nt = nt[1:]
                del nts[nt]
            elif nt in nts:
                # Dammit Python!
                nts[nt] = nts[nt].copy()
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
        return makeIR(name, ts, nts)
    irAttrs["extend"] = extend

    def selfPass(self):
        return self.makePassTo(self)
    irAttrs["selfPass"] = selfPass

    return type(name + "IR", (object,), irAttrs)()
