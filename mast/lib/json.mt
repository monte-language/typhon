imports => unittest
exports (JSON, json__quasiParser)

object valueHoleMarker as DeepFrozen:
    pass

object patternHoleMarker as DeepFrozen:
    pass


def specialDecodeChars :Map[Char, Str] := [
    '"' => "\"",
    '\\' => "\\",
    '/' => "/",
    'b' => "\b",
    'f' => "\f",
    'n' => "\n",
    'r' => "\r",
    't' => "\t",
]

def specialEncodeChars :Map[Char, Str] := [
    '"' => "\\\"",
    '\\' => "\\\\",
    '/' => "\\/",
    '\b' => "\\b",
    '\f' => "\\f",
    '\n' => "\\n",
    '\r' => "\\r",
    '\t' => "\\t",
]


def makeStream(s :Str) as DeepFrozen:
    var index :Int := 0
    return object stream:
        to next():
            def rv := s[index]
            index += 1
            return rv

        to peek():
            return s[index]

        to fastForward(count):
            index += count

        to finished() :Bool:
            return index >= s.size()


def makeLexer() as DeepFrozen:
    def tokens := [].diverge()

    return object lexer:
        to next(stream):
            switch (stream.next()):
                match ==' ':
                    pass
                match =='\n':
                    pass
                match =='{':
                    tokens.push('{')
                match =='}':
                    tokens.push('}')
                match ==',':
                    tokens.push(',')
                match ==':':
                    tokens.push(':')
                match =='[':
                    tokens.push('[')
                match ==']':
                    tokens.push(']')
                match =='t':
                    tokens.push(true)
                    stream.fastForward(3)
                match =='f':
                    tokens.push(false)
                    stream.fastForward(4)
                match =='n':
                    tokens.push(null)
                    stream.fastForward(3)

                match =='"':
                    lexer.nextString(stream)

                match digit ? ("0123456789".contains(digit)):
                    # Things I miss from C: do-while. ~ C.
                    var i := digit.asInteger() - '0'.asInteger()
                    while ("0123456789".contains(stream.peek())):
                        def nextDigit := stream.next()
                        i *= 10
                        i += nextDigit.asInteger() - '0'.asInteger()
                    tokens.push(i)

                match c:
                    throw(`Unknown character $c`)

        to nextString(stream):
            def buf := [].diverge()

            while (true):
                switch (stream.next()):
                    match =='"':
                        break
                    match =='\\':
                        def c := stream.next()
                        buf.push(specialDecodeChars.fetch(c,
                            fn {throw(`Bad escape character $c`)}))
                    match c:
                        buf.push(c.asString())

            tokens.push("".join(buf))

        to getTokens():
            return tokens

        to lex(stream):
            while (!stream.finished()):
                lexer.next(stream)

        to markValueHole(index):
            tokens.push([valueHoleMarker, index])

        to markPatternHole(index):
            tokens.push([patternHoleMarker, index])


def parse(var tokens) as DeepFrozen:
    var state := ["arr"].diverge()
    var stack := [[].diverge()].diverge()
    var key := null

    def pushValue(value):
        if (state[state.size() - 1] == "obj"):
            stack[stack.size() - 1][key] := value
        else:
            stack[stack.size() - 1].push(value)

    while (tokens.size() > 0):
        # traceln("Tokens", tokens)
        switch (tokens):
            match [==','] + rest:
                tokens := rest
            match [=='{'] + rest:
                state.push("obj")
                stack.push([].asMap().diverge())
                tokens := rest
            match [=='}'] + rest:
                state.pop()
                def obj := stack.pop().snapshot()
                pushValue(obj)
                tokens := rest
            match [=='['] + rest:
                state.push("arr")
                stack.push([].diverge())
                tokens := rest
            match [==']'] + rest:
                state.pop()
                def arr := stack.pop().snapshot()
                pushValue(arr)
                tokens := rest
            match [k, ==':'] + rest:
                key := k
                tokens := rest
            match [v] + rest:
                pushValue(v)
                tokens := rest

    # traceln("final stack", stack)
    return stack[0][0]


def makeJSON(value) as DeepFrozen:
    return object JSON:
        to substitute(values):
            if (values == []):
                return JSON

            return switch (value):
                match [==valueHoleMarker, index]:
                    makeJSON(values[index].getValue())
                match l :List:
                    makeJSON([for v in (l)
                              makeJSON(v).substitute(values).getValue()])
                match m :Map:
                    makeJSON([for k => v in (m)
                              k => makeJSON(v).substitute(values).getValue()])
                match _:
                    JSON

        to _matchBind(values, specimen, ej):
            def pattern := JSON.substitute(values)
            def s := specimen.getValue()
            var rv := [].asMap()

            switch (value):
                match [==patternHoleMarker, index]:
                    rv := rv.with(index, specimen)
                match ss :List:
                    def l :List exit ej := value
                    if (l.size() != ss.size()):
                        throw(ej, "Lists are not of the same size")
                    var i := 0
                    while (i < l.size()):
                        def v := makeJSON(l[i])
                        rv |= v._matchBind(values, makeJSON(ss[i]), ej)
                        i += 1
                match ss :Map:
                    # Asymmetry in the patterns for clarity: Only drill down
                    # into keys which are present in the pattern.
                    def m :Map exit ej := s
                    for k => v in ss:
                        rv |= makeJSON(v)._matchBind(values, makeJSON(m[k]), ej)
                match ==value:
                    pass
                match _:
                    pass

            return rv

        to matchBind(values, specimen, ej):
            def matched := JSON._matchBind(values, specimen, ej)
            def rv := [].diverge()

            for k => v in matched:
                while (k >= rv.size()):
                    rv.push(null)
                rv[k] := v

            return rv.snapshot()

        to getValue():
            return value


object json__quasiParser as DeepFrozen:
    to valueMaker(pieces):
        def lexer := makeLexer()

        for piece in pieces:
            switch (piece):
                match [==valueHoleMarker, index]:
                    lexer.markValueHole(index)
                match [==patternHoleMarker, index]:
                    lexer.markPatternHole(index)
                match _:
                    def stream := makeStream(piece)
                    lexer.lex(stream)

        def parsed := parse(lexer.getTokens())
        return makeJSON(parsed)

    to matchMaker(pieces):
        return json__quasiParser.valueMaker(pieces)

    to valueHole(index):
        return [valueHoleMarker, index]

    to patternHole(index):
        return [patternHoleMarker, index]


object JSON as DeepFrozen:
    "The JSON data format."

    to decode(specimen, ej):
        def s :Str exit ej := specimen
        def lexer := makeLexer()
        def stream := makeStream(s)
        lexer.lex(stream)
        return parse(lexer.getTokens())

    to encode(specimen, ej) :Str:
        return switch (specimen):
            match m :Map:
                def pieces := [].diverge()
                for k => v in m:
                    def s :Str exit ej := k
                    def es := JSON.encodeStr(s)
                    def ev := JSON.encode(v, ej)
                    pieces.push(`$es:$ev`)
                `{${",".join(pieces)}}`
            match l :List:
                def pieces := [for i in (l) JSON.encode(i, ej)]
                `[${",".join(pieces)}]`
            match i :Int:
                M.toString(i)
            match d :Double:
                M.toString(d)
            match s :Str:
                JSON.encodeStr(s)
            match c :Char:
                JSON.encodeStr(c.asString())
            match _:
                throw.eject(ej, `$specimen isn't representable in JSON`)

    to encodeStr(s :Str) :Str:
        def pieces := [for c in (s)
                       specialEncodeChars.fetch(c, fn {c.asString()})]
        return `"${"".join(pieces)}"`


def testJSONDecode(assert):
    def specimen := "{\"first\":42,\"second\":[5,7]}"
    assert.equal(JSON.decode(specimen, null),
                 ["first" => 42, "second" => [5, 7]])

def testJSONDecodeSlash(assert):
    def specimen := "{\"face\\/off\":1997}"
    assert.equal(JSON.decode(specimen, null), ["face/off" => 1997])

def testJSONEncode(assert):
    def specimen := ["first" => 42, "second" => [5, 7]]
    assert.equal(JSON.encode(specimen, null),
                 "{\"first\":42,\"second\":[5,7]}")

unittest([
    testJSONDecode,
    testJSONDecodeSlash,
    testJSONEncode,
])
