imports
exports (makeIterFount)

def makeIterFount(iterable) as DeepFrozen:
    def iterator := iterable._makeIterator()
    var drain := null
    var pauses :Int := 0
    var completions := []

    def next():
        if (pauses == 0 && drain != null):
            # Okay, we're good to go.
            escape exhausted:
                # XXX capturing iterator key/index could be interesting for stats
                def [_, item] := iterator.next(exhausted)
                when (item) ->
                    drain.receive(item)
                    # And queue the next one.
                    next()
                catch problem:
                    drain.flowAborted(problem)
                    for completion in completions:
                        completion.smash(problem)
            catch problem:
                # No more items.
                drain.flowStopped(problem)
                for completion in completions:
                    completion.resolve(problem)

    return object iterFount:
        "A fount which feeds an iterator to its drain."

        to completion():
            "A promise which will be fulfilled when the drain is finished.
            
             The promise will be smashed if the drain encounters a problem."

            def [p, r] := Ref.promise()
            completions with= (r)
            return p

        to flowTo(newDrain):
            drain := newDrain
            drain.flowingFrom(iterFount)
            next()
            return drain

        to pauseFlow():
            pauses += 1
            var once :Bool := true
            return object iterFountUnpauser:
                to unpause():
                    if (once):
                        once := false
                        pauses -= 1
                        next()

        to stopFlow():
            drain.flowStopped("stopFlow/0")
            drain := null

        to abortFlow():
            drain.flowAborted("abortFlow/0")
            drain := null
