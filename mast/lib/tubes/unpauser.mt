def makeUnpauser(thunk):
    var called :Bool := false
    return object unpauser:
        to unpause():
            if (!called):
                called := true
                thunk()

def testUnpauser(assert):
    var cell := 5
    def thunk():
        cell := 42

    def unpauser := makeUnpauser(thunk)
    unpauser.unpause()
    assert.equal(cell, 42)

    cell := 31
    unpauser.unpause()
    assert.equal(cell, 31)

unittest([testUnpauser])


[=> makeUnpauser]
