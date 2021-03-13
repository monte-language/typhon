```
import "lib/iterators" =~ [=> islice]
import "unittest" =~ [=> unittest :Any]
exports (stepIterable, optimalSpeedup)
```

# Optimal Speedup of Las Vegas Algorithms

[Luby's algorithm](https://www.cs.utexas.edu/~diz/pubs/speedup.pdf) is an
optimal scheduler for incremental [Las Vegas
algorithms](https://en.wikipedia.org/wiki/Las_Vegas_algorithm). A Las Vegas
algorithm is precomposed with a source of randomness, and evaluates a variable
number of steps before returning a result. An incremental Las Vegas algorithm
takes a parameter bounding the number of steps for each evaluation; if the
evaluation would need more steps, then it instead returns without a result.

The algorithm should probably be credited not just to Luby, but also Sinclair
and Zuckerman.

## Iterating the Optimal Number of Steps

Luby's algorithm revolves around the idea of an optimal strategy for Las Vegas
algorithms. It happens that there is such a strategy:

    [1, 1, 2, 1, 1, 2, 4, 1, 1, 2, 1, 1, 2, 4, 8, …]

We will need a clever iterator to generate this sequence. Under [this
sequence's entry in OEIS](https://oeis.org/A182105), Knuth gives a clever
algorithm which we can use.

```
def stepIterable._makeIterator() as DeepFrozen:
    var i := 0
    var u := 1
    var v := 1
    return def stepIterator.next(_ej):
        def rv := [i, v]
        i += 1
        if ((u & -u) == v):
            u += 1
            v := 1
        else:
            v *= 2
        return rv

def testStepIterable(assert):
    def expected := [1, 1, 2, 1, 1, 2, 4, 1, 1, 2]
    assert.equal(_makeList.fromIterable(islice(stepIterable, 0, 10)), expected)

unittest([testStepIterable])
```

## Performing the Speedup

We simply try to run the given algorithm for each number of steps. If it
manages to succeed at any point, then we're done.

```
def optimalSpeedup(lv) as DeepFrozen:
    "
    Repeatedly evaluate `lv` until it succeeds. 
    "

    return def lubyScheduler(x):
        for steps in (stepIterable):
            return lv(x, steps, __continue)
```
