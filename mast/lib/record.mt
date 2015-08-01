def capitalize(s :Str) :Str:
    if (s.size() > 0):
        return s.slice(0, 1).toUpperCase() + s.slice(1)
    return s

# XXX should be Map[Str, Guard]
def makeRecord(name :Str, fields :Map[Str, Any]):
    def fieldNames :List[Str] := fields.getKeys()
    def capitalizedNames :List[Str] := [for fieldName in (fieldNames)
                                        capitalize(fieldName)]

    interface Record guards RecordStamp:
        pass

    object recordMaker:
        match [=="run", elements ? (elements.size() == fields.size())]:
            object record as RecordStamp:
                "A record."

                to _conformTo(guard):
                    if (guard == Map):
                        return elements
                    return record

                to _printOn(out):
                    def parts := [for i => fieldName in (fieldNames)
                                  `$fieldName => ${M.toQuote(elements[i])}`]
                    out.print(`$name(${", ".join(parts)})`)

                # match [`get$slug` ? (def i := capitalizedNames.indexOf(slug) != -1),
                #        []]:
                #     elements[i]

                # match [`with$slug` ? (def i := capitalizedNames.indexOf(slug) != -1),
                #        [newValue :fields[fieldNames[i]]]]:
                #     def newElements := elements.with(i, newValue)
                #     recordMaker(newElements)

    return [Record, recordMaker]

def testRecord(assert):
    def [Test, makeTest] := makeRecord("Test",
                                       ["first" => Int, "second" => Char])
    # Yeah, I'm aware that this is a crime against ejectors. I don't care.
    # They had it coming. ~ C.
    assert.doesNotEject(fn ej {
        def test :Test exit ej := makeTest(42, 'm')
        assert.equal(M.toString(test), "Test(first => 42, second => 'm')")
        # def mutated :Test exit ej := test.withFirst(7)
        # assert.equal(mutated.getFirst(), 7)
        # assert.equal(mutated.getSecond(), 'm')
    })

unittest([testRecord])

[=> makeRecord]
