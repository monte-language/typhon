import "lib/curl" =~ [=> getURL]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/nelder-mead" =~ [=> makeNelderMead]
import "lib/which" =~ [=> makePathSearcher, => makeWhich]
exports (main)

# https://arxiv.org/abs/1603.01446

def parseProm(s :Str) :Map[Str, Double] as DeepFrozen:
    def rv := [].asMap().diverge(Str, Double)
    for line in (s.split(`$\n`)):
        if (line =~ `@k @{via (_makeDouble) v}`):
            rv[k] := v
    return rv.snapshot()

def fetchPromKeys(head :Str, m :Map[Str, Double]) :Map[Str, Double] as DeepFrozen:
    def rv := [].asMap().diverge(Str, Double)
    for k => v in (m):
        if (k =~ `$head{@tags}`):
            rv[tags] := v
    return rv.snapshot()

def makeProm(curl, url :Bytes) as DeepFrozen:
    return def getTemperatures():
        return when (def bs := getURL(curl, url)) ->
            def fullKeys := parseProm(UTF8.decode(bs, null))
            def rv := [].diverge()
            for k in (["node_thermal_zone_temp", "node_hwmon_temp_celsius"]):
                def temp := fetchPromKeys(k, fullKeys)
                rv.extend(temp.sortKeys().getValues())
            rv.snapshot()

def max(l :List) as DeepFrozen:
    def [var rv] + tail := l
    for t in (tail):
        rv max= (t)
    return rv

def main(_argv, => currentProcess, => makeFileResource, => makeProcess,
         => Timer) as DeepFrozen:
    def paths := currentProcess.getEnvironment()[b`PATH`]
    def searcher := makePathSearcher(makeFileResource, paths)
    def which := makeWhich(makeProcess, searcher)
    def curl := which("curl")

    def myProm := makeProm(curl, b`http://192.168.1.5:9100/metrics`)
    def theirProm := makeProm(curl, b`http://192.168.1.22:9100/metrics`)

    # Sheaf:
    # fused: { O, W₀, W₁ }: R³
    # outside: { O } : R
    # sensor: { T₀ } : R
    # Restriction fused -> outside: project 0
    # Restriction fused -> sensor: project 1
    var fused := [20.0, 50.0, 50.0]
    var outside := 20.0
    var mySensors := [50.0] * 4
    var theirSensors := [50.0] * 3

    def consistencyRadius(fusedOutside, fusedMine, fusedTheirs):
        var cr := (fusedOutside - outside).abs()
        for sensor in (mySensors):
            cr max= ((fusedMine - sensor).abs())
        for sensor in (theirSensors):
            cr max= ((fusedTheirs - sensor).abs())
        return cr

    def go():
        when (Timer.fromNow(5.0)) ->
            mySensors := myProm()
            theirSensors := theirProm()
            when (mySensors, theirSensors) ->
                # Improve the sheaf's fused values.
                for i => xs in (makeNelderMead(consistencyRadius, 3, "origin" => fused)):
                    fused := xs
                    if (i > 100):
                        break
                traceln("outside", outside)
                traceln("sensors", mySensors, theirSensors)
                traceln("fused", fused)
                traceln("CR", M.call(consistencyRadius, "run", fused, [].asMap()))
                go<-()

    return when (go<-()) ->
        0
