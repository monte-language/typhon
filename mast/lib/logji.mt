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
        if (isZero(left)) { return right }
        if (isZero(right)) { return left }
        return fn ej {
            escape la { left(la) } catch p {
                if (p =~ [x, next]) {
                    throw.eject(ej, [x, logic.plus(right, next)])
                } else { right(ej) }
            }
        }

    to "bind"(action, f):
        # Again, remove zeroes from the tree.
        if (isZero(action)) { return zero }
        return fn ej {
            escape la { action(la) } catch p {
                if (p =~ [x, next]) {
                    logic.plus(f(x), logic."bind"(next, f))(ej)
                } else { throw.eject(ej, null) }
            }
        }

    to ifte(test, cons, alt):
        # The zero test is a little different here.
        if (isZero(test)) { return alt }
        return fn ej {
            escape la { test(la) } catch p {
                if (p =~ [x, next]) {
                    logic.plus(cons(x), logic."bind"(next, cons))
                } else { alt }(ej)
            }
        }

    to once(action):
        # Again, remove zeroes from the tree.
        if (isZero(action)) { return zero }
        return fn ej {
            escape la { action(la) } catch p {
                throw.eject(ej, if (p =~ [x, _next]) { [x, zero] } else { null })
            }
        }

    to sum(actions):
        var rv := zero
        for action in (actions):
            rv := logic.plus(rv, action)
        return rv

def iterate(var action):
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
