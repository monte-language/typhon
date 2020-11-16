import "lib/amp" =~ [=> makeAMPClient]
exports (main)

def makeVamp() as DeepFrozen:
    "A basic environment for restricted execution."

    def heap := [safeScope].diverge()
    def reverseHeap := [safeScope => 0].diverge()

    def lookup(key):
        return switch (key):
            match `ref:@{via (_makeInt.fromStr) i}`:
                heap[i]
            match `lit:@l`:
                eval(l, [].asMap())

    def pack(key):
        return switch (key):
            match literal :Any[Char, Double, Int, Str]:
                "lit:" + M.toQuote(literal)
            match obj:
                "ref:" + reverseHeap.fetch(obj, fn {
                    heap.push(obj)
                    reverseHeap[obj] := heap.size() - 1
                })

    return def vamp(command, arguments):
        return switch (command):
            match =="bootstrap":
                ["value" => "ref:0"]
            match =="call":
                def [target, verb, args, namedArgs] := [for arg in (arguments) lookup(arg)]
                def rv := M.call(target, verb, args, namedArgs)
                ["value" => pack(rv)]

def toBytes(specimen, ej) as DeepFrozen:
    return _makeBytes.fromStr(Str.coerce(specimen, ej))

def main(argv, => makeTCP4ClientEndpoint) as DeepFrozen:
    def [via (toBytes) host, via (_makeInt) port] := argv.slice(argv.size() - 2)
    def endpoint := makeAMPClient(makeTCP4ClientEndpoint(host, port))
    traceln(`Dialing $endpoint`)
    def amp := endpoint.connectStream(makeVamp())
    return when (amp) ->
        traceln(`AMP worker $amp connected to $endpoint`)
        0
