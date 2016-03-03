import "unittest" =~ [=> unittest]
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

        to accept(c :Char):
            return if (s[index] == c) {index += 1; true} else {false}

        to fastForward(count):
            index += count

        to finished() :Bool:
            return index >= s.size()


def charDigit(c :('0'..'9')) :(0..9) as DeepFrozen:
    "Lex a character into an integer.

     The definition of this function should leave little room for doubt on its
     behavior."

    # 0x30 == '0'.asInteger()
    return c.asInteger() - 0x30


def makeLexer(ej) as DeepFrozen:
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
                        i *= 10
                        i += charDigit(stream.next())
                    # We now check for the fraction and exponent. Either,
                    # both, or neither.
                    if (stream.accept('.')):
                        # Fraction.
                        var fraction := 0
                        var divisor := 1
                        while ("0123456789".contains(stream.peek())):
                            divisor *= 10
                            fraction *= 10
                            fraction += charDigit(stream.next())
                        # Scale the fraction.
                        fraction /= divisor
                        # And apply the fraction.
                        i += fraction
                    # Safe; the second branch only executes when the first
                    # branch fails, and the stream is not advanced on failure.
                    if (stream.accept('E') || stream.accept('e')):
                        def negative :Bool := stream.accept('-')
                        # If not negative, could be explicitly positive.
                        if (!negative):
                            stream.accept('+')
                        # Y'know, maybe this should be a function or a method
                        # on the stream...
                        var exponent := charDigit(stream.next())
                        while ("0123456789".contains(stream.peek())):
                            exponent *= 10
                            exponent += charDigit(stream.next())
                        # Apply the negative flag.
                        if (negative):
                            exponent := -exponent
                        # And now apply the exponent. Note that the RHS is an
                        # integer; whether this results in an integer or
                        # double is dependent on whether the LHS was converted
                        # to a double by matching the fraction.
                        i *= 10 ** exponent
                    tokens.push(i)

                match c:
                    throw.eject(ej, `Unknown character $c`)

        to nextString(stream):
            def buf := [].diverge()

            while (true):
                switch (stream.next()):
                    match =='"':
                        break
                    match =='\\':
                        def c := stream.next()
                        buf.push(specialDecodeChars.fetch(c,
                            fn {throw.eject(ej, `Bad escape character $c`)}))
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


def parse(var tokens, ej) as DeepFrozen:
    var stack := [].diverge()
    var key := null
    var rv := null

    def pushValue(value):
        if (stack.size() == 0):
            rv := value
        else:
            switch (stack.last()):
                match [=="object", map, _]:
                    map[key] := value
                match [=="array", list, _]:
                    list.push(value)
                match _:
                    throw.eject(ej, "Congrats, you broke the JSON parser.")

    while (tokens.size() > 0):
        switch (tokens):
            match [==','] + rest:
                tokens := rest
            match [=='{'] + rest:
                stack.push(["object", [].asMap().diverge(), key])
                tokens := rest
            match [=='}'] + rest:
                if (stack.size() == 0):
                    throw.eject(ej, "Stack underflow (unbalanced object)")
                def [=="object", obj, k] exit ej := stack.pop().snapshot()
                key := k
                pushValue(obj.snapshot())
                tokens := rest
            match [=='['] + rest:
                stack.push(["array", [].diverge(), key])
                tokens := rest
            match [==']'] + rest:
                if (stack.size() == 0):
                    throw.eject(ej, "Stack underflow (unbalanced array)")
                def [=="array", arr, k] exit ej := stack.pop().snapshot()
                key := k
                pushValue(arr.snapshot())
                tokens := rest
            match [k, ==':'] + rest:
                key := k
                tokens := rest
            match [v] + rest:
                pushValue(v)
                key := null
                tokens := rest
    if (stack.size() != 0):
        throw.eject(ej, "Nonempty stack (unclosed object/array)")
    if (rv == null):
        throw.eject(ej, "No object decoded (empty string)")

    return rv


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
                        throw.eject(ej, "Lists are not of the same size")
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

        def parsed := parse(lexer.getTokens(), null)
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
        def lexer := makeLexer(ej)
        def stream := makeStream(s)
        lexer.lex(stream)
        return parse(lexer.getTokens(), ej)

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

def testJSONDecodeNested(assert):
    def specimen := `{"first":{"second":{"third":42}}}`
    assert.equal(JSON.decode(specimen, null),
        ["first" => ["second" => ["third" => 42]]])

def testJSONDecodeDouble(assert):
    def specimen := `{"pi":3.14}`
    # Yeah, this test really is supposed to be this precise. Any imprecisions
    # here should be due to implementation error, AFAICT.
    assert.equal(JSON.decode(specimen, null), ["pi" => 3.14])

def testJSONDecodeDoubleTooPrecise(assert):
    def specimen := `{"digits":0.7937000378463977}`
    # Yeah, this test really is supposed to be this precise. Any imprecisions
    # here should be due to implementation error, AFAICT.
    assert.equal(JSON.decode(specimen, null), ["digits" => 0.7937000378463977])

def testJSONDecodeInvalid(assert):
    def specimens := [
        "",
        "{",
        "}",
        "asdf",
        "{asdf}",
    ]
    for s in specimens:
        assert.ejects(fn ej {def via (JSON.decode) _ exit ej := s})

def testJSONEncode(assert):
    def specimen := ["first" => 42, "second" => [5, 7]]
    assert.equal(JSON.encode(specimen, null),
                 "{\"first\":42,\"second\":[5,7]}")

unittest([
    testJSONDecode,
    testJSONDecodeSlash,
    testJSONDecodeNested,
    testJSONDecodeDouble,
    testJSONDecodeDoubleTooPrecise,
    testJSONDecodeInvalid,
    testJSONEncode,
])
