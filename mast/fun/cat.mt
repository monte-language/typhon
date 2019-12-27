import "unittest" =~ [=> unittest :Any]
exports (parse, assemble, concat)

def specials :List[Char] := [' ', ',', '(', ')']
def specialPred(x) as DeepFrozen { return !specials.contains(x) }

object functors as DeepFrozen:
    to id(x):
        return x

    to diagonal(x):
        return [x, x]

def parse(s :Str, cat :DeepFrozen) as DeepFrozen:
    def path := s.split(" ")
    def go(id) { return M.call(cat, id, [], [].asMap()) }
    return [for expr in (path) switch (expr) {
        match `@functor(@guts)` {
            def args := [for a in (guts.split(",")) go(a)]
            M.call(functors, functor, args, [].asMap())
        }
        match id { go(id) }
    }]

def assemble(cat :DeepFrozen, path :List) as DeepFrozen:
    var rv := cat.id()
    for arrow in (path):
        rv := cat.compose(rv, arrow)
    return rv

object polyMonte as DeepFrozen:
    to id():
        return fn x { x }

    to compose(f, g):
        return fn x { g(f(x)) }

    to unit(size :Int):
        return [null] * size

    to pair(left, right):
        return [left, right]

    to exl():
        return fn [l, _] { l }

    to exr():
        return fn [_, r] { r }

    to braid():
        return fn [l, r] { [r, l] }

    to diagonal():
        return fn x { [x, x] }

    to apply():
        return fn [f, x] { f(x) }

# http://tunes.org/~iepos/joy.html

# This is a theory of concatenative combinators. We will show that some common
# combinators yield a Turing category.

object concat as DeepFrozen:
    to id():
        return []

    to compose(x, y):
        return x + y

    to unit(size :Int):
        return ["drop"] * size

    to pair(left :List, right :List):
        return right + left

    to exl():
        return ["drop"]

    to exr():
        return ["swap", "drop"]

    to braid():
        return ["swap"]

    to diagonal():
        return ["dup"]

# The internal hom is encoded using quotations. As a consequence, every
# internal hom comes with source code.

    to apply():
        return ["swap", "i"]

    to tuple():
        return [["i", "swap"], "cons"]

    to lift():
        return [[[["i"], "cons"], "dip", ["dip"], "dip", "i", "cons"],
                "cons", "cons", "cons"]

    to curry():
        return [[[["i"]], "dip", ["cons", "dip", "i"], "dip", "i"], "cons",
                "cons", "cons"]

    to uncurry():
        return [[["swap"], "dip", "i", "i"], "cons"]

    to codeApply():
        return [["i", "swap", "cat"], "cons"]

    to codeLambda():
        return ["i"]

# Products are encoded directly using the stack. This gives a strict monoidal
# product, so that we do not need to check the triangle nor pentagon
# identities.

def reduce(q :List) :List as DeepFrozen:
    "Shrink a quotation according to the equivalence of stack effects."

    # Keep this sorted.
    return switch (q) {
        match [=="dup", =="drop"] + rest { reduce(rest) }
        match [=="dup", =="swap"] + rest { reduce(["dup"] + rest) }
        match [=="swap", =="swap"] + rest { reduce(rest) }
        match [[[=="i"], =="dip", =="i"], =="cons", =="cons"] + rest {
            reduce(["cat"] + rest)
        }
        match [[], =="cons"] + rest { reduce(["unit"] + rest) }
        match [q :List] + rest { [reduce(q)] + reduce(rest) }
        match [head] + rest { [head] + reduce(rest) }
        match _ { q }
    }

def catReduceCartesian(assert):
    def diag := concat.diagonal()
    def e := concat.unit(1)
    def left := concat.pair([], e)
    def right := concat.pair(e, [])

    assert.equal(reduce(diag + left), [])
    assert.equal(reduce(diag + right), [])
    assert.equal(concat.exl(), reduce(left))
    assert.equal(concat.exr(), reduce(right))

def catReduceBraid(assert):
    assert.equal(reduce(concat.braid() + concat.braid()), [])

def catReduceCurry(assert):
    assert.equal(reduce(concat.curry() + concat.uncurry()), [])
    assert.equal(reduce(concat.uncurry() + concat.curry()), [])

def catReduceTuring(assert):
    assert.equal(reduce(concat.codeApply() + concat.codeLambda()), [])

unittest([
    catReduceCartesian,
    catReduceBraid,
    catReduceCurry,
    catReduceTuring,
])

def makeInterpreter() as DeepFrozen:
    def stack := [].diverge()

    return def interpret(q :List):
        for inst in (q):
            switch (inst) {
                match =="cat" {
                    def r := stack.pop()
                    def l := stack.pop()
                    stack.push(l + r)
                }
                match =="cons" {
                    def t := stack.pop()
                    def h := stack.pop()
                    stack.push([h] + t)
                }
                match =="dip" {
                    def f := stack.pop()
                    def s := stack.pop()
                    interpret(f)
                    stack.push(s)
                }
                match =="drop" { stack.pop() }
                match =="dup" { stack.push(stack.last()) }
                match =="i" { interpret(stack.pop()) }
                match =="swap" {
                    def x := stack.pop()
                    def y := stack.pop()
                    stack.push(x)
                    stack.push(y)
                }
                match l :List { stack.push(l) }
            }
        return stack.snapshot()
