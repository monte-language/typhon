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
def [=> UTF8Encode] | _ := import("lib/utf8")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")
def ["request" => requestParser] | _ := import("lib/parsers/http")


def makeRequestPump():
    var parser := requestParser

    return object requestPump:
        to started():
            pass
        to progressed(amount):
            pass
        to stopped():
            pass

        to received(bytes):
            # traceln(`bytes $bytes`)
            # Update the parser with new data.
            parser := parser.feedMany(bytes)
            # Check whether the parser is ready to finish.
            if (parser.isEmpty()):
                # Reset the parser.
                parser := requestParser
                return [null]
            else if (parser.nullable()):
                def results := parser.results()
                # XXX there should be a way to get only the first result.
                def rv := results.asList()[0]
                # Reset the parser.
                parser := requestParser
                return [rv]
            else:
                # Parse is incomplete.
                return []


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


def constantHeaders := ["Server" => "Monte"]


object tag:
    match [tagType, contents]:
        def guts := " ".join(contents)
        `<$tagType>$guts</$tagType>`


def process(request):
    # traceln(`request $request`)

    if (request == null):
        # Bad request.
        return [400, [].asMap(), []]

    def headers := constantHeaders.diverge()

    headers["Connection"] := "close"

    def body := UTF8Encode(tag.body(
        tag.h2("Monte HTTP Demo"),
        tag.p("This is Monte code running under Typhon."),
        tag.p("No other support code is provided; this is a Monte webserver."),
        tag.p("It is not intended for anything other than a demonstration.")))

    headers["Content-Length"] := `${body.size()}`

    return [200, headers.snapshot(), body]


def makeProcessingTube():
    return makePumpTube(makeMapPump(process))


def responder(fount, drain):
    fount<-flowTo(makeRequestTube())<-flowTo(makeProcessingTube())<-flowTo(makeResponseTube())<-flowTo(drain)


def endpoint := makeTCP4ServerEndpoint(8080)
endpoint.listen(responder)
