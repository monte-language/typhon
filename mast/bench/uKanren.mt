import "lib/logji" =~ [=> logic, => makeKanren]
exports (b)

def table(rows :List) as DeepFrozen:
    return object tabling:
        match [=="run", vars, _]:
            def tabled(k):
                return logic.sum([for row in (rows) k.unify(vars, row)])

def allOf(actions :List) as DeepFrozen:
    return def allingOf(k):
        var rv := logic.pure(k)
        for action in (actions):
            rv := logic."bind"(rv, action)
        return rv

def withFresh(count :Int, f) as DeepFrozen:
    return def freshened(k):
        def [kanren] + vars := k.fresh(count)
        return M.call(f, "run", vars, [].asMap())(kanren)

def b() as DeepFrozen:
    # The puzzle:
    # There are islanders, in two flavors: Steady and flaky. Steady islanders
    # are always honest; flaky islanders strictly alternate between truth and
    # lies.
    # We see a child and its parents.
    def [kanren, child, parent1, parent2] := makeKanren().fresh(3)
    # We ask the child its flavor:
    # Child: *native tongue*
    # Parent 1: "They said, 'I'm steady.'"
    # Parent 2: "The child is flaky. The child lied."
    # What are everybody's flavors?
    object steady {}
    object flaky {}
    object honest {}
    object lie {}
    # [flavor, truthiness]
    def flavoredStatement := table([
        [steady, honest],
        [flaky, honest],
        [flaky, lie],
    ])
    # [flavor, truthiness1, truthiness2]
    def flavoredStatements := table([
        [steady, honest, honest],
        [flaky, honest, lie],
        [flaky, lie, honest],
    ])
    def puzzle := withFresh(2, fn childClaim, childHonest {
        allOf([
            flavoredStatement(child, childHonest),
            table([
                [steady, steady, honest],
                [flaky, steady, lie],
                [flaky, flaky, honest],
            ])(child, childClaim, childHonest),
            withFresh(1, fn parent1Honest {
                allOf([
                    flavoredStatement(parent1, parent1Honest),
                    table([
                        [honest, steady],
                        [lie, flaky],
                    ])(parent1Honest, childClaim),
                ])
            }),
            withFresh(2, fn parent2Honest1, parent2Honest2 {
                allOf([
                    flavoredStatements(parent2, parent2Honest1,
                                       parent2Honest2),
                    table([
                        [flaky, honest],
                        [steady, lie],
                    ])(child, parent2Honest1),
                    table([
                        [lie, honest],
                        [honest, lie],
                    ])(childHonest, parent2Honest2),
                ])
            }),
        ])
    })
    def cols := [=> child, => parent1, => parent2]
    return [for rk in (logic.makeIterable(puzzle(kanren))) {
        [for k => v in (cols) k => rk.walk(v)]
    }]
