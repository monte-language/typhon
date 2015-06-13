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

def [=> strToInt] | _ := import("lib/atoi")
def [=> makeEnum] | _ := import("lib/enum")
def [=> UTF8] | _ := import("lib/codec/utf8")
def [=> nullPump] := import("lib/tubes/nullPump")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makeStatefulPump] := import("lib/tubes/statefulPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")
def [=> chain] := import("lib/tubes/chain")

# Either we await a key length, value length, or string.
def [AMPState, KEY, VALUE, STRING] := makeEnum([
    "AMP key length", "AMP value length", "AMP string"])

def makeAMPPacketMachine():
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
                    def s := UTF8.decode(data, null)
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


def packAMPPacket(packet):
    var buf := []
    for via (UTF8.encode) key => via (UTF8.encode) value in packet:
        def keySize :(Int <= 0xff) := key.size()
        buf += [0x00, keySize]
        buf += key
        def valueSize :(Int <= 0xffff) := value.size()
        buf += [valueSize >> 8, valueSize & 0xff]
        buf += value
    buf += [0x00, 0x00]
    return buf


def makeAMP(drain, responder):
    var buf := []
    var serial :Int := 0
    var pending := [].asMap()

    return object AMP:
        to flowingFrom(upstream):
            null

        to flowStopped(reason):
            null

        to sendPacket(packet):
            buf with= (packet)
            when (drain) ->
                if (drain != null):
                    for item in buf:
                        drain.receive(item)
                    buf := []

        to receive(item):
            # Either it's a new command, a successful reply, or a failure.
            switch (item):
                match [=> _command] | var arguments:
                    # New command.
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
                match [=> _answer] | arguments:
                    # Successful reply.
                    def via (strToInt) answer := _answer
                    if (pending.contains(answer)):
                        pending[answer].resolve(arguments)
                        pending without= (answer)
                match [=> _error] | arguments:
                    # Error reply.
                    def via (strToInt) error := _error
                    if (pending.contains(error)):
                        def [=> _error_description := "unknown error"] | _ := arguments
                        pending[answer].smash(_error_description)
                        pending without= (answer)
                match _:
                    pass

        to send(var packet, expectReply :Bool):
            if (expectReply):
                packet |= ["_ask" => serial]
                def [p, r] := Ref.promise()
                pending |= [serial => r]
                serial += 1
                AMP.sendPacket(packAMPPacket(packet))
                return p
            else:
                AMP.sendPacket(packAMPPacket(packet))


def makeAMPServer(endpoint):
    return object AMPServerEndpoint:
        to listen(responder):
            def f(var fount, drain):
                chain([
                    fount,
                    makePumpTube(makeStatefulPump(makeAMPPacketMachine())),
                    makeAMP(drain, responder),
                ])
            endpoint.listen(f)


[=> makeAMPServer]
