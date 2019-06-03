exports (main)

def CRLF :Bytes := b`$\r$\n`
def TAB :Bytes := b`$\x09`

def obtainRequest(source) :Vow[Bytes] as DeepFrozen:
    var buf := b``
    def resolver := def rv
    source<-(object go {
        to run(chunk) {
            buf += chunk
            switch (buf + chunk) {
                match b`@r$CRLF@_` { bind rv := r }
                match b`@r$TAB@_` { bind rv := r }
                match _ { source<-(go) }
            }
        }
        to complete() { bind rv := buf }
        to abort(problem) { resolver.smash(problem) }
    })
    return rv

def makeGopherHole(gopherMap :Map) as DeepFrozen:
    return def handle(source, sink):
        # Gopher is line-oriented. However, requests have no keepalive, so
        # CRLF is actually a terminator of the entire request, rather than a
        # delimiter.
        when (def request := obtainRequest(source)) ->
            # To facilitate streaming, we allow the resource to write multiple
            # times directly into the sink.
            def resource := gopherMap[request]
            when (resource(sink<-run)) ->
                sink<-complete()

def writeMap(write) as DeepFrozen:
    write(b`iHello World!${TAB}fake${TAB}(NULL)${TAB}0$CRLF.$CRLF`)

def myMap :Map[Bytes, DeepFrozen] := [
    b`` => writeMap,
]

def main(_argv, => makeTCP4ServerEndpoint) as DeepFrozen:
    # XXX grab port from argv, default to 70?
    def ep := makeTCP4ServerEndpoint(7070)
    ep.listenStream(makeGopherHole(myMap))
    def never
    return when (never) -> { 0 }
