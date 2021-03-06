import "unittest" =~ [=> unittest :Any]
import "lib/enum" =~ [=> makeEnum]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/json" =~ [=> JSON]
import "lib/streams" =~ [
    => Sink :DeepFrozen,
    => alterSink :DeepFrozen,
    => flow :DeepFrozen,
    => makePump :DeepFrozen,
]
import "lib/sealing" =~ [=> makeBrandPair]
exports (makeAMPServer, makeAMPClient, makeAMPPool)

# Copyright (C) 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Either we await a key length, value length, or string.
def [AMPState :DeepFrozen,
     KEY :DeepFrozen,
     VALUE :DeepFrozen,
     STRING :DeepFrozen
] := makeEnum(["AMP key length", "AMP value length", "AMP string"])

def makeAMPPacketMachine() as DeepFrozen:
    def packetMap := [].asMap().diverge(Str, Str)
    var pendingKey :Str := ""
    def results := [].diverge(Map)

    return object AMPPacketMachine:
        to getStateGuard():
            return AMPState

        to getInitialState():
            return [KEY, 2]

        to advance(state :AMPState, data):
            return switch (state):
                match ==KEY:
                    # We have two bytes of data representing key length.
                    # Except the first byte is always 0x00.
                    def len := data[1]
                    # If the length was zero, then it was the end-of-packet
                    # marker. Go ahead and snip the packet.
                    if (len == 0):
                        results.push(packetMap.snapshot())
                        packetMap.clear()
                        [KEY, 2]
                    else:
                        # Otherwise, get the actual key string.
                        [STRING, len]
                match ==VALUE:
                    # Same as the KEY case, but without EOP.
                    def len := (data[0] << 8) | data[1]
                    [STRING, len]
                match ==STRING:
                    # First, decode.
                    def s := UTF8.decode(_makeBytes.fromInts(data), null)
                    # Was this for a key or a value? We'll guess based on
                    # whether there's a pending key.
                    if (pendingKey.isEmpty()):
                        # This was a key.
                        pendingKey := s
                        [VALUE, 2]
                    else:
                        # This was a value.
                        packetMap[pendingKey] := s
                        pendingKey := ""
                        [KEY, 2]

        to results():
            def rv := results.snapshot()
            results.clear()
            return rv


# A variety of error-handling approaches are possible here; in this case,
# we'll let _makeBytes.fromInts/1 throw an exception. ~ C.
def packSize(i :Int) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([i >> 8, i & 0xff])


def packAMPPacket(packet :Map[Str, Str]) :Bytes as DeepFrozen:
    def pieces := [].diverge()
    for via (UTF8.encode) key => via (UTF8.encode) value in (packet):
        def keySize :(Int <= 0xff) := key.size()
        pieces.push(packSize(keySize))
        pieces.push(key)
        def valueSize :(Int <= 0xffff) := value.size()
        pieces.push(packSize(valueSize))
        pieces.push(value)
    pieces.push(b`$\x00$\x00`)
    return b``.join(pieces)


def testPackAMPPacket(assert):
    def box := packAMPPacket([
        "_ask" => "23",
        "_command" => "Sum",
        "a" => "13",
        "b" => "81",
    ])
    assert.equal(box,
        b`$\x00$\x04_ask$\x00$\x0223$\x00$\x08_command$\x00$\x03Sum$\x00$\x01a$\x00$\x0213$\x00$\x01b$\x00$\x0281$\x00$\x00`)

unittest([
    testPackAMPPacket,
])


def makeAMP(sink, handler) as DeepFrozen:
    var serial :Int := 0
    def pending := [].asMap().diverge(Int, Any)

    def process(box) :Void:
        # Either it's a new command, a successful reply, or a failure.
        switch (box):
            match [=> _command, => _ask := null] | arguments:
                # New command.
                if (_ask == null):
                    # Send-only.
                    # traceln(`AMP: <- $_command (sendOnly)`)
                    handler<-(_command, arguments)
                    null
                else:
                    def _answer := _ask
                    # traceln(`AMP: <- $_command (send)`)
                    def result := handler<-(_command, arguments)
                    when (result) ->
                        # traceln(`AMP: -> $_command (reply)`)
                        def packet := result | [=> _answer]
                        sink<-(packAMPPacket(packet))
                    catch _error_description:
                        # Even errors will be sent!
                        def packet := result | [=> _answer,
                                                => _error_description]
                        # traceln(`AMP: -> $_command (error)`)
                        sink<-(packAMPPacket(packet))
            match [=> _answer] | arguments:
                # Successful reply.
                def answer := _makeInt.fromBytes(UTF8.encode(_answer, null))
                if (pending.contains(answer)):
                    # traceln(`AMP: ! $_answer (success)`)
                    pending[answer].resolve(arguments)
                    pending.removeKey(answer)
                else:
                    traceln(`AMP: Received Martian answer $answer`)
            match [=> _error] | arguments:
                # Error reply.
                def error := _makeInt.fromBytes(_error)
                if (pending.contains(error)):
                    # traceln(`AMP: ! $_error (error)`)
                    def [=> _error_description := "unknown error"] | _ := arguments
                    pending[error].smash(_error_description)
                    pending.removeKey(error)
                else:
                    traceln(`AMP: Received Martian error $error`)
            match _:
                traceln("AMP: Received unknwon AMP box", box)

    return object AMP:
        to sink() :Sink:
            object AMPSink as Sink:
                to run(box):
                    return process<-(box)
                to abort(problem):
                    handler.abort(problem)
                to complete():
                    handler.complete()
            def boxPump := makePump.fromStateMachine(makeAMPPacketMachine())
            return alterSink.fusePump(boxPump, AMPSink)

        to send(command :Str, arguments :Map, expectReply :Bool):
            return if (expectReply):
                # traceln(`AMP: ? $serial`)
                # traceln(`AMP: -> $command (send)`)
                def packet := arguments | ["_command" => command, "_ask" => `$serial`]
                def resolver := def reply
                pending[serial] := resolver
                serial += 1
                sink<-(packAMPPacket(packet))
                reply
            else:
                # Send-only. (And there's no reply at all, no, there's no
                # reply at all...) ~ C.
                # traceln(`AMP: -> $command (sendOnly)`)
                sink<-(packAMPPacket(arguments))
                null


def makeAMPServer(endpoint) as DeepFrozen:
    return def AMPServerEndpoint.listenStream(handler):
        def f(source, sink):
            def amp := makeAMP(sink, handler)
            flow(source, amp.sink())
        endpoint.listenStream(f)


def makeAMPClient(endpoint) as DeepFrozen:
    return def AMPClientEndpoint.connectStream(handler):
        return when (def [source, sink] := endpoint.connectStream()) ->
            def amp := makeAMP(sink, handler)
            flow(source, amp.sink())
            amp


def deepFulfilled(p) as DeepFrozen:
    "Generic version of promiseAllFulfilled over lists and maps."

    return when (p) ->
        if (p =~ l :Any[List, Map]):
            promiseAllFulfilled([for x in (l) deepFulfilled(x)])
        else:
            p


def makeAMPPool(bootExpression :DeepFrozen, endpoint) as DeepFrozen:
    "
    Make an AMP server which receives connections from worker clients and
    distributes work among them.
    "

    def bootMAST :Str := {
        def ctx := makeMASTContext()
        ctx(bootExpression.expand())
        _makeStr.fromChars([for i in (ctx.bytes().asList()) '\x00' + i])
    }
    traceln(`Boot MAST size ${bootMAST.size()}`)

    var clientId :Int := 0
    def clients := [].asMap().diverge()
    def callbacks := [].asSet().diverge()
    def runCallbacks(proxy):
        for cb in (callbacks):
            cb<-(proxy)

    endpoint.listenStream(fn source, sink {
        def client :Int := clientId += 1

        object poolHandler {
            to run(command, arguments) {
                traceln(`Pool client $client: Command $command arguments $arguments`)
            }
            to abort(problem) {
                traceln(`Pool client $client uncleanly lost: $problem`)
                traceln.exception(problem)
                clients.removeKey(client)
            }
            to complete() {
                traceln(`Pool client $client cleanly exited`)
                clients.removeKey(client)
            }
        }
        def amp := makeAMP(sink, poolHandler)

        def ampCall(target, verb, arguments, namedArguments, => FAIL) {
            return when (target, deepFulfilled(arguments),
                         deepFulfilled(namedArguments)) -> {
                try {
                    def payload := JSON.encode([
                        => target,
                        => verb,
                        => arguments,
                        => namedArguments,
                    ], FAIL)
                    def rv := amp.send("call", [=> payload], true)
                    when (rv) -> { JSON.decode(rv["result"], FAIL) }
                } catch problem {
                    traceln(`problem in ampCall($target, $verb, $arguments)`)
                    traceln.exception(problem)
                    Ref.broken(problem)
                }
            }
        }

        def ampNoun(binding :Vow[Str]) {
            def slot := ampCall(binding, "get", [], [].asMap())
            return when (slot) -> { ampCall(slot, "get", [], [].asMap()) }
        }

        def [sealRef, unsealRef] := makeBrandPair("AMP proxy")
        def refBrand := sealRef.getBrand()
        def unboxing(arg) {
            return switch (arg) {
                match xs :List { [for x in (xs) unboxing(x)] }
                match _ {
                    def box := arg<-_sealedDispatch(refBrand)
                    return when (box) -> {
                        escape ej {
                            unsealRef.unsealing(box, ej)
                        } catch _ { arg }
                    }
                }
            }
        }

        object makeProxy {
            to decode(json) {
                return switch (json) {
                    match xs :List { [for x in (xs) makeProxy.decode(x)] }
                    match xs :Map {
                        [for k => v in (xs) k => makeProxy.decode(v)]
                    }
                    match `$$ref:@{via (_makeInt) next}` {
                        def resolutionBox
                        Ref.makeProxy(makeProxy.on(next), resolutionBox,
                                      "resolved" => true)
                    }
                    match `$$$$@x` { x }
                    match x { x }
                }
            }

            to on(target :Int) {
                def self := `$$ref:$target`

                return object proxyHandler {
                    to handleSend(verb :Str, args :List, namedArgs :Map) {
                        return switch ([verb, args]) {
                            match [=="_sealedDispatch", [b]] {
                                when (b) -> {
                                    if (_equalizer.sameYet(b, refBrand)) {
                                        sealRef.seal(self)
                                    }
                                }
                            }
                            match [=="_whenMoreResolved", [cb]] {
                                # 'More resolved?' I am your proxy! I am the
                                # most resolved you are *ever* gonna get!
                                cb<-(proxyHandler)
                            }
                            match _ {
                                def argRefs := [for arg in (args) {
                                    unboxing(arg)
                                }]
                                # XXX we could reflect FAIL, but we'd need to
                                # reflect arbitrary refs. Maybe that's coming up?
                                def namedArgRefs := [for k => v in (namedArgs) ? (k != "FAIL") k => {
                                    unboxing(v)
                                }]
                                def rv := ampCall(self, verb,
                                                  argRefs, namedArgRefs)
                                when (rv) -> { makeProxy.decode(rv) }
                            }
                        }
                    }
                    to handleSendOnly(verb :Str, args :List, namedArgs :Map) {
                        # XXX
                        return proxyHandler.handleSend(verb, args, namedArgs)
                    }
                }
            }
        }

        # Boot strategy starting with some custom MAST. Upload the MAST in
        # slices with the "load" command, and then use the "bootstrap" command
        # to call it.
        # in a single call! Hope it's small enough.
        traceln(`Pool client $client: Copying boot module`)
        # Use 32KiB chunks for upload.
        def chunkSize := 0x8_000
        def chunks := [for i in (0..(bootMAST.size() // chunkSize)) {
            def start := i * chunkSize
            def stop := (i + 1) * chunkSize
            def mast := bootMAST.slice(start, stop)
            traceln(`Pool client $client: Boot slice $i ($start..!$stop)`)
            amp.send("load", [=> mast], true)
        }]
        def root := when (promiseAllFulfilled(chunks)) -> {
            traceln(`Pool client $client: Booting`)
            amp.send("bootstrap", [].asMap(), true)
        }
        clients[client] := when (root) -> {
            traceln(`Pool client $client: Booted root $root`)
            def ["value" => bootRef] := root
            def proxy := makeProxy.decode(JSON.decode(bootRef, null))
            runCallbacks<-(proxy)
            proxy
        }

        flow(source, amp.sink())
    })

    return def poolController.whenClient(cb):
        callbacks.include(cb)
        for proxy in (clients):
            cb<-(proxy)
