exports (SKI, SKIToMonte)

# https://en.wikipedia.org/wiki/SKI_combinator_calculus

object SKI as DeepFrozen:
    to signature():
        return "ski"

    to guard():
        return Any

    to id():
        return "i"

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
                SKI.compose(x, SKI.compose(y, right))
            }
            # Sx(Ky)z -> xzy
            match [[=="s", x], [=="k", y]] {
                SKI.compose(SKI.compose(x, right), y)
            }
            match _ { [left, right] }
        }

def s :DeepFrozen := m`fn x { fn y { fn z { x(z)(y(z)) } } }`
def k :DeepFrozen := m`fn x { fn _ { x } }`
def i :DeepFrozen := m`fn x { x }`
def combinators :Map[Str, DeepFrozen] := [=> s, => k, => i]

object SKIToMonte as DeepFrozen:
    to signature():
        return ["ski", "monte"]

    to run(tree) :DeepFrozen:
        return switch (tree) {
            match [via (SKIToMonte) x, via (SKIToMonte) y] { m`$x($y)` }
            match via (combinators.fetch) c { c }
        }
