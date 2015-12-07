imports
exports (chain)

def chain([var fount] + drains) as DeepFrozen:
    for drain in drains:
        fount := fount<-flowTo(drain)
    return fount
