exports (expandExpr, main)

def ab :DeepFrozen := astBuilder
def litExpr :DeepFrozen := ab.LiteralExpr
def nounExpr :DeepFrozen := ab.NounExpr

def nameFromPatt(patt :DeepFrozen) :Str as DeepFrozen:
    return switch (patt.getNodeName()) {
        match =="FinalPattern" { patt.getNoun().getName() }
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
            match =="ListExpr" {
                def items := [for item in (expr.getItems()) moe(item)]
                fn expand {
                    ab.MethodCallExpr(m`_makeList`, "run",
                                      [for item in (items) item(expand)], [],
                                      span)
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
            match =="SeqExpr" {
                def exprs := [for ex in (expr.getExprs()) moe(ex)]
                fn expand { ab.SeqExpr([for ex in (exprs) ex(expand)], span) }
            }
            match =="LiteralExpr" { fn _ { expr } }
            match =="MethodCallExpr" { moe.call(expr, expr.getVerb()) }
            match =="NounExpr" { fn _ { expr } }
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

# A marker for dynamic values.
object dynamic as DeepFrozen {}

def runMoe(expr, fqn :Str, var scope :Map, frameState :List, => parent := null) as DeepFrozen:
    while (true):
        object expand:
            to ensureDynamic(name :Str):
                if (scope.contains(name) && scope[name] != dynamic):
                    scope with= (name, dynamic)
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
        echo("x", 1, => _makeMap)
    }`
    traceln("hm", input, eval(m`$input()`, safeScope))
    def output := expandExpr(input, "derp.mt")
    traceln("yay", output)
    return 0
