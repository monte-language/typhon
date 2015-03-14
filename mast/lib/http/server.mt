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
