import "lib/enum" =~ [=> makeEnum]
import "lib/streams" =~ [=> flow, => Sink]
exports (runREPL)

def [REPLState :DeepFrozen, PS1 :DeepFrozen, PS2 :DeepFrozen] := makeEnum(["PS1", "PS2"])

def runREPL(makeParser, reducer, ps1 :Str, ps2 :Str, source, sink) as DeepFrozen:
    # Show the initial prompt.
    sink<-(ps1)

    var replState :REPLState := PS1
    var parser := makeParser()

    # The serial number of the next promise/eventual value we see.
    var promiseCounter :Int := 0

    def reset():
        replState := PS1
        parser := makeParser()

    def prompt():
        return switch (replState):
            match ==PS1:
                sink(ps1)
            match ==PS2:
                sink(ps2)

    object REPLSink extends sink as Sink:
        to run(s :Str, => FAIL):
            escape ej:
                def `@chars$\n` exit ej := s
                # If they just thoughtlessly hit Enter, then don't bother.
                if (replState == PS1 && chars.isEmpty()):
                    return prompt()

                parser.feedMany(chars)
                if (parser.failed()):
                    # The parser cannot continue.
                    sink(`Parse error: ${parser.getFailure()}$\n`)
                    reset()
                else if (parser.finished()):
                    # The parser can stop cleanly.
                    switch (parser.results()):
                        match [result] + _:
                            def reduced := reducer(result)
                            if (Ref.isResolved(reduced)):
                                sink(`Result: $reduced$\n`)
                            else:
                                def pc := promiseCounter += 1
                                sink(`Promise $pc: $reduced$\n`)
                                when (reduced) ->
                                    sink(`Resolved $pc: $reduced$\n`)
                                catch problem:
                                    sink(`Problem $pc: $problem$\n`)
                        match _:
                            sink(`No result?$\n`)
                    reset()
                else:
                    # Partial parse.
                    replState := PS2
                return prompt()
            catch problem:
                throw.eject(FAIL, problem)

    return flow(source, REPLSink)
