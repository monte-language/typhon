import "capn/rpc" =~ ["reader" => RPCReader, "makeWriter" => makeRPCWriter]
import "lib/capn" =~ [=> loads, => makeMessageReader]
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

def makeCapTPTables(source, sink) as DeepFrozen:
    "Prepare the four tables."

    def questions := [].asMap().diverge()
    def answers := [].asMap().diverge()
    def imports := [].asMap().diverge()
    # We always export the safe scope.
    def ::"exports" := [=> safeScope].diverge()

    var nextQuestionID := 0
    def nextQuestion():
        return nextQuestionID += 1
    var nextExportID := 1

    object capTables:
        "
        The four tables of CapTP.

        This sink can directly receive Capn messages.
        "

        to run(bs :Bytes):
            traceln("Got bytes", bs)
            traceln("Capn skeleton", makeMessageReader(bs).getRoot())
            def message := loads(bs, RPCReader, "Message")
            traceln("Capn message", message)
            return switch (message._which()):
                match ==3:
                    # Return.
                    def ::"return" := message."return"()
                    def questionId := ::"return".answerId()
                    def results := ::"return".results()
                    traceln("Return: question", questionId, "results", results)
                    questions[questionId] := results.content()
                    # Finish the question.
                    def writer := makeRPCWriter()
                    def finish := writer.makeFinish(=> questionId)
                    def message := writer.makeMessage(=> finish)
                    def bs := writer.dump(message)
                    sink(bs)
                match ==4:
                    # Finish.
                    def answerId := message.finish().questionId()
                    traceln("Finish: answer", answerId)
                    answers.removeKey(answerId)
                match ==8:
                    # Bootstrap.
                    def answerId := message.bootstrap().questionId()
                    traceln("Bootstrap: answer", answerId)
                    answers[answerId] := null
                    def writer := makeRPCWriter()
                    # Safe scope is at export 0.
                    def senderHosted := 0
                    def capTable := [[=> senderHosted]]
                    # The bootstrap return needs to have null content.
                    def results := writer.makePayload("content" => 0,
                                                      => capTable)
                    def ::"return" := writer.makeReturn(=> answerId, => results)
                    def message := writer.makeMessage(=> ::"return")
                    def bs := writer.dump(message)
                    sink(bs)
                match i:
                    traceln("Unknown message type", i,
                            makeMessageReader(bs).getRoot())

        to complete():
            traceln("time to shutdown")

        to abort(problem):
            traceln("got problem", problem)
            traceln.exception(problem)

        to getQuestion(index :Int):
            return questions[index]

        to getExportTable():
            # XXX attenuate?
            return ::"exports"

        to bootstrap():
            "Request the least-powerful interface from the other side."
            def writer := makeRPCWriter()
            def questionId := nextQuestion()
            def bootstrap := writer.makeBootstrap(=> questionId)
            def message := writer.makeMessage(=> bootstrap)
            def bs := writer.dump(message)
            traceln("Requested bootstrap", questionId)
            return when (sink(bs)) -> { questionId }

    flow(source, capTables)
    return capTables

def serveCapn(endpoint) as DeepFrozen:
    endpoint.listenStream(makeCapTPTables)

def bootstrapCapn(endpoint) as DeepFrozen:
    def [source, sink] := endpoint.connectStream()
    return when (source, sink) ->
        traceln("Initialized bootstrap connection", source, sink)
        def tables := makeCapTPTables(source, sink)
        traceln("Created client tables", tables)
        def bs := tables.bootstrap()
        when (bs) ->
            traceln("Bootstrapped", bs)
            tables

def main(_argv, => makeTCP4ServerEndpoint, => makeTCP4ClientEndpoint) as DeepFrozen:
    def serverEndpoint := makeTCP4ServerEndpoint(2323)
    def clientEndpoint := makeTCP4ClientEndpoint(b`127.0.0.1`, 2323)
    traceln("Endpoints", serverEndpoint, clientEndpoint)
    def server := serveCapn(serverEndpoint)
    return when (server) ->
        traceln("Started server")
        def clientTables := bootstrapCapn(clientEndpoint)
        when (clientTables) ->
            traceln("Boostrapped client", clientTables)
            0
    catch problem:
        traceln("Welp...", problem)
        traceln.exception(problem)
        1
