def capitalize(s :Str) :Str:
    if (s.size() > 0):
        return s.slice(0, 1).toUpperCase() + s.slice(1)
    return s

# XXX should be Map[Str, Guard]
def makeRecord(name :Str, fields :Map[Str, Any]):
    def fieldNames :List[Str] := fields.getKeys()
    def fieldGuards :List := fields.getValues()
    def capitalizedNames :List[Str] := [for fieldName in (fieldNames)
                                        capitalize(fieldName)]
    def checkSlug := capitalizedNames.indexOf

    def checkElements(elts, ej):
        if (elts.size() != fieldGuards.size()):
            throw.eject(ej, "Wrong number of elements")

        return [for i => elt in (elts) fieldGuards[i].coerce(elt, ej)]

    interface Record guards RecordStamp:
        pass

    object recordMaker:
        match [=="run", via (checkElements) elements, _]:
            object record as RecordStamp:
                "A record."

                to _printOn(out):
                    def parts := [for i => fieldName in (fieldNames)
                                  `$fieldName => ${M.toQuote(elements[i])}`]
                    out.print(`$name(${", ".join(parts)})`)

                to asMap():
                    return [for i => element in (elements)
                            fieldNames[i] => element]

                match [`get@slug` ? ((def i := checkSlug(slug)) != -1),
                       [], _]:
                    elements[i]

                match [`with@slug` ? ((def i := checkSlug(slug)) != -1),
                       [newValue :fields[fieldNames[i]]], _]:
                    def newElements := elements.with(i, newValue)
                    M.call(recordMaker, "run", newElements, [].asMap())

    return [Record, recordMaker]

# For testing purposes only.
def [Test, makeTest] := makeRecord("Test", ["first" => Int, "second" => Char])

def testRecordMutation(assert):
    # Yeah, I'm aware that this is a crime against ejectors. I don't care.
    # They had it coming. ~ C.
    assert.doesNotEject(fn ej {
        def test :Test exit ej := makeTest(42, 'm')
        assert.equal(M.toString(test), "Test(first => 42, second => 'm')")
        assert.equal(test.getFirst(), 42)
        assert.equal(test.getSecond(), 'm')
        def mutated :Test exit ej := test.withFirst(7)
        assert.equal(mutated.getFirst(), 7)
        assert.equal(mutated.getSecond(), 'm')
    })

def testRecordCreationGuard(assert):
    # The guards should kick in during creation.
    assert.throws(fn {def test := makeTest(42.0, 'm')})
    assert.throws(fn {def test := makeTest(42, "m")})

def testRecordMutationGuard(assert):
    # The guard should also kick in when mutated.
    assert.throws(fn {
        def test := makeTest(42, 'm')
        # *This* is what we're testing.
        def mutated := test.withFirst("invalid")
    })

def testRecordAsMap(assert):
    def test := makeTest(42, 'm')
    assert.equal(test.asMap(), ["first" => 42, "second" => 'm'])

unittest([
    testRecordMutation,
    testRecordCreationGuard,
    testRecordMutationGuard,
    testRecordAsMap,
])

[=> makeRecord]
