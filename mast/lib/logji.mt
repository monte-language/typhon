exports (logic)

# A simple logic monad.
# Loosely based on http://homes.sice.indiana.edu/ccshan/logicprog/LogicT-icfp2005.pdf

def zero(ej) as DeepFrozen:
    throw.eject(ej, null)

def isZero(action) :Bool as DeepFrozen:
    return _equalizer.sameYet(action, zero) == true

object logic as DeepFrozen:
    to zero():
        return zero

    to pure(value):
        return fn ej {
            throw.eject(ej, [value, zero])
        }

    to plus(left, right):
        # Optimization: Remove zeroes from the tree.
        return if (isZero(left)) {
            right
        } else if (isZero(right)) { left } else {
            fn ej {
                escape la { left(la) } catch p {
                    if (p =~ [x, next]) {
                        throw.eject(ej, [x, logic.plus(right, next)])
                    } else { right(ej) }
                }
            }
        }

    to "bind"(action, f):
        # Again, remove zeroes from the tree.
        return if (isZero(action)) { zero } else {
            fn ej {
                escape la { action(la) } catch p {
                    if (p =~ [x, next]) {
                        logic.plus(f(x), logic."bind"(next, f))(ej)
                    } else { throw.eject(ej, null) }
                }
            }
        }

    to ifte(test, cons, alt):
        # The zero test is a little different here.
        return if (isZero(test)) { alt } else {
            fn ej {
                escape la { test(la) } catch p {
                    if (p =~ [x, next]) {
                        logic.plus(cons(x), logic."bind"(next, cons))
                    } else { alt }(ej)
                }
            }
        }

    to once(action):
        # Again, remove zeroes from the tree.
        return if (isZero(action)) { zero } else {
            fn ej {
                escape la { action(la) } catch p {
                    throw.eject(ej, if (p =~ [x, _next]) { [x, zero] } else { null })
                }
            }
        }

    to sum(actions :List):
        var rv := zero
        for i => action in (actions.reverse()):
            # Skip zeroes.
            if (isZero(action)):
                continue

            # Do even-odd alternation in order to keep the tree from getting
            # too heavy on one side. This will cause the exploration of the
            # tree to fan out nicely:
            # ▲> _makeList.fromIterable(logic.makeIterable(logic.sum([for i in (0..10) logic.pure(i)])))
            # Result: [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9]
            rv := if (i % 2 == 0) {
                logic.plus(action, rv)
            } else {
                logic.plus(rv, action)
            }
        return rv

    to makeIterable(var action):
        return def makeIterator._makeIterator():
            var i :Int := 0
            return def iterator.next(ej):
                escape la:
                    action(la)
                catch p:
                    def [x, act] exit ej := p
                    action := act
                    def rv := [i, x]
                    i += 1
                    return rv
