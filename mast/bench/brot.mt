import "unittest" =~ [=> unittest]
import "bench" =~ [=> bench]
import "lib/complex" =~ [=> makeComplex :DeepFrozen]
import "lib/tubes" =~ [=> makeUTF8EncodePump :DeepFrozen,
                       => makePumpTube :DeepFrozen]
exports ()


def ITERATIONS :Int := 170


def brotCount(a) :Int as DeepFrozen:
    var rv := makeComplex(0.0, 0.0)
    var i := ITERATIONS
    while (i > 0 && rv.abs() <= 2):
        rv := makeComplex(rv.real().abs(), rv.imag().abs())
        rv := rv * rv + a
        i -= 1
    # traceln(["Iterations", i, "Seed", a.real(), a.imag()])
    return i


def getScaled(l, count :Int) as DeepFrozen:
    def range := l.size()
    def index := (count * range // ITERATIONS).min(range - 1)
    return l[index]


def [=> ramp :DeepFrozen] | _ := ::"import".script("lib/ansiColor")
def chars :Str := "@#&%!*+-."
def colors :List[Str] := ["37", "32", "33", "31", "36", "35", "34"]
def ramp80 :List[Str] := [for i in (ramp(80)) `38;5;$i`].reverse()


def format(count :Int) :Str as DeepFrozen:
    def c := getScaled(chars, count)
    # def color := getScaled(colors, count)
    def color := getScaled(ramp80, count)
    return `$\u001b[${color}m$c`


def doStep(start :Double, step :Double, iterations :Int) :List[Double] as DeepFrozen:
    return [for i in (0..!iterations) start + i * step]


def fullBrot(yStart :Double, yStep :Double, xStart :Double, xStep :Double) :Str as DeepFrozen:
    def pieces := [].diverge()
    for y in doStep(yStart, yStep, 40):
        for x in doStep(xStart, xStep, 80):
            def count := brotCount(makeComplex(x, y))
            pieces.push(format(count))
        pieces.push("\n")
    pieces.push("\u001b[0m\n")
    return "".join(pieces)


def brotAt(xCenter :Double, yCenter :Double, xScale :Double, yScale :Double) :Str as DeepFrozen:
    def xStart := xCenter - xScale * 40
    def yStart := yCenter - yScale * 20
    return fullBrot(yStart, yScale, xStart, xScale)


bench(fn {brotAt(-0.25, -0.4, 1 / 32.0, 1 / 20.0)},
      "Burning ship (large)")
bench(fn {brotAt(-1.7529296875, -0.025, 1 / 1024.0, 1 / 640.0)},
      "Burning ship (small)")

def main(=> makeStdOut) :Int as DeepFrozen:
    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout.flowTo(makeStdOut())
    # And you thought Pokémon Snap was hard. ~ C.
    stdout.receive(brotAt(-0.25, -0.4, 1 / 32.0, 1 / 20.0))
    stdout.receive(brotAt(-1.7529296875, -0.025, 1 / 1024.0, 1 / 640.0))

    return 0
