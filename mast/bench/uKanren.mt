import "lib/iterators" =~ [=> zip :DeepFrozen]
import "lib/uKanren" =~ [=> kanren :DeepFrozen]
import "bench" =~ [=> bench]
exports (main)

def b() as DeepFrozen:
    # The puzzle:
    # There are islanders, in two flavors: Steady and flaky. Steady islanders
    # are always honest; flaky islanders strictly alternate between truth and
    # lies.
    # We see a child and its parents. We ask the child its flavor:
    # Child: *native tongue*
    # Parent 1: "They said, 'I'm steady.'"
    # Parent 2: "The child is flaky. The child lied."
    # What are everybody's flavors?
    object steady {}
    object flaky {}
    object honest {}
    object lie {}
    # [flavor, truthiness]
    def flavoredStatement := kanren.table([
        [steady, honest],
        [flaky, honest],
        [flaky, lie],
    ])
    # [flavor, truthiness1, truthiness2]
    def flavoredStatements := kanren.table([
        [steady, honest, honest],
        [flaky, honest, lie],
        [flaky, lie, honest],
    ])
    def puzzle := kanren.fresh(fn child, parent1, parent2 {
        kanren.fresh(fn childClaim, childHonest {
            kanren.allOf([
                flavoredStatement(child, childHonest),
                kanren.table([
                    [steady, steady, honest],
                    [flaky, steady, lie],
                    [flaky, flaky, honest],
                ])(child, childClaim, childHonest),
                kanren.fresh(fn parent1Honest {
                    kanren.allOf([
                        flavoredStatement(parent1, parent1Honest),
                        kanren.table([
                            [honest, steady],
                            [lie, flaky],
                        ])(parent1Honest, childClaim),
                    ])
                }, 1),
                kanren.fresh(fn parent2Honest1, parent2Honest2 {
                    kanren.allOf([
                        flavoredStatements(parent2, parent2Honest1,
                                           parent2Honest2),
                        kanren.table([
                            [flaky, honest],
                            [steady, lie],
                        ])(child, parent2Honest1),
                        kanren.table([
                            [lie, honest],
                            [honest, lie],
                        ])(childHonest, parent2Honest2),
                    ])
                }, 2),
            ])
        }, 2)
    }, 3)
    def l := _makeList.fromIterable(kanren.asIterable(puzzle))
    # Deduplicate. Surprisingly, only one duplicate solution
    def results := [].asSet().diverge()
    for row in (l):
        def cols := ["child", "parent1", "parent2"]
        def m := [for [k, v] in (zip.ragged(cols, row)) k => v]
        results.include(m)
    return results

bench(b, "uKanren logic puzzle")

def main(_argv) :Int as DeepFrozen:
    b()
    return 0
