exports (make)

def makeGreeter(init :Str) as DeepFrozen:
    var greeting :Str := init

    def noNamedArgs := [].asMap()

    return object Hello:
        to setGreeting(s :Str):
            greeting := s

        to _unCall():
            return [makeGreeter, "run", [greeting], noNamedArgs]

def make() as DeepFrozen:
    return makeGreeter("Hello World")
