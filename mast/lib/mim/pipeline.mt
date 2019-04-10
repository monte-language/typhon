import "lib/mim/full" =~ [=> expand]
import "lib/mim/anf" =~ [=> makeNormal]
exports (go, evaluate)

def go(expr :DeepFrozen) as DeepFrozen:
    return makeNormal().alpha(expand(expr))

def b :DeepFrozen := "&&".add

def evaluate(expr, frame) as DeepFrozen:
    "
    Interpret `expr` within `frame`, returning a value or raising an
    exception.
    "

    def getBinding(name, span):
        return frame.fetch(b(name), fn {
            throw(`Name ::"$name" not in frame at $span`)
        })

    object atom {
        to LiteralExpr(value, _span) { return value }
        to NounExpr(name, span) { return getBinding(name, span).get().get() }
        to SlotExpr(name, span) { return getBinding(name, span).get() }
        to BindingExpr(name, span) { return getBinding(name, span) }
    }

    def matchBind(patt, value):
        return patt.walk(object patternMatchBinder {
            to IgnorePattern(_span) { return frame }

            to FinalPattern(noun, _span) { return frame.with(b(noun), &&value) }

            to BindingPattern(noun, _span) { return frame.with(b(noun), value) }

            to ListPattern(patterns, span) {
                def l :List := value
                if (patterns.size() != l.size()) {
                    throw(`List pattern couldn't match ${patterns.size()} patterns against ${l.size()} specimens at $span`)
                }
                var f := frame
                # XXX wrong, but maybe ListPatts are going away in lib/mim/anf?
                for i => p in (patterns) { f := matchBind(p, l[i]) }
                return f
            }
        })

    return expr.walk(object evaluator {
        to MethodCallExpr(receiver, verb, args, _namedArgs, _span) {
            # XXX Miranda, namedArgs
            return M.call(receiver(atom), verb,
                          [for arg in (args) arg(atom)],
                          [].asMap())
        }

        # to AssignExpr(lvalue, rvalue, span):

        to FinallyExpr(body, unwinder, _span) {
            return try {
                evaluate(body, frame)
            } finally { evaluate(unwinder, frame) }
        }

        to EscapeExpr(ejectorPattern, body, catchPattern, catchBody, _span) {
            return escape ej {
                evaluate(body, matchBind(ejectorPattern, ej))
            } catch problem {
                if (catchPattern != null && catchBody != null) {
                    evaluate(catchBody, matchBind(catchPattern, problem))
                }
            }
        }

        to IfExpr(test, cons, alt, _span) {
            return evaluate((test(atom) :Bool).pick(cons, alt), frame)
        }

        to LetExpr(pattern, expr, body, _span) {
            return evaluate(body, matchBind(pattern, evaluate(expr, frame)))
        }

        to Atom(a, _span) { return a(atom) }
    })
