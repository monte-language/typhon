# Copyright (C) 2014 Google Inc. All rights reserved.
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

def [=> simple__quasiParser] := import("lib/simple")
def [=> b__quasiParser, => Bytes] | _ := import("lib/bytes")
def [=> makeEnum] | _ := import("lib/enum")
def [=> UTF8Decode, => UTF8Encode] | _ := import("lib/utf8")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")


def bytesToStatus(bytes :Bytes) :Int:
    var rv :Int := 0
    for byte in bytes:
        rv := rv * 10 + (byte - 48)
    return rv

def testBytesToStatus(assert):
    assert.equal(bytesToStatus(b`200`), 200)

unittest([
    testBytesToStatus,
])


def makeResponse(status :Int, headers):
    return object response:
        to _printOn(out):
            out.print(`<response($status)>`)


def [HTTPState, REQUEST, HEADER, BODY] := makeEnum(
    ["request", "header", "body"])


def makeResponseDrain(resolver):
    var state :HTTPState := REQUEST
    var buf := []
    var headers := null
    var status := null
    var label := null

    return object responseDrain:
        to receive(bytes):
            buf += bytes
            responseDrain.parse()

        to flowingFrom(fount):
            return responseDrain

        to parseStatus(ej):
            def b`HTTP/1.1 @code @label$\r$\n@tail` exit ej := buf
            status := bytesToStatus(code)
            traceln(`Status: $status (${UTF8Decode(label)})`)
            buf := tail
            state := HEADER
            headers := [].asMap().diverge()

        to parseHeader(ej):
            escape final:
                def b`@key: @value$\r$\n@tail` exit final := buf
                buf := tail
                headers[UTF8Decode(key)] := UTF8Decode(value)
            catch _:
                def b`$\r$\n@tail` exit ej := buf
                buf := tail
                state := BODY

        to parse():
            while (true):
                switch (state):
                    match ==REQUEST:
                        responseDrain.parseStatus(__break)
                    match ==HEADER:
                        responseDrain.parseHeader(__break)
                    match ==BODY:
                        # XXX we don't currently parse the body
                        state := REQUEST
                        responseDrain.issueResponse()
                        break

        to issueResponse():
            resolver.resolve(makeResponse(status, headers))


def makeRequest(host :String, resource :String):
    var port :Int := 80
    def headers := [
        "Host" => host,
        "Connection" => "close",
    ].diverge()

    return object request:
        to put(key, value):
            headers[key] := value

        to write(verb, drain):
            drain.receive(UTF8Encode(`$verb $resource HTTP/1.1$\r$\n`))
            for k => v in headers:
                drain.receive(UTF8Encode(`$k: $v$\r$\n`))
            drain.receive(b`$\r$\n`)

        to send(verb :String):
            def endpoint := makeTCP4ClientEndpoint(host, port)
            def [fount, drain] := endpoint.connect()
            def [p, r] := Ref.promise()

            # Write request.
            when (drain) ->
                request.write(verb, drain)
            # Read response.
            fount<-flowTo(makeResponseDrain(r))

            return p

        to get():
            return request.send("GET")


def response := makeRequest("example.com", "/").get()
when (response) ->
    traceln("Finished request with response", response)
