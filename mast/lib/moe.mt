exports (expandExpr, main)

def ab :DeepFrozen := astBuilder
def litExpr :DeepFrozen := ab.LiteralExpr
def nounExpr :DeepFrozen := ab.NounExpr

def nameFromPatt(patt :DeepFrozen) :Str as DeepFrozen:
    return switch (patt.getNodeName()) {
        match =="FinalPattern" { patt.getNoun().getName() }
    }

# A marker for dynamic values.
object dynamic as DeepFrozen {}

object moe as DeepFrozen:
    to call(expr :DeepFrozen, verb :Str):
        def span := expr.getSpan()
        def receiver := moe(expr.getReceiver())
        def args := [for arg in (expr.getArgs()) moe(arg)]
        def namedArgs := [for na in (expr.getNamedArgs()) {
            def [key, value] := if (na.getNodeName() == "NamedArgExport") {
                def v := na.getValue()
                def k := switch (v.getNodeName()) {
                    match =="BindingExpr" { "&&" + v.getNoun().getName() }
                    match =="SlotExpr" { "&" + v.getNoun().getName() }
                    match =="NounExpr" { v.getName() }
                }
                [fn _ { litExpr(k, span) }, moe(v)]
            } else {
                [moe(na.getKey()), moe(na.getValue())]
            }
            fn expand {
                ab.NamedArg(key(expand), value(expand), span)
            }
        }]
        return fn expand {
            ab.MethodCallExpr(receiver(expand), verb,
                              [for arg in (args) arg(expand)],
                              [for na in (namedArgs) na(expand)], span)
        }

    to script(s :DeepFrozen):
        def meths := [for m in (s.getMethods()) {
            def doc := m.getDocstring()
            def verb := m.getVerb()
            def body := moe(m.getBody())
            fn expand {
                # XXX params
                def b := expand.inNewScope(body)
                ab."Method"(doc, verb, m.getParams(), m.getNamedParams(),
                            m.getResultGuard(), b, m.getSpan())
            }
        }]
        def matchers := [for m in (s.getMatchers()) {
            def patt := m.getPattern()
            def body := moe(m.getBody())
            fn expand {
                # XXX patt
                def b := expand.inNewScope(body)
                ab.Matcher(patt, b, m.getSpan())
            }
        }]
        # XXX extends
        return fn expand {
            ab.Script(null, [for m in (meths) m(expand)],
                      [for m in (matchers) m(expand)], s.getSpan())
        }

    to run(var expr :DeepFrozen):
        # Note that we grab the span *once*. This ensures that, even if we do
        # several rewrites, we'll correctly reattach the span at the end. ~ C.
        def span := expr.getSpan()
        while (true):
            escape instead:
                return switch (expr) {
                    # These expressions are defined in terms of Kernel-Monte.
                    match m`@specimen :(@guard)` {
                        instead(m`$guard.coerce($specimen, throw)`)
                    }
                    # XXX these need to have the static scope check!
                    match m`@lhs && @rhs` {
                        def sw := ab.makeScopeWalker()
                        def conflicts := (sw.getStaticScope(lhs).outNames() |
                                          sw.getStaticScope(rhs).outNames())
                        if (conflicts.isEmpty()) {
                            instead(m`if ($lhs) { $rhs :Bool } else { false }`)
                        } else {
                            throw(`XXX not implemented`)
                        }
                    }
                    match m`@lhs || @rhs` {
                        def sw := ab.makeScopeWalker()
                        def conflicts := (sw.getStaticScope(lhs).outNames() |
                                          sw.getStaticScope(rhs).outNames())
                        if (conflicts.isEmpty()) {
                            instead(m`if ($lhs) { true } else { $rhs :Bool }`)
                        } else {
                            throw(`XXX not implemented`)
                        }
                    }
                    match m`@lhs == @rhs` {
                        instead(m`_equalizer.sameEver($lhs, $rhs)`)
                    }
                    match m`@lhs != @rhs` {
                        instead(m`_equalizer.sameEver($lhs, $rhs).not()`)
                    }
                    match m`@start..@stop` {
                        instead(m`_makeOrderedSpace.op__thru($start, $stop)`)
                    }
                    match m`@start..!@stop` {
                        instead(m`_makeOrderedSpace.op__till($start, $stop)`)
                    }
                    # Modular exponentiation doesn't have explicit parser
                    # support. Instead, whenever the parse tree happens to
                    # have a modpow, we match for it before matching for mod
                    # or pow, and find it that way. ~ C.
                    match m`@base ** @exponent % @modulus` {
                        instead(m`$base.modPow($exponent, $modulus)`)
                    }
                    match m`@base ** @exponent` {
                        instead(m`$base.pow($exponent)`)
                    }
                    match m`@x % @modulus` { instead(m`$x.mod($modulus)`) }
                    match m`@x[@i]` { instead(m`$x.get($i)`) }
                    # XXX needs DefExpr support first!
                    # match m`@x[@i] := @rhs` {
                    #     instead(m`{
                    #         def rv := $rhs
                    #         { $x }.put({ $i }, rv)
                    #         rv
                    #     }`)
                    # }
                    # Meta stuff.
                    match m`meta.context()` {
                        fn expand {
                            def prefix := litExpr(expand.getFQNPrefix(), span)
                            m`object _ as DeepFrozen {
                                method getFQNPrefix() { $prefix }
                            }`.withSpan(span)
                        }
                    }
                    match m`meta.getState()` {
                        fn expand {
                            def names := [for name in (expand.getState()) {
                                ab.MapExprExport(nounExpr("&&" + name, span), span)
                            }]
                            ab.MapExpr(names, span)
                        }
                    }
                    # Kernel-Monte.
                    match m`{ @inner }` {
                        def i := moe(inner)
                        fn expand { ab.HideExpr(expand.inNewScope(i), span) }
                    }
                    match m`if (@test) { @cons } else { @alt }` {
                        def t := moe(test)
                        def c := moe(cons)
                        def a := moe(alt)
                        fn expand {
                            expand.inNewScope(fn expand {
                                switch (t(expand)) {
                                    match m`true` { expand.inNewScope(c) }
                                    match m`false` { expand.inNewScope(a) }
                                    match newTest {
                                        ab.IfExpr(newTest,
                                                  expand.inNewScope(c),
                                                  expand.inNewScope(a), span)
                                    }
                                }
                            })
                        }
                    }
                    match _ {
                        # Go by node name.
                        switch (expr.getNodeName()) {
                            # Full-Monte.
                            match =="FunCallExpr" { moe.call(expr, "run") }
                            match =="FunctionExpr" {
                                def body := moe(expr.getBody())
                                fn expand {
                                    def b := expand.inNewScope(body)
                                    def meth := ab."Method"(null, "run", expr.getParams(),
                                                            expr.getNamedParams(), null, b, span)
                                    def script := ab.Script(null, [meth], [], span)
                                    ab.ObjectExpr(null, mpatt`_`, null, [], script, span)
                                }
                            }
                            match =="ListExpr" {
                                def items := [for item in (expr.getItems()) moe(item)]
                                fn expand {
                                    ab.MethodCallExpr(m`_makeList`, "run",
                                                      [for item in (items) item(expand)], [],
                                                      span)
                                }
                            }
                            # Kernel-Monte.
                            match =="LiteralExpr" { fn _ { expr } }
                            match =="MethodCallExpr" { moe.call(expr, expr.getVerb()) }
                            match =="NounExpr" {
                                def name := expr.getName()
                                fn expand {
                                    def val := expand[name]
                                    if (val == dynamic) { expr } else { val }
                                }
                            }
                            match =="ObjectExpr" {
                                def script := moe.script(expr.getScript())
                                def name := nameFromPatt(expr.getName())
                                def frameNames := ab.makeScopeWalker().getStaticScope(expr).getNamesRead()
                                fn expand {
                                    def s := expand.inNewFrame(name, frameNames, script)
                                    # XXX everything not in script
                                    ab.ObjectExpr(expr.getDocstring(), expr.getName(),
                                                  expr.getAsExpr(), expr.getAuditors(), s,
                                                  expr.getSpan())
                                }
                            }
                            match =="SeqExpr" {
                                def exprs := [for ex in (expr.getExprs()) moe(ex)]
                                fn expand { ab.SeqExpr([for ex in (exprs) ex(expand)], span) }
                            }
                        }
                    }
                }
            catch newExpr:
                expr := newExpr
                # And implicitly continue.

def runMoe(expr, fqn :Str, var scope :Map, frameState :List, => parent := null) as DeepFrozen:
    while (true):
        object expand:
            to ensureDynamic(name :Str):
                if (scope.contains(name) && scope[name] != dynamic):
                    # Change the name to be dynamic within our scope, and
                    # restart the expansion.
                    traceln("making name dynamic", name)
                    scope with= (name, dynamic)
                    traceln("restarting at", fqn)
                    continue
                else if (parent != null):
                    parent.ensureDynamic(name)

            to get(name :Str):
                return scope.fetch(name, fn {
                    if (parent != null) { parent[name] } else { dynamic }
                })

            to getFQNPrefix():
                return fqn + "$"

            to getState():
                return frameState

            to inNewScope(action):
                return runMoe(action, fqn, scope, frameState, "parent" => expand)

            to inNewFrame(name, frameNames, action):
                def frame := [for n in (frameNames) ? (expand[n] == dynamic) n]
                traceln("giving new frame", name, frame)
                return runMoe(action, fqn + "$" + name, scope, frame, "parent" => expand)

        return expr(expand)

def expandExpr(expr, fqn :Str) as DeepFrozen:
    return runMoe(moe(expr), fqn, [].asMap(), [])

def main(_argv) as DeepFrozen:
    def input := m`fn {
        object echo {
            method derp() {
                [true, meta.getState(), (meta.context()).getFQNPrefix()]
            }
            match message { message }
        }
        2 ** 5 % 13
        2 ** (5 % 13)
        echo(0..!42, (42 == 7) || true)
        echo("x", 1, => _makeMap)
    }`
    traceln("hm", input, eval(m`$input()`, safeScope))
    def output := expandExpr(input, "derp.mt")
    traceln("yay", output)
    return 0
