import "lib/mim/syntax/anf" =~ ["ASTBuilder" => anf]
exports (anf, makeNormal)

# http://matt.might.net/articles/a-normalization/

def id(x) as DeepFrozen:
    return x

def nounToName(noun) :Str as DeepFrozen:
    return noun(def extractNoun.NounExpr(name, _) { return name })

def nameForPatt(patt) :NullOk[Str] as DeepFrozen:
    return patt(object pattNamer {
        to IgnorePattern(_, _) { return null }
        to FinalPattern(noun, _, _) {
            # XXX fucky input types
            return if (noun =~ s :Str) { s } else { nounToName(noun) }
        }
        to NounExpr(name, _) { return name }
    })

def Atom :DeepFrozen := anf.atom()
def Complex :DeepFrozen := anf.complex()

def makeNormal() as DeepFrozen:
    var counter :Int := 0
    def gensym() :Str:
        counter += 1
        return `_temp_anf_sym$counter`
    def letsym(complex :Complex, k, span) :Complex:
        # k() wants a noun as a Str.
        def sym :Str := gensym()
        return anf.LetExpr(anf.FinalPattern(sym, null, span), complex, k(sym), span)
    def escapesym(k, span) :Complex:
        # k() wants a noun as a Str.
        def sym :Str := gensym()
        return anf.EscapeExpr(anf.FinalPattern(sym, null, span), k(sym), span)

    # We are doing a sort of context-passing. Each k() is a hole for placing a
    # value into the caller's context.

    return object normal:
        to name(m, k) :Complex:
            # k() wants an atom.
            return normal(m, fn n {
                n.walk(object namer {
                    match [constructor, args, _] {
                        switch (constructor) {
                            match =="Atom" { k(args[0]) }
                            match =="LiteralExpr" { k(n) }
                            match =="NounExpr" { k(n) }
                            match =="BindingExpr" { k(n) }
                            match _ {
                                letsym(n, fn t { k(anf.NounExpr(t, null)) },
                                null)
                            }
                        }
                    }
                })
            })

        to names(ms :List, k) :Complex:
            # k() wants a list of atoms.
            return switch (ms) {
                match [] { k([]) }
                match [m] + tail {
                    normal.name(m, fn n {
                        normal.names(tail, fn ns { k([n] + ns) })
                    })
                }
            }

        to matchBind(patt, specimen :Atom, ej :Atom, k) :Complex:
            # k() wants nothing. It should be run after `patt` is bound.
            return patt.walk(object normalizer {
                to IgnorePattern(guard, span) {
                    return if (guard == null) { k() } else {
                        normal.name(guard, fn g {
                            anf.LetExpr(anf.IgnorePattern(span),
                                        anf.MethodCallExpr(g, "coerce",
                                                           [specimen, ej], [],
                                                           span),
                                        k())
                        })
                    }
                }
                to BindingPattern(noun, span) {
                    def name := nounToName(noun)
                    return anf.LetExpr(anf.BindingPattern(name, span),
                                       anf.Atom(specimen, span),
                                       k(), span)
                }
                to FinalPattern(noun, guard, span) {
                    def name := nounToName(noun)
                    return if (guard == null) {
                        anf.LetExpr(anf.FinalPattern(name, null, span),
                                    anf.Atom(specimen, span),
                                    k(), span)
                    } else {
                        normal(guard, fn g {
                            letsym(g, fn ng {
                                anf.LetExpr(anf.FinalPattern(name, ng, span),
                                            anf.Atom(specimen, span),
                                            k(), span)
                            }, span)
                        })
                    }
                }
                to VarPattern(noun, guard, span) {
                    def name := nounToName(noun)
                    return if (guard == null) {
                        anf.LetExpr(anf.VarPattern(name, null, span),
                                    anf.Atom(specimen, span),
                                    k(), span)
                    } else {
                        normal(guard, fn g {
                            letsym(g, fn ng {
                                anf.LetExpr(anf.VarPattern(name, ng, span),
                                            anf.Atom(specimen, span),
                                            k(), span)
                            }, span)
                        })
                    }
                }
                to ViaPattern(trans, subpatt, span) {
                    return normal.name(trans, fn t {
                        letsym(anf.MethodCallExpr(trans, "run",
                                                  [specimen, ej], [], span),
                               fn s {
                            normal.matchBind(subpatt, anf.NounExpr(s, span), ej, k)
                        }, span)
                    })
                }
            })

        to run(expr, k) :Complex:
            # k() wants a complex expression.
            return expr.walk(object normalizer {
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
                    return normal.name(asExpr, fn a {
                        normal.names(auditors, fn auds {
                            k(anf.Atom(anf.ObjectExpr(docstring, name, a, auds, script,
                                                      span), span))
                        })
                    })
                }
                to MethodCallExpr(receiver, verb :Str, args, namedArgs, span) {
                    # XXX namedArgs
                    return normal.name(receiver, fn r {
                        normal.names(args, fn ars {
                            normal.names(namedArgs, fn nas {
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
                        escapesym(fn ej {
                            normal.matchBind(ejPatt, anf.NounExpr(ej, span),
                                             null, fn { normal.alpha(body) })
                        }, span)
                    } else {
                        # Tricky case: Turn the catcher into a second ejector
                        # on the outside.
                        escapesym(fn rv {
                            def inner := escapesym(fn ej {
                                normal.matchBind(ejPatt, anf.NounExpr(ej, span),
                                                 null, fn {
                                    normal.name(normal.alpha(body), fn b {
                                        anf.JumpExpr(anf.NounExpr(rv, span),
                                                     b, span)
                                    })
                                })
                            }, span)
                            letsym(inner, fn i {
                                normal.matchBind(catchPatt,
                                                 anf.NounExpr(i, span), null,
                                                 fn {
                                     normal.alpha(catchBody)
                                })
                            }, span)
                        }, span)
                    })
                }
                # These expressions are compiled away entirely.
                to HideExpr(expr, _span) { return k(expr.walk(normalizer)) }
                to DefExpr(patt, ex, expr, span) {
                    def finishDef(x) {
                        return normal.name(expr, fn e {
                            normal.matchBind(patt, e, x, fn {
                                k(anf.Atom(e, span))
                            })
                        })
                    }
                    return if (ex == null) {
                        # XXX is this a good idea?
                        finishDef(anf.NounExpr("null", span))
                    } else {
                        normal.name(ex, finishDef)
                    }
                }
                to AssignExpr(lvalue, rvalue, span) {
                    # XXX should we do this in the expander instead?
                    def name := nounToName(lvalue)
                    return normal.name(rvalue, fn rv {
                        letsym(anf.Atom(anf.BindingExpr(name, span), span),
                               fn binding {
                            letsym(anf.MethodCallExpr(anf.NounExpr(binding,
                                                                   span),
                                                      "get", [], [], span),
                                   fn slot {
                                letsym(anf.MethodCallExpr(anf.NounExpr(slot,
                                                                       span),
                                                          "put", [rv], [],
                                                          span),
                                       fn _ { k(rv) }, span)
                            }, span)
                        }, span)
                    })
                }
                to SeqExpr(exprs, span) {
                    return normal.names(exprs, fn ns {
                        k(anf.Atom(ns.last(), span))
                    })
                }
            })

        to alpha(expr) :Complex:
            return normal(expr, id)
