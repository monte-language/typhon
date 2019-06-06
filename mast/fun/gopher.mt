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

def intToBytes(v, ej) as DeepFrozen:
    def i :Int exit ej := v
    def s :Str exit ej := M.toString(i)
    def rv :Bytes exit ej := _makeBytes.fromStr(s)
    return rv

def makeMenuWriter(myHost :Bytes, myPort :Bytes) as DeepFrozen:
    return def menuWriter(write) as DeepFrozen:
        return object menu:
            to i(label :Bytes):
                "Informational text."
                write(b`i$label${TAB}fake${TAB}(NULL)${TAB}0$CRLF`)

            to "1"(label :Bytes, selector :Bytes, => host :Bytes := myHost,
                   => port :Bytes := myPort):
                "Menu."
                write(b`1$label$TAB$selector$TAB$host$TAB$port$CRLF`)

def errorResource(write) as DeepFrozen:
    write(b`3Selector Not Found$TAB$TAB$TAB$CRLF`)
    write(b`.$CRLF`)

def makeGopherHole(root, => host :Bytes, "port" => via (intToBytes) port :Bytes := 70) as DeepFrozen:
    # selectors => resources
    def resources := [b`` => root].diverge()
    # Reverse lookup, resources => selectors
    # def selectors := [root => b``].diverge()

    def menuWriter := makeMenuWriter(host, port)

    return def handle(source, sink):
        # Gopher is line-oriented. However, requests have no keepalive, so
        # CRLF is actually a terminator of the entire request, rather than a
        # delimiter.
        when (def request := obtainRequest(source)) ->
            # To facilitate streaming, we allow the resource to write multiple
            # times directly into the sink.
            def resource := resources.fetch(request, &errorResource.get)
            def write := sink<-run
            def menu := menuWriter(write)
            when (resource(write, => menu)) ->
                sink<-complete()

def myRoot(write, => menu) as DeepFrozen:
    menu.i(b`Hello world!`)
    menu.i(b`This is a lot easier now.`)
    menu."1"(b`Don't click me?`, b`fakeSelector`)
    write(b`.$CRLF`)

def main(_argv, => makeTCP4ServerEndpoint) as DeepFrozen:
    # XXX grab port from argv, default to 70?
    def port :Int := 7070
    def ep := makeTCP4ServerEndpoint(port)
    def hole := makeGopherHole(myRoot, "host" => b`localhost`, => port)
    ep.listenStream(hole)
    def never
    return when (never) -> { 0 }
