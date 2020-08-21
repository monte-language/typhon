exports (makeMonad, sequence)

# Monad transformers ala mtl.

object identityMonad as DeepFrozen:
    "
    The do-nothing monad.

    This monad sequences applications and obeys the laws, but otherwise has no
    effects.
    "

    to pure(x):
        return x

    to control(verb :Str, ==1, ==1, block):
        return switch (verb):
            match =="map":
                def mapMonad.controlRun():
                    def [[x], lambda] := block()
                    return lambda(x, null)
            match =="do":
                def doMonad.controlRun():
                    def [[x], lambda] := block()
                    return lambda(x, null)

object listMonad as DeepFrozen:
    "
    The list monad.

    This monad is non-deterministic, strictly exploring every alternative.
    "

    to pure(x):
        return [x]

    to zero():
        return []

    to control(verb :Str, ==1, ==1, block):
        return switch (verb):
            match =="map":
                def mapMonad.controlRun():
                    def [[xs], lambda] := block()
                    return [for x in (xs) lambda(x, null)]
            match =="do":
                def doMonad.controlRun():
                    def [[xs], lambda] := block()
                    def rv := [].diverge()
                    for x in (xs) { rv.extend(lambda(x, null)) }
                    return rv.snapshot()

object makeMonad as DeepFrozen:
    "
    Stack monads to produce towers of effects.

    In general, stacks are inside-out. m`makeMonad.foo(makeMonad.bar(m))` will
    produce bars full of foos.
    "

    to identity():
        "A monad with no effects and no parameters."

        return identityMonad

    to list():
        "A strict non-determinism monad."

        return listMonad

    to error(m :DeepFrozen):
        "A mother of all monads which uses ejectors within a single turn."

        return object ejectorContinuationMonad as DeepFrozen:
            "
            A continuation monad. Also, an error-handling monad.

            This monad suspends and sequences all actions; it is a mother of
            all monads. When provided with an ejector, this monad's actions
            execute until a value is produced and the ejector is fired with
            the value.

            Actions use `throw.eject/2` to ensure that ejectors really are
            fired.

            This monad is a transformer and acts 'under' some other effects;
            however, this monad is a mother of all monads, and acts over its
            transformed effects.
            "

            to pure(x):
                return fn _ { m.pure(x) }

            to throw(problem):
                return fn ej { throw.eject(ej, problem) }

            to reset(f):
                return fn _ej { escape la { f(la) } }

            to callCC(f):
                "
                Call `f` with the current continuation. `f` may return a
                monadic action as normal, or it may invoke the continuation
                with the monadic action to be returned.

                The continuation will be reified as an ejector, so it may only
                be called once and is delimited to prevent misuse.
                "

                return escape ej { f(ej) }

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[f], lambda] := block()
                            return fn ej {
                                m (f(ej)) map x { lambda(x, ej) }
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[f], lambda] := block()
                            return fn ej {
                                m (f(ej)) do x { lambda(x, ej)(ej) }
                            }

            match [verb, args, namedArgs]:
                fn _ { M.call(m, verb, args, namedArgs) }

    to reader(m :DeepFrozen):
        "A monad which reads from an environment."

        return object readerMonad as DeepFrozen:
            "
            The reader monad.

            This monad parameterizes all computation with a runner-chosen
            variable. This parameter can be thought of as an environment, a
            configuration, an index, a source space, or a regime.

            This monad is a transformer and acts under some other effects.
            "

            to pure(x):
                return m.pure(fn _ { x })

            to zero():
                return m.zero()

            to ask():
                return m.pure(fn e { e })

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) map f {
                                fn e { lambda(f(e), null) }
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) map f {
                                fn e { lambda(f(e), null)(e) }
                            }

    to writer(m :DeepFrozen, w :DeepFrozen):
        "A monad which accumulates an annotation in monoid `w`."

        return object writer as DeepFrozen:
            "
            The writer monad.

            This monad adds an annotation from a monoid, and sums up the
            annotations as it joins computations.

            This monad is a transformer and acts under some other effects.
            "

            to pure(x):
                return m.pure([x, w.one()])

            to zero():
                return m.zero()

            to tell(x):
                return m.pure([null, x])

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) map [x, w1] {
                                [lambda(x, null), w1]
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) do [x, w1] {
                                m (lambda(x, null)) map [y, w2] {
                                    [y, w.multiply(w1, w2)]
                                }
                            }

    to state(m :DeepFrozen):
        "A monad which threads mutable state through monad `m`."

        return object state as DeepFrozen:
            "
            The state monad.

            This monad takes an additional state argument, and passes it from
            action to action, so that joined computations effectively mutate
            the state. Crucially, this illusion does not actually require that
            the state object itself be mutable; the state may be `DeepFrozen`.

            This monad is a transformer and acts under some other effects.
            "

            # NB: Since we are doing a relatively strict and uncurried version
            # of this monad, it doesn't particularly matter which order we put
            # our variables in. We have four choices; of those, two are
            # headaches, one is what Haskell does, and one is what we do here
            # in order to more closely match .writer/2.

            to pure(x):
                return fn s { m.pure([x, s]) }

            to zero():
                return fn _ { m.zero() }

            to get():
                return fn s { m.pure([s, s]) }

            to set(x):
                return fn s { m.pure([null, x]) }

            to modify(f):
                return fn s { m.pure([null, f(s)]) }

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[ma], lambda] := block()
                            return fn s1 {
                                m (ma(s1)) map [x, s2] { [lambda(x, null), s2] }
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[ma], lambda] := block()
                            return fn s1 {
                                m (ma(s1)) do [x, s2] { lambda(x, null)(s2) }
                            }
                    match =="modify":
                        def modifyMonad.controlRun():
                            def [[ma], lambda] := block()
                            return fn s1 {
                                m (ma(s1)) map [x, s2] { [x, lambda(s2, null)] }
                            }

    to rws(m :DeepFrozen, w :DeepFrozen):
        "
        A monad which combines reader, writer, and state effects on monad `m`
        and monoid `w` in a coherent fashion.
        "

        return object RWSMonad as DeepFrozen:
            "
            The reader+writer+state monad.

            This monad's actions take an additional two arguments, the
            environment and the state, and return fresh states and monoidal
            logs along with the result.

            This monad is a transformer and acts under some other effects.
            "

            to pure(x):
                return fn _e, s { m.pure([x, s, w.one()]) }

            to ask():
                return fn e, s { m.pure([e, s, w.one()]) }

            to tell(x):
                return fn _e, s { m.pure([null, s, x]) }

            to get():
                return fn _e, s { m.pure([s, s, w.one()]) }

            to set(x):
                return fn _e, s { m.pure([null, x, w.one()]) }

            to modify(f):
                return fn _e, s { m.pure([null, f(s), w.one()]) }

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[ma], lambda] := block()
                            return fn e, s1 {
                                m (ma(e, s1)) map [x, s2, l] {
                                    [lambda(x, null), s2, l]
                                }
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[ma], lambda] := block()
                            return fn e, s1 {
                                m (ma(e, s1)) do [x, s2, l1] {
                                    m (lambda(x, null)(e, s2)) map [y, s3, l2] {
                                        [y, s3, w.multiply(l1, l2)]
                                    }
                                }
                            }
                    match =="modify":
                        def modifyMonad.controlRun():
                            def [[ma], lambda] := block()
                            return fn e, s1 {
                                m (ma(e, s1)) map [x, s2, l] {
                                    [x, lambda(s2, null), l]
                                }
                            }

    to maybe(m :DeepFrozen):
        "A partial monad."

        object failure as DeepFrozen {}

        return object maybeMonad as DeepFrozen:
            "
            The maybe monad.

            This monad models partiality and failure with a sentinel value. To
            check against the sentinel value, use `.failure()`.

            This monad is a transformer and acts under some other effects.
            "

            to pure(x):
                return m.pure(x)

            to failure():
                return failure

            to zero():
                return m.pure(failure)

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) map x {
                                if (x == failure) { failure } else {
                                    lambda(x, null)
                                }
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) do x {
                                if (x == failure) { m.pure(failure) } else {
                                    lambda(x, null)
                                }
                            }

    to either(m :DeepFrozen):
        "A coproduct or sum monad."

        return object eitherMonad as DeepFrozen:
            "
            The either monad.

            This monad encodes a disjoint union. We call the carrier side the
            'right' side, and the exceptional side the 'left' side. Actions in
            the monad will be short-circuited by the left side's values, by
            default. These are historical conventions.

            To run this monad's actions, pass an object with both .left/1 and
            .right/1 methods.

            This monad is a transformer and acts under some other effects.
            "

            to pure(x):
                return m.pure(fn e { e.right(x) })

            to throw(error):
                return m.pure(fn e { e.left(error) })

            to control(verb :Str, ==1, ==1, block):
                return switch (verb):
                    match =="map":
                        def mapMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) map s {
                                s(object mapEither {
                                    to left(l) { return fn e { e.left(l) } }
                                    to right(r) {
                                        return fn e {
                                            e.right(lambda(r, null))
                                        }
                                    }
                                })
                            }
                    match =="do":
                        def doMonad.controlRun():
                            def [[ma], lambda] := block()
                            return m (ma) do s {
                                s(object doEither {
                                    to left(l) { return eitherMonad.throw(l) }
                                    to right(r) { return lambda(r, null) }
                                })
                            }

def sequence(m :DeepFrozen, actions :List) as DeepFrozen:
    "
    Run `actions` in sequence in monad `m` and return a single monadic action
    which accumulates all of the results.

    This function is, and must be, notoriously slow. It has quadratic time
    complexity in the length of `actions`.
    "

    return if (actions =~ [ma] + mas) {
        m (ma) do x { m (sequence(m, mas)) map xs { [x] + xs } }
    } else { m.pure([]) }
