exports (makeSemaphoreRef)

# All about promises!

def makeSemaphoreRef(ref, size :(Int > 0)) as DeepFrozen:
    "
    A forwarder for `ref` which only allows `size` pending messages to be
    enqueued at once.

    The forwarder is a semaphore in the sense that when more than `size`
    messages are sent to the forwarder, it will wait for at least one
    forwarded message to resolve before sending another.

    The return kit `[semaphoreRef, active]` includes a getter for the number
    of active messages.
    "

    var active :(0..size) := 0
    var queue := []
    def next
    def go(verb, args, namedArgs):
        active += 1
        return when (def rv := M.send(ref, verb, args, namedArgs)) ->
            next<-()
            rv
        catch problem:
            next<-()
            problem
    bind next():
        active -= 1
        if (queue =~ [[resolver, verb, args, namedArgs]] + q):
            queue := q
            resolver.resolve(go(verb, args, namedArgs))

    object semaphoreRef:
        "A patient and polite forwarder."

        match [verb, args, namedArgs]:
            return if (active < size):
                go(verb, args, namedArgs)
            else:
                def resolver := def promise
                queue with= ([resolver, verb, args, namedArgs])
                promise

    return [semaphoreRef, &active.get]
