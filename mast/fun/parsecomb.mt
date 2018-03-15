exports (main)

# http://www.cs.nott.ac.uk/~pszgmh/pearl.pdf
# http://vaibhavsagar.com/blog/2018/02/04/revisiting-monadic-parsing-haskell/

def sliceString(s :Str) as DeepFrozen:
    def size :Int := s.size()
    def makeStringSlicer(index :Int):
        return def stringSlicer.next(ej):
            def i := index + 1
            return if (i <= size) {
                [s[index], makeStringSlicer(i)]
            } else { ej(`End of string`) }
    return makeStringSlicer(0)

def concat([x, xs :List]) as DeepFrozen:
    return [x] + xs

def augment(parser :DeepFrozen) as DeepFrozen:
    return object augmentedParser extends parser as DeepFrozen:
        to mod(reducer :DeepFrozen):
            return augment(def reduce(s1, ej) as DeepFrozen {
                def [c, s2] := parser(s1, ej)
                return [reducer(c), s2]
            })

        to add(other :DeepFrozen):
            return augment(def added(s1, ej) as DeepFrozen {
                def [a, s2] := parser(s1, ej)
                def [b, s3] := other(s2, ej)
                return [[a, b], s3]
            })

        to shiftLeft(other :DeepFrozen):
            return augment(def left(s1, ej) as DeepFrozen {
                def [c, s2] := parser(s1, ej)
                def [_, s3] := other(s2, ej)
                return [c, s3]
            })

        to shiftRight(other :DeepFrozen):
            return augment(def right(s1, ej) as DeepFrozen {
                def [_, s2] := parser(s1, ej)
                def [c, s3] := other(s2, ej)
                return [c, s3]
            })

        to approxDivide(other :DeepFrozen):
            return augment(def orderedChoice(s, ej) as DeepFrozen {
                escape first { parser(s, first) } catch _ { other(s, ej) }
            })

        to complement():
            return augment(def complement(s, ej) as DeepFrozen {
                return escape fail {
                    parser(s, fail)
                    ej(`parser succeeded`)
                } catch _ { [null, s] }
            })

        to zeroOrMore():
            return augment(def zeroOrMore(var s, _ej) as DeepFrozen {
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

        to joinedBy(sep :DeepFrozen):
            def tail := sep >> augmentedParser
            return (augmentedParser + tail.zeroOrMore()) % concat

object pk as DeepFrozen:
    "A parser kit."

    to anything(s, ej):
        return s.next(ej)

    to satisfies(pred :DeepFrozen):
        return augment(def satisfier(s, ej) as DeepFrozen {
            def rv := def [c, next] := s.next(ej)
            return if (pred(c)) { rv } else { ej(`didn't satisfy $pred`) }
        })

    to equals(obj :DeepFrozen):
        return pk.satisfies(def equalizer(c) as DeepFrozen {
            return obj == c
        })

    to never(_s, ej):
        ej(`parse error?`)

def main(_argv) as DeepFrozen:
    def s := sliceString("1,1,11111,111,1")
    def one := pk.equals('1')
    def comma := pk.equals(',')
    def parser := one.oneOrMore().joinedBy(comma)
    escape ej:
        traceln(`yay`, parser(s, ej))
    catch problem:
        traceln(`nope`, problem)
    traceln(`yerp`)
    return 0
