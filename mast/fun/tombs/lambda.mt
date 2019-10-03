exports (lambda, lambdaToMonte, lambdaToSKI)

# The untyped lambda calculus, using de Bruijn indices.

def occursFree(tree, i :Int) :Bool as DeepFrozen:
    return switch (tree) {
        match [=="λ", e] { occursFree(e, i + 1) }
        match [left, right] { occursFree(left, i) || occursFree(right, i) }
        match v :Int { v == i }
        # Only happens when compiling to SKI.
        match _ { false }
    }

def subst(tree, v, i :Int) as DeepFrozen:
    return switch (tree) {
        match [=="λ", e] { ["λ", subst(e, v, i + 1)] }
        match [left, right] { [subst(left, v, i), subst(right, v, i)] }
        # XXX kindly WTF?
        match x { if (_equalizer.sameYet(x, i) == true) { v } else { x } }
    }

def dec(tree) as DeepFrozen:
    return switch (tree) {
        match [=="λ", e] { ["λ", dec(e)] }
        match [left, right] { [dec(left), dec(right)] }
        match v :Int { v - 1 }
    }

def inc(tree) as DeepFrozen:
    return switch (tree) {
        match [=="λ", e] { ["λ", inc(e)] }
        match [left, right] { [inc(left), inc(right)] }
        match v :Int { v + 1 }
        # Only happens when compiling to SKI.
        match comb { comb }
    }

object lambda as DeepFrozen:
    to signature():
        return "lambda"

    to guard():
        return Any

    to id():
        return ["λ", 0]

    to compose(left, right):
        # XXX eta-reduce?
        return [left, right]


object lambdaToMonte as DeepFrozen:
    to signature():
        return ["lambda", "monte"]

    to run(tree) :DeepFrozen:
        def vars := "xyzw"
        var sp := 0
        def go(t):
            return switch (t) {
                match [=="λ", e] {
                    def v := astBuilder.NounExpr(vars[sp].asString(), null)
                    def patt := astBuilder.FinalPattern(v, null, null)
                    sp += 1
                    def rv := m`fn $patt { ${go(subst(e, v, 0))} }`
                    sp -= 1
                    rv
                }
                match [left, right] { m`${go(left)}(${go(right)})` }
                match v { v }
            }
        return go(tree)

object lambdaToSKI as DeepFrozen:
    to signature():
        return ["lambda", "ski"]

    to run(tree):
        def r := lambdaToSKI
        return switch (tree) {
            match ==["λ", 0] { "i" }
            match [left ? (left != "λ"), right] { [r(left), r(right)] }
            match [=="λ", e ? (!occursFree(e, 0))] { ["k", r(e)] }
            # Eta-reduction: \(e0) =~ e
            match [=="λ", [e ? (!occursFree(e, 0)), ==0]] { r(e) }
            match [=="λ", [left ? (left != "λ"), right]] {
                [["s", r(["λ", left])], r(["λ", right])]
            }
            match [=="λ", [=="λ", e]] { r(["λ", inc(r(["λ", dec(e)]))]) }
            match x { x }
        }
