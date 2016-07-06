import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "unittest" =~ [=> unittest]
exports (Pump, Unpauser, Fount, Drain, Tube,
         nullPump,
         makePump, chainPumps,
         makeMapPump, makeSplitPump, makeStatefulPump,
         makeUTF8DecodePump, makeUTF8EncodePump,
         makeIterFount,
         makePureDrain,
         makePumpTube,
         chainTubes,
         chain)

interface Pump :DeepFrozen:
    "A stream processor which does not care about flow control.

     Pumps transform incoming items each into zero or more outgoing
     elements."

    to started() :Vow[Void]:
        "Flow has started; items will be received soon.

         Pumps should use this method to initialize any required mutable
         state.
         
         The pump may not be considered started until this method's return
         value resolves."

    to stopped(reason :Str) :Vow[Void]:
        "Flow has stopped.

         Pumps should use this method to tear down any allocated resources
         that they may be holding.
         
         The pump may not be considered stopped until this method's return
         value resolves."

    to received(item) :Vow[List]:
        "Process an item and send zero or more items downstream.

         The return value vows to be a list of items."

    # XXX :(Double >= 0.0)
    to progressed(amount :Double) :Void:
        "The current flow control around the pump has updated its load.

         `amount` is 1.0 for every task queued further up the pipeline. Pumps
         might use this method to adjust their processing parameters to trade
         speed for memory or quality."


interface Unpauser :DeepFrozen:
    "An unpauser."

    to unpause() :Void:
        "Remove the pause corresponding to this unpauser.

         Flow will resume when all extant pauses are removed, so unpausing
         this object will not necessarily cause flow to resume.

         Calling `unpause()` more than once will have no effect.

         Flow could resume during this turn; use an eventual send if you want
         to defer it to a subsequent turn.

         The spice must flow."


# XXX Fount[X]
interface Fount :DeepFrozen:
    "A source of streaming data."

    to flowTo(drain) :Any:
        "Designate a drain to receive data from this fount.

         Once called, flow could happen immediately, within the current turn;
         this fount must merely call `to flowingFrom(fount)` before starting
         to flow.

         The return value should be a fount which can `to flowTo()` another
         drain. This is typically achieved by returning the drain that was
         flowed to and treating it as a tube."

    to pauseFlow() :Unpauser:
        "Interrupt the flow.

         Returns an `Unpauser` which can resume flow."

    to stopFlow() :Void:
        "Terminate the flow.

         This fount should cleanly terminate its resources. This fount may
         send more data to its drain, but should eventually cease flow and
         call `to flowStopped()` on its drain when quiescent."

    to abortFlow() :Void:
        "Terminate the flow with extreme prejudice.

         This fount must not send any more data downstream. Instead, it must
         uncleanly release its resources and abort any further upstream flow."


# XXX Drain[X]
interface Drain :DeepFrozen:
    "A sink of streaming data."

    to flowingFrom(fount) :Any:
        "Inform this drain that a fount will be flowing to it.

         The return value is a fount which can `to flowTo()` another drain;
         this is normally done by treating this drain as a tube and returning
         itself."

    to receive(item) :Void:
        "Accept some data.

         This method is the main workhorse of the entire tube subsystem.
         Founts call `to receive()` on their drains repeatedly to move data
         downstream."

    to progress(amount :Double) :Void:
        "Inform a drain of incoming task load.

         In response to extra load, a drain may choose to pause its upstream
         founts; this backpressure should be propagated as far as necessary."

    to flowStopped(reason :Str):
        "Flow has ceased.

         This drain should allow itself to drain cleanly to the next drain in
         the flow or whatever external resource this drain represents, and
         then call `to flowStopped()` on the next drain."

    to flowAborted(reason :Str):
        "Flow has been aborted.

         This drain should uncleanly release its resources and abort the
         remainder of the downstream flow, if any."


interface Tube :DeepFrozen extends Drain, Fount:
    "A pressure-sensitive segment in a stream processing workflow."


def chainPumps(first :Pump, second :Pump) :Pump as DeepFrozen:
    "Chain two pumps together in sequence."

    return object chainedPump as Pump:
        "A chained pump."

        to started() :Vow[Void]:
            return when (first.started()) -> { second.started() }

        to stopped() :Vow[Void]:
            return when (first.stopped()) -> { second.stopped() }

        to received(item) :Vow[List]:
            return when (def xs := first.received(item)) ->
                def promises := [for x in (xs) second.received(x)]
                when (promiseAllFulfilled(promises)) ->
                    var rv := []
                    for p in (promises):
                        rv += p
                    rv

        to progressed(amount):
            first.progressed(amount)
            second.progressed(amount)


object nullPump as DeepFrozen implements Pump:
    "The do-nothing pump."

    to started():
        null

    to stopped(_):
        null

    to received(item) :List:
        return []

    to progressed(_):
        null


object makePump as DeepFrozen:
    "The maker of many useful types of pumps.

     In general, to allow for segmentation, all of the pumps have 'flattened'
     versions which expect their callable arguments to return lists. The
     precise semantics vary by method."

    to map(f) :Pump:
        return object mapPump extends nullPump as Pump:
            to received(item):
                return [f(item)]

    to mapFlat(f) :Pump:
        "A pump which maps each incoming item to zero or more outgoing items."
        return object mapPump extends nullPump as Pump:
            to received(item) :List:
                return f(item)

    to filter(pred) :Pump:
        return object filterPump extends nullPump as Pump:
            to received(item):
                return if (pred(item)) { [item] } else { [] }

    to filterFlat(pred) :Pump:
        "A pump which can replicate an item zero or more times.

         Yes, this one is kind of strange and useless."
        return object filterPump extends nullPump as Pump:
            to received(item):
                return [for b in (pred(item)) ? (b) item]

    to scan(f, var z) :Pump:
        "A pump which can 'scan', performing an incremental fold."
        return object scanPump extends nullPump as Pump:
            to received(item):
                def rv := [z]
                z := f(z, item)
                return rv

    to scanFlat(f, var z) :Pump:
        "A pump which can scan, like `.scan/2`, but which can scan zero or
         more times per incoming item, returning a list of outgoing
         incremental folds."
        return object scanPump extends nullPump as Pump:
            to received(item):
                return switch (f(z, item)) {
                    # Feed me. Feeed me.
                    match [] { [] }
                    match zs {
                        def rv := [z] + zs.slice(0, zs.size() - 1)
                        z := zs.last()
                        rv
                    }
                }

    to accum(f, var acc) :Pump:
        "A pump which accumulates a value over repeated iterations."
        return object accumPump extends nullPump as Pump:
            to received(item):
                def [a, x] := f(acc, item)
                acc := a
                return [x]

    to accumFlat(f, var acc) :Pump:
        "A pump which accumulates, like `.accum/2`, but which can accumulate
         zero or more times per incoming item, returning a final accumulator
         and a list of accumlated outgoing items."
        return object accumPump extends nullPump as Pump:
            to received(item) :List:
                def [a, xs] := f(acc, item)
                acc := a
                return xs


def makeMapPump(f) :Pump as DeepFrozen:
    return makePump.map(f)


def splitAt(needle, var haystack) as DeepFrozen:
    def pieces := [].diverge()
    var offset := 0

    while (offset < haystack.size()):
        def nextNeedle := haystack.indexOf(needle, offset)
        if (nextNeedle == -1):
            break

        def piece := haystack.slice(offset, nextNeedle)
        pieces.push(piece)
        offset := nextNeedle + needle.size()

    return [pieces.snapshot(), haystack.slice(offset, haystack.size())]


def testSplitAtColons(assert):
    def specimen := b`colon:splitting:things`
    def [pieces, leftovers] := splitAt(b`:`, specimen)
    assert.equal(pieces, [b`colon`, b`splitting`])
    assert.equal(leftovers, b`things`)

def testSplitAtWide(assert):
    def specimen := b`it's##an##octagon#not##an#octothorpe`
    def [pieces, leftovers] := splitAt(b`##`, specimen)
    assert.equal(pieces, [b`it's`, b`an`, b`octagon#not`])
    assert.equal(leftovers, b`an#octothorpe`)

unittest([
    testSplitAtColons,
    testSplitAtWide,
])


def makeSplitPump(separator :Bytes) :Pump as DeepFrozen:
    def splitAccum(buf, item):
        def [pieces, leftovers] := splitAt(separator, buf + item)
        return [leftovers, pieces]
    return makePump.accumFlat(splitAccum, b``)


def makeStatefulPump(machine) :Pump as DeepFrozen:
    def State := machine.getStateGuard()
    def [var state :State, var size :Int] := machine.getInitialState()

    def stateAccum(var buf, item):
        buf += _makeList.fromIterable(item)
        while (buf.size() >= size):
            def data := buf.slice(0, size)
            buf := buf.slice(size, buf.size())
            def [newState, newSize] := machine.advance(state, data)
            state := newState
            size := newSize

        return [buf, machine.results()]
    return makePump.accumFlat(stateAccum, [])

def makeUTF8DecodePump() :Pump as DeepFrozen:
    var buf :Bytes := b``
    def decodeAccum(buf :Bytes, item :Bytes):
        def [s, leftovers] := UTF8.decodeExtras(buf + item, null)
        return [leftovers, if (s.size() != 0) { [s] } else { [] }]
    return makePump.accum(decodeAccum, b``)

def makeUTF8EncodePump() :Pump as DeepFrozen:
    return makePump.map(fn s {UTF8.encode(s, null)})

def makeIterFount(iterable) :Fount as DeepFrozen:
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
                    for completion in (completions):
                        completion.smash(problem)
            catch problem:
                # No more items.
                drain.flowStopped(problem)
                for completion in (completions):
                    completion.resolve(problem)

    return object iterFount as Fount:
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

def makePureDrain() :Drain as DeepFrozen:
    def buf := [].diverge()
    var itemsPromise := null
    var itemsResolver := null

    return object pureDrain as Drain:
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

def makePumpTube(pump) :Pump as DeepFrozen:
    var upstream := var downstream := null
    var pause := null
    var stash := []

    return object pumpTube as Pump:
        to flowingFrom(fount):
            upstream := fount
            return pumpTube

        to receive(item):
            def pumped := pump.received(item)
            stash += pumped
            # If we no longer have a downstream, then buffer the received item
            # and pause upstream. We'll unpause on the next flowTo().
            if (downstream == null && pause == null):
                if (upstream != null):
                    pause := upstream.pauseFlow()
            else:
                pumpTube.flush()

        to flowStopped(reason :Str):
            pump.stopped(reason)

            if (downstream != null):
                downstream.flowStopped(reason)

        to flowAborted(reason :Str):
            pump.stopped(reason)

            if (downstream != null):
                downstream.flowAborted(reason)

        to flowTo(drain):
            # The drain must be fulfilled. We handle flow control, not
            # asynchrony.

            # Disconnect.
            if (drain == null):
                downstream := null
                return null

            # Contractual obligation: Fire flowingFrom() callback.
            def rv := drain.flowingFrom(pumpTube)
            downstream := drain

            # If there's any stashed output (leftovers, pushback, etc.) reflow
            # to the new drain.
            pumpTube.flush()

            # If we asked upstream to pause, ask them to unpause now.
            if (pause != null):
                pause.unpause()
                pause := null

            return rv

        to pauseFlow():
            return upstream.pauseFlow()

        to stopFlow():
            downstream.flowStopped()
            downstream := null
            return upstream.stopFlow()

        to abortFlow():
            downstream.flowAborted()
            downstream := null
            return upstream.abortFlow()

        to flush():
            while (stash.size() > 0 &! downstream == null):
                def [piece] + newStash := stash
                stash := newStash
                downstream.receive(piece)

def chainTubes([var fount] + drains) as DeepFrozen:
    for drain in (drains):
        fount := fount<-flowTo(drain)
    return fount

def &&chain := &&chainTubes
