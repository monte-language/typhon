exports (NotNull, Guard, Tuple)

def NotNull.coerce(specimen, ej) as DeepFrozen:
    if (specimen == null):
        throw.eject(ej, "null not allowed")
    return specimen

def Guard :DeepFrozen := Any  # TODO?

object Tuple as DeepFrozen:
    match [=="get", subguards :DeepFrozen, _]:
        def sizeGuard :DeepFrozen := Same[subguards.size()]
        def tuple.coerce(specimen, ej) as DeepFrozen:
            List.coerce(specimen, ej)
            sizeGuard.coerce(specimen.size(), ej)
            for ix => g in (subguards):
                g.coerce(specimen[ix], ej)
            return specimen
