imports
exports (json__quasiParser)

object valueHoleMarker as DeepFrozen:
    pass

object patternHoleMarker as DeepFrozen:
    pass


def makeStream(s) as DeepFrozen:
    var index :Int := 0
    return object stream:
        to next():
            def rv := s[index]
            index += 1
            return rv

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
                    tokens.push(digit.asInteger() - '0'.asInteger())

                match c:
                    throw(`Unknown character $c`)

        to nextString(stream):
            def buf := [].diverge()

            while (true):
                switch (stream.next()):
                    match =='"':
                        break
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
        traceln("Tokens", tokens)
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

    traceln("final stack", stack)
    return stack[0][0]


# def l := makeLexer()
# l.lex(makeStream("{ \"testing\": true, \"production\": false, \"arr\": [1, 2, 3, 4] }"))
# def lexed := l.getTokens()
# traceln(lexed)
# def parsed := parse(lexed)
# traceln(parsed)


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


# def parsing := json`{"nested": "structures"}`
# traceln(parsing.getValue())
# traceln(json`{"quasi": $parsing}`.getValue())

# def json`{"nested": @stuff}` := parsing
# traceln(stuff.getValue())
