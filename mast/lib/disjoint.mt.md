```
exports (makeDisjointForest)
```

A [disjoint-set
forest](https://en.wikipedia.org/wiki/Disjoint-set_data_structure), also
commonly called a union-find map (after "UNION" and "FIND" in [Tarjan's
original paper](https://dl.acm.org/doi/10.1145/321879.321884)) or a triangular
substitution map, is a customizeable equivalence relation. Given a sequence of
objects and an equivalence relation on those objects, a disjoint-set forest
provides an efficient online structure for computing and querying that
relation. In particular, we are interested in the [equivalence
closure](https://en.wikipedia.org/wiki/Closure_(mathematics)#Binary_relation_closures)
over the sequence of objects.

Since the objects are assumed to be ordered in a sequence, we can use natural
numbers to index them. Our forest will consist of a sea of partitions, with
each partition representing an equivalence class. Each number is either a
**representative**, which is a witness for the existence of a particular
equivalence class, or an element of some other representative's equivalence
class. To create a new partition, designate a fresh representative. To merge
two partitions, convert one partition's representative to an element of the
other partition. To look up the partition for an element, return its
representative. This is all conceptually simple, but implementations can get
quite fancy. A common theme is to use mutable storage.

```
def makeDisjointForest() as DeepFrozen:
    def forest := [].diverge(Int)
    def sizes := [].asMap().diverge(Int, Int)

    return object disjointForest:
        "A union-find operation."

        to freshClass() :Int:
            "A not-before-seen representative."

            def rv := forest.size()
            forest.push(rv)
            sizes[rv] := 1
            return rv

        to find(x :Int) :Int:
            "The representative of `x`."

            var k := x
            var v := forest[k]
            while (k != v):
                # Path compression: The path looks like:
                # k -> v -> next
                def next := forest[v]
                # Now it'll look like:
                # k -> next
                forest[k] := next
                # And iterate.
                k := v
                v := next
            return v

        to union(x :Int, y :Int) :Void:
            "Assert that `x` and `y` are in the same partition."

            def rx := disjointForest.find(x)
            def ry := disjointForest.find(y)
            if (rx != ry):
                # The smaller set will be a child of the larger set.
                if (sizes[rx] >= sizes[ry]):
                    forest[ry] := rx
                    sizes[rx] += sizes[ry]
                    sizes.removeKey(ry)
                else:
                    forest[rx] := ry
                    sizes[ry] += sizes[rx]
                    sizes.removeKey(rx)

        to size(x :Int) :Int:
            "
            The number of elements currently in the same equivalence class as
            `x`, including `x` itself.
            "

            return sizes[disjointForest.find(x)]

        to partitions() :Int:
            "The number of partitions currently represented."

            return sizes.size()
```
