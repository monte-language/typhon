```
import "lib/logji" =~ [=> logic, => makeKanren, => Katren]
exports (interpret, inferTypes)
```

# QuasiCat

A [category](https://ncatlab.org/nlab/show/category) is a place for doing
logic, including programming. It is useful to express terms within an
arbitrary category without being forced to choose a locale ahead of time. We
will implement a hopefully-boring syntax which designates arrows within
arbitrary categories.

## Parser

Our grammar is based on the following principle. A categorical combinator term
is a functor and a list of parameter terms. Each term designates a
possibly-empty family of arrows; I'm not doing any type-checking.

```
def parseParens(s :Str) as DeepFrozen:
    def stack := [[].diverge()].diverge()
    var currentWord :Str := ""
    def endWord():
        if (!currentWord.isEmpty()):
            stack.last().push(currentWord)
            currentWord := ""

    for c in (s):
        switch (c):
            match =='(':
                endWord()
                stack.push([].diverge())
            match ==')':
                endWord()
                def l := stack.pop().snapshot()
                stack.last().push(l)
            match ==' ':
                endWord()
            match _:
                currentWord with= (c)

    return stack.last().last()
```

## Optimizer

Our optimizer will be based on e-graphs. For each functor which we recognize,
we will add the appropriate algebraic laws as rewrite rules. Functors are
each canonically assigned a parse string, called their **verbs**.

For verbs, we will look at and compare several sources:

* Combinators from [Curien 1986](https://core.ac.uk/download/pdf/82017242.pdf)
* Constructors, natural transformations, and factorizers from [Hagino
  1987](https://arxiv.org/abs/2010.05167)
* Words from [Von Thun
  2001](http://www.kevinalbrecht.com/code/joy-mirror/joy.html)
* Combinators from [Kerby 2002](http://tunes.org/~iepos/joy.html)
* Combinators and notation from [Baez & Stay
  2009](https://math.ucr.edu/home/baez/rosetta.pdf)
* Methods from [Elliott
  2017](http://conal.net/papers/compiling-to-categories/compiling-to-categories.pdf)
* Notation from [Patterson 2017](https://arxiv.org/abs/1706.00526)

### Kerby's Category

Kerby gives a broad argument that their `i` combinator, which unquotes a
single quotation and executes its stack effect, is a homomorphism. Indeed, we
will imagine an entire category which routes quotations opaquely without
executing them; to execute any expression in Kerby's category, simply suffix
it with `i`. However, Kerby also gives a persuasive argument that lambda
calculus is best understood with the identity arrow being the expression
`A\A`, which corresponds precisely to `i`. We thus will use `i` for identity
and reason from there.

### Categories

All categories have identity arrows and the ability to compose arrows.

| Curien | Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|--------|----------|-------|-------------|---------|-----------|
| Id     |        | id       | i     | id          | id      | 1         |
| ◦      |        |          | b     | ◦           | ◦       |           |

Composition is usually implicitly built from one-dimensional sequences in
syntax, and we will continue that tradition. However, we will need to
explicitly compose arrows in the e-graph.

Our lone composition-only rule is used to lean all composition trees to the
right, so that we only have to write one variety of any rule which spans three
or more arrows. We also have a pair of rules for removing identity arrows.

```
def categoryRules :DeepFrozen := [
    ["comp", ["id"], 1] => 1,
    ["comp", 1, ["id"]] => 1,
    ["comp", ["comp", 1, 2], 3] => ["comp", 1, ["comp", 2, 3]],
]
```

### Initial and Terminal Objects

A [terminal object](https://ncatlab.org/nlab/show/terminal%20object) is a
common categorical feature. They often show up as monoidal units.

| Curien | Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|--------|----------|-------|-------------|---------|-----------|
| 1      | !      | drop     | zap   | !           | it      | I         |

The lone rule for terminal objects implements the universal property: There's
only one terminal arrow, regardless of input type.

```
def terminalRules :DeepFrozen := [
    ["comp", 1, ["!"]] => ["!"],
]
```

Initial objects are also a thing in some categories. However, because initial
objects represent absurdity or impossibility in categorical logic, the initial
arrows usually aren't executable unless the category is dualizable and the
intial/terminal object is in fact a [zero
object](https://ncatlab.org/nlab/show/zero%20object).

| Curien | Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|--------|----------|-------|-------------|---------|-----------|
|        | !!     |          |       |             |         |           |

### Products & Coproducts

Categorical products on their own are quite limited. The only universal arrows
are the projections and the pairing.

| Curien | Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|--------|----------|-------|-------------|---------|-----------|
| Fst    | pi1    | pop      | k     | p           | exl     |           |
| Snd    | pi2    | popd     | z     | p'          | exr     |           |
| <,>    | pair   |          | c     |             | △       |           |

Our rules eliminate unneeded work on either side of a product. This is
a fundamentally lazy evaluation, based on the idea that lazy evaluation has
products while eager evaluation has coproducts.

```
def productRules :DeepFrozen := [
    ["comp", ["pair", [1, 2]], ["exl"]] => 1,
    ["comp", ["pair", [1, 2]], ["exr"]] => 2,
]
```

However, some authors also include a tensoring operation which takes two
arrows and returns an arrow on their products. That is, given f : X → Y and
g : Z → W, their tensor has type X × Z → Y × W.

| Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|----------|-------|-------------|---------|-----------|
| prod   |          |       | ⊗           |         | ⊗         |

Dually, coproducts only have injections.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| in1    |          |       | inl     |           |
| in2    |          |       | inr     |           |
| case   |          |       | jam     |           |

### Monoidal Categories

A monoidal category has a unit object and a tensor-like product. Any category
with finite products (products and a terminal object) can be interpreted as a
monoidal category.

Many categories need an associator of some sort, an isomorphism
(X ⊗ Y) ⊗ Z → X ⊗ (Y ⊗ Z). They also have left and right unitors, isomorphisms
1 ⊗ X → X and X ⊗ 1 → X.

| Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|----------|-------|-------------|---------|-----------|
|        |          |       | assoc       |         |           |
|        |          |       | left        |         |           |
|        |          |       | right       |         |           |

### Lists

A [list](https://en.wikipedia.org/wiki/List_(abstract_data_type)) is a
standard and ubiquitous endofunctor. Its factorizing eliminators are
[katamorphisms](https://en.wikipedia.org/wiki/Catamorphism) which "fold" the
list into a single value.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| nil    | []       |       |         |           |
| cons   | cons     |       |         |           |
| prl    | fold     |       |         |           |

### Braided & Symmetric Monoidal Categories

A braided monoidal category allows us
to swap the order of products back and forth with the braiding isomorphism
X ⊗ Y → Y ⊗ X. A [symmetric monoidal
category](https://ncatlab.org/nlab/show/symmetric+monoidal+category) requires
the braiding to be its own inverse.

| Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|----------|-------|-------------|---------|-----------|
|        | swap     | swap  | braid       |         | σ         |

```
def symmetricRules :DeepFrozen := [
    ["comp", ["pair", 0, 2], ["swap"]] => ["pair", 2, 1]
]
```

### Dual Objects & Dagger Categories

On the way to compact closed categories, we must define dual objects. In
addition, for dagger categories, we must provide a dagger on arrows.

| Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|----------|-------|-------------|---------|-----------|
|        |          |       | *           |         | *         |
|        |          |       | †           |         | †         |

### Cartesian Monoidal Categories

A [Cartesian monoidal
category](https://ncatlab.org/nlab/show/cartesian+monoidal+category) has the
same construction for its monoidal and categorical product. This induces a
diagonal arrow.

| Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|----------|-------|-------------|---------|-----------|
|        | dup      | dup   | ∆           |         | ∆         |

### Closed Monoidal Categories

A closed monoidal category has internal homs, enabling currying and
uncurrying. Additionally, there is an application arrow, which is merely an
uncurried identity arrow.

| Curien | Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|--------|----------|-------|-------------|---------|-----------|
| Λ      | curry  |          |       | ~           | curry   |           |
|        |        |          |       |             | uncurry |           |
| App    | eval   | b        |       | eval        | apply   |           |

```
def closedRules :DeepFrozen := [
    ["uncurry", ["id"]] => ["apply"],
    ["uncurry", ["curry", 1]] => 1,
    ["curry", ["uncurry", 1]] => 1,
]
```

### Compact Closed Categories

A compact closed category has internal homs based on dual objects. For every
object, there is a pair of arrows which relate it to both its dual object and
also the monoidal unit. Confusingly, these arrows are called the unit and
counit.

| Hagino | Von Thun | Kerby | Baez & Stay | Elliott | Patterson |
|--------|----------|-------|-------------|---------|-----------|
|        |          |       | i           |         | η         |
|        |          |       | e           |         | ε         |

### Epi-Mono Factorization

In many topos-like categories, every arrow X → Y can be factored into a left
arrow X → I and a right arrow I → Y. The left arrow is usually epic, the right
arrow is usually monic, their composition is uniquely the original arrow, and
the intermediate object I is called the image of the original arrow.

### Natural Numbers Objects

A [natural numbers
object](https://ncatlab.org/nlab/show/natural+numbers+object) is a reasonable
replacement for unary-encoded natural numbers. Note that encoding does matter;
an NNO is not guaranteed to have fast bit-by-bit recursion, only slow
primitive recursion.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| zero   | 0        | z0    |         |           |
| succ   | succ     |       |         |           |
| pr     | primrec  |       |         |           |

### Subobject Classifier


| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        |          |       |         |           |

## Evaluation of ASTs

```
def runExpression(expr, interp) as DeepFrozen:
    def [f] + args := expr
    return M.call(interp, f, [for arg in (args) runExpression(arg, interp)],
                  [].asMap())
```

## Serialization

We define a basic output format which should be homomorphic with what our
parser currently accepts.

```
object serializeExpression as DeepFrozen:
    match [verb, args, _]:
        `$verb(${", ".join(args)})`
```

## Interpreter

```
object interpret as DeepFrozen:
    to id():
        return fn x { x }

    to pair(f, g):
        return fn x { [f(x), g(x)] }

    to exl():
        return fn [x, _] { x }

    to exr():
        return fn [_, x] { x }

    to zero():
        return fn _ { 0 }

    to succ():
        return fn x { x + 1 }

    to pr(e, f):
        return fn x {
            var rv := e(null)
            for _ in (0..!x) { rv := f(rv) }
            rv
        }
```

## Typechecker

```
def assertType(ty :Str) as DeepFrozen:
    return fn k, u { logic (k.unify(u, ty)) map k2 { [k2, u] } }

object typeGoal as DeepFrozen:
    to id():
        return Katren.merge()

    to zero():
        def l := Katren.compose(Katren.exl(), assertType("1"))
        def r := Katren.compose(Katren.exr(), assertType("nat"))
        return Katren.prod(l, r)

def inferTypes(expr) as DeepFrozen:
    def goal := runExpression(expr, typeGoal)
    def [k, x, y] := makeKanren().fresh(2)
    for [context, _] in (logic.makeIterable(goal(k, [x, y]))):
        def wx := context.walk(x)
        def wy := context.walk(y)
        def input := if (wx == x) { "X" } else { wx }
        def output := if (wy == y) { "Y" } else { wy }
        traceln("input", input, "output", output)
```
