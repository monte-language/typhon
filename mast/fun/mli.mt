exports (main)

def nullLiteral :DeepFrozen := astBuilder.LiteralExpr(null, null)
def isNull(expr) as DeepFrozen:
    return expr == null || expr =~ m`null` || expr =~ m`${nullLiteral}`

def compile(expr) as DeepFrozen:
    def compileMap(exprs):
        return [for e in (exprs) compile(e)]

    def matchBind(patt):
        return switch (patt.getNodeName()) {
            match =="IgnorePattern" {
                def guardExpr := patt.getGuard()
                if (isNull(guardExpr)) {
                    fn _, _, _ { null }
                } else {
                    def guard := compile(guardExpr)
                    fn env, specimen, ex { guard(env).coerce(specimen, ex) }
                }
            }
            match =="BindingPattern" {
                def name := "&&" + patt.getNoun().getName()
                fn env, specimen, _ { env[name] := specimen }
            }
            match =="FinalPattern" {
                def name := "&&" + patt.getNoun().getName()
                def guardExpr := patt.getGuard()
                if (isNull(guardExpr)) {
                    fn env, specimen, _ { env[name] := &&specimen }
                } else {
                    def guard := compile(guardExpr)
                    fn env, specimen, ex {
                        def binding :(guard(env)) exit ex := specimen
                        env[name] := &&binding
                    }
                }
            }
            match =="VarPattern" {
                def name := "&&" + patt.getNoun().getName()
                def guardExpr := patt.getGuard()
                if (isNull(guardExpr)) {
                    fn env, var specimen, _ { env[name] := &&specimen }
                } else {
                    def guard := compile(guardExpr)
                    fn env, specimen, _ {
                        var binding :(guard(env)) := specimen
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
        def key := if (np.getNodeName() == "NamedParamImport") {
            np.getValue().getNoun().getName()
        } else { compile(np.getKey()) }
        def value := matchBind(np.getValue())
        return if (np.getDefault() == null) {
            fn env, map, ex { value(env, map[key(env)], ex) }
        } else {
            def default := compile(np.getDefault())
            fn env, map, ex {
                value(env, map.fetch(key(env), fn { default(env) }), ex)
            }
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
        match =="HideExpr" {
            def body := compile(expr.getBody())
            fn env { body(env.diverge()) }
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
        match =="AssignExpr" {
            def name := "&&" + expr.getLvalue().getName()
            def rhs := compile(expr.getRvalue())
            fn env { env[name].get().put(rhs(env)) }
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
                fn env {
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
        match =="CatchExpr" {
            def body := compile(expr.getBody())
            def patt := matchBind(expr.getPattern())
            def catcher := compile(expr.getCatcher())
            fn env {
                try { body(env.diverge()) } catch problem {
                    def innerEnv := env.diverge()
                    patt(innerEnv, problem, null)
                    catcher(innerEnv)
                }
            }
        }
        match =="FinallyExpr" {
            def body := compile(expr.getBody())
            def unwinder := compile(expr.getUnwinder())
            fn env {
                try { body(env.diverge()) } finally { unwinder(env.diverge()) }
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
            def namePatt := matchBind(expr.getName())
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
                namePatt(env, interpObject, null)
                interpObject
            }
        }
    }

def ev(expr, scope) as DeepFrozen:
    return compile(expr)(scope.diverge())

def bfInterp :DeepFrozen := m`def bf(insts :Str) {
    def jumps := {
        def m := [].asMap().diverge()
        def stack := [].diverge()
        for i => c in (insts) {
            if (c == '[') { stack.push(i) } else if (c == ']') {
                def j := stack.pop()
                m[i] := j
                m[j] := i
            }
        }
        m.snapshot()
    }

    return def interpret() {
        var i := 0
        var pointer := 0
        def tape := [0].diverge()
        def output := [].diverge()
        while (i < insts.size()) {
            switch(insts[i]) {
                match =='>' {
                    pointer += 1
                    while (pointer >= tape.size()) { tape.push(0) }
                }
                match =='<' { pointer -= 1 }
                match =='+' { tape[pointer] += 1 }
                match =='-' { tape[pointer] -= 1 }
                match =='.' { output.push(tape[pointer]) }
                match ==',' { tape[pointer] := 0 }
                match =='[' {
                    if (tape[pointer] == 0) { i := jumps[i] }
                }
                match ==']' {
                    if (tape[pointer] != 0) { i := jumps[i] }
                }
            }
            i += 1
        }
        return output.snapshot()
    }
}`

def main(_argv, => makeFileResource) as DeepFrozen:
    def bf := ev(bfInterp.expand(), safeScope)
    traceln(bf("+++.>>.<<[->>+<<].>>.")())
    def bs := makeFileResource("mast/fun/mli.mast")<-getContents()
    return when (bs) ->
        escape ej:
            def ast := readMAST(bs, "filename" => "meta", "FAIL" => ej)
            def module := ev(ast, safeScope)
            traceln("module", module)
            traceln("deps", module.dependencies())
            traceln("instantiated", module(null))
            0
        catch problem:
            when (traceln(`Problem decoding MAST: $problem`)) -> { 1 }
