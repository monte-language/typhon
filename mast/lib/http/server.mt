import "lib/codec" =~ [=> composeCodec]
import "lib/codec/percent" =~ [=> PercentEncoding]
import "lib/codec/utf8" =~  [=> UTF8]
import "lib/enum" =~ [=> makeEnum]
import "lib/http/headers" =~ ["ASTBuilder" => headerBuilder]
import "lib/streams" =~ [=> alterSink, => flow, => fuse, => makePump]
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

def ResponseHeaders :DeepFrozen := headerBuilder.responseHeaders()
def MediaType :DeepFrozen := headerBuilder.mediaType()
def RegisteredType :DeepFrozen := headerBuilder.registeredType()
def TransferEncoding :DeepFrozen := headerBuilder.transferEncoding()

def parseTransferEncoding(bs :Bytes) :List[TransferEncoding] as DeepFrozen:
    return [for coding in (bs.toLowerCase().split(b`,`))
        switch (coding.trim()) {
            match b`identity` { headerBuilder.Identity() }
            match b`chunked` { headerBuilder.Chunked() }
            match b`compress` { headerBuilder.Compress() }
            match b`deflate` { headerBuilder.Deflate() }
            match b`gzip` { headerBuilder.Gzip() }
        }]

def registeredTypes :Map[Str, RegisteredType] := [for verb in ([
    "Application", "Audio", "Example", "Font", "Image", "Message", "Model",
    "Multipart", "Text", "Video"])
    verb.toLowerCase() => M.call(headerBuilder, verb, [], [].asMap())]

def parseMediaType(value :Bytes) :MediaType as DeepFrozen:
    # XXX should support options, right?
    def via (UTF8.decode) `@type/@subtype` := value
    return headerBuilder.Media(registeredTypes[type], subtype)


# Strange as it sounds, the percent encoding is actually *outside* the UTF-8
# encoding!
def UTF8Percent :DeepFrozen := composeCodec(PercentEncoding, UTF8)

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

    # Splay out the headers into their various components. When it's time to
    # finish the request, we'll pick up each component and copy it into a
    # single header structure.
    var contentLength :NullOk[Int] := null
    var contentType :NullOk[MediaType] := null
    var userAgent :NullOk[Str] := null
    var transferEncoding :List[TransferEncoding] := []
    var spares := [].asMap().diverge()

    def parseHeader(bs :Bytes):
        "Parse a bytestring header and add it to a header record."

        def b`@header:@{var value}` := bs
        value trim= ()
        return switch (header.trim().toLowerCase()):
            match b`content-length`:
                contentLength := _makeInt.fromBytes(value)
            match b`content-type`:
                contentType := parseMediaType(value)
            match b`transfer-encoding`:
                transferEncoding := parseTransferEncoding(value)
            match b`user-agent`:
                userAgent := UTF8.decode(value, null)
            match h:
                spares[h] := value

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
                contentLength := null
                userAgent := null
                transferEncoding := []
                spares := [].asMap().diverge()
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
                    if (contentLength != null):
                        bodyState := [FIXED, contentLength]
                    return true

                def slice := buf.slice(0, index)
                parseHeader(slice)
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
                            def spareHeaders := [for [k, v] in (spares) {
                                headerBuilder.Header(k, v)
                            }]
                            def headers := headerBuilder.RequestHeaders(
                                => contentLength,
                                => contentType,
                                => userAgent,
                                => transferEncoding,
                                => spareHeaders,
                            )
                            pendingRequest := [=> verb, => path, => headers,
                                               => body]
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


# To raise Monte awareness.
def serverBanner :Str := "Monte (Typhon) (.i ma'a tarci pulce)"

# If we get `null` from the app, then we'll use this response. Also it's nice
# to have a fake response around for testing. This is kind of a duplicate of
# stuff in lib/http/apps though.
def defaultResponse :DeepFrozen := [
    "statusCode" => 501,
    "headers" => headerBuilder.ResponseHeaders(
        headerBuilder.Media(headerBuilder.Text(), "plain"),
        headerBuilder.Close(),
        serverBanner,
        [],
        [],
    ),
    "body" => b`Not Implemented`,
]

object lowercaseVerb as DeepFrozen:
    match [verb, _, _]:
        verb.toLowerCase()

def formatMediaType.Media(registeredType, subType) as DeepFrozen:
    return b`${registeredType(lowercaseVerb)}/$subType`


def makeResponsePump() as DeepFrozen:
    return def responsePump(var response):
        traceln(`responsePump($response)`)
        if (response == null) { response := defaultResponse }
        def [=> statusCode :Int,
             => headers :ResponseHeaders,
             => body :Bytes] := response
        def statusDescription := statusMap.fetch(statusCode,
                                                 "Unknown Status")
        def status := `$statusCode $statusDescription`
        def rv := [b`HTTP/1.1 $status$\r$\n`].diverge()
        if (headers != null):
            headers(def writeHeaders.ResponseHeaders(contentType, connection,
                                                     server, transferEncoding,
                                                     spareHeaders) {
                if (contentType != null) {
                    rv.push(b`Content-Type: ${contentType(formatMediaType)}$\r$\n`)
                }
                def conn := if (connection == null) { "close" } else {
                    connection(lowercaseVerb)
                }
                rv.push(b`Connection: $conn$\r$\n`)
                def banner := UTF8.encode(
                    (server == null).pick(serverBanner, server), null)
                rv.push(b`Server: $banner$\r$\n`)
                if (!transferEncoding.isEmpty()) {
                    def encodings := b`,`.join([for te in (transferEncoding) {
                        UTF8.encode(te(lowercaseVerb), null)
                    }])
                    rv.push(b`Transfer-Encoding: ${b`,`.join(encodings)}$\r$\n`)
                }
                for spare in (spareHeaders) {
                    spare(def writeHeader.Header(k, v) {
                        rv.push(b`$k: $v$\r$\n`)
                    })
                }
            })
        rv.push(b`Content-Length: ${M.toString(body.size())}$\r$\n`)
        rv.push(b`$\r$\n`)
        rv.push(body)
        return rv

def makeHTTPEndpoint(endpoint) as DeepFrozen:
    return def HTTPEndpoint.listen(app):
        "
        Listen for HTTP requests and run them through `app`.

        `app(request)` will repeatedly recieve request quadruplets of
        [=> verb :Str, => path :Str, => headers :RequestHeaders, => body :Bytes] and
        should return response triples of
        [=> statusCode :Int, => headers :ResponseHeaders, => body :Bytes] or `null`.
        "

        def responder(source, sink):
            def request := makeRequestPump()
            def processing := makePump.map(app)
            def response := makeResponsePump()
            def fused := fuse(request, fuse(processing, response))
            flow(source, alterSink.fusePump(fused, sink))
        endpoint.listenStream(responder)
