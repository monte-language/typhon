import "unittest" =~ [=> unittest]
exports (
    Sink, Source,
    makeSink, makeSource,
    flow,
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
        def l := [].diverge()
        def [p, r] := Ref.promise()

        object listSink as Sink:
            to run(packet) :Void:
                l.push(packet)
                return null

            to complete() :Void:
                r.resolve(l.snapshot())

            to abort(problem) :Void:
                r.smash(problem)

        return [p, listSink]

def testMakeSinkAsList(assert):
    def [l, sink] := makeSink.asList()
    return when (sink(1), sink(2), sink(3)) ->
        sink.complete()
        assert.willEqual(l, [1, 2, 3])

def testMakeSinkAsListAbort(assert):
    def [l, sink] := makeSink.asList()
    return when (sink(1), sink(2), sink(3)) ->
        sink.abort("Testing")
        assert.willBreak(l)

unittest([
    testMakeSinkAsList,
    testMakeSinkAsListAbort,
])

object makeSource as DeepFrozen:
    "A maker of several types of sources."

    to fromIterator(iter) :Source:
        return def iterSource(sink :Sink) :Vow[Void] as Source:
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
            return when (sink(packet)) ->
                source(flowSink)

        to complete() :Void:
            r.resolve(null)
            sink.complete()

        to abort(problem) :Void:
            r.smash(problem)
            sink.abort(problem)

    source(flowSink)
    return p

def testFlow(assert):
    def [l, sink] := makeSink.asList()
    def source := makeSource.fromIterable([1, 2, 3])
    return when (flow(source, sink)) ->
        assert.willEqual(l, [[0, 1], [1, 2], [2, 3]])

unittest([testFlow])

object alterSink as DeepFrozen:
    "A collection of decorative attachments for sinks."

    to map(f, sink :Sink) :Sink:
        "Map over packets coming into `sink` with the function `f`."

        return object mapSink extends sink as Sink:
            to run(packet) :Vow[Void]:
                return sink(f(packet))

    to filter(predicate, sink :Sink) :Sink:
        "Filter packets coming into `sink` with the `predicate`."

        return object filterSink extends sink as Sink:
            to run(packet) :Vow[Void]:
                return if (predicate(packet)) { sink(packet) } else { null }

    to scan(f, var z, sink :Sink) :Sink:
        "Accumulate a partial fold of `f` with `z` as the starting value."

        var finished :Bool := false

        return object scanSink extends sink as Sink:
            to run(packet) :Vow[Void]:
                def rv := sink(z)
                z := f(z, packet)
                return rv

            to complete():
                if (finished):
                    throw("scanSink.complete/0: Already finished")
                finished := true
                return when (sink(z)) ->
                    sink.complete()

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
    for i in ([1] * 10):
        scanSink(i)
    scanSink.complete()
    return assert.willEqual(l, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

unittest([
    testAlterSinkMap,
    testAlterSinkFilter,
    testAlterSinkScan,
])

object alterSource as DeepFrozen:
    "A collection of decorative attachments for sources."

    to map(f, source :Source) :Source:
        "Map over packets coming out of `source` with the function `f`."

        return def mapSource(sink :Sink) :Vow[Void] as Source:
            return source(alterSink.map(f, sink))

    to filter(predicate, source :Source) :Source:
        "Filter packets coming out of `source` with `predicate`."

        return def filterSource(sink :Sink) :Vow[Void] as Source:
            return source(alterSink.filter(predicate, sink))

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
