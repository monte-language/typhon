exports (logic, makeKanren, Katren)

# A simple logic monad.
# Loosely based on http://homes.sice.indiana.edu/ccshan/logicprog/LogicT-icfp2005.pdf

def zero(ej) as DeepFrozen:
    throw.eject(ej, null)

def isZero(action) :Bool as DeepFrozen:
    return _equalizer.sameYet(action, zero) == true

object logic as DeepFrozen:
    "
    A continuation monad for logic puzzles.

    This monad non-deterministically explores many possibilies, and uses
    logical operators to add and remove those possibilities from
    consideration.

    To run this monad's actions, call .run/1 with an ejector. The ejector will
    eventually be fired, with the escaping value either a pair of a value and
    a new action, or `null` for no more results.
    "

    to zero():
        "Never succeed."

        return zero

    to pure(value):
        "Succeed in just one case."

        return fn ej { throw.eject(ej, [value, zero]) }

    to plus(left, right):
        "Succeed if `left` or `right` succeed."

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

    to map(action, f):
        # Remove zeroes from the tree.
        return if (isZero(action)) { zero } else {
            fn ej {
                escape la { action(la) } catch p {
                    if (p =~ [x, next]) {
                        logic.plus(logic.pure(f(x)), logic.map(next, f))(ej)
                    } else { throw.eject(ej, null) }
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

    to control(verb :Str, ==1, ==1, block):
        return switch (verb):
            match =="map":
                def mapMonad.controlRun():
                    def [[action], lambda] := block()
                    return logic.map(action, fn x { lambda(x, null) })
            match =="do":
                def doMonad.controlRun():
                    def [[action], lambda] := block()
                    return logic."bind"(action, fn x { lambda(x, null) })
            match =="then":
                def thenMonad.control(=="else", ==0, ==0, block2):
                    return def elseMonad.controlRun():
                        def [[test], cons] := block()
                        def [[], alt] := block2()
                        return logic.ifte(test, fn x { cons(x, null) }, alt())

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

# https://arxiv.org/pdf/1706.00526.pdf

object Katren as DeepFrozen:
    "
    A category of logic variables, ala miniKanren.

    Arrows in this category take a pair of a Kanren context and a logic
    variable, and return a logical action yielding many pairs of contexts and
    variables. Run an arrow with an empty context and a fresh variable, and
    get a logical action for zero or more contexts and variables.
    "

    to id():
        return fn k, u { logic.pure([k, u]) }

    to compose(f, g):
        return fn k1, u {
            logic (f(k1, u)) do [k2, v] { g(k2, v) }
        }

    # Daggering.

    to dagger(f):
        return fn k1, u {
            def [k2, v, fu] := k1.fresh(2)
            logic (f(k2, fu)) do [k3, fv] {
                logic (k3.unify([u, v], [fv, fu])) map k4 { [k4, v] }
            }
        }

    # Products. Note that we are using prod(), not pair()!

    to exl():
        return fn k1, u {
            def [k2, l, r] := k1.fresh(2)
            logic (k2.unify(u, [l, r])) map k3 { [k3, l] }
        }

    to exr():
        return fn k1, u {
            def [k2, l, r] := k1.fresh(2)
            logic (k2.unify(u, [l, r])) map k3 { [k3, r] }
        }

    to prod(f, g):
        return fn k1, u {
            def [k2, inl, inr, outl, outr, v] := k1.fresh(5)
            logic (k2.unify([u, v], [[inl, inr], [outl, outr]])) do k3 {
                logic (f(k3, inl)) do [k4, outf] {
                    # We have a choice here: Do we unify f's output with our
                    # return value first, or do we run g? This amounts to
                    # short-circuiting g, if we so choose. ~ C.
                    logic (g(k4, inr)) do [k5, outg] {
                        logic (k5.unify([outf, outg], [outl, outr])) map k6 {
                            [k6, v]
                        }
                    }
                }
            }
        }

    to braid():
        return fn k1, u {
            def [k2, v, l, r] := k1.fresh(3)
            logic (k2.unify([u, v], [[l, r], [r, l]])) map k3 { [k3, v] }
        }

    # Cartesian copying.

    to copy():
        return fn k1, u {
            def [k2, v] := k1.fresh(1)
            logic (k2.unify([u, u], v)) map k3 { [k3, v] }
        }

    to delete():
        return fn k, _ {
            # Cheat: We use null to carry the I type, and unification always
            # succeeds (because any input will be related to the lone possible
            # output), so we effectively can kill the input.
            logic.pure([k, null])
        }

    to merge():
        return fn k1, u {
            def [k2, v] := k1.fresh(1)
            logic (k2.unify(u, [v, v])) map k3 { [k3, v] }
        }

    to create():
        return fn k1, u {
            # Note that, unlike in delete(), we have to pre-kill the input
            # value. This will be required later. One might think of delete()
            # as reaping logic values which are being allocated here.
            def [k2, v] := k1.fresh(1)
            logic (k2.unify(u, null)) map k3 { [k3, v] }
        }

    # Compact closure.

    to unit():
        return fn k1, u {
            # As with create(), pre-kill.
            def [k2, v, pipe] := k1.fresh(2)
            logic (k2.unify([u, v], [null, [pipe, pipe]])) map k3 {
                [k3, v]
            }
        }

    to counit():
        return fn k1, u {
            # As with delete(), cheat.
            def [k2, pipe] := k1.fresh(1)
            logic (k2.unify(u, [pipe, pipe])) map k3 { [k3, null] }
        }

    # Logical operations.

    to and(f, g):
        # This one is easier to compose than to open-code.
        return Katren.compose(Katren.copy(),
                              Katren.compose(Katren.prod(f, g),
                                             Katren.merge()))

    to "true"():
        return fn k, _ { logic.pure(k.fresh(1)) }

    # NNO.

    to zero():
        return fn k1, u {
            logic (k1.unify(u, null)) map k2 { [k2, 0] }
        }

    to succ():
        return fn k1, u {
            # This is basically a custom constraint. We're going to examine u
            # and see whether it is already bound; if so, then we cheat, but
            # if not, then we iterate.
            if (k1.walk(u) =~ i :Int) { logic.pure([k1, i + 1]) } else {
                def [k2, v] := k1.fresh(1)
                def go(k, x) {
                    def isZero := logic (k.unify([u, v], [x, x + 1])) map k3 {
                        [k3, v]
                    }
                    def notZero := logic (k.disunify(u, x)) do k3 {
                        go(k3, x + 1)
                    }
                    return logic.plus(isZero, notZero)
                }
                go(k2, 0)
            }
        }

    to pr(q, f):
        return def go(k1, u):
            # Either it's zero, or it's not.
            def isZero := logic (k1.unify(u, 0)) do k2 { q(k2, null) }
            def notZero := logic (k1.disunify(u, 0)) do k2 {
                # So it's at least one? Unsucc and recurse.
                Katren.compose(Katren.dagger(Katren.succ()), Katren.compose(go, f))(k2, u)
            }
            return logic.plus(isZero, notZero)
