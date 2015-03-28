# XXX DF
def DeepFrozen := Any

object termFactory as DeepFrozen:
    match [name, args]:
        makeTerm(makeTag(null, name, null), null,
                 [convertToTerm(a, null) for a in args], null)
