import "lib/mim/full" =~ [=> expand]
import "lib/mim/anf" =~ [=> makeNormal]
exports (go)

def go(expr :DeepFrozen) as DeepFrozen:
    return makeNormal().alpha(expand(expr))
