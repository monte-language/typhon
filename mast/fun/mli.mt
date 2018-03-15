exports (makeCompiler, ev, main)

# Using closures for code generation:
# http://www.iro.umontreal.ca/~feeley/papers/FeeleyLapalmeCL87.pdf

def nullLiteral :DeepFrozen := astBuilder.LiteralExpr(null, null)
def isNull(expr) as DeepFrozen:
    return expr == null || expr =~ m`null` || expr =~ m`${nullLiteral}`

def assign(var env :List, index, binding) as DeepFrozen:
    if (env.size() <= index):
        env += [null] * (index - env.size() + 1)
    return env.with(index, binding)

def map(exprs :List, var env) as DeepFrozen:
    def rv := [].diverge()
    for expr in (exprs):
        def [x, e] := expr(env)
        rv.push(x)
        env := e
    return [rv.snapshot(), env]

def mapPairs(exprs :List, var env) as DeepFrozen:
    def rv := [].asMap().diverge()
    for [key, val] in (exprs):
        def [k, e] := key(env)
        def [v, e2] := val(e)
        rv[k] := v
        env := e2
    return [rv.snapshot(), env]

# Our CC:
# Expressions take an env and return a value and updated env.
# Patterns take an env, a specimen, and an ejector, and return an updated env.

def makeCompiler(frame) as DeepFrozen:
    def indexOf(name):
        def i := frame.indexOf(name)
        return if (i >= 0) { i } else {
            def rv := frame.size()
            frame.push(name)
            rv
        }

    return object compile:
        to all(exprs):
            return [for e in (exprs) compile(e)]

        to matchBind(patt):
            return switch (patt.getNodeName()) {
                match =="IgnorePattern" {
                    def guardExpr := patt.getGuard()
                    if (isNull(guardExpr)) {
                        fn env, _, _ { env }
                    } else {
                        def guard := compile(guardExpr)
                        fn env, specimen, ex {
                            def [g, e] := guard(env)
                            g.coerce(specimen, ex)
                            e
                        }
                    }
                }
                match =="BindingPattern" {
                    def index := indexOf(patt.getNoun().getName())
                    # fn env, specimen, _ { env[index] := specimen }
                    fn env, specimen, _ { assign(env, index, specimen) }
                }
                match =="FinalPattern" {
                    def index := indexOf(patt.getNoun().getName())
                    def guardExpr := patt.getGuard()
                    if (isNull(guardExpr)) {
                        # fn env, specimen, _ { env[index] := &&specimen }
                        fn env, specimen, _ { assign(env, index, &&specimen) }
                    } else {
                        def guard := compile(guardExpr)
                        fn env, specimen, ex {
                            def [g, e] := guard(env)
                            def binding :g exit ex := specimen
                            # env[index] := &&binding
                            assign(e, index, &&binding)
                        }
                    }
                }
                match =="VarPattern" {
                    def index := indexOf(patt.getNoun().getName())
                    def guardExpr := patt.getGuard()
                    if (isNull(guardExpr)) {
                        # fn env, var specimen, _ { env[index] := &&specimen }
                        fn env, var specimen, _ { assign(env, index, &&specimen) }
                    } else {
                        def guard := compile(guardExpr)
                        fn env, specimen, _ {
                            def [g, e] := guard(env)
                            var binding :g := specimen
                            assign(e, index, &&binding)
                        }
                    }
                }
                match =="ListPattern" {
                    def patts := [for p in (patt.getPatterns()) compile.matchBind(p)]
                    def size :Int := patts.size()
                    fn var env, specimen, ex {
                        def l :List exit ex := specimen
                        if (l.size() == size) {
                            for i => p in (patts) { env := p(env, l[i], ex) }
                            env
                        } else {
                            throw.eject(ex, `List specimen $l doesn't have size $size`)
                        }
                    }
                }
                match =="ViaPattern" {
                    def p := compile.matchBind(patt.getPattern())
                    def trans := compile(patt.getExpr())
                    fn env, specimen, ex {
                        def [v, e] := trans(env)
                        p(e, v(specimen, ex), ex)
                    }
                }
            }

        to matchBindAll(patts):
            return [for patt in (patts) compile.matchBind(patt)]

        to matchBindNamed(np):
            def key := if (np.getNodeName() == "NamedParamImport") {
                np.getValue().getNoun().getName()
            } else { compile(np.getKey()) }
            def value := compile.matchBind(np.getValue())
            return if (np.getDefault() == null) {
                fn env, map, ex {
                    def [k, e] := key(env)
                    value(e, map[k], ex)
                }
            } else {
                def default := compile(np.getDefault())
                fn env, map, ex {
                    def [k, e] := key(env)
                    def [v, e2] := escape ej {
                        [map.fetch(k, ej), e]
                    } catch _ { default(e) }
                    value(e2, v, ex)
                }
            }

        to run(expr):
            if (expr == null) { return fn _ { null } }
            return switch (expr.getNodeName()) {
                match =="LiteralExpr" { fn env { [expr.getValue(), env] } }
                match =="BindingExpr" {
                    def index := indexOf(expr.getName())
                    fn env { [env[index], env] }
                }
                match =="NounExpr" {
                    def index := indexOf(expr.getName())
                    fn env { [env[index].get().get(), env] }
                }
                match =="SeqExpr" {
                    def exprs := compile.all(expr.getExprs())
                    fn var env {
                        var rv := null
                        for ex in (exprs) {
                            def [v, e] := ex(env)
                            rv := v
                            env := e
                        }
                        [rv, env]
                    }
                }
                match =="HideExpr" {
                    def body := makeCompiler(frame.diverge())(expr.getBody())
                    fn env { [body(env)[0], env] }
                }
                match =="IfExpr" {
                    def test := compile(expr.getTest())
                    def cons := compile(expr.getThen())
                    def alt := compile(expr.getElse())
                    fn env {
                        def [t :Bool, e] := test(env)
                        [t.pick(cons, alt)(e)[0], env]
                    }
                }
                match =="DefExpr" {
                    def ex := compile(expr.getExit())
                    def patt := compile.matchBind(expr.getPattern())
                    def rhs := compile(expr.getExpr())
                    fn env {
                        def [rv, e] := rhs(env)
                        def [exiter, e2] := ex(e)
                        [rv, patt(e2, rv, exiter)]
                    }
                }
                match =="AssignExpr" {
                    def index := indexOf(expr.getLvalue().getName())
                    def rhs := compile(expr.getRvalue())
                    fn env {
                        def [r, e] := rhs(env)
                        e[index].get().put(r)
                        [r, e]
                    }
                }
                match =="EscapeExpr" {
                    def ejCompiler := makeCompiler(frame.diverge())
                    def ejPatt := ejCompiler.matchBind(expr.getEjectorPattern())
                    def ejBody := ejCompiler(expr.getBody())
                    if (expr.getCatchBody() == null) {
                        fn env {
                            escape ej {
                                def innerEnv := ejPatt(env, ej, null)
                                [ejBody(innerEnv)[0], env]
                            }
                        }
                    } else {
                        def catchCompiler := makeCompiler(frame.diverge())
                        def catchPatt := catchCompiler.matchBind(expr.getCatchPattern())
                        def catchBody := catchCompiler(expr.getCatchBody())
                        fn env {
                            escape ej {
                                def innerEnv := ejPatt(innerEnv, ej, null)
                                [ejBody(innerEnv)[0], env]
                            } catch val {
                                def innerEnv := catchPatt(innerEnv, val, null)
                                [catchBody(innerEnv)[0], env]
                            }
                        }
                    }
                }
                match =="CatchExpr" {
                    def body := makeCompiler(frame.diverge())(expr.getBody())
                    def catchCompiler := makeCompiler(frame.diverge())
                    def patt := catchCompiler.matchBind(expr.getPattern())
                    def catcher := catchCompiler(expr.getCatcher())
                    fn env {
                        try {
                            def [rv, _] := body(env)
                            [rv, env]
                        } catch problem {
                            def innerEnv := patt(env, problem, null)
                            [catcher(innerEnv), env]
                        }
                    }
                }
                match =="FinallyExpr" {
                    def body := makeCompiler(frame.diverge())(expr.getBody())
                    def unwinder := makeCompiler(frame.diverge())(expr.getUnwinder())
                    fn env {
                        try {
                            def [rv, _] := body(env)
                            [rv, env]
                        } finally { unwinder(env) }
                    }
                }
                match =="MethodCallExpr" {
                    def receiver := compile(expr.getReceiver())
                    def args := compile.all(expr.getArgs())
                    def namedArgs := [for namedArg in (expr.getNamedArgs())
                                      [compile(namedArg.getKey()),
                                       compile(namedArg.getValue())]]
                    fn env {
                        def [r, e] := receiver(env)
                        def [a, e2] := map(args, e)
                        def [ns, e3] := mapPairs(namedArgs, e2)
                        def rv := M.call(r, expr.getVerb(), a, ns)
                        [rv, e3]
                    }
                }
                match =="ObjectExpr" {
                    # XXX auditions
                    def script := expr.getScript()
                    def ss := astBuilder.makeScopeWalker().getStaticScope(script)
                    def namesUsed := ss.namesUsed().asList()
                    def atoms := [for meth in (script.getMethods())
                        [meth.getVerb(), meth.getParams().size()] => {
                            def innerCompiler := makeCompiler(namesUsed.diverge())
                            def params := innerCompiler.matchBindAll(meth.getParams())
                            def nps := [for np in (meth.getNamedParams())
                                        innerCompiler.matchBindNamed(np)]
                            [params, nps, innerCompiler(meth.getBody())]
                        }]
                    def matchers := [for m in (script.getMatchers()) {
                            def innerCompiler := makeCompiler(namesUsed.diverge())
                            def patt := innerCompiler.matchBind(m.getPattern())
                            def body := innerCompiler(m.getBody())
                            [patt, body]
                        }]
                    def indices := [for name in (namesUsed) indexOf(name)]
                    def displayName := `<${expr.getName()}>`
                    def namePatt := compile.matchBind(expr.getName())
                    def miranda(message, ej) {
                        return switch (message) {
                            match [=="_printOn", [out], _] {
                                out.print(displayName)
                                ej(null)
                            }
                            match _ { null }
                        }
                    }
                    fn env {
                        def closure
                        object interpObject {
                            match message {
                                def [verb, args, namedArgs] := message
                                escape noMethod {
                                    def [patts, nps, body] := atoms.fetch([verb, args.size()], noMethod)
                                    var innerEnv := closure
                                    for i => patt in (patts) {
                                        innerEnv := patt(innerEnv, args[i], null)
                                    }
                                    for np in (nps) {
                                        innerEnv := np(innerEnv, namedArgs, null)
                                    }
                                    body(innerEnv)[0]
                                } catch _ {
                                    escape ret {
                                        for [patt, body] in (matchers) {
                                            def innerEnv := patt(closure,
                                                                 message,
                                                                 __continue)
                                            ret(body(innerEnv)[0])
                                        }
                                        miranda(message, ret)
                                        throw(`Object $namePatt didn't respond to [$verb, $args, $namedArgs]`)
                                    }
                                }
                            }
                        }
                        def e := namePatt(env, interpObject, null)
                        bind closure := [for index in (indices) e[index]]
                        [interpObject, e]
                    }
                }
            }

def ev(expr, scope) as DeepFrozen:
    def names := [for `&&@k` => _ in (scope) k].diverge()
    def compile := makeCompiler(names)
    return compile(expr)(scope.getValues())[0]

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
            def module := ev(ast, safeScope)(null)
            traceln("module", module)
            def metamod := module["ev"](ast, safeScope)(null)
            traceln("metamod", metamod)
            0
        catch problem:
            when (traceln(`Problem decoding MAST: $problem`)) -> { 1 }
