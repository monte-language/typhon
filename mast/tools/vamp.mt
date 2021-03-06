import "lib/amp" =~ [=> makeAMPClient]
import "lib/json" =~ [=> JSON]
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
            return switch (value):
                match xs :List:
                    [for x in (xs) gordianSurgeon.serialize(x)]
                match xs :Map:
                    [for k => v in (xs) k => gordianSurgeon.serialize(v)]
                match literal :Any[Bool, Double, Int, Void]:
                    literal
                match literal :Str ? (literal.size() < 0x100):
                    if (literal.startsWith("$")) {
                        "$$" + literal
                    } else { literal }
                match via (unscope.fetch) knownExit:
                    `$$ref:$knownExit`
                match _:
                    def newExit := gordianSurgeon.addExit(value)
                    # traceln("Automatic object export", value, newExit)
                    `$$ref:$newExit`

        to unserialize(depiction):
            return switch (depiction):
                match xs :List:
                    [for x in (xs) gordianSurgeon.unserialize(x)]
                match xs :Map:
                    [for k => v in (xs) k => {
                        gordianSurgeon.unserialize(v)
                    }]
                match `$$$$@x`:
                    x
                match `$$ref:@{via (_makeInt) i}`:
                    exitPoints[i]
                match v:
                    v

def makeVamp() as DeepFrozen:
    "A basic environment for restricted execution."

    def surgeon := makeSurgeon()

    var bootMAST := b``

    return object vamp:
        to complete():
            traceln("Lost connection")

        to abort(problem):
            traceln("Aborted connection", problem)
            traceln.exception(problem)

        to run(command, params, => FAIL):
            return switch (command):
                match =="load":
                    def [=> mast] exit FAIL := params
                    bootMAST += _makeBytes.fromStr(mast)
                    traceln(`Got MAST slice of ${mast.size()} (${bootMAST.size()} total)`)
                    [].asMap()
                match =="bootstrap":
                    traceln(`Got boot MAST of ${bootMAST.size()}`)
                    def expr := readMAST(bootMAST, "filename" => "<vamp>", => FAIL)
                    def module := eval(expr, safeScope)(null)
                    traceln(`Got module $module`)
                    def bootRef := JSON.encode(surgeon.serialize(module), FAIL)
                    ["value" => bootRef]
                match =="call":
                    escape badCall:
                        def [=> payload] exit badCall := params
                        def unserialized := surgeon.unserialize(JSON.decode(payload, badCall))
                        def [=> target,
                             => verb :Str,
                             => arguments :List,
                             => namedArguments :Map] exit badCall := unserialized
                        # traceln("call", target, verb, arguments, namedArguments)
                        try:
                            def rv := M.call(target, verb, arguments, namedArguments)
                            # traceln("call result", rv)
                            def serialized := JSON.encode(surgeon.serialize(rv), FAIL)
                            # traceln("serialized", serialized)
                            ["result" => serialized]
                        catch problem:
                            traceln("call problem", problem)
                            traceln.exception(problem)
                            throw.eject(FAIL, problem)
                    catch problem:
                        traceln("bad call", params)
                match _:
                    throw.eject(FAIL, `unknown command $command`)

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
