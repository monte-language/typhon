imports
exports (emptyState, unifyGoal, callFresh, conj, disj)
"μKanren."

object VARS as DeepFrozen:
    "Variables are tagged with this object."

def makeVar(c) as DeepFrozen:
    return [VARS, c]

def emptyState() as DeepFrozen:
    return [[].asMap(), 0]

def walk(u, s :Map) as DeepFrozen:
    return if (u =~ [==VARS, k]):
        if (s.contains(k)) {walk(s[k], s)} else {u}
    else:
        u

def unify(u, v, s :Map) :NullOk[Map] as DeepFrozen:
    def rv := switch ([walk(u, s), walk(v, s)]) {
        match [[==VARS, x], [==VARS, y]] ? (x == y) {s}
        match [[==VARS, x], y] {[x => y] | s}
        match [x, [==VARS, y]] {[y => x] | s}
        match [x, y] {if (x == y) {s}}
    }
    traceln(`Unify: $u ≡ $v in $s: $rv`)
    return rv

def unifyGoal(u, v) as DeepFrozen:
    return def unifyingGoal([s, c]) :List:
        def next := unify(u, v, s)
        return if (next != null) {[[next, c]]} else {[]}

def callFresh(f) as DeepFrozen:
    return def freshGoal([s, c]):
        return f(makeVar(c))([s, c + 1])

def mplus(stream1, stream2) as DeepFrozen:
    return switch (stream1) {
        match [] {stream2}
        match [x] + xs {[x, mplus(xs, stream2)]}
        match f {fn {mplus(stream2, f())}}
    }

def mbind(stream, g) as DeepFrozen:
    return switch (stream) {
        match [] {[]}
        match [x] + xs {mplus(g(x), mbind(xs, g))}
        match f {fn {mbind(f(), g)}}
    }

def disj(g1, g2) as DeepFrozen:
    return def orGoal(sc):
        return mplus(g1(sc), g2(sc))

def conj(g1, g2) as DeepFrozen:
    return def andGoal(sc):
        return mbind(g1(sc), g2)
