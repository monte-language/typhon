import py

from rpython.rlib.debug import debug_print
from rpython.rlib.unroll import unrolling_iterable


class CompilerFailed(Exception):
    """
    An invariant in the compiler failed.
    """

    def __init__(self, problem, span):
        self.problem = problem
        self.span = span

    def __str__(self):
        return self.formatError()

    def formatError(self):
        l = [
            u"Compiler invariant failed: " + self.problem,
        ]
        if self.span is not None:
            l += [
                u"In file '%s'" % self.span.source,
                u"Line %d, column %d" % (self.span.startLine,
                                         self.span.startCol),
            ]
        return u"\n".join(l).encode("utf-8")


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

        def tryAsTree(piece):
            try:
                return piece.asTree()
            except:
                return piece

        def build(tag, constructor, pieces):
            ipieces = unrolling_iterable(enumerate(pieces + [['span', None]]))
            class Constructor(NT):
                _immutable_ = True
                _immutable_fields_ = (["_constructorTag", "span"] +
                        [freezeField(field, ty) for field, ty in pieces])

                _constructorTag = tag

                def __init__(self, *args):
                    for i, (piece, _) in ipieces:
                        setattr(self, piece, args[i])

                def asTree(self):
                    "NOT_RPYTHON"
                    l = [constructor]
                    for i, (piece, ty) in ipieces:
                        if ty is None:
                            l.append(getattr(self, piece))
                        elif ty.endswith("*"):
                            l.append([tryAsTree(x) for x in getattr(self, piece)])
                        else:
                            l.append(tryAsTree(getattr(self, piece)))
                    return l

            Constructor.__name__ = name + "~" + constructor + str(increment())
            irAttrs[constructor] = Constructor

        for tag, (constructor, pieces) in enumerate(constructors.iteritems()):
            build(tag, constructor, pieces)

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
                    "args": ",".join(p[0] for p in pieces + [['span']]),
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
                tag = getattr(self, constructor)._constructorTag
                specimenPieces = ",".join("specimen.%s" % p[0] for p in pieces
                                          + [['span']])
                callVisit = "self.%s(%s)" % (visitName, specimenPieces)
                conClasses.append((tag, constructor, callVisit))
            # Construct subordinate clauses for the visitor on this
            # non-terminal.
            d = {}
            clauses = []
            for tag, constructor, callVisit in conClasses:
                ass = "assert isinstance(specimen, self.src.%s), 'donkey'" % constructor
                clauses.append("if tag == %d: %s; return %s" %
                        (tag, ass, callVisit))
            params = {
                "name": nonterm,
                "clauses": "\n    ".join(clauses),
            }
            exec py.code.Source("""
def visit%(name)s(self, specimen):
    assert isinstance(specimen, self.src._NonTerminal), "cabbage"
    tag = specimen._constructorTag
    %(clauses)s
    assert False, "radish"
            """ % params).compile() in d
            attrs.update(d)

        def errorWithSpan(self, problem, span):
            """
            Throw a fatal error with span information.
            """

            debug_print(problem.encode("utf-8"))
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

def withHoles(irClass):
    """
    Create an object similar to the IR class but for building an AST
    pattern-matching template rather than building an AST. Designed for use in
    unit tests.

    Note that this currently doesn't check the schema when constructing a
    quasi-AST so it's possible to construct a template that will not match any
    valid AST.
    """
    class IRMatcherInstance(object):
        def __init__(self, quasi, name, args, cls):
            self.quasi = quasi
            self.name = name
            self.args = args
            self.cls = cls

        def match(self, specimen):
            if not isinstance(specimen, self.cls):
                raise ValueError("Expected %s, got %s" % (
                    self.cls.__name__, type(specimen).__name__))
            for p, (argname, argtype) in zip(self.args,
                                             self.quasi.schema[self.name]):
                val = getattr(specimen, argname)
                if argtype is None or argtype in irClass.terminals:
                    if isinstance(p, IRHole):
                        p.match(val)
                        continue
                    elif val != p:
                        raise ValueError("Expected %r, got %r" % (p, val))
                    else:
                        continue
                if (argtype.endswith('*') and isinstance(p, list)):
                    for subp, item in zip(p, val):
                        subp.match(item)
                else:
                    p.match(val)
            return self.quasi.holeMatches

    class IRMatcher(object):
        def __init__(self, name, quasi, original):
            self.quasi = quasi
            self.name = name
            self.original = original

        def __call__(self, *a):
            if len(a) != len(self.quasi.schema[self.name]):
                raise ValueError("Expected %d arguments, got %d" % (
                    len(a), len(self.quasi.schema[self.name])))
            return IRMatcherInstance(self.quasi, self.name, a, self.original)

    class IRHole(object):
        def __init__(self, name, quasi, typeConstructor):
            self.name = name
            self.quasi = quasi
            self.typeConstructor = typeConstructor

        def match(self, specimen):
            if (self.typeConstructor is not None and
                not isinstance(specimen, self.typeConstructor)):
                raise ValueError("Expected %s, got %s" % (
                    self.typeConstructor.__name__, type(specimen).__name__))
            self.quasi.holeMatches[self.name] = specimen


    class QuasiIR(object):
        def __init__(self):
            self.holes = []
            self.holeMatches = {}

            self.schema = {}
            for nonterm, constructors in irClass.nonterms.iteritems():
                for constructor, pieces in constructors.iteritems():
                    self.schema[constructor] = pieces

        def __getattr__(self, name):
            return IRMatcher(name, self, getattr(irClass, name))

        def HOLE(self, name, typeConstructor=None):
            if typeConstructor is not None:
                if isinstance(typeConstructor, IRMatcher):
                    tycon = typeConstructor.original
                elif isinstance(typeConstructor, irClass._NonTerminal):
                    tycon = typeConstructor
                else:
                    raise ValueError("%s is not a type constructor for "
                                     "either %s or %s" % (typeConstructor, irClass, self))
            else:
                tycon = None
            h = IRHole(name, self, tycon)
            self.holes.append(h)
            return h

    return QuasiIR()
