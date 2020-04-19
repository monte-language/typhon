exports (V, glsl)

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

        # XXX should be ==V, but diamond dependencies will cause vectors from
        # one import to be unusable in another import.
        def [_, =="run", args, _] exit ej := specimen._uncall()
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

# Monoids needed for GLSL.
def sumPlus(x, y) as DeepFrozen { return x + y }
def sumDouble :DeepFrozen := V.makeFold(0.0, sumPlus)

object glsl as DeepFrozen:
    "
    An implementation of vectorized routines suitable for graphics work.

    As the names suggest, this object is designed to be familiar to speakers
    of GLSL, the language used by Mesa3D for shaders.
    "

    # When I link to Khronos, I am emphasizing that our routine is directly
    # derived from their mathematical specification. We use recipes which are
    # compatible with them in all cases, so the link does not indicate just
    # that we are compatible, but that we used their specification to write
    # our code.

    # Lacking any preference, keep these alphabetical, but do sort by
    # complexity and inclusion, so that simpler methods come earlier and
    # methods which reference others come later.

    # https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/mod.xhtml
    to mod(x, y):
        "`x % y`, but for vectors of doubles."
        return x - y * (x / y).floor()

    to dot(u, v) :Double:
        "The dot product of `u` and `v`."
        return sumDouble(u * v)

    to length(u) :Double:
        "The distance of `u` from the origin."
        return sumDouble(u ** 2).squareRoot()

    to normalize(u):
        "The unit vector pointing in the same direction as `u`."
        return u * glsl.length(u).reciprocal()

    # https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/distance.xhtml
    to distance(p0, p1) :Double:
        "The length of the vector from `p0` to `p1`."
        return glsl.length(p0 - p1)

    # https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/cross.xhtml
    to cross(x, y):
        "The cross product of `x` and `y`."

        def [x0, x1, x2] := V.un(x, null)
        def [y0, y1, y2] := V.un(y, null)
        return V(
            x1 * y2 - y1 * x2,
            x2 * y0 - y2 * x0,
            x0 * y1 - y0 * x1,
        )

    # https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/mix.xhtml
    to mix(x, y, a :Double):
        "
        Linearly interpolate between `x` and `y` with weight `a`.

        When `a` is 0.0, returns `x`; when `a` is 1.0, returns `y`. For fun,
        does not check whether `a :(0.0..1.0)`.
        "

        return x * (1.0 - a) + y * a

    # https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/reflect.xhtml
    to reflect(I, N):
        "Reflect `I` across normal `N`."
        return I - N * (2.0 * glsl.dot(I, N))


    # https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/refract.xhtml
    to refract(I, N, eta :Double):
        "
        Refract `I` at normal `N` with ratio of indices of refraction `eta`.

        Unlike GLSL, return `null`, rather than the zero vector, if the angle
        of incidence would lead to reflection rather than refraction.
        "

        def cosi := glsl.dot(N, I)
        def k := 1.0 - eta * eta * (1.0 - cosi * cosi)
        # NB: Because we check that k ≥ 0, √k should be safe.
        return if (k.atLeastZero()) {
            I * eta + N * (eta * cosi + k.squareRoot())
        }
