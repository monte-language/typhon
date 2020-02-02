import "lib/asdl" =~ [=> asdlParser]
exports (parse, assemble, buildExpr, catMonte, computationGraph, ports)

# We'll need some conventions. We're doing the Cartesian closed category
# approach, so we'll see these combinators:
# Categories: id
# Products: pair(f,g) exl exr
# Terminus: unit
# Internal homs: apply curry uncurry
# NNO: zero succ pr(q,f)

# We also have .compose(f,g) for performing compositions. We require that
# .id() and .compose(f,g) be available on every category, and the rest is
# dynamically typed.

def specials :Set[Char] := "(), ".asSet()

def parseAt(s :Str, start :Int) as DeepFrozen:
    var position :Int := start
    def more() { return position < s.size() }
    def rv := [].diverge()
    while (more() && !specials.contains(s[position])):
        def top := position
        while (more() && !specials.contains(s[position])):
            position += 1
        def name := s.slice(top, position)
        if (more() && s[position] == '('):
            def args := [].diverge()
            position += 1
            while (s[position] != ')'):
                def [elt, pos] := parseAt(s, position)
                args.push(elt)
                position := pos
                if (s[position] == ','):
                    position += 1
            rv.push([name, args.snapshot()])
            position += 1
        else:
            rv.push(name)
        def shouldBreak := more() && s[position] != ' '
        if (shouldBreak):
            break
        else:
            position += 1
    return [rv.snapshot(), position]

def parse(s :Str) as DeepFrozen { return parseAt(s, 0)[0] }

def assemble(cat :DeepFrozen, path :List) as DeepFrozen:
    var rv := cat.id()
    for obj in (path):
        def f := switch (obj) {
            match [con, args] {
                M.call(cat, con, [for arg in (args) assemble(cat, arg)],
                       [].asMap())
            }
            match arr { M.call(cat, arr, [], [].asMap()) }
        }
        rv := cat.compose(rv, f)
    return rv

def buildExpr(cat :DeepFrozen, s :Str) as DeepFrozen:
    return assemble(cat, parse(s))

object catMonte as DeepFrozen:
    to id():
        return fn x { x }

    to compose(f, g):
        return fn x { g(f(x)) }

    to pair(left, right):
        return fn x { [left(x), right(x)] }

    to exl():
        return fn [l, _] { l }

    to exr():
        return fn [_, r] { r }

    to unit():
        return fn _ { [] }

    to apply():
        return fn [f, x] { f(x) }

    to curry(f):
        return fn x { fn y { f([x, y]) } }

    to uncurry(f):
        return fn [x, y] { f(x)(y) }

    to zero():
        return fn _ { 0 }

    to succ():
        return fn x { x + 1 }

    to pr(q, f):
        return fn x { var rv := q([]); for _ in (0..!x) { rv := f(rv) }; rv }

# Turn CCCs into SSA computational graphs.
# http://conal.net/papers/compiling-to-categories/compiling-to-categories.pdf
# p8

def ports :DeepFrozen := asdlParser(mpatt`ports`, `
    ports = UnitP
          | BoolP(int)
          | DoubleP(int)
          | IntP(int)
          | PairP(ports, ports)
          | FunP(df)
`, null)

object state as DeepFrozen:
    "The State monad."

    to pure(x :DeepFrozen):
        return def pureState(s) as DeepFrozen { return [x, s] }

    to fmap(f :DeepFrozen):
        return def fmapState(action :DeepFrozen) as DeepFrozen:
            return def mappedState(s1) as DeepFrozen:
                def [x, s2] := action(s1)
                return [f(x), s2]

    to join(action :DeepFrozen):
        return def joinState(s1) as DeepFrozen:
            def [act, s2] := action(s1)
            return act(s2)

    to ">>="(action :DeepFrozen, f :DeepFrozen):
        return def bindState(s1) as DeepFrozen:
            def [x, s2] := action(s1)
            return f(x)(s2)

    to liftA2(f :DeepFrozen, a1 :DeepFrozen, a2 :DeepFrozen):
        return def liftA2State(s1) as DeepFrozen:
            def [x, s2] := a1(s1)
            def [y, s3] := a2(s2)
            return [f(x, y), s3]

    to get():
        return def getState(s) as DeepFrozen:
            return [s, s]

    to put(x :DeepFrozen):
        return def putState(s) as DeepFrozen:
            return [null, x]

    to modify(f :DeepFrozen):
        return def modifyState(s) as DeepFrozen:
            return [null, f(s)]

def const(x :DeepFrozen) as DeepFrozen:
    return def constantly(_) as DeepFrozen { return x }

def genPorts(arity :Int) as DeepFrozen:
    return state.">>="(state.get(), def g1([o :Int, comps]) as DeepFrozen {
        return state.">>="(state.put([o + arity, comps]),
                           const(state.pure(o)))
    })

def makeCompGraph(compName :Str, arity :Int, f :DeepFrozen) as DeepFrozen:
    return def compGraph(ps :DeepFrozen) as DeepFrozen:
        return state.">>="(genPorts(arity), def compPort(p :DeepFrozen) as DeepFrozen {
            def new :DeepFrozen := M.call(f, "run",
                                          _makeList.fromIterable(p..!(p + arity)),
                                          [].asMap())
            def append([o, comps]) as DeepFrozen {
                return [o, comps.with([compName, ps, new])]
            }
            return state.">>="(state.modify(append), const(state.pure(new)))
        })

object computationGraph as DeepFrozen:
    "A basic SSA computation graph."

    to id():
        return def idGraph(ps) as DeepFrozen { return state.pure(ps) }

    to compose(f :DeepFrozen, g :DeepFrozen):
        return def composedGraph(ps) as DeepFrozen {
            # Kleisli composition.
            return state.join(state.fmap(g)(f(ps)))
        }

    to unit():
        return def unitGraph(ps) as DeepFrozen:
            return state.pure(ports.UnitP())

    to pair(left :DeepFrozen, right :DeepFrozen):
        return def pairGraph(ps) as DeepFrozen:
            return state.liftA2(ports.PairP, left(ps), right(ps))

    to exl():
        return def leftGraph(ps) as DeepFrozen:
            return ps.walk(def walker.PairP(l, _) { return state.pure(l) })

    to exr():
        return def rightGraph(ps) as DeepFrozen:
            return ps.walk(def walker.PairP(_, r) { return state.pure(r) })

    to apply():
        return def applyGraph(ps) as DeepFrozen:
            return ps.walk(def walker.PairP(fun, x) {
                return fun.walk(def funp.FunP(g) { return g(x) })
            })

    to curry(f :DeepFrozen):
        return def curryGraph(ps1 :DeepFrozen) as DeepFrozen:
            return state.pure(ports.FunP(def curriedGraph(ps2) as DeepFrozen {
                return f(ports.PairP(ps1, ps2))
            }))

    to uncurry(g :DeepFrozen):
        return def uncurryGraph(ps :DeepFrozen) as DeepFrozen:
            return ps.walk(def walker.PairP(l, r :DeepFrozen) {
                return state.">>="(g(l), def uncurried(graph) as DeepFrozen {
                    return graph.walk(def funp.FunP(f) { return f(r) })
                })
            })

    to zero():
        return makeCompGraph("0", 1, ports.IntP)

    to succ():
        return makeCompGraph("+1", 1, ports.IntP)

    to pr(q :DeepFrozen, f :DeepFrozen):
        def prep := computationGraph.pair(computationGraph.unit(),
                                          computationGraph.id())
        def qf := computationGraph.compose(prep, computationGraph.pair(q, f))
        def rec := makeCompGraph("ℕ", 1, ports.IntP)
        return computationGraph.compose(qf, rec)

    # And extra operations.

    to mulC():
        return makeCompGraph("×", 1, ports.IntP)

    to addC():
        return makeCompGraph("+", 1, ports.IntP)
