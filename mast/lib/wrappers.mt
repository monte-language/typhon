exports (makeRevokable, yakbak)

def makeRevokable(obj, &toggle) as DeepFrozen:
    "
    Wrap `obj` with a transparent forwarder. The wrapper will throw an
    exception whenever `toggle` is `false`.
    "

    return object transparentRevokableWrapper:
        "A transparent forwarder."

        match [verb, args, [=> FAIL] | namedArgs]:
            if (!toggle):
                throw.eject(FAIL, `$verb/${args.size()}: Object is disabled`)
            M.call(obj, verb, args, namedArgs)

object yakbak as DeepFrozen:
    "
    A recorder of a single action.
    "

    match message :DeepFrozen:
        def playback(subject) as DeepFrozen:
            return M.callWithMessage(subject, message)
