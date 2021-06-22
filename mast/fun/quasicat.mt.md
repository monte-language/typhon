# QuasiCat

A [category](https://ncatlab.org/nlab/show/category) is a place for doing
logic, including programming. It is useful to express terms within an
arbitrary category without being forced to choose a locale ahead of time. We
will implement a hopefully-boring syntax which designates arrows within
arbitrary categories.

For verbs, we will look at and compare [Hagino
1987](https://arxiv.org/abs/2010.05167), [Von Thun
2001](http://www.kevinalbrecht.com/code/joy-mirror/joy.html), [Kerby
2002](http://tunes.org/~iepos/joy.html), [Elliott
2017](http://conal.net/papers/compiling-to-categories/compiling-to-categories.pdf),
and [Patterson 2017](https://arxiv.org/abs/1706.00526).

## Categories

All categories have identity arrows and the ability to compose arrows.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        | id       |       | id      | 1         |

Composition is usually implicitly built from one-dimensional sequences in
syntax, and we will continue that tradition.

## Initial and Terminal Objects

A [terminal object](https://ncatlab.org/nlab/show/terminal%20object) is a
common categorical feature. They often show up as monoidal units.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| !      | drop     | zap   | it      | I         |

Initial objects are also a thing in some categories.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| !!     |          |       |         |           |

## Products & Coproducts

Categorical products on their own are quite limited. The only universal arrows
are the projections and the pairing. Note that some authors are talking about
monoidal products, depending on how the chosen categories are closed.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| pi1    | pop      |       | exl     |           |
| pi2    | popd     |       | exr     |           |
| pair   |          |       | △       |           |

However, some authors also include a tensoring operation which takes two
arrows and returns an arrow on their products. That is, given f : X → Y and
g : Z → W, their tensor has type X × Z → Y × W.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| prod   |          |       |         | ⊗         |

Dually, coproducts only have injections.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| in1    |          |       |         |           |
| in2    |          |       |         |           |
| case   |          |       |         |           |

## Lists

A [list](https://en.wikipedia.org/wiki/List_(abstract_data_type)) is a
standard and ubiquitous endofunctor. Its factorizing eliminators are
[katamorphisms](https://en.wikipedia.org/wiki/Catamorphism) which "fold" the
list into a single value.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| nil    | []       |       |         |           |
| cons   | cons     |       |         |           |
| prl    | fold     |       |         |           |

## Braided & Symmetric Monoidal Categories

A [symmetric monoidal
category](https://ncatlab.org/nlab/show/symmetric+monoidal+category) allows us
to swap the order of products back and forth. A braided monoidal category also
has swaps, but two swaps isn't necessarily identity.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        | swap     | swap  |         | σ         |

## Dual Objects & Dagger Categories

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        |          |       |         | *         |
|        |          |       |         | †         |

## Cartesian Monoidal Categories

A [Cartesian monoidal
category](https://ncatlab.org/nlab/show/cartesian+monoidal+category) has the
same construction for its monoidal and categorical product. This induces a
diagonal arrow, and also allows building products.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        | dup      | dup   |         | ∆         |

## Compact Closed Categories

A compact closed category has internal homs based on dual objects. For every
object, there is a pair of arrows which relate it to both its dual object and
also the monoidal unit. Confusingly, these arrows are called the unit and
counit.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        |          |       |         | I         |
|        |          |       |         | η         |
|        |          |       |         | ε         |

## Cartesian Closed Categories

A Cartesian closed category has internal homs based on the diagonal arrow.
This includes currying and uncurrying, as well as the application arrow, which
is merely an uncurried identity arrow.

Note that the internal homs of Cartesian closed categories are necessarily
[exponential objects](https://ncatlab.org/nlab/show/exponential%20object);
this fact is required to correctly read some surveyed papers.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| eval   | b        |       | apply   |           |
| curry  |          |       | curry   |           |
|        |          |       | uncurry |           |

## Epi-Mono Factorization

In many topos-like categories, every arrow X → Y can be factored into a left
arrow X → I and a right arrow I → Y. The left arrow is usually epic, the right
arrow is usually monic, their composition is uniquely the original arrow, and
the intermediate object I is called the image of the original arrow.

## Natural Numbers Objects

A [natural numbers
object](https://ncatlab.org/nlab/show/natural+numbers+object) is a reasonable
replacement for unary-encoded natural numbers. Note that encoding does matter;
an NNO is not guaranteed to have fast bit-by-bit recursion, only slow
primitive recursion.

| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
| zero   | 0        |       |         |           |
| succ   | succ     |       |         |           |
| pr     | primrec  |       |         |           |

## Subobject Classifier


| Hagino | Von Thun | Kerby | Elliott | Patterson |
|--------|----------|-------|---------|-----------|
|        |          |       |         |           |
