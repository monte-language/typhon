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
        # Partial evaluation to affine normal form. It doesn't matter how the
        # RHS is structured, only whether the LHS needs to examine it more
        # than once.
        return switch (left) {
            # I is affine in its lone argument.
            # Ix -> x
            match =="i" { right }
            # K is affine in both arguments, but can only be removed if fully
            # applied.
            # Kxy -> x
            match [=="k", x] { x }
            # S is affine iff one of its first two arguments discards its
            # input; that is, if one of them is a partially-applied Kx.
            # S(Kx)yz -> x(yz)
            match [[=="s", [=="k", x]], y] {
                ski.compose(x, ski.compose(y, right))
            }
            # Sx(Ky)z -> xzy
            match [[=="s", x], [=="k", y]] {
                ski.compose(ski.compose(x, right), y)
            }
            match _ { [left, right] }
        }

    to optimize(tree):
        return switch (tree) {
            match [x, y] { ski.compose(x, y) }
            match leaf { leaf }
        }
