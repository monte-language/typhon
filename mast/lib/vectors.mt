exports (V)

# Generalized wrapping for vectorized/broadcasting operations.

# XXX Transparent. It's not hard, just do it.

object V as DeepFrozen:
    "
    A maker of lists, but with an interface focused on performing broadcasted
    and vectorized operations.

    'It's about sending a message.'
    "

    to un(specimen, ej):
        "
        If `specimen` is a vectorized list, unwrap and return its contents
        with a `List` interface. Otherwise, throw to `ej`.

        This method helps implement auto-vectorized behaviors.
        "

        def [==V, =="run", args, _] exit ej := specimen._uncall()
        return args

    to makeFold(zero :DeepFrozen, plus :DeepFrozen):
        "
        Make a reusable fold from a monoid.

        The resulting fold traverses vectors left-to-right.
        "

        return def vFold(via (V.un) xs) as DeepFrozen:
            var rv := zero
            for x in (xs):
                rv := plus(rv, x)
            return rv

    match [=="run", args :List[DeepFrozen], _]:
        def size :Int := args.size()
        object vectorizingListWrapper as DeepFrozen:
            "
            This list is for broadcasting and vectorizing.

            Messages sent to this list are duplicated and sent to every
            element of this list. Arguments are introspected to enable
            zipping. If an argument is a vectorized list, then it is
            length-checked and zipped; otherwise, it is treated as a scalar
            and broadcast.
            "

            to _makeIterator():
                return args._makeIterator()

            to _printOn(out):
                out.print("V(")
                args._printOn(out)
                out.print(")")

            to _uncall():
                return [V, "run", args, [].asMap()]

            # Vector operations. Only one single vector argument is currently
            # supported; this can be extended to allow others and to allow
            # mixtures, with effort.
            match [verb, [via (V.un) others], namedArgs]:
                if (others.size() != size):
                    throw("size mismatch")
                M.call(V, "run",
                       [for i => x in (args) M.call(x, verb, [others[i]], namedArgs)],
                       [].asMap())

            # Scalar operations.
            match message:
                M.call(V, "run",
                       [for x in (args) M.callWithMessage(x, message)],
                       [].asMap())
