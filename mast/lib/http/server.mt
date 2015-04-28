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

def [=> b__quasiParser] | _ := import("lib/bytes")
def [=> UTF8Decode, => UTF8Encode] | _ := import("lib/utf8")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")
def [=> makeEnum] | _ := import("lib/enum")
def [=> percentDecode] | _ := import("lib/percent")

def [RequestState, REQUEST, HEADER, BODY] := makeEnum(
    ["request", "header", "body"])

def makeRequestPump():
    var state :RequestState := REQUEST
    var buf := []
    var pendingRequest := null
    var pendingRequestLine := null
    var pendingHeaders := null

    return object requestPump:
        to started():
            pass
        to progressed(amount):
            pass
        to stopped():
            pass

        to received(bytes) :List:
            # traceln(`received bytes $bytes`)
            buf += bytes

            var shouldParseMore :Bool := true

            while (shouldParseMore):
                escape badParse:
                    shouldParseMore := requestPump.parse(badParse)
                catch _:
                    return [null]

            if (pendingRequest != null):
                def rv := [pendingRequest]
                pendingRequest := null
                return rv

            return []

        to parse(ej) :Bool:
            # Return whether more parsing can take place.
            # Eject if the parse fails.

            switch (state):
                match ==REQUEST:
                    if (buf.startOf(b`$\r$\n`) == -1):
                        return false

                    # XXX it'd be swell if these were subpatterns
                    def b`@verb @uri HTTP/1.1$\r$\n@t` exit ej := buf
                    pendingRequestLine := [UTF8Decode(verb),
                                           percentDecode(uri)]
                    pendingHeaders := [].asMap()
                    state := HEADER
                    buf := t
                    return true

                match ==HEADER:
                    if (buf.startOf(b`$\r$\n`) == -1):
                        return false

                    if (buf =~ b`$\r$\n@t`):
                        state := BODY
                        buf := t
                        return true

                    def b`@header:@value$\r$\n@t` exit ej := buf
                    pendingHeaders |= [UTF8Decode(header) => UTF8Decode(value)]
                    buf := t
                    return true

                match ==BODY:
                    state := REQUEST
                    pendingRequest := [pendingRequestLine, pendingHeaders]
                    return true


def makeRequestTube():
    return makePumpTube(makeRequestPump())


def statusMap :Map := [
    200 => "OK",
    400 => "Bad Request",
]


def makeResponsePump():
    return object responsePump:
        to started():
            pass
        to progressed(amount):
            pass
        to stopped():
            pass

        to received(response):
            # traceln(`preparing to send $response`)
            def [statusCode, headers, body] := response
            def status := `$statusCode ${statusMap[statusCode]}`
            var rv := [b`HTTP/1.1 $status$\r$\n`]
            for header => value in headers:
                def headerLine := `$header: $value`
                rv with= b`$headerLine$\r$\n`
            rv with= b`$\r$\n`
            rv with= body
            return rv


def makeResponseTube():
    return makePumpTube(makeResponsePump())


def serverHeader := ["Server" => "Monte (Typhon) (.i ma'a tarci pulce)"]

def processorWrapper(app):
    def wrappedProcessor(request):
        # null means a bad request that was unparseable.
        def [statusCode, headers, body] := if (request == null) {
            # We must close the connection after a bad request, since a parse
            # failure leaves the request tube in an indeterminate state.
            [400, ["Connection" => "close"], []]
        } else {app(request)}
        return [statusCode, headers | serverHeader, body]
    return wrappedProcessor


def makeProcessingTube(app):
    return makePumpTube(makeMapPump(processorWrapper(app)))


def makeHTTPEndpoint(endpoint):
    return object HTTPEndpoint:
        to listen(processor):
            def responder(fount, drain):
                fount<-flowTo(makeRequestTube())<-flowTo(makeProcessingTube(processor))<-flowTo(makeResponseTube())<-flowTo(drain)
            endpoint.listen(responder)


[=> makeHTTPEndpoint]
