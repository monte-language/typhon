exports (makeCompiler, ev, main)

# Using closures for code generation:
# http://www.iro.umontreal.ca/~feeley/papers/FeeleyLapalmeCL87.pdf

def nullLiteral :DeepFrozen := astBuilder.LiteralExpr(null, null)
def isNull(expr) as DeepFrozen:
    return expr == null || expr =~ m`null` || expr =~ m`${nullLiteral}`

def assign(env, index, binding) :Void as DeepFrozen:
    while (env.size() <= index):
        env.push(null)
    env[index] := binding

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
                        fn _, _, _ { null }
                    } else {
                        def guard := compile(guardExpr)
                        fn env, specimen, ex { guard(env).coerce(specimen, ex) }
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
                            def binding :(guard(env)) exit ex := specimen
                            # env[index] := &&binding
                            assign(env, index, &&binding)
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
                            var binding :(guard(env)) := specimen
                            assign(env, index, &&binding)
                        }
                    }
                }
                match =="ListPattern" {
                    def patts := [for p in (patt.getPatterns()) compile.matchBind(p)]
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
                    def p := compile.matchBind(patt.getPattern())
                    def trans := compile(patt.getExpr())
                    fn env, specimen, ex { p(env, trans(env)(specimen, ex), ex) }
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
                fn env, map, ex { value(env, map[key(env)], ex) }
            } else {
                def default := compile(np.getDefault())
                fn env, map, ex {
                    value(env, map.fetch(key(env), fn { default(env) }), ex)
                }
            }

        to run(expr):
            if (expr == null) { return fn _ { null } }
            return switch (expr.getNodeName()) {
                match =="LiteralExpr" { fn _ { expr.getValue() } }
                match =="BindingExpr" {
                    def index := indexOf(expr.getName())
                    fn env { env[index] }
                }
                match =="NounExpr" {
                    def index := indexOf(expr.getName())
                    fn env { env[index].get().get() }
                }
                match =="SeqExpr" {
                    def exprs := compile.all(expr.getExprs())
                    fn env {
                        var rv := null
                        for ex in (exprs) { rv := ex(env) }
                        rv
                    }
                }
                match =="HideExpr" {
                    def body := makeCompiler(frame.diverge())(expr.getBody())
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
                    def patt := compile.matchBind(expr.getPattern())
                    def rhs := compile(expr.getExpr())
                    fn env {
                        def rv := rhs(env)
                        patt(env, rv, ex(env))
                        rv
                    }
                }
                match =="AssignExpr" {
                    def index := indexOf(expr.getLvalue().getName())
                    def rhs := compile(expr.getRvalue())
                    fn env { env[index].get().put(rhs(env)) }
                }
                match =="EscapeExpr" {
                    def ejCompiler := makeCompiler(frame.diverge())
                    def ejPatt := ejCompiler.matchBind(expr.getEjectorPattern())
                    def ejBody := ejCompiler(expr.getBody())
                    if (expr.getCatchBody() == null) {
                        fn var env {
                            escape ej {
                                def innerEnv := env.diverge()
                                ejPatt(innerEnv, ej, null)
                                ejBody(innerEnv)
                            }
                        }
                    } else {
                        def catchCompiler := makeCompiler(frame.diverge())
                        def catchPatt := catchCompiler.matchBind(expr.getCatchPattern())
                        def catchBody := catchCompiler(expr.getCatchBody())
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
                    def body := makeCompiler(frame.diverge())(expr.getBody())
                    def catchCompiler := makeCompiler(frame.diverge())
                    def patt := catchCompiler.matchBind(expr.getPattern())
                    def catcher := catchCompiler(expr.getCatcher())
                    fn env {
                        try { body(env.diverge()) } catch problem {
                            def innerEnv := env.diverge()
                            patt(innerEnv, problem, null)
                            catcher(innerEnv)
                        }
                    }
                }
                match =="FinallyExpr" {
                    def body := makeCompiler(frame.diverge())(expr.getBody())
                    def unwinder := makeCompiler(frame.diverge())(expr.getUnwinder())
                    fn env {
                        try { body(env.diverge()) } finally { unwinder(env.diverge()) }
                    }
                }
                match =="MethodCallExpr" {
                    def receiver := compile(expr.getReceiver())
                    def args := compile.all(expr.getArgs())
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
                                    def innerEnv := closure.diverge()
                                    for i => patt in (patts) {
                                        patt(innerEnv, args[i], null)
                                    }
                                    for np in (nps) {
                                        np(innerEnv, namedArgs, null)
                                    }
                                    body(innerEnv)
                                } catch _ {
                                    escape ret {
                                        for [patt, body] in (matchers) {
                                            def innerEnv := closure.diverge()
                                            patt(innerEnv, message,
                                                 __continue)
                                            ret(body(innerEnv))
                                        }
                                        miranda(message, ret)
                                        throw(`Object $namePatt didn't respond to [$verb, $args, $namedArgs]`)
                                    }
                                }
                            }
                        }
                        namePatt(env, interpObject, null)
                        bind closure := [for index in (indices) env[index]]
                        interpObject
                    }
                }
            }

def ev(expr, scope) as DeepFrozen:
    def names := [for `&&@k` => _ in (scope) k].diverge()
    def compile := makeCompiler(names)
    return compile(expr)(scope.getValues().diverge())

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
