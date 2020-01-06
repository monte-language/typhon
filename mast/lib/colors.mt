exports (makeColor, pd, composite)

# http://graphics.pixar.com/library/Compositing/paper.pdf
# https://www.cairographics.org/operators/

def Chan :DeepFrozen := (0.0..1.0)

# These ought to be inverses.

def sRGB2linear(u :Double) :Double as DeepFrozen:
    return if (u <= 0.0031308) { u * 323 / 25 } else {
        (211 * (u ** (5 / 12)) - 11) / 200
    }

def linear2sRGB(u :Double) :Double as DeepFrozen:
    return if (u <= 0.04045) { u * 25 / 323 } else {
        ((u * 200 + 11) / 211) ** (12 / 5)
    }

def _makeColor(r :Chan, g :Chan, b :Chan, a :Chan) :DeepFrozen as DeepFrozen:
    # No public docstring; this ought never to be directly exported.
    # All input channels must be premultiplied and clamped.

    return object color as DeepFrozen:
        "
        A sample from four-dimensional color space.

        Specifically, this color is stored in linear sRGB color space. Color
        channels are premultiplied with the alpha channel.
        "

        to alpha():
            return a

        to sRGB():
            return [linear2sRGB(r), linear2sRGB(g), linear2sRGB(b), a]

        to RGB():
            return [r, g, b, a]

        # Names and descriptions of these operators are from Porter-Duff.

        to darken(phi :Double):
            "
            Darken this color.

            When `phi` is between 0 and 1, this color is darkened to
            blackness. When `phi` is greater than 1, this color is brightened.
            "
            return _makeColor(r * phi, g * phi, b * phi, a)

        to dissolve(delta :Chan):
            "
            Dissolve this color.

            As `delta` decreases from 1 to 0, this color evanesces to
            clearness.
            "
            return _makeColor(r * delta, g * delta, b * delta, a * delta)

        to opaque(omega :Chan):
            "
            Opacify this color.

            As `omega` decreases from 1 to 0, this color becomes less
            indicative of a solid surface and more indicative of translucency.
            In the limit, zero `omega` indicates a colored light source.
            "
            return _makeColor(r, g, b, a * omega)

def black :DeepFrozen := _makeColor(0.0, 0.0, 0.0, 1.0)
def clear :DeepFrozen := _makeColor(0.0, 0.0, 0.0, 0.0)

object makeColor as DeepFrozen:
    "
    A sample of some optical phenomenon.

    Colors are points drawn from a color space. Due to the design of the human
    eye, we traditionally imagine color spaces as three-dimensional, with one
    dimension per type of cone cell. We add an additional alpha dimension to
    facilitate Porter-Duff compositing algebra.

    Our color model is fundamentally additive and oriented towards
    computer-driven luminescent displays.
    "

    to black():
        "The darkest representable color."

        return black

    to clear():
        "The most transparent representable color."

        return clear

    to sRGB(red :Double, green :Double, blue :Double, alpha :Double):
        "
        An sRGB color sample.

        Colors will be multiplied by `alpha`.
        "

        return _makeColor(sRGB2linear(red) * alpha,
                          sRGB2linear(green) * alpha,
                          sRGB2linear(blue) * alpha, alpha)

    to RGB(red :Double, green :Double, blue :Double, alpha :Double):
        "
        A linear RGB color sample.

        Colors will be multiplied by `alpha`.
        "

        return _makeColor(red * alpha, green * alpha, blue * alpha, alpha)

def pd(src, dest, op) as DeepFrozen:
    "
    Perform a Porter-Duff composition operation `op` with operands `src` and
    `dest`. The operands and return value are drawables, even though the
    operation is only specified per-color.
    "

    return def PorterDuff.drawAt(x, y):
        return op(src.drawAt(x, y), dest.drawAt(x, y))

object composite as DeepFrozen:
    "
    A Porter-Duff compositor.

    This compositor is meant to be used curried with `pd`:
    > pd(src, dest, compositor.over)
    "

    # Names from Porter-Duff and also Cairo.

    # XXX do we want to even provide the trivial operations? They can be
    # achieved by much easier means, I think, than by creating bogus drawables
    # just for composition.

    # XXX codegen?

    to clear(_, _):
        return clear

    to source(s, _):
        return s

    to over(s, d):
        def [sr, sg, sb, sa] := s.RGB()
        def [dr, dg, db, da] := d.RGB()
        def ra := sa + da * (1 - sa)
        def rr := (sr + dr * (1 - sa))
        def rg := (sg + dg * (1 - sa))
        def rb := (sb + db * (1 - sa))
        return _makeColor(rr, rg, rb, ra)
