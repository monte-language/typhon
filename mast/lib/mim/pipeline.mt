# import "unittest" =~ [=> unittest :Any]
# import "tests/acceptance" =~ [=> acceptanceSuite]
import "lib/mim/expand" =~ [=> expand]
import "lib/mim/anf" =~ [=> makeNormal]
# import "lib/mim/mix" =~ [=> makeMixer]
exports (go, pretty, evaluate)

object pretty as DeepFrozen:
    to LiteralExpr(value, _):
        return M.toQuote(value)

    to NounExpr(name, _):
        # XXX shame syntax
        return name

    to SlotExpr(name, _):
        return `&$name`

    to BindingExpr(name, _):
        return `&&$name`

    to ObjectExpr(docstring, name, asExpr, auditors, script, _):
        def auds := if (asExpr != null) { `as $asExpr` } else { "" }
        def imps := if (auditors.isEmpty()) { "" } else {
            `implements ${", ".join(auditors)}`
        }
        def doc := if (docstring == null) { "" } else { M.toQuote(docstring) }
        return `object $name $auds $imps {$doc $script }`

    to MethodCallExpr(receiver, verb, arguments, namedArguments, _):
        def args := ", ".join(arguments)
        def namedArgs := ", ".join(namedArguments)
        def message := if (args.isEmpty() && namedArgs.isEmpty()) { "" } else {
            if (args.isEmpty()) { namedArgs } else if (namedArgs.isEmpty()) { args }
        }
        return `$receiver.${M.toQuote(verb)}($message)`

    to FinallyExpr(body, unwinder, _):
        return `try { $body } finally { $unwinder }`

    to IfExpr(test, alt, cons, _):
        return `if ($test) { $alt } else { $cons }`

    to LetExpr(pattern, expr, body, _):
        return `let ($expr) =~ $pattern in { $body }`

    to EscapeExpr(pattern, body, _):
        return `escape $pattern { $body }`

    to JumpExpr(ejector, arg, _):
        return `throw.eject($ejector, $arg)`

    to Atom(atom, _):
        return atom

    to IgnorePattern(_):
        return "_"

    to FinalPattern(noun, guard, _):
        return if (guard == null) { noun } else { `$noun :$guard` }

    to BindingPattern(noun, _):
        return `&&$noun`

    to ListPattern(patterns, _):
        return `[${",".join(patterns)}]`

    to NamedArg(key, value, _):
        return `($key) => $value`

    to NamedParam(key, value, default, _):
        def d := if (default != null) { ` := $default` } else { "" }
        return `($key) => $value` + d

    to "Method"(docstring, verb, parameters, namedParameters, resultGuard, body, _):
        def params := ", ".join(parameters)
        def namedParams := ", ".join(namedParameters)
        def sig := if (params.isEmpty() && namedParams.isEmpty()) { "" } else {
            if (params.isEmpty()) { namedParams } else if (namedParams.isEmpty()) { params }
        }
        def rg := if (resultGuard == null) { "" } else { `:$resultGuard` }
        def doc := if (docstring == null) { "" } else { M.toQuote(doc) }
        return `method ${M.toQuote(verb)}($sig) $rg {$doc $body }`

    to Script(methods, matchers, _):
        def ms := " ".join([for [patt, body] in (matchers) {
            `match $patt { $body }`
        }])
        return `${" ".join(methods)} $ms`

def go(expr :DeepFrozen) as DeepFrozen:
    def normalized := makeNormal().alpha(expand(expr))
    # def reductionBasis := [
    #     => &&true, => &&false, => &&null,
    #     => &&_makeList,
    #     => &&Bool, => &&Char, => &&Double, => &&Int, => &&Str,
    # ]
    # return makeMixer(anf, reductionBasis).mix(normalized, [].asMap())
    return normalized

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

    return expr.walk(object evaluator extends atom {
        to MethodCallExpr(receiver, verb, args, _namedArgs, _span) {
            # XXX Miranda, namedArgs
            return M.call(receiver(atom), verb,
                          [for arg in (args) arg(atom)],
                          [].asMap())
        }

        to FinallyExpr(body, unwinder, _span) {
            return try {
                evaluate(body, frame)
            } finally { evaluate(unwinder, frame) }
        }

        to EscapeExpr(patt, body, _span) {
            return escape ej {
                evaluate(body, matchBind(patt, ej))
            }
        }

        to JumpExpr(ejector, arg, _span) {
            throw.eject(ejector, arg)
        }

        to IfExpr(test, cons, alt, _span) {
            return evaluate((test(atom) :Bool).pick(cons, alt), frame)
        }

        to LetExpr(pattern, expr, body, _span) {
            return evaluate(body, matchBind(pattern, evaluate(expr, frame)))
        }

        to Atom(a, _span) { return a(atom) }
    })

# unittest(acceptanceSuite(fn expr, frame { evaluate(go(expr), frame) }))
