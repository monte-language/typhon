# Copyright (C) 2015 Google Inc. All rights reserved.
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

def [
    => makeDerp,
    => ex,
    => anything,
    => set
] | _ := import("lib/parsers/derp")
def [=> b__quasiParser] | _ := import("lib/bytes")
def [=> makeEnum] | _ := import("lib/enum")

def bytes(bs):
    # Flip the bytes around, and then build up a tree which leans in the
    # opposite direction from normal. This will result in a tree which parses
    # much faster, especially for head fails.
    def [head] + tail := bs.reverse()
    var p := ex(head)
    for b in tail:
        p := ex(b) + p
    return p % fn _ {bs}

def testBytes(assert):
    def p := bytes(b`asdf`)
    def results := p.feedMany(b`asdf`).results()
    assert.equal(results, [b`asdf`].asSet())

unittest([testBytes])

# RFC 2616 5.1.1
def [
    Methods, OPTIONS, GET, HEAD, POST, PUT, DELETE, TRACE, CONNECT
] := makeEnum(["OPTIONS", "GET", "HEAD", "POST", "PUT", "DELETE", "TRACE",
               "CONNECT"])
var methods := bytes(b`OPTIONS`) % fn _ {OPTIONS} | bytes(b`GET`) % fn _ {GET}
methods |= bytes(b`HEAD`) % fn _ {HEAD} | bytes(b`POST`) % fn _ {POST}
methods |= bytes(b`PUT`) % fn _ {PUT} | bytes(b`DELETE`) % fn _ {DELETE}
methods |= bytes(b`TRACE`) % fn _ {TRACE} | bytes(b`CONNECT`) % fn _ {CONNECT}

# RFC 2396 2.3
def mark := set(b`-_.!~*'()`)
def lowercase := set(b`abcdefghijklmnopqrstuvwxyz`)
def uppercase := set(b`ABCDEFGHIJKLMNOPQRSTUVWXYZ`)
def digit := set(b`1234567890`)
def unreserved := lowercase | uppercase | digit | mark

# RFC 2396 3.3
def pchar := unreserved | set(b`:@@&=+$$,`)
def param := pchar.repeated()
var segment := pchar.repeated() + (bytes(b`;`) + param).repeated()
segment %= fn [h, t] {[h] + t}
var pathSegments := segment + (bytes(b`/`) + segment).repeated()
pathSegments %= fn [h, t] {[h] + t}

# RFC 2396 3
def absPath := (bytes(b`/`) + pathSegments) % fn [_, ss] {ss}

# RFC 2616 5.1.2
def requestURI := bytes(b`*`) | absPath

# RFC 2616 5.1
def sp := bytes(b` `)
def version := bytes(b`HTTP/1.1`)
def crlf := bytes(b`$\r$\n`)
var requestLine := methods + sp + requestURI + sp + version + crlf
requestLine %= fn [[[[[m, _], uri], _], _], _] {[m, uri]}

def testRequestLine(assert):
    def option := requestLine(b`OPTIONS * HTTP/1.1$\r$\n`)
    assert.equal(option, [[OPTIONS, b`*`]].asSet())

    def get := requestLine(b`GET /test HTTP/1.1$\r$\n`)
    assert.equal(get, [[GET, [[b`test`]]]].asSet())

def notcr := set((0..!256).asSet().without(13).without(10))

# RFC 2616 14.1
# XXX incomplete
var accept := bytes(b`Accept: `) + notcr.repeated() + crlf
accept %= fn [[_, a], _] {a}

def testAccept(assert):
    def anything := accept(b`Accept: */*$\r$\n`)
    assert.equal(anything, [b`*/*`].asSet())

unittest([testAccept])

# RFC 2616 14.23
# XXX incomplete
var host := bytes(b`Host: `) + notcr.repeated() + crlf
host %= fn [[_, h], _] {h}

def testHost(assert):
    def localhost := host(b`Host: localhost:8080$\r$\n`)
    assert.equal(localhost, [b`localhost:8080`].asSet())

unittest([testHost])

# RFC 2616 14.43
# XXX incomplete
var userAgent := bytes(b`User-Agent: `) + notcr.repeated() + crlf
userAgent %= fn [[_, ua], _] {ua}

def testUserAgent(assert):
    def curl := userAgent(b`User-Agent: curl/7.38.0$\r$\n`)
    assert.equal(curl, [b`curl/7.38.0`].asSet())

unittest([testUserAgent])

# RFC 2616 5.3
# XXX incomplete
def requestHeader := accept | host | userAgent

# RFC 2616 5
# XXX incomplete
var request := requestLine + requestHeader.repeated() + crlf
request %= fn [[line, headers], _] {[line, headers]}

[=> request]
