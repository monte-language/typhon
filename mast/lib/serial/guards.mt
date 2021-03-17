exports (NotNull, Guard)

def NotNull.coerce(specimen, ej) as DeepFrozen:
    if (specimen == null):
        throw.eject(ej, "null not allowed")
    return specimen

def Guard :DeepFrozen := Any  # TODO?
