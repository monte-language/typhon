def [=> UTF8] | _ := import("lib/codec/utf8",
                            [=> Bool, => Bytes, => Char, => Int, => List,
                             => Str,
                             => b__quasiParser,
                             => bench, => __accumulateList,
                             => __quasiMatcher, => __mapExtract,
                             => __iterWhile, => __comparer,
                             => __suchThat, => __switchFailed,
                             => __matchSame, => __validateFor,
                             => __makeVerbFacet, => __makeOrderedSpace])

def astCodes := [
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
    "BindingPattern" => 32]

def asciiShift(bs):
    def result := [].diverge()
    for c in bs:
        result.push((c + 32) % 256)
    return result.snapshot()

def zze(val):
    if (val < 0):
        return ((val * 2) ^ -1) | 1
    else:
        return val * 2


def dumpVarint(var value, write):
    if (value == 0):
        write(asciiShift([0]))
    else:
        def target := [].diverge()
        while (value > 0):
            def chunk := value & 0x7f
            value >>= 7
            if (value > 0):
                target.push(chunk | 0x80)
            else:
                target.push(chunk)
        write(asciiShift(target))


def dump(item, write):
    if (item == null):
        write(asciiShift([0]))
        return
    switch (item):
        match _ :Int:
            write(asciiShift([6]))
            dumpVarint(zze(item), write)
        match _ :Str:
            write(asciiShift([3]))
            def bs := UTF8.encode(item, throw)
            dumpVarint(bs.size(), write)
            write(bs)
        match _ :Double:
            write(asciiShift([4]))
            write(asciiShift(item.toBytes()))
        match _ :Char:
            write(asciiShift([33]))
            write(asciiShift([3]))
            def bs := UTF8.encode(__makeString.fromChars([item]), throw)
            dumpVarint(bs.size(), write)
            write(bs)
        match _ :List:
            write(asciiShift([7]))
            dumpVarint(item.size(), write)
            for val in item:
                dump(val, write)
        match _:
            escape ej:
                def [nodeMaker, _, arglist] exit ej := item._uncall()
            catch failure:
                throw(`$item had a misbehaving _uncall: ${item._uncall()}`)

            def name := item.getNodeName()
            if (name == "MetaContextExpr"):
                write(asciiShift([astCodes["Meta"]]))
                dump("context", write)
            else if (name == "MetaStateExpr"):
                write(asciiShift([astCodes["Meta"]]))
                dump("getState", write)
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
