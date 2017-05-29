import "lib/enum" =~ [=> makeEnum :DeepFrozen]
exports (main)

object identity as DeepFrozen:
    "The identity monad."

    to unit(x):
        return x

    to "bind"(action, f):
        return f(action)

def stateT(m :DeepFrozen) as DeepFrozen:
    "The state monad transformer."

    return object state as DeepFrozen:
        to _printOn(out):
            out.print(`<state($m)>`)

        to unit(x):
            return def unit(s) { return m.unit([x, s]) }

        to "bind"(action, f):
            return def ::"bind"(s) {
                return m."bind"(action(s), fn [a, s2] { f(a)(s2) })
            }

        to get():
            return def get(s) {
                return m.unit([s, s])
            }

        to put(x):
            return def put(_) {
                return m.unit([null, x])
            }

        to zero():
            return def zero(_) { return m.zero() }

        to alt(left, right):
            return def alt(s) { return m.alt(left(s), right(s)) }

def ambT(m :DeepFrozen) as DeepFrozen:
    "
    The non-determinism monad transformer.

    This implementation uses `Set` to model non-determinism.
    "

    return object amb as DeepFrozen:
        to _printOn(out):
            out.print(`<amb($m)>`)

        to unit(x):
            return m.unit([x].asSet())

        to "bind"(action, f):
            return m."bind"(action, fn xs {
                var rv := m.unit([].asSet())
                for x in (xs) { rv := amb.alt(rv, f(x)) }
                rv
            })

        to get():
            return m."bind"(m.get(), amb.unit)

        to put(x):
            return m."bind"(m.put(x), amb.unit)

        to zero():
            return m.unit([].asSet())

        to alt(left, right):
            return m."bind"(left, fn l {
                m."bind"(right, fn r { m.unit(l | r) })
            })

def flowT(m :DeepFrozen) as DeepFrozen:
    "Flow-sensitive non-determinism monad."

    return object flow as DeepFrozen:
        to _printOn(out):
            out.print(`<flow($m)>`)

        to unit(x):
            return fn s { m.unit([x => s]) }

        to "bind"(action, f):
            return fn s {
                m."bind"(action(s), fn xs {
                    var rv := m.unit([].asMap())
                    def actions := [for k => v in (xs) f(k)(v)]
                    for a in (actions) {
                        rv := m."bind"(rv, fn l {
                            m."bind"(a, fn r { m.unit(l | r) })
                        })
                    }
                    rv
                })
            }

        to get():
            return fn s { m.unit([s => s]) }

        to put(x):
            return fn _ { m.unit([null => x]) }

        to zero():
            return fn s { m.unit([].asMap()) }

        to alt(left, right):
            return fn s {
                m."bind"(left(s), fn l {
                    m."bind"(right(s), fn r { m.unit(l | r) })
                })
            }

# C is for Control.
def [Inst :DeepFrozen,
    instLiteral :DeepFrozen, instDrop :DeepFrozen,
    instNoun :DeepFrozen,
    instDup :DeepFrozen, instAssign :DeepFrozen,
] := makeEnum([
    "literal", "drop",
    "noun",
    "dup", "assign",
])

# K is for Kontinuation.
def [Kont :DeepFrozen,
    kontDone :DeepFrozen,
] := makeEnum([
    "done",
])

def compileToInst(topExpr) as DeepFrozen:
    def frameStack := [[].asMap().diverge()].diverge()
    def literalStack := [[].asMap().diverge()].diverge()
    def instStack := [[].diverge()].diverge()

    def popFrame():
        return [frameStack.pop().size(),
                literalStack.pop().getKeys(),
                instStack.pop().snapshot()]

    def writeInst(inst :Inst, i :Int):
        instStack.last().push([inst, i])

    object compiler:
        to literal(value):
            def lits := literalStack.last()
            def index := lits.fetch(value, fn { lits[value] := lits.size() })
            writeInst(instLiteral, index)

        to drop():
            writeInst(instDrop, 0)

        to noun(name :Str):
            def frame := frameStack.last()
            def index := frame[name]
            writeInst(instNoun, index)

        to dup():
            writeInst(instDup, 0)

        to assign(name :Str):
            def frame := frameStack.last()
            def index := frame[name] := frame.size()
            writeInst(instAssign, index)

        to matchBind(patt):
            switch (patt.getNodeName()):
                match =="FinalPattern":
                    compiler.drop()
                    compiler.assign(patt.getNoun().getName())

        to run(expr):
            if (expr == null):
                compiler.literal(null)
                return

            switch (expr.getNodeName()):
                # Layer 0: Sequencing.
                match =="LiteralExpr":
                    compiler.literal(expr.getValue())
                match =="SeqExpr":
                    def [head] + tail := expr.getExprs()
                    compiler(head)
                    for t in (tail):
                        compiler.drop()
                        compiler(t)
                # Layer 1: Read-only store.
                match =="NounExpr":
                    compiler.noun(expr.getName())
                match =="BindingExpr":
                    compiler.binding(expr.getNoun().getName())
                # Layer 2: Read-write store.
                match =="DefExpr":
                    compiler(expr.getExpr())
                    compiler.dup()
                    compiler(expr.getExit())
                    compiler.matchBind(expr.getPattern())

    compiler(topExpr)
    return popFrame()

def modify(m, action) as DeepFrozen:
    return m."bind"(m.get(), fn state { m.put(action(state)) })

def modifyEnv(m, action) as DeepFrozen:
    return modify(m, fn state { state.modifyEnv(action) })

def tick(m, _expr) as DeepFrozen:
    return m."bind"(m.get(), fn state {
        def [[env, kaddr, kstore, time], store] := state  
        # def newTime := [expr, kaddr, time]
        def newTime := time + 1
        m.put([[env, kaddr, kstore, newTime], store])
    })

def getNoun(m, name) as DeepFrozen:
    return m."bind"(m.get(), fn state {
        def [[env, _, _, _], store] := state
        m.unit(store[env[name]])
    })

def putNoun(m, name, value) as DeepFrozen:
    return m."bind"(m.get(), fn state {
        def [[env, kaddr, kstore, time], store] := state  
        def k := [name, time]
        def newEnv := env | [name => k]
        def newStore := store | [k => value]
        m.put([[newEnv, kaddr, kstore, time], newStore])
    })

def C :DeepFrozen := List[Pair[Inst, Int]]

def makeCESKState(c :C, e, s, k :Kont) as DeepFrozen:
    # E is [stack, frame]

    return object CESKState:
        to c() :C:
            return c

        to e():
            return e

        to peek():
            return e[0].last()

        to modifyEnv(action):
            return makeCESKState(c, action(e), s, k)

        to s():
            return s

        to k() :Kont:
            return k

        to isFinal() :Bool:
            "Whether this state is a final, non-steppable state."

            return !c.isEmpty() && k == kontDone

def stepConcrete(m, literals) as DeepFrozen:
    def push(value):
        return modifyEnv(m, fn [stack, frame] {
            [stack.with(value), frame]
        })

    return m."bind"(m.get(), fn state {
        switch (state.c()) {
            match [] {
                # No more instructions, so we need to perform a return.
                switch (state.c()) {
                    match ==kontDone { throw(state.peek()) }
                }
            }
            match [[inst, index]] + insts {
                # def prelude := tick(m, null)
                def prelude := m.unit(null)
                def body := switch (inst) {
                    # Layer 0: Sequencing.
                    match ==instLiteral { push(literals[index]) }
                    match ==instDrop {
                        modifyEnv(m, fn [stack, frame] {
                            [stack.slice(0, stack.size() - 1), frame]
                        })
                    }
                    # Layer 1: Read-only store.
                    match ==instNoun {
                        modifyEnv(m, fn [stack, frame] {
                            [stack.with(frame[index]), frame]
                        })
                    }
                    # Layer 2: Read-write store.
                    match ==instDup {
                        modifyEnv(m, fn [stack, frame] {
                            traceln(`dup $stack`)
                            [stack.with(stack.last()), frame]
                        })
                    }
                    match ==instAssign {
                        modifyEnv(m, fn [stack, frame] {
                            traceln(`assign $stack`)
                            [stack.slice(0, stack.size() - 1),
                             frame.with(index, stack.last())]
                        })
                    }
                }
                def footer := modify(m, fn state {
                    makeCESKState(insts, state.e(), state.s(), state.k())
                })
                m."bind"(prelude, fn _ {
                    m."bind"(body, fn result {
                        m."bind"(footer, fn _ { m.unit(result) })
                    })
                })
            }
        }
    })

def main(_argv) as DeepFrozen:
    def f(m):
        traceln(`Running interpreter on monad $m`)
        def ast := m`def x := 5; def y := 2; 42; x; y`
        def [_, literals, insts] := compileToInst(ast)
        # [stack, frame]
        def env := [[], []]
        # [env, kaddr, kstore, time]
        def psi := [env, null, [null => kontDone], 0]
        # [psi, store]
        var state := makeCESKState(insts, env, psi, kontDone)
        def rv := while (true) {
            traceln(`old state`, state)
            def action := stepConcrete(m, literals)
            def [_, newState] := action(state)
            traceln(newState)
            state := newState
            break
        }
        traceln(rv)
    f(ambT(stateT(identity)))
    f(flowT(identity))
    f(stateT(ambT(identity)))
    return 0
