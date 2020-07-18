import "capn/rpc" =~ ["reader" => RPCReader, "makeWriter" => makeRPCWriter]
import "lib/capn" =~ [=> loads]
import "lib/enum" =~ [=> makeEnum]
import "lib/streams" =~ [=> alterSink, => flow, => makePump]
exports (main)

def [CapnFraming :DeepFrozen,
     COUNT :DeepFrozen,
     SIZES :DeepFrozen,
     PADDING :DeepFrozen,
     SEGMENT :DeepFrozen] := makeEnum([
     "Capn segment count",
     "Capn segment sizes",
     "Capn padding",
     "Capn segment",
])

def decodeUInt32(bs :Bytes) :Int as DeepFrozen:
    return bs[0] | (bs[1] << 8) | (bs[2] << 16) | (bs[3] << 24)

# XXX should be parameterized on reader and type

def makeCapnRPCMachine() as DeepFrozen:
    "
    Manage the state required to decode Capn Proto RPC messages from a stream
    of data.

    This maker's return value is meant to be used with
    makePump.fromStateMachine/1 from lib/streams.
    "

    var segmentCount := null
    var segmentSizes := null
    var currentSegment := 0
    var segments := [].diverge()
    var results := [].diverge()

    return object capnRPCMachine:
        to getStateGuard():
            return CapnFraming

        to getInitialState():
            return [COUNT, 4]

        to advance(state :CapnFraming, data):
            return switch (state):
                match ==COUNT:
                    segmentCount := decodeUInt32(data) + 1
                    [SIZES, 4 * segmentCount]
                match ==SIZES:
                    # Split into individual rows.
                    segmentSizes := [for i in (0..!segmentCount) {
                        decodeUInt32(data.slice(i * 4, (i + 1) * 4))
                    }]
                    # If we aren't at a word boundary, then we need to pad.
                    # We've consumed half a word for the count and half a word
                    # for each size, so we need to pad iff the count is even.
                    currentSegment := 0
                    if ((segmentCount % 2).isZero()) { [PADDING, 4] } else {
                        [SEGMENT, segmentSizes[0]]
                    }
                match ==PADDING:
                    currentSegment := 0
                    [SEGMENT, segmentSizes[0]]
                match ==SEGMENT:
                    segments.push(data)
                    currentSegment += 1
                    if (currentSegment >= segmentCount) {
                        # All done, so reset.
                        results.push(segments.snapshot())
                        segments := [].diverge()
                        [COUNT, 4]
                    } else { [SEGMENT, segmentSizes[currentSegment]] }

        to results():
            def rv := results.snapshot()
            results := [].diverge()
            return rv

def fuseCapnSink(sink) as DeepFrozen:
    def segmentPump := makePump.fromStateMachine(makeCapnRPCMachine())
    return alterSink.fusePump(segmentPump, sink)

def makeCapTPTables(source, _sink) as DeepFrozen:
    def questions := [].asMap().diverge()
    def answers := [].asMap().diverge()
    def imports := [].asMap().diverge()
    def ::"exports" := [].asMap().diverge()

    var nextQuestionID := 0
    var nextExportID := 0

    object capTables:
        "
        The four tables of CapTP.

        This sink can directly receive Capn messages.
        "

        to run(bs :Bytes):
            traceln("Got bytes", bs)
            def message := loads(bs, RPCReader, "Message")
            traceln("decoded message", message)
            switch (message._which()):
                match ==8:
                    # Bootstrap.
                    def answerId := message.bootstrap().questionId()
                    traceln("bootstrap", answerId)
                    answers[answerId] := "bootstrap"
                    def writer := makeRPCWriter()
                    def results := writer.makePayload("content" => 0)
                    def ret := writer.makeReturn(=> answerId, => results)

        to complete():
            traceln("time to shutdown")

        to abort(problem):
            traceln("got problem", problem)

        to getQuestion(index :Int):
            return questions[index]

        to getExportTable():
            # XXX attenuate?
            return ::"exports"

    flow(source, capTables)
    return capTables

def serveCapn(endpoint) as DeepFrozen:
    endpoint.listenStream(makeCapTPTables)

def bootstrapCapn(endpoint) as DeepFrozen:
    def [source, sink] := endpoint.connectStream()
    return when (source, sink) ->
        traceln("initialized bootstrap connection", source, sink)
        def writer := makeRPCWriter()
        def bootstrap := writer.makeBootstrap("questionId" => 0)
        def message := writer.makeMessage(=> bootstrap)
        def bs := writer.dump(message)
        traceln("message", message, "bytes", bs)
        when (sink(bs)) ->
            traceln("sent bootstrap, setting up tables")
            makeCapTPTables(source, sink)

def main(_argv, => makeTCP4ServerEndpoint, => makeTCP4ClientEndpoint) as DeepFrozen:
    def serverEndpoint := makeTCP4ServerEndpoint(2323)
    def clientEndpoint := makeTCP4ClientEndpoint(b`127.0.0.1`, 2323)
    traceln("endpoints", serverEndpoint, clientEndpoint)
    def server := serveCapn(serverEndpoint)
    return when (server) ->
        traceln("started server")
        def client := bootstrapCapn(clientEndpoint)
        when (client) ->
            traceln("bootstrapped client", client)
            0
