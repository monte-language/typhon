import "unittest" =~ [=> unittest :Any]
import "lib/proptests" =~ [=> arb, => prop]
exports (mp, ::"parse``", main)

# Parse: Dead-simple reasonably-performing incremental parser toolkit.
# Based largely on this functional pearl:
# http://matt.might.net/papers/might2011derivatives.pdf

# Not using lib/enum because we might need to be prelude-compatible at some
# point in the future.
object empty as DeepFrozen {}
object eps as DeepFrozen {}
object red as DeepFrozen {}
object cat as DeepFrozen {}
object alt as DeepFrozen {}
object rep as DeepFrozen {}

object exactly as DeepFrozen {}
# These two are not in the original paper. They permit matching inputs not by
# equality, but by set membership or predicate.
object oneOf as DeepFrozen {}
object suchThat as DeepFrozen {}

def emptyYet(x) as DeepFrozen { return _equalizer.sameYet(x, empty) }

def kleeneMemo(f :DeepFrozen, default :DeepFrozen) as DeepFrozen:
    object pending as DeepFrozen {}
    return object memoized as DeepFrozen:
        match [=="run", topArgs, _]:
            var table := [].asMap()
            object recurse:
                match [=="run", args, _]:
                    if (table.contains(args)):
                        if (table[args] == pending):
                            def rv := default()
                            table with= (args, rv)
                            rv
                        else:
                            table[args]
                    else:
                        table with= (args, pending)
                        def rv := M.call(f, "run", [recurse] + args, [].asMap())
                        table with= (args, rv)
                        rv
            M.call(recurse, "run", topArgs, [].asMap())

def _parseNull(parseNull, parser) :Set as DeepFrozen:
    return switch (parser) {
        match ==empty { [].asSet() }
        match [==eps, set] { set }
        match [==cat, l, r] {
            var s := [].asSet()
            for p in (parseNull(l)) {
                for q in (parseNull(r)) { s with= ([p, q]) }
            }
            s
        }
        match [==alt, l, r] { parseNull(l) | parseNull(r) }
        match [==rep, _] { [[]].asSet() }
        match [==red, l, f] { [for x in (parseNull(l)) f(x)].asSet() }

        match [==exactly, _] { [].asSet() }
        match [==oneOf, _] { [].asSet() }
        match [==suchThat, _] { [].asSet() }
    }
def parseNull :DeepFrozen := kleeneMemo(_parseNull, [].asSet)

def _leaders(leaders, parser) :Set as DeepFrozen:
    return switch (parser) {
        match ==empty { [].asSet() }
        match [==cat, l, r] {
            if (!parseNull(l).isEmpty()) {
                leaders(l) | leaders(r)
            } else { leaders(l) }
        }
        match [==alt, l, r] { leaders(l) | leaders(r) }
        match [==rep, l] { leaders(l).with(eps) }
        match [==red, l, _] { leaders(l) }
        match [==eps, _] { [eps].asSet() }
        match [tag, _] ? ([exactly, oneOf, suchThat].contains(tag)) {
            [parser].asSet()
        }
    }
def leaders :DeepFrozen := kleeneMemo(_leaders, [].asSet)

def breakOut(parser) as DeepFrozen:
    var m := [empty => 0]
    def stack := [parser].diverge()
    var label :Int := 1
    while (!stack.isEmpty()):
        def piece := stack.pop()
        if (!m.contains(piece)):
            m with= (piece, label)
            label += 1
            for p in (piece):
                if (p =~ _ :List):
                    stack.push(p)
    return m

def singletonSet(specimen, ej) as DeepFrozen:
    def s :Set ? (s.size() == 1) exit ej := specimen
    return s.asList()[0]

def compose(f, g) as DeepFrozen:
    return def composed(x):
        return g(f(x))

def derive(c, parser) as DeepFrozen:
    # NB: Cycles are likelier to happen on earlier pieces. (Proof: Think about
    # it for a bit.) This reversal makes emptyYet likelier to return true. ~ C.
    def breakout := breakOut(parser).reverse()
    def table := [for piece => _ in (breakout) piece => Ref.promise()]
    def go(piece):
        return table[piece][0]
    def derived := [for piece => _ in (table) piece => {
        def next := switch (piece) {
            match ==empty { empty }
            match [==eps, _] { empty }
            match [==cat, l, r] {
                def dl := go(l)
                def [lhs, skipLeft] := if (emptyYet(dl)) {
                    [empty, true]
                } else if (dl =~ [==eps, via (singletonSet) t1]) {
                    [[red, r, fn t2 { [t1, t2] }], false]
                } else { [[cat, dl, r], false] }
                def dr := go(r)
                def [rhs, skipRight] := if (emptyYet(dr)) {
                    [empty, true]
                } else {
                    def nullable := parseNull(l)
                    if (nullable.isEmpty()) {
                        [empty, true]
                    } else if (nullable =~ via (singletonSet) t1) {
                        [[red, dr, fn t2 { [t1, t2] }], false]
                    } else {
                        [[cat, [eps, nullable], dr], false]
                    }
                }
                def rv := if (skipLeft) {
                    if (skipRight) { empty } else { rhs }
                } else if (skipRight) { lhs } else { [alt, lhs, rhs] }
                rv
            }
            match [==alt, l, r] {
                def dl := go(l)
                def dr := go(r)
                if (emptyYet(dl)) { dr } else if (emptyYet(dr)) {
                    dl
                } else { [alt, dl, dr] }
            }
            match [==rep, l] {
                def dl := go(l)
                if (emptyYet(dl)) { [eps, [[]].asSet()] } else {
                    [red, [cat, dl, piece], fn [h, t] { [h] + t }]
                }
            }
            match [==red, l, outerRed] {
                var f := outerRed
                var dl := go(l)
                if (dl =~ [==red, inner, innerRed]) {
                    dl := inner
                    f := compose(innerRed, outerRed)
                }
                if (emptyYet(dl)) { empty } else if (dl =~ [==eps, ts]) {
                    [eps, [for t in (ts) f(t)].asSet()]
                } else { [red, dl, f] }
            }
            match [==exactly, specimen] {
                if (c == specimen) { [eps, [c].asSet()] } else { empty }
            }
            match [==oneOf, set] {
                if (set.contains(c)) { [eps, [c].asSet()] } else { empty }
            }
            match [==suchThat, pred] {
                if (pred(c)) { [eps, [c].asSet()] } else { empty }
            }
        }
        table[piece][1].resolve(next)
        next 
    }]
    return derived[parser]

def _sizeOf(sizeOf, parser) :Int as DeepFrozen:
    return 1 + switch (parser) {
        match ==empty { 0 }
        match [==eps, _] { 0 }
        match [==cat, l, r] { sizeOf(l) + sizeOf(r) }
        match [==alt, l, r] { sizeOf(l) + sizeOf(r) }
        match [==rep, l] { sizeOf(l) }
        match [==red, l, _] { sizeOf(l) }

        match [==exactly, _] { 0 }
        match [==oneOf, _] { 0 }
        match [==suchThat, _] { 0 }
    }
def zero :Int := 0
def sizeOf :DeepFrozen := kleeneMemo(_sizeOf, &zero.get)

object noValue as DeepFrozen {}
object parserMarker as DeepFrozen {}

def unwrap(combinator, ej) as DeepFrozen:
    def parser := combinator._sealedDispatch(parserMarker)
    return if (parser == null) {
        throw.eject(ej, `Not a parser combinator`)
    } else { parser }

def wrap(parser) as DeepFrozen:
    return object parserCombinator:
        to _sealedDispatch(brand):
            return if (brand == parserMarker) { parser }

        to size() :Int:
            return sizeOf(parser)

        # Standard combinators.

        to reduce(f):
            return wrap([red, parser, f])

        to add(via (unwrap) other):
            return wrap([cat, parser, other])

        to or(via (unwrap) other):
            return wrap([alt, parser, other])

        to zeroOrMore():
            return wrap([rep, parser])

        to oneOrMore():
            return wrap([red, [cat, parser, [rep, parser]],
                fn [h, t] { [h] + t }])

        to optional(=> default := null):
            return wrap([alt, [eps, [default].asSet()], parser])

        to join(via (unwrap) element):
            return wrap([red, [cat, [red, element, _makeList],
                          [rep, [red, [cat, parser, element], fn [_, x] { x }]]],
                    fn [h, t] { h + t }])

        to bracket(via (unwrap) bra, via (unwrap) ket):
            return wrap([red, [cat, bra, [cat, parser, ket]],
                fn [_, [x, _]] { x }])

object mp as DeepFrozen:
    # Primitives.

    to exactly(value):
        return wrap([exactly, value])

    to oneOf(values :Set):
        return wrap([oneOf, values])

    to suchThat(predicate):
        return wrap([suchThat, predicate])

    # For parsing characters specifically.

    to keyword(s :Str, => value := noValue):
        def [h] + t := s.asList()
        var p := [exactly, h]
        for char in (t):
            p := [cat, p, [exactly, char]]
        return wrap([red, p,
            fn _ { if (value == noValue) { s } else { value } }])

    to token(s :Str):
        "Eat leading whitespace and then parse `s`."

        def whitespace := wrap([oneOf, " \n".asSet()]).zeroOrMore()
        return (whitespace + mp.keyword(s)).reduce(fn [_, y] { y })

    to stringOf(chars :Set[Char]):
        def char := wrap([oneOf, chars])
        return wrap([red, char.oneOrMore(), _makeStr.fromChars])

    to integer():
        # XXX support other radices
        def digits := "1234567890".asSet()
        def f(ds):
            return _makeInt(_makeStr.fromChars(ds))
        return wrap([oneOf, digits]).oneOrMore().reduce(f)

def main(_argv) as DeepFrozen:
    def e := {
        def p := mp.oneOf("eE".asSet()) + mp.oneOf("+-".asSet()).optional()
        p.reduce(fn [_, negate] { negate == '-' })
    }
    def digits := mp.integer()
    def exp := (e + digits).reduce(fn [negate, i] {
        if (negate) { -i } else { i }
    })
    def frac := (mp.exactly('.') + digits).reduce(fn [_, y] { y })
    def int := (mp.exactly('-').optional() + digits).reduce(fn [negate, i] {
        if (negate == null) { i } else { -i }
    })
    def number := int + frac.optional() + exp.optional()
    def char := mp.suchThat(fn x { x != '"' })
    def chars := char.zeroOrMore()
    def string := chars.bracket(mp.exactly('"'),
        mp.exactly('"')).reduce(_makeStr.fromChars)
    def [value, elements, array, pair, members, obj] := [
        string | number | obj | array | mp.keyword("true", "value" => true) |
            mp.keyword("false", "value" => false) |
            mp.keyword("null", "value" => null),
        mp.token(",").join(value).optional("default" => []),
        elements.bracket(mp.token("["), mp.token("]")),
        (string + mp.token(":") + value).reduce(fn [k, [_, v]] { [k, v] }),
        mp.token(",").join(pair).optional("default" => []).reduce(fn pairs {
            [for [k, v] in (pairs) k => v]
        }),
        members.bracket(mp.token("{"), mp.token("}")),
    ]
    def testParse(var parser, input):
        for char in (input):
            traceln(`Feeding ${M.toQuote(char)}`)
            def old := parser
            parser := derive(char, parser)
            def ls := leaders(parser)
            if (ls.isEmpty()):
                throw(`Fed ${M.toQuote(char)}, couldn't advance; wanted ${leaders(old)}`)
        return parseNull(parser)
    traceln(testParse(unwrap(obj, null), `
{
  "selska": [
    "zirpu"
  ],
  "selcmi": {
    "bangu": {
      "ve tavla": {}
    }
  },
  "du": {
    "se vacri": "plini"
  }
}
    `))
    return 0

def parserPrimitiveAlt(hy, c1, c2):
    def p := [alt, [exactly, c1], [exactly, c2]]
    hy.sameEver(parseNull(derive(c1, p)), [c1].asSet())
    hy.sameEver(parseNull(derive(c2, p)), [c2].asSet())

def parserPrimitiveCat(hy, c1, c2):
    def p := [cat, [exactly, c1], [exactly, c2]]
    hy.sameEver(parseNull(derive(c2, derive(c1, p))), [[c1, c2]].asSet())

def parserPrimitiveRep(hy, c, size):
    hy.assume(size >= 0)
    def p := [rep, [exactly, c]]
    var d := p
    for _ in (0..!size):
        d := derive(c, d)
    hy.sameEver(parseNull(d), [[c] * size].asSet())

unittest([
    prop.test([arb.Char(), arb.Char()], parserPrimitiveAlt),
    prop.test([arb.Char(), arb.Char()], parserPrimitiveCat),
    prop.test([arb.Char(), arb.Int("ceiling" => 42)], parserPrimitiveRep),
])


def oneOrMore(p) :DeepFrozen:
    def cons([h, t]) as DeepFrozen:
        return [h] + t
    return [red, [cat, p, [rep, p]], cons]

def parserHelperOneOrMore(hy, c, size):
    hy.assume(size >= 1)
    def p := oneOrMore([exactly, c])
    var d := p
    for _ in (0..!size):
        d := derive(c, d)
    hy.sameEver(parseNull(d), [[c] * size].asSet())

unittest([
    prop.test([arb.Char(), arb.Int("ceiling" => 42)], parserHelperOneOrMore),
])


object exprHoleTag as DeepFrozen {}

def throwParseError(parser) as DeepFrozen:
    throw(`Error: ${leaders(parser)}`)

def makeQP(name :Str, parser :DeepFrozen, substituter :DeepFrozen) as DeepFrozen:
    return object quasiParser as DeepFrozen:
        to _printOn(out):
            out.print(`<$name````>`)

        to valueHole(index :Int):
            return [exprHoleTag, index]

        to valueMaker(pieces):
            var p := parser

            def advance(x):
                def old := p
                p := derive(x, p)
                if (leaders(p).isEmpty()):
                    throwParseError(old)

            for piece in (pieces):
                if (piece =~ [==exprHoleTag, index :Int]):
                    advance(piece)
                else:
                    for char in (piece):
                        advance(char)

            def forest := parseNull(parser)
            if (forest =~ via (singletonSet) tree):
                return def ruleSubstituter.substitute(values):
                    return substituter(tree, values)
            else if (forest.isEmpty()):
                throw(`Parse error`)
            else:
                throw(`Ambiguous parse forest: $forest`)


def testParser(p, cases :Map):
    return def testParserCase(assert):
        for input => output in (cases):
            var d := p
            for char in (input):
                d := derive(char, d)
            assert.equal(parseNull(d), [output].asSet())

object nt as DeepFrozen {}

def snd([_, x]) as DeepFrozen:
    return x

def ws := [oneOf, " \n".asSet()]
def eat(p) :DeepFrozen:
    return [red, [cat, [rep, ws], p], snd]

unittest([
    testParser(eat([exactly, 'x']), ["x" => 'x', " x" => 'x', "  x" => 'x']),
])

def chars := [oneOf, [for c in ('a'..'z' | 'A'..'Z' | '0'..'9') c].asSet()]
def word := [red, oneOrMore(chars), _makeStr.fromChars]

unittest([
    testParser(word, ["word" => "word", "hunter2" => "hunter2"]),
    # testParser(eat(word), [
    #     "  word" => "word", "  hunter2" => "hunter2",
    #     " word" => "word", " hunter2" => "hunter2",
    #     "word" => "word", "hunter2" => "hunter2",
    # ]),
])

def expr := oneOrMore(eat(word))

def buildEq([name, [_, [p, _]]]) as DeepFrozen:
    return [name, p]
def eq := [red, [cat, eat(word), [cat, eat([exactly, '=']),
    [cat, expr, eat([exactly, ';'])]]], buildEq]
def buildQP([eqs, _]) as DeepFrozen:
    return _makeMap.fromPairs(eqs)
def qp := [red, [cat, oneOrMore(eq), [rep, ws]], buildQP]

def finishQP(nts :Map[Str, DeepFrozen], _) :DeepFrozen as DeepFrozen:
    def m := [for k => _ in (nts) k => Ref.promise()]
    throw(m)

def ::"parse``" :DeepFrozen := makeQP("parse", qp, finishQP)
# traceln(parse`
#     x = y z;
# `)
