exports (makeMonad)

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
