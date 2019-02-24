import "lib/asdl" =~ [=> asdlParser]
exports (anf, makeNormal)

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
            | VarPattern(str noun)
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

def nameForPatt(patt) :Str as DeepFrozen:
    return patt(object pattNamer {
        to FinalPattern(noun, _, _) { return noun }
        to NounExpr(name, _) { return name }
    })

def makeNormal() as DeepFrozen:
    var counter :Int := 0
    def gensym():
        return `_temp_anf_sym$counter`
    return object normal:
        to name(m, k):
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
            return switch (ms) {
                match [] { k([]) }
                match [m] + tail {
                    normal.name(m, fn n {
                        normal.names(tail, fn ns { k([n] + ns) })
                    })
                }
            }

        to run(expr, k):
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
                to IfExpr(test, cons, alt, span) {
                    return normal.name(test, fn t {
                        k(anf.IfExpr(t, normal.alpha(cons), normal.alpha(alt), span))
                    })
                }
            })

        to alpha(expr):
            return normal(expr, id)
