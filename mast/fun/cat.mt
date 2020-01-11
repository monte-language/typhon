exports (parse, assemble, catMonte)

def specials :Set[Char] := "(), ".asSet()

def parseAt(s :Str, start :Int) as DeepFrozen:
    var position :Int := start
    def more() { return position < s.size() }
    def rv := [].diverge()
    while (more() && !specials.contains(s[position])):
        def top := position
        while (more() && !specials.contains(s[position])):
            position += 1
        def name := s.slice(top, position)
        if (more() && s[position] == '('):
            def args := [].diverge()
            position += 1
            while (s[position] != ')'):
                def [elt, pos] := parseAt(s, position)
                args.push(elt)
                position := pos
                if (s[position] == ','):
                    position += 1
            rv.push([name, args.snapshot()])
            position += 1
        else:
            rv.push(name)
        def shouldBreak := more() && s[position] != ' '
        if (shouldBreak):
            break
        else:
            position += 1
    return [rv.snapshot(), position]

def parse(s :Str) as DeepFrozen { return parseAt(s, 0)[0] }

def assemble(cat :DeepFrozen, path :List) as DeepFrozen:
    var rv := cat.id()
    for obj in (path):
        def f := switch (obj) {
            match [con, args] {
                M.call(cat, con, [for arg in (args) assemble(cat, arg)],
                       [].asMap())
            }
            match arr { M.call(cat, arr, [], [].asMap()) }
        }
        rv := cat.compose(rv, f)
    return rv

object catMonte as DeepFrozen:
    to id():
        return fn x { x }

    to compose(f, g):
        return fn x { g(f(x)) }

    to pair(left, right):
        return fn x { [left(x), right(x)] }

    to exl():
        return fn [l, _] { l }

    to exr():
        return fn [_, r] { r }

    to unit():
        return fn _ { [] }

    to apply():
        return fn [f, x] { f(x) }

    to curry(f):
        return fn x { fn y { f([x, y]) } }

    to uncurry(f):
        return fn [x, y] { f(x)(y) }

    to "0"():
        return fn _ { 0 }

    to succ():
        return fn x { x + 1 }

    to pr(q, f):
        return fn x { var rv := q([]); for _ in (0..!x) { rv := f(rv) }; rv }

object autoMonte as DeepFrozen:
    "
    Monte primitives as a low-level automaton.
    "

    # We use Mealy machines in the above category of functions.
    # Our machine state is a list/array of Monte values, and our inputs and
    # outputs are single Monte values. A machine skeleton:
    # fn s, i { [s', o] }

    # However, we are implementing the *simulations*. A simulation sends
    # machines to machines.

    to id():
        return fn m { m }

    to compose(f, g):
        return fn x { g(f(x)) }

    to pair(left, right):
        return fn x {
            def lx := left(x)
            def rx := right(x)
            fn s, i {
                def [sl, ol] := lx(s, i)
                def [sr, or] := rx(s, i)
                [[sl, sr], [ol, or]]
            }
        }

    to exl():
        return fn x { fn [s, _], [i, _] { [s, i] } }

    to exr():
        return fn x { fn [_, s], [_, i] { [s, i] } }

    to unit():
        return fn x { fn _, i { i } }
