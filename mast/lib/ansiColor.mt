def HSVToRGB(h :Double, s :Double, v :Double) :List[Double]:
    "Like Python's colorsys."
    if (s <=> 0.0):
        return [v, v, v]

    def i :Int := (h * 6.0).floor()
    def f := (h * 6.0) - i
    def p := v * (1.0 - s)
    def q := v * (1.0 - s * f)
    def t := v * (1.0 - s * (1.0 - f))

    return switch (i % 6):
        match ==0:
            [v, t, p]
        match ==1:
            [q, v, p]
        match ==2:
            [p, v, t]
        match ==3:
            [p, q, v]
        match ==4:
            [t, p, v]
        match ==5:
            [v, p, q]

def HSVToANSI(h :Double, s :Double, v :Double) :Int:
    if (s < 0.1):
        return (v * 23).floor() + 232

    def [r, g, b] := [for d in (HSVToRGB(h, s, v)) (d * 5).floor()]
    return 16 + r * 36 + g * 6 + b

def rampIndex(i :Int, num :(Int > i)) :Int:
    def i0 := i / num
    def h := 0.57 + i0
    def s := 1 - (i0 * i0 * i0)
    def v := 1.0
    return HSVToANSI(h, s, v)

def ramp(size :Int) :List[Int]:
    return [for i in (0..!size) rampIndex(i, size)]

[=> ramp]
