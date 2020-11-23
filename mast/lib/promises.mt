exports (makeSemaphoreRef, makeLoadBalancingRef)

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
            Ref.broken(problem)
    bind next():
        active -= 1
        if (queue =~ [[resolver, verb, args, namedArgs]] + q):
            queue := q
            resolver.resolve(go(verb, args, namedArgs))

    object semaphoreRef:
        "A patient and polite forwarder."

        match [verb, args, namedArgs]:
            if (active < size):
                go(verb, args, namedArgs)
            else:
                def resolver := def promise
                queue with= ([resolver, verb, args, namedArgs])
                promise

    return [semaphoreRef, &active.get]

def makeLoadBalancingRef() as DeepFrozen:
    "
    A forwarder which transparently delivers messages to one of many possible
    backend references.

    The returned kit `[loadBalancingRef, addRef]` includes a callable for
    adding new refs to the load balancer.
    "

    var nextKey :Int := 0
    def refs := [].asMap().diverge()
    def loads := [].asMap().diverge(Int, Int)

    object loadBalancingRef:
        match [verb, args, namedArgs]:
            if (loads.isEmpty()):
                throw(`Load balancer has no backends`)
            def [k, load] := loads.sortValues()._makeIterator().next(null)
            traceln(`Load balancer delegating message [$verb, $args, $namedArgs] to backend $k (load $load)`)
            loads[k] += 1
            def rv := M.send(refs[k], verb, args, namedArgs)
            when (rv) ->
                loads[k] -= 1
                rv
            catch problem:
                loads[k] -= 1
                Ref.broken(problem)

    def addRef(ref):
        refs[nextKey] := ref
        loads[nextKey] := 0
        nextKey += 1

    return [loadBalancingRef, addRef]
