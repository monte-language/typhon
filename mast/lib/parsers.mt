exports (main)

# A series of parser controllers.

interface SP :DeepFrozen {}

def buildSlowParser(combo :DeepFrozen) as DeepFrozen:
    return object slow as DeepFrozen:
        "A naïve parser which explores the entire parse forest, up to equality."

        to parseIterable(parser :SP, iterable):
            def l := _makeList.fromIterable(iterable)

            return def slowParser.forest():
                # traceln(`forest() -> ${parser(l)}`)
                return [for [result, leftovers] in (parser(l))
                        ? (leftovers.isEmpty()) result]

        to unit(x):
            return combo(slow, SP, def ::"slowParser.unit"(l) as SP {
                # traceln(`unit($x)($l)`)
                return [[x, l]]
            })

        to "bind"(parser :SP, f):
            return combo(slow, SP, def ::"slowParser.bind"(l) as SP {
                # traceln(`bind($parser, $f)($l)`)
                def rv := [].asSet().diverge()
                for [result, leftovers] in (parser(l)) {
                    for pair in (f(result)(leftovers)) { rv.include(pair) }
                }
                # traceln(`bind($parser, $f)($l) -> $rv`)
                return rv.asList()
            })

        to option(left :SP, right :SP):
            return combo(slow, SP, def ::"slowParser.option"(l) as SP {
                return (left(l).asSet() | right(l).asSet()).asList()
            })

        to anything():
            return combo(slow, SP, def ::"slowParser.anything"(l) as SP {
                # traceln(`anything()($l)`)
                return switch (l) {
                    match [head] + tail { [[head, tail]] }
                    match [] { [] }
                }
            })

        to fail(_reason :Str):
            return combo(slow, SP, def ::"slowParser.failure"(_l) as SP {
                # traceln(`fail($_reason)($_l)`)
                return []
            })

        to label(parser :SP, _label :Str):
            return parser

def combo(m, stamp, action :stamp) as DeepFrozen:
    return object parserCombinator extends action as stamp:
        to add(p :stamp) :stamp:
            return m."bind"(action, fn left {
                m."bind"(p, fn right { m.unit([left, right]) })
            })

        to or(p :stamp) :stamp:
            return m.option(action, p)

def sequence(m :DeepFrozen, l :List) as DeepFrozen:
    "
    Collate a list `l` of monadic actions in monad `m` into a single action,
    yielding a list of the yields of each individual action.
    "

    return if (l =~ [head] + tail):
        var rv := m."bind"(head, fn x { m.unit([x]) })
        for action in (tail):
            rv := m."bind"(rv, fn xs {
                m."bind"(action, fn x { m.unit(xs.with(x)) })
            })
        rv
    else:
        m.unit([])

def makeController(m :DeepFrozen, stamp :DeepFrozen) as DeepFrozen:
    def maybeUnit(x) as DeepFrozen:
        return if (x =~ p :stamp) { p } else { m.unit(x) }

    def failOnEject(f) as DeepFrozen:
        return escape ej { f(ej) } catch problem {
            m.fail(M.toString(problem))
        }

    return object parserController extends m as DeepFrozen:
        to control(operator :Str, argArity :Int, paramArity :Int, block):
            "Build parsers incrementally."

            def buildParserOn(p, config, block, => firstTime :Bool):
                def [args, lambda] := block()
                return switch (config):
                    # The first controller clause can bring in parser pieces.
                    match [=="reduce", count :(Int > 0), ==count] ? (firstTime):
                        def [args, lambda] := block()
                        p + m."bind"(sequence(m, args), fn l {
                            failOnEject(fn ej {
                                m.unit(M.call(lambda, "run", l.with(ej),
                                              [].asMap()))
                            })
                        })
                    match ==["reduce", 0, 1]:
                        def [args, lambda] := block()
                        m."bind"(p, fn x {
                            failOnEject(fn ej { lambda(x, ej) })
                        })
                    match ==["label", 0, 0]:
                        def [args, lambda] := block()
                        m.label(p, lambda())
                    # Token matching. Tokens are triples:
                    # [tag :Str, data :Str, span]
                    match ==["token", 1, 2]:
                        m."bind"(p, fn _ {
                            m."bind"(m.anything(), fn token {
                                failOnEject(fn ej {
                                    def [[tag :Str], lambda] exit ej := block()
                                    def [==tag, data, span] exit ej := token
                                    maybeUnit(lambda(data, span, ej))
                                })
                            })
                        })

            var p := buildParserOn(m.unit(null),
                                   [operator, argArity, paramArity], block,
                                   "firstTime" => true)

            return object parserControlFlow:
                to control(operator :Str, argArity :Int, paramArity :Int, block):
                    p := buildParserOn(p, [operator, argArity, paramArity],
                                       block, "firstTime" => false)
                    return parserControlFlow

                to controlRun():
                    return p

def slowParser :DeepFrozen := makeController(buildSlowParser(combo), SP)

def main(_argv) as DeepFrozen:
    def p := slowParser ("tag") token v, _ {
        slowParser ("moreTag") token x, _ { v + x } |
        slowParser ("moreTag") token x, _ { v - x }
    }
    def l := [["tag", 42, null], ["moreTag", 2, null]]
    def f := slowParser.parseIterable(p, l)
    traceln(f.forest())
    return 0
