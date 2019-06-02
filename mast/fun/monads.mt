import "lib/asdl" =~ [=> asdlParser]
exports (freeMonad, rewrite, id, list, maybe, pprint, parse)

# Yet another attempt at encoding monads.
# This starts with the free monad, in a relatively efficient Church final
# encoding [0], then proceeds to build arbitrary effects on top. We use two
# insights of Oleg [1]: That we may encode an effect not as a full functor,
# but as a recursively-defined tower of effects on the free monad; and also
# that we do not need to build full fmaps, but instead can partially apply
# them.
#
# [0] https://hackage.haskell.org/package/free-5.1.1/docs/Control-Monad-Free-Church.html
# [1] http://okmij.org/ftp/Haskell/extensible/more.pdf

interface Free :DeepFrozen:
    to run(kpure, keffect):
        "
        Evaluate.

        If this value is pure, then `kpure.run/1` will be called with the pure
        value; otherwise, `keffect.run/1` will be called with an effectful
        value.
        "

object freeMonad as DeepFrozen:
    "
    The free monad on effects.

    This object's return values are free actions. They contain pure values,
    effects, and applications of transformations.
    "

    to pure(a):
        "Just `a`, with no effects."
        return def purely(kpure, _keffect) as Free:
            return kpure(a)

    to effect(fa):
        "
        A functorial effect, parameterized over some unknown value.

        `fa.run/1` should take a single-argument function and run that
        function on every value within the effect, producing a new effect.
        "
        return def effectful(kpure, keffect) as Free:
            return keffect(fa(kpure))

    to ">>="(ma :Free, handler):
        "
        Bind `ma`, an action from the free monad, onto `handler`.

        `handler.run/1` should take a pure value and return a new action from
        the free monad.
        "
        return def bound(kpure, keffect) as Free:
            return ma(fn x { handler(x)(kpure, keffect) }, keffect)

object rewrite as DeepFrozen:
    to pure(f):
        "Apply `f` to every leaf of a free action."
        return def rewrite(action):
            return def rewriting(kpure, keffect) as Free:
                return action(fn a { kpure(f(a)) }, keffect)

    to effectContra(nt):
        "
        Apply `nt`, a natural transformation, *backwards* to every effect of
        a free action.

        If `nt` explains abstract effects in more concrete terms, then the
        rewritten action's effects will become abstracted.
        "
        return def rewrite(action):
            return def rewriting(kpure, keffect) as Free:
                return action(kpure, fn fr { keffect(nt(fr)) })

def sequence(actions :List[Free]) :Free as DeepFrozen:
    return if (actions =~ [action] + rest) {
        freeMonad.">>="(action, fn x {
            freeMonad.">>="(sequence(rest), fn xs {
                freeMonad.pure([x] + xs)
            })
        })
    } else { freeMonad.pure([]) }

def id(x) as DeepFrozen:
    return fn trans { trans(x) }

def list(xs) as DeepFrozen:
    return fn trans { [for x in (xs) trans(x)] }

def set(xs) as DeepFrozen:
    return fn trans { [for x in (xs) trans(x)].asSet() }

def maybe(x) as DeepFrozen:
    return if (x == null) { fn _ { null } } else { fn trans { trans(x) } }

def bfFull :DeepFrozen := asdlParser(mpatt`bfFull`, `
    inst = Inc | Dec | Advance | Previous | Output | Input | Begin | End
           attributes (any n)
    done = Done
`, null)

def chars :Map[Char, Str] := [
    '+' => "Inc",
    '-' => "Dec",
    '>' => "Advance",
    '<' => "Previous",
    '.' => "Output",
    ',' => "Input",
    '[' => "Begin",
    ']' => "End",
]

def const(x) as DeepFrozen:
    return fn _ { x }

def parse(s :Str) as DeepFrozen:
    var rv := freeMonad.pure(bfFull.Done())
    for c in (s.asList().reverse()):
        def via (chars.fetch) verb exit __continue := c
        def next := rv
        def applyInst(trans):
            return M.call(bfFull, verb, [trans(next)], [].asMap())
        rv := freeMonad.effect(applyInst)
    return rv

def bfRLE :DeepFrozen := asdlParser(mpatt`bfRLE`, `
    inst = Inc(int i) | Dec(int i) | Advance(int i) | Previous(int i)
         | Output | Input | Begin | End
           attributes (any n)
    done = Done
`, null)

def rleInsts :List[Str] := ["Inc", "Dec", "Advance", "Previous"]

def rle(action) as DeepFrozen:
    return action(freeMonad.pure, fn fa {
        freeMonad.effect(fa.walk(object rlencoder {
            to Done() { return fn _ { bfRLE.Done() } }
            match [verb, [n], _] {
                def applyRLE(trans) {
                    def transArgs := if (rleInsts.contains(verb)) {
                        [1, trans(n)]
                    } else { [trans(n)] }
                    return M.call(bfRLE, verb, transArgs, [].asMap())
                }
            }
        })
    )})

def pprint(action) as DeepFrozen:
    return action(M.toString, fn fs { `effect($fs)` })

def simple :Str := "++++++++++[>++++++++++<<-]>+++++++.>."

def action := rle(parse(simple))
traceln(action)
traceln(pprint(action))
