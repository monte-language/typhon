import "lib/amp" =~ [=> makeAMPClient]
exports (main)

def makeSurgeon() as DeepFrozen:
    "A basic mutable Gordian surgeon."

    def exitPoints := [].diverge()
    def unscope := [].asMap().diverge()

    return object gordianSurgeon:
        to addExit(obj) :Int:
            def rv := exitPoints.size()
            exitPoints.push(obj)
            unscope[obj] := rv
            return rv

        to serialize(value):
            traceln("serializing", value)
            return switch (value):
                match literal :Any[Double, Int]:
                    `lit:$literal`
                match literal :Str ? (literal.size() < 0x100):
                    `lit:${M.toQuote(literal)}`
                match via (unscope.fetch) knownExit:
                    `ref:$knownExit`
                match _:
                    def newExit := gordianSurgeon.addExit(value)
                    traceln("Automatic object export", value, newExit)
                    `ref:$newExit`

        to unserialize(depiction):
            traceln("unserializing", depiction)
            return switch (depiction):
                match `lit:@l`:
                    eval(l, [=> &&_makeList])
                match `ref:@{via (_makeInt) i}`:
                    exitPoints[i]
                match `list:@xs`:
                    [for x in (xs.split(";")) gordianSurgeon.unserialize(x)]

def makeVamp() as DeepFrozen:
    "A basic environment for restricted execution."

    def surgeon := makeSurgeon()
    def bootRef := surgeon.addExit(safeScope)

    return def vamp(command, params):
        return switch (command):
            match =="bootstrap":
                ["value" => `ref:$bootRef`]
            match =="call":
                def [=> target,
                     => verb :Str,
                     => arguments,
                     => namedArguments] := params
                def t := surgeon.unserialize(target)
                def args :List := surgeon.unserialize(arguments)
                def namedArgs :Map := surgeon.unserialize(namedArguments)
                traceln("calling", t, verb, args, namedArgs)
                try:
                    def rv := M.call(t, verb, args, namedArgs)
                    traceln("result", rv)
                    ["value" => surgeon.serialize(rv)]
                catch problem:
                    traceln.exception(problem)

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
