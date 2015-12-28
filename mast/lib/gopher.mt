imports
exports (main)

def unittest(_) {null}

def [=> nullPump :DeepFrozen,
     => makePumpTube :DeepFrozen,
     => chain :DeepFrozen,
] | _ := import("lib/tubes", [=> unittest])

def gopherLine(name :Bytes, selector :Bytes, host :Bytes, port :Int) :Bytes as DeepFrozen:
    def portBytes := b`${M.toString(port)}`
    return b`0$name$\x09$selector$\x09$host$\x09$portBytes`

def gopherLines(lines :List[Bytes]) :Bytes as DeepFrozen:
    return b`$\r$\n`.join(lines) + b`.$\r$\n`

def makeGopherPump(resource) as DeepFrozen:
    var buf :Bytes := b``

    return object gopherPump extends nullPump:
        to received(data :Bytes):
            buf += data
            if (buf =~ b`@query$\r$\n`):
                def lines := [for [name, selector, host, port]
                              in (resource.search(query))
                              gopherLine(name, selector, host, port)]
                return [gopherLines(lines), null]
            return []

object tree:
    to search(query :Bytes):
        return [
            [b`This is '$\xc3$\xa9' title`, b`selector`, b`localhost`, 70],
            [b`Next one`, b`next-selector`, b`localhost`, 70],
        ]

def listener(fount, drain) as DeepFrozen:
    chain([fount, makePumpTube(makeGopherPump(tree)), drain])

def main(=> makeTCP4ServerEndpoint) :Int as DeepFrozen:
    def endpoint := makeTCP4ServerEndpoint(70)
    endpoint.listen(listener)
    return 0
