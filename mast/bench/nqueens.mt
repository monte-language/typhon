def hitAt(ranks, size :Int) :Bool:
    def i := size - 1
    def x := ranks[i]
    var j := 0

    for y in ranks.slice(0, i):
        def d := x - y
        if (x == y | i - j == d | j - i == d):
            return true
        j += 1

    return false


def nQueen(n :Int):
    def ranks := ([0] * n).diverge()
    var size :Int := 1

    while (size > 0):
        def hit :Bool := hitAt(ranks, size)

        if (size == n && !hit):
            return ranks.snapshot()

        if (size < n && !hit):
            ranks[size] := 0
            size += 1
        else:
            while (size > 0):
                ranks[size - 1] += 1
                if (ranks[size - 1] == n):
                    size -= 1
                else:
                    break


def showBoard(ranks):
    def end := ranks.size()
    for rank in ranks:
        def s := ("." * rank) + "*" + ("." * (end - rank - 1))
        traceln(s)


bench(fn {nQueen(8)})
