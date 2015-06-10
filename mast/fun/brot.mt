def [=> makePumpTube] | _ := import("lib/tubes/pumpTube")
def [=> makeUTF8EncodePump] | _ := import("lib/tubes/utf8")


def makeComplex(r, i):
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
            return makeComplex(r * r - i * i, 2 * r * i)


def ITERATIONS := 170


def brotCount(a):
    var rv := makeComplex(0.0, 0.0)
    var i := ITERATIONS
    while (i > 0 && rv.abs() <= 2):
        rv := makeComplex(rv.real().abs(), rv.imag().abs())
        rv := rv * rv + a
        i -= 1
    # traceln(["Iterations", i, "Seed", a.real(), a.imag()])
    return i


def getChar(count):
    def chars := "@#&%!*+-."
    def range := chars.size()
    def index := (count * range // ITERATIONS).min(range - 1)
    return chars[index]


def getColor(count):
    def colors := ["37", "32", "33", "31", "36", "35", "34"]
    def range := colors.size()
    def index := (count * range // ITERATIONS).min(range - 1)
    return colors[index]


def format(count):
    def c := getChar(count)
    def color := getColor(count)
    return "\u001b[" + color + "m" + c


def doStep(start, step, iterations):
    def rv := [].diverge()
    var i := 0
    while (i < iterations):
        rv.push(start + i * step)
        i += 1
    return rv.snapshot()

def stdout := makePumpTube(makeUTF8EncodePump())
stdout.flowTo(makeStdOut())

def fullBrot(yStart, yStep, xStart, xStep):
    for y in doStep(yStart, yStep, 40):
        for x in doStep(xStart, xStep, 80):
            def count := brotCount(makeComplex(x, y))
            stdout.receive(format(count))
        stdout.receive("\n")
    stdout.receive("\u001b[0m\n")


def brotAt(xCenter, yCenter, xScale, yScale):
    def xStart := xCenter - xScale * 40
    def yStart := yCenter - yScale * 20
    fullBrot(yStart, yScale, xStart, xScale)


brotAt(-0.5, -0.1, 1 / 32.0, 1 / 20.0)
brotAt(-1.75, -0.01, 1 / 1024.0, 1 / 640.0)
#fullBrot(-1.5, 1 / 20.0, -1.5, 1 / 32.0)
#fullBrot(-0.0625, 1 / 320.0, -1.828125, 1 / 512.0)
