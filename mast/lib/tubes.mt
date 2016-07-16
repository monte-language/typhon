import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "unittest" =~ [=> unittest]
exports (Pump, Unpauser, Fount, Drain, Tube,
         nullPump, makePump, chainPumps,
         makeMapPump, makeSplitPump, makeStatefulPump,
         makeUTF8DecodePump, makeUTF8EncodePump,
         makeFount,
         makeIterFount,
         makePureDrain,
         makePumpTube,
         chain)

interface Pump :DeepFrozen:
    "A stream processor which does not care about flow control.

     Pumps transform incoming items each into zero or more outgoing
     elements."

    to started() :Void:
        "Flow has started; items will be received soon.

         Pumps should use this method to initialize any required mutable
         state."

    to received(item) :Vow[List]:
        "Process an item and send zero or more items downstream.

         The return value must be a list of items, but it can be a promise."

    to stopped(reason :Str) :Void:
        "Flow has stopped.

         Pumps should use this method to tear down any allocated resources
         that they may be holding."


interface Unpauser :DeepFrozen:
    "An unpauser."

    to unpause():
        "Remove the pause corresponding to this unpauser.

         Flow will resume when all extant pauses are removed, so unpausing
         this object will not necessarily cause flow to resume.

         Calling `unpause()` more than once will have no effect.

         Flow could resume during this turn; use an eventual send if you want
         to defer it to a subsequent turn.

         The spice must flow."


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

# Pumps.

def chainPumps(first :Pump, second :Pump) :Pump as DeepFrozen:
    return object chainedPump as Pump:
        to started() :Vow[Void]:
            return when (first.started()) -> { second.started() }

        to stopped(reason :Str) :Vow[Void]:
            return when (first.stopped(reason)) -> { second.stopped(reason) }

        to received(item) :Vow[List]:
            return when (def items := first.received(item)) ->
                var l := []
                for i in (items):
                    l += second.received(i)
                l

object nullPump as DeepFrozen implements Pump:
    "The do-nothing pump."

    to started() :Void:
        null

    to stopped(_) :Void:
        null

    to received(item) :List:
        return []

def testChainPumps(assert):
    object double extends nullPump as Pump:
        to received(item):
            return [item - 1, item + 1]
    def pump := chainPumps(double, double)
    return when (def p := pump.received(3)) ->
        assert.equal(p, [1, 3, 3, 5])

object makePump as DeepFrozen:

    to map(f) :Pump:
        return object mapPump extends nullPump as Pump:
            to received(item) :List:
                return [f(item)]

def makeMapPump(f) :Pump as DeepFrozen:
    traceln(`makeMapPump/1: Use makePump.map/1 instead`)
    return makePump.map(f)

def testPumpMap(assert):
    def pump := makePump.map(fn x { x + 1 })
    assert.equal(pump.received(4), [5])

unittest([
    testChainPumps,
    testPumpMap,
])

# Misc. pumps which haven't been factored.

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
    var buf :Bytes := b``

    return object splitPump extends nullPump as Pump:
        to received(item):
            buf += item
            def [pieces, leftovers] := splitAt(separator, buf)
            buf := leftovers
            return pieces

def makeStatefulPump(machine) :Pump as DeepFrozen:
    def State := machine.getStateGuard()
    def [var state :State, var size :Int] := machine.getInitialState()
    var buf := []

    return object statefulPump extends nullPump as Pump:
        to received(item) :List:
            buf += _makeList.fromIterable(item)
            while (buf.size() >= size):
                def data := buf.slice(0, size)
                buf := buf.slice(size, buf.size())
                def [newState, newSize] := machine.advance(state, data)
                state := newState
                size := newSize

            return machine.results()

def makeUTF8DecodePump() :Pump as DeepFrozen:
    var buf :Bytes := b``

    return object UTF8DecodePump extends nullPump as Pump:
        to received(bs :Bytes) :List[Str]:
            buf += bs
            def [s, leftovers] := UTF8.decodeExtras(buf, null)
            buf := leftovers
            return if (s.size() != 0) {[s]} else {[]}

def makeUTF8EncodePump() :Pump as DeepFrozen:
    return makePump.map(fn s {UTF8.encode(s, null)})

# Unpausers.

def makeUnpauser(var once) as DeepFrozen:
    return object unpauser:
        to unpause() :Void:
            if (once != null):
                once()
                once := null

# Founts.

def _makeBasicFount(controller) as DeepFrozen:
    "Make a fount that is controlled by a single callable."

    var drain := null
    var pauses :Int := 0
    var completions :List := []
    var queue :List := []

    def canDeliver() :Bool:
        return pauses == 0 && drain != null

    def flush() :Void:
        for i => item in (queue):
            if (canDeliver()):
                drain.receive(item)
            else:
                queue slice= (i, queue.size())
                break
        queue := []

    def enqueue(item) :Void:
        queue with= (item)
        flush()

    def basicFount

    def next() :Void:
        if (canDeliver()):
            # Okay, we're good to go.
            when (def item := controller()) ->
                enqueue(item)
                # And queue the next one.
                next()
            catch problem:
                basicFount.stopFlow()

    return bind basicFount as Fount:
        "A fount controlled by a single callable."

        to completion():
            "A promise which will be fulfilled when the drain is finished.

             The promise will be smashed if the drain encounters a problem."

            traceln(`basicFount.completion/0: Deprecated`)
            def [p, r] := Ref.promise()
            completions with= (r)
            return p

        to flowTo(newDrain):
            drain := newDrain
            drain.flowingFrom(basicFount)
            next()
            return drain

        to pauseFlow():
            pauses += 1
            return makeUnpauser(fn { pauses -= 1; next() })

        to stopFlow():
            for completion in (completions):
                completion.resolve(null)
            if (drain != null):
                drain.flowStopped("stopFlow/0")
                drain := null

        to abortFlow():
            for completion in (completions):
                completion.resolve(null)
            if (drain != null):
                drain.flowAborted("abortFlow/0")
                drain := null

object makeFount as DeepFrozen:
    "A maker of founts."

    to fromIterable(iterable) :Fount:
        def iterator := iterable._makeIterator()

        def controller():
            return escape ej:
                iterator.next(ej)
            catch problem:
                Ref.broken(problem)

        return _makeBasicFount(controller)

def makeIterFount(iterable) :Fount as DeepFrozen:
    "Old behavior."

    traceln(`makeIterFount/1: Use makeFount.fromIterable/1 instead`)

    def iterator := iterable._makeIterator()

    def controller():
        return escape ej:
            iterator.next(ej)[1]
        catch problem:
            Ref.broken(problem)

    return _makeBasicFount(controller)

# Drains.

def _makeBasicDrain(controller) :Drain as DeepFrozen:
    "Make a drain that is controlled by a single callable."

    var buf :List := []
    var fount := null

    # XXX this is where backpressure would go, signalling the fount that there
    # is too much stuff coming in. Perhaps a named argument with a default
    # buffer size would be nice. Five?
    def flush():
        controller<-(buf[0])
        buf := []

    return object basicDrain as Drain:
        "A basic drain."

        to flowingFrom(newFount) :Drain:
            fount := newFount
            return basicDrain

        to receive(item):
            buf with= (item)
            flush()

        to progress(amount :Double):
            null

        to flowStopped(reason :Str):
            null

        to flowAborted(reason :Str):
            null

def makePureDrain() :Drain as DeepFrozen:
    def buf := [].diverge()
    var itemsPromise := null
    var itemsResolver := null

    def controller(item):
        buf.push(item)

    return object pureDrain extends _makeBasicDrain(controller) as Drain:
        "A drain that has no external effects."

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

def testPureDrainSingle(assert):
    def drain := makePureDrain()
    drain.receive(1)
    drain.flowStopped("test")
    when (def items := drain.promisedItems()) ->
        assert.equal(items, [1])

def testPureDrainDouble(assert):
    def drain := makePureDrain()
    drain.receive(1)
    drain.receive(2)
    drain.flowStopped("test")
    when (def items := drain.promisedItems()) ->
        assert.equal(items, [1])

unittest([
    testPureDrainSingle,
    testPureDrainDouble,
])

# Tubes.

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

def chain([var fount] + drains) as DeepFrozen:
    for drain in (drains):
        fount := fount<-flowTo(drain)
    return fount
