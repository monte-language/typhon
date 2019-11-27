# import "unittest" =~ [=> unittest :Any]
import "lib/freezer" =~ [=> freezing]
import "lib/proptests" =~ [=> arb, => prop]
exports (acceptanceSuite)

# Acceptance tests for eval(). If eval() works properly, then everything else
# works properly, too.

# These tests are parameterized upon any object `eval` with a .run/2 method,
# to facilitate compiler development.

def ringAxioms(equiv, strategy) as DeepFrozen:
    def ringAxiomAbelianAssociative(hy, a, b, c):
        hy.assert(equiv(m`($a + $b) + $c`, m`$a + ($b + $c)`))
    def ringAxiomAbelianCommutative(hy, a, b):
        hy.assert(equiv(m`$a + $b`, m`$b + $a`))
    def ringAxiomAbelianIdentity(hy, a):
        hy.assert(equiv(m`$a + 0`, a))
    def ringAxiomAbelianInverse(hy, a):
        hy.assert(equiv(m`$a + (-$a)`, m`0`))
    def ringAxiomMonoidAssociative(hy, a, b, c):
        hy.assert(equiv(m`($a * $b) * $c`, m`$a * ($b * $c)`))
    def ringAxiomMonoidIdentity(hy, a):
        hy.assert(equiv(m`$a * 1`, a))
    def ringAxiomDistributiveLeft(hy, a, b, c):
        hy.assert(equiv(m`$a * ($b + $c)`, m`$a * $b + $a * $c`))
    def ringAxiomDistributiveRight(hy, a, b, c):
        hy.assert(equiv(m`($a + $b) * $c`, m`$a * $c + $b * $c`))
    def one := [strategy]
    def two := one * 2
    def three := one * 3
    return [
        prop.test(three, ringAxiomAbelianAssociative),
        prop.test(two, ringAxiomAbelianCommutative),
        prop.test(one, ringAxiomAbelianIdentity),
        prop.test(one, ringAxiomAbelianInverse),
        prop.test(three, ringAxiomMonoidAssociative),
        prop.test(one, ringAxiomMonoidIdentity),
        prop.test(three, ringAxiomDistributiveLeft),
        prop.test(three, ringAxiomDistributiveRight),
    ]

def divisionAxiom(ev, equiv) as DeepFrozen:
    return def testDivisionAxiom(hy, dividend, divisor):
        hy.assume(ev(divisor, safeScope) != 0)
        def [via (freezing) quotient,
             via (freezing) remainder] := ev(m`$dividend.divMod($divisor)`,
                                             safeScope)
        hy.assert(equiv(dividend, m`$divisor * $quotient + $remainder`))

# Containers have zero size iff they are empty.
def zeroSizeIffEmpty(equiv) as DeepFrozen:
    return def testZeroSizeIffEmpty(hy, container):
        hy.assert(equiv(m`$container.size() == 0`, m`$container.isEmpty()`))

# Promises appear to be near once they are resolved.
def resolvedPromisesAreNear(equiv) as DeepFrozen:
    return def testResolvedPromisesAreNear(hy, i):
        hy.assert(equiv(m`true`, m`{
            def x
            bind x := $i
            Ref.isNear(x)
        }`))

# Basic identity template for most data.
def sameEverIdentity(equiv) as DeepFrozen:
    return def testSameEverIdentity(hy, x):
        hy.assert(equiv(x, x))

# Cyclic structures, including maps and lists, compare equal.
def sameEverIdentityCycles(equiv) as DeepFrozen:
    return def testSameEverIdentityCycles(hy, i):
        def l := m`def l := [$i, l]`
        def m := m`def m := [$i => m]`
        hy.assert(equiv(l, l))
        hy.assert(equiv(m, m))

def acceptanceSuite(ev) as DeepFrozen:
    def equiv(l, r, => scope :Map := safeScope):
        def rv := ev(l, scope) == ev(r, scope)
        return rv

    def int := arb.Ast(arb.Int())
    def containers := [
        arb.Bytes(),
        arb.Str(),
        arb.List(arb.Int()),
        arb.Map(arb.Int(), arb.Int()),
        arb.Set(arb.Int()),
    ]

    return (
        # Int forms a ring.
        ringAxioms(equiv, int) +
        # Division is correct.
        [
            prop.test([int, int], divisionAxiom(ev, equiv)),
        ] +
        # Containers.
        [for container in (containers) {
            prop.test([arb.Ast(container)], zeroSizeIffEmpty(equiv))
        }] +
        # Promises.
        [
            prop.test([int], resolvedPromisesAreNear(equiv)),
        ] +
        # Equality axioms.
        # Identity.
        # Identity for primitives.
        [
            prop.test([arb.Ast(arb.Bytes())], sameEverIdentity(equiv)),
            prop.test([arb.Ast(arb.Char())], sameEverIdentity(equiv)),
            prop.test([arb.Ast(arb.Double())], sameEverIdentity(equiv)),
            prop.test([arb.Ast(arb.Int())], sameEverIdentity(equiv)),
            prop.test([arb.Ast(arb.Str())], sameEverIdentity(equiv)),
            # Any data will do here.
            prop.test([int], sameEverIdentityCycles(equiv)),
        ]
    )

# unittest(acceptanceSuite(eval))
