import "lib/capn" =~ [=> makeMessageReader :DeepFrozen]
import "lib/enum" =~ [=> makeEnum]
import "lib/streams" =~ [
    => Sink :DeepFrozen,
    => alterSink :DeepFrozen,
    => flow :DeepFrozen,
    => makePump :DeepFrozen,
]
import "fun/capnDemo/message" =~ [=> reader, => makeWriter]

exports (main)

def [MsgState :DeepFrozen,
     SEGMENT_COUNT :DeepFrozen,
     SEGMENT_SIZES :DeepFrozen,
     PADDING :DeepFrozen,
     BODY :DeepFrozen,
] := makeEnum(["capn segment count", "capn segment sizes", "capn padding", "capn message body"])

def makeCapnMessageMachine(limit :Int) as DeepFrozen:
    var segmentCount := 1
    var segmentSizes := []
    var header := []
    var totalBody := 0
    var messages := []
    return object CapnMessageMachine:
        to getStateGuard():
            return MsgState

        to getInitialState():
            return [SEGMENT_COUNT, 4]

        to advance(state :MsgState, data):
            return switch (state):
                match ==SEGMENT_COUNT:
                    segmentCount := (data[0] | data[1] << 8 |
                                     data[2] << 16 | data[3] << 24) + 1
                    header := data
                    [SEGMENT_SIZES, segmentCount * 4]
                match ==SEGMENT_SIZES:

                    for i in (0..!segmentCount):
                        def j := i * 4
                        def segmentSize := (data[j] |
                                            data[j + 1] << 8 |
                                            data[j + 2] << 16 |
                                            data[j + 3] << 24)
                        segmentSizes with= (segmentSize)
                        totalBody += segmentSize
                    if (totalBody > limit):
                        throw(`Message of ${totalBody} bytes is too large`)
                    header += data
                    if (segmentCount % 2 == 0):
                        [PADDING, 4]
                    else:
                        [BODY, totalBody * 8]
                match ==PADDING:
                    [BODY, totalBody]
                match ==BODY:
                    def msg := _makeBytes.fromInts(header + data)
                    messages with= (reader.Message(makeMessageReader(msg).getRoot()))
                    [SEGMENT_COUNT, 4]

        to results():
            return messages

def makeDemo(sink, handler) as DeepFrozen:
    var pending := null

    def process(message) :Void:
        switch (message.message()._which()):
            match ==0:
                # Request.
                def result :Vow[Int] := handler <- (message.message().request().a(),
                                                    message.message().request().b())
                when (result) ->
                    def w := makeWriter()
                    sink <- (w.dump(w.makeMessage("message" => ["response" => w.makeResult("result" => result)])))
            match ==1:
                if (pending != null):
                    pending.resolve(message.message().response().result())
                    pending := null

    return object Demo:
        to sink() :Sink:
            object DemoSink as Sink:
                to run(box):
                    return process<-(box)
                to abort(p):
                    traceln.exception(p)
                to complete():
                    traceln("Goodbye")

            def boxPump := makePump.fromStateMachine(
                makeCapnMessageMachine(64 * 1024 * 1024))
            return alterSink.fusePump(boxPump, DemoSink)

        to send(a :Int, b :Int):
            def r := def reply
            pending := r
            def w := makeWriter()

            def msg := w.dump(w.makeMessage("message" => ["request" => w.makeSum(=> a, => b)]))
            sink <- (msg)
            return reply


def makeDemoServer(endpoint) as DeepFrozen:
    return def DemoServerEndpoint.listenStream(handler):
        def f(source, sink):
            def demo := makeDemo(sink, handler)
            flow(source, demo.sink())
        endpoint.listenStream(f)


def makeDemoClient(endpoint) as DeepFrozen:
    return def DemoClientEndpoint.connectStream(handler):
        return when (def [source, sink] := endpoint.connectStream()) ->
            def demo := makeDemo(sink, handler)
            flow(source, demo.sink())
            demo

def main(argv, => makeTCP4ClientEndpoint, => makeTCP4ServerEndpoint) as DeepFrozen:
    def port := 9876
    switch (argv):
        match [=="-client"]:
            def ep := makeTCP4ClientEndpoint(b`127.0.0.1`, port)
            def client := makeDemoClient(ep)
            def demo := client.connectStream(fn a, b {
                a + b
            })
            when (def result := demo <- send(17, 25)) ->
                traceln("success", result)

        match [=="-server"]:
            def ep := makeTCP4ServerEndpoint(port)
            def server := makeDemoServer(ep)
            server.listenStream(fn a, b {
                traceln("Received", a, b)
                a + b
            })
    return 0
