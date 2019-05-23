exports (makeVat)

def makeVat() as DeepFrozen:
    # Cheap banker's queue.
    var incomingTurns := [].diverge()
    var queuedTurns := [].diverge()

    def nextTurn(ej):
        if (queuedTurns.isEmpty()):
            queuedTurns := incomingTurns.reverse().diverge()
            incomingTurns := [].diverge()
        if (queuedTurns.isEmpty()):
            throw.eject(ej, "No more turns")
        return queuedTurns.pop()

    return object vat:
        to send(target, verb, args, namedArgs):
            def resolver := def rv
            incomingTurns.push([resolver, target, verb, args, namedArgs])
            return rv

        to sendOnly(target, verb, args, namedArgs):
            incomingTurns.push([null, target, verb, args, namedArgs])

        to takeTurn():
            def [resolver, target, verb, args, namedArgs] := nextTurn(throw)

            escape FAIL:
                def rv := M.call(target, verb, args, namedArgs | [=> FAIL])
                if (resolver != null):
                    resolver.resolve(rv)
            catch problem:
                if (resolver != null):
                    resolver.smash(problem)

        to turnsRemaining() :Int:
            return incomingTurns.size() + queuedTurns.size()

        to isEmpty() :Bool:
            return incomingTurns.isEmpty() && queuedTurns.isEmpty()
