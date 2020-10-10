exports (composeLens, get, modify, set, makeLens, strChars, charInt,
         intNegated, listAt)

# We all knew it was going to come to this eventually.

def id(x) as DeepFrozen:
    return x

# A lens is a DF object which witnesses isomorphism-like transformations
# between some entire system and some part of that system. Traditionally, a
# lens is a zoom between a data structure and a single inner element.

# The theory of mirrored lenses
# http://comonad.com/reader/2012/mirrored-lenses/ requires endofunctors. We
# have a choice of whether or not to curry and whether or not to require DF;
# we'll start by curring and not requiring DF. (And change this later and
# explain why we changed it!)

def identityFunctor(f) as DeepFrozen:
    return f

def listFunctor(f) as DeepFrozen:
    return fn xs :List { [for x in (xs) f(x)] }

def nullFunctor(f) as DeepFrozen:
    return fn x { if (x != null) { f(x) } }

def constFunctor(_f) as DeepFrozen:
    return id

# A lens becomes a getter under the constant functor; the functor's constant
# is the value being gotten.

def get(l) as DeepFrozen:
    return l(constFunctor)(id)

# Similarly, a lens becomes a setter under the identity functor.

def modify(l, f) as DeepFrozen:
    return l(identityFunctor)(f)

def set(l, x) as DeepFrozen:
    return modify(l, fn _ { x })

# Lens construction from isomorphisms and getter/setter actions.

object makeLens as DeepFrozen:
    to fromIsomorphism(kata :DeepFrozen, ana :DeepFrozen):
        "
        A lens from isomorphism `kata` and inverse `ana`.

        Technically, an entire family of types may be related rather than just
        monomorphically requiring that `ana` and `kata` are perfect inverses.
        Use this functionality with caution.
        "

        return def iso(fmap) as DeepFrozen:
            return fn f { fn x { fmap(ana)(f(kata(x))) } }

    to fromAdjustment(getting :DeepFrozen, setting :DeepFrozen):
        "
        A lens from getter `getting` and setter `setting`.

        The getter should be a function from whole objects to parts of
        objects, as in classical lenses, but the setter should be a curried
        function from both the whole and the part to the new whole.
        "

        return def adjust(fmap) as DeepFrozen:
            return fn f { fn x { fmap(setting(x))(f(getting(x))) } }

# Van Laarhoven lenses take a functor and an inner traversal in that functor,
# and return an outer traversal in that same functor. For any given functor,
# they give a category.

def identityLens :DeepFrozen := makeLens.fromIsomorphism(id, id)

def composeLens(lenses :List[DeepFrozen]) :DeepFrozen as DeepFrozen:
    "Compose a list of lenses, left-to-right, into a single lens."
    return def composedLens(fmap) as DeepFrozen:
        def ls :List := [for l in (lenses) l(fmap)].reverse()
        return fn f {
            var rv := f
            for l in (ls) { rv := l(rv) }
            rv
        }

# Example: A Str is like a list of Chars, and a Char is like an Int.

def listAt(index :(Int >= 0)) as DeepFrozen:
    def listGet(l :List) as DeepFrozen:
        return l[index]
    def listSet(l :List) as DeepFrozen:
        return fn x { l.with(index, x) }
    return makeLens.fromAdjustment(listGet, listSet)

def strChars :DeepFrozen := makeLens.fromIsomorphism(_makeList.fromIterable,
                                                     _makeStr.fromChars)

def charIntKata(c :Char) :Int as DeepFrozen:
    return c.asInteger()
def charIntAna(i :(Int >= 0)) :Char as DeepFrozen:
    return '\x00' + i
def charInt :DeepFrozen := makeLens.fromIsomorphism(charIntKata, charIntAna)

def negate(i :Int) :Int as DeepFrozen:
    return -i
def intNegated :DeepFrozen := makeLens.fromIsomorphism(negate, negate)
