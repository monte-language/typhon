import "bench" =~ [=> bench]
import "lib/parsers/marley" =~ [=> ::"marley``"]
exports ()

def marleyBench():
    def wp := marley`
        P -> S
        S -> S '+' M | M
        M -> M '*' T | T
        T -> '1' | '2' | '3' | '4'
    `
    def reduce(l):
        switch (l):
            match [=="P", s]:
                return reduce(s)
            match [=="S", s, _, m]:
                return reduce(s) + reduce(m)
            match [=="S", m]:
                return reduce(m)
            match [=="M", m, _, t]:
                return reduce(m) * reduce(t)
            match [=="M", t]:
                return reduce(t)
            match [=="T", c]:
                return c.asInteger() - '0'.asInteger()

    def wpParser := wp("P")
    wpParser.feedMany("1*2+3*4+1*2+3*4")
    return reduce(wpParser.results()[0]) == 28
bench(marleyBench, "Marley arithmetic")

