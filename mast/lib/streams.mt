import "unittest" =~ [=> unittest :Any]
import "lib/enum" =~ [=> makeEnum :DeepFrozen]
# For testing only; not to be re-exported. ~ C.
import "lib/codec/utf8" =~ [=> UTF8]
exports (
    Sink, Source, Pump,
    makeSink, makeSource, makePump,
    makePumpPair,
    endOfStream, EOSOk,
    flow, fuse,
    collectStr, collectBytes,
    alterSink, alterSource,
)

# A new stream library.

interface Sink :DeepFrozen:
    "A receptacle into which discrete packets of data may be deposited."

    to run(packet) :Vow[Void]:
        "Receive `packet`, returning a `Vow` which resolves when the sink is
         ready to receive again."

    to complete() :Vow[Void]:
        "Signal that no more packets will be delivered, returning a `Vow`
         which resolves when the sink has released its resources."

    to abort(problem) :Vow[Void]:
        "Signal that no more packets will be delivered because of `problem`,
         returning a `Vow` which resolves when the sink has released its
         resources."

interface Source :DeepFrozen:
    "A source from which discrete packets of data are delivered."

    to run(sink :Sink) :Vow[Void]:
        "Deliver a packet to `sink` at a later time.

         Returns a `Vow` which resolves after attempted delivery, either to
         `null` in case of success, or a broken promise in case of failure."

object makeSink as DeepFrozen:
    "A maker of several types of sinks."

    to asList() :Pair[Vow[List], Sink]:
        "Collect data into a List."

        def l := [].diverge()
        def [p, r] := Ref.promise()

        object listSink as Sink:
            to run(packet) :Void:
                l.push(packet)

            to complete() :Void:
                r.resolve(l.snapshot())

            to abort(problem) :Void:
                r.smash(problem)

        return [p, listSink]

    to asStr() :Pair[Vow[Str], Sink]:
        "Collect Strs and concatenate them into a single string."

        # Reuse the list machinery.
        def [p, listSink] := makeSink.asList()
        return [when (p) -> { "".join(p) }, listSink]

    to asBytes() :Pair[Vow[Bytes], Sink]:
        "Collect Bytes and concatenate them into a single bytestring."

        # Reuse the list machinery.
        def [p, listSink] := makeSink.asList()
        return [when (p) -> { b``.join(p) }, listSink]

def testMakeSinkAsList(assert):
    def [l, sink] := makeSink.asList()
    return when (sink(1), sink(2), sink(3)) ->
        when (sink.complete()) ->
            assert.willEqual(l, [1, 2, 3])

def testMakeSinkAsListAbort(assert):
    def [l, sink] := makeSink.asList()
    return when (sink(1), sink(2), sink(3)) ->
        when (sink.abort("Testing")) ->
            assert.willBreak(l)

def testMakeSinkAsStr(assert):
    def [s, sink] := makeSink.asStr()
    return when (sink("suit"), sink("case")) ->
        when (sink.complete()) ->
            assert.willEqual(s, "suitcase")

def testMakeSinkAsBytes(assert):
    def [bs, sink] := makeSink.asBytes()
    return when (sink(b`suit`), sink(b`case`)) ->
        when (sink.complete()) ->
            assert.willEqual(bs, b`suitcase`)

unittest([
    testMakeSinkAsList,
    testMakeSinkAsListAbort,
    testMakeSinkAsStr,
    testMakeSinkAsBytes,
])

object makeSource as DeepFrozen:
    "A maker of several types of sources."

    to fromIterator(iter) :Source:
        return def iterSource(sink) :Vow[Void] as Source:
            return try:
                escape ej:
                    sink(iter.next(ej))
                catch _:
                    sink.complete()
            catch problem:
                sink.abort(problem)

    to fromIterable(iter) :Source:
        return makeSource.fromIterator(iter._makeIterator())

def testMakeSourceFromIterable(assert):
    def [l, sink] := makeSink.asList()
    def source := makeSource.fromIterable([1, 2, 3])
    # One extra turn is required for completion to be delivered.
    for _ in (0..3):
        source(sink)
    return assert.willEqual(l, [[0, 1], [1, 2], [2, 3]])

unittest([testMakeSourceFromIterable])

def flow(source, sink) :Vow[Void] as DeepFrozen:
    "Flow all packets from `source` to `sink`, returning a `Vow` which
     resolves to `null` upon completion or a broken promise upon failure."

    def [p, r] := Ref.promise()

    object flowSink as Sink:
        to run(packet) :Vow[Void]:
            # We must pass the packet to the sink, and not request another
            # packet until we have completed delivery. However, we will cause
            # a deep recursion on the promises if we return `source(flowSink)`
            # directly. Instead, we return `null` as soon as delivery of
            # *this* packet has finished. ~ C.
            return when (sink<-(packet)) ->
                source<-(flowSink)
                null
            catch problem:
                r.smash(problem)
                sink.abort(problem)
                Ref.broken(problem)

        to complete() :Vow[Void]:
            r.resolve(null)
            return sink.complete()

        to abort(problem) :Vow[Void]:
            r.smash(problem)
            return sink.abort(problem)

    return when (source<-(flowSink)) ->
        p
    catch problem:
        r.smash(problem)
        null

def testFlow(assert):
    def [l, sink] := makeSink.asList()
    def source := makeSource.fromIterable([1, 2, 3])
    return when (flow(source, sink)) ->
        assert.willEqual(l, [[0, 1], [1, 2], [2, 3]])

def testFlowAbort(assert):
    def source(sink) as Source:
        sink.abort("test")
    def [_, sink] := makeSink.asList()
    # XXX should this pattern be moved up to a common method?
    return when (flow(source, sink)) ->
        null
    catch problem:
        assert.equal(problem, "test")

def testFlowFail(assert):
    def source(_sink, => FAIL) as Source:
        throw.eject(FAIL, "test")
    def [_, sink] := makeSink.asList()
    return when (flow(source, sink)) ->
        null
    catch problem:
        assert.equal(problem, "test")

unittest([
    testFlow,
    testFlowAbort,
    testFlowFail,
])

def collectStr(source) :Vow[Str] as DeepFrozen:
    "Collect a single Str from a source of Strs."

    def [s, sink] := makeSink.asStr()
    flow(source, sink)
    return s

def collectBytes(source) :Vow[Bytes] as DeepFrozen:
    "Collect a single Bytes from a source of Bytes."

    def [bs, sink] := makeSink.asBytes()
    flow(source, sink)
    return bs

def testCollectStr(assert):
    var i :Int := 0
    def source(sink):
        i += 1
        if (i > 3):
            sink.complete()
        else:
            sink(`$i`)
    def s := collectStr(source)
    when (s) ->
        assert.equal(s, "123")

def testCollectBytes(assert):
    def source := makeSource.fromIterable([b`baseball`, b`diamond`, b`ring`])
    def bs := collectBytes(source)
    return Ref.whenNear(bs, fn _ { assert.equal(bs, b`baseballdiamondring`) })

unittest([
    testCollectStr,
    testCollectBytes,
])

object endOfStream as DeepFrozen:
    "An in-band signal that a pump has successfully halted."

object EOSOk extends List as DeepFrozen:
    "A list of packets, any of which might be `==endOfStream`."

    to get(subGuard):
        object EOSGuard extends subGuard:
            to coerce(specimen, ej):
                return if (specimen == endOfStream) { specimen } else {
                    super.coerce(specimen, ej)
                }
        return List[EOSGuard]

def testEOSOk(assert):
    assert.doesNotEject(fn ej {
        EOSOk.coerce([], ej)
        EOSOk.coerce([1, 2], ej)
        EOSOk.coerce([3, endOfStream], ej)
    })

def testSubEOSOk(assert):
    def g := EOSOk[Int]
    assert.doesNotEject(fn ej {
        g.coerce([], ej)
        g.coerce([1, 2], ej)
        g.coerce([3, endOfStream], ej)
    })
    assert.ejects(fn ej { g.coerce(["asdf"], ej) })

unittest([
    testEOSOk,
    testSubEOSOk,
])

interface Pump :DeepFrozen:
    "A machine which emits zero or more packets for every incoming packet."

    to run(packet) :EOSOk:
        "
        Consume `packet` and return zero or more packets.

        A packet may be `endOfStream` to signal an end-of-stream condition.
        "

def trimPackets(specimen) as DeepFrozen:
    "Helper for trimming pump emissions."
    def index := specimen.indexOf(endOfStream)
    return if (index == -1) {
        [false, specimen]
    } else {
        [true, specimen.slice(0, index)]
    }

def [PumpState :DeepFrozen,
     QUIET :DeepFrozen,
     PACKETS :DeepFrozen,
     SINKS :DeepFrozen,
     CLOSING :DeepFrozen,
     FINISHED :DeepFrozen,
     ABORTED :DeepFrozen,
] := makeEnum(["quiet", "packets", "sinks", "closing", "finished", "aborted"])

def _makePumpPair(pump) :Pair[Sink, Source] as DeepFrozen:
    "Given `pump`, produce a sink which feeds packets into the pump and a
     source which produces the pump's results."

    # The current state enum and the actual state variable.
    var ps :PumpState := QUIET
    # QUIET, FINISHED: null; PACKETS, CLOSING: list of packets; SINKS: list of
    # sinks; ABORTED: problem
    var state := null

    def pumpSource(sink) :Vow[Void] as Source:
        return switch (ps):
            match ==QUIET:
                def [p, r] := Ref.promise()
                ps := SINKS
                state := [[sink, r]]
                p
            match ==PACKETS:
                def [packet] + packets := state
                if (packets.isEmpty()):
                    ps := QUIET
                    state := null
                else:
                    state := packets
                sink<-(packet)
            match ==SINKS:
                def [p, r] := Ref.promise()
                state with= ([sink, r])
                p
            match ==CLOSING:
                def [packet] + packets := state
                if (packets.isEmpty()):
                    ps := FINISHED
                    state := null
                else:
                    state := packets
                sink<-(packet)
            match ==FINISHED:
                sink<-complete()
            match ==ABORTED:
                sink<-abort(state)

    object pumpSink as Sink:
        to run(packet) :Vow[Void]:
            switch (ps):
                match ==QUIET:
                    def [eos, packets] := trimPackets(pump(packet))
                    # If we get no packets from the pump, but the pump hasn't
                    # signaled EOS, then this is just priming the pump and
                    # we're still quiet. That's why we switch on EOS first and
                    # leave one case empty. (Should this just be a single big
                    # switch-expr?) ~ C.
                    if (eos):
                        if (packets.isEmpty()):
                            ps := FINISHED
                        else:
                            ps := CLOSING
                            state := packets
                    else:
                        if (!packets.isEmpty()):
                            ps := PACKETS
                            state := packets
                match ==PACKETS:
                    def [eos, packets] := trimPackets(pump(packet))
                    if (eos):
                        ps := CLOSING
                    state += (packets)
                match ==SINKS:
                    def [eos, packets] := trimPackets(pump(packet))
                    def packetsSize := packets.size()
                    def sinkSize := state.size()
                    for i => p in (packets):
                        if (i >= sinkSize):
                            break
                        def [sink, r] := state[i]
                        r.resolve(null)
                        sink<-(p)
                    if (packetsSize > sinkSize):
                        ps := eos.pick(CLOSING, PACKETS)
                        state := packets.slice(sinkSize)
                    else if (packetsSize < sinkSize):
                        state slice= (packetsSize)
                    else:
                        ps := eos.pick(FINISHED, QUIET)
                        state := null

        to complete() :Void:
            switch (ps):
                match ==QUIET:
                    ps := FINISHED
                match ==PACKETS:
                    ps := CLOSING
                match ==SINKS:
                    ps := FINISHED
                    for [sink, r] in (state):
                        sink<-complete()
                        r.resolve(null)
                    state := null

        to abort(problem) :Void:
            if (ps == SINKS):
                for [sink, r] in (state):
                    sink<-abort(problem)
                    r.smash(problem)
            ps := ABORTED
            state := problem

    return [pumpSink, pumpSource]

def nullPump(_) :EOSOk as DeepFrozen implements Pump:
    return [endOfStream]

def idPump(packet) :List as DeepFrozen implements Pump:
    return [packet]

object makePumpPair extends _makePumpPair as DeepFrozen:
    "A maker of sources and sinks from pumps."

    to withIdentityPump() :Pair[Sink, Source]:
        "
        Produce a `[sink, source]` pair where the source's data comes from the
        sink.

        This is the correct way to return a source without having to manage an
        interface more complex than `Sink`.
        "

        return _makePumpPair(idPump)

def testMakePumpPair(assert):
    def [sink, source] := makePumpPair.withIdentityPump()
    def [l, listSink] := makeSink.asList()
    for i in (0..3):
        sink<-(i)
    sink<-complete()
    return when (flow(source, listSink), l) ->
        assert.equal(l, [0, 1, 2, 3])

unittest([
    testMakePumpPair,
])

object makePump as DeepFrozen:
    "A maker of several types of pumps."

    to null() :Pump:
        "
        The null pump.
        
        Of the two possible pumps that might be called the 'null' pump, this
        is the pump which always returns `null`. (The other option, the
        'unproductive' pump which always returns `[]`, is not currently
        available.)
        "

        return nullPump

    to id() :Pump:
        "The identity pump."

        return idPump

    to takeWhile(pred) :Pump:
        "
        A pump which is the identity pump while `pred(packet) :Bool`
        returns `true`, then the null pump after that.

        The packet on the edge for which `pred(packet) == false` will
        *not* be transmitted downstream. 
        "

        var on :Bool := true
        return def takeWhilePump(packet) :EOSOk as Pump:
            return if (on && (on := pred(packet))) { [packet] } else { [endOfStream] }

    to map(f) :Pump:
        return def mapPump(packet) :List as Pump:
            return [f(packet)]

    to filter(predicate) :Pump:
        return def filterPump(packet) :List as Pump:
            return if (predicate(packet)) { [packet] } else { [] }

    to scan(f, var z) :Pump:
        var first :Bool := true
        return def scanPump(packet) :List as Pump:
            return if (first):
                first := false
                # Sorry! ~ C.
                [z, z := f(z, packet)]
            else:
                # Okay, clearly not so sorry. ~ C.
                [z := f(z, packet)]

    to encode(codec) :Pump:
        "A pump for encoding with `codec`."

        return def encodePump(packet) :List as Pump:
            return [codec.encode(packet, null)]

    to decode(codec, => withExtras :Bool := false) :Pump:
        "A pump for decoding with `codec`."

        return if (withExtras):
            # XXX the protocol doesn't give us good initial leftovers. My
            # kingdom for a monoid~
            var leftovers := null
            def decodeWithExtrasPump(var packet) :List as Pump:
                if (leftovers != null):
                    packet := leftovers + packet
                def [rv, remainder] := codec.decodeExtras(packet, null)
                leftovers := remainder
                return [rv]
        else:
            def decodePump(packet) :List as Pump:
                return [codec.decode(packet, null)]

    to splitAt(fragment, var buf) :Pump:
        "
        A pump which splits and buffers strings of some sort.

        The final split piece is only delivered when terminated by the
        splitting fragment; this behavior is meant for splitting trailing
        newlines.

        To split strings: makePump.splitAt(\":\", \"\")

        To split bytestrings: makePump.splitAt(b`:`, b``)
        "

        return def splitAtPump(packet) :List as Pump:
            buf += packet
            def pieces := buf.split(fragment)
            buf := pieces.last()
            return pieces.slice(0, pieces.size() - 1)

    to fromStateMachine(machine) :Pump:
        "
        A pump from a state machine. Any state machine which operates on a
        stream of characters or ints should be acceptable; the resulting pump
        will map from segments of the stream (strings or bytestrings) to
        outputs of the state machine.

        The state machine should have the following methods:
        * .getStateGuard() should return a guard for the machine state
        * .getInitialState() should return a pair of the initial state and
          number of characters required 
        * .advance(state, data :List) passes the current state and the
          expected number of characters in a list, and should return a pair of
          the next state and number of characters required
        * .results() should return the accumulated outputs of the state
          machine since the last call to .results()
        "

        def State := machine.getStateGuard()
        def [var state :State, var size :Int] := machine.getInitialState()
        var buf := []

        return def statefulPump(packet) :List as Pump:
            buf += _makeList.fromIterable(packet)
            while (buf.size() >= size):
                def data := buf.slice(0, size)
                buf slice= (size, buf.size())
                def [newState, newSize] := machine.advance(state, data)
                state := newState
                size := newSize
            return machine.results()

def testMakePumpNull(assert):
    def pump := makePump.null()
    assert.equal(pump(42), [endOfStream])

def testMakePumpId(assert):
    def pump := makePump.id()
    var l := []
    for x in (0..4):
        l += pump(x)
    assert.equal(l, [0, 1, 2, 3, 4])

def testMakePumpTakeWhile(assert):
    def pump := makePump.takeWhile(fn x { x % 3 != 2 })
    var l := []
    for x in (0..5):
        def [_eos, packets] := trimPackets(pump(x))
        l += packets
    assert.equal(l, [0, 1])

def testMakePumpFilter(assert):
    def pump := makePump.filter(fn x { x % 2 == 1 })
    var l := []
    for x in (0..5):
        def [_eos, packets] := trimPackets(pump(x))
        l += packets
    assert.equal(l, [1, 3, 5])

def testMakePumpScan(assert):
    def pump := makePump.scan(fn z, x { z + x }, 0)
    var l := []
    for x in (1..4):
        def [_eos, packets] := trimPackets(pump(x))
        l += packets
    assert.equal(l, [0, 1, 3, 6, 10])

def testMakePumpEncodeUTF8(assert):
    def pump := makePump.encode(UTF8)
    assert.equal(pump("⌵"), [b`$\xe2$\x8c$\xb5`])

def testMakePumpSplitAtStr(assert):
    def pump := makePump.splitAt(":", "")
    assert.equal(pump("a:b:c"), ["a", "b"])
    assert.equal(pump(":"), ["c"])

def testMakePumpSplitAtBytes(assert):
    def pump := makePump.splitAt(b`:`, b``)
    assert.equal(pump(b`a:b:c`), [b`a`, b`b`])
    assert.equal(pump(b`:`), [b`c`])

def testPumpPairSingle(assert):
    def [sink, source] := makePumpPair(makePump.id())
    def [p, r] := Ref.promise()
    object testSink as Sink:
        to run(packet):
            assert.equal(packet, 42)
        to complete():
            r.resolve(null)
        to abort(problem):
            r.smash(problem)
    flow(source, testSink)
    sink(42)
    sink.complete()
    return p

def testPumpPairPostHoc(assert):
    def [sink, source] := makePumpPair(makePump.id())
    def [p, r] := Ref.promise()
    object testSink as Sink:
        to run(packet):
            assert.fail(`Didn't expect packet $packet`)
        to complete():
            r.resolve(null)
        to abort(problem):
            r.smash(problem)
    flow(source, testSink)
    sink.complete()
    return p

unittest([
    testMakePumpNull,
    testMakePumpId,
    testMakePumpTakeWhile,
    testMakePumpFilter,
    testMakePumpScan,
    testMakePumpEncodeUTF8,
    testMakePumpSplitAtStr,
    testMakePumpSplitAtBytes,
    testPumpPairSingle,
    testPumpPairPostHoc,
])

def fuse(first, second) :Pump as DeepFrozen:
    "Fuse two pumps into a single pump."

    # Note that we take advantage of pumps being defined synchronously; this
    # should be async in the future. ~ C.

    # XXX I am sorry for the layout of this function. It has a certain
    # recursive nature to it that I find appealing, though... ~ C.
    return def fusedPump(packet) as Pump:
        def [var eos, ps] := trimPackets(first(packet))
        var rv := []
        for p in (ps):
            def [eosNext, psNext] := trimPackets(second(p))
            eos |= eosNext
            rv += psNext
        return if (eos) { rv.with(endOfStream) } else { rv }

def testFuseSieve(assert):
    def pump := fuse(makePump.filter(fn x { x % 2 == 0 }),
                     makePump.filter(fn x { x % 3 == 0 }))
    var l := []
    for x in (0..10):
        def [_eos, packets] := trimPackets(pump(x))
        l += packets
    assert.equal(l, [0, 6])

def testFuseNull(assert):
    def pump := fuse(makePump.null(), makePump.filter(fn x { x % 3 == 0 }))
    for x in (0..10):
        assert.equal(trimPackets(pump(x)), [true, []])

def testFuseTakeWhile(assert):
    def pump := fuse(makePump.id(), makePump.takeWhile(fn x { x < 5 }))
    var l := []
    for x in (0..10):
        def [_eos, packets] := trimPackets(pump(x))
        l += packets
    assert.equal(l, [0, 1, 2, 3, 4])

unittest([
    testFuseSieve,
    testFuseNull,
    testFuseTakeWhile,
])

object alterSink as DeepFrozen:
    "A collection of decorative attachments for sinks."

    to fusePump(pump, sink) :Sink:
        "Attach `pump` to `sink`."

        def [fuseSink, source] := makePumpPair(pump)
        flow(source, sink)
        return fuseSink

    to map(f, sink) :Sink:
        "Map over packets coming into `sink` with the function `f`."

        return object mapSink extends sink as Sink:
            to run(packet) :Vow[Void]:
                return sink(f(packet))

    to takeWhile(predicate, sink) :Sink:
        "Accept packets into `sink` as long as `predicate(packet)` holds."

        return alterSink.fusePump(makePump.takeWhile(predicate), sink)

    to filter(predicate, sink) :Sink:
        "Filter packets coming into `sink` with the `predicate`."

        return alterSink.fusePump(makePump.filter(predicate), sink)

    to scan(f, z, sink) :Sink:
        "Accumulate a partial fold of `f` with `z` as the starting value."

        return alterSink.fusePump(makePump.scan(f, z), sink)

    to encodeWith(codec, sink) :Sink:
        "Encode packets coming into `sink` with the `codec`."

        return alterSink.fusePump(makePump.encode(codec), sink)

    to decodeWith(codec, sink, => withExtras :Bool := false) :Sink:
        "Decode packets coming into `sink` with the `codec`."

        def pump := makePump.decode(codec, => withExtras)
        return alterSink.fusePump(pump, sink)

def testAlterSinkMap(assert):
    def [l, sink] := makeSink.asList()
    def mapSink := alterSink.map(fn x { x + 1 }, sink)
    mapSink(1)
    mapSink(2)
    mapSink.complete()
    return assert.willEqual(l, [2, 3])

def testAlterSinkFilter(assert):
    def [l, sink] := makeSink.asList()
    def filterSink := alterSink.filter(fn x { x % 2 == 0 }, sink)
    for i in (0..4):
        filterSink(i)
    filterSink.complete()
    return assert.willEqual(l, [0, 2, 4])

def testAlterSinkScan(assert):
    def [l, sink] := makeSink.asList()
    def scanSink := alterSink.scan(fn z, x { z + x }, 0, sink)
    for i in (1..5):
        scanSink(i)
    scanSink.complete()
    return assert.willEqual(l, [0, 1, 3, 6, 10, 15])

def testAlterSinkEncodeWithUTF8(assert):
    def [l, sink] := makeSink.asList()
    def encodeSink := alterSink.encodeWith(UTF8, sink)
    encodeSink("⌵")
    encodeSink.complete()
    return assert.willEqual(l, [b`$\xe2$\x8c$\xb5`])

def testAlterSinkDecodeWithUTF8(assert):
    def [l, sink] := makeSink.asList()
    def decodeSink := alterSink.decodeWith(UTF8, sink)
    decodeSink(b`$\xe2$\x8c$\xb5`)
    decodeSink.complete()
    return assert.willEqual(l, ["⌵"])

def testAlterSinkDecodeWithExtrasUTF8(assert):
    def [l, sink] := makeSink.asList()
    def decodeSink := alterSink.decodeWith(UTF8, sink, "withExtras" => true)
    decodeSink(b`$\xe2`)
    decodeSink(b`$\x8c`)
    decodeSink(b`$\xb5`)
    decodeSink.complete()
    return when (l) -> { assert.willEqual("".join(l), "⌵") }

unittest([
    testAlterSinkMap,
    testAlterSinkFilter,
    testAlterSinkScan,
    testAlterSinkEncodeWithUTF8,
    testAlterSinkDecodeWithUTF8,
    testAlterSinkDecodeWithExtrasUTF8,
])

object alterSource as DeepFrozen:
    "A collection of decorative attachments for sources."

    to fusePump(pump, source):
        "Fuse `pump` to `source`."

        def [fuseSink, fuseSource] := makePumpPair(pump)
        return def fusingSource(sink) :Vow[Void] as Source:
            return when (source(fuseSink), fuseSource(sink)) -> { null }

    to map(f, source) :Source:
        "Map over packets coming out of `source` with the function `f`."

        return def mapSource(sink) :Vow[Void] as Source:
            return source(alterSink.map(f, sink))

    to takeWhile(predicate, source) :Source:
        "Allow packets out of `source` as long as `predicate(packet)` holds."

        return alterSource.fusePump(makePump.takeWhile(predicate), source)

    to filter(predicate, source) :Source:
        "Filter packets coming out of `source` with `predicate`."

        return alterSource.fusePump(makePump.filter(predicate), source)

    to scan(f, z, source) :Source:
        "Produce partial folds of `source` with function `f` and initial value
         `z`."

        return alterSource.fusePump(makePump.scan(f, z), source)

    to encodeWith(codec, source) :Source:
        "Encode packets coming out of `source` with `codec`."

        return alterSource.fusePump(makePump.encode(codec), source)

    to decodeWith(codec, source, => withExtras :Bool := false) :Source:
        "Decode packets coming out of `source` with `codec`."

        def pump := makePump.decode(codec, => withExtras)
        return alterSource.fusePump(pump, source)

def testAlterSourceMap(assert):
    def [l, sink] := makeSink.asList()
    def source := makeSource.fromIterable([1, 2, 3])
    def mapSource := alterSource.map(fn [_, snd] { snd }, source)
    return when (flow(mapSource, sink)) ->
        assert.willEqual(l, [1, 2, 3])

def testAlterSourceFilter(assert):
    def [l, sink] := makeSink.asList()
    def source := makeSource.fromIterable([0, 1, 2, 3, 4])
    def filterSource := alterSource.filter(fn [_, x] { x % 2 == 0 }, source)
    return when (flow(filterSource, sink)) ->
        assert.willEqual(l, [0, 2, 4])

unittest([testAlterSourceMap, testAlterSourceFilter])
