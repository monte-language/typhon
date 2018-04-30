import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "lib/gai" =~ [=> makeGAI :DeepFrozen]
import "lib/enum" =~ [=> makeEnum :DeepFrozen]
import "lib/streams" =~ [
    => Pump :DeepFrozen,
    => Source :DeepFrozen,
    => alterSource :DeepFrozen,
    => flow :DeepFrozen,
    => makePump :DeepFrozen,
    => makeSink :DeepFrozen,
]
import "http/headers" =~ [
    => Headers :DeepFrozen,
    => emptyHeaders :DeepFrozen,
    => parseHeader :DeepFrozen,
    => IDENTITY :DeepFrozen,
    => CHUNKED :DeepFrozen,
]
exports (main, makeRequest)

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


def lowercase(specimen, ej) as DeepFrozen:
    def s :Str exit ej := specimen
    return s.toLowerCase()


def makeResponse(status :Int, headers :Headers, bodySource :Source) as DeepFrozen:
    return object response:
        to _printOn(out):
            out.print(`<response $status: $headers>`)

        to status() :Int:
            return status

        to headers() :Headers:
            return headers

        to source():
            return bodySource


def [HTTPState :DeepFrozen,
     REQUEST :DeepFrozen,
     HEADER :DeepFrozen,
     BODY :DeepFrozen,
] := makeEnum(["request", "header", "body"])


def makeBodyMachine(headers :Headers) as DeepFrozen:
    def contentLength :NullOk[Int] := headers.getContentLength()
    var resolver := null
    var buf :Bytes := b``
    var done :Bool := false

    def source(sink) :Vow[Void] as Source:
        traceln(`source($sink) done=$done buf.size()=${buf.size()} resolver=$resolver`)
        return if (done):
            if (buf.size() == 0):
                sink<-complete()
            else:
                # Final chunk.
                sink<-(buf)
                buf := b``
                sink<-complete()
        else:
            sink<-(buf)
            buf := b``

    def feed(bs :Bytes) :Bool:
        traceln(`feed($bs)`)
        buf += bs
        return true

    def machine := if (contentLength == null) {
        feed
    } else {
        var remaining :Int := contentLength

        def finiteBodyMachine(bs :Bytes) :Bool {
            "A controller for a finite body."

            remaining -= bs.size()
            return if (remaining <= 0) {
                feed(bs)
                done := true
                false
            } else {
                feed(bs)
            }
        }
    }

    return [machine, source]

def [ChunkedState :DeepFrozen,
     SIZE :DeepFrozen,
     CHUNK :DeepFrozen,
] := makeEnum(["size", "chunk"])

# XXX this is...not ideal.
def hexDigits :Map[Int, Int] := [
    for i in (b`0123456789abcdefABCDEF`)
    i => _makeInt.withRadix(16).fromBytes(_makeBytes.fromInts([i]))]

def makeChunkedPump() :Pump as DeepFrozen:
    "Make a pump which decodes chunked transfer coding."

    var chunkSize :Int := 0
    var chunks := []

    object chunkMachine:
        to getStateGuard():
            return ChunkedState

        to getInitialState():
            return [SIZE, 1]

        to advance(state, data):
            return switch (state):
                match ==SIZE:
                    def i := data[0]
                    if (i == b`$\r`[0]):
                        traceln(`SIZE->CHUNK $chunkSize $data`)
                        # Chunks will looks like b`$\n...$\r$\n` so we'll have
                        # three extra characters to trim off.
                        def rv := [CHUNK, chunkSize + 3]
                        chunkSize := 0
                        rv
                    else:
                        chunkSize *= 16
                        chunkSize += hexDigits[i]
                        traceln(`SIZE $chunkSize $data`)
                        [SIZE, 1]
                match ==CHUNK:
                    def slice := data.slice(1, data.size() - 2)
                    def chunk := _makeBytes.fromInts(slice)
                    traceln(`CHUNK $chunk`)
                    chunks with= (chunk)
                    [SIZE, 1]

        to results():
            def rv := chunks
            chunks := []
            return rv

    return makePump.fromStateMachine(chunkMachine)


def makeResponseSink(resolver) as DeepFrozen:
    var state :HTTPState := REQUEST
    var buf :Bytes := b``
    var headers :Headers := emptyHeaders()
    var status :NullOk[Int] := null

    var bodyMachine := null

    def nextLine(ej) :Bytes:
        def b`@line$\r$\n@tail` exit ej := buf
        buf := tail
        return line

    def parseStatus(ej):
        def line := nextLine(ej)
        if (line =~ b`HTTP/1.1 @{via (_makeInt.fromBytes) s} @label`):
            status := s
            traceln(`Status: $status ($label)`)
            state := HEADER
            headers := emptyHeaders()

    def parseHeaderLine(ej):
        def line := nextLine(ej)
        if (line.size() == 0):
            # Double newline; end of headers.
            state := BODY
            def [machine, var source :Source] := makeBodyMachine(headers)
            bodyMachine := machine
            # Rig up body decoder.
            for encoding in (headers.getTransferEncoding()):
                switch (encoding):
                    match ==IDENTITY:
                        # No-op.
                        null
                    match ==CHUNKED:
                        source := alterSource.fusePump(makeChunkedPump(),
                                                       source)
            def response := makeResponse(status, headers, source)
            resolver.resolve(response)
        else:
            headers := parseHeader(headers, line)

    def parse():
        while (true):
            switch (state):
                match ==REQUEST:
                    parseStatus(__break)
                match ==HEADER:
                    parseHeaderLine(__break)
                match ==BODY:
                    def more :Bool := bodyMachine(buf)
                    buf := b``
                    if (!more):
                        bodyMachine := null
                        state := REQUEST
                    break

    return object responseSink:
        to complete():
            traceln(`Response complete`)

        to abort(reason):
            traceln(`Response aborted: $reason`)

        to run(bytes):
            buf += bytes
            parse()


def makeRequest(makeTCP4ClientEndpoint, host :Bytes, resource :Str,
                => port :Int := 80) as DeepFrozen:
    def headers := [
        "Host" => host,
        "Connection" => b`close`,
    ].diverge()

    return object request:
        to put(key, value :Bytes):
            headers[key] := value

        to write(verb, sink):
            sink(UTF8.encode(`$verb $resource HTTP/1.1$\r$\n`, null))
            for via (UTF8.encode) k => v in (headers):
                sink(b`$k: $v$\r$\n`)
            sink(b`$\r$\n`)

        to send(verb :Str):
            def endpoint := makeTCP4ClientEndpoint(host, port)
            def [source, sink] := endpoint.connectStream()
            def [p, r] := Ref.promise()

            # Write request.
            when (sink) ->
                request.write(verb, sink)
                sink.complete()
            # Read response.
            source<-(makeResponseSink(r))

            return p

        to get():
            return request.send("GET")


def main(_argv, => getAddrInfo, => makeTCP4ClientEndpoint) as DeepFrozen:
    def addrs := getAddrInfo(b`localhost`, b``)
    return when (addrs) ->
        def gai := makeGAI(addrs)
        def [addr] + _ := gai.TCP4()
        def port :Int := 3456
        def response := makeRequest(makeTCP4ClientEndpoint, addr.getAddress(),
                                    "/statistics?t=json", => port).get()
        when (response) ->
            traceln("Finished request with response", response)
            def [pieces, sink] := makeSink.asList()
            traceln("Getting body...")
            flow(response.source(), sink)
            when (pieces) ->
                traceln(`Pieces: $pieces`)
                0
    catch problem:
        traceln(`Problem: $problem`)
        traceln.exception(problem)
        1
