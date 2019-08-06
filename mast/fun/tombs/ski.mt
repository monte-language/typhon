exports (ski)

# https://en.wikipedia.org/wiki/SKI_combinator_calculus

def s :DeepFrozen := m`fn x { fn y { fn z { x(z)(y(z)) } } }`
def k :DeepFrozen := m`fn x { fn _ { x } }`
def i :DeepFrozen := m`fn x { x }`
def combinators :Map[Str, DeepFrozen] := [=> s, => k, => i]

object ski as DeepFrozen:
    to id() :DeepFrozen:
        return i

    to compile(tree, ej) :DeepFrozen:
        return switch (tree) {
            match [via (ski.compile) x, via (ski.compile) y] { m`$x($y)` }
            match via (combinators.fetch) c { c }
            match invalid { throw.eject(ej, `Invalid branch $invalid`) }
        }

    to compose(left, right):
        return [left, right]
