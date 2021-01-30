import "lib/mim/syntax/anf" =~ ["ASTBuilder" => anf]
exports (anf, makeNormal)

# http://matt.might.net/articles/a-normalization/

def id(x) as DeepFrozen:
    return x

def nameForPatt(patt) :NullOk[Str] as DeepFrozen:
    return patt(object pattNamer {
        to IgnorePattern(_, _) { return null }
        to FinalPattern(noun, _, _) { return noun }
    })

def Atom :DeepFrozen := anf.atom()
def Complex :DeepFrozen := anf.complex()

def makeNormal() as DeepFrozen:
    var counter :Int := 0
    def gensym() :Str:
        counter += 1
        return `_temp_anf_sym$counter`
    def letsym(complex :Complex, span):
        return fn k {
            # k() wants a noun as a Str.
            def sym :Str := gensym()
            anf.LetExpr(anf.FinalPattern(sym, null, span), complex, k(sym), span)
        }
    def escapesym(span):
        return fn k {
            # k() wants a noun as a Str.
            def sym :Str := gensym()
            anf.EscapeExpr(anf.FinalPattern(sym, null, span), k(sym), span)
        }
    # Easy calls without named args when everything is already an atom. The
    # return value in the continuation is also an atom.
    def callsym(receiver :Atom, verb :Str, args :List[Atom], span):
        return fn k {
            # k() wants a noun as an Atom.
            letsym(anf.MethodCallExpr(receiver, verb, args, [], span),
                   span)(fn rv { k(anf.NounExpr(rv, span)) })
        }

    # We are doing a sort of context-passing. Each k() is a hole for placing a
    # value into the caller's context. Indeed, k is for kontinuation.

    return object normal:
        to name(m):
            return fn k {
                # k() wants an atom.
                normal(m)(fn n {
                    n.walk(object namer {
                        match [constructor, args, _] {
                            switch (constructor) {
                                match =="Atom" { k(args[0]) }
                                match =="LiteralExpr" { k(n) }
                                match =="NounExpr" { k(n) }
                                match =="BindingExpr" { k(n) }
                                match _ {
                                    letsym(n, null)(fn t { k(anf.NounExpr(t, null)) })
                                }
                            }
                        }
                    })
                })
            }

        to names(ms :List):
            return fn k {
                # k() wants a list of atoms.
                switch (ms) {
                    match [] { k([]) }
                    match [m] + tail {
                        normal.name(m)(fn n {
                            normal.names(tail)(fn ns { k([n] + ns) })
                        })
                    }
                }
            }

        to matchBind(patt, specimen :Atom, ej :Atom):
            return fn k {
                # k() wants nothing. It should be run after `patt` is bound.
                patt.walk(object normalizer {
                    to IgnorePattern(guard, span) {
                        return if (guard == null) { k() } else {
                            normal.name(guard)(fn g {
                                anf.LetExpr(anf.IgnorePattern(span),
                                            anf.MethodCallExpr(g, "coerce",
                                                               [specimen, ej], [],
                                                               span),
                                            k())
                            })
                        }
                    }
                    to BindingPattern(name, span) {
                        return anf.LetExpr(anf.BindingPattern(name, span),
                                           anf.Atom(specimen, span),
                                           k(), span)
                    }
                    to FinalPattern(name, guard, span) {
                        return if (guard == null) {
                            anf.LetExpr(anf.FinalPattern(name, null, span),
                                        anf.Atom(specimen, span),
                                        k(), span)
                        } else {
                            normal(guard)(fn g {
                                letsym(g, span)(fn ng {
                                    anf.LetExpr(anf.FinalPattern(name, ng, span),
                                                anf.Atom(specimen, span),
                                                k(), span)
                                })
                            })
                        }
                    }
                    to VarPattern(name, guard, span) {
                        return if (guard == null) {
                            anf.LetExpr(anf.VarPattern(name, null, span),
                                        anf.Atom(specimen, span),
                                        k(), span)
                        } else {
                            normal(guard)(fn g {
                                letsym(g, span)(fn ng {
                                    anf.LetExpr(anf.VarPattern(name, ng, span),
                                                anf.Atom(specimen, span),
                                                k(), span)
                                })
                            })
                        }
                    }
                    to ViaPattern(trans, subpatt, span) {
                        return normal.name(trans)(fn t {
                            callsym(trans, "run", [specimen, ej], span)(fn s {
                                normal.matchBind(subpatt, anf.NounExpr(s, span), ej)(k)
                            })
                        })
                    }
                    to ListPattern(patts, tail, span) {
                        def listGuard := anf.NounExpr("List", span)
                        def pattSize := anf.LiteralExpr(patts.size(), span)
                        def zeroVerb := (tail == null).pick("isZero", "atLeastZero")
                        return callsym(listGuard, "coerce", [specimen, ej], span)(fn l {
                            def go(i) {
                                return if (i >= patts.size()) {
                                    if (tail == null) { k() } else {
                                        callsym(l, "slice", [pattSize], span)(fn rest {
                                            normal.matchBind(tail, rest, ej)(k)
                                        })
                                    }
                                } else {
                                    def index := anf.LiteralExpr(i, span)
                                    callsym(l, "get", [index], span)(fn s {
                                        normal.matchBind(patts[i], s, ej)(fn {
                                            go(i + 1)
                                        })
                                    })
                                }
                            }
                            def tower := go(0)

                            def fail := anf.MethodCallExpr(
                                anf.NounExpr("throw", span),
                                "eject",
                                [ej, anf.LiteralExpr(`List pattern needed ${patts.size()} elements`, span)],
                                [], span)

                            callsym(l, "size", [], span)(fn size {
                                callsym(size, "subtract", [pattSize], span)(fn rem {
                                    callsym(rem, zeroVerb, [], span)(fn b {
                                        anf.IfExpr(b, tower, fail, span)
                                    })
                                })
                            })
                        })
                    }
                })
            }

        to run(expr):
            return fn k {
                # k() wants a complex expression.
                expr.walk(object normalizer {
                    to LiteralExpr(value, span) {
                        return k(anf.Atom(anf.LiteralExpr(value, span), span))
                    }
                    to NounExpr(value, span) {
                        return k(anf.Atom(anf.NounExpr(value, span), span))
                    }
                    to BindingExpr(value, span) {
                        return k(anf.Atom(anf.BindingExpr(value, span), span))
                    }
                    to ObjectExpr(docstring, namePatt, asExpr, auditors, script,
                                  span) {
                        # XXX script
                        # XXX names can be null?
                        def name :NullOk[Str] := nameForPatt(namePatt)
                        return normal.name(asExpr)(fn a {
                            normal.names(auditors)(fn auds {
                                k(anf.Atom(anf.ObjectExpr(docstring, name, a, auds, script,
                                                          span), span))
                            })
                        })
                    }
                    to MethodCallExpr(receiver, verb :Str, args, namedArgs, span) {
                        # XXX namedArgs
                        return normal.name(receiver)(fn r {
                            normal.names(args)(fn ars {
                                normal.names(namedArgs)(fn nas {
                                    k(anf.MethodCallExpr(r, verb, ars, nas, span))
                                })
                            })
                        })
                    }
                    to FinallyExpr(body, unwinder, span) {
                        return k(anf.FinallyExpr(normal.alpha(body), normal.alpha(unwinder), span))
                    }
                    to IfExpr(test, cons, alt, span) {
                        return normal.name(test, fn t {
                            k(anf.IfExpr(t, normal.alpha(cons), normal.alpha(alt), span))
                        })
                    }
                    to EscapeExpr(ejPatt, body, catchPatt, catchBody, span) {
                        return k(if (catchPatt == null || catchBody == null) {
                            # Easy case: Nothing much changes.
                            escapesym(span)(fn ej {
                                normal.matchBind(ejPatt, anf.NounExpr(ej, span),
                                                 null)(fn { normal.alpha(body) })
                            })
                        } else {
                            # Tricky case: Turn the catcher into a second ejector
                            # on the outside.
                            escapesym(span)(fn rv {
                                def inner := escapesym(span)(fn ej {
                                    normal.matchBind(ejPatt, anf.NounExpr(ej, span),
                                                     null)(fn {
                                        normal.name(normal.alpha(body))(fn b {
                                            anf.JumpExpr(anf.NounExpr(rv, span),
                                                         b, span)
                                        })
                                    })
                                })
                                letsym(inner, span)(fn i {
                                    normal.matchBind(catchPatt,
                                                     anf.NounExpr(i, span),
                                                     null)(fn {
                                         normal.alpha(catchBody)
                                    })
                                })
                            })
                        })
                    }
                    # These expressions are compiled away entirely.
                    to HideExpr(expr, _span) { return k(expr.walk(normalizer)) }
                    to DefExpr(patt, ex, expr, span) {
                        def finishDef(x) {
                            return normal.name(expr)(fn e {
                                normal.matchBind(patt, e, x)(fn {
                                    k(anf.Atom(e, span))
                                })
                            })
                        }
                        return if (ex == null) {
                            # XXX is this a good idea?
                            finishDef(anf.NounExpr("null", span))
                        } else {
                            normal.name(ex)(finishDef)
                        }
                    }
                    to SeqExpr(exprs, span) {
                        return normal.names(exprs)(fn ns {
                            k(anf.Atom(ns.last(), span))
                        })
                    }
                })
            }

        to alpha(expr) :Complex:
            return normal(expr)(id)
