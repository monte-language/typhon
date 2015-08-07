def makeComplex(r :Double, i :Double):
    return object complex:
        to real():
            return r

        to imag():
            return i

        to abs():
            return (r * r + i * i).sqrt()

        to add(other):
            return makeComplex(r + other.real(), i + other.imag())

        to multiply(other):
            return makeComplex(r * r - i * i, 2.0 * r * i)


def ITERATIONS :Int := 170


def brotCount(a) :Int:
    var rv := makeComplex(0.0, 0.0)
    var i := ITERATIONS
    while (i > 0 && rv.abs() <= 2):
        rv := makeComplex(rv.real().abs(), rv.imag().abs())
        rv := rv * rv + a
        i -= 1
    # traceln(["Iterations", i, "Seed", a.real(), a.imag()])
    return i


def getChar(count :Int) :Char:
    def chars := "@#&%!*+-."
    def range := chars.size()
    def index := (count * range // ITERATIONS).min(range - 1)
    return chars[index]


def getColor(count :Int) :Str:
    def colors := ["37", "32", "33", "31", "36", "35", "34"]
    def range := colors.size()
    def index := (count * range // ITERATIONS).min(range - 1)
    return colors[index]


def format(count :Int) :Str:
    def c := getChar(count)
    def color := getColor(count)
    return `$\u001b[${color}m$c`


def doStep(start :Double, step :Double, iterations :Int) :List[Double]:
    return [for i in (0..!iterations) start + i * step]


def fullBrot(yStart :Double, yStep :Double, xStart :Double, xStep :Double) :Str:
    def pieces := [].diverge()
    for y in doStep(yStart, yStep, 40):
        for x in doStep(xStart, xStep, 80):
            def count := brotCount(makeComplex(x, y))
            pieces.push(format(count))
        pieces.push("\n")
    pieces.push("\u001b[0m\n")
    return "".join(pieces)


def brotAt(xCenter :Double, yCenter :Double, xScale :Double, yScale :Double) :Str:
    def xStart := xCenter - xScale * 40
    def yStart := yCenter - yScale * 20
    return fullBrot(yStart, yScale, xStart, xScale)


def [=> makeUTF8EncodePump] | _ := import("lib/tubes/utf8")
def [=> makePumpTube] | _ := import("lib/tubes/pumpTube")
def stdout := makePumpTube(makeUTF8EncodePump())
stdout.flowTo(makeStdOut())
# And you thought Pokémon Snap was hard. ~ C.
stdout.receive(brotAt(-0.25, -0.4, 1 / 32.0, 1 / 20.0))
stdout.receive(brotAt(-1.7529296875, -0.025, 1 / 1024.0, 1 / 640.0))

bench(fn {brotAt(-0.25, -0.4, 1 / 32.0, 1 / 20.0)}, "Burning ship (large)")
bench(fn {brotAt(-1.7529296875, -0.025, 1 / 1024.0, 1 / 640.0)},
      "Burning ship (small)")
