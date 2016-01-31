import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "lib/tubes" =~ [
    => nullPump :DeepFrozen,
    => makePumpTube :DeepFrozen,
    => chain :DeepFrozen,
]
import "lib/enum" =~ [=> makeEnum :DeepFrozen]
import "lib/record" =~ [=> makeRecord :DeepFrozen]
exports (main)

def [ItemType :DeepFrozen,
     FILE :DeepFrozen,
] := makeEnum(["file"])

def [Item :DeepFrozen, makeItem :DeepFrozen
] := makeRecord("Item", [
    "type" => ItemType,
    "label" => Bytes,
    "data" => Any,
    "host" => Bytes,
    "port" => Int,
])

def gopherLine(selector :Bytes, item :Item) :Bytes as DeepFrozen:
    def label := item.getLabel()
    def host := item.getHost()
    def portBytes := b`${M.toString(item.getPort())}`
    return b`0$label$\x09$selector$\x09$host$\x09$portBytes`

def gopherLines(lines :List[Bytes]) :Bytes as DeepFrozen:
    return b`$\r$\n`.join(lines) + b`.$\r$\n`

def makeGopherPump(resource) as DeepFrozen:
    var buf :Bytes := b``

    return object gopherPump extends nullPump:
        to received(data :Bytes):
            buf += data
            if (buf =~ b`@query$\r$\n`):
                switch (query):
                    match b``:
                        def lines := [for selector => item in (resource)
                                      gopherLine(selector, item)]
                        return [gopherLines(lines), null]
                    match selector ? (resource.contains(selector)):
                        def item := resource[selector]
                        def bs := UTF8.encode(item.getData(), null)
                        return [b`$bs$\r$\n.$\r$\n`, null]
                    match _:
                        return [b`3$\r$\n`, null]
            return []

def tree := [
    b`selector` => makeItem(FILE, b`Derp label`, `Test file!`, b`localhost`,
                            70),
    b`another-selector` => makeItem(FILE, b`Herp label`, `Another test file!`,
                                    b`localhost`, 70),
]

def listener(fount, drain) as DeepFrozen:
    chain([fount, makePumpTube(makeGopherPump(tree)), drain])

def main(argv, => makeTCP4ServerEndpoint) :Int as DeepFrozen:
    def endpoint := makeTCP4ServerEndpoint(70)
    endpoint.listen(listener)
    return 0
