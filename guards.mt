exports (NotNull, Guard, Tuple)

def NotNull.coerce(specimen, ej) as DeepFrozen:
    if (specimen == null):
        ej("null not allowed")
    return specimen

def Guard :DeepFrozen := Any  # TODO?

object Tuple as DeepFrozen:
    match [=="get", subguards, _]:
        traceln(`making Tuple[$subguards]`)
        def sizeGuard := Same[subguards.size()]
        return def tuple.coerce(specimen, ej) as DeepFrozen:
            List.coerce(specimen, ej)
            sizeGuard.coerce(specimen, ej)
            for ix => g in (subguards):
                g.coerce(specimen[ix], ej)
            return specimen
