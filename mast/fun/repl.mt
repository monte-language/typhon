import "lib/enum" =~ [=> makeEnum]
import "lib/streams" =~ [
    => flow :DeepFrozen,
    => Sink :DeepFrozen,
]
exports (runREPL)

# XXX these names are pretty lame
def [REPLState :DeepFrozen, PS1 :DeepFrozen, PS2 :DeepFrozen] := makeEnum(["PS1", "PS2"])

# XXX wheel reinvention
object comp as DeepFrozen {}
object abort as DeepFrozen {}

def runREPL(makeParser, reducer, ps1 :Str, ps2 :Str, source, sink) as DeepFrozen:
    sink(ps1)

    var replState :REPLState := PS1
    var parser := makeParser()

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
                if (replState == PS1 && chars.size() == 0):
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
                            sink(`Result: $reduced$\n`)
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
