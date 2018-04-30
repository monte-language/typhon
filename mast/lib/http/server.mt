import "unittest" =~ [=> unittest]
import "lib/codec" =~ [=> composeCodec :DeepFrozen]
import "lib/codec/percent" =~ [=> PercentEncoding :DeepFrozen]
import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "lib/enum" =~ [=> makeEnum :DeepFrozen]
import "lib/record" =~ [=> makeRecord :DeepFrozen]
import "lib/streams" =~ [
    => alterSink :DeepFrozen,
    => flow :DeepFrozen,
    => fuse :DeepFrozen,
]
import "lib/tubes" =~ [
     => makePumpTube :DeepFrozen,
]
import "http/headers" =~ [
    => Headers :DeepFrozen,
    => emptyHeaders :DeepFrozen,
    => parseHeader :DeepFrozen,
]
exports (makeHTTPEndpoint)

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


# Strange as it sounds, the percent encoding is actually *outside* the UTF-8
# encoding!
def UTF8Percent :DeepFrozen := composeCodec(PercentEncoding, UTF8)

def [Request :DeepFrozen,
     makeRequest :DeepFrozen] := makeRecord("Request",
     ["verb" => Str,
      "path" => Str,
      "headers" => Headers,
      # XXX can/should/will be a tube, especially once we have chunked
      "body" => Bytes])

def [RequestState :DeepFrozen,
     REQUEST :DeepFrozen,
     HEADER :DeepFrozen,
     BODY :DeepFrozen] := makeEnum(["request", "header", "body"])

def [BodyState :DeepFrozen,
     FIXED :DeepFrozen,
     CHUNKED :DeepFrozen] := makeEnum(["fixed", "chunked"])

def makeRequestPump() as DeepFrozen:
    var requestState :RequestState := REQUEST
    # How body state works: The int is how much is left to read in the current
    # "chunk". For FIXED, that's how much body is left total; for CHUNKED,
    # it's how much body is left in the current chunk of data.
    var bodyState :Pair[BodyState, Int] := [FIXED, 0]

    var buf :Bytes := b``
    var pendingRequest := null
    var pendingRequestLine := null
    var headers :Headers := emptyHeaders()

    def parse(ej) :Bool:
        # Return whether more parsing can take place.
        # Eject if the parse fails.

        switch (requestState):
            match ==REQUEST:
                if (buf.indexOf(b`$\r$\n`) == -1):
                    return false

                # XXX it'd be swell if these were subpatterns
                def b`@{via (UTF8.decode) verb} @{via (UTF8Percent.decode) uri} HTTP/1.1$\r$\n@t` exit ej := buf
                pendingRequestLine := [verb, uri]
                headers := emptyHeaders()
                requestState := HEADER
                buf := t
                return true

            match ==HEADER:
                def index := buf.indexOf(b`$\r$\n`)

                if (index == -1):
                    return false

                if (index == 0):
                    # Single newline; end of headers.
                    requestState := BODY
                    buf := buf.slice(2)
                    # Copy the content length to become the body length.
                    def contentLength := headers.getContentLength()
                    if (contentLength != null):
                        bodyState := [FIXED, contentLength]
                    return true

                def slice := buf.slice(0, index)
                headers := parseHeader(headers, slice)
                buf := buf.slice(index + 2)
                return true

            match ==BODY:
                switch (bodyState):
                    # XXX this should eventually just deliver each chunk
                    # to a tube.
                    match [==FIXED, len]:
                        if (buf.size() >= len):
                            def body := buf.slice(0, len)
                            buf slice= (len)
                            requestState := REQUEST
                            def [verb, uri] := pendingRequestLine
                            pendingRequest := makeRequest(verb, uri,
                                                          headers, body)
                            bodyState := [FIXED, 0]
                        else:
                            return false
                return true

    return def requestPump(bytes :Bytes) :List:
        # traceln(`received bytes $bytes`)
        buf += bytes

        var shouldParseMore :Bool := true

        while (shouldParseMore):
            escape badParse:
                shouldParseMore := parse(badParse)
            catch _:
                return [null]

        if (pendingRequest != null):
            def rv := [pendingRequest]
            pendingRequest := null
            return rv

        return []


def statusMap :Map[Int, Str] := [
    200 => "OK",
    301 => "Moved Permanently",
    303 => "See Other",
    307 => "Temporary Redirect",
    400 => "Bad Request",
    404 => "Not Found",
]


def makeResponsePump() as DeepFrozen:
    return def responsePump(response):
        def [statusCode, headers, body] := response
        def statusDescription := statusMap.fetch(statusCode,
                                                 "Unknown Status")
        def status := `$statusCode $statusDescription`
        var rv := [b`HTTP/1.1 $status$\r$\n`]
        for header => value in (headers):
            def headerLine := `$header: $value`
            rv with= (b`$headerLine$\r$\n`)
        rv with= (b`$\r$\n`)
        rv with= (body)
        return rv


def serverHeader :Map[Str, Str] := [
    "Server" => "Monte (Typhon) (.i ma'a tarci pulce)",
]

def processorWrapper(app) as DeepFrozen:
    def wrappedProcessor(request):
        # null means a bad request that was unparseable.
        def [statusCode, headers, body] := if (request == null) {
            # We must close the connection after a bad request, since a parse
            # failure leaves the request tube in an indeterminate state.
            [400, ["Connection" => "close"], []]
        } else {
            try {
                app(request)
            } catch problem {
                traceln(`Caught problem in app:`)
                traceln.exception(problem)
                [500, ["Connection" => "close"], []]
            }
        }
        return [statusCode, headers | serverHeader, body]
    return wrappedProcessor


def makeProcessingPump(app) as DeepFrozen:
    def wrapper := processorWrapper(app)
    return def processingPump(request):
        return [wrapper(request)]


def makeHTTPEndpoint(endpoint) as DeepFrozen:
    return object HTTPEndpoint:
        to listen(processor):
            def responder(source, sink):
                def request := makeRequestPump()
                def processing := makeProcessingPump(processor)
                def response := makeResponsePump()
                def fused := fuse(request, fuse(processing, response))
                flow(source, alterSink.fusePump(fused, sink))
            endpoint.listenStream(responder)
