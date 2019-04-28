exports (logic, makeKanren)

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

# µKanren: Logic variables and unification.
# http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf

def makeKanren() as DeepFrozen:
    def [varSealer, varUnsealer] := makeBrandPair("logic variable")
    def varb := varUnsealer.unsealing

    def makeCS(s :Map, c :Int):
        return object kanren:
            "A state for doing logical unification."

            to fresh(count :Int):
                "Allocate `count` fresh logic variables."

                def next := c + count
                def vars := [for i in (c..!next) varSealer.seal(i)]
                return [makeCS(s, next)] + vars

            to walk(v):
                "
                Look up `v` in this logic context.

                If this method returns its argument unchanged, then it is
                either an unbound logic variable or not a logic variable at
                all.
                "

                return switch (v) {
                    match via (varb) via (s.fetch) x { kanren.walk(x) }
                    match us :List { [for u in (us) kanren.walk(u)] }
                    match _ { v }
                }

            to unify(u, v):
                return switch ([kanren.walk(u), kanren.walk(v)]) {
                    match [via (varb) i, via (varb) j] {
                        logic.pure(if (i == j) { kanren } else {
                            makeCS(s.with(i, v), c)
                        })
                    }
                    match [via (varb) i, rhs] {
                        logic.pure(makeCS(s.with(i, rhs), c))
                    }
                    match [lhs, via (varb) j] {
                        logic.pure(makeCS(s.with(j, lhs), c))
                    }
                    # XXX: zip() from lib/iterators doesn't have a good API
                    # for doing this sort of ragged work cleanly.
                    match [us :List, vs :List] {
                        if (us.size() == vs.size()) {
                            var rv := logic.pure(kanren)
                            for i => x in (us) {
                                rv := logic."bind"(rv, fn k { k.unify(x, vs[i]) })
                            }
                            rv
                        } else { logic.zero() }
                    }
                    match [x, y] {
                        if (x == y) { logic.pure(kanren) } else { logic.zero() }
                    }
                }

    return makeCS([].asMap(), 0)
