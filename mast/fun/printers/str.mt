exports (stringPrinter)

object stringPrinter as DeepFrozen:
    "Basic printers to strings."

    to collectStr():
        "Print to a single string."

        return def printObjectToString(obj):
            def rv := [].diverge(Str)
            def out.print(s :Str) { rv.push(s) }
            obj._printOn(out)
            return "".join(rv)

    to trailingOff(cutoff :Int):
        "Print to a single string, but halt printing after `cutoff` characters."

        return def printObjectToString(obj):
            var length :Int := 0
            def rv := [].diverge(Str)
            escape ej:
                def out.print(s :Str):
                    length += s.size()
                    rv.push(s)
                    if (length >= cutoff) { ej() }
                obj._printOn(out)
            return "".join(rv).slice(0, cutoff)
