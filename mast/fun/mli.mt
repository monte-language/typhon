exports (main)

def compile(expr) as DeepFrozen:
    def compileMap(exprs):
        return [for e in (exprs) compile(e)]

    def matchBind(patt):
        return switch (patt.getNodeName()) {
            match =="BindingPattern" {
                def name := "&&" + patt.getNoun().getName()
                fn env, specimen, _ { env[name] := specimen }
            }
            match =="FinalPattern" {
                def name := "&&" + patt.getNoun().getName()
                if (patt.getGuard() == null) {
                    fn env, specimen, _ { env[name] := &&specimen }
                } else {
                    def guard := compile(patt.getGuard())
                    fn env, specimen, ex {
                        def binding :(guard(env)) exit ex := specimen
                        env[name] := &&binding
                    }
                }
            }
            match =="ListPattern" {
                def patts := [for p in (patt.getPatterns()) matchBind(p)]
                def size :Int := patts.size()
                fn env, specimen, ex {
                    def l :List exit ex := specimen
                    if (l.size() == size) {
                        for i => p in (patts) { p(env, l[i], ex) }
                    } else {
                        throw.eject(ex, `List specimen $l doesn't have size $size`)
                    }
                }
            }
            match =="ViaPattern" {
                def p := matchBind(patt.getPattern())
                def trans := compile(patt.getExpr())
                fn env, specimen, ex { p(env, trans(env)(specimen, ex), ex) }
            }
        }

    def matchBindMap(patts):
        return [for patt in (patts) matchBind(patt)]

    def matchBindNamed(np):
        return switch (np.getNodeName()) {
        }

    if (expr == null) { return fn _ { null } }
    return switch (expr.getNodeName()) {
        match =="LiteralExpr" { fn _ { expr.getValue() } }
        match =="BindingExpr" {
            def name :Str := "&&" + expr.getName()
            fn env { env[name] }
        }
        match =="NounExpr" {
            def name :Str := "&&" + expr.getName()
            fn env { env[name].get().get() }
        }
        match =="SeqExpr" {
            def exprs := compileMap(expr.getExprs())
            fn env {
                var rv := null
                for ex in (exprs) { rv := ex(env) }
                rv
            }
        }
        match =="IfExpr" {
            def test := compile(expr.getTest())
            def cons := compile(expr.getThen())
            def alt := compile(expr.getElse())
            fn env { (test(env) :Bool).pick(cons, alt)(env) }
        }
        match =="DefExpr" {
            def ex := compile(expr.getExit())
            def patt := matchBind(expr.getPattern())
            def rhs := compile(expr.getExpr())
            fn env {
                def rv := rhs(env)
                patt(env, rv, ex(env))
                rv
            }
        }
        match =="EscapeExpr" {
            def ejPatt := matchBind(expr.getEjectorPattern())
            def ejBody := compile(expr.getBody())
            if (expr.getCatchBody() == null) {
                fn var env {
                    escape ej {
                        def innerEnv := env.diverge()
                        ejPatt(innerEnv, ej, null)
                        ejBody(innerEnv)
                    }
                }
            } else {
                def catchPatt := matchBind(expr.getCatchPattern())
                def catchBody := compile(expr.getCatchBody())
                fn var env {
                    escape ej {
                        def innerEnv := env.diverge()
                        ejPatt(innerEnv, ej, null)
                        ejBody(innerEnv)
                    } catch val {
                        def innerEnv := env.diverge()
                        catchPatt(innerEnv, val, null)
                        catchBody(innerEnv)
                    }
                }
            }
        }
        match =="MethodCallExpr" {
            def receiver := compile(expr.getReceiver())
            def args := compileMap(expr.getArgs())
            def namedArgs := [for namedArg in (expr.getNamedArgs())
                              [compile(namedArg.getKey()),
                               compile(namedArg.getValue())]]
            fn env {
                M.call(receiver(env), expr.getVerb(),
                       [for arg in (args) arg(env)],
                       [for [k, v] in (namedArgs) k(env) => v(env)])
            }
        }
        match =="ObjectExpr" {
            # XXX matchers and auditions
            def script := expr.getScript()
            def atoms := [for meth in (script.getMethods())
                          [meth.getVerb(), meth.getParams().size()] =>
                          [matchBindMap(meth.getParams()),
                           [for np in (meth.getNamedParams())
                            matchBindNamed(np)],
                           compile(meth.getBody())]]
            def names := [for name in
                          (astBuilder.makeScopeWalker().getStaticScope(expr).namesUsed())
                          "&&" + name]
            def displayName := `<${expr.getName()}>`
            fn env {
                def closure := [for name in (names) name => env[name]]
                object interpObject {
                    to _printOn(out) { out.print(displayName) }

                    match [verb, args, namedArgs] {
                        escape ret {
                            for [v, size] => [patts, nps, body] in (atoms) {
                                if (v == verb && args.size() == size) {
                                    def innerEnv := closure.diverge()
                                    for i => patt in (patts) {
                                        patt(innerEnv, args[i], null)
                                    }
                                    for np in (nps) {
                                        np(innerEnv, namedArgs, null)
                                    }
                                    ret(body(innerEnv))
                                }
                            }
                            throw(`Object doesn't respond to [$verb, $args, $namedArgs]`)
                        }
                    }
                }
            }
        }
    }

def ev(expr, scope) as DeepFrozen:
    return compile(expr)(scope.diverge())

def main(_argv) as DeepFrozen:
    def f := ev(m`fn x { fn { x } }`.expand(), safeScope)
    traceln(f, f(2), f(42)())
    return 0
