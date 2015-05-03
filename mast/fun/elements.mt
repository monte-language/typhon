def table :Str := "
h                                                  he
li be                               b  c  n  o  f  ne
na mg                               al si p  s  cl ar
k  ca sc ti v  cr mn fe co ni cu zn ga ge as se br kr
rb sr y  zr nb mo tc ru rh pd ag cd in sn sb te i  xe
cs ba    hf ta w  re os ir pt au hg ti pb bi po at rn
fr ra    rf db sg bh hs mt ds rg cn    fl    lv

      la ce pr nd pm sm eu gd tb dy ho er tm yb lu
      ac th pa u  np pu am cm bk cf es fm md no lr
"

var elements :Set[Str] := [].asSet()
for line in table.split("\n"):
    for element in line.split(" "):
        elements with= element.trim()
elements without= ""

# traceln(`Elements: $elements`)

def elementsOf(word :Str):
    "Return a list of lists of elements which concatenate to the given word."

    if (word.size() == 0):
        return []

    var partials := [[word, []]]
    var finished := []

    while (partials.size() != 0):
        def [[remainder, pieces]] + rest := partials
        # traceln(`Remainder $remainder and pieces $pieces`)
        partials := rest

        if (remainder.size() == 0):
            finished with= pieces
        else:
            for element in elements:
                switch (remainder):
                    match `$element@rest`:
                        partials with= [rest, pieces.with(element)]
                    match _:
                        pass

    return finished

def testElementsOfWhippersnapper(assert):
    assert.equal(elementsOf("whippersnapper"),
                 [["w", "h", "i", "p", "p", "er", "s", "na", "p", "p", "er"]])

def testElementsOfXenon(assert):
    assert.equal(elementsOf("xenon"),
                 [["xe", "no", "n"], ["xe", "n", "o", "n"]])

def testElementsOfZero(assert):
    assert.equal(elementsOf("zero"), [])

unittest([
    testElementsOfWhippersnapper,
    testElementsOfXenon,
    testElementsOfZero,
])

[=> elementsOf]
