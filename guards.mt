exports (NotNull, Guard, Tuple, DFTuple)

def NotNull.coerce(specimen, ej) as DeepFrozen:
    if (specimen == null):
        throw.eject(ej, "null not allowed")
    return specimen

def Guard :DeepFrozen := Any  # TODO?

object DFTuple as DeepFrozen:
    match [=="get", subguards :DeepFrozen, _]:
        traceln(`making DFTuple[$subguards]`)
        def sizeGuard :DeepFrozen := Same[subguards.size()]
        def dftuple.coerce(specimen, ej) as DeepFrozen:
            traceln(`DFTuple[$subguards].coerce($specimen)`)
            List.coerce(specimen, ej)
            sizeGuard.coerce(specimen.size(), ej)
            for ix => g in (subguards):
                g.coerce(specimen[ix], ej)
            return specimen

object Tuple as DeepFrozen:
    match [=="get", subguards, _]:
        traceln(`making Tuple[$subguards]`)
        def sizeGuard := Same[subguards.size()]
        def tuple.coerce(specimen, ej):
            traceln(`Tuple[$subguards].coerce($specimen)`)
            List.coerce(specimen, ej)
            sizeGuard.coerce(specimen.size(), ej)
            for ix => g in (subguards):
                g.coerce(specimen[ix], ej)
            return specimen
