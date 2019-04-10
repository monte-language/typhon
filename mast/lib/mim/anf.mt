import "lib/asdl" =~ [=> asdlParser]
exports (anf, makeNormal)

# http://matt.might.net/articles/a-normalization/

def anf :DeepFrozen := asdlParser(mpatt`anf`, `
    atom = LiteralExpr(df value)
         | NounExpr(str name)
         | SlotExpr(str name)
         | BindingExpr(str name)
         | ObjectExpr(str? docstring, str name, atom? asExpr,
                      atom* auditors, script script)
         attributes (df span)
    complex = MethodCallExpr(atom receiver, str verb, atom* args,
                             namedArg* namedArgs)
            | AssignExpr(atom lvalue, atom rvalue)
            | FinallyExpr(complex body, complex unwinder)
            | EscapeExpr(pattern ejectorPattern, complex body,
                         pattern? catchPattern, complex? catchBody)
            | IfExpr(atom test, complex then, complex else)
            | LetExpr(pattern pattern, complex expr, complex body)
            | Atom(atom atom)
            attributes (df span)
    pattern = IgnorePattern
            | FinalPattern(str noun)
            | BindingPattern(str noun)
            | ListPattern(pattern* patterns)
            attributes (df span)
    namedArg = NamedArg(atom key, atom value, df span)
    namedParam = NamedParam(atom key, pattern value, atom? default, df span)
    method = Method(str? docstring, str verb, pattern* params,
                    namedParam* namedParams, atom? resultGuard, complex body,
                    df span)
    matcher = (pattern pattern, complex body)
    script = Script(method* methods, matcher* matchers, df span)
`, null)

def id(x) as DeepFrozen:
    return x

def nounToName(noun) :Str as DeepFrozen:
    return noun(def extractNoun.NounExpr(name, _) { return name })

def nameForPatt(patt) :Str as DeepFrozen:
    return patt(object pattNamer {
        to FinalPattern(noun, _, _) { return nounToName(noun) }
        to NounExpr(name, _) { return name }
    })

def makeNormal() as DeepFrozen:
    var counter :Int := 0
    def gensym():
        counter += 1
        return `_temp_anf_sym$counter`

    # We are doing a sort of context-passing. Each k() is a hole for placing a
    # value into the caller's context.

    return object normal:
        to name(m, k):
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
                                def t := gensym()
                                anf.LetExpr(anf.FinalPattern(t, null), n,
                                            k(anf.NounExpr(t, null)), null)
                            }
                        }
                    }
                })
            })

        to names(ms, k):
            # k() wants a list of atoms.
            return switch (ms) {
                match [] { k([]) }
                match [m] + tail {
                    normal.name(m, fn n {
                        normal.names(tail, fn ns { k([n] + ns) })
                    })
                }
            }

        to matchBind(patt, specimen, ej, k):
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
                to FinalPattern(noun, guard, span) {
                    def name := nounToName(noun)
                    return if (guard == null) {
                        anf.LetExpr(anf.FinalPattern(name, span),
                                    anf.Atom(specimen, span),
                                    k(), span)
                    } else {
                        normal.name(guard, fn g {
                            def slot := gensym()
                            anf.LetExpr(anf.FinalPattern(slot, span),
                                        anf.MethodCallExpr(anf.NounExpr("_makeFinalSlot",
                                                                        span),
                                                           "run",
                                                           [g, specimen, ej],
                                                           [], span),
                                        anf.LetExpr(anf.BindingPattern(name,
                                                                       span),
                                                    anf.MethodCallExpr(anf.NounExpr("_slotToBinding",
                                                                                    span),
                                                                       "run",
                                                                       [anf.NounExpr(slot,
                                                                                     span),
                                                                        ej],
                                                                       [],
                                                                       span),
                                                    k(), span),
                                        span)
                        })
                    }
                }
            })

        to run(expr, k):
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
                to ObjectExpr(docstring, namePatt, asExpr, auditors, script) {
                    # XXX script
                    def name :Str := nameForPatt(namePatt)
                    return normal.name(asExpr, fn a {
                        normal.names(auditors, fn auds {
                            k(anf.ObjectExpr(docstring, name, a, auds, script))
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
                # These expressions are compiled away entirely.
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
                to SeqExpr(exprs, span) {
                    return normal.names(exprs, fn ns {
                        k(anf.Atom(ns.last(), span))
                    })
                }
            })

        to alpha(expr):
            return normal(expr, id)
