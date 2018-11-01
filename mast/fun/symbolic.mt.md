```
exports (deriv)
```

It's Halloween. Let's show how Monte's homoiconicity works, by cribbing a fun
[Lisp blog post](http://taeric.github.io/CodeAsData.html) about symbolic
derivatives.

We'll want a few helpers first. This pattern-matching tool will disambiguate
integer-bearing literal expressions from the other kinds of Monte literals,
like strings.

```
def literalInt(exp, ej) as DeepFrozen:
    return if (exp.getNodeName() == "LiteralExpr") {
        Int.coerce(exp.getValue(), ej)
    } else { throw.eject(ej, "not a literal int") }
```

The guard for nouns can be used for pattern-matching. We'll bind it to a
convenient name.

```
def Noun :DeepFrozen := astBuilder.getNounGuard()
```

We'll assume that our variable of differentiation is passed in as a
plain string, to make it easier to do comparisons.

```
def _deriv(exp, varb) as DeepFrozen:
    return switch (exp) {
```

The derivative of any literal integer is zero.

```
        match via (literalInt) _ { m`0` }
```

The derivative of our variable is one, and of other variables is zero.

```
        match n :Noun { if (n.getName() == varb) { m`1` } else { m`0` } }
```

And now pattern-matching becomes really useful. We'll assume, for readability,
that the original expression is Full-Monte and that operators haven't been
expanded. First, sums.

```
        match m`@lhs + @rhs` { m`${_deriv(lhs, varb)} + ${_deriv(rhs, varb)}` }
```

And then, products.

```
        match m`@lhs * @rhs` {
            m`($lhs * ${_deriv(rhs, varb)}) + (${_deriv(lhs, varb)} * $rhs)`
        }
    }
```

At this point, we can demonstrate feature parity.

    ▲> deriv(m`x * 2 + 12`, "x")
    Result: m`x * 0 + 1 * 2 + 0`

We can implement the automatically-simplifying version too. First, let's
define our simplifying builders.

```
def makeSum(lhs, rhs) as DeepFrozen:
    return if (lhs =~ via (literalInt) ==0) {
        rhs
    } else if (rhs =~ via (literalInt) ==0) {
        lhs
    } else if ([lhs, rhs] =~ [via (literalInt) i, via (literalInt) j]) {
        astBuilder.LiteralExpr(i + j, null)
    } else { m`$lhs + $rhs` }

def makeProd(lhs, rhs) as DeepFrozen:
    return if (lhs =~ via (literalInt) ==0 || rhs =~ via (literalInt) ==0) {
        m`0`
    } else if (lhs =~ via (literalInt) ==1) {
        rhs
    } else if (rhs =~ via (literalInt) ==1) {
        lhs
    } else if ([lhs, rhs] =~ [via (literalInt) i, via (literalInt) j]) {
        astBuilder.LiteralExpr(i * j, null)
    } else { m`$lhs * $rhs` }
```

And now the real deal.

```
def deriv(exp, varb) as DeepFrozen:
    return switch (exp) {
        match via (literalInt) _ { m`0` }
        match n :Noun { if (n.getName() == varb) { m`1` } else { m`0` } }
        match m`@lhs + @rhs` { makeSum(deriv(lhs, varb), deriv(rhs, varb)) }
        match m`@lhs * @rhs` {
            makeSum(makeProd(lhs, deriv(rhs, varb)), makeProd(deriv(lhs, varb), rhs))
        }
    }
```

    ▲> deriv(m`x * 2 + 12`, "x")
    Result: m`2`

We can evaluate this easily on some example functions.

```
def ex1 := eval(m`fn x { ${deriv(m`x * 2 + 12`, "x")} }`, [].asMap())
traceln([for i in (1..10) ex1(i)])

def ex2 := eval(m`fn x { ${deriv(m`x * x`, "x")} }`, [].asMap())
traceln([for i in (1..10) ex2(i)])
```

Note that Monte evaluation is relatively safe, and in this case, the basic
authority of integers alone is sufficient in our computed derivatives, so that
we can pass `[].asMap()` as our scope instead of the more traditional
`safeScope`.
