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

def [=> bytesToInt] | _ := import.script("lib/atoi")
def [=> makeEnum] | _ := import.script("lib/enum")
def [=> UTF8] | _ := import.script("lib/codec/utf8")
def [=> makeMapPump] := import.script("lib/tubes/mapPump")
def [=> makePumpTube] := import.script("lib/tubes/pumpTube")


def lowercase(s :Str, _):
    return s.toLowerCase()


def makeCommonHeaders(contentLength :NullOk[Int]):
    return object commonHeaders:
        to _printOn(out):
            out.print("<common HTTP headers: ")
            out.print(`Content length: $contentLength`)
            out.print(">")

        to finiteBody() :Bool:
            return contentLength != null

        to smallBody() :Bool:
            return contentLength != null && contentLength < 1024 * 1024


def makeResponse(status :Int, commonHeaders, extraHeaders, body):
    return object response:
        to _printOn(out):
            out.print(`<response $status: $commonHeaders ($extraHeaders)>`)

        to getBody():
            return body


def [HTTPState, REQUEST, HEADER, BODY, BUFFERBODY, FOUNTBODY] := makeEnum(
    ["request", "header", "body", "body (buffered)", "body (streaming)"])


def makeResponseDrain(resolver):
    var state :HTTPState := REQUEST
    var buf := []
    var headers := null
    var status :NullOk[Int] := null
    var label := null

    var contentLength :NullOk[Int] := null
    var commonHeaders := null

    return object responseDrain:
        to receive(bytes):
            buf += bytes
            responseDrain.parse()

        to flowingFrom(fount):
            return responseDrain

        to flowAborted(reason):
            traceln(`Flow aborted: $reason`)

        to flowStopped(reason):
            traceln(`End of response: $reason`)

        to parseStatus(ej):
            def b`HTTP/1.1 @{via (bytesToInt) statusCode} @{via (UTF8.decode) label}$\r$\n@tail` exit ej := buf
            status := statusCode
            traceln(`Status: $status ($label)`)
            buf := tail
            state := HEADER
            headers := [].asMap().diverge()

        to parseHeader(ej):
            escape final:
                def b`@{via (UTF8.decode) key}: @value$\r$\n@tail` exit final := buf
                buf := tail
                switch (key):
                    match via (lowercase) =="content-length":
                        contentLength := bytesToInt(value, ej)
                    match header:
                        headers[header] := UTF8.decode(value, null)
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
                        commonHeaders := makeCommonHeaders(contentLength)
                        if (commonHeaders.finiteBody()):
                            traceln("Currently expecting finite body")
                            if (commonHeaders.smallBody()):
                                traceln("Body is small; will buffer in memory")
                                state := BUFFERBODY
                            else:
                                traceln("Body isn't small")
                                state := FOUNTBODY
                    match ==BUFFERBODY:
                        if (buf.size() >= contentLength):
                            def body := buf.slice(0, contentLength)
                            buf := buf.slice(contentLength, buf.size())
                            responseDrain.finalize(body)
                        else:
                            break
                    match ==FOUNTBODY:
                        traceln("I'm not prepared to do this yet!")
                        throw("Couldn't do fount body!")

        to finalize(body):
            def response := makeResponse(status, commonHeaders,
                                         headers.snapshot(), body)
            resolver.resolve(response)


def makeRequest(host :Str, resource :Str):
    var port :Int := 80
    def headers := [
        "Host" => host,
        "Connection" => "close",
    ].diverge()

    return object request:
        to put(key, value):
            headers[key] := value

        to write(verb, drain):
            drain.receive(UTF8.encode(`$verb $resource HTTP/1.1$\r$\n`, null))
            for k => v in headers:
                drain.receive(UTF8.encode(`$k: $v$\r$\n`, null))
            drain.receive(b`$\r$\n`)

        to send(verb :Str):
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
    traceln(UTF8.decode(response.getBody(), null))
