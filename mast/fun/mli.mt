import "lib/iterators" =~ [=> zip]
exports (withDomain, concreteMonte, ev)

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

# We parameterize the compiler by an abstract interpreter, traditionally
# named δ, which acts as a homomorphism from the concrete domain to the
# abstract domain. The behavior of δ is that it sends literals, including
# object literals, to their corresponding abstract leaves, and also sends
# calls to their abstractions.

object concreteMonte as DeepFrozen:
    "The concrete, typical domain of Monte objects."

    to literal(value):
        return value

    to objectLiteral(displayName, atoms, matchers, miranda, closure):
        return object interpObject {
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
                        throw(`Object $displayName didn't respond to [$verb, $args, $namedArgs]`)
                    }
                }
            }
        }

    to call(receiver, verb, args, namedArgs):
        return M.call(receiver, verb, args, namedArgs)

def listProduct(l :List) as DeepFrozen:
    return if (l =~ [head] + tail) {
        def rv := [].asSet().diverge()
        for h in (head) {
            for t in (listProduct(tail)) { rv.include([h] + t) }
        }
        rv.snapshot()
    } else { [[]].asSet() }

def mapProduct(m :Map) as DeepFrozen:
    def keys := m.getKeys()
    return [for values in (listProduct(m.getValues())) {
        _makeMap.fromPairs(_makeList.fromIterable(zip(keys, values)))
    }].asSet()

def multi(domain :DeepFrozen) as DeepFrozen:
    return object multiMonte as DeepFrozen:
        "A non-deterministic flavor of `domain`."

        to literal(value):
            traceln("literal", value)
            return [value].asSet()

        to objectLiteral(displayName, atoms, matchers, miranda, closure):
            def obj := domain.objectLiteral(displayName, atoms, matchers,
                                            miranda, closure)
            return [obj].asSet()

        to call(receiver, verb, args, namedArgs):
            traceln("call", receiver, verb, args, namedArgs)
            # Take a Cartesian product.
            def rv := [].asSet().diverge()
            for r in (receiver):
                for a in (args):
                    for na in (namedArgs):
                        # We need to take the Cartesian for args and named
                        # args as well.
                        def uas := listProduct(a)
                        def unas := mapProduct(na)
                        for ua in (uas):
                            for una in (unas):
                                traceln("primcall", r, verb, ua, una)
                                rv.include(domain.call(r, verb, ua, una))
            return rv.snapshot()

def literalTypes :DeepFrozen := [
    Int => [
        ["add", 1] => [Int, [Int], [].asMap()],
    ],
]

object gradualTyper as DeepFrozen:
    to literal(value):
        return literalTypes[value._getAllegedInterface()]

    to objectLiteral(_displayName, atoms, _matchers, _miranda, _closure):
        # XXX not specific enough
        return [for [verb, len] => _ in (atoms)
                [verb, len] => [Any, [Any] * len, [].asMap()]]

    to call(receiver, verb, args, namedArgs):
        return escape ej {
            def sig := receiver.fetch([verb, args.size()], ej)
        } catch _ { null }

# We ask that δ be DF. It's just too painful to reason about otherwise.

def withDomain(delta :DeepFrozen) as DeepFrozen:
    return def makeCompiler(frame) as DeepFrozen:
        def indexOf(name):
            def i := frame.indexOf(name)
            return if (i >= 0) { i } else {
                def rv := frame.size()
                frame.push(name)
                rv
            }

        def fresh():
            return makeCompiler(frame.diverge())

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
                    match =="LiteralExpr" {
                        fn env { [delta.literal(expr.getValue()), env] }
                    }
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
                        def body := fresh()(expr.getBody())
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
                        def ejCompiler := fresh()
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
                            def catchCompiler := fresh()
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
                        def body := fresh()(expr.getBody())
                        def catchCompiler := fresh()
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
                        def body := fresh()(expr.getBody())
                        def unwinder := fresh()(expr.getUnwinder())
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
                            def rv := delta.call(r, expr.getVerb(),
                                                 delta.literal(a),
                                                 delta.literal(ns))
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
                            def interpObject := delta.objectLiteral(displayName,
                                                                    atoms,
                                                                    matchers,
                                                                    miranda,
                                                                    closure)
                            def e := namePatt(env, interpObject, null)
                            bind closure := [for index in (indices) e[index]]
                            [interpObject, e]
                        }
                    }
                }


def ev(expr, scope) as DeepFrozen:
    def names := [for `&&@k` => _ in (scope) k].diverge()
    def makeCompiler := withDomain(concreteMonte)
    def compile := makeCompiler(names)
    return compile(expr)(scope.getValues())[0]
