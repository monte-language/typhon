import "lib/codec" =~ [=> composeCodec]
import "lib/codec/percent" =~ [=> PercentEncoding]
import "lib/codec/utf8" =~  [=> UTF8]
import "lib/enum" =~ [=> makeEnum]
import "lib/gadts" =~ [=> makeGADT]
import "lib/streams" =~ [=> alterSink, => flow, => fuse, => makePump]
import "lib/http/headers" =~ [
    => Headers,
    => emptyHeaders,
    => parseHeader,
]
import "lib/http/response" =~ [=> Response]
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

def Request :DeepFrozen := makeGADT("Request", [
    "full" => [
        "verb" => Str,
        "path" => Str,
        # "headers" => Headers,
        "headers" => DeepFrozen,
        "body" => Bytes,
    ],
])

def [RequestState :DeepFrozen,
     REQUEST :DeepFrozen,
     HEADER :DeepFrozen,
     BODY :DeepFrozen] := makeEnum(["request", "header", "body"])

def [BodyState :DeepFrozen,
     FIXED :DeepFrozen,
     _CHUNKED :DeepFrozen] := makeEnum(["fixed", "chunked"])

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
                    def contentLength := headers.contentLength()
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
                            def [verb, path] := pendingRequestLine
                            pendingRequest := Request.full(=> verb, => path,
                                                           => headers, => body)
                            bodyState := [FIXED, 0]
                        else:
                            return false
                return true

    return def requestPump(bytes :Bytes) :List:
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
    500 => "Internal Server Error",
    501 => "Not Implemented",
]


# If we get `null` from the app, then we'll use this response. Also it's nice
# to have a fake response around for testing. This is kind of a duplicate of
# stuff in lib/http/apps though.
def defaultResponse :DeepFrozen := Response.full(
    "statusCode" => 501,
    "headers" => emptyHeaders().with("spareHeaders" => [
        b`Connection` => b`close`,
        b`Server` => b`Monte (Typhon) (.i ma'a tarci pulce)`,
    ]),
    "body" => b`Not Implemented`,
)


def makeResponsePump() as DeepFrozen:
    return def responsePump(var response):
        if (response == null) { response := defaultResponse }
        def statusCode :Int := response.statusCode()
        def headers :Headers := response.headers()
        def body :Bytes := response.body()
        def statusDescription := statusMap.fetch(statusCode,
                                                 "Unknown Status")
        def status := `$statusCode $statusDescription`
        def rv := [b`HTTP/1.1 $status$\r$\n`].diverge()
        for header => value in (headers.spareHeaders()):
            rv.push(b`$header: $value$\r$\n`)
        rv.push(b`Content-Length: ${M.toString(body.size())}$\r$\n`)
        rv.push(b`$\r$\n`)
        rv.push(response.body())
        return rv

def makeHTTPEndpoint(endpoint) as DeepFrozen:
    return def HTTPEndpoint.listen(app):
        "
        Listen for HTTP requests and run them through `app`.

        `app(request)` should return a `Response` or `null`.
        "

        def responder(source, sink):
            def request := makeRequestPump()
            def processing := makePump.map(app)
            def response := makeResponsePump()
            def fused := fuse(request, fuse(processing, response))
            flow(source, alterSink.fusePump(fused, sink))
        endpoint.listenStream(responder)
