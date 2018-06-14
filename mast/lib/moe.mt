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

def sameEver(l :DeepFrozen, r :DeepFrozen) :NullOk[Bool] as DeepFrozen:
    return if (l.getNodeName() == "LiteralExpr" &&
               r.getNodeName() == "LiteralExpr") {
        l.getValue() == r.getValue()
    }

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

    to run(expr :DeepFrozen):
        def span := expr.getSpan()
        traceln("moe", expr)

        return switch (expr.getNodeName()) {
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
            match =="IfExpr" {
                def test := moe(expr.getTest())
                def cons := moe(expr.getThen())
                def alt := moe(expr.getElse())
                fn expand {
                    expand.inNewScope(fn expand {
                        def t := test(expand)
                        switch (t) {
                            match m`true` { expand.inNewScope(cons) }
                            match m`false` { expand.inNewScope(alt) }
                            match _ {
                                ab.IfExpr(t, expand.inNewScope(cons),
                                          expand.inNewScope(alt), span)
                            }
                        }
                    })
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
            match =="SameExpr" {
                def left := moe(expr.getLeft())
                def right := moe(expr.getRight())
                def direction :Bool := expr.getDirection()
                fn expand {
                    def l := left(expand)
                    def r := right(expand)
                    def se := sameEver(l, r)
                    if (se == true) {
                        direction.pick(m`true`, m`false`)
                    } else if (se == false) {
                        direction.pick(m`false`, m`true`)
                    } else if (direction) {
                        m`_equalizer.sameEver($l, $r)`
                    } else {
                        m`_equalizer.sameEver($l, $r).not()`
                    }
                }
            }
            # Meta stuff.
            match =="MetaContextExpr" {
                fn expand {
                    def prefix := litExpr(expand.getFQNPrefix(), span)
                    m`object _ as DeepFrozen {
                        method getFQNPrefix() { $prefix }
                    }`.withSpan(span)
                }
            }
            match =="MetaStateExpr" {
                fn expand {
                    def names := [for name in (expand.getState()) {
                        ab.MapExprExport(nounExpr("&&" + name, span), span)
                    }]
                    ab.MapExpr(names, span)
                }
            }
            # Kernel-Monte.
            match =="LiteralExpr" { fn _ { expr } }
            match =="SeqExpr" {
                def exprs := [for ex in (expr.getExprs()) moe(ex)]
                fn expand { ab.SeqExpr([for ex in (exprs) ex(expand)], span) }
            }
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
        }

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
        if (echo != null) { 1 } else { 2 }
        if (3 != 2) { 1 } else { 2 }
        echo("x", 1, => _makeMap)
    }`
    traceln("hm", input, eval(m`$input()`, safeScope))
    def output := expandExpr(input, "derp.mt")
    traceln("yay", output)
    return 0
