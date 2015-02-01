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

def [=> simple__quasiParser] | _ := import("lib/simple")
def [=> b__quasiParser] | _ := import("lib/bytes")
def [=> makeEnum] | _ := import("lib/enum")
def [=> UTF8Decode, => UTF8Encode] | _ := import("lib/utf8")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")


object tag:
    match [tagType, contents]:
        def guts := " ".join(contents)
        `<$tagType>$guts</$tagType>`


def [HTTPState, RESPONSE, HEADER, BODY] := makeEnum(
    ["response", "header", "body"])


def makeRequestDrain(callback):
    var state :HTTPState := RESPONSE
    var buf := []
    var fount := null
    var headers := [].asMap().diverge()

    return object requestDrain:
        to flowingFrom(newFount):
            fount := newFount
            return requestDrain

        to flowStopped():
            pass

        to receive(bytes):
            # traceln(`buf $buf bytes $bytes`)
            buf += bytes
            requestDrain.parse()

        to parseStart(ej):
            def b`@meth @url HTTP/@version$\r$\n@tail` exit ej := buf
            if (version != b`1.1`):
                throw(`Bad HTTP version: $version`)
            state := HEADER
            return [UTF8Decode(meth), url, tail]

        to parseHeader(ej):
            escape final:
                def b`@key: @value$\r$\n@tail` exit final := buf
                # traceln("Header:", key, value)
                buf := tail
                headers[key] := value
            catch _:
                def b`$\r$\n@tail` exit ej := buf
                # traceln("End of headers")
                buf := tail
                state := BODY
                callback()

        to parse():
            # traceln(`entering parse with buf $buf`)
            while (true):
                switch (state):
                    match ==RESPONSE:
                        requestDrain.parseStart(__break)
                    match ==HEADER:
                        requestDrain.parseHeader(__break)
                    match ==BODY:
                        # XXX we don't handle any encodings or deal with the
                        # body in any way.
                        state := RESPONSE
                        callback()
                        # fount.stopFlow()
                        break


def sendHeaders(drain, headers):
    for header => value in headers:
        def packed := header + ": " + value + "\r\n"
        drain.receive(packed)
    drain.receive("\r\n")


def constantHeaders := ["Server" => "Monte"]


def makeUTF8EncodeTube():
    return makePumpTube(makeMapPump(UTF8Encode))


def responder(fount, drain):
    def callback():
        # traceln("in callback")
        def strDrain := makeUTF8EncodeTube()
        strDrain.flowTo(drain)

        def headers := constantHeaders.diverge()

        headers["Connection"] := "close"

        def body := UTF8Encode(tag.body(
            tag.h2("Monte HTTP Demo"),
            tag.p("This is Monte code running under Typhon."),
            tag.p("No other support code is provided; this is a Monte webserver."),
            tag.p("It is not intended for anything other than a demonstration.")))

        headers["Content-Length"] := `${body.size()}`

        strDrain.receive("HTTP/1.1 200 OK\r\n")
        sendHeaders(strDrain, headers)
        drain.receive(body)

        # strDrain<-close()
    fount.flowTo(makeRequestDrain(callback))


def endpoint := makeTCP4ServerEndpoint(8080)
endpoint.listen(responder)
