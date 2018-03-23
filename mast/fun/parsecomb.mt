exports (main, pk)

# http://www.cs.nott.ac.uk/~pszgmh/pearl.pdf
# http://vaibhavsagar.com/blog/2018/02/04/revisiting-monadic-parsing-haskell/

def sliceString(s :Str) as DeepFrozen:
    def size :Int := s.size()
    def makeStringSlicer(index :Int) as DeepFrozen:
        return object stringSlicer as DeepFrozen:
            to _printOn(out):
                out.print(`<string size=$size index=$index>`)

            to next(ej):
                def i := index + 1
                return if (i <= size) {
                    [s[index], makeStringSlicer(i)]
                } else { ej(`End of string`) }

            to eject(ej, reason):
                throw.eject(ej, reason)

    return makeStringSlicer(0)

def concat([x, xs :List]) as DeepFrozen:
    return [x] + xs

def pure(x :DeepFrozen) as DeepFrozen:
    return def pure(s, _) as DeepFrozen:
        return [x, s]

def binding(p, f) as DeepFrozen:
    return def bound(s, ej):
        def [b, s2] := p(s, ej)
        return f(b)(s2, ej)

def augment(parser) as DeepFrozen:
    return object augmentedParser extends parser:
        to mod(reducer):
            return augment(def reduce(s1, ej) {
                def [c, s2] := parser(s1, ej)
                return [reducer(c), s2]
            })

        to add(other):
            return augment(def added(s1, ej) {
                def [a, s2] := parser(s1, ej)
                def [b, s3] := other(s2, ej)
                return [[a, b], s3]
            })

        to shiftLeft(other):
            return augment(def left(s1, ej) {
                def [c, s2] := parser(s1, ej)
                def [_, s3] := other(s2, ej)
                return [c, s3]
            })

        to shiftRight(other):
            return augment(def right(s1, ej) {
                def [_, s2] := parser(s1, ej)
                def [c, s3] := other(s2, ej)
                return [c, s3]
            })

        to approxDivide(other):
            return augment(def orderedChoice(s, ej) {
                return escape first {
                    parser(s, first)
                } catch _ { other(s, ej) }
            })

        to complement():
            return augment(def complement(s, ej) {
                return escape fail {
                    def [_, s2] := parser(s, fail)
                    s2.eject(ej, `not $parser`)
                } catch _ { [null, s] }
            })

        to optional():
            return augmentedParser / pure(null)

        to zeroOrMore():
            return augment(def zeroOrMore(var s, _ej) {
                def cs := [].diverge()
                while (true) {
                    def [c, next] := parser(s, __break)
                    cs.push(c)
                    s := next
                }
                return [cs.snapshot(), s]
            })

        to oneOrMore():
            return (augmentedParser + augmentedParser.zeroOrMore()) % concat

        to joinedBy(sep):
            def tail := sep >> augmentedParser
            return (augmentedParser + tail.zeroOrMore()) % concat

        to chainLeft(op):
            def tail := op + parser
            def rest(a):
                def r := tail % fn [f, b] { f(a, b) }
                return augment(binding(r, rest)) / pure(a)
            return augment(binding(parser, rest))

        to chainRight(op):
            def [scan, head, rest] := [
                binding(parser, rest),
                op + scan,
                fn a {
                    def r := head % fn [f, b] { f(a, b) }
                    augment(binding(r, rest)) / pure(a)
                }]
            return augment(scan)

        to bracket(bra, ket):
            return bra >> augmentedParser << ket

object pk as DeepFrozen:
    "A parser kit."

    to pure(obj :DeepFrozen):
        return augment(pure(obj))

    to anything(s, ej):
        return s.next(ej)

    to satisfies(pred :DeepFrozen):
        return augment(def satisfier(s, ej) as DeepFrozen {
            def rv := def [c, next] := s.next(ej)
            return if (pred(c)) { rv } else {
                next.eject(ej, `something satisfying $pred`)
            }
        })

    to equals(obj :DeepFrozen):
        return pk.satisfies(def equalizer(c) as DeepFrozen {
            return obj == c
        })

    to string(iterable):
        var p := pk.pure(null)
        for x in (iterable):
            p <<= pk.equals(x)
        return p

    to never(s, ej):
        s.eject(ej, `an impossibility`)

    to mapping(m :Map):
        return pk.satisfies(m.contains) % m.get

def main(_argv) as DeepFrozen:
    def s := sliceString(`[1,"2",true,4,[],{"key":"val"}]`)
    def e := (pk.equals('e') / pk.equals('E')) + (
        pk.equals('+') / pk.equals('-')).optional()
    def zero := '0'.asInteger()
    def digit := pk.satisfies('0'..'9') % fn c { c.asInteger() - zero }
    def digits := digit.oneOrMore() % fn ds {
        var i :Int := 0
        for d in (ds) { i := i * 10 + d }
        i
    }
    def exp := e >> digits
    def frac := pk.equals('.') >> digits
    def int := (pk.equals('-') >> digits) % fn i { -i } / digits
    def number := (int + frac.optional() + exp.optional()) % fn [[i, f], e] {
        # XXX do floats or whatever
        [i, f, e]
    }
    def plainChar(c) :Bool as DeepFrozen:
        return c != '"' && c != '\\'
    # XXX \u
    def char := pk.satisfies(plainChar) / (pk.equals('\\') >> pk.mapping([
        '"' => '"',
        '\\' => '\\',
        '/' => '/',
        'b' => '\b',
        'f' => '\f',
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
    ]))
    def quote := pk.equals('"')
    def comma := pk.equals(',')
    def string := (char.zeroOrMore() % _makeStr.fromChars).bracket(quote, quote)
    def constant := (pk.string("true") >> pk.pure(true)) / (
        pk.string("false") >> pk.pure(false)) / (pk.string("null") >> pk.pure(null))
    def array
    def obj
    def value := string / number / obj / array / constant
    def elements := value.joinedBy(comma)
    bind array := elements.optional().bracket(pk.equals('['), pk.equals(']'))
    def pair := ((string << pk.equals(':')) + value)
    def members := pair.joinedBy(comma) % _makeMap.fromPairs
    bind obj := members.optional().bracket(pk.equals('{'), pk.equals('}'))
    escape ej:
        traceln(`whoo`, value(s, ej))
    catch problem:
        traceln(`nope`, problem)
    traceln(`yerp`)
    return 0
