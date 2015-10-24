imports
exports (makePureDrain)

def makePureDrain() as DeepFrozen:
    def buf := [].diverge()
    var itemsPromise := null
    var itemsResolver := null

    return object pureDrain:
        "A drain that has no external effects."

        to flowingFrom(fount): 
            return pureDrain

        to receive(item):
            buf.push(item)

        to progress(amount :Double):
            null

        to flowStopped(reason :Str):
            if (itemsResolver != null):
                itemsResolver.resolve(buf.snapshot())

        to flowAborted(reason :Str):
            if (itemsResolver != null):
                itemsResolver.smash(reason)

        to items() :List:
            return buf.snapshot()

        to promisedItems():
            if (itemsPromise == null):
                def [p, r] := Ref.promise()
                itemsPromise := p
                itemsResolver := r
            return itemsPromise
