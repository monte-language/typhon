exports (logic, makeKanren, unify)

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

# Notes on the data model:
# * We use a brand to protect logic variables from inspection
# * The variables themselves are Ints
# * We unify entire lists at a time, rather than Scheme-style pairs
# * Unbound fresh logic variables are not scoped! Use this for extraction

def makeKanren() as DeepFrozen:
    def [varSealer, varUnsealer] := makeBrandPair("logic variable")
    def varb := varUnsealer.unsealing

    def walkOn(s :Map, v):
        return switch (v) {
            match via (varb) via (s.fetch) x { walkOn(s, x) }
            match us :List { [for u in (us) walkOn(s, u)] }
            match _ { v }
        }

    def unifyOn(s :Map, u, v):
        return switch ([walkOn(s, u), walkOn(s, v)]) {
            match [via (varb) i, via (varb) j] {
                if (i == j) { [].asMap() } else { [i => v, j => v] }
            }
            match [via (varb) i, rhs] { [i => rhs] }
            match [lhs, via (varb) j] { [j => lhs] }
            # XXX: zip() from lib/iterators doesn't have a good API
            # for doing this sort of ragged work cleanly.
            match [us :List, vs :List] {
                if (us.size() == vs.size()) {
                    var rv := [].asMap()
                    for i => x in (us) {
                        def sub := unifyOn(s, x, vs[i])
                        if (sub == null) { return null }
                        rv |= sub
                    }
                    rv
                }
            }
            match [x, y] { if (x == y) { [].asMap() } }
        }

    # s: substitutions
    # d: disequality constraint store
    # c: next state variable offset
    def makeCS(s :Map, d :List[Map], c :Int):
        "Create a constraint package."

        return object kanren:
            "A state for doing logical unification."

            to fresh(count :Int):
                "Allocate `count` fresh logic variables."

                def next := c + count
                def vars := [for i in (c..!next) varSealer.seal(i)]
                return [makeCS(s, d, next)] + vars

            to walk(v):
                "
                Look up `v` in this logic context.

                If this method returns its argument unchanged, then it is
                either an unbound logic variable or not a logic variable at
                all.
                "

                return walkOn(s, v)

            to unify(u, v):
                return switch (unifyOn(s, u, v)) {
                    match ==null { logic.zero() }
                    match ==([].asMap()) { logic.pure(kanren) }
                    match subs {
                        def news := s | subs
                        def newd := [].diverge()
                        for constraint in (d) {
                            # NB: Each key in the constraint must be sealed in
                            # order to appear as varb.
                            def ks := [for k in (constraint.getKeys()) {
                                varSealer.seal(k)
                            }]
                            def vs := constraint.getValues()
                            switch (unifyOn(news, ks, vs)) {
                                match ==null { null }
                                match ==([].asMap()) { return logic.zero() }
                                match cons { newd.push(cons) }
                            }
                        }
                        logic.pure(makeCS(news, newd.snapshot(), c))
                    }
                }

            to disunify(u, v):
                return switch (unifyOn(s, u, v)) {
                    match ==null { logic.pure(kanren) }
                    match ==([].asMap()) { logic.zero() }
                    match subs {
                        logic.pure(makeCS(s, d.with(subs), c))
                    }
                }

            to cond(fs :List):
                var rv := logic.zero()
                for f in (fs):
                    rv := logic.plus(rv, f(kanren))
                return rv

            to all(fs :List):
                var rv := logic.pure(kanren)
                for f in (fs):
                    rv := logic."bind"(rv, f)
                return rv

    return makeCS([].asMap(), [], 0)

object unify as DeepFrozen:
    to run(lhs, rhs):
        return def unifying(k):
            return k.unify(lhs, rhs)

    to dis(lhs, rhs):
        return def disunifying(k):
            return k.disunify(lhs, rhs)

object cond as DeepFrozen:
    match [=="run", fs, _]:
        def conde(k):
            return k.cond(fs)
