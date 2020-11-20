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
    var packetMap :Map := [].asMap()
    var pendingKey :Str := ""
    var results :List := []

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
                        results with= (packetMap)
                        packetMap := [].asMap()
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
                    if (pendingKey == ""):
                        # This was a key.
                        pendingKey := s
                        [VALUE, 2]
                    else:
                        # This was a value.
                        packetMap with= (pendingKey, s)
                        pendingKey := ""
                        [KEY, 2]

        to results():
            return results


def packAMPPacket(packet :Map[Str, Str]) :Bytes as DeepFrozen:
    var buf := []
    for via (UTF8.encode) key => via (UTF8.encode) value in (packet):
        def keySize :(Int <= 0xff) := key.size()
        buf += [0x00, keySize]
        buf += _makeList.fromIterable(key)
        def valueSize :(Int <= 0xffff) := value.size()
        buf += [valueSize >> 8, valueSize & 0xff]
        buf += _makeList.fromIterable(value)
    buf += [0x00, 0x00]
    return _makeBytes.fromInts(buf)


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
    var pending := [].asMap()

    def process(box) :Void:
        # Either it's a new command, a successful reply, or a failure.
        switch (box):
            match [=> _command, => _ask := null] | arguments:
                # New command.
                if (_ask == null):
                    # Send-only.
                    traceln(`AMP: <- $_command (sendOnly)`)
                    handler<-(_command, arguments)
                    null
                else:
                    def _answer := _ask
                    traceln(`AMP: <- $_command (send)`)
                    def result := handler<-(_command, arguments)
                    when (result) ->
                        traceln(`AMP: -> $_command (reply)`)
                        def packet := result | [=> _answer]
                        def packetBytes := packAMPPacket(packet)
                        sink <- (packetBytes)
                    catch _error_description:
                        # Even errors will be sent!
                        def packet := result | [=> _answer,
                                                => _error_description]
                        traceln(`AMP: -> $_command (error)`)
                        sink<-(packAMPPacket(packet))
            match [=> _answer] | arguments:
                # Successful reply.
                def answer := _makeInt.fromBytes(UTF8.encode(_answer, null))
                if (pending.contains(answer)):
                    traceln(`AMP: ! $_answer (success)`)
                    pending[answer].resolve(arguments)
                    pending without= (answer)
            match [=> _error] | arguments:
                # Error reply.
                def error := _makeInt.fromBytes(_error)
                if (pending.contains(error)):
                    traceln(`AMP: ! $_error (error)`)
                    def [=> _error_description := "unknown error"] | _ := arguments
                    pending[error].smash(_error_description)
                    pending without= (error)
            match _:
                pass

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

        to send(command :Str, var arguments :Map, expectReply :Bool):
            return if (expectReply):
                traceln(`AMP: ? $serial`)
                traceln(`AMP: -> $command (send)`)
                arguments |= ["_command" => command, "_ask" => `$serial`]
                def resolver := def reply
                pending |= [serial => resolver]
                serial += 1
                sink<-(packAMPPacket(arguments))
                reply
            else:
                # Send-only. (And there's no reply at all, no, there's no
                # reply at all...) ~ C.
                traceln(`AMP: -> $command (sendOnly)`)
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


def makeAMPPool(bootExpression :Str, endpoint) as DeepFrozen:
    "
    Make an AMP server which receives connections from worker clients and
    distributes work among them.
    "

    var clientId :Int := 0
    def clients := [].asMap().diverge()

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

        # NB: Str is the guard of refs.

        def ampCall(target, verb, arguments, namedArguments) {
            return when (target, promiseAllFulfilled(arguments), namedArguments) -> {
                traceln(`ampCall($target, $verb, $arguments, $namedArguments)`)
                def payload := JSON.encode([
                    => target,
                    => verb,
                    => arguments,
                    => namedArguments,
                ], null)
                def rv := amp.send("call", [=> payload], true)
                when (rv) -> { JSON.decode(rv["result"], null) }
            }
        }

        def ampNoun(binding :Vow[Str]) {
            def slot := ampCall(binding, "get", [], [].asMap())
            return when (slot) -> { ampCall(slot, "get", [], [].asMap()) }
        }

        # Boot strategy, starting with safeScope:
        # 1) Get _makeMap
        # 2) Run _makeMap.fromPairs() for empty map
        # 3) Get _makeList for flex list
        # 4) Upload bootExpression to flex list
        # 5) Snapshot and join flex list to get expr
        # 6) Get eval
        # 7) Run eval(expr, safeScope)
        traceln(`Pool client $client: Booting`)
        def root := amp.send("bootstrap", [].asMap(), true)
        clients[client] := when (root) -> {
            def remoteSafeScope := "$ref:" + root["value"]
            traceln(`Pool client $client: Bootstrap (0) $remoteSafeScope`)

            def makeListBinding := ampCall(remoteSafeScope, "get",
                                           ["&&_makeList"], [].asMap())
            def makeList := ampNoun(makeListBinding)
            traceln(`Pool client $client: Bootstrap (3) $makeList`)

            def emptyList := ampCall(makeList, "run", [], [].asMap())
            var buffer := emptyList
            # Upload 4KiB chunks of code.
            for offset in (0..(bootExpression.size() // 0x100)) {
                def slice := bootExpression.slice(offset * 0x100, (offset + 1) * 0x100)
                buffer := ampCall(buffer, "with", [slice], [].asMap())
            }
            traceln(`Pool client $client: Bootstrap (4) $buffer`)

            def remoteExpr := ampCall(`lit:""`, "join", [buffer], [].asMap())
            traceln(`Pool client $client: Bootstrap (5) $remoteExpr`)

            def evalBinding := ampCall(remoteSafeScope, "get",
                                       ["&&eval"], [].asMap())
            def remoteEval := ampNoun(evalBinding)
            traceln(`Pool client $client: Bootstrap (6) $remoteEval`)

            when (remoteExpr, remoteEval) -> {
                traceln(`Pool client $client: expr: $remoteExpr remoteEval: $remoteEval`)

                # More remote safe tools. We want M in particular.
                def MBinding := ampCall(remoteSafeScope, "get",
                                        ["&&M"], [].asMap())
                def remoteM := ampNoun(MBinding)
                when (remoteM) -> {
                    traceln(`Pool client $client: M $remoteM`)
                }

                def [sealRef, unsealRef] := makeBrandPair("AMP proxy")
                def refBrand := sealRef.getBrand()
                def unboxing(x) {
                    def box := x<-_sealedDispatch(refBrand)
                    return when (box) -> {
                        escape ej {
                            unsealRef.unsealing(box, ej)
                        } catch _ { x }
                    }
                }

                def makeProxyOn(target :Int) {
                    def self := `$$ref:$target`

                    def decode(json) {
                        return switch (json) {
                            match xs :List { [for x in (xs) decode(x)] }
                            match xs :Map {
                                [for k => v in (xs) k => decode(v)]
                            }
                            match `$$ref:@{via (_makeInt) next}` {
                                def resolutionBox
                                Ref.makeProxy(makeProxyOn(next), resolutionBox)
                            }
                            match `$$$$@x` { x }
                            match x { x }
                        }
                    }

                    return object proxyHandler {
                        to handleSend(verb :Str, args :List, namedArgs :Map) {
                            return switch (verb) {
                                match =="_printOn" {
                                    def rv := ampCall(remoteM, "toString",
                                                      [self], [].asMap())
                                    when (rv) -> {
                                        `<proxy ref via AMP to $rv>`
                                    }
                                }
                                match =="_sealedDispatch" ? (args[0] == refBrand) {
                                    sealRef.seal(self)
                                }
                                match _ {
                                    def argRefs := [for arg in (args) {
                                        unboxing(arg)
                                    }]
                                    def namedArgRefs := [for k => v in (namedArgs) ? (k != "FAIL") k => {
                                        unboxing(v)
                                    }]
                                    def rv := ampCall(self, verb,
                                                      argRefs, namedArgRefs)
                                    when (rv) -> { decode(rv) }
                                }
                            }
                        }
                        to handleSendOnly(verb :Str, args :List, namedArgs :Map) {
                            # XXX
                            return proxyHandler.handleSend(verb, args, namedArgs)
                        }
                    }
                }

                def bootedRef := ampCall(remoteEval, "run",
                                         [remoteExpr, remoteSafeScope],
                                         [].asMap())
                when (bootedRef) -> {
                    def `$$ref:@{via (_makeInt) bootedRefHandle}` := bootedRef
                    def proxyHandler := makeProxyOn(bootedRefHandle)
                    def resolutionBox
                    Ref.makeProxy(proxyHandler, resolutionBox)
                }
            }
        }

        flow(source, amp.sink())
    })

    return object poolController:
        match [verb, args, namedArgs]:
            promiseAllFulfilled([for client in (clients) {
                M.send(client, verb, args, namedArgs)
            }])
