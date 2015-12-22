def [=> UTF8 :DeepFrozen] | _ := import.script("lib/codec/utf8", safeScope | [=> &&bench])

def astCodes :Map[Str, Int] := [
    "LiteralExpr" => 10,
    "NounExpr" => 11,
    "BindingExpr" => 12,
    "SeqExpr" => 13,
    "MethodCallExpr" => 14,
    "DefExpr" => 15,
    "EscapeExpr" => 16,
    "ObjectExpr" => 17,
    "Script" => 18,
    "Method" => 19,
    "Matcher" => 20,
    "AssignExpr" => 21,
    "FinallyExpr" => 22,
    "CatchExpr" => 23,
    "HideExpr" => 24,
    "IfExpr" => 25,
    "Meta" => 26,
    "FinalPattern" => 27,
    "IgnorePattern" => 28,
    "VarPattern" => 29,
    "ListPattern" => 30,
    "ViaPattern" => 31,
    "BindingPattern" => 32,
    "NamedParam" => 34]

def asciiShift(bs) :Bytes as DeepFrozen:
    var result := b``
    for c in bs:
        result with= ((c + 32) % 256)
    return result

def zze(val) as DeepFrozen:
    if (val < 0):
        return ((val * 2) ^ -1) | 1
    else:
        return val * 2


def dumpVarint(var value, write) as DeepFrozen:
    if (value == 0):
        write(asciiShift(b`$\x00`))
    else:
        var target := b``
        while (value > 0):
            def chunk := value & 0x7f
            value >>= 7
            if (value > 0):
                target with= (chunk | 0x80)
            else:
                target with= (chunk)
        write(asciiShift(target))


def dump(item, write) as DeepFrozen:
    if (item == null):
        write(asciiShift(b`$\x00`))
        return
    switch (item):
        match _ :Int:
            write(asciiShift(b`$\x06`))
            dumpVarint(zze(item), write)
        match _ :Str:
            write(asciiShift(b`$\x03`))
            def bs := UTF8.encode(item, throw)
            dumpVarint(bs.size(), write)
            write(bs)
        match _ :Double:
            write(asciiShift(b`$\x04`))
            write(asciiShift(item.toBytes()))
        match _ :Char:
            # Char holds a Str internally.
            write(asciiShift(b`$\x21$\x03`))
            def bs := UTF8.encode(_makeString.fromChars([item]), throw)
            dumpVarint(bs.size(), write)
            write(bs)
        match _ :List:
            write(asciiShift(b`$\x07`))
            dumpVarint(item.size(), write)
            for val in item:
                dump(val, write)
        match _:
            def [nodeMaker, _, arglist, ==([].asMap())] := escape ej {
                def [nodeMaker, _, arglist, ==([].asMap())] exit ej := item._uncall()
            } catch failure {
                throw(`$item had a misbehaving _uncall: ${item._uncall()}`)
            }
            def name := item.getNodeName()
            if (name == "MetaContextExpr"):
                write(asciiShift([astCodes["Meta"]]))
                dump("context", write)
            else if (name == "MetaStateExpr"):
                write(asciiShift([astCodes["Meta"]]))
                dump("getState", write)
            else if (name == "NamedArg"):
                write(asciiShift(b`$\x07`))
                dumpVarint(2, write)
                dump(item.getKey(), write)
                dump(item.getValue(), write)
            else if (name == "ObjectExpr"):
                write(asciiShift([astCodes[name]]))
                dump(item.getDocstring(), write)
                dump(item.getName(), write)
                dump([item.getAsExpr()] + item.getAuditors(), write)
                dump(item.getScript(), write)
            else:
                write(asciiShift([astCodes[name]]))
                def nodeArgs := arglist.slice(0, arglist.size() - 1)
                for a in nodeArgs:
                    dump(a, write)


[=> dump]
