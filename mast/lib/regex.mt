def [=> makeDerp, => anything, => ex] | _ := import("lib/parsers/derp")

def anyChar := ex('.') % fn _ {anything}

def regex := anyChar

object re__quasiParser:
    to valueMaker(pieces):
        var p := regex
        for chunk in pieces:
            p := p.feedMany(chunk)
        return object hurp:
            to substitute(values):
                return p

traceln(re`.`)
