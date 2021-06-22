import "lib/egg" =~ [=> makeEGraph]
exports (simplifyExpression)

def sizeOfNode(eg, node) as DeepFrozen:
    var rv := 1
    for arg in (node.slice(1)):
        rv += eg.analyze(arg)
    return rv

object sizeAnalysis as DeepFrozen:
    to make(n, _span, eg):
        return sizeOfNode(eg, n)

    to join(l, r):
        return l.min(r)

    to modify(eclass, _span):
        return eclass

def just(i :Int) as DeepFrozen:
    return def justOne(m, _eg) as DeepFrozen:
        return m[i]

def simplifyExpression(tree) as DeepFrozen:
    def patterns := [
        # Categories.
        ["comp", ["comp", 1, 2], 3] => fn m, eg {
            eg.add(["comp", m[1], eg.add(["comp", m[2], m[3]], null)], null)
        },
        ["comp", 1, ["comp", 2, 3]] => fn m, eg {
            eg.add(["comp", eg.add(["comp", m[1], m[2]], null), m[3]], null)
        },
        ["comp", ["id"], 1] => just(1),
        ["comp", 1, ["id"]] => just(1),
        # Monoidal categories.
        ["comp", ["prod", 1, 2], ["exl"]] => just(1),
        ["comp", ["prod", 1, 2], ["exr"]] => just(2),
        # Cartesian closed categories.
        ["comp", ["prod", ["comp", ["exl"], ["cur", 1]], ["exr"]], ["ev"]] => just(1),
    ]
    def eg := makeEGraph(sizeAnalysis)
    def add(branch):
        return switch (branch):
            match s :Str:
                eg.add([s], null)
            match [tag] + args:
                def node := [tag] + [for arg in (args) add(arg)]
                eg.add(node, null)
    def top := add(tree)
    for i in (0..!5):
        def pairs := [].diverge()
        for lhs => rhs in (patterns):
            def matches := eg.ematch(lhs)
            for m in (matches):
                pairs.push([m[0], rhs(m, eg)])
        if (!eg.mergePairs(pairs.snapshot())):
            traceln("done early", i)
            break
        traceln("iteration", i, "found # of pairs", pairs.size(), "best cost", eg.analyze(top))
    def extract(class):
        def nodes := eg.nodes(class)
        traceln("extract", class, "considering # of nodes", nodes.size())
        var best := Infinity
        var rv := null
        for node in (nodes):
            # Discard self-referential nodes.
            if (nodes.contains(class)):
                continue
            def size := sizeOfNode(eg, node)
            if (size < best):
                best := size
                rv := node
                traceln("new best node", rv, best)
        def [tag] + args := rv
        return [tag] + [for arg in (args) extract(arg)]
    return extract(top)
