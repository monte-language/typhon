def [=> makeEnum] | _ := import.script("lib/enum")

# XXX these names are pretty lame
def [REPLState, PS1, PS2] := makeEnum(["PS1", "PS2"])

def makeREPLTube(makeParser, reducer, ps1 :Str, ps2 :Str, drain):
    var replState : REPLState := PS1
    var parser := null

    return object REPLTube:
        to flowingFrom(upstream):
            REPLTube.reset()
            REPLTube.prompt()

        to receive(s):
            def `@chars$\n` := s
            # If they just thoughtlessly hit Enter, then don't bother.
            if (chars.size() == 0):
                REPLTube.prompt()
                return
            parser.feedMany(chars)
            if (parser.failed()):
                # The parser cannot continue.
                drain.receive(`Parse error: ${parser.getFailure()}$\n`)
                REPLTube.reset()
            else if (parser.finished()):
                # The parser can stop cleanly.
                switch (parser.results()):
                    match [result] + _:
                        def reduced := reducer(result)
                        drain.receive(`Result: $reduced$\n`)
                    match _:
                        drain.receive(`No result?$\n`)
                REPLTube.reset()
            else:
                # Partial parse.
                replState := PS2
            REPLTube.prompt()

        to reset():
            replState := PS1
            parser := makeParser()

        to prompt():
            switch (replState):
                match ==PS1:
                    drain.receive(ps1)
                match ==PS2:
                    drain.receive(ps2)

[=> makeREPLTube]
