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


import "lib/enum" =~ [=> makeEnum]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/tubes" =~ [
    => nullPump :DeepFrozen,
     => makeMapPump :DeepFrozen,
     => makeStatefulPump :DeepFrozen,
     => makePumpTube :DeepFrozen,
     => chain :DeepFrozen,
]

exports (makeAMPServer, makeAMPClient)

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
            switch (state):
                match ==KEY:
                    # We have two bytes of data representing key length.
                    # Except the first byte is always 0x00.
                    def len := data[1]
                    # If the length was zero, then it was the end-of-packet
                    # marker. Go ahead and snip the packet.
                    if (len == 0):
                        results with= (packetMap)
                        packetMap := [].asMap()
                        return [KEY, 2]

                    # Otherwise, get the actual key string.
                    return [STRING, len]
                match ==VALUE:
                    # Same as the KEY case, but without EOP.
                    def len := (data[0] << 8) | data[1]
                    return [STRING, len]
                match ==STRING:
                    # First, decode.
                    def s := UTF8.decode(_makeBytes.fromInts(data), null)
                    # Was this for a key or a value? We'll guess based on
                    # whether there's a pending key.
                    if (pendingKey == ""):
                        # This was a key.
                        pendingKey := s
                        return [VALUE, 2]
                    else:
                        # This was a value.
                        packetMap with= (pendingKey, s)
                        pendingKey := ""
                        return [KEY, 2]

        to results():
            return results


def packAMPPacket(packet) as DeepFrozen:
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


def makeAMP(drain) as DeepFrozen:
    var responder := null
    var buf := []
    var serial :Int := 0
    var pending := [].asMap()

    return object AMP:
        to flowingFrom(upstream):
            null

        to flowAborted(reason):
            null

        to flowStopped(reason):
            null

        to sendPacket(packet :Bytes):
            buf with= (packet)
            when (drain) ->
                if (drain != null):
                    for item in (buf):
                        drain.receive(item)
                    buf := []

        to receive(item):
            # Either it's a new command, a successful reply, or a failure.
            switch (item):
                match [=> _command] | var arguments:
                    # New command.
                    if (responder == null):
                        traceln(`AMP: No responder to handle command`)
                        return

                    def _answer := if (arguments.contains("_ask")) {
                        def [=> _ask] | args := arguments
                        arguments := args
                        _ask
                    } else {null}
                    def result := responder<-(_command, arguments)
                    if (serial != null):
                        when (result) ->
                            def packet := result | [=> _answer]
                            AMP.sendPacket(packAMPPacket(packet))
                        catch _error_description:
                            def packet := result | [=> _answer,
                                                    => _error_description]
                            AMP.sendPacket(packAMPPacket(packet))
                match [=> _answer] | arguments:
                    # Successful reply.
                    def answer := _makeInt.fromBytes(_answer)
                    if (pending.contains(answer)):
                        pending[answer].resolve(arguments)
                        pending without= (answer)
                match [=> _error] | arguments:
                    # Error reply.
                    def error := _makeInt(_error)
                    if (pending.contains(error)):
                        def [=> _error_description := "unknown error"] | _ := arguments
                        pending[error].smash(_error_description)
                        pending without= (error)
                match _:
                    pass

        to send(command :Str, var arguments :Map, expectReply :Bool):
            if (expectReply):
                arguments |= ["_command" => command, "_ask" => `$serial`]
                def [p, r] := Ref.promise()
                pending |= [serial => r]
                serial += 1
                AMP.sendPacket(packAMPPacket(arguments))
                return p
            else:
                AMP.sendPacket(packAMPPacket(arguments))

        to setResponder(r):
            responder := r


def makeAMPServer(endpoint) as DeepFrozen:
    return object AMPServerEndpoint:
        to listen(callback):
            def f(fount, drain):
                def amp := makeAMP(drain)
                chain([
                    fount,
                    makePumpTube(makeStatefulPump(makeAMPPacketMachine())),
                    amp,
                ])
                callback(amp)
            endpoint.listen(f)


def makeAMPClient(endpoint) as DeepFrozen:
    return object AMPClientEndpoint:
        to connect():
            def [fount, drain] := endpoint.connect()
            def amp := makeAMP(drain)
            chain([
                fount,
                makePumpTube(makeStatefulPump(makeAMPPacketMachine())),
                amp,
            ])
            return amp
