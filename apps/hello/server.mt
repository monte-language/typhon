exports (make)

def make(ctx :DeepFrozen) as DeepFrozen:
    def makeGreeter(init :Str) as DeepFrozen:
        def &greeting := ctx.slot(init, "guard" => Str)

        def noNamedArgs := [].asMap()

        return object hello:
            to _printOn(out):
                out.print(`<hello greeting: $greeting>`)

            to setGreeting(s :Str):
                greeting := s

            to _unCall():
                return [makeGreeter, "run", [greeting], noNamedArgs]
    return makeGreeter("Hello World")
